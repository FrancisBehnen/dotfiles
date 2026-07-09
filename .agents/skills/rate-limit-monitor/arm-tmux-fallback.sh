#!/usr/bin/env bash
# Arm a tmux-based fallback wakeup for the current Claude Code pane.
# If the session gets hard-capped (monthly spend limit, API refusing calls),
# ScheduleWakeup never fires — but a message typed into the pane always wakes
# the REPL. This script detaches a sleeper that does exactly that.
#
# Usage: arm-tmux-fallback.sh <delay_seconds> [message]
#        arm-tmux-fallback.sh cancel
set -euo pipefail

PIDFILE="${TMPDIR:-/tmp}/claude-rlm-tmux-fallback.pid"

if [ "${1:-}" = "cancel" ]; then
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "fallback cancelled"
  else
    echo "no fallback armed"
  fi
  exit 0
fi

DELAY="${1:?usage: arm-tmux-fallback.sh <delay_seconds> [message] | cancel}"
MSG="${2:-Wakey wakey - rate limit window should have reset. Re-run /rate-limit-monitor and resume the loop.}"

if [ -z "${TMUX_PANE:-}" ]; then
  echo "not inside tmux - cannot arm fallback (ScheduleWakeup is the only wake path)" >&2
  exit 0
fi
PANE="$TMUX_PANE"

# Replace any previously armed fallback so only one sleeper exists
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

nohup bash -c "sleep $DELAY; tmux send-keys -t '$PANE' -l \"\$0\"; sleep 1; tmux send-keys -t '$PANE' Enter" "$MSG" >/dev/null 2>&1 &
echo $! > "$PIDFILE"
echo "fallback armed: wake message will be typed into pane $PANE in ${DELAY}s (pid $(cat "$PIDFILE"))"
