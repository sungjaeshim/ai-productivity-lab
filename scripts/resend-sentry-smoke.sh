#!/bin/bash
# Resend/Sentry Smoke Test
# 실행: bash /root/.openclaw/workspace/scripts/resend-sentry-smoke.sh

set -euo pipefail

# ============================================
# 설정
# ============================================
API_BASE="http://127.0.0.1:18800"
SERVICE_NAME="growth-center"
PROJECT_DIR="/root/Projects/growth-center"
ENV_FILE="$PROJECT_DIR/.env"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================
# 유틸리티 함수
# ============================================
log_ok()    { echo -e "${GREEN}✅ $1${NC}"; }
log_err()   { echo -e "${RED}❌ $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_info()  { echo "ℹ️  $1"; }

mask_value() {
    local val="$1"
    if [[ -n "$val" ]]; then
        echo "${val:0:8}***"
    else
        echo "(미설정)"
    fi
}

# ============================================
# 1. 서버 상태 확인
# ============================================
check_server() {
    log_info "서버 상태 확인 중..."

    if ! curl -sf "$API_BASE/api/system" > /dev/null 2>&1; then
        log_err "서버 응답 없음 ($API_BASE)"
        log_info "서비스 상태: $(systemctl is-active $SERVICE_NAME 2>/dev/null || echo 'unknown')"
        return 1
    fi

    log_ok "서버 정상 작동 (port 18800)"
    return 0
}

# ============================================
# 2. Env 파일 존재 확인
# ============================================
check_env_file() {
    log_info "Env 파일 확인 중..."

    if [[ ! -f "$ENV_FILE" ]]; then
        log_warn "Env 파일 없음: $ENV_FILE"
        log_info "다음 명령으로 생성 필요:"
        echo ""
        echo "  cat > $ENV_FILE << 'EOF'"
        echo "  RESEND_API_KEY=re_xxxxxxxxxxxx"
        echo "  RESEND_FROM=noreply@yourdomain.com"
        echo "  RESEND_TO=your-email@example.com"
        echo "  SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx"
        echo "  EOF"
        echo "  chmod 600 $ENV_FILE"
        echo ""
        return 1
    fi

    log_ok "Env 파일 존재"
    return 0
}

# ============================================
# 3. Resend 설정 확인
# ============================================
check_resend() {
    log_info "Resend 설정 확인 중..."

    local response
    response=$(curl -sf "$API_BASE/api/system/email-test" 2>/dev/null)

    if [[ -z "$response" ]]; then
        log_err "API 응답 없음"
        return 1
    fi

    local configured
    configured=$(echo "$response" | jq -r '.data.configured' 2>/dev/null || echo "false")

    if [[ "$configured" == "true" ]]; then
        log_ok "Resend 설정됨"
        echo "$response" | jq '.data | {from, to}' 2>/dev/null
        return 0
    else
        local missing
        missing=$(echo "$response" | jq -r '.data.missing | join(", ")' 2>/dev/null)
        log_warn "Resend 미설정 — 누락: $missing"
        return 1
    fi
}

# ============================================
# 4. Sentry 설정 확인 (로그 기반)
# ============================================
check_sentry() {
    log_info "Sentry 설정 확인 중..."

    # env 파일에서 DSN 확인
    local sentry_dsn=""
    if [[ -f "$ENV_FILE" ]]; then
        sentry_dsn=$(grep -E "^SENTRY_DSN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "")
    fi

    # 실행 중인 프로세스 환경에서 확인
    local pid
    pid=$(pgrep -f "node.*server.js.*growth-center" 2>/dev/null | head -1 || echo "")

    if [[ -n "$pid" && -n "$sentry_dsn" ]]; then
        log_ok "Sentry DSN 설정됨: $(mask_value "$sentry_dsn")"
        return 0
    fi

    # 서비스 파일에 EnvironmentFile 있는지 확인
    if systemctl cat "$SERVICE_NAME" 2>/dev/null | grep -q "EnvironmentFile"; then
        log_warn "Sentry DSN 미설정 — .env 파일에 SENTRY_DSN 추가 필요"
    else
        log_warn "Sentry DSN 미설정 + 서비스에 EnvironmentFile 없음"
        log_info "서비스 파일 수정 필요:"
        echo ""
        echo "  sudo sed -i '/^Environment=/a EnvironmentFile=$ENV_FILE' /etc/systemd/system/$SERVICE_NAME.service"
        echo "  sudo systemctl daemon-reload"
        echo "  sudo systemctl restart $SERVICE_NAME"
        echo ""
    fi
    return 1
}

# ============================================
# 5. Resend 발송 테스트 (옵션)
# ============================================
test_resend_send() {
    log_info "Resend 발송 테스트..."

    local response
    response=$(curl -sf -X POST "$API_BASE/api/system/email-test" 2>/dev/null)

    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        log_ok "이메일 발송 성공"
        echo "$response" | jq '.data | {messageId, to, subject}' 2>/dev/null
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.error // "알 수 없는 오류"' 2>/dev/null)
        log_err "이메일 발송 실패: $error"
        return 1
    fi
}

# ============================================
# 6. 의존성 확인
# ============================================
check_dependencies() {
    log_info "패키지 의존성 확인 중..."

    cd "$PROJECT_DIR"

    local resend_ver sentry_ver
    resend_ver=$(jq -r '.dependencies.resend // empty' package.json 2>/dev/null || echo "")
    sentry_ver=$(jq -r '.dependencies["\\(@sentry/node)"] // empty' package.json 2>/dev/null || echo "")

    if [[ -n "$resend_ver" ]]; then
        log_ok "resend 설치됨: $resend_ver"
    else
        log_err "resend 미설치"
    fi

    if [[ -n "$sentry_ver" ]]; then
        log_ok "@sentry/node 설치됨: $sentry_ver"
    else
        log_err "@sentry/node 미설치"
    fi

    # node_modules 확인
    if [[ -d "node_modules/resend" && -d "node_modules/@sentry/node" ]]; then
        log_ok "node_modules 내 의존성 존재"
        return 0
    else
        log_warn "npm install 필요"
        return 1
    fi
}

# ============================================
# 메인
# ============================================
main() {
    echo "============================================"
    echo "  Resend/Sentry Smoke Test"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    local errors=0

    check_server || ((errors++))
    echo ""

    check_env_file || ((errors++))
    echo ""

    check_dependencies || ((errors++))
    echo ""

    check_resend || ((errors++))
    echo ""

    check_sentry || ((errors++))
    echo ""

    # Resend 발송 테스트는 설정된 경우에만
    if curl -sf "$API_BASE/api/system/email-test" 2>/dev/null | jq -e '.data.configured == true' > /dev/null 2>&1; then
        echo "--- 선택적 테스트 ---"
        test_resend_send || ((errors++))
        echo ""
    fi

    echo "============================================"
    if [[ $errors -eq 0 ]]; then
        log_ok "모든 검증 통과"
    else
        log_err "$errors개 항목 실패/차단"
    fi
    echo "============================================"

    # 상세 보고서 위치 안내
    echo ""
    log_info "상세 보고서: /root/.openclaw/workspace/docs/resend-sentry-validation.md"

    exit $errors
}

main "$@"
