#!/bin/bash
# incident-router.sh - 인시던트 라우팅 및 4줄 리포트 생성 + Telegram/Discord 발송
# 입력: JSON (project, severity, title, cause, action, verify, prevent)
# 출력: 채널 제안 + 4줄 리포트 + Telegram/Discord 발송 (L2/L3)

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 기본 설정
PROJECT_CHANNELS=${PROJECT_CHANNELS:-"general"}
ALERTS_CHANNEL=${ALERTS_CHANNEL:-"alerts"}
TELEGRAM_SUMMARY=${TELEGRAM_SUMMARY:-"true"}
INCIDENT_DB_ENABLED=${INCIDENT_DB_ENABLED:-"true"}

# Telegram 설정
TELEGRAM_TARGET=${INCIDENT_TELEGRAM_TARGET:-}

# Discord Webhook 설정
DISCORD_WEBHOOK_ALERTS=${DISCORD_WEBHOOK_ALERTS:-}   # L2/L3용
DISCORD_WEBHOOK_PROJECT=${DISCORD_WEBHOOK_PROJECT:-} # L1용 (프로젝트별)

DRY_RUN="false"
ENABLE_TTS="false"
INCIDENT_ID=""
DISCORD_SEND_FAILED="false"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] '<JSON>'

OPTIONS:
  --dry-run    Telegram 발송 없이 리포트만 출력
  --tts        L3 인시던트에 대해 TTS 음성 생성 (openclaw tts)
  --list [N]   최근 N건 인시던트 조회 (기본: 20)

JSON 필드:
  project   - 프로젝트명 (예: jarvis, api, web)
  severity  - 심각도 (L1/L2/L3)
  title     - 인시던트 제목
  cause     - 원인
  action    - 조치 내용
  verify    - 검증 방법
  prevent   - 재발방지 대책

ENVIRONMENT:
  INCIDENT_TELEGRAM_TARGET  Telegram target/chatId (필수, L2/L3 발송용)
  DISCORD_WEBHOOK_ALERTS    Discord webhook URL for L2/L3 alerts
  DISCORD_WEBHOOK_PROJECT   Discord webhook URL for L1 (project-specific)
  INCIDENT_DB_ENABLED       DB 저장 여부 (기본: true)
  TELEGRAM_SUMMARY          Telegram 요약 전송 여부
  PROJECT_CHANNELS          L1용 프로젝트 채널
  ALERTS_CHANNEL            L2/L3용 알림 채널

예시:
  $0 '{"project":"jarvis","severity":"L2","title":"API 응답 지연","cause":"DB 커넥션 풀 고갈","action":"커넥션 풀 크기 증설","verify":"응답시간 < 200ms 확인","prevent":"풀 모니터링 알림 추가"}'

  $0 --dry-run '{"severity":"L3","title":"긴급 장애",...}'
  
  $0 --list 10
  
  INCIDENT_TELEGRAM_TARGET=62403941 $0 --tts '{"severity":"L3","title":"서버 다운",...}'
EOF
    exit 1
}

# JSON 파싱 (jq 필요, 없으면 간단한 파싱)
parse_json() {
    local json="$1"
    local field="$2"
    
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$field // empty"
    else
        # 간단한 grep 기반 파싱
        echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*: *"\([^"]*\)".*/\1/'
    fi
}

