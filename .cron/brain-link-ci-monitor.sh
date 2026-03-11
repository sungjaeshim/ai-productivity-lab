#!/bin/bash
# CI failure monitor for brain-link-ingest-test workflow
# Quiet mode: only alerts on NEW failures

set -euo pipefail

# Configuration
REPO="sungjaeshim/ai-productivity-lab"
WORKFLOW_FILE=".github/workflows/brain-link-ingest-test.yml"
WORKFLOW_NAME="brain-link-ingest-test"
STATE_DIR="/root/.openclaw/workspace/.state"
FAILURE_STATE="${STATE_DIR}/brain-link-ci-last-failure.txt"
ERROR_STATE="${STATE_DIR}/brain-link-ci-last-error.txt"
TELEGRAM_USER="62403941"

mkdir -p "$STATE_DIR"

# Function to send Telegram alert
send_alert() {
  local message="$1"
  message --action=send --channel=telegram --target="$TELEGRAM_USER" --message="$message"
}

# Function to dedupe errors
check_error_dedupe() {
  local fingerprint="$1"
  if [[ -f "$ERROR_STATE" ]]; then
    local last_fingerprint
    last_fingerprint=$(cat "$ERROR_STATE")
    if [[ "$fingerprint" == "$last_fingerprint" ]]; then
      return 1  # Same error, skip alert
    fi
  fi
  echo "$fingerprint" > "$ERROR_STATE"
  return 0  # New error
}

# Step 1: Resolve workflow ID
echo "Resolving workflow ID..." >&2

workflow_response=$(curl -sS -w '\n%{http_code}' \
  "https://api.github.com/repos/${REPO}/actions/workflows?per_page=100")

http_code=$(echo "$workflow_response" | tail -n1)
body=$(echo "$workflow_response" | sed '$d')

if [[ "$http_code" != "200" ]]; then
  fingerprint="GET/workflows HTTP${http_code} failed"
  if check_error_dedupe "$fingerprint"; then
    send_alert "⚠️ CI 모니터 오류: 워크플로우 조회 실패 (HTTP ${http_code})"
  fi
  exit 1
fi

workflow_id=$(echo "$body" | jq -r --arg wf "$WORKFLOW_FILE" --arg wn "$WORKFLOW_NAME" \
  '.workflows[] | select(.path == $wf or .name == $wn) | .id' | head -n1)

if [[ -z "$workflow_id" || "$workflow_id" == "null" ]]; then
  fingerprint="workflow_not_found"
  if check_error_dedupe "$fingerprint"; then
    send_alert "⚠️ CI 모니터 오류: 워크플로우를 찾을 수 없음 (${WORKFLOW_FILE})"
  fi
  exit 1
fi

echo "Workflow ID: $workflow_id" >&2

# Step 2: Fetch runs
runs_response=$(curl -sS -w '\n%{http_code}' \
  "https://api.github.com/repos/${REPO}/actions/workflows/${workflow_id}/runs?per_page=10")

http_code=$(echo "$runs_response" | tail -n1)
body=$(echo "$runs_response" | sed '$d')

if [[ "$http_code" != "200" ]]; then
  fingerprint="GET/runs HTTP${http_code} failed"
  if check_error_dedupe "$fingerprint"; then
    send_alert "⚠️ CI 모니터 오류: 실행 조회 실패 (HTTP ${http_code})"
  fi
  exit 1
fi

# Step 3: Find most recent failure
failure=$(echo "$body" | jq -r '.workflow_runs[] | select(.conclusion == "failure") | {id, head_branch, head_sha, html_url, created_at}' | jq -s 'first')

if [[ "$failure" == "null" || -z "$failure" ]]; then
  # No failures found - clean exit (quiet)
  exit 0
fi

run_id=$(echo "$failure" | jq -r '.id')
branch=$(echo "$failure" | jq -r '.head_branch')
sha=$(echo "$failure" | jq -r '.head_sha' | cut -c1-7)
html_url=$(echo "$failure" | jq -r '.html_url')
created_at=$(echo "$failure" | jq -r '.created_at')

# Step 4: Deduplicate
if [[ -f "$FAILURE_STATE" ]]; then
  last_failure_id=$(cat "$FAILURE_STATE")
  if [[ "$run_id" == "$last_failure_id" ]]; then
    # Same failure - quiet exit
    exit 0
  fi
fi

# Step 5: Send alert for NEW failure
alert_message="🚨 brain-link-ingest-test 실패 감지

Branch: ${branch}
Commit: ${sha}
시간: ${created_at}

${html_url}

로그 확인 후 fix/push하면 다음 성공으로 자동 정상화"

send_alert "$alert_message"

# Save run id
echo "$run_id" > "$FAILURE_STATE"
