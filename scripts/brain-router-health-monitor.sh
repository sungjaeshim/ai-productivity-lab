#!/usr/bin/env bash
# brain-router-health-monitor.sh
# Check stability of Telegram -> Router pipelines and alert only on state change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u

CHECKPOINT_FILE="${WORKSPACE_DIR}/memory/second-brain/.brain-autopull-checkpoint.json"
TODO_REGISTRY="${WORKSPACE_DIR}/memory/second-brain/.todo-router-registry.jsonl"
TAG_REGISTRY="${WORKSPACE_DIR}/memory/second-brain/.tag-router-registry.jsonl"
PENDING_URL_QUEUE="${WORKSPACE_DIR}/memory/second-brain/.pending-queue.jsonl"
PENDING_MEMO_QUEUE="${WORKSPACE_DIR}/memory/second-brain/.pending-note-queue.jsonl"
ROUTE_RETRY_QUEUE="${WORKSPACE_DIR}/memory/second-brain/.pending-route-queue.jsonl"
STATE_FILE="${WORKSPACE_DIR}/.state/brain-router-monitor-state.json"
JOBS_FILE="/root/.openclaw/cron/jobs.json"
AUTOPULL_JOB_ID="e53379bf-067e-477a-8614-98eed8fe0f87"
AUTOPULL_JOB_NAME="🔄 Brain Telegram Autopull"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_PATH:-/root/.openclaw/openclaw.json}"
MEMORY_AGENT_ID="${BRAIN_MON_MEMORY_AGENT_ID:-main}"
MEMORY_HEALTH_QUERY="${BRAIN_MON_MEMORY_QUERY:-시스템 설정}"

DISCORD_TARGET="${DISCORD_SYSTEM_HEALTH:-1477310512680276080}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"

STALE_WARN_MIN="${BRAIN_MON_STALE_WARN_MIN:-25}"
STALE_CRIT_MIN="${BRAIN_MON_STALE_CRIT_MIN:-40}"
QUEUE_WARN_COUNT="${BRAIN_MON_QUEUE_WARN_COUNT:-5}"
QUEUE_CRIT_COUNT="${BRAIN_MON_QUEUE_CRIT_COUNT:-20}"
ROUTE_QUEUE_WARN_COUNT="${BRAIN_MON_ROUTE_QUEUE_WARN_COUNT:-1}"
ROUTE_QUEUE_CRIT_COUNT="${BRAIN_MON_ROUTE_QUEUE_CRIT_COUNT:-5}"
REPEAT_WARN_MIN="${BRAIN_MON_REPEAT_WARN_MIN:-120}"
REPEAT_CRIT_MIN="${BRAIN_MON_REPEAT_CRIT_MIN:-30}"
MEMORY_FAIL_CRIT_STREAK="${BRAIN_MON_MEMORY_FAIL_CRIT_STREAK:-3}"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

mkdir -p "$(dirname "$STATE_FILE")"

now_epoch=$(date +%s)
crit=()
warn=()
info=()
checkpoint_age_min=-1
ollama_base_url=""
memory_fail_streak=0

# 1) Checkpoint freshness
if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  crit+=("checkpoint_missing")
else
  last_ts=$(jq -r '.last_ts // empty' "$CHECKPOINT_FILE" 2>/dev/null || true)
  if [[ -z "$last_ts" ]]; then
    crit+=("checkpoint_invalid")
  else
    age_sec=$(python3 - <<'PY' "$last_ts" "$now_epoch"
import datetime,sys
last_ts=sys.argv[1]
now=int(sys.argv[2])
try:
    dt=datetime.datetime.fromisoformat(last_ts.replace('Z','+00:00'))
    age=max(0, now - int(dt.timestamp()))
    print(age)
except Exception:
    print(-1)
PY
)
    if [[ "$age_sec" == "-1" ]]; then
      crit+=("checkpoint_parse_error")
    else
      age_min=$((age_sec / 60))
      checkpoint_age_min=$age_min
      if (( age_min >= STALE_CRIT_MIN )); then
        crit+=("autopull_stale_${age_min}m")
      elif (( age_min >= STALE_WARN_MIN )); then
        warn+=("autopull_stale_${age_min}m")
      else
        info+=("autopull_age_${age_min}m")
      fi
    fi
  fi
fi

