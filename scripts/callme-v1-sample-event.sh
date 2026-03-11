#!/usr/bin/env bash
# callme-v1-sample-event.sh - L1/L2 샘플 이벤트 JSON 생성
# Usage:
#   ./callme-v1-sample-event.sh l1|l2 [--output DIR] [--path-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"

LEVEL=""
OUTPUT_DIR="${WORKSPACE}/events/callme"
PATH_ONLY=false

usage() {
  cat <<EOF
Usage: $0 l1|l2 [--output DIR] [--path-only]

Options:
  --output DIR   출력 디렉토리 (기본: ${WORKSPACE}/events/callme)
  --path-only    파일 경로만 출력(스크립트 연동용)
EOF
}

# 인자 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    l1|L1|l2|L2)
      LEVEL="$1"
      shift
      ;;
    --output)
      [ $# -lt 2 ] && { echo "Error: --output requires DIR" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --path-only)
      PATH_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$LEVEL" ]; then
  echo "Error: level required (l1|l2)" >&2
  usage >&2
  exit 1
fi

case "$LEVEL" in
  l1|L1)
    LEVEL="L1"
    DESCRIPTION="즉시 알림 - 시스템 장애, 긴급 보안 이슈"
    ;;
  l2|L2)
    LEVEL="L2"
    DESCRIPTION="일반 알림 - 중요 이벤트, 예약 리마인더"
    ;;
esac

mkdir -p "$OUTPUT_DIR"

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DATESTAMP="$(date '+%Y%m%d')"
TIMESTAMP_SHORT="$(date '+%H%M%S')"

case "$LEVEL" in
  L1)
    EVENT_DATA=$(cat <<'EOF'
{
  "level": "L1",
  "type": "system_critical",
  "source": "health-monitor",
  "timestamp": "TIMESTAMP",
  "subject": "[긴급] 서버 응답 시간 초과",
  "message": "API 서버 응답 시간이 30초를 초과했습니다. 즉시 확인이 필요합니다.",
  "details": {
    "server": "api-prod-01",
    "response_time_ms": 32450,
    "threshold_ms": 30000,
    "consecutive_failures": 3
  },
  "actions": [
    "SSH 접속 확인: ssh admin@api-prod-01",
    "로그 확인: journalctl -u api -f",
    "서비스 재시작: systemctl restart api"
  ],
  "channels": ["telegram", "tts"],
  "priority": "critical",
  "ttl_seconds": 3600
}
EOF
)
    ;;
  L2)
    EVENT_DATA=$(cat <<'EOF'
{
  "level": "L2",
  "type": "scheduled_reminder",
  "source": "calendar-sync",
  "timestamp": "TIMESTAMP",
  "subject": "[알림] 30분 후 회의 시작",
  "message": "주간 팀 미팅이 30분 후 시작됩니다. 준비해주세요.",
  "details": {
    "meeting_title": "주간 팀 미팅",
    "start_time": "09:00",
    "location": "회의실 A",
    "attendees": 5
  },
  "actions": [
    "회의 자료 확인",
    "발표 준비"
  ],
  "channels": ["telegram"],
  "priority": "normal",
  "ttl_seconds": 7200
}
EOF
)
    ;;
esac

EVENT_DATA="$(echo "$EVENT_DATA" | sed "s/TIMESTAMP/${TIMESTAMP}/g")"
FILENAME="${LEVEL,,}_${DATESTAMP}_${TIMESTAMP_SHORT}.json"
FILEPATH="${OUTPUT_DIR}/${FILENAME}"
printf '%s\n' "$EVENT_DATA" > "$FILEPATH"

if command -v jq >/dev/null 2>&1; then
  jq . "$FILEPATH" >/dev/null
fi

if [ "$PATH_ONLY" = true ]; then
  printf '%s\n' "$FILEPATH"
  exit 0
fi

echo "=== 샘플 이벤트 생성 완료 ==="
echo "레벨: $LEVEL"
echo "설명: $DESCRIPTION"
echo "파일: $FILEPATH"
echo "검증: valid"
echo ""
echo "--- 이벤트 내용 ---"
cat "$FILEPATH"
echo ""
echo "--- 사용법 ---"
echo "# 이벤트 발송 테스트:"
echo "openclaw message send --channel telegram --message \"\$(jq -r '.subject' $FILEPATH)\""
echo ""
if [ "$LEVEL" = "L1" ]; then
  echo "# TTS 테스트 (L1):"
  echo "openclaw tts --text \"\$(jq -r '.message' $FILEPATH)\""
fi
echo ""
echo "$FILEPATH"