# DB 저장 (incident-db.sh 호출)
save_to_db() {
    local json="$1"
    
    # dry-run 모드면 저장 안 함
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} DB 저장 생략"
        return 0
    fi
    
    # DB 비활성화면 스킵
    if [[ "$INCIDENT_DB_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local db_script
    db_script="$(dirname "${BASH_SOURCE[0]}")/incident-db.sh"
    
    if [[ -x "$db_script" ]]; then
        INCIDENT_ID=$("$db_script" insert "$json" 2>&1) || {
            echo -e "${YELLOW}⚠ DB 저장 실패 (무시하고 계속)${NC}"
            INCIDENT_ID=""
            return 0
        }
        # ID만 추출 (마지막 숫자 라인)
        INCIDENT_ID=$(echo "$INCIDENT_ID" | grep -E '^[0-9]+$' | tail -1)
    else
        echo -e "${YELLOW}⚠ incident-db.sh 없음, DB 저장 생략${NC}"
    fi
}

# 4줄 요약 포맷 (Telegram 발송용)
format_summary() {
    local project="$1" severity="$2" title="$3"
    local cause="$4" action="$5" verify="$6" prevent="$7"
    
    local id_suffix=""
    if [[ -n "$INCIDENT_ID" ]]; then
        id_suffix=" [#$INCIDENT_ID]"
    fi
    
    cat <<EOF
🚨 [$severity] $project - $title$id_suffix

🔍 원인: $cause
🔧 조치: $action
✅ 검증: $verify
🛡️ 재발방지: $prevent
EOF
}

# Telegram 발송 (L2/L3용)
send_telegram() {
    local message="$1"
    local retry_count=0
    local max_retries=1
    
    # dry-run 모드면 발송 안 함
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Telegram 발송 생략"
        echo "--- MESSAGE ---"
        echo "$message"
        echo "---------------"
        return 0
    fi
    
    # 타겟 확인
    if [[ -z "$TELEGRAM_TARGET" ]]; then
        echo -e "${RED}ERROR${NC}: INCIDENT_TELEGRAM_TARGET 환경변수가 필요합니다"
        return 1
    fi
    
    # 발송 (최대 1회 재시도)
    while [[ $retry_count -le $max_retries ]]; do
        if openclaw message send --channel telegram --target "$TELEGRAM_TARGET" --message "$message" 2>&1; then
            echo -e "${GREEN}✓ Telegram 발송 성공${NC} (target: $TELEGRAM_TARGET)"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -le $max_retries ]]; then
            echo -e "${YELLOW}⚠ Telegram 발송 실패, 재시도 중... (${retry_count}/${max_retries})${NC}"
            sleep 2
        fi
    done
    
    echo -e "${RED}✗ Telegram 발송 실패${NC} (재시도 ${max_retries}회 후)"
    return 1
}

# TTS 생성 (L3용, 선택적)
send_tts() {
    local text="$1"
    
    # dry-run 모드면 생략
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} TTS 생성 생략"
        return 0
    fi
    
    # TTS 플래그 확인
    if [[ "$ENABLE_TTS" != "true" ]]; then
        return 0
    fi
    
    echo -e "${BLUE}🔊 TTS 생성 중...${NC}"
    if openclaw tts --text "$text" 2>&1; then
        echo -e "${GREEN}✓ TTS 생성 성공${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ TTS 생성 실패 (치명적 아님)${NC}"
        return 0
    fi
}

# 민감정보 마스킹 (webhook URL 등)
mask_sensitive() {
    local text="$1"
    # webhook URL 마스킹: https://discord.com/api/webhooks/ID/TOKEN
    echo "$text" | sed -E 's|https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|https://discord.com/api/webhooks/***/***|g'
}

