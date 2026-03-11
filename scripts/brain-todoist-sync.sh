#!/bin/bash
# brain-todoist-sync.sh - Sync Discord brain-ops status to Todoist
# Usage: brain-todoist-sync.sh --item-id ID --status STATUS --title "Title" [--project PROJECT] [--dry-run]

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
CREDENTIALS_DIR="$HOME/.openclaw/credentials"

TODOIST_TOKEN_FILE="$CREDENTIALS_DIR/todoist"
TODOIST_PROJECTS_FILE="$CREDENTIALS_DIR/todoist-projects.json"
SYNC_REGISTRY="$WORKSPACE_DIR/memory/second-brain/.brain-todoist-registry.jsonl"
TODO_ROUTER_REGISTRY="$WORKSPACE_DIR/memory/second-brain/.todo-router-registry.jsonl"

API_BASE="https://api.todoist.com/api/v1"

# Exit codes
EC_SUCCESS=0
EC_MISSING_ARG=1
EC_INVALID_STATUS=2
EC_MISSING_TOKEN=3
EC_API_ERROR=4
EC_DUPLICATE=5
EC_NOT_FOUND=6

# ============================================================================
# Functions
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") --item-id ID --status STATUS --title "Title" [OPTIONS]

Sync Discord brain-ops status to Todoist.

Required:
  --item-id ID       Unique identifier from brain-ops (e.g., URL hash or message ID)
  --status STATUS    Status: TODO, DOING, DONE, BLOCKED
  --title "Title"    Task title/content

Optional:
  --project PROJECT  Target project: queue|active|waiting|inbox (default: active)
  --reason "Reason"  Reason for BLOCKED status
  --dry-run          Simulate without making changes

Status Mapping:
  TODO    -> Todoist task (priority 2, project: queue)
  DOING   -> Todoist task (priority 1, project: active, due: today)
  DONE    -> Close Todoist task
  BLOCKED -> Todoist task + comment (project: waiting, due: tomorrow)

Exit Codes:
  0  Success
  1  Missing required argument
  2  Invalid status
  3  Todoist token not found
  4  Todoist API error
  5  Duplicate (task already synced)
  6  Task not found (for DONE/updates)

Examples:
  # Create new TODO item
  $(basename "$0") --item-id "abc123" --status TODO --title "Research AI agents"

  # Mark as DOING (moves to active, sets due today)
  $(basename "$0") --item-id "abc123" --status DOING --title "Research AI agents"

  # Complete task
  $(basename "$0") --item-id "abc123" --status DONE --title "Research AI agents"

  # Block with reason
  $(basename "$0") --item-id "abc123" --status BLOCKED --title "Research AI agents" --reason "Waiting for API access"

  # Dry run
  $(basename "$0") --item-id "abc123" --status TODO --title "Test" --dry-run
EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_dry_run() {
    echo "[DRY-RUN] $*"
}

# Load Todoist token
load_token() {
    if [[ ! -f "$TODOIST_TOKEN_FILE" ]]; then
        log "ERROR: Todoist token not found at $TODOIST_TOKEN_FILE"
        exit $EC_MISSING_TOKEN
    fi
    TODOIST_TOKEN=$(cat "$TODOIST_TOKEN_FILE")
}

# Load project IDs
load_projects() {
    if [[ ! -f "$TODOIST_PROJECTS_FILE" ]]; then
        log "ERROR: Projects file not found at $TODOIST_PROJECTS_FILE"
        exit $EC_MISSING_TOKEN
    fi
    PROJECT_QUEUE=$(jq -r '.queue' "$TODOIST_PROJECTS_FILE")
    PROJECT_ACTIVE=$(jq -r '.active' "$TODOIST_PROJECTS_FILE")
    PROJECT_WAITING=$(jq -r '.waiting' "$TODOIST_PROJECTS_FILE")
    PROJECT_INBOX=$(jq -r '.inbox' "$TODOIST_PROJECTS_FILE")
}

# Get project ID by name
get_project_id() {
    local project_name="$1"
    case "$project_name" in
        queue)   echo "$PROJECT_QUEUE" ;;
        active)  echo "$PROJECT_ACTIVE" ;;
        waiting) echo "$PROJECT_WAITING" ;;
        inbox)   echo "$PROJECT_INBOX" ;;
        *)       echo "$PROJECT_ACTIVE" ;;  # default
    esac
}

