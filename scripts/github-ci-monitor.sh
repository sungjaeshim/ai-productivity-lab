#!/usr/bin/env bash
set -euo pipefail

# GitHub CI failure monitor - brain-link-ingest-test
# Quiet mode: only alerts on NEW failures or ERROR state changes

REPO="sungjaeshim/ai-productivity-lab"
WORKFLOW_NAME="brain-link-ingest-test"
STATE_DIR="/root/.openclaw/workspace/.state"
LAST_FAILURE_FILE="$STATE_DIR/brain-link-ci-last-failure.txt"
LAST_ERROR_FILE="$STATE_DIR/brain-link-ci-last-error.txt"
TELEGRAM_TARGET="62403941"

mkdir -p "$STATE_DIR"

# Helper: dedup errors by fingerprint
error_fingerprint() {
    local http_code="$1"
    local endpoint="$2"
    local error_msg="$3"
    # Short error: first 50 chars, space normalized
    local short_error=$(echo "$error_msg" | head -c 50 | tr -s ' ')
    echo "${http_code}|${endpoint}|${short_error}"
}

# Step 1: Resolve workflow ID
WORKFLOW_RESPONSE=$(curl -sS -w '\n%{http_code}' "https://api.github.com/repos/${REPO}/actions/workflows?per_page=100")
WORKFLOW_HTTP=$(echo "$WORKFLOW_RESPONSE" | tail -n 1)
WORKFLOW_BODY=$(echo "$WORKFLOW_RESPONSE" | head -n -1)

# Transient GitHub edge errors: retry once before alerting
if [ "$WORKFLOW_HTTP" = "502" ] || [ "$WORKFLOW_HTTP" = "503" ] || [ "$WORKFLOW_HTTP" = "504" ]; then
    sleep 2
    WORKFLOW_RESPONSE=$(curl -sS -w '\n%{http_code}' "https://api.github.com/repos/${REPO}/actions/workflows?per_page=100")
    WORKFLOW_HTTP=$(echo "$WORKFLOW_RESPONSE" | tail -n 1)
    WORKFLOW_BODY=$(echo "$WORKFLOW_RESPONSE" | head -n -1)
fi

if [ "$WORKFLOW_HTTP" != "200" ]; then
    FP=$(error_fingerprint "$WORKFLOW_HTTP" "workflow_list" "$WORKFLOW_BODY")
    LAST_FP="none"
    if [ -f "$LAST_ERROR_FILE" ]; then
        LAST_FP=$(cat "$LAST_ERROR_FILE")
    fi
    if [ "$FP" != "$LAST_FP" ]; then
        echo "$FP" > "$LAST_ERROR_FILE"
        echo "🚨 GitHub CI monitor error: HTTP $WORKFLOW_HTTP fetching workflow list"
    fi
    exit 0
fi

WORKFLOW_ID=$(echo "$WORKFLOW_BODY" | jq -r --arg wf_name "$WORKFLOW_NAME" '
    .workflows[] |
    select(.path == ".github/workflows/'"$WORKFLOW_NAME"'.yml" or .name == "'"$WORKFLOW_NAME"'") |
    .id
')

if [ -z "$WORKFLOW_ID" ] || [ "$WORKFLOW_ID" = "null" ]; then
    echo "Workflow not found: $WORKFLOW_NAME" >&2
    exit 0
fi

# Step 2: Fetch runs
RUNS_RESPONSE=$(curl -sS -w '\n%{http_code}' "https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW_ID}/runs?per_page=10")
RUNS_HTTP=$(echo "$RUNS_RESPONSE" | tail -n 1)
RUNS_BODY=$(echo "$RUNS_RESPONSE" | head -n -1)

# Transient GitHub edge errors: retry once before alerting
if [ "$RUNS_HTTP" = "502" ] || [ "$RUNS_HTTP" = "503" ] || [ "$RUNS_HTTP" = "504" ]; then
    sleep 2
    RUNS_RESPONSE=$(curl -sS -w '\n%{http_code}' "https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW_ID}/runs?per_page=10")
    RUNS_HTTP=$(echo "$RUNS_RESPONSE" | tail -n 1)
    RUNS_BODY=$(echo "$RUNS_RESPONSE" | head -n -1)
fi

if [ "$RUNS_HTTP" != "200" ]; then
    FP=$(error_fingerprint "$RUNS_HTTP" "runs" "$RUNS_BODY")
    LAST_FP="none"
    if [ -f "$LAST_ERROR_FILE" ]; then
        LAST_FP=$(cat "$LAST_ERROR_FILE")
    fi
    if [ "$FP" != "$LAST_FP" ]; then
        echo "$FP" > "$LAST_ERROR_FILE"
        echo "🚨 GitHub CI monitor error: HTTP $RUNS_HTTP fetching runs"
    fi
    exit 0
fi

# Step 3: Find most recent failure
FAILED_RUN=$(echo "$RUNS_BODY" | jq -r '.workflow_runs[] | select(.conclusion == "failure") | {id, head_branch, head_sha, html_url, created_at} | [(.id|tostring), .head_branch, (.head_sha[0:7]), .html_url, .created_at] | @tsv' | head -n 1)

if [ -z "$FAILED_RUN" ]; then
    # No failures - quiet mode, do nothing
    exit 0
fi

# Parse failed run
IFS=$'\t' read -r RUN_ID BRANCH SHA7 URL CREATED_AT <<< "$FAILED_RUN"

# Step 4: Deduplicate
LAST_FAILURE_ID=""
if [ -f "$LAST_FAILURE_FILE" ]; then
    LAST_FAILURE_ID=$(cat "$LAST_FAILURE_FILE")
fi

if [ "$RUN_ID" = "$LAST_FAILURE_ID" ]; then
    # Already reported - quiet mode
    exit 0
fi

# Step 5: New failure - send alert
# Convert UTC to KST (Asia/Seoul = UTC+9)
CREATED_KST=$(date -d "$CREATED_AT 9 hours" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$CREATED_AT (UTC)")

cat > /tmp/brain-link-ci-alert.txt << EOF
🚨 brain-link-ingest-test 실패 감지

Branch: $BRANCH
SHA: $SHA7
URL: $URL
시간: $CREATED_KST

로그 확인 후 fix/push하면 다음 성공으로 자동 정상화
EOF

message send --channel telegram --to "$TELEGRAM_TARGET" "$(cat /tmp/brain-link-ci-alert.txt)"
rm -f /tmp/brain-link-ci-alert.txt

# Step 6: Update state
echo "$RUN_ID" > "$LAST_FAILURE_FILE"

exit 0
