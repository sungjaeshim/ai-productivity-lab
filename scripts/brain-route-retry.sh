#!/usr/bin/env bash
# brain-route-retry.sh
# Retry failed Todo/Tag route events queued by brain-telegram-autopull.sh

set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/message-guard.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECOND_BRAIN_DIR="${SECOND_BRAIN_DIR:-${WORKSPACE_DIR}/memory/second-brain}"
QUEUE_FILE="${SECOND_BRAIN_DIR}/.pending-route-queue.jsonl"
QUEUE_LOCK_FILE="${SECOND_BRAIN_DIR}/.pending-route-queue.lock"
FAILED_FILE="${SECOND_BRAIN_DIR}/.pending-route-failed.jsonl"
STAGE0_DIR="${WORKSPACE_DIR}/feedback"
STAGE0_FILE="${STAGE0_DIR}/ralph-stage0-routing.jsonl"
STAGE0_LOCK_FILE="${STAGE0_DIR}/ralph-stage0-routing.lock"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"
ACK_TELEGRAM="${BRAIN_ROUTER_ACK_TELEGRAM:-false}"

RETRY_BASE_SEC="${BRAIN_ROUTE_RETRY_BASE_SEC:-300}"
RETRY_MAX_SEC="${BRAIN_ROUTE_RETRY_MAX_SEC:-21600}"
MAX_ATTEMPTS="${BRAIN_ROUTE_RETRY_MAX_ATTEMPTS:-12}"
BATCH_LIMIT="${BRAIN_ROUTE_RETRY_BATCH_LIMIT:-20}"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

mkdir -p "$SECOND_BRAIN_DIR" "$STAGE0_DIR"
touch "$QUEUE_FILE"
touch "$STAGE0_FILE"

is_truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

send_telegram_ack() {
  local msg="$1"
  if ! is_truthy "$ACK_TELEGRAM"; then
    return 0
  fi

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel telegram --target "$TELEGRAM_TARGET"; then
    echo "[WARN] Telegram ack skipped: validation failed" >&2
    return 1
  fi

  local cmd=("$SCRIPT_DIR/send-guarded-message.sh" --channel telegram --target "$TELEGRAM_TARGET" --message "$msg" --context brain-route-retry)
  if $DRY_RUN; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}" >/dev/null 2>&1 || true
}

append_stage0_event() {
  local event_type="$1"
  local status="$2"
  local retry_id="$3"
  local route_type="$4"
  local source_ts="$5"
  local routed_raw="$6"
  local attempts="$7"
  local reason="${8:-}"
  local last_error="${9:-}"
  local created_at stage0_id entry

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  stage0_id="$(python3 - <<'PY' "$event_type" "$retry_id" "$route_type" "$source_ts" "$created_at"
import hashlib
import sys
event_type, retry_id, route_type, source_ts, created_at = sys.argv[1:6]
finger = f"{event_type}|{retry_id}|{route_type}|{source_ts}|{created_at}"
print(hashlib.sha1(finger.encode("utf-8")).hexdigest()[:20])
PY
)"
  entry="$(jq -cn \
    --arg stage0_id "$stage0_id" \
    --arg event_type "$event_type" \
    --arg status "$status" \
    --arg retry_id "$retry_id" \
    --arg route_type "$route_type" \
    --arg source_ts "$source_ts" \
    --arg routed_raw "$routed_raw" \
    --arg reason "$reason" \
    --arg last_error "$last_error" \
    --arg worker "brain-route-retry" \
    --arg created_at "$created_at" \
    --argjson attempts "$attempts" \
    '{stage0_id:$stage0_id,event_type:$event_type,status:$status,retry_id:$retry_id,route_type:$route_type,source_ts:$source_ts,routed_raw:$routed_raw,reason:$reason,last_error:$last_error,attempts:$attempts,worker:$worker,created_at:$created_at}')"

  if $DRY_RUN; then
    echo "[DRY-RUN][stage0] $entry"
    return 0
  fi

  {
    flock -x 202
    printf '%s\n' "$entry" >> "$STAGE0_FILE"
  } 202>"$STAGE0_LOCK_FILE"
}

calc_backoff() {
  local attempts="$1"
  local backoff="$RETRY_BASE_SEC"
  local i
  for ((i=1; i<attempts; i++)); do
    backoff=$((backoff * 2))
    if (( backoff >= RETRY_MAX_SEC )); then
      backoff="$RETRY_MAX_SEC"
      break
    fi
  done
  echo "$backoff"
}

run_route() {
  local route_type="$1"
  local routed_raw="$2"
  local source_ts="$3"

  case "$route_type" in
    todo)
      "$SCRIPT_DIR/brain-todo-route.sh" --raw "$routed_raw" --source-ts "$source_ts"
      ;;
    tag)
      "$SCRIPT_DIR/brain-tag-route.sh" --raw "$routed_raw" --source-ts "$source_ts"
      ;;
    *)
      echo "unsupported route_type: $route_type" >&2
      return 2
      ;;
  esac
}