# 2) Pending queue backlog
queue_url_count=0
queue_memo_count=0
queue_route_count=0
[[ -f "$PENDING_URL_QUEUE" ]] && queue_url_count=$(wc -l < "$PENDING_URL_QUEUE" | tr -d ' ')
[[ -f "$PENDING_MEMO_QUEUE" ]] && queue_memo_count=$(wc -l < "$PENDING_MEMO_QUEUE" | tr -d ' ')
[[ -f "$ROUTE_RETRY_QUEUE" ]] && queue_route_count=$(wc -l < "$ROUTE_RETRY_QUEUE" | tr -d ' ')
queue_total=$((queue_url_count + queue_memo_count + queue_route_count))
if (( queue_route_count >= ROUTE_QUEUE_CRIT_COUNT )); then
  crit+=("route_retry_queue_${queue_route_count}")
elif (( queue_route_count >= ROUTE_QUEUE_WARN_COUNT )); then
  warn+=("route_retry_queue_${queue_route_count}")
else
  info+=("route_retry_queue_${queue_route_count}")
fi
if (( queue_total >= QUEUE_CRIT_COUNT )); then
  crit+=("pending_queue_${queue_total}")
elif (( queue_total >= QUEUE_WARN_COUNT )); then
  warn+=("pending_queue_${queue_total}")
else
  info+=("pending_queue_${queue_total}")
fi

