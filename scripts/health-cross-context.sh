#!/bin/bash
#
# health-cross-context.sh - Cross-context routing health check
#
# USAGE:
#   ./health-cross-context.sh [--json]
#
# CHECKS:
#   1. OpenClaw Discord channel config
#   2. Discord webhook env var
#   3. Network connectivity to Discord
#   4. discord-send-safe.sh availability
#
# EXIT CODE:
#   0 - All checks pass
#   1 - Some checks failed (details in output)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Output mode
JSON_MODE=false
PASS=0
FAIL=0
WARN=0

# ============================================================================
# FUNCTIONS
# ============================================================================

pass() {
    ((PASS++))
    [[ "$JSON_MODE" == "false" ]] && echo -e "${GREEN}✓${NC} $1"
}

fail() {
    ((FAIL++))
    [[ "$JSON_MODE" == "false" ]] && echo -e "${RED}✗${NC} $1"
}

warn() {
    ((WARN++))
    [[ "$JSON_MODE" == "false" ]] && echo -e "${YELLOW}⚠${NC} $1"
}

check_openclaw_discord_config() {
    local config_file="$HOME/.openclaw/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        warn "OpenClaw config not found: $config_file"
        return 1
    fi
    
    if grep -q '"discord"' "$config_file" && grep -A5 '"discord"' "$config_file" | grep -q '"enabled"[[:space:]]*:[[:space:]]*true'; then
        pass "Discord channel configured and enabled in OpenClaw"
        return 0
    else
        warn "Discord channel NOT configured in OpenClaw (cross-context will be denied)"
        return 1
    fi
}

check_discord_webhook_env() {
    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        # Mask the URL for display
        local masked
        masked=$(echo "$DISCORD_WEBHOOK_URL" | sed -E 's|https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|https://discord.com/api/webhooks/***/***|g')
        pass "DISCORD_WEBHOOK_URL is set: $masked"
        return 0
    else
        # Check .env file
        if [[ -f "$WORKSPACE/.env" ]] && grep -q "^DISCORD_WEBHOOK_URL=" "$WORKSPACE/.env"; then
            pass "DISCORD_WEBHOOK_URL found in .env (source it first)"
            return 0
        fi
        fail "DISCORD_WEBHOOK_URL not set (webhook fallback unavailable)"
        return 1
    fi
}

check_network_connectivity() {
    # Quick check to Discord API
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 3 --max-time 5 "https://discord.com/api/v10/gateway" >/dev/null 2>&1; then
            pass "Network connectivity to Discord API OK"
            return 0
        else
            warn "Cannot reach Discord API (network/firewall issue?)"
            return 1
        fi
    else
        warn "curl not available, skipping network check"
        return 1
    fi
}

check_safe_sender() {
    local script="$SCRIPT_DIR/discord-send-safe.sh"
    
    if [[ -x "$script" ]]; then
        # Syntax check
        if bash -n "$script" 2>/dev/null; then
            pass "discord-send-safe.sh exists and syntax OK"
            return 0
        else
            fail "discord-send-safe.sh has syntax errors"
            return 1
        fi
    else
        fail "discord-send-safe.sh not found or not executable"
        return 1
    fi
}

check_tools() {
    local missing=0
    
    for tool in curl jq; do
        if command -v "$tool" >/dev/null 2>&1; then
            pass "$tool available"
        else
            warn "$tool not available (some features may not work)"
            ((missing++))
        fi
    done
    
    return $missing
}

print_summary() {
    local total=$((PASS + FAIL + WARN))
    
    if [[ "$JSON_MODE" == "true" ]]; then
        cat <<EOF
{
  "status": "$([ $FAIL -eq 0 ] && echo "ok" || echo "degraded")",
  "passed": $PASS,
  "failed": $FAIL,
  "warnings": $WARN,
  "checks": $total,
  "recommendation": "$([ $FAIL -gt 0 ] && echo "Set DISCORD_WEBHOOK_URL or configure Discord in OpenClaw" || echo "All checks passed")"
}
EOF
    else
        echo ""
        echo "================================"
        echo "Summary: $PASS passed, $FAIL failed, $WARN warnings"
        echo "================================"
        
        if [[ $FAIL -gt 0 ]]; then
            echo ""
            echo "⚠ Action needed:"
            echo "  1. Set DISCORD_WEBHOOK_URL in .env for webhook fallback"
            echo "  2. Or configure Discord channel in ~/.openclaw/config.json"
            echo ""
            echo "Quick fix:"
            echo "  echo 'DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/ID/TOKEN' >> .env"
            return 1
        fi
    fi
}

# ============================================================================
# MAIN
# ============================================================================

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--json]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

[[ "$JSON_MODE" == "false" ]] && echo "=== Cross-Context Routing Health Check ==="
[[ "$JSON_MODE" == "false" ]] && echo ""

# Run checks
check_openclaw_discord_config || true
check_discord_webhook_env || true
check_network_connectivity || true
check_safe_sender || true
check_tools || true

# Print summary
print_summary
