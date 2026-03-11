#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="/root/.openclaw/workspace"
STATE_DIR="$ROOT/.state"
DATA_DIR="$ROOT/data"
set +u
source "$SCRIPT_DIR/env-loader.sh" 2>/dev/null || true
set -u

TELEGRAM_TARGET_DEFAULT="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"
DISCORD_TARGET_DEFAULT="${DISCORD_BRIEFING_LOG_CHANNEL_ID:-${DISCORD_BRIEFING_LOG:-1477462915509387314}}"

TELEGRAM_TARGET="$TELEGRAM_TARGET_DEFAULT"
DISCORD_TARGET="$DISCORD_TARGET_DEFAULT"
MESSAGE_FILE=""
MESSAGE_TEXT=""
SILENT="--silent"

usage() {
  cat <<EOF
Usage:
  $0 --message-file <path> [--telegram <id>] [--discord <id>] [--no-silent]
  $0 --message "text" [--telegram <id>] [--discord <id>] [--no-silent]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message-file)
      MESSAGE_FILE="$2"
      shift 2
      ;;
    --message)
      MESSAGE_TEXT="$2"
      shift 2
      ;;
    --telegram)
      TELEGRAM_TARGET="$2"
      shift 2
      ;;
    --discord)
      DISCORD_TARGET="$2"
      shift 2
      ;;
    --no-silent)
      SILENT=""
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "SEND_BRIEFING_ERROR: unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$MESSAGE_FILE" ]]; then
  [[ -f "$MESSAGE_FILE" ]] || { echo "SEND_BRIEFING_ERROR: file not found: $MESSAGE_FILE" >&2; exit 1; }
  MESSAGE_TEXT="$(cat "$MESSAGE_FILE")"
fi

if [[ -z "${MESSAGE_TEXT:-}" ]]; then
  echo "SEND_BRIEFING_ERROR: message is empty" >&2
  exit 1
fi

if [[ -z "$TELEGRAM_TARGET" || -z "$DISCORD_TARGET" ]]; then
  echo "SEND_BRIEFING_ERROR: missing target (telegram=$TELEGRAM_TARGET, discord=$DISCORD_TARGET)" >&2
  exit 1
fi

send_one() {
  local channel="$1"
  local target="$2"
  local msg="$3"

  if [[ -n "$SILENT" ]]; then
    openclaw message send --channel "$channel" --target "$target" --message "$msg" "$SILENT" >/dev/null
  else
    openclaw message send --channel "$channel" --target "$target" --message "$msg" >/dev/null
  fi
}

send_one telegram "$TELEGRAM_TARGET" "$MESSAGE_TEXT"
send_one discord "$DISCORD_TARGET" "$MESSAGE_TEXT"

mkdir -p "$STATE_DIR"

BRIEFING_MESSAGE_TEXT="$MESSAGE_TEXT" \
BRIEFING_TELEGRAM_TARGET="$TELEGRAM_TARGET" \
BRIEFING_DISCORD_TARGET="$DISCORD_TARGET" \
python3 - <<'PY'
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

root = Path('/root/.openclaw/workspace')
state_dir = root / '.state'
data_dir = root / 'data'
runs_path = state_dir / 'morning-briefing-runs.jsonl'

kst = timezone(timedelta(hours=9))
now = datetime.now(kst)
ts_kst = now.isoformat(timespec='seconds')
date_kst = now.strftime('%Y-%m-%d')
message_text = os.environ.get('BRIEFING_MESSAGE_TEXT', '')

record = {
    'ts_kst': ts_kst,
    'date_kst': date_kst,
    'status': 'success',
    'telegram_target': os.environ.get('BRIEFING_TELEGRAM_TARGET'),
    'discord_target': os.environ.get('BRIEFING_DISCORD_TARGET'),
    'message_chars': len(message_text),
}

with runs_path.open('a', encoding='utf-8') as f:
    f.write(json.dumps(record, ensure_ascii=False) + '\n')

context_path = data_dir / f'morning-context-{date_kst}.json'
if context_path.exists():
    try:
        payload = json.loads(context_path.read_text(encoding='utf-8'))
        payload['briefing_sent'] = True
        payload['briefing_sent_at'] = ts_kst
        context_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    except Exception:
        pass
PY

echo "SEND_BRIEFING_OK"
