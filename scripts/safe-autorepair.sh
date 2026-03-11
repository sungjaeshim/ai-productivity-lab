#!/bin/bash
# safe-autorepair.sh - 안전한 자동 복구 스크립트
# 기본: 계획 모드 (no-op), --execute 시 실제 실행

set -euo pipefail

# 색상 코드
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${LOG_FILE:-$WORKSPACE_DIR/logs/incident-autorepair.log}"
EXECUTE_MODE=false
AUTO_APPROVE=false

# 허용 서비스 allowlist
ALLOWED_SERVICES=(
    "openclaw"
    "growth-center"
    "nginx"
    "cloudflared"
)

# 위험 작업 키워드 (항상 거부)
DANGEROUS_KEYWORDS=(
    "DROP"
    "DELETE"
    "TRUNCATE"
    "ALTER TABLE"
    "rm -rf"
    "chmod 777"
    "shutdown"
    "reboot"
    "halt"
    "poweroff"
)

usage() {
    cat <<EOF
Usage: $0 <action> [service] [options]

안전 작업:
  restart <service>     - 서비스 재시작
  reload <service>      - 서비스 설정 리로드
  status <service>      - 서비스 상태 확인
  health-check          - 전체 헬스체크

옵션:
  --execute             - 실제 실행 (기본: 계획 모드)
  --yes                 - 실행 전 확인 생략
  --log FILE            - 로그 파일 지정

예시:
  $0 restart nginx              # 계획만 출력
  $0 restart nginx --execute    # 실제 실행 (--yes 필요)
  $0 restart nginx --execute --yes  # 확인 없이 실행

allowlist 서비스:
  ${ALLOWED_SERVICES[*]}
EOF
    exit 1
}

# 로깅
log() {
    local level="$1" msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] [$level] $msg"
    
    # 로그 디렉토리 생성
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # 파일에 기록
    echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true
    
    # 콘솔 출력
    case "$level" in
        ERROR)   echo -e "${RED}$log_line${NC}" ;;
        WARN)    echo -e "${YELLOW}$log_line${NC}" ;;
        SUCCESS) echo -e "${GREEN}$log_line${NC}" ;;
        INFO)    echo -e "${BLUE}$log_line${NC}" ;;
        *)       echo "$log_line" ;;
    esac
}

# 서비스 허용 확인
is_allowed_service() {
    local service="$1"
    
    for allowed in "${ALLOWED_SERVICES[@]}"; do
        if [[ "$service" == "$allowed" ]]; then
            return 0
        fi
    done
    return 1
}

# 위험 작업 검사
is_dangerous() {
    local cmd="$1"
    local normalized_cmd
    normalized_cmd=$(echo "$cmd" | tr '[:upper:]' '[:lower:]')
    
    for keyword in "${DANGEROUS_KEYWORDS[@]}"; do
        if echo "$normalized_cmd" | grep -qi "$keyword"; then
            return 0
        fi
    done
    return 1
}

# 실행 확인 프롬프트
confirm_execution() {
    local action="$1" service="$2"
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  실행 확인${NC}"
    echo -e "  작업: $action"
    echo -e "  대상: $service"
    echo -e "  모드: 실제 실행 (--execute)"
    echo ""
    echo -n "진행하시겠습니까? (y/N): "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

# 위험 작업 거부
reject_dangerous() {
    local cmd="$1"
    
    echo ""
    echo -e "${RED}🚫 실행 거부${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  이 작업은 위험으로 분류되어 실행할 수 없습니다."
    echo ""
    echo -e "  ${YELLOW}요청:${NC} $cmd"
    echo ""
    echo -e "  ${BLUE}안내:${NC}"
    echo "  - 삭제/포트변경/DB마이그레이션은 수동으로 처리하세요"
    echo "  - 필요시 관리자에게 문의하세요"
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log "WARN" "위험 작업 거부됨: $cmd"
    return 1
}

# 허용되지 않은 서비스 거부
reject_unauthorized_service() {
    local service="$1"
    
    echo ""
    echo -e "${RED}🚫 서비스 거부${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}$service${NC} 는 allowlist에 없습니다."
    echo ""
    echo -e "  ${GREEN}허용된 서비스:${NC}"
    for allowed in "${ALLOWED_SERVICES[@]}"; do
        echo "    - $allowed"
    done
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log "WARN" "허용되지 않은 서비스: $service"
    return 1
}

# 계획 모드 실행 (기본)
plan_mode() {
    local action="$1" service="$2"
    
    echo ""
    echo -e "${BLUE}📋 계획 모드 (--execute 없음)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  작업: $action"
    echo -e "  대상: $service"
    echo ""
    
    case "$action" in
        restart|reload)
            echo -e "  ${GREEN}예정 명령:${NC} systemctl $action $service"
            echo -e "  ${GREEN}예상 결과:${NC} $service 서비스가 $action 됨"
            ;;
        status)
            echo -e "  ${GREEN}예정 명령:${NC} systemctl status $service"
            echo -e "  ${GREEN}예상 결과:${NC} $service 상태 정보 출력"
            ;;
        health-check)
            echo -e "  ${GREEN}예정 작업:${NC} allowlist 서비스 상태 확인"
            for svc in "${ALLOWED_SERVICES[@]}"; do
                echo "    - systemctl status $svc"
            done
            ;;
        *)
            echo -e "  ${YELLOW}알 수 없는 작업${NC}"
            ;;
    esac
    
    echo ""
    echo -e "  ${BLUE}실제 실행하려면 --execute 플래그를 추가하세요${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log "INFO" "계획 모드 완료: $action $service"
    return 0
}

