#!/bin/bash
# Growth Center Resend/Sentry Environment Setup
# Usage: ./growth-center-env-setup.sh [--dry-run] [--apply]
#
# --dry-run: Show what would be done (default)
# --apply:  Actually create files and restart service
#
# Required env vars (set before running or provide interactively):
#   RESEND_API_KEY - From https://resend.com/api-keys
#   RESEND_FROM    - Sender email (must be verified in Resend)
#   RESEND_TO      - Default recipient email
#   SENTRY_DSN     - From Sentry project settings (optional)

set -euo pipefail

# ============================================
# CONFIG
# ============================================

SERVICE_NAME="growth-center"
PROJECT_DIR="/root/Projects/growth-center"
ENV_FILE="/root/Projects/growth-center/.env"
OVERRIDE_DIR="/etc/systemd/system/${SERVICE_NAME}.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# ARGS
# ============================================

DRY_RUN=true
APPLY=false

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true; APPLY=false ;;
    --apply) DRY_RUN=false; APPLY=true ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

# ============================================
# FUNCTIONS
# ============================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_cmd() {
  if command -v "$1" &>/dev/null; then
    log_ok "$1 available"
    return 0
  else
    log_err "$1 not found"
    return 1
  fi
}

# ============================================
# PREFLIGHT CHECKS
# ============================================

echo ""
echo "============================================"
echo "  Growth Center ENV Setup - Preflight Check"
echo "============================================"
echo ""

# Check required commands
CMDS_OK=true
for cmd in systemctl node curl; do
  check_cmd "$cmd" || CMDS_OK=false
done

if ! $CMDS_OK; then
  log_err "Missing required commands. Install and retry."
  exit 1
fi

# Check service exists
if ! systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null; then
  log_err "Service ${SERVICE_NAME} not found"
  exit 1
fi
log_ok "Service ${SERVICE_NAME} found"

# ============================================
# ENV VARS CHECK
# ============================================

echo ""
log_info "Checking environment variables..."
echo ""

# Resend vars
RESEND_API_KEY="${RESEND_API_KEY:-}"
RESEND_FROM="${RESEND_FROM:-}"
RESEND_TO="${RESEND_TO:-}"

# Sentry var
SENTRY_DSN="${SENTRY_DSN:-}"

# Track what's missing
MISSING=()

if [[ -z "$RESEND_API_KEY" ]]; then
  log_warn "RESEND_API_KEY: NOT SET"
  MISSING+=("RESEND_API_KEY")
else
  log_ok "RESEND_API_KEY: ${RESEND_API_KEY:0:10}..."
fi

if [[ -z "$RESEND_FROM" ]]; then
  log_warn "RESEND_FROM: NOT SET"
  MISSING+=("RESEND_FROM")
else
  log_ok "RESEND_FROM: $RESEND_FROM"
fi

if [[ -z "$RESEND_TO" ]]; then
  log_warn "RESEND_TO: NOT SET"
  MISSING+=("RESEND_TO")
else
  log_ok "RESEND_TO: $RESEND_TO"
fi

if [[ -z "$SENTRY_DSN" ]]; then
  log_warn "SENTRY_DSN: NOT SET (optional - Sentry disabled)"
else
  log_ok "SENTRY_DSN: ${SENTRY_DSN:0:30}..."
fi

# ============================================
# BLOCKER CHECK
# ============================================

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  log_err "BLOCKERS FOUND - Cannot proceed without:"
  echo ""
  for var in "${MISSING[@]}"; do
    echo "  - $var"
  done
  echo ""
  echo "Get these values from:"
  echo "  RESEND_API_KEY: https://resend.com/api-keys"
  echo "  RESEND_FROM:    Verified sender in Resend dashboard"
  echo "  RESEND_TO:      Your email address"
  echo ""
  echo "Then run with variables set:"
  echo "  RESEND_API_KEY=re_xxx RESEND_FROM=noreply@yourdomain.com RESEND_TO=you@example.com \\"
  echo "    $0 --apply"
  echo ""
  exit 1
fi

# ============================================
# DRY RUN PREVIEW
# ============================================

