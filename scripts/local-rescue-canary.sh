#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="/root/.openclaw/openclaw.json"
MODEL="${1:-qwen3.5:9b-q4_K_M}"
BASE_URL="${OLLAMA_BASE_URL:-$(jq -r '.models.providers.ollama.baseUrl' "$CONFIG_PATH")}"
PROMPT="${LOCAL_RESCUE_PROMPT:-Reply with exactly LOCAL_RESCUE_OK.}"
AGENT_ID="${LOCAL_RESCUE_AGENT_ID:-local-rescue}"
MODEL_TIMEOUT="${LOCAL_RESCUE_MODEL_TIMEOUT:-45}"
HARNESS_TIMEOUT_MS="${LOCAL_RESCUE_HARNESS_TIMEOUT_MS:-70000}"
EXPECTED_USED="${LOCAL_RESCUE_EXPECTED_USED:-ollama/qwen3.5:9b-q4_K_M}"

echo "[1/3] Checking Ollama version at ${BASE_URL}"
curl -fsS --max-time 5 "${BASE_URL}/api/version"
echo

echo "[2/3] Checking model availability: ${MODEL}"
curl -fsS --max-time 10 "${BASE_URL}/api/tags" \
  | jq -e --arg model "$MODEL" '
      .models[]?
      | select((.name // .model) == $model or (.model // "") == $model)
    ' >/dev/null
echo "model found: ${MODEL}"

echo "[3/3] Running isolated local-rescue smoke prompt"
name="local-rescue-canary-$(date +%s)-$RANDOM"
add_json="$(
  openclaw cron add \
    --name "$name" \
    --agent "$AGENT_ID" \
    --session isolated \
    --no-deliver \
    --light-context \
    --thinking off \
    --message "${PROMPT}" \
    --timeout-seconds "${MODEL_TIMEOUT}" \
    --at 20m \
    --json
)"
job_id="$(jq -r '.id // .job.id // empty' <<< "$add_json")"
if [[ -z "$job_id" ]]; then
  echo "$add_json"
  echo "failed: could not parse cron job id" >&2
  exit 1
fi

trap 'openclaw cron rm "$job_id" >/dev/null 2>&1 || true' EXIT

openclaw cron run "$job_id" --expect-final --timeout "${HARNESS_TIMEOUT_MS}" >/dev/null
runs_json="$(openclaw cron runs --id "$job_id" --limit 1)"
entry="$(jq -c '.entries[0] // empty' <<< "$runs_json")"
if [[ -z "$entry" ]]; then
  echo "$runs_json"
  echo "failed: no cron run entry found" >&2
  exit 1
fi

used_provider="$(jq -r '.provider // ""' <<< "$entry")"
used_model="$(jq -r '.model // ""' <<< "$entry")"
used="${used_provider}/${used_model}"
summary="$(jq -r '.summary // ""' <<< "$entry")"
status="$(jq -r '.status // ""' <<< "$entry")"

echo "$runs_json"

if [[ "$status" != "ok" ]]; then
  echo "failed: cron run status=${status}" >&2
  exit 1
fi

if [[ "$used" != "$EXPECTED_USED" ]]; then
  echo "failed: expected ${EXPECTED_USED}, got ${used}" >&2
  exit 1
fi

if [[ "$summary" != *"LOCAL_RESCUE_OK"* ]]; then
  echo "failed: expected LOCAL_RESCUE_OK summary, got ${summary}" >&2
  exit 1
fi