# Find existing Todoist task by brain item-id
# Returns task_id or empty string
find_task_by_item_id() {
    local item_id="$1"

    # 1) Check sync registry first
    if [[ -f "$SYNC_REGISTRY" ]]; then
        local entry=$(grep "\"item_id\":\"$item_id\"" "$SYNC_REGISTRY" | tail -1)
        if [[ -n "$entry" ]]; then
            echo "$entry" | jq -r '.todoist_id // empty'
            return
        fi
    fi

    # 2) Fallback: #todo router registry (event_id -> todoist_id)
    if [[ -f "$TODO_ROUTER_REGISTRY" ]]; then
        local routed=$(grep "\"event_id\":\"$item_id\"" "$TODO_ROUTER_REGISTRY" | tail -1)
        if [[ -n "$routed" ]]; then
            echo "$routed" | jq -r '.todoist_id // empty'
            return
        fi
    fi

    echo ""
}

# Save sync record to registry
save_sync_record() {
    local item_id="$1"
    local todoist_id="$2"
    local status="$3"
    local title="$4"
    
    local record=$(jq -n \
        --arg item_id "$item_id" \
        --arg todoist_id "$todoist_id" \
        --arg status "$status" \
        --arg title "$title" \
        --arg timestamp "$(date -Iseconds)" \
        '{item_id: $item_id, todoist_id: $todoist_id, status: $status, title: $title, synced_at: $timestamp}')
    
    # Append to registry
    mkdir -p "$(dirname "$SYNC_REGISTRY")"
    echo "$record" >> "$SYNC_REGISTRY"
}

# Get today's date in YYYY-MM-DD format
get_today() {
    date '+%Y-%m-%d'
}

# Get tomorrow's date in YYYY-MM-DD format
get_tomorrow() {
    date -d '+1 day' '+%Y-%m-%d' 2>/dev/null || date -v+1d '+%Y-%m-%d'
}

# ============================================================================
# Todoist API Functions
# ============================================================================

# Safe escape function for JSON strings
json_escape() {
    local s="$1"
    # Escape backslashes, quotes, and control characters
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$(echo $'\n')/\\n}"
    s="${s//$(echo $'\r')/\\r}"
    s="${s//$(echo $'\t')/\\t}"
    echo "$s"
}