if ! $DRY_RUN; then
  exec 200>"$QUEUE_LOCK_FILE"
  if ! flock -n 200; then
    echo "HEARTBEAT_OK: retry worker already running"
    exit 0
  fi
fi

tmp_queue="$(mktemp)"
now_epoch="$(date +%s)"
processed=0
success=0
failed=0
deferred=0
invalid=0
queue_size_before=$(wc -l < "$QUEUE_FILE" | tr -d ' ')

while IFS= read -r line || [[ -n "${line:-}" ]]; do
  [[ -z "${line:-}" ]] && continue

  if ! jq -e . >/dev/null 2>&1 <<< "$line"; then
    invalid=$((invalid + 1))
    printf '%s\n' "$line" >> "$tmp_queue"
    continue
  fi

  retry_id="$(jq -r '.retry_id // empty' <<< "$line")"
  route_type="$(jq -r '.route_type // empty' <<< "$line")"
  source_ts="$(jq -r '.source_ts // empty' <<< "$line")"
  raw="$(jq -r '.raw // empty' <<< "$line")"
  routed_raw="$(jq -r '.routed_raw // empty' <<< "$line")"
  reason="$(jq -r '.reason // empty' <<< "$line")"
  attempts="$(jq -r '.attempts // 0' <<< "$line")"
  next_retry_at_epoch="$(jq -r '.next_retry_at_epoch // 0' <<< "$line")"

  if [[ -z "$route_type" || -z "$source_ts" || -z "$routed_raw" ]]; then
    invalid=$((invalid + 1))
    printf '%s\n' "$line" >> "$tmp_queue"
    continue
  fi

  if (( next_retry_at_epoch > now_epoch )); then
    deferred=$((deferred + 1))
    printf '%s\n' "$line" >> "$tmp_queue"
    continue
  fi

  if (( processed >= BATCH_LIMIT )); then
    deferred=$((deferred + 1))
    printf '%s\n' "$line" >> "$tmp_queue"
    continue
  fi

  if $DRY_RUN; then
    processed=$((processed + 1))
    route_label="$(echo "$routed_raw" | awk '{print $1}')"
    echo "[DRY-RUN] would retry ${route_label:-$route_type} (retry_id: ${retry_id:-unknown}, attempts: ${attempts})"
    continue
  fi

  processed=$((processed + 1))

  if out="$(run_route "$route_type" "$routed_raw" "$source_ts" 2>&1)"; then
    success=$((success + 1))
    echo "$out"
    route_label="$(echo "$routed_raw" | awk '{print $1}')"
    send_telegram_ack "✅ 재시도 성공 ${route_label:-$route_type}"
    append_stage0_event "route_retry_success" "resolved" "${retry_id:-unknown}" "$route_type" "$source_ts" "$routed_raw" "$attempts" "$reason" ""
    continue
  fi

  failed=$((failed + 1))
  echo "$out" >&2
  new_attempts=$((attempts + 1))
  err_preview="$(echo "$out" | tail -n 2 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if (( new_attempts >= MAX_ATTEMPTS )); then
    dropped="$(jq -c \
      --arg status "dropped_after_max_attempts" \
      --arg last_error "$err_preview" \
      --arg updated_at "$now_iso" \
      --argjson attempts "$new_attempts" \
      '.attempts=$attempts | .last_error=$last_error | .updated_at=$updated_at | .status=$status' <<< "$line")"
    printf '%s\n' "$dropped" >> "$FAILED_FILE"
    route_label="$(echo "$routed_raw" | awk '{print $1}')"
    send_telegram_ack "❌ 재시도 최종실패 ${route_label:-$route_type}"
    append_stage0_event "route_retry_dropped" "failed" "${retry_id:-unknown}" "$route_type" "$source_ts" "$routed_raw" "$new_attempts" "$reason" "$err_preview"
    continue
  fi

  backoff="$(calc_backoff "$new_attempts")"
  next_retry=$((now_epoch + backoff))
  updated="$(jq -c \
    --arg last_error "$err_preview" \
    --arg updated_at "$now_iso" \
    --argjson attempts "$new_attempts" \
    --argjson next_retry_at_epoch "$next_retry" \
    '.attempts=$attempts | .last_error=$last_error | .updated_at=$updated_at | .next_retry_at_epoch=$next_retry_at_epoch' <<< "$line")"
  printf '%s\n' "$updated" >> "$tmp_queue"
  append_stage0_event "route_retry_requeued" "pending" "${retry_id:-unknown}" "$route_type" "$source_ts" "$routed_raw" "$new_attempts" "$reason" "$err_preview"
done < "$QUEUE_FILE"

if ! $DRY_RUN; then
  mv "$tmp_queue" "$QUEUE_FILE"
else
  rm -f "$tmp_queue"
fi

queue_size_after=$(wc -l < "$QUEUE_FILE" | tr -d ' ')
echo "HEARTBEAT_OK: route-retry processed=${processed} success=${success} failed=${failed} deferred=${deferred} invalid=${invalid} queue_before=${queue_size_before} queue_after=${queue_size_after}"
