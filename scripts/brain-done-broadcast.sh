#!/usr/bin/env bash
# brain-done-broadcast.sh
# Todoist DONE 3줄 요약을 Discord brain-review + Telegram에 전송
# Usage: brain-done-broadcast.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_SCRIPT="$WORKSPACE/scripts/brain-todoist-done-summary.sh"

DISCORD_REVIEW_CHANNEL="${BRAIN_REVIEW_CHANNEL_ID:-1477462915509387314}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-62403941}"

if [[ ! -x "$SUMMARY_SCRIPT" ]]; then
  echo "ERROR: summary script not executable: $SUMMARY_SCRIPT" >&2
  exit 1
fi

SUMMARY="$($SUMMARY_SCRIPT --output markdown --date today 2>/dev/null || true)"
if [[ -z "$SUMMARY" ]]; then
  SUMMARY="### 🧾 오늘 DONE 3줄 요약\n- 완료 항목 없음\n- 다음 액션: TODO 상위 1개 착수\n- 리스크: 없음"
fi

DISCORD_MSG="[BRAIN-REVIEW] $(date '+%Y-%m-%d') DONE 요약\n\n$SUMMARY"
TELEGRAM_MSG="🧾 DONE 3줄 요약\n\n$(echo "$SUMMARY" | sed 's/^#* //g' | head -n 12)"

send_msg() {
  local channel="$1" target="$2" message="$3"
  if $DRY_RUN; then
    echo "[DRY-RUN][$channel:$target]"
    echo "$message" | head -n 20
    return 0
  fi
  openclaw message send --channel "$channel" --target "$target" --message "$message" --silent >/dev/null
}

send_msg discord "$DISCORD_REVIEW_CHANNEL" "$DISCORD_MSG" || true
send_msg telegram "$TELEGRAM_TARGET" "$TELEGRAM_MSG" || true

echo "HEARTBEAT_OK"
