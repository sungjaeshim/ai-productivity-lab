#!/usr/bin/env bash
# Compatibility wrapper for legacy todoist-monitor callers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_HOURS="${TODOIST_MONITOR_HOURS:-24}"

exec "${SCRIPT_DIR}/brain-todoist-stale-check.sh" --hours "$DEFAULT_HOURS" "$@"