if $DRY_RUN; then
  echo ""
  echo "============================================"
  echo "  DRY RUN - What would be done:"
  echo "============================================"
  echo ""
  
  echo "1. Create ${ENV_FILE}:"
  echo "---"
  echo "# Growth Center Environment"
  echo "# Generated: $(date -Iseconds)"
  echo ""
  echo "NODE_ENV=production"
  echo "RESEND_API_KEY=${RESEND_API_KEY}"
  echo "RESEND_FROM=${RESEND_FROM}"
  echo "RESEND_TO=${RESEND_TO}"
  if [[ -n "$SENTRY_DSN" ]]; then
    echo "SENTRY_DSN=${SENTRY_DSN}"
  fi
  echo "---"
  echo ""
  
  echo "2. Create systemd override ${OVERRIDE_FILE}:"
  echo "---"
  echo "[Service]"
  echo "EnvironmentFile=${ENV_FILE}"
  echo "---"
  echo ""
  
  echo "3. Reload systemd daemon"
  echo ""
  echo "4. Restart ${SERVICE_NAME} service"
  echo ""
  
  echo "5. Verify with:"
  echo "   curl -s http://127.0.0.1:18800/api/system/email-test"
  echo ""
  
  log_info "Run with --apply to execute"
  exit 0
fi

# ============================================
# APPLY CHANGES
# ============================================

if $APPLY; then
  echo ""
  log_info "Applying changes..."
  echo ""
  
  # Create .env file
  log_info "Creating ${ENV_FILE}..."
  cat > "${ENV_FILE}" <<EOF
# Growth Center Environment
# Generated: $(date -Iseconds)
# WARNING: This file contains secrets - DO NOT COMMIT

NODE_ENV=production
RESEND_API_KEY=${RESEND_API_KEY}
RESEND_FROM=${RESEND_FROM}
RESEND_TO=${RESEND_TO}
EOF

  if [[ -n "$SENTRY_DSN" ]]; then
    echo "SENTRY_DSN=${SENTRY_DSN}" >> "${ENV_FILE}"
  fi
  
  chmod 600 "${ENV_FILE}"
  log_ok "Created ${ENV_FILE} (chmod 600)"
  
  # Create systemd override
  log_info "Creating systemd override..."
  mkdir -p "${OVERRIDE_DIR}"
  cat > "${OVERRIDE_FILE}" <<EOF
[Service]
EnvironmentFile=${ENV_FILE}
EOF
  log_ok "Created ${OVERRIDE_FILE}"
  
  # Reload systemd
  log_info "Reloading systemd daemon..."
  systemctl daemon-reload
  log_ok "Systemd reloaded"
  
  # Restart service
  log_info "Restarting ${SERVICE_NAME}..."
  systemctl restart "${SERVICE_NAME}"
  sleep 2
  
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log_ok "Service ${SERVICE_NAME} restarted successfully"
  else
    log_err "Service ${SERVICE_NAME} failed to start!"
    systemctl status "${SERVICE_NAME}" --no-pager
    exit 1
  fi
  
  # Verify
  echo ""
  log_info "Verifying email configuration..."
  sleep 2
  
  EMAIL_STATUS=$(curl -s http://127.0.0.1:18800/api/system/email-test)
  CONFIGURED=$(echo "$EMAIL_STATUS" | grep -o '"configured":[^,}]*' | cut -d: -f2)
  
  if [[ "$CONFIGURED" == "true" ]]; then
    log_ok "Email configured successfully!"
    echo ""
    echo "$EMAIL_STATUS" | python3 -m json.tool 2>/dev/null || echo "$EMAIL_STATUS"
  else
    log_err "Email configuration check failed"
    echo "$EMAIL_STATUS"
  fi
  
  # Sentry check
  echo ""
  log_info "Sentry status (check logs):"
  journalctl -u "${SERVICE_NAME}" -n 5 --no-pager | grep -i sentry || echo "(No Sentry logs - either disabled or not yet initialized)"
  
  echo ""
  log_ok "SETUP COMPLETE!"
  echo ""
  echo "Test email send:"
  echo "  curl -X POST http://127.0.0.1:18800/api/system/email-test"
  echo ""
  echo "View logs:"
  echo "  journalctl -u ${SERVICE_NAME} -f"
  echo ""
fi
