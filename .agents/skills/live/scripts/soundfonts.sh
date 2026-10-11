#!/bin/bash
# /live: VoiceMode's tool-call sounds (soundfonts) off for a live session, and back afterwards.
#
#   soundfonts.sh off      set VOICEMODE_SOUNDFONTS_ENABLED=false in voicemode.env, remembering the old value
#   soundfonts.sh restore  put the remembered value back (does nothing if `off` changed nothing)
#   soundfonts.sh status   print the current value and whether a restore is pending
#
# VoiceMode's hook receiver re-reads voicemode.env on every hook call, so the change takes effect on
# the next tool call; no restart. If the value is already false, `off` changes nothing and `restore`
# leaves it false. The remembered value lives in a marker file; a marker left by a session that never
# restored (a crash) is kept, so the next `off` cannot overwrite the true original with "false".
# Overrides for tests: VOICEMODE_ENV_FILE, LIVE_TALKER_STATE_DIR.
set -euo pipefail

ENV_FILE="${VOICEMODE_ENV_FILE:-$HOME/.voicemode/voicemode.env}"
STATE_DIR="${LIVE_TALKER_STATE_DIR:-$HOME/.local/state/live-talker}"
MARKER="$STATE_DIR/soundfonts-restore"
KEY=VOICEMODE_SOUNDFONTS_ENABLED

current() {  # the effective value in the file (last uncommented line wins), or __unset__
  local v
  v=$(grep -E "^${KEY}=" "$ENV_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d "\"'" || true)
  echo "${v:-__unset__}"
}

set_value() {  # rewrite every uncommented KEY= line in place (keeps the file's mode and inode)
  local tmp
  tmp=$(mktemp "$STATE_DIR/voicemode.env.XXXXXX")
  sed "s/^${KEY}=.*/${KEY}=$1/" "$ENV_FILE" > "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

drop_line() {  # remove the KEY= line that `off` appended to a file that had none
  local tmp
  tmp=$(mktemp "$STATE_DIR/voicemode.env.XXXXXX")
  grep -v -E "^${KEY}=" "$ENV_FILE" > "$tmp" || true
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

is_false() { case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in false|0|no|off) return 0;; *) return 1;; esac; }

mkdir -p "$STATE_DIR"
case "${1:-}" in
  off)
    if [ -f "$MARKER" ]; then
      [ "$(current)" = false ] || set_value false
      echo "soundfonts: off (a restore to '$(cat "$MARKER")' was already pending from an earlier session; kept)"
      exit 0
    fi
    was=$(current)
    if is_false "$was"; then
      echo "soundfonts: already off ($KEY=$was in $ENV_FILE); nothing to restore afterwards"
      exit 0
    fi
    echo "$was" > "$MARKER"
    if [ "$was" = __unset__ ]; then
      printf '%s=false\n' "$KEY" >> "$ENV_FILE"
    else
      set_value false
    fi
    echo "soundfonts: off ($KEY was '$was', now false in $ENV_FILE)"
    ;;
  restore)
    if [ ! -f "$MARKER" ]; then
      echo "soundfonts: nothing to restore ($KEY=$(current))"
      exit 0
    fi
    was=$(cat "$MARKER")
    if [ "$was" = __unset__ ]; then
      drop_line
    else
      set_value "$was"
    fi
    rm -f "$MARKER"
    echo "soundfonts: restored ($KEY=$(current) in $ENV_FILE)"
    ;;
  status)
    echo "soundfonts: $KEY=$(current) in $ENV_FILE; restore pending: $([ -f "$MARKER" ] && cat "$MARKER" || echo no)"
    ;;
  *)
    echo "usage: $0 off|restore|status" >&2
    exit 2
    ;;
esac
