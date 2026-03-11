#!/usr/bin/env bash
set -euo pipefail

AGENT_ID="${LOCAL_RESCUE_AGENT_ID:-local-rescue-q35-eval}"
MODEL_TIMEOUT="${LOCAL_RESCUE_MODEL_TIMEOUT:-20}"
HARNESS_TIMEOUT_MS="${LOCAL_RESCUE_HARNESS_TIMEOUT_MS:-45000}"
EXPECTED_USED="${LOCAL_RESCUE_EXPECTED_USED:-ollama/qwen3.5:35b-a3b}"

prompts=(
  "Reply with exactly LOCAL_RESCUE_OK."
  $'다음 형식으로만 답하라.\n1) 상태: 정상\n2) 안내: 잠시 후 다시 시도'
  "모르면 모른다고만 짧게 답하라: 오늘 미국 CPI 수치 알려줘."
)

printf '# agent=%s model_timeout=%sms harness_timeout_ms=%s expected=%s\n' \
  "$AGENT_ID" "$MODEL_TIMEOUT" "$HARNESS_TIMEOUT_MS" "$EXPECTED_USED"
printf 'CASE\tRESULT\tUSED\tDURATION_MS\tDETAIL\n'

run_case() {
  local label="$1"
  local prompt="$2"
  local attempts=0
  local name="q35-rescue-eval-${label}-$(date +%s)-$RANDOM"
  local add_json add_rc job_id run_out run_rc runs_json entry
  local used_provider used_model used duration status summary error detail result

  while :; do
    set +e
    add_json="$(
      openclaw cron add \
        --name "$name" \
        --agent "$AGENT_ID" \
        --session isolated \
        --no-deliver \
        --message "$prompt" \
        --timeout-seconds "$MODEL_TIMEOUT" \
        --thinking off \
        --light-context \
        --at 20m \
        --json 2>&1
    )"
    add_rc=$?
    set -e

    if [[ $add_rc -eq 0 || $attempts -ge 1 ]]; then
      break
    fi

    if [[ "$add_json" == *"gateway closed (1006"* ]]; then
      attempts=$((attempts + 1))
      sleep 2
      continue
    fi

    break
  done

  if [[ $add_rc -ne 0 ]]; then
    detail="$(printf '%s' "$add_json" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-160)"
    printf '%s\tFAIL\tadd-failed\t-1\t%s\n' "$label" "$detail"
    return
  fi

  job_id="$(jq -r '.id // .job.id // empty' <<< "$add_json" 2>/dev/null || true)"
  if [[ -z "$job_id" ]]; then
    detail="$(printf '%s' "$add_json" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-160)"
    printf '%s\tFAIL\tadd-parse\t-1\t%s\n' "$label" "$detail"
    return
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
    printf '%s\tFAIL\tno-entry\t-1\t%s\n' "$label" "$detail"
    return
  fi

  used_provider="$(jq -r '.provider // ""' <<< "$entry")"
  used_model="$(jq -r '.model // ""' <<< "$entry")"
  used="${used_provider}/${used_model}"
  duration="$(jq -r '.durationMs // -1' <<< "$entry")"
  status="$(jq -r '.status // ""' <<< "$entry")"
  summary="$(jq -r '.summary // ""' <<< "$entry" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"
  error="$(jq -r '.error // ""' <<< "$entry" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"

  result="FAIL"
  detail="$error"

  case "$label" in
    smoke)
      if [[ "$status" == "ok" && "$used" == "$EXPECTED_USED" && "$summary" == *"LOCAL_RESCUE_OK"* ]]; then
        result="PASS"
        detail="$summary"
      fi
      ;;
    format)
      if [[ "$status" == "ok" && "$used" == "$EXPECTED_USED" && "$summary" == *"1) 상태: 정상"* && "$summary" == *"2) 안내: 잠시 후 다시 시도"* ]]; then
        result="PASS"
        detail="$summary"
      fi
      ;;
    failsoft)
      if [[ "$status" == "ok" && "$used" == "$EXPECTED_USED" && "$summary" != "" ]]; then
        result="PASS"
        detail="$summary"
      fi
      ;;
  esac

  if [[ "$status" == "ok" && "$used" != "$EXPECTED_USED" ]]; then
    detail="wrong-model:${used}"
  fi

  if [[ -z "$detail" ]]; then
    detail="empty"
  fi

  if [[ $run_rc -ne 0 && "$result" != "PASS" && "$detail" == "empty" ]]; then
    detail="$(printf '%s' "$run_out" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$result" "$used" "$duration" "$detail"
  sleep 1
}

run_case smoke "${prompts[0]}"
run_case format "${prompts[1]}"
run_case failsoft "${prompts[2]}"
