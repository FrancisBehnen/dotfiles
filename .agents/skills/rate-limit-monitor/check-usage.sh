#!/usr/bin/env bash
# Fetches current rate limit data from the Anthropic OAuth usage API.
# Output: JSON with utilization percentages and reset times.
# Requires: jq, macOS Keychain with Claude Code credentials.
set -euo pipefail

_get_token() {
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"
    return
  fi
  local blob=""
  if command -v security >/dev/null 2>&1; then
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true
  fi
  if [ -z "$blob" ] && [ -f ~/.claude/.credentials.json ]; then
    blob=$(< ~/.claude/.credentials.json)
  fi
  if [ -z "$blob" ] && command -v secret-tool >/dev/null 2>&1; then
    blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null) || true
  fi
  [ -n "$blob" ] && jq -r '.claudeAiOauth.accessToken // empty' <<< "$blob" 2>/dev/null
}

TOKEN=$(_get_token)
if [ -z "$TOKEN" ]; then
  echo '{"error": "no_token", "message": "Could not retrieve OAuth token"}'
  exit 1
fi

RESP=$(curl -s --max-time 5 \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" \
  "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

if [ -z "$RESP" ] || ! echo "$RESP" | jq . >/dev/null 2>&1; then
  echo '{"error": "api_failed", "message": "API call failed or returned invalid JSON"}'
  exit 1
fi

NOW=$(date +%s)

RESET_5H=$(echo "$RESP" | jq -r '.five_hour.resets_at // empty')
RESET_7D=$(echo "$RESP" | jq -r '.seven_day.resets_at // empty')

RM5=""
if [ -n "$RESET_5H" ]; then
  RESET_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$(echo "$RESET_5H" | sed 's/\.[0-9]*+.*//; s/\.[0-9]*Z//')" +%s 2>/dev/null) || true
  [ -n "$RESET_EPOCH" ] && RM5=$(( (RESET_EPOCH - NOW) / 60 ))
fi

RM7=""
if [ -n "$RESET_7D" ]; then
  RESET_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$(echo "$RESET_7D" | sed 's/\.[0-9]*+.*//; s/\.[0-9]*Z//')" +%s 2>/dev/null) || true
  [ -n "$RESET_EPOCH" ] && RM7=$(( (RESET_EPOCH - NOW) / 60 ))
fi

jq --argjson rm5 "${RM5:-null}" --argjson rm7 "${RM7:-null}" '{
  five_hour: {
    utilization: (.five_hour.utilization // 0),
    resets_at: (.five_hour.resets_at // null),
    resets_in_minutes: $rm5
  },
  seven_day: {
    utilization: (.seven_day.utilization // 0),
    resets_at: (.seven_day.resets_at // null),
    resets_in_minutes: $rm7
  }
}' <<< "$RESP"
