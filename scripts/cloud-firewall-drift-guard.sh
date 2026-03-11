#!/usr/bin/env bash
set -euo pipefail

export HOME=/root
export PATH="/root/.local/bin:/root/.npm-global/bin:/root/bin:/root/.volta/bin:/root/.asdf/shims:/root/.bun/bin:/root/.nvm/current/bin:/root/.fnm/current/bin:/root/.local/share/pnpm:/usr/local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set +u
source "${SCRIPT_DIR}/env-loader.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true
set -u

ACTION="check"
DRY_RUN="${DRY_RUN:-0}"
APPLY_CHANGES="${APPLY_CHANGES:-0}"
INSTANCE_ID_ARG=""
BASELINE_FILE_ARG=""
INSTANCE_JSON_FILE=""
FIREWALL_JSON_FILE=""

usage() {
  cat <<'EOF'
Usage:
  cloud-firewall-drift-guard.sh [check|bootstrap|ack|dispatch|remediate] [options]

Actions:
  check      Compare current cloud firewall state against baseline (default)
  bootstrap  Save current state as baseline
  ack        Promote latest snapshot to baseline (after approved change)
  dispatch   Send queued ticket messages to Telegram/Discord
  remediate  Build drift remediation plan (dry-run by default)

Options:
  --instance-id <id>      Override VULTR_INSTANCE_ID
  --baseline-file <path>  Override baseline file path
  --instance-json <path>  Offline mode: use local instance JSON
  --firewall-json <path>  Offline mode: use local firewall JSON
  --apply                 Apply remediation plan to Vultr API (default: dry-run plan only)
  --dry-run               Do not send messages
  -h, --help              Show help

Environment:
  VULTR_API_KEY            Vultr API token
  VULTR_INSTANCE_ID        Vultr instance ID
  DISCORD_SYSTEM_HEALTH    Discord channel target
  TELEGRAM_TARGET          Telegram target chat ID
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check|bootstrap|ack|dispatch|remediate)
      ACTION="$1"
      shift
      ;;
    --instance-id)
      INSTANCE_ID_ARG="${2:-}"
      shift 2
      ;;
    --baseline-file)
      BASELINE_FILE_ARG="${2:-}"
      shift 2
      ;;
    --instance-json)
      INSTANCE_JSON_FILE="${2:-}"
      shift 2
      ;;
    --firewall-json)
      FIREWALL_JSON_FILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --apply)
      APPLY_CHANGES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

STATE_DIR="${STATE_DIR:-/root/.openclaw/state/cloud-firewall-drift-guard}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-$STATE_DIR/snapshots}"
INCIDENT_DIR="${INCIDENT_DIR:-$STATE_DIR/incidents}"
TICKET_DIR="${TICKET_DIR:-$STATE_DIR/tickets}"
QUEUE_FILE="${QUEUE_FILE:-$STATE_DIR/ticket-queue.jsonl}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/state.json}"
LOCK_FILE="${LOCK_FILE:-/tmp/cloud-firewall-drift-guard.lock}"
LOG_FILE="${LOG_FILE:-/tmp/cloud-firewall-drift-guard.log}"
LAST_CURRENT_FILE="${LAST_CURRENT_FILE:-$STATE_DIR/last-current.json}"
LAST_TICKET_FILE="${LAST_TICKET_FILE:-$STATE_DIR/last-ticket-path.txt}"
LAST_DIFF_FILE="${LAST_DIFF_FILE:-$STATE_DIR/last-rules.diff}"
LAST_PLAN_FILE="${LAST_PLAN_FILE:-$STATE_DIR/last-remediation-plan.json}"

BASELINE_FILE="${BASELINE_FILE_ARG:-${BASELINE_FILE:-/root/.openclaw/workspace/config/cloud-firewall-baseline.vultr.json}}"
VULTR_API_BASE="${VULTR_API_BASE:-https://api.vultr.com/v2}"
VULTR_API_KEY="${VULTR_API_KEY:-}"
VULTR_INSTANCE_ID="${INSTANCE_ID_ARG:-${VULTR_INSTANCE_ID:-}}"

DISCORD_TARGET="${DISCORD_TARGET:-${DISCORD_SYSTEM_HEALTH:-}}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-62403941}}"

mkdir -p "$STATE_DIR" "$SNAPSHOT_DIR" "$INCIDENT_DIR" "$TICKET_DIR" "$(dirname "$BASELINE_FILE")"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" >>"$LOG_FILE"
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

file_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

count_lines() {
  local file="$1"
  if [[ -s "$file" ]]; then
    wc -l <"$file" | tr -d ' '
  else
    echo "0"
  fi
}

text_sha1() {
  local input="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha1sum | awk '{print $1}'
  else
    printf '%s' "$input" | shasum -a 1 | awk '{print $1}'
  fi
}

