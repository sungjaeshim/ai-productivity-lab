#!/bin/bash
# brain-todoist-stale-check.sh - Detect tasks with no status change in 24h
# Usage: brain-todoist-stale-check.sh [--dry-run] [--hours N] [--output json|text]
#
# Purpose: Find BLOCKED candidates in Active/Waiting projects
# Output: Tasks that haven't been updated in the specified hours (default: 24)
#
# Exit codes:
#   0 - Success (may have stale tasks)
#   1 - API error
#   2 - Auth error (missing/invalid token)
#   3 - jq not available
#
# Limitations:
#   - Todoist API doesn't provide full activity history; uses updated_at only
#   - Cannot detect comment-only updates as status changes
#   - Rate limited to ~450 requests/15min (Todoist Sync API)

set -eo pipefail

# === Config ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_DIR="/root/.openclaw/credentials"
TODOIST_TOKEN=""
PROJECTS_FILE="${CREDENTIALS_DIR}/todoist-projects.json"
API_BASE="https://api.todoist.com/api/v1"

# Default values
DRY_RUN=false
STALE_HOURS=24
OUTPUT_FORMAT="text"

# === Parse args ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --hours) STALE_HOURS="$2"; shift 2 ;;
        --output) OUTPUT_FORMAT="$2"; shift 2 ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Detect tasks with no status change in the last N hours.

Options:
  --dry-run      Show what would be checked without API calls
  --hours N      Hours threshold for staleness (default: 24)
  --output FMT   Output format: text|json (default: text)
  --help         Show this help

Examples:
  $(basename "$0")                    # Check for 24h stale tasks
  $(basename "$0") --hours 48         # Check for 48h stale tasks
  $(basename "$0") --dry-run          # Preview without API calls

Exit codes: 0=OK, 1=API error, 2=Auth error, 3=Missing jq
EOF
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# === Dependencies ===
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 3
fi

# === Load token ===
if [[ -f "${CREDENTIALS_DIR}/todoist" ]]; then
    TODOIST_TOKEN=$(cat "${CREDENTIALS_DIR}/todoist")
else
    echo "ERROR: Todoist token not found at ${CREDENTIALS_DIR}/todoist" >&2
    exit 2
fi

if [[ -z "$TODOIST_TOKEN" ]]; then
    echo "ERROR: Todoist token is empty" >&2
    exit 2
fi

# === Load project IDs ===
if [[ ! -f "$PROJECTS_FILE" ]]; then
    echo "ERROR: Projects file not found: $PROJECTS_FILE" >&2
    exit 1
fi

ACTIVE_ID=$(jq -r '.active' "$PROJECTS_FILE" 2>/dev/null)
WAITING_ID=$(jq -r '.waiting' "$PROJECTS_FILE" 2>/dev/null)

if [[ -z "$ACTIVE_ID" || "$ACTIVE_ID" == "null" ]]; then
    echo "ERROR: Could not get Active project ID" >&2
    exit 1
fi

if [[ -z "$WAITING_ID" || "$WAITING_ID" == "null" ]]; then
    echo "ERROR: Could not get Waiting project ID" >&2
    exit 1
fi

# === Calculate threshold ===
# ISO 8601 timestamp for N hours ago
THRESHOLD_TS=$(date -d "${STALE_HOURS} hours ago" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -v-${STALE_HOURS}H -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

if [[ -z "$THRESHOLD_TS" ]]; then
    echo "ERROR: Could not calculate threshold timestamp" >&2
    exit 1
fi

# === Dry-run mode ===
if $DRY_RUN; then
    cat <<EOF
[DRY-RUN] Would check for stale tasks

Configuration:
  Stale threshold: ${STALE_HOURS}h (before $THRESHOLD_TS)
  Active project:  $ACTIVE_ID
  Waiting project: $WAITING_ID
  Output format:   $OUTPUT_FORMAT

Would fetch tasks from both projects and filter by updated_at < threshold.
EOF
    exit 0
fi

# === Fetch tasks ===
fetch_tasks() {
    local project_id="$1"
    local result
    result=$(curl -s -w "\n%{http_code}" -X GET "${API_BASE}/tasks?project_id=${project_id}" \
        -H "Authorization: Bearer ${TODOIST_TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    local http_code=$(echo "$result" | tail -1)
    local body=$(echo "$result" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        echo "ERROR: API returned HTTP $http_code for project $project_id" >&2
        echo "$body" >&2
        return 1
    fi
    
    echo "$body"
}

# Fetch from both projects
ACTIVE_TASKS=$(fetch_tasks "$ACTIVE_ID") || exit 1
WAITING_TASKS=$(fetch_tasks "$WAITING_ID") || exit 1

# === Process and find stale tasks ===
# Filter tasks where updated_at < threshold
STALE_ACTIVE=$(echo "$ACTIVE_TASKS" | jq --arg threshold "$THRESHOLD_TS" '
    .results | map(select(.updated_at < $threshold)) | 
    map({id, content, updated_at, project: "Active"})
' 2>/dev/null)

STALE_WAITING=$(echo "$WAITING_TASKS" | jq --arg threshold "$THRESHOLD_TS" '
    .results | map(select(.updated_at < $threshold)) | 
    map({id, content, updated_at, project: "Waiting"})
' 2>/dev/null)

# Combine results
ALL_STALE=$(echo "[$STALE_ACTIVE, $STALE_WAITING]" | jq 'add | sort_by(.updated_at)')

# Count
STALE_COUNT=$(echo "$ALL_STALE" | jq 'length')

# === Output ===
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "$ALL_STALE" | jq '{
        stale_count: length,
        threshold_hours: '"$STALE_HOURS"' | tostring,
        threshold_time: "'"$THRESHOLD_TS"'",
        tasks: .
    }'
else
    echo "=== Stale Task Report ==="
    echo "Threshold: ${STALE_HOURS}h (tasks not updated since $THRESHOLD_TS)"
    echo ""
    
    if [[ "$STALE_COUNT" -eq 0 ]]; then
        echo "✅ No stale tasks found."
    else
        echo "⚠️  Found $STALE_COUNT stale task(s):"
        echo ""
        echo "$ALL_STALE" | jq -r '.[] | "[\(.project)] \(.id[:8])... \(.content)\n    Last update: \(.updated_at)\n"'
        
        echo ""
        echo "📋 BLOCKED Candidates:"
        echo "   Tasks above haven't moved in ${STALE_HOURS}h. Consider:"
        echo "   1. Move to Waiting if blocked externally"
        echo "   2. Break down if too large"
        echo "   3. Delete if no longer relevant"
    fi
fi

exit 0