# 실제 실행 모드
execute_mode() {
    local action="$1" service="$2"
    
    log "INFO" "실행 모드 시작: $action $service"
    
    case "$action" in
        restart)
            log "INFO" "systemctl restart $service 실행 중..."
            if systemctl restart "$service" 2>&1; then
                log "SUCCESS" "✅ $service 재시작 완료"
            else
                log "ERROR" "❌ $service 재시작 실패"
                return 1
            fi
            ;;
        reload)
            log "INFO" "systemctl reload $service 실행 중..."
            if systemctl reload "$service" 2>&1; then
                log "SUCCESS" "✅ $service 리로드 완료"
            else
                log "ERROR" "❌ $service 리로드 실패"
                return 1
            fi
            ;;
        status)
            log "INFO" "systemctl status $service 출력..."
            systemctl status "$service" 2>&1 || true
            ;;
        health-check)
            log "INFO" "전체 헬스체크 시작..."
            local failed=0
            for svc in "${ALLOWED_SERVICES[@]}"; do
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    log "SUCCESS" "✅ $svc: 실행 중"
                else
                    log "WARN" "⚠️ $svc: 중지됨 또는 없음"
                    ((failed++)) || true
                fi
            done
            if [[ $failed -eq 0 ]]; then
                log "SUCCESS" "헬스체크: 모든 서비스 정상"
            else
                log "WARN" "헬스체크: $failed개 서비스 비정상"
            fi
            ;;
        *)
            log "ERROR" "알 수 없는 작업: $action"
            return 1
            ;;
    esac
    
    return 0
}

# 메인 로직
main() {
    local action="${1:-}"
    
    if [[ -z "$action" || "$action" == "-h" || "$action" == "--help" ]]; then
        usage
    fi
    
    # 옵션 파싱
    shift || true
    local service="${1:-}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --execute)
                EXECUTE_MODE=true
                shift
                ;;
            --yes)
                AUTO_APPROVE=true
                shift
                ;;
            --log)
                LOG_FILE="$2"
                shift 2
                ;;
            -*)
                echo "알 수 없는 옵션: $1" >&2
                exit 1
                ;;
            *)
                if [[ -z "$service" ]]; then
                    service="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 위험 작업 검사
    if is_dangerous "$action $service"; then
        reject_dangerous "$action $service"
        exit 1
    fi
    
    # 서비스 필요 작업 검사
    if [[ "$action" =~ ^(restart|reload|status)$ ]]; then
        if [[ -z "$service" ]]; then
            log "ERROR" "서비스명 필요: $0 $action <service>"
            exit 1
        fi
        
        # allowlist 확인
        if ! is_allowed_service "$service"; then
            reject_unauthorized_service "$service"
            exit 1
        fi
    fi
    
    # 실행 모드 분기
    if [[ "$EXECUTE_MODE" == "true" ]]; then
        # 실행 확인 (--yes 없으면 프롬프트)
        if ! confirm_execution "$action" "$service"; then
            log "INFO" "사용자에 의해 취소됨"
            exit 0
        fi
        execute_mode "$action" "$service"
    else
        plan_mode "$action" "$service"
    fi
}

main "$@"