# 3) Autopull cron state
if [[ -f "$JOBS_FILE" ]]; then
  resolved_autopull_id=$(jq -r --arg id "$AUTOPULL_JOB_ID" --arg name "$AUTOPULL_JOB_NAME" '
    ( .jobs[] | select(.id==$id) | .id ) //
    ( .jobs[] | select(.name==$name) | .id ) // ""
  ' "$JOBS_FILE" 2>/dev/null || true)

  if [[ -z "$resolved_autopull_id" ]]; then
    if (( checkpoint_age_min >= 0 && checkpoint_age_min < STALE_WARN_MIN )); then
      info+=("autopull_job_missing_bootstrap")
    else
      warn+=("autopull_job_missing")
    fi
  else
    last_status=$(jq -r --arg id "$resolved_autopull_id" '.jobs[] | select(.id==$id) | .state.lastRunStatus // .state.lastStatus // empty' "$JOBS_FILE" 2>/dev/null || true)
    cons_err=$(jq -r --arg id "$resolved_autopull_id" '.jobs[] | select(.id==$id) | .state.consecutiveErrors // 0' "$JOBS_FILE" 2>/dev/null || echo 0)

    if [[ -z "$last_status" ]]; then
      if (( checkpoint_age_min >= 0 && checkpoint_age_min < STALE_WARN_MIN )); then
        info+=("autopull_state_missing_bootstrap")
      else
        warn+=("autopull_state_missing")
      fi
    else
      if [[ "$last_status" != "ok" ]]; then
        if [[ "$cons_err" =~ ^[0-9]+$ ]] && (( cons_err >= 3 )); then
          crit+=("autopull_status_${last_status}_err${cons_err}")
        else
          warn+=("autopull_status_${last_status}_err${cons_err}")
        fi
      else
        info+=("autopull_status_ok")
      fi
    fi
  fi
fi

# 4) Registry format sanity
for reg in "$TODO_REGISTRY" "$TAG_REGISTRY"; do
  [[ ! -f "$reg" ]] && continue
  if ! tail -n 1 "$reg" | jq -e . >/dev/null 2>&1; then
    warn+=("registry_tail_invalid_$(basename "$reg")")
  fi
done

prev_level="ok"
prev_fp=""
prev_alert_epoch=0
prev_memory_fail_streak=0
if [[ -f "$STATE_FILE" ]]; then
  prev_level=$(jq -r '.level // "ok"' "$STATE_FILE" 2>/dev/null || echo "ok")
  prev_fp=$(jq -r '.fingerprint // ""' "$STATE_FILE" 2>/dev/null || echo "")
  prev_alert_epoch=$(jq -r '.last_alert_epoch // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  prev_memory_fail_streak=$(jq -r '.memory_fail_streak // 0' "$STATE_FILE" 2>/dev/null || echo 0)
fi

# 5) Remote Ollama memory path health
if [[ -f "$OPENCLAW_CONFIG_FILE" ]]; then
  ollama_base_url=$(jq -r '.models.providers.ollama.baseUrl // empty' "$OPENCLAW_CONFIG_FILE" 2>/dev/null || true)
fi
if [[ -z "$ollama_base_url" ]]; then
  warn+=("ollama_baseurl_missing")
else
  info+=("ollama_baseurl_set")
fi

memory_ok=false
for attempt in 1 2; do
  if openclaw memory search --agent "$MEMORY_AGENT_ID" --query "$MEMORY_HEALTH_QUERY" --max-results 1 --json >/dev/null 2>&1; then
    memory_ok=true
    break
  fi
  sleep 2
done

if $memory_ok; then
  memory_fail_streak=0
  info+=("memory_search_ok")
else
  if [[ "$prev_memory_fail_streak" =~ ^[0-9]+$ ]]; then
    memory_fail_streak=$((prev_memory_fail_streak + 1))
  else
    memory_fail_streak=1
  fi
  if (( memory_fail_streak >= MEMORY_FAIL_CRIT_STREAK )); then
    crit+=("memory_search_fail_streak_${memory_fail_streak}")
  else
    warn+=("memory_search_fail_streak_${memory_fail_streak}")
  fi
fi

level="ok"
if (( ${#crit[@]} > 0 )); then
  level="critical"
elif (( ${#warn[@]} > 0 )); then
  level="warn"
fi

issues=""
if [[ "$level" == "critical" ]]; then
  issues="${crit[*]}"
elif [[ "$level" == "warn" ]]; then
  issues="${warn[*]}"
else
  issues="ok"
fi

fingerprint=$(printf '%s|%s' "$level" "$issues" | sha1sum | awk '{print $1}')

should_alert=false
if [[ "$level" == "ok" ]]; then
  if [[ "$prev_level" != "ok" ]]; then
    should_alert=true
  fi
else
  if [[ "$fingerprint" != "$prev_fp" ]]; then
    should_alert=true
  else
    elapsed_min=$(( (now_epoch - prev_alert_epoch) / 60 ))
    if [[ "$level" == "critical" ]] && (( elapsed_min >= REPEAT_CRIT_MIN )); then
      should_alert=true
    fi
    if [[ "$level" == "warn" ]] && (( elapsed_min >= REPEAT_WARN_MIN )); then
      should_alert=true
    fi
  fi
fi

send_discord() {
  local msg="$1"
  if ! validate_message_params --channel discord --target "$DISCORD_TARGET"; then
    echo "[WARN] Discord send skipped: validation failed" >&2
    return 1
  fi

  local cmd=("$SCRIPT_DIR/send-guarded-message.sh" --channel discord --target "$DISCORD_TARGET" --message "$msg" --context brain-router-health-monitor)
  if $DRY_RUN; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}" >/dev/null 2>&1 || true
}

send_telegram() {
  local msg="$1"
  if ! validate_message_params --channel telegram --target "$TELEGRAM_TARGET"; then
    echo "[WARN] Telegram send skipped: validation failed" >&2
    return 1
  fi

  local cmd=("$SCRIPT_DIR/send-guarded-message.sh" --channel telegram --target "$TELEGRAM_TARGET" --message "$msg" --context brain-router-health-monitor)
  if $DRY_RUN; then
    cmd+=(--dry-run)
  fi
  "${cmd[@]}" >/dev/null 2>&1 || true
}

if $should_alert; then
  if [[ "$level" == "ok" ]]; then
    msg="✅ brain 라우팅 복구\n- 상태: 정상\n- pending_queue: ${queue_total} (url:${queue_url_count}, memo:${queue_memo_count}, route:${queue_route_count})"
    send_discord "$msg"
    send_telegram "$msg"
    echo "RECOVERY_SENT"
  else
    msg="⚠️ brain 라우팅 경고 (${level})\n- issues: ${issues}\n- pending_queue: ${queue_total} (url:${queue_url_count}, memo:${queue_memo_count}, route:${queue_route_count})\n- checkpoint: ${CHECKPOINT_FILE}"
    send_discord "$msg"
    if [[ "$level" == "critical" ]]; then
      send_telegram "$msg"
    fi
    echo "ALERT_SENT:$level"
  fi
else
  echo "HEARTBEAT_OK"
fi

next_alert_epoch="$prev_alert_epoch"
if $should_alert; then
  next_alert_epoch="$now_epoch"
fi

jq -cn \
  --arg level "$level" \
  --arg fingerprint "$fingerprint" \
  --argjson last_alert_epoch "$next_alert_epoch" \
  --arg updated_at "$(date -Iseconds)" \
  --arg ollama_base_url "$ollama_base_url" \
  --argjson memory_fail_streak "$memory_fail_streak" \
  --arg issues "$issues" \
  '{level:$level,fingerprint:$fingerprint,last_alert_epoch:$last_alert_epoch,updated_at:$updated_at,issues:$issues,ollama_base_url:$ollama_base_url,memory_fail_streak:$memory_fail_streak}' > "$STATE_FILE"