send_message() {
  local channel="$1"
  local target="$2"
  local message="$3"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] ${channel}:${target} ${message:0:180}"
    return 0
  fi

  # Validate channel and target before sending
  if ! MESSAGE_GUARD_DRY_RUN="false" validate_message_params --channel "$channel" --target "$target"; then
    log "[WARN] message send skipped: validation failed for $channel"
    return 0
  fi

  openclaw message send \
    --channel "$channel" \
    --target "$target" \
    --message "$message" \
    --silent >/dev/null 2>&1 || true
}

send_alert() {
  local message="$1"
  send_message "telegram" "$TELEGRAM_TARGET" "$message"
  send_message "discord" "$DISCORD_TARGET" "$message"
}

state_value() {
  local key="$1"
  if [[ -f "$STATE_FILE" ]]; then
    jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE" 2>/dev/null || true
  fi
}

write_state() {
  local status="$1"
  local fingerprint="$2"
  local message="$3"
  jq -nc \
    --arg status "$status" \
    --arg fingerprint "$fingerprint" \
    --arg message "$message" \
    --arg updatedAt "$(iso_now)" \
    '{status:$status,fingerprint:$fingerprint,message:$message,updatedAt:$updatedAt}' >"$STATE_FILE"
}

vultr_api_get() {
  local api_path="$1"
  local body_file="$2"
  local err_file="$3"
  local url="${VULTR_API_BASE}${api_path}"
  local http_code

  http_code="$(curl -sS \
    -H "Authorization: Bearer ${VULTR_API_KEY}" \
    --connect-timeout 7 \
    --max-time 20 \
    -o "$body_file" \
    -w '%{http_code}' \
    "$url" 2>"$err_file" || echo "000")"

  if [[ ! "$http_code" =~ ^2 ]]; then
    printf 'http_code=%s\n' "$http_code" >>"$err_file"
    return 1
  fi

  jq -e . "$body_file" >/dev/null 2>&1 || return 1
  return 0
}

vultr_api_write() {
  local method="$1"
  local api_path="$2"
  local body_file="$3"
  local err_file="$4"
  local payload="${5:-}"
  local url="${VULTR_API_BASE}${api_path}"
  local http_code

  if [[ -n "$payload" ]]; then
    http_code="$(curl -sS \
      -H "Authorization: Bearer ${VULTR_API_KEY}" \
      -H "Content-Type: application/json" \
      --connect-timeout 7 \
      --max-time 20 \
      -X "$method" \
      -d "$payload" \
      -o "$body_file" \
      -w '%{http_code}' \
      "$url" 2>"$err_file" || echo "000")"
  else
    http_code="$(curl -sS \
      -H "Authorization: Bearer ${VULTR_API_KEY}" \
      --connect-timeout 7 \
      --max-time 20 \
      -X "$method" \
      -o "$body_file" \
      -w '%{http_code}' \
      "$url" 2>"$err_file" || echo "000")"
  fi

  if [[ ! "$http_code" =~ ^2 ]]; then
    printf 'http_code=%s\n' "$http_code" >>"$err_file"
    return 1
  fi
  return 0
}

