#!/usr/bin/env bash
# Archived 2026-03-06.
# Replacement: github-ci-monitor.sh
# Monitor brain-link-ingest-test CI failures for sungjaeshim/ai-productivity-lab
# Quiet mode: only alerts on NEW failures or error state changes

set -e

REPO="sungjaeshim/ai-productivity-lab"
WORKFLOW_NAME="brain-link-ingest-test"
STATE_DIR="/root/.openclaw/workspace/.state"
FAILURE_STATE_FILE="${STATE_DIR}/brain-link-ci-last-failure.txt"
ERROR_STATE_FILE="${STATE_DIR}/brain-link-ci-last-error.txt"
TELEGRAM_CHAT_ID="62403941"

# Helper: GET with HTTP code in footer
github_get() {
  local url="$1"
  curl -sS -w '\n%{http_code}' "$url"
}

# 1. Resolve workflow ID robustly
echo "[1/5] Resolving workflow ID..."
WORKFLOW_RESPONSE=$(github_get "https://api.github.com/repos/${REPO}/actions/workflows?per_page=100")
HTTP_CODE=$(echo "$WORKFLOW_RESPONSE" | tail -n1)
BODY=$(echo "$WORKFLOW_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  ERROR_FINGERPRINT="GET_WORKFLOWS_${HTTP_CODE}_$(echo "$BODY" | jq -r '.message // .error // "unknown' 2>/dev/null || echo "unknown")"
  LAST_ERROR=$(cat "$ERROR_STATE_FILE" 2>/dev/null || echo "")

  if [ "$ERROR_FINGERPRINT" != "$LAST_ERROR" ]; then
    echo "$ERROR_FINGERPRINT" > "$ERROR_STATE_FILE"
    openclaw message send --channel=telegram --to="$TELEGRAM_CHAT_ID" --message="⚠️ CI Monitor Error: Failed to list workflows (HTTP $HTTP_CODE)"
  fi
  exit 1
fi

# Find workflow by path OR name
WORKFLOW_ID=$(echo "$BODY" | jq -r ".workflows[] | select(.path == \".github/workflows/${WORKFLOW_NAME}.yml\" or .name == \"$WORKFLOW_NAME\") | .id" | head -n1)

if [ -z "$WORKFLOW_ID" ] || [ "$WORKFLOW_ID" = "null" ]; then
  ERROR_FINGERPRINT="WORKFLOW_NOT_FOUND"
  LAST_ERROR=$(cat "$ERROR_STATE_FILE" 2>/dev/null || echo "")

  if [ "$ERROR_FINGERPRINT" != "$LAST_ERROR" ]; then
    echo "$ERROR_FINGERPRINT" > "$ERROR_STATE_FILE"
    openclaw message send --channel=telegram --to="$TELEGRAM_CHAT_ID" --message="⚠️ CI Monitor Error: Workflow '$WORKFLOW_NAME' not found"
  fi
  exit 1
fi

echo "[2/5] Workflow ID: $WORKFLOW_ID"

# 2. Fetch recent runs
echo "[3/5] Fetching workflow runs..."
RUNS_RESPONSE=$(github_get "https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW_ID}/runs?per_page=10")
HTTP_CODE=$(echo "$RUNS_RESPONSE" | tail -n1)
BODY=$(echo "$RUNS_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  ERROR_FINGERPRINT="GET_RUNS_${HTTP_CODE}_$(echo "$BODY" | jq -r '.message // .error // "unknown' 2>/dev/null || echo "unknown")"
  LAST_ERROR=$(cat "$ERROR_STATE_FILE" 2>/dev/null || echo "")

  if [ "$ERROR_FINGERPRINT" != "$LAST_ERROR" ]; then
    echo "$ERROR_FINGERPRINT" > "$ERROR_STATE_FILE"
    openclaw message send --channel=telegram --to="$TELEGRAM_CHAT_ID" --message="⚠️ CI Monitor Error: Failed to fetch runs (HTTP $HTTP_CODE)"
  fi
  exit 1
fi

# Clear any previous error state on success
> "$ERROR_STATE_FILE" 2>/dev/null || true

# 3. Check most recent run status
MOST_RECENT_RUN=$(echo "$BODY" | jq -r '.workflow_runs[0] | "\(.conclusion) \(.id) \(.head_branch) \(.head_sha) \(.html_url) \(.created_at)"')

RECENT_CONCLUSION=$(echo "$MOST_RECENT_RUN" | awk '{print $1}')
RECENT_RUN_ID=$(echo "$MOST_RECENT_RUN" | awk '{print $2}')
RECENT_BRANCH=$(echo "$MOST_RECENT_RUN" | awk '{print $3}')
RECENT_SHA=$(echo "$MOST_RECENT_RUN" | awk '{print $4}')
RECENT_URL=$(echo "$MOST_RECENT_RUN" | awk '{print $5}')
RECENT_TIME=$(echo "$MOST_RECENT_RUN" | awk '{print $6}')

# If most recent run succeeded, keep failure state (dedupe anchor) and exit
if [ "$RECENT_CONCLUSION" = "success" ]; then
  echo "[4/5] Most recent run succeeded. Keep failure state for dedupe."
  exit 0
fi

# Check if most recent run is a failure
if [ "$RECENT_CONCLUSION" != "failure" ]; then
  echo "[4/5] Most recent run status: $RECENT_CONCLUSION. Not monitoring."
  exit 0
fi

# 4. Deduplicate by run ID
LAST_FAILURE_ID=$(cat "$FAILURE_STATE_FILE" 2>/dev/null || echo "")

if [ "$RECENT_RUN_ID" = "$LAST_FAILURE_ID" ]; then
  echo "[5/5] Failure already reported ($RECENT_RUN_ID). Quiet."
  exit 0
fi

# Prepare failure details for alert
SHA7=$(echo "$RECENT_SHA" | cut -c1-7)
KST_TIME=$(date -d "$RECENT_TIME UTC +9 hours" "+%Y-%m-%d %H:%M:%S KST" 2>/dev/null || echo "$RECENT_TIME")

BRANCH="$RECENT_BRANCH"
HTML_URL="$RECENT_URL"
RUN_ID="$RECENT_RUN_ID"

# 5. New failure: send alert
echo "[5/5] NEW failure detected ($RUN_ID). Sending alert..."

openclaw message send --channel=telegram --to="$TELEGRAM_CHAT_ID" --message="🚨 brain-link-ingest-test 실패 감지

Branch: $BRANCH
Commit: $SHA7
시간: $KST_TIME
URL: $HTML_URL

로그 확인 후 fix/push하면 다음 성공으로 자동 정상화"

# Update state
echo "$RUN_ID" > "$FAILURE_STATE_FILE"

echo "Alert sent. State updated."
