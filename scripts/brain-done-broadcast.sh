#!/usr/bin/env bash
# brain-done-broadcast.sh
# Todoist DONE 요약을 "개별 메시지"로 Discord brain-review + Telegram에 전송
# Usage: brain-done-broadcast.sh [--dry-run]

set -euo pipefail

# Load message guard
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
set -u

SUMMARY_SCRIPT="$WORKSPACE/scripts/brain-todoist-done-summary.sh"

DISCORD_REVIEW_CHANNEL="${BRAIN_REVIEW_CHANNEL_ID:-${DISCORD_DECISION_LOG:-1477310567906672750}}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"

if [[ ! -x "$SUMMARY_SCRIPT" ]]; then
  echo "ERROR: summary script not executable: $SUMMARY_SCRIPT" >&2
  exit 1
fi

SUMMARY="$($SUMMARY_SCRIPT --output markdown --date today 2>/dev/null || true)"
if [[ -z "$SUMMARY" ]]; then
  SUMMARY="### 🧾 오늘 DONE 3줄 요약
- 완료 항목 없음
- 다음 액션: TODO 상위 1개 착수
- 리스크: 없음"
fi

# markdown summary를 개별 메시지로 분리
# - 헤더/카운트 라인
# - 각 bullet 라인
# - 기타 보조 라인
build_message_parts() {
  local summary="$1"
  local -n out_arr=$2

  out_arr=()

  # 첫 메시지: 날짜 + 카운트(또는 헤더)
  local title_line="$(echo "$summary" | sed -n '1,3p' | sed '/^$/d' | head -n 2 | paste -sd ' | ' -)"
  if [[ -z "$title_line" ]]; then
    title_line="🧾 DONE 요약 $(date '+%Y-%m-%d')"
  fi
  local first_msg
  printf -v first_msg "🧾 DONE 요약 %s\n%s" "$(date '+%Y-%m-%d')" "$title_line"
  out_arr+=("$first_msg")

  # bullet/숫자 라인만 추출해서 개별 메시지화
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # markdown 장식 제거(너무 과한 포맷 방지)
    local clean
    clean="$(echo "$line" | sed -E 's/^[-*][[:space:]]+//; s/^#*[[:space:]]+//; s/^_[[:space:]]*//; s/[[:space:]]*_$//')"
    [[ -z "$clean" ]] && continue

    out_arr+=("• ${clean}")
  done < <(echo "$summary" | grep -E '^[-*] ' || true)

  # bullet이 없으면 summary 본문 앞 3줄을 fallback으로 개별화
  if [[ ${#out_arr[@]} -le 1 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local clean
      clean="$(echo "$line" | sed -E 's/^#*[[:space:]]+//; s/^_[[:space:]]*//; s/[[:space:]]*_$//')"
      [[ -z "$clean" ]] && continue
      out_arr+=("• ${clean}")
    done < <(echo "$summary" | sed '/^$/d' | head -n 6 | tail -n +2)
  fi
}

send_msg() {
  local channel="$1" target="$2" message="$3"

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel "$channel" --target "$target"; then
    echo "[ERROR] message validation failed: channel=$channel, target=$target" >&2
    return 1
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN][$channel:$target] $message"
    return 0
  fi
  openclaw message send --channel "$channel" --target "$target" --message "$message" --silent >/dev/null
}

PARTS=()
build_message_parts "$SUMMARY" PARTS

# Discord 개별 전송
for msg in "${PARTS[@]}"; do
  send_msg discord "$DISCORD_REVIEW_CHANNEL" "$msg" || true
  sleep 0.2
done

# Telegram 개별 전송
for msg in "${PARTS[@]}"; do
  send_msg telegram "$TELEGRAM_TARGET" "$msg" || true
  sleep 0.2
done

echo "HEARTBEAT_OK"