# Discord Webhook 발송
send_discord() {
    local webhook_url="$1"
    local title="$2"
    local description="$3"
    local severity="$4"
    local project="$5"
    local retry_count=0
    local max_retries=1
    
    # dry-run 모드면 발송 안 함
    if [[ "$DRY_RUN" == "true" ]]; then
        local masked_url
        masked_url=$(mask_sensitive "$webhook_url")
        echo -e "${YELLOW}[DRY-RUN]${NC} Discord 발송 생략 (webhook: $masked_url)"
        return 0
    fi
    
    # webhook URL 확인
    if [[ -z "$webhook_url" ]]; then
        echo -e "${YELLOW}⚠ Discord webhook URL 없음, 발송 생략${NC}"
        return 0
    fi
    
    # 색상 결정 (Discord embed color: decimal)
    local color=16776960  # 기본: 노랑
    case "$severity" in
        L1) color=5763719 ;;   # 초록
        L2) color=16776960 ;;   # 노랑
        L3) color=15548997 ;;   # 빨강
    esac
    
    # Discord payload 생성 (jq 없으면 plain text fallback)
    local embed_json
    if command -v jq >/dev/null 2>&1; then
        embed_json=$(cat <<EOJ
{
  "embeds": [{
    "title": "🚨 [$severity] $project - $title",
    "description": $(echo "$description" | jq -Rs .),
    "color": $color,
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "footer": {"text": "incident-router.sh"}
  }]
}
EOJ
)
    else
        local plain
        plain="[$severity][$project] $title | $description"
        plain=$(echo "$plain" | sed 's/\\/\\\\/g; s/"/\\"/g')
        embed_json="{\"content\":\"$plain\"}"
        echo -e "${YELLOW}⚠ jq 없음: Discord plain text fallback 사용${NC}"
    fi

    # 발송 (최대 1회 재시도)
    while [[ $retry_count -le $max_retries ]]; do
        local response
        local http_code

        # 짧은 타임아웃으로 블로킹 최소화
        if command -v timeout >/dev/null 2>&1; then
            response=$(timeout 6s curl -s -w "\n%{http_code}" \
                --connect-timeout 3 \
                --max-time 5 \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$embed_json" \
                "$webhook_url" 2>&1) || true
        else
            response=$(curl -s -w "\n%{http_code}" \
                --connect-timeout 3 \
                --max-time 5 \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$embed_json" \
                "$webhook_url" 2>&1) || true
        fi

        if [[ -n "$response" ]]; then
            
            http_code=$(echo "$response" | tail -1)
            
            if [[ "$http_code" == "204" || "$http_code" == "200" ]]; then
                echo -e "${GREEN}✓ Discord 발송 성공${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠ Discord HTTP $http_code${NC}"
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -le $max_retries ]]; then
            echo -e "${YELLOW}⚠ Discord 발송 실패, 재시도 중... (${retry_count}/${max_retries})${NC}"
            sleep 2
        fi
    done
    
    # 실패 시 fallback 로그 + 비정상 종료 플래그
    DISCORD_SEND_FAILED="true"
    local masked_url
    masked_url=$(mask_sensitive "$webhook_url")
    
    # Fallback: 로그 파일에 저장
    local fallback_log
    fallback_log="$(dirname "${BASH_SOURCE[0]}")/../logs/discord-fallback.log"
    mkdir -p "$(dirname "$fallback_log")" 2>/dev/null || true
    
    {
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "FAILED Discord webhook to: $masked_url"
        echo "Severity: $severity | Project: $project"
        echo "Title: $title"
        echo "Description: $description"
        echo ""
    } >> "$fallback_log" 2>/dev/null || true
    
    echo -e "${RED}✗ Discord 발송 실패${NC} (fallback 로그 저장됨: $fallback_log)"
    return 1
}

# 4줄 리포트 생성
generate_report() {
    local project="$1" severity="$2" title="$3"
    local cause="$4" action="$5" verify="$6" prevent="$7"
    
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚨 INCIDENT REPORT [$severity] - $project
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📌 $title

🔍 원인: $cause
🔧 조치: $action
✅ 검증: $verify
🛡️ 재발방지: $prevent
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# 채널 라우팅 결정
determine_channels() {
    local project="$1" severity="$2"
    
    case "$severity" in
        L1)
            echo "PROJECT:${project}-channel"
            ;;
        L2|L3)
            local channels="ALERTS:${ALERTS_CHANNEL}"
            if [[ "$TELEGRAM_SUMMARY" == "true" ]]; then
                channels+="|TELEGRAM:incident-summary"
            fi
            if [[ "$severity" == "L3" ]]; then
                channels+="|SLACK:oncall"
            fi
            echo "$channels"
            ;;
        *)
            echo "PROJECT:${PROJECT_CHANNELS}"
            ;;
    esac
}

