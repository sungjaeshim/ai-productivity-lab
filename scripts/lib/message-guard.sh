#!/usr/bin/env bash
# message-guard.sh - Common validation guard for OpenClaw message tool
# Ensures channel and target are provided before sending messages
#
# USAGE:
#   source "$(dirname "$0")/lib/message-guard.sh"
#   validate_message_params --channel "$channel" --target "$target"
#
# EXIT CODES:
#   0 - Validation passed
#   1 - Validation failed (missing channel or target)
#
# ENVIRONMENT:
#   MESSAGE_GUARD_STRICT - If "true", fail even in dry-run mode (default: false)

set -euo pipefail

# Color output for errors
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation function
validate_message_params() {
    local channel=""
    local target=""
    local strict="${MESSAGE_GUARD_STRICT:-false}"
    local dry_run="${MESSAGE_GUARD_DRY_RUN:-false}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel)
                channel="${2:-}"
                shift 2
                ;;
            --target)
                target="${2:-}"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                cat <<EOF
message-guard.sh - Validate message parameters

Usage:
  validate_message_params --channel CHANNEL --target TARGET [--dry-run]

Options:
  --channel CHANNEL    Channel to send to (required: telegram/discord/etc)
  --target TARGET      Target ID for the channel (required)
  --dry-run            Mark as dry-run mode (validation may be relaxed)

Exit Codes:
  0  Validation passed
  1  Validation failed (missing required parameters)

Environment:
  MESSAGE_GUARD_STRICT  If "true", fail even in dry-run mode (default: false)
  MESSAGE_GUARD_DRY_RUN Internal dry-run flag

Examples:
  # Basic validation
  if ! validate_message_params --channel "$CHAN" --target "$TGT"; then
    echo "Invalid parameters" >&2
    exit 1
  fi

  # With inline call
  validate_message_params --channel "telegram" --target "62403941" || exit 1

  # Strict mode (fail even in dry-run)
  MESSAGE_GUARD_STRICT=true validate_message_params --channel "$CHAN" --target "$TGT"
EOF
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Skip validation if dry_run and not strict
    if [[ "$dry_run" == "true" && "$strict" != "true" ]]; then
        return 0
    fi

    # Validate channel
    if [[ -z "${channel:-}" ]]; then
        echo -e "${RED}✗ message-guard: missing channel parameter${NC}" >&2
        echo -e "${YELLOW}  Usage: openclaw message send --channel CHANNEL --target TARGET${NC}" >&2
        return 1
    fi

    # Validate target
    if [[ -z "${target:-}" ]]; then
        echo -e "${RED}✗ message-guard: missing target parameter for channel '$channel'${NC}" >&2
        echo -e "${YELLOW}  Usage: openclaw message send --channel $channel --target TARGET${NC}" >&2
        echo -e "${YELLOW}  Environment: Set appropriate *_TARGET or *_CHANNEL_ID variable${NC}" >&2
        return 1
    fi

    # Both parameters present
    return 0
}

# Export function for sourcing
export -f validate_message_params

# If script is executed directly, run validation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_message_params "$@"
    exit $?
fi
