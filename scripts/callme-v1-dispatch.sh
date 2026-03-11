#!/bin/bash
#
# Call-Me v1 Dispatch Script
# - L1/L2 알림 디스패치
# - dry-run 모드 지원
#
# Usage:
#   ./callme-v1-dispatch.sh --event event.json [--channel telegram|discord|both] [--dry-run]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER_JS="$SCRIPT_DIR/callme-v1-router.js"

# 기본값
DRY_RUN=false
CHANNEL="telegram"
EVENT_FILE=""

# CLI 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        --event)
            EVENT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Call-Me v1 Dispatch

Usage:
  $0 --event <event.json> [--channel telegram|discord|both] [--dry-run]

Options:
  --event FILE     이벤트 JSON 파일 경로
  --channel CH     전송 채널 (telegram|discord|both, 기본: telegram)
  --dry-run        실제 전송 없이 명령만 출력
  --help           이 도움말

Example:
  $0 --event alert.json --channel both
  echo '{"eventType":"test","project":"api","severity":"high","summary":"Test","details":"Details","retryCount":0,"needApprovalMinutes":0,"occurredAt":"2026-03-01T08:00:00Z"}' | jq . > /tmp/test.json
  $0 --event /tmp/test.json --dry-run
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# 검증
if [[ -z "$EVENT_FILE" ]]; then
    echo "Error: --event required" >&2
    exit 1
fi

if [[ ! -f "$EVENT_FILE" ]]; then
    echo "Error: Event file not found: $EVENT_FILE" >&2
    exit 1
fi

if [[ ! -f "$ROUTER_JS" ]]; then
    echo "Error: Router not found: $ROUTER_JS" >&2
    exit 1
fi

# 라우팅 정보 가져오기
ROUTE_JSON=$(node "$ROUTER_JS" "$(<"$EVENT_FILE")")
LEVEL=$(echo "$ROUTE_JSON" | jq -r '.level')
MESSAGE=$(echo "$ROUTE_JSON" | jq -r '.message')
TTS_MESSAGE=$(echo "$ROUTE_JSON" | jq -r '.ttsMessage // empty')

echo "========================================"
echo "Call-Me v1 Dispatch"
echo "========================================"
echo "Level: $LEVEL"
echo "Channel: $CHANNEL"
echo "Dry-run: $DRY_RUN"
echo "----------------------------------------"
echo "Message:"
echo "$MESSAGE"
echo "========================================"

# openclaw CLI 존재 확인
OPENCLAW_CLI=""
if command -v openclaw &>/dev/null; then
    OPENCLAW_CLI="openclaw"
elif [[ -x "$HOME/.local/bin/openclaw" ]]; then
    OPENCLAW_CLI="$HOME/.local/bin/openclaw"
fi

# L1 디스패치
dispatch_l1() {
    local msg="$1"
    local target_channel="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would send to $target_channel:"
        echo "  Message: $msg"
        return 0
    fi
    
    if [[ -n "$OPENCLAW_CLI" ]]; then
        echo "[DISPATCH] Sending to $target_channel via openclaw..."
        case "$target_channel" in
            telegram)
                $OPENCLAW_CLI message send --channel telegram -t "62403941" -m "$msg" 2>&1 || echo "  Warning: Failed to send to Telegram"
                ;;
            discord)
                $OPENCLAW_CLI message send --channel discord -m "$msg" 2>&1 || echo "  Warning: Failed to send to Discord"
                ;;
        esac
    else
        echo "[FALLBACK] openclaw CLI not found. Manual send command:"
        case "$target_channel" in
            telegram)
                echo "  curl -X POST \"https://api.telegram.org/bot<TOKEN>/sendMessage\" -d \"chat_id=<CHAT_ID>&text=$(echo "$msg" | jq -Rs .)\""
                ;;
            discord)
                echo "  curl -X POST \"<WEBHOOK_URL>\" -H \"Content-Type: application/json\" -d \"{\\\"content\\\":$(echo "$msg" | jq -Rs .)\"}\""
                ;;
        esac
    fi
}

# L2 디스패치 (Telegram + TTS)
dispatch_l2() {
    local msg="$1"
    local tts_msg="$2"
    
    # 1차: 텍스트 메시지
    dispatch_l1 "$msg" "telegram"
    
    # 2차: TTS 재알림
    if [[ -n "$tts_msg" ]]; then
        echo "----------------------------------------"
        echo "[L2] TTS Re-alert"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would speak: $tts_msg"
            return 0
        fi
        
        # TTS는 에이전트 세션에서 직접 처리 (CLI tts 미지원)
        echo "[INFO] TTS는 에이전트 세션에서 처리 필요"
        echo "  TTS Message: $tts_msg"
        echo "  참고: openclaw CLI에는 tts 명령 없음 → 에이전트 tts 툴 사용"
    fi
}

# 메인 디스패치 로직
case "$LEVEL" in
    L1)
        if [[ "$CHANNEL" == "both" ]]; then
            dispatch_l1 "$MESSAGE" "telegram"
            dispatch_l1 "$MESSAGE" "discord"
        else
            dispatch_l1 "$MESSAGE" "$CHANNEL"
        fi
        ;;
    L2)
        # L2는 항상 Telegram + TTS
        dispatch_l2 "$MESSAGE" "$TTS_MESSAGE"
        ;;
    *)
        echo "Error: Unknown level: $LEVEL" >&2
        exit 1
        ;;
esac

echo "========================================"
echo "Dispatch complete ✅"
echo "========================================"