# 메인 로직
main() {
    local json=""
    local list_mode="false"
    local list_count="20"
    
    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --tts)
                ENABLE_TTS="true"
                shift
                ;;
            --list)
                list_mode="true"
                shift
                if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
                    list_count="$1"
                    shift
                fi
                ;;
            -*)
                echo -e "${RED}ERROR${NC}: 알 수 없는 옵션: $1"
                usage
                ;;
            *)
                json="$1"
                shift
                ;;
        esac
    done
    
    # --list 모드
    if [[ "$list_mode" == "true" ]]; then
        local db_script
        db_script="$(dirname "${BASH_SOURCE[0]}")/incident-db.sh"
        if [[ -x "$db_script" ]]; then
            "$db_script" --list "$list_count"
        else
            echo -e "${RED}ERROR${NC}: incident-db.sh 없음"
            exit 1
        fi
        exit 0
    fi
    
    if [[ -z "$json" ]]; then
        usage
    fi
    
    # JSON 파싱
    project=$(parse_json "$json" "project")
    severity=$(parse_json "$json" "severity")
    title=$(parse_json "$json" "title")
    cause=$(parse_json "$json" "cause")
    action=$(parse_json "$json" "action")
    verify=$(parse_json "$json" "verify")
    prevent=$(parse_json "$json" "prevent")
    
    # 필수 필드 검증
    if [[ -z "$severity" || -z "$title" ]]; then
        echo -e "${RED}ERROR${NC}: severity와 title은 필수 필드입니다"
        exit 1
    fi
    
    # 기본값 설정
    project=${project:-"unknown"}
    cause=${cause:-"원인 분석 중"}
    action=${action:-"조치 대기 중"}
    verify=${verify:-"검증 필요"}
    prevent=${prevent:-"재발방지 대책 수립 중"}
    
    # DB 저장
    save_to_db "$json"
    
    # 채널 결정
    channels=$(determine_channels "$project" "$severity")
    
    # 출력
    echo ""
    echo -e "${BLUE}═══════════════════════════════════${NC}"
    echo -e "${BLUE}  INCIDENT ROUTER${NC}"
    echo -e "${BLUE}═══════════════════════════════════${NC}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN MODE]${NC}"
    fi
    
    echo -e "${GREEN}📢 라우팅 제안:${NC}"
    echo "$channels" | tr '|' '\n' | while read -r ch; do
        echo "  → $ch"
    done
    echo ""
    
    # 4줄 리포트 생성
    generate_report "$project" "$severity" "$title" "$cause" "$action" "$verify" "$prevent"
    
    # L2/L3인 경우 Telegram + Discord 발송
    if [[ "$severity" == "L2" || "$severity" == "L3" ]]; then
        local summary
        summary=$(format_summary "$project" "$severity" "$title" "$cause" "$action" "$verify" "$prevent")
        
        # Discord 발송 (우선)
        if [[ -n "$DISCORD_WEBHOOK_ALERTS" ]]; then
            echo ""
            echo -e "${BLUE}📤 Discord 발송 중...${NC}"
            local discord_desc="🔍 원인: $cause\n🔧 조치: $action\n✅ 검증: $verify\n🛡️ 재발방지: $prevent"
            send_discord "$DISCORD_WEBHOOK_ALERTS" "$title" "$discord_desc" "$severity" "$project"
        fi
        
        # Telegram 발송
        if [[ "$TELEGRAM_SUMMARY" == "true" ]]; then
            echo ""
            echo -e "${BLUE}📤 Telegram 발송 중...${NC}"
            send_telegram "$summary"
            
            # L3 + TTS 플래그인 경우 음성 생성
            if [[ "$severity" == "L3" && "$ENABLE_TTS" == "true" ]]; then
                local tts_text="긴급 인시던트 발생. $title. 원인은 $cause. 조치는 $action 완료."
                send_tts "$tts_text"
            fi
        fi
    fi
    
    # L1인 경우 Discord 프로젝트 채널 발송 (선택)
    if [[ "$severity" == "L1" && -n "$DISCORD_WEBHOOK_PROJECT" ]]; then
        echo ""
        echo -e "${BLUE}📤 Discord (project) 발송 중...${NC}"
        local discord_desc="🔍 원인: $cause\n🔧 조치: $action\n✅ 검증: $verify\n🛡️ 재발방지: $prevent"
        send_discord "$DISCORD_WEBHOOK_PROJECT" "$title" "$discord_desc" "$severity" "$project"
    fi
    
    # 출력 포맷 (후속 처리용)
    echo ""
    echo "---JSON_OUTPUT---"
    cat <<EOF
{"channels":"$channels","report":{"project":"$project","severity":"$severity","title":"$title","cause":"$cause","action":"$action","verify":"$verify","prevent":"$prevent"},"telegram_sent":"$([[ "$severity" == "L2" || "$severity" == "L3" ]] && echo "true" || echo "false")","discord_sent":"$([[ -n "$DISCORD_WEBHOOK_ALERTS" ]] && echo "true" || echo "false")","discord_failed":"$DISCORD_SEND_FAILED"}
EOF
    
    # Discord 발송 실패 시 비정상 종료
    if [[ "$DISCORD_SEND_FAILED" == "true" ]]; then
        exit 2
    fi
}

main "$@"
