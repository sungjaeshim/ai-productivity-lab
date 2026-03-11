#!/usr/bin/env bash
set -euo pipefail

PROMPT="${LOCAL_RESCUE_PROMPT:-Reply with exactly LOCAL_RESCUE_OK.}"
MODEL_TIMEOUT="${LOCAL_RESCUE_MODEL_TIMEOUT:-20}"
HARNESS_TIMEOUT_MS="${LOCAL_RESCUE_HARNESS_TIMEOUT_MS:-45000}"

models=("$@")
if [[ ${#models[@]} -eq 0 ]]; then
  models=(
    "ollama/qwen3:14b"
    "ollama/hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q3_K_M"
    "ollama/hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q4_K_M"
  )
fi

printf 'MODEL\tRESULT\tUSED\tDURATION_MS\tDETAIL\n'

for model in "${models[@]}"; do
  name="local-rescue-eval-$(date +%s)-$RANDOM"

  set +e
  add_json="$(
    openclaw cron add \
      --name "$name" \
      --agent local-rescue \
      --session isolated \
      --no-deliver \
      --message "$PROMPT" \
      --model "$model" \
      --timeout-seconds "$MODEL_TIMEOUT" \
      --thinking off \
      --light-context \
      --at 20m \
      --json 2>&1
  )"
  add_rc=$?
  set -e

  if [[ $add_rc -ne 0 ]]; then
    detail="$(printf '%s' "$add_json" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-160)"
    printf '%s\tFAIL\tadd-failed\t-1\t%s\n' "$model" "$detail"
    continue
  fi

  job_id="$(jq -r '.id // .job.id // empty' <<< "$add_json" 2>/dev/null || true)"
  if [[ -z "$job_id" ]]; then
    detail="$(printf '%s' "$add_json" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-160)"
    printf '%s\tFAIL\tadd-parse\t-1\t%s\n' "$model" "$detail"
    continue
  fi

  set +e
  run_out="$(
    openclaw cron run "$job_id" --expect-final --timeout "$HARNESS_TIMEOUT_MS" 2>&1
  )"
  run_rc=$?
  set -e

  runs_json="$(openclaw cron runs --id "$job_id" --limit 1 2>&1 || true)"
  entry="$(jq -c '.entries[0] // empty' <<< "$runs_json" 2>/dev/null || true)"
  openclaw cron rm "$job_id" >/dev/null 2>&1 || true

  if [[ -z "$entry" ]]; then
    detail="$(printf '%s | %s' "$run_out" "$runs_json" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-160)"
    printf '%s\tFAIL\tno-entry\t-1\t%s\n' "$model" "$detail"
    continue
  fi

  used_provider="$(jq -r '.provider // ""' <<< "$entry")"
  used_model="$(jq -r '.model // ""' <<< "$entry")"
  used="${used_provider}/${used_model}"
  duration="$(jq -r '.durationMs // -1' <<< "$entry")"
  status="$(jq -r '.status // ""' <<< "$entry")"
  summary="$(jq -r '.summary // ""' <<< "$entry" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-120)"
  error="$(jq -r '.error // ""' <<< "$entry" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-120)"

  result="FAIL"
  detail="$error"
  if [[ "$status" == "ok" && "$summary" == *"LOCAL_RESCUE_OK"* ]]; then
    result="PASS"
    detail="$summary"
  fi

  if [[ -z "$detail" ]]; then
    detail="empty"
  fi

  if [[ $run_rc -ne 0 && "$result" != "PASS" && "$detail" == "empty" ]]; then
    detail="$(printf '%s' "$run_out" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-120)"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$model" "$result" "$used" "$duration" "$detail"
done