# Validate due_date format (YYYY-MM-DD)
validate_due_date() {
    local due="$1"
    if [[ -z "$due" ]]; then
        return 0  # Empty is OK
    fi
    # Check YYYY-MM-DD format and length (should be exactly 10)
    if [[ ! "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [[ ${#due} -ne 10 ]]; then
        log "WARN: Invalid due_date format: '$due' (expected YYYY-MM-DD, length 10)"
        return 1
    fi
    return 0
}

# Create a new task
api_create_task() {
    local title="$1"
    local project_id="$2"
    local priority="${3:-2}"
    local due_date="${4:-}"
    
    # Validate and truncate title (Todoist limit is usually 1000+ chars, but we cap at 500 for safety)
    local safe_title="${title:0:500}"
    
    # Validate due_date format before including in payload
    if [[ -n "$due_date" ]] && ! validate_due_date "$due_date"; then
        log "WARN: Skipping invalid due_date '$due_date' for task creation"
        due_date=""
    fi
    
    # Build JSON payload with proper escaping
    local data
    data=$(jq -n \
        --arg content "$safe_title" \
        --arg project_id "$project_id" \
        --argjson priority "$priority" \
        --arg description "brain-id: $ITEM_ID" \
        '{content: $content, project_id: $project_id, priority: $priority, description: $description}')
    
    if [[ -n "$due_date" ]]; then
        data=$(echo "$data" | jq --arg due_date "$due_date" '. + {due_date: $due_date}')
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "POST $API_BASE/tasks"
        log_dry_run "Data: $data"
        echo '{"id": "dry-run-task-id"}'
        return 0
    fi
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/tasks" \
        -H "Authorization: Bearer $TODOIST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$data")
    
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
        log "ERROR: API returned HTTP $http_code"
        log "Response: $body"
        return 1
    fi
    
    echo "$body"
}

# Close a task
api_close_task() {
    local task_id="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "POST $API_BASE/tasks/$task_id/close"
        return 0
    fi
    
    local http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_BASE/tasks/$task_id/close" \
        -H "Authorization: Bearer $TODOIST_TOKEN")
    
    if [[ "$http_code" != "204" && "$http_code" != "200" ]]; then
        log "ERROR: Failed to close task (HTTP $http_code)"
        return 1
    fi
}

# Move task to different project
api_move_task() {
    local task_id="$1"
    local project_id="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "POST $API_BASE/tasks/$task_id/move to project $project_id"
        return 0
    fi
    
    local http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_BASE/tasks/$task_id/move" \
        -H "Authorization: Bearer $TODOIST_TOKEN" \
        -d "project_id=$project_id")
    
    if [[ "$http_code" != "204" && "$http_code" != "200" ]]; then
        log "ERROR: Failed to move task (HTTP $http_code)"
        return 1
    fi
}

# Update task priority and due date
api_update_task() {
    local task_id="$1"
    local priority="$2"
    local due_date="${3:-}"
    
    # Validate due_date format before including in payload
    if [[ -n "$due_date" ]] && ! validate_due_date "$due_date"; then
        log "WARN: Skipping invalid due_date '$due_date' for task update"
        due_date=""
    fi
    
    local data="{\"priority\": $priority"
    if [[ -n "$due_date" ]]; then
        data="$data, \"due_date\": \"$due_date\""
    fi
    data="$data}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "POST $API_BASE/tasks/$task_id with data: $data"
        return 0
    fi
    
    local http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_BASE/tasks/$task_id" \
        -H "Authorization: Bearer $TODOIST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$data")
    
    if [[ "$http_code" != "204" && "$http_code" != "200" ]]; then
        log "ERROR: Failed to update task (HTTP $http_code)"
        return 1
    fi
}

# Add comment to task
api_add_comment() {
    local task_id="$1"
    local content="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "POST $API_BASE/comments with content: $content"
        return 0
    fi
    
    local http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_BASE/comments" \
        -H "Authorization: Bearer $TODOIST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"task_id\": \"$task_id\", \"content\": \"$content\"}")
    
    if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
        log "WARN: Failed to add comment (HTTP $http_code)"
        # Non-fatal, continue
    fi
}

# ============================================================================
# Status Handlers
# ============================================================================

handle_todo() {
    local title="$1"
    local project="$2"
    
    project="${project:-queue}"
    local project_id=$(get_project_id "$project")
    local existing_id=$(find_task_by_item_id "$ITEM_ID")
    
    if [[ -n "$existing_id" && "$DRY_RUN" != "true" ]]; then
        log "Task already exists for item-id: $ITEM_ID (Todoist ID: $existing_id)"
        # Move to queue, set p2
        if ! api_move_task "$existing_id" "$project_id"; then
            log "WARN: Failed to move task, continuing with update"
        fi
        api_update_task "$existing_id" 2
        log "Updated existing task to TODO state"
        return $EC_SUCCESS
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -n "$existing_id" ]]; then
            log_dry_run "Would update existing task $existing_id to TODO (p2, project: $project)"
        else
            log_dry_run "Would create new task: '$title' (p2, project: $project)"
        fi
        return $EC_SUCCESS
    fi
    
    local response=$(api_create_task "$title" "$project_id" 2)
    local task_id=$(echo "$response" | jq -r '.id // empty')
    
    if [[ -z "$task_id" ]]; then
        log "ERROR: Failed to create task"
        return $EC_API_ERROR
    fi
    
    save_sync_record "$ITEM_ID" "$task_id" "TODO" "$title"
    log "Created TODO task: $task_id"
}

