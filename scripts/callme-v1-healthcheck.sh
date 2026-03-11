#!/usr/bin/env bash
# callme-v1-healthcheck.sh - Call-Me v1 의존성 및 설정 점검
# Usage: ./callme-v1-healthcheck.sh [--json]

set -euo pipefail

JSON_MODE=false
[ "${1:-}" = "--json" ] && JSON_MODE=true

declare -a PASS_ITEMS=()
declare -a FAIL_ITEMS=()
declare -a WARN_ITEMS=()

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    PASS_ITEMS+=("$1 명령어 존재")
  else
    FAIL_ITEMS+=("$1 명령어 없음")
  fi
}

check_openclaw_cli() {
  if command -v openclaw >/dev/null 2>&1; then
    PASS_ITEMS+=("openclaw CLI 존재")
    if openclaw --help >/dev/null 2>&1; then
      PASS_ITEMS+=("openclaw CLI 실행 가능")
    else
      FAIL_ITEMS+=("openclaw CLI 실행 실패")
    fi
  else
    FAIL_ITEMS+=("openclaw CLI 없음")
  fi
}

check_subcommands() {
  if openclaw message --help >/dev/null 2>&1; then
    PASS_ITEMS+=("message 명령 사용 가능")
  else
    FAIL_ITEMS+=("message 명령 사용 불가")
  fi

  if openclaw tts --help >/dev/null 2>&1; then
    PASS_ITEMS+=("tts 명령 사용 가능")
  else
    WARN_ITEMS+=("tts 명령 확인 불가")
  fi
}

check_channel_status() {
  local status
  if ! status="$(openclaw channels status --probe 2>/dev/null || true)"; then
    WARN_ITEMS+=("채널 상태 조회 실패")
    return
  fi

  if echo "$status" | grep -Eqi 'Telegram .*works|Telegram .*running'; then
    PASS_ITEMS+=("Telegram 연결 정상")
  else
    FAIL_ITEMS+=("Telegram 연결 확인 필요")
  fi

  if echo "$status" | grep -Eqi 'Discord .*works|Discord .*running'; then
    PASS_ITEMS+=("Discord 연결 정상")
  else
    WARN_ITEMS+=("Discord 연결 확인 필요(선택)")
  fi
}

main() {
  echo "=== Call-Me v1 Healthcheck ==="
  echo "시간: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo ""

  check_cmd jq
  check_cmd curl
  check_openclaw_cli
  check_subcommands
  check_channel_status

  echo "--- 통과 (${#PASS_ITEMS[@]}) ---"
  for item in "${PASS_ITEMS[@]}"; do
    echo "  ✓ $item"
  done

  if [ ${#WARN_ITEMS[@]} -gt 0 ]; then
    echo ""
    echo "--- 경고 (${#WARN_ITEMS[@]}) ---"
    for item in "${WARN_ITEMS[@]}"; do
      echo "  ⚠ $item"
    done
  fi

  if [ ${#FAIL_ITEMS[@]} -gt 0 ]; then
    echo ""
    echo "--- 실패 (${#FAIL_ITEMS[@]}) ---"
    for item in "${FAIL_ITEMS[@]}"; do
      echo "  ✗ $item"
    done
  fi

  echo ""
  if [ ${#FAIL_ITEMS[@]} -gt 0 ]; then
    echo "결과: FAIL (차단 항목 ${#FAIL_ITEMS[@]}개)"
    if [ "$JSON_MODE" = true ]; then
      printf '{"status":"fail","pass":%d,"warn":%d,"fail":%d}\n' \
        "${#PASS_ITEMS[@]}" "${#WARN_ITEMS[@]}" "${#FAIL_ITEMS[@]}"
    fi
    exit 1
  fi

  echo "결과: PASS"
  if [ "$JSON_MODE" = true ]; then
    printf '{"status":"pass","pass":%d,"warn":%d,"fail":0}\n' \
      "${#PASS_ITEMS[@]}" "${#WARN_ITEMS[@]}"
  fi
}

main
