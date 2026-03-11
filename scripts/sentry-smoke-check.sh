#!/bin/bash
#
# Sentry DSM Smoke Check
# DSN 유무 검증 + 테스트 이벤트 명령 출력
#
# 사용법:
#   ./sentry-smoke-check.sh              # DSN 유무만 확인
#   ./sentry-smoke-check.sh --send       # 실제 테스트 이벤트 발송
#   ./sentry-smoke-check.sh --env-file .env.sentry  # 특정 env 파일 사용
#

set -euo pipefail

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${WORKSPACE_ROOT}/.env.sentry"
SEND_TEST=false

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 프로젝트 정의
declare -A PROJECTS=(
    ["growth-center"]="SENTRY_DSN_GROWTH_CENTER"
    ["blog"]="SENTRY_DSN_BLOG"
    ["ceo-ai"]="SENTRY_DSN_CEO_AI"
    ["macd-bot"]="SENTRY_DSN_MACD_BOT"
)

# 사용법 출력
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --send            실제 테스트 이벤트 발송"
    echo "  --env-file FILE   환경변수 파일 지정 (기본: .env.sentry)"
    echo "  -h, --help        도움말 출력"
    echo ""
    echo "Example:"
    echo "  $0                          # DSN 유무만 확인"
    echo "  $0 --send                   # 테스트 이벤트 발송"
    echo "  $0 --env-file /opt/app/.env # 특정 파일 사용"
}

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --send)
            SEND_TEST=true
            shift
            ;;
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}알 수 없는 옵션: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# 환경변수 파일 로드
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        echo -e "${BLUE}환경변수 파일 로드: $ENV_FILE${NC}"
        # 파일에서 변수 읽어서 export (주석 및 빈 줄 제외)
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 주석과 빈 줄 건너뛰기
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            # export 실행
            export "$line" 2>/dev/null || true
        done < "$ENV_FILE"
    else
        echo -e "${YELLOW}경고: 환경변수 파일 없음 - $ENV_FILE${NC}"
        echo -e "${YELLOW}기존 환경변수만 검사합니다.${NC}"
    fi
}

# DSN 형식 검증
validate_dsn_format() {
    local dsn="$1"
    if [[ "$dsn" =~ ^https://[a-f0-9]+@o[0-9]+\.ingest\.sentry\.io/[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# DSN 존재 여부 확인
check_dsn() {
    local project="$1"
    local varname="$2"
    local value="${!varname:-}"

    if [[ -z "$value" ]]; then
        echo -e "  ${RED}✗${NC} $project: ${varname} = (미설정)"
        return 1
    elif validate_dsn_format "$value"; then
        echo -e "  ${GREEN}✓${NC} $project: ${varname} = ${value:0:30}..."
        return 0
    else
        echo -e "  ${YELLOW}!${NC} $project: ${varname} = (형식 오류)"
        return 1
    fi
}

# 테스트 이벤트 발송 명령 출력
print_test_commands() {
    echo ""
    echo -e "${BLUE}=== 테스트 이벤트 발송 명령 ===${NC}"
    echo ""
    for project in "${!PROJECTS[@]}"; do
        local varname="${PROJECTS[$project]}"
        local value="${!varname:-}"

        if [[ -n "$value" ]]; then
            echo -e "${YELLOW}# $project${NC}"
            echo "curl -sL https://sentry.io/api/embed/error-page/ -H 'Content-Type: application/json' \\"
            echo "  -H 'X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${value#https://}, sentry_client=test' \\"
            echo "  -d '{\"message\":\"[SMOKE TEST] $project connectivity check\",\"level\":\"info\"}'"
            echo ""
        fi
    done
}

# 실제 테스트 이벤트 발송
send_test_events() {
    echo -e "${BLUE}=== 테스트 이벤트 발송 중 ===${NC}"
    echo ""

    local sent_count=0
    local fail_count=0

    for project in "${!PROJECTS[@]}"; do
        local varname="${PROJECTS[$project]}"
        local value="${!varname:-}"

        if [[ -n "$value" ]]; then
            echo -n "  $project: "
            # Sentry API를 통한 테스트 이벤트 (간단한 HTTP 요청)
            # 실제 SDK 없이 curl로 테스트
            local key="${value#https://}"
            key="${key%%@*}"

            local response
            response=$(curl -sL -w "%{http_code}" -o /dev/null \
                "https://sentry.io/api/embed/error-page/" \
                -H "Content-Type: application/json" \
                -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$key, sentry_client=smoke-check/1.0" \
                -d "{\"message\":\"[SMOKE TEST] $project connectivity check\",\"level\":\"info\"}" 2>/dev/null || echo "000")

            if [[ "$response" =~ ^2 ]]; then
                echo -e "${GREEN}전송 완료 (HTTP $response)${NC}"
                ((sent_count++))
            else
                echo -e "${RED}전송 실패 (HTTP $response)${NC}"
                ((fail_count++))
            fi
        fi
    done

    echo ""
    echo -e "결과: ${GREEN}성공 $sent_count${NC}, ${RED}실패 $fail_count${NC}"
}

# 메인
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Sentry DSN Smoke Check${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    load_env
    echo ""

    echo -e "${BLUE}=== DSN 설정 확인 ===${NC}"

    local total=0
    local configured=0

    for project in growth-center blog ceo-ai macd-bot; do
        ((total++))
        if check_dsn "$project" "${PROJECTS[$project]}"; then
            ((configured++))
        fi
    done

    echo ""
    echo -e "요약: ${configured}/${total} 프로젝트 DSN 설정됨"

    if [[ "$SEND_TEST" == true ]]; then
        send_test_events
    else
        print_test_commands
        echo -e "${YELLOW}팁: --send 옵션으로 실제 테스트 이벤트 발송 가능${NC}"
    fi

    echo ""
    echo -e "${BLUE}========================================${NC}"

    # 종료 코드
    if [[ $configured -eq $total ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