normalize_rules_file() {
  local firewall_json="$1"
  local output_file="$2"

  jq -c '
    .firewall.rules // []
    | map({
        id: (.id // ""),
        ip_type: (.ip_type // ""),
        protocol: (.protocol // ""),
        subnet: (.subnet // ""),
        subnet_size: (.subnet_size // ""),
        port: (.port // ""),
        source: (.source // ""),
        notes: (.notes // "")
      })
    | sort_by(.ip_type, .protocol, .subnet, .subnet_size, .port, .source, .notes, .id)
    | .[]
  ' "$firewall_json" >"$output_file"
}

normalize_rules_semantic_from_firewall_file() {
  local firewall_json="$1"
  local output_file="$2"

  jq -c '
    .firewall.rules // []
    | map({
        ip_type: (.ip_type // ""),
        protocol: (.protocol // ""),
        subnet: (.subnet // ""),
        subnet_size: (
          if (.subnet_size // "") == "" then "" else ((.subnet_size | tostring)) end
        ),
        port: (.port // ""),
        source: (.source // ""),
        notes: (.notes // "")
      })
    | sort_by(.ip_type, .protocol, .subnet, .subnet_size, .port, .source, .notes)
    | .[]
  ' "$firewall_json" >"$output_file"
}

normalize_rules_semantic_from_snapshot() {
  local snapshot_json="$1"
  local output_file="$2"

  jq -c '
    .rules // []
    | map({
        ip_type: (.ip_type // ""),
        protocol: (.protocol // ""),
        subnet: (.subnet // ""),
        subnet_size: (
          if (.subnet_size // "") == "" then "" else ((.subnet_size | tostring)) end
        ),
        port: (.port // ""),
        source: (.source // ""),
        notes: (.notes // "")
      })
    | sort_by(.ip_type, .protocol, .subnet, .subnet_size, .port, .source, .notes)
    | .[]
  ' "$snapshot_json" >"$output_file"
}

current_rule_id_map_from_snapshot() {
  local snapshot_json="$1"
  local output_file="$2"

  jq -r '
    .rules // []
    | map({
        id: (.id // ""),
        key: ({
          ip_type: (.ip_type // ""),
          protocol: (.protocol // ""),
          subnet: (.subnet // ""),
          subnet_size: (
            if (.subnet_size // "") == "" then "" else ((.subnet_size | tostring)) end
          ),
          port: (.port // ""),
          source: (.source // ""),
          notes: (.notes // "")
        })
      })
    | .[]
    | [(.key | tojson), .id] | @tsv
  ' "$snapshot_json" >"$output_file"
}

capture_failure_snapshot() {
  local stage="$1"
  local reason="$2"
  local api_path="$3"
  local body_file="$4"
  local err_file="$5"
  local ts file

  ts="$(date +%Y%m%d-%H%M%S)"
  file="$INCIDENT_DIR/failure-${ts}.log"

  {
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
    echo "stage=$stage"
    echo "reason=$reason"
    echo "instance_id=${VULTR_INSTANCE_ID:-unset}"
    echo "api_path=$api_path"
    echo
    echo "--- stderr ---"
    cat "$err_file" 2>/dev/null || true
    echo
    echo "--- response body ---"
    cat "$body_file" 2>/dev/null || true
    echo
    echo "--- resolv.conf ---"
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "--- route to api.vultr.com ---"
    ip route get 108.61.10.10 2>/dev/null || true
  } >"$file"

  echo "$file"
}

create_ticket_bundle() {
  local title="$1"
  local cause="$2"
  local action="$3"
  local verify="$4"
  local prevent="$5"
  local severity="$6"
  local snapshot_path="$7"
  local diff_path="${8:-}"
  local ts ticket_base ticket_json ticket_md

  ts="$(date +%Y%m%d-%H%M%S)"
  ticket_base="$TICKET_DIR/ticket-${ts}"
  ticket_json="${ticket_base}.json"
  ticket_md="${ticket_base}.md"

  jq -nc \
    --arg createdAt "$(iso_now)" \
    --arg project "infra" \
    --arg severity "$severity" \
    --arg title "$title" \
    --arg cause "$cause" \
    --arg action "$action" \
    --arg verify "$verify" \
    --arg prevent "$prevent" \
    --arg snapshot "$snapshot_path" \
    --arg diff "$diff_path" \
    '{
      createdAt: $createdAt,
      project: $project,
      severity: $severity,
      title: $title,
      cause: $cause,
      action: $action,
      verify: $verify,
      prevent: $prevent,
      attachments: (
        [
          (if $snapshot != "" then {type:"snapshot", path:$snapshot} else empty end),
          (if $diff != "" then {type:"diff", path:$diff} else empty end)
        ]
      )
    }' >"$ticket_json"

  {
    echo "## Ticket Draft"
    echo "- createdAt: $(iso_now)"
    echo "- severity: $severity"
    echo "- title: $title"
    echo "- cause: $cause"
    echo "- action: $action"
    echo "- verify: $verify"
    echo "- prevent: $prevent"
    echo "- snapshot: ${snapshot_path:-n/a}"
    echo "- diff: ${diff_path:-n/a}"
  } >"$ticket_md"

  jq -c . "$ticket_json" >>"$QUEUE_FILE"
  printf '%s\n' "$ticket_json" >"$LAST_TICKET_FILE"
  echo "$ticket_json"
}

collect_current_snapshot() {
  local ts tmp_dir instance_body instance_err firewall_body firewall_err
  local firewall_group_id firewall_name rules_file rules_sem_file rule_hash snapshot_file

  ts="$(date +%Y%m%d-%H%M%S)"
  tmp_dir="$(mktemp -d)"
  instance_body="$tmp_dir/instance.json"
  instance_err="$tmp_dir/instance.err"
  firewall_body="$tmp_dir/firewall.json"
  firewall_err="$tmp_dir/firewall.err"
  rules_file="$tmp_dir/rules.jsonl"
  rules_sem_file="$tmp_dir/rules-semantic.jsonl"

  if [[ -n "$INSTANCE_JSON_FILE" ]]; then
    cp "$INSTANCE_JSON_FILE" "$instance_body"
    jq -e . "$instance_body" >/dev/null
  else
    if [[ -z "$VULTR_API_KEY" ]]; then
      local snap ticket
      snap="$(capture_failure_snapshot "config_validation" "Missing VULTR_API_KEY" "n/a" "/dev/null" "/dev/null")"
      ticket="$(create_ticket_bundle \
        "[Cloud Firewall] config validation failed" \
        "VULTR_API_KEY is missing" \
        "Set VULTR_API_KEY and rerun check" \
        "Validate API key presence in environment" \
        "Keep runtime secrets loading health-check before nightly checks" \
        "L2" \
        "$snap" \
        "")"
      send_alert "ALERT: cloud-firewall check failed (missing VULTR_API_KEY). ticket=${ticket} snapshot=${snap}"
      write_state "fail" "missing_api_key" "missing VULTR_API_KEY"
      return 11
    fi
    if [[ -z "$VULTR_INSTANCE_ID" ]]; then
      local snap ticket
      snap="$(capture_failure_snapshot "config_validation" "Missing VULTR_INSTANCE_ID" "n/a" "/dev/null" "/dev/null")"
      ticket="$(create_ticket_bundle \
        "[Cloud Firewall] config validation failed" \
        "VULTR_INSTANCE_ID is missing" \
        "Set VULTR_INSTANCE_ID and rerun check" \
        "Validate instance ID in environment" \
        "Store instance metadata in a managed config file" \
        "L2" \
        "$snap" \
        "")"
      send_alert "ALERT: cloud-firewall check failed (missing VULTR_INSTANCE_ID). ticket=${ticket} snapshot=${snap}"
      write_state "fail" "missing_instance_id" "missing VULTR_INSTANCE_ID"
      return 12
    fi
    if ! vultr_api_get "/instances/${VULTR_INSTANCE_ID}" "$instance_body" "$instance_err"; then
      local snap ticket
      snap="$(capture_failure_snapshot "instance_fetch" "Vultr instance API call failed" "/instances/${VULTR_INSTANCE_ID}" "$instance_body" "$instance_err")"
      ticket="$(create_ticket_bundle \
        "[Cloud Firewall] API failure on instance fetch" \
        "Vultr API /instances call failed or returned invalid payload" \
        "Check VULTR_API_KEY allowlist, network path, and API status" \
        "Open snapshot and confirm HTTP/status details" \
        "Keep API token allowlist in sync and monitor network egress" \
        "L2" \
        "$snap" \
        "")"
      send_alert "ALERT: cloud-firewall check failed (instance fetch). ticket=${ticket} snapshot=${snap}"
      write_state "fail" "instance_fetch_fail" "instance fetch failed"
      return 21
    fi
  fi

  firewall_group_id="$(jq -r '.instance.firewall_group_id // empty' "$instance_body" 2>/dev/null || true)"

  if [[ -n "$FIREWALL_JSON_FILE" ]]; then
    cp "$FIREWALL_JSON_FILE" "$firewall_body"
    jq -e . "$firewall_body" >/dev/null
  elif [[ -n "$firewall_group_id" ]]; then
    if ! vultr_api_get "/firewalls/${firewall_group_id}" "$firewall_body" "$firewall_err"; then
      local snap ticket
      snap="$(capture_failure_snapshot "firewall_fetch" "Vultr firewall API call failed" "/firewalls/${firewall_group_id}" "$firewall_body" "$firewall_err")"
      ticket="$(create_ticket_bundle \
        "[Cloud Firewall] API failure on firewall fetch" \
        "Vultr API /firewalls call failed or returned invalid payload" \
        "Check firewall_group_id validity and API permissions" \
        "Open snapshot and compare with Vultr dashboard" \
        "Run periodic token/permission validation" \
        "L2" \
        "$snap" \
        "")"
      send_alert "ALERT: cloud-firewall check failed (firewall fetch). ticket=${ticket} snapshot=${snap}"
      write_state "fail" "firewall_fetch_fail" "firewall fetch failed"
      return 22
    fi
  else
    jq -nc '{"firewall":{"id":"","description":"none","rules":[]}}' >"$firewall_body"
  fi

  firewall_name="$(jq -r '.firewall.description // empty' "$firewall_body" 2>/dev/null || true)"
  normalize_rules_file "$firewall_body" "$rules_file"
  normalize_rules_semantic_from_firewall_file "$firewall_body" "$rules_sem_file"
  rule_hash="$(file_sha256 "$rules_sem_file")"
  snapshot_file="$SNAPSHOT_DIR/current-${ts}.json"

  jq -nc \
    --arg provider "vultr" \
    --arg checkedAt "$(iso_now)" \
    --arg instanceId "${VULTR_INSTANCE_ID:-$(jq -r '.instance.id // empty' "$instance_body")}" \
    --arg firewallGroupId "$firewall_group_id" \
    --arg firewallName "$firewall_name" \
    --arg ruleHash "$rule_hash" \
    --slurpfile rules "$rules_file" \
    '{
      provider: $provider,
      checkedAt: $checkedAt,
      instanceId: $instanceId,
      firewallGroupId: $firewallGroupId,
      firewallName: $firewallName,
      ruleHash: $ruleHash,
      rules: $rules
    }' >"$snapshot_file"

  cp "$snapshot_file" "$LAST_CURRENT_FILE"
  printf '%s\n' "$snapshot_file"
}

bootstrap_baseline() {
  local snapshot
  snapshot="$(collect_current_snapshot)"
  cp "$snapshot" "$BASELINE_FILE"
  write_state "ok" "bootstrap" "baseline created"
  log "[BOOTSTRAP] baseline updated from ${snapshot}"
  echo "BASELINE_CREATED:$BASELINE_FILE"
}

ack_latest_snapshot() {
  if [[ ! -f "$LAST_CURRENT_FILE" ]]; then
    echo "ERROR: no latest snapshot to ack: $LAST_CURRENT_FILE" >&2
    exit 1
  fi
  cp "$LAST_CURRENT_FILE" "$BASELINE_FILE"
  write_state "ok" "ack" "baseline promoted from last snapshot"
  log "[ACK] baseline promoted from ${LAST_CURRENT_FILE}"
  echo "BASELINE_ACKED:$BASELINE_FILE"
}

emit_recovery_if_needed() {
  local prev_status
  prev_status="$(state_value status)"
  if [[ "$prev_status" == "drift" || "$prev_status" == "fail" ]]; then
    send_alert "OK: cloud-firewall recovered. baseline and current configuration are aligned."
  fi
}

check_drift() {
  local snapshot baseline_id current_id baseline_hash current_hash fingerprint
  local baseline_rules current_rules diff_file rules_changed id_changed
  local prev_fingerprint prev_status ticket msg reasons

  # Nightly cron safe guard:
  # when Vultr runtime config is missing, skip gracefully instead of creating fail tickets.
  if [[ -z "$INSTANCE_JSON_FILE" && -z "$FIREWALL_JSON_FILE" ]]; then
    if [[ -z "$VULTR_API_KEY" || -z "$VULTR_INSTANCE_ID" ]]; then
      write_state "skipped" "missing_vultr_config" "skip check: missing VULTR_API_KEY or VULTR_INSTANCE_ID"
      log "[SKIP] check skipped due to missing VULTR_API_KEY or VULTR_INSTANCE_ID"
      echo "SKIPPED_MISSING_CONFIG"
      return 0
    fi
  fi

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "ERROR: baseline not found: $BASELINE_FILE" >&2
    echo "Run: $0 bootstrap"
    exit 1
  fi

  snapshot="$(collect_current_snapshot)"
  baseline_id="$(jq -r '.firewallGroupId // empty' "$BASELINE_FILE" 2>/dev/null || true)"
  current_id="$(jq -r '.firewallGroupId // empty' "$snapshot" 2>/dev/null || true)"
  baseline_hash="$(jq -r '.ruleHash // empty' "$BASELINE_FILE" 2>/dev/null || true)"
  current_hash="$(jq -r '.ruleHash // empty' "$snapshot" 2>/dev/null || true)"

  baseline_rules="$(mktemp)"
  current_rules="$(mktemp)"
  normalize_rules_semantic_from_snapshot "$BASELINE_FILE" "$baseline_rules"
  normalize_rules_semantic_from_snapshot "$snapshot" "$current_rules"

  diff_file="$INCIDENT_DIR/rules-diff-$(date +%Y%m%d-%H%M%S).patch"
  diff -u "$baseline_rules" "$current_rules" >"$diff_file" || true
  cp "$diff_file" "$LAST_DIFF_FILE"

  id_changed=0
  rules_changed=0
  reasons=()

  if [[ "$baseline_id" != "$current_id" ]]; then
    id_changed=1
    reasons+=("firewall_group_id drift (${baseline_id} -> ${current_id})")
  fi
  if [[ "$baseline_hash" != "$current_hash" ]]; then
    rules_changed=1
    reasons+=("SG/ACL rules changed (hash ${baseline_hash} -> ${current_hash})")
  fi

  if [[ ! -s "$diff_file" ]]; then
    rm -f "$diff_file"
    diff_file=""
  fi

  if (( id_changed == 0 && rules_changed == 0 )); then
    emit_recovery_if_needed
    write_state "ok" "ok:${current_hash}" "no drift"
    log "[OK] no cloud firewall drift"
    echo "NO_DRIFT"
    return 0
  fi

  fingerprint="$(text_sha1 "$(printf '%s|%s|%s' "$current_id" "$current_hash" "${reasons[*]}")")"
  prev_fingerprint="$(state_value fingerprint)"
  prev_status="$(state_value status)"

  if [[ "$prev_status" != "drift" || "$prev_fingerprint" != "$fingerprint" ]]; then
    msg="$(printf '%s; ' "${reasons[@]}")"
    ticket="$(create_ticket_bundle \
      "[Cloud Firewall] drift detected on instance ${VULTR_INSTANCE_ID:-unknown}" \
      "$msg" \
      "Review diff and Vultr dashboard. Roll back unauthorized changes or ack approved changes with 'ack'." \
      "Verify firewall_group_id/rules match baseline and rerun check." \
      "Apply change control: approved changes require immediate baseline update." \
      "L2" \
      "$snapshot" \
      "$diff_file")"
    send_alert "WARN: cloud firewall drift detected. reason=${msg} ticket=${ticket} diff=${diff_file:-none}"
    log "[DRIFT] ${msg} ticket=${ticket}"
  else
    log "[DRIFT] unchanged fingerprint=${fingerprint}; skip duplicate alert"
  fi

  write_state "drift" "$fingerprint" "${reasons[*]}"
  echo "DRIFT_DETECTED"
}

build_remediation_plan() {
  local current_snapshot="$1"
  local plan_file="$LAST_PLAN_FILE"
  local baseline_id current_id target_group_id switch_required
  local baseline_rules current_rules to_add to_remove id_map
  local remove_actions_jsonl remove_actions_json add_rules_json
  local add_count remove_count switch_count action_count
  local warning_unset_not_supported suppression

  baseline_id="$(jq -r '.firewallGroupId // empty' "$BASELINE_FILE" 2>/dev/null || true)"
  current_id="$(jq -r '.firewallGroupId // empty' "$current_snapshot" 2>/dev/null || true)"
  target_group_id="$current_id"
  switch_required=0
  warning_unset_not_supported=0
  suppression=0

  if [[ -n "$baseline_id" && "$baseline_id" != "$current_id" ]]; then
    switch_required=1
    target_group_id="$baseline_id"
  fi

  if [[ -z "$baseline_id" && -n "$current_id" ]]; then
    warning_unset_not_supported=1
    suppression=1
  fi

  baseline_rules="$(mktemp)"
  current_rules="$(mktemp)"
  to_add="$(mktemp)"
  to_remove="$(mktemp)"
  id_map="$(mktemp)"
  remove_actions_jsonl="$(mktemp)"
  remove_actions_json="$(mktemp)"
  add_rules_json="$(mktemp)"

  normalize_rules_semantic_from_snapshot "$BASELINE_FILE" "$baseline_rules"
  normalize_rules_semantic_from_snapshot "$current_snapshot" "$current_rules"
  current_rule_id_map_from_snapshot "$current_snapshot" "$id_map"

  if [[ "$suppression" == "1" ]]; then
    : >"$to_add"
    : >"$to_remove"
  else
    comm -23 "$baseline_rules" "$current_rules" >"$to_add"
    comm -13 "$baseline_rules" "$current_rules" >"$to_remove"
  fi

  while IFS= read -r rule_key; do
    [[ -z "$rule_key" ]] && continue
    local rule_id
    rule_id="$(awk -F'\t' -v key="$rule_key" '$1 == key {print $2; exit}' "$id_map")"
    jq -nc \
      --argjson rule "$rule_key" \
      --arg ruleId "${rule_id:-}" \
      '{rule:$rule, ruleId:$ruleId}' >>"$remove_actions_jsonl"
  done <"$to_remove"

  if [[ -s "$remove_actions_jsonl" ]]; then
    jq -cs . "$remove_actions_jsonl" >"$remove_actions_json"
  else
    echo "[]" >"$remove_actions_json"
  fi

  if [[ -s "$to_add" ]]; then
    jq -cs . "$to_add" >"$add_rules_json"
  else
    echo "[]" >"$add_rules_json"
  fi

  add_count="$(count_lines "$to_add")"
  remove_count="$(count_lines "$to_remove")"
  switch_count="$switch_required"
  action_count=$((switch_count + add_count + remove_count))

  jq -nc \
    --arg createdAt "$(iso_now)" \
    --arg mode "$( [[ "$APPLY_CHANGES" == "1" ]] && echo "apply" || echo "dry-run" )" \
    --arg baselineFile "$BASELINE_FILE" \
    --arg currentSnapshot "$current_snapshot" \
    --arg baselineFirewallGroupId "$baseline_id" \
    --arg currentFirewallGroupId "$current_id" \
    --arg targetFirewallGroupId "$target_group_id" \
    --argjson switchRequired "$switch_required" \
    --argjson suppressed "$suppression" \
    --argjson warningUnset "$warning_unset_not_supported" \
    --argjson applyRequested "$APPLY_CHANGES" \
    --argjson dryRunMode "$( [[ "$APPLY_CHANGES" == "1" ]] && echo "0" || echo "1" )" \
    --slurpfile addRules "$add_rules_json" \
    --slurpfile removeRules "$remove_actions_json" \
    --argjson addCount "$add_count" \
    --argjson removeCount "$remove_count" \
    --argjson switchCount "$switch_count" \
    --argjson actionCount "$action_count" \
    '{
      createdAt: $createdAt,
      mode: $mode,
      applyRequested: ($applyRequested == 1),
      dryRun: ($dryRunMode == 1),
      baselineFile: $baselineFile,
      currentSnapshot: $currentSnapshot,
      firewallGroupSwitch: {
        required: ($switchRequired == 1),
        current: $currentFirewallGroupId,
        desired: $baselineFirewallGroupId
      },
      targetFirewallGroupId: $targetFirewallGroupId,
      rules: {
        add: $addRules[0],
        remove: $removeRules[0]
      },
      warnings: (
        [
          (if $warningUnset == 1 then "desired firewall_group_id is empty; auto-unset is not implemented" else empty end),
          (if $suppressed == 1 then "rule reconciliation suppressed because desired firewall_group_id is empty" else empty end)
        ]
      ),
      summary: {
        switchCount: $switchCount,
        addCount: $addCount,
        removeCount: $removeCount,
        actionCount: $actionCount
      }
    }' >"$plan_file"

  echo "$plan_file"
}

remediate_drift() {
  local snapshot plan_file action_count switch_required add_count remove_count
  local target_group_id failure_count changed_count verification_snapshot verification_plan
  local remaining_actions fail_snapshot ticket

  if [[ -z "$INSTANCE_JSON_FILE" && -z "$FIREWALL_JSON_FILE" ]]; then
    if [[ -z "$VULTR_API_KEY" || -z "$VULTR_INSTANCE_ID" ]]; then
      write_state "skipped" "missing_vultr_config" "skip remediate: missing VULTR_API_KEY or VULTR_INSTANCE_ID"
      log "[SKIP] remediate skipped due to missing VULTR_API_KEY or VULTR_INSTANCE_ID"
      echo "SKIPPED_MISSING_CONFIG"
      return 0
    fi
  fi

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "ERROR: baseline not found: $BASELINE_FILE" >&2
    echo "Run: $0 bootstrap"
    exit 1
  fi

  snapshot="$(collect_current_snapshot)"
  plan_file="$(build_remediation_plan "$snapshot")"

  action_count="$(jq -r '.summary.actionCount // 0' "$plan_file")"
  switch_required="$(jq -r '.firewallGroupSwitch.required // false' "$plan_file")"
  add_count="$(jq -r '.summary.addCount // 0' "$plan_file")"
  remove_count="$(jq -r '.summary.removeCount // 0' "$plan_file")"
  target_group_id="$(jq -r '.targetFirewallGroupId // empty' "$plan_file")"

  log "[REMEDIATE_PLAN] action_count=${action_count} switch=${switch_required} add=${add_count} remove=${remove_count} apply=${APPLY_CHANGES}"
  echo "REMEDIATION_PLAN:$plan_file"
  echo "REMEDIATION_SUMMARY: switch=${switch_required} add=${add_count} remove=${remove_count} total=${action_count} apply=${APPLY_CHANGES}"

  if [[ "$action_count" == "0" ]]; then
    write_state "ok" "remediate_noop" "no remediation needed"
    echo "NO_REMEDIATION_NEEDED"
    return 0
  fi

  if [[ "$APPLY_CHANGES" != "1" ]]; then
    write_state "plan" "remediation_plan_ready" "remediation plan generated (dry-run)"
    echo "REMEDIATION_DRY_RUN_ONLY"
    return 0
  fi

  if [[ -n "$INSTANCE_JSON_FILE" || -n "$FIREWALL_JSON_FILE" ]]; then
    echo "ERROR: --apply cannot be used with offline fixture mode" >&2
    exit 1
  fi

  failure_count=0
  changed_count=0
  fail_snapshot=""

  if [[ "$switch_required" == "true" ]]; then
    local switch_payload switch_body switch_err
    switch_payload="$(jq -nc --arg gid "$(jq -r '.firewallGroupSwitch.desired // empty' "$plan_file")" '{firewall_group_id:$gid}')"
    switch_body="$(mktemp)"
    switch_err="$(mktemp)"
    if vultr_api_write "PATCH" "/instances/${VULTR_INSTANCE_ID}" "$switch_body" "$switch_err" "$switch_payload"; then
      changed_count=$((changed_count + 1))
      log "[REMEDIATE_APPLY] switched instance firewall_group_id"
      # Refresh snapshot and plan after group switch.
      snapshot="$(collect_current_snapshot)"
      plan_file="$(build_remediation_plan "$snapshot")"
      target_group_id="$(jq -r '.targetFirewallGroupId // empty' "$plan_file")"
    else
      failure_count=$((failure_count + 1))
      fail_snapshot="$(capture_failure_snapshot "remediate_switch_firewall_group" "Failed to switch instance firewall group" "/instances/${VULTR_INSTANCE_ID}" "$switch_body" "$switch_err")"
      log "[REMEDIATE_APPLY] failed to switch instance firewall_group_id"
    fi
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local rule_id delete_body delete_err
    rule_id="$(echo "$row" | jq -r '.ruleId // empty')"
    if [[ -z "$rule_id" ]]; then
      failure_count=$((failure_count + 1))
      log "[REMEDIATE_APPLY] cannot delete rule without ruleId"
      continue
    fi
    delete_body="$(mktemp)"
    delete_err="$(mktemp)"
    if vultr_api_write "DELETE" "/firewalls/${target_group_id}/rules/${rule_id}" "$delete_body" "$delete_err"; then
      changed_count=$((changed_count + 1))
      log "[REMEDIATE_APPLY] deleted firewall rule ${rule_id}"
    else
      failure_count=$((failure_count + 1))
      fail_snapshot="$(capture_failure_snapshot "remediate_delete_rule" "Failed to delete firewall rule" "/firewalls/${target_group_id}/rules/${rule_id}" "$delete_body" "$delete_err")"
      log "[REMEDIATE_APPLY] failed to delete firewall rule ${rule_id}"
    fi
  done < <(jq -c '.rules.remove[]?' "$plan_file")

  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    local add_payload add_body add_err
    add_payload="$(jq -nc --argjson r "$rule" '
      {
        ip_type: ($r.ip_type // ""),
        protocol: ($r.protocol // ""),
        subnet: ($r.subnet // ""),
        subnet_size: (if (($r.subnet_size // "") | tostring) == "" then null else (($r.subnet_size | tonumber?) // ($r.subnet_size | tostring)) end),
        port: ($r.port // ""),
        source: ($r.source // ""),
        notes: ($r.notes // "")
      }
      | with_entries(select(.value != null and .value != ""))
    ')"
    add_body="$(mktemp)"
    add_err="$(mktemp)"
    if vultr_api_write "POST" "/firewalls/${target_group_id}/rules" "$add_body" "$add_err" "$add_payload"; then
      changed_count=$((changed_count + 1))
      log "[REMEDIATE_APPLY] added firewall rule"
    else
      failure_count=$((failure_count + 1))
      fail_snapshot="$(capture_failure_snapshot "remediate_add_rule" "Failed to add firewall rule" "/firewalls/${target_group_id}/rules" "$add_body" "$add_err")"
      log "[REMEDIATE_APPLY] failed to add firewall rule"
    fi
  done < <(jq -c '.rules.add[]?' "$plan_file")

  verification_snapshot="$(collect_current_snapshot)"
  verification_plan="$(build_remediation_plan "$verification_snapshot")"
  remaining_actions="$(jq -r '.summary.actionCount // 0' "$verification_plan")"

  if (( failure_count > 0 )); then
    ticket="$(create_ticket_bundle \
      "[Cloud Firewall] remediation apply failed" \
      "remediation apply had ${failure_count} API failure(s)" \
      "Review failure snapshot and fix API permission/allowlist, then rerun remediate --apply" \
      "Run remediate dry-run and ensure summary.total becomes 0" \
      "Keep dry-run gate and approval flow before apply" \
      "L2" \
      "$fail_snapshot" \
      "$verification_plan")"
    send_alert "ALERT: cloud firewall remediation apply failed. failures=${failure_count} ticket=${ticket} plan=${verification_plan}"
    write_state "fail" "remediate_apply_failed" "remediation apply failed"
    echo "REMEDIATION_APPLY_FAILED"
    return 1
  fi

  if [[ "$remaining_actions" == "0" ]]; then
    send_alert "OK: cloud firewall remediation applied successfully. changed=${changed_count}"
    write_state "ok" "remediated" "remediation applied successfully"
    echo "REMEDIATION_APPLIED"
    return 0
  fi

  ticket="$(create_ticket_bundle \
    "[Cloud Firewall] remediation partial" \
    "remediation applied but ${remaining_actions} action(s) still remain" \
    "Inspect latest remediation plan and rerun with approval" \
    "Run remediate dry-run and review remaining actions" \
    "Treat partial remediation as incident and validate policy drift source" \
    "L2" \
    "$verification_snapshot" \
    "$verification_plan")"
  send_alert "WARN: cloud firewall remediation partial. remaining=${remaining_actions} ticket=${ticket} plan=${verification_plan}"
  write_state "drift" "remediate_partial" "remediation partial; drift remains"
  echo "REMEDIATION_PARTIAL"
  return 1
}

dispatch_queue() {
  local tmp_file sent_count
  sent_count=0

  if [[ ! -s "$QUEUE_FILE" ]]; then
    echo "QUEUE_EMPTY"
    return 0
  fi

  tmp_file="$(mktemp)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
      continue
    fi

    local title severity cause snapshot diff msg
    title="$(echo "$line" | jq -r '.title // empty')"
    severity="$(echo "$line" | jq -r '.severity // "L2"')"
    cause="$(echo "$line" | jq -r '.cause // empty')"
    snapshot="$(echo "$line" | jq -r '.attachments[]? | select(.type=="snapshot") | .path' | head -n1)"
    diff="$(echo "$line" | jq -r '.attachments[]? | select(.type=="diff") | .path' | head -n1)"
    msg="[TICKET][${severity}] ${title}
- cause: ${cause}
- snapshot: ${snapshot:-n/a}
- diff: ${diff:-n/a}"

    send_message "telegram" "$TELEGRAM_TARGET" "$msg"
    send_message "discord" "$DISCORD_TARGET" "$msg"
    sent_count=$((sent_count + 1))
  done <"$QUEUE_FILE"

  # Queue is considered delivered once dispatched to channels.
  : >"$tmp_file"
  mv "$tmp_file" "$QUEUE_FILE"
  log "[DISPATCH] sent=${sent_count}"
  echo "QUEUE_DISPATCHED:${sent_count}"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required" >&2
  exit 1
fi

case "$ACTION" in
  check)
    check_drift
    ;;
  bootstrap)
    bootstrap_baseline
    ;;
  ack)
    ack_latest_snapshot
    ;;
  remediate)
    remediate_drift
    ;;
  dispatch)
    dispatch_queue
    ;;
  *)
    echo "Unsupported action: $ACTION" >&2
    exit 2
    ;;
esac