handle_doing() {
    local title="$1"
    local project="$2"
    
    project="${project:-active}"
    local project_id=$(get_project_id "$project")
    local existing_id=$(find_task_by_item_id "$ITEM_ID")
    local due_date=$(get_today)
    
    if [[ -n "$existing_id" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would update existing task $existing_id to DOING (p1, project: $project, due: $due_date)"
            return $EC_SUCCESS
        fi
        
        # Move to active, set p1, due today
        if ! api_move_task "$existing_id" "$project_id"; then
            log "WARN: Failed to move task, continuing with update"
        fi
        if ! api_update_task "$existing_id" 1 "$due_date"; then
            log "WARN: Failed to update due_date for task $existing_id, task may be incomplete"
            # Continue anyway - non-fatal
        fi
        log "Updated task to DOING state: $existing_id"
        return $EC_SUCCESS
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would create new task: '$title' (p1, project: $project, due: $due_date)"
        return $EC_SUCCESS
    fi
    
    local response=$(api_create_task "$title" "$project_id" 1 "$due_date")
    local task_id=$(echo "$response" | jq -r '.id // empty')
    
    if [[ -z "$task_id" ]]; then
        log "ERROR: Failed to create task (possibly due to invalid due_date '$due_date'), retrying without due..."
        # Fallback: try creating without due_date
        response=$(api_create_task "$title" "$project_id" 1 "")
        task_id=$(echo "$response" | jq -r '.id // empty')
        
        if [[ -z "$task_id" ]]; then
            log "ERROR: Failed to create task even without due_date"
            return $EC_API_ERROR
        fi
        log "Created DOING task (fallback, without due): $task_id"
    fi
    
    save_sync_record "$ITEM_ID" "$task_id" "DOING" "$title"
    log "Created DOING task: $task_id"
}

handle_done() {
    local title="$1"
    
    local existing_id=$(find_task_by_item_id "$ITEM_ID")
    
    if [[ -z "$existing_id" ]]; then
        log "WARN: No existing task found for item-id: $ITEM_ID"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would skip - task not found"
            return $EC_SUCCESS
        fi
        return $EC_NOT_FOUND
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would close task: $existing_id"
        return $EC_SUCCESS
    fi
    
    api_close_task "$existing_id"
    log "Closed task: $existing_id"
}

handle_blocked() {
    local title="$1"
    local project="$2"
    local reason="${REASON:-No reason provided}"
    
    project="${project:-waiting}"
    local project_id=$(get_project_id "$project")
    local existing_id=$(find_task_by_item_id "$ITEM_ID")
    local due_date=$(get_tomorrow)
    
    if [[ -n "$existing_id" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would update existing task $existing_id to BLOCKED"
            log_dry_run "  - Move to: $project"
            log_dry_run "  - Due: $due_date"
            log_dry_run "  - Comment: 🚫 Blocked: $reason"
            return $EC_SUCCESS
        fi
        
        if ! api_move_task "$existing_id" "$project_id"; then
            log "WARN: Failed to move task, continuing with update"
        fi
        if ! api_update_task "$existing_id" 2 "$due_date"; then
            log "WARN: Failed to update due_date for task $existing_id, task may be incomplete"
            # Continue anyway - non-fatal
        fi
        api_add_comment "$existing_id" "🚫 Blocked: $reason"
        log "Updated task to BLOCKED state: $existing_id"
        return $EC_SUCCESS
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would create new BLOCKED task: '$title'"
        log_dry_run "  - Project: $project"
        log_dry_run "  - Due: $due_date"
        log_dry_run "  - Comment: 🚫 Blocked: $reason"
        return $EC_SUCCESS
    fi
    
    local response=$(api_create_task "$title" "$project_id" 2 "$due_date")
    local task_id=$(echo "$response" | jq -r '.id // empty')
    
    if [[ -z "$task_id" ]]; then
        log "ERROR: Failed to create task (possibly due to invalid due_date '$due_date'), retrying without due..."
        # Fallback: try creating without due_date
        response=$(api_create_task "$title" "$project_id" 2 "")
        task_id=$(echo "$response" | jq -r '.id // empty')
        
        if [[ -z "$task_id" ]]; then
            log "ERROR: Failed to create task even without due_date"
            return $EC_API_ERROR
        fi
        log "Created BLOCKED task (fallback, without due): $task_id"
    fi
    
    api_add_comment "$task_id" "🚫 Blocked: $reason"
    save_sync_record "$ITEM_ID" "$task_id" "BLOCKED" "$title"
    log "Created BLOCKED task: $task_id"
}

# ============================================================================
# Main
# ============================================================================

# Parse arguments
ITEM_ID=""
STATUS=""
TITLE=""
PROJECT=""
REASON=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --item-id)
            ITEM_ID="$2"
            shift 2
            ;;
        --status)
            STATUS="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --reason)
            REASON="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit $EC_SUCCESS
            ;;
        *)
            log "ERROR: Unknown argument: $1"
            usage
            exit $EC_MISSING_ARG
            ;;
    esac
done

# Validate required args
if [[ -z "$ITEM_ID" ]]; then
    log "ERROR: --item-id is required"
    usage
    exit $EC_MISSING_ARG
fi

if [[ -z "$STATUS" ]]; then
    log "ERROR: --status is required"
    usage
    exit $EC_MISSING_ARG
fi

if [[ -z "$TITLE" ]]; then
    log "ERROR: --title is required"
    usage
    exit $EC_MISSING_ARG
fi

# Validate status
case "$STATUS" in
    TODO|DOING|DONE|BLOCKED)
        ;;
    *)
        log "ERROR: Invalid status: $STATUS (must be TODO, DOING, DONE, or BLOCKED)"
        exit $EC_INVALID_STATUS
        ;;
esac

# Load configuration
load_token
load_projects

# Handle status
case "$STATUS" in
    TODO)    handle_todo "$TITLE" "$PROJECT" ;;
    DOING)   handle_doing "$TITLE" "$PROJECT" ;;
    DONE)    handle_done "$TITLE" ;;
    BLOCKED) handle_blocked "$TITLE" "$PROJECT" ;;
esac
