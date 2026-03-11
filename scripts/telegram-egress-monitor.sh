#!/usr/bin/env bash
set -euo pipefail

export HOME=/root
export PATH="/root/.local/bin:/root/.npm-global/bin:/root/bin:/root/.volta/bin:/root/.asdf/shims:/root/.bun/bin:/root/.nvm/current/bin:/root/.fnm/current/bin:/root/.local/share/pnpm:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${LOG_FILE:-/tmp/telegram-egress-monitor.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/telegram-egress-monitor.lock}"
STATE_DIR="${STATE_DIR:-/root/.openclaw/state/telegram-egress-monitor}"
INCIDENT_DIR="${INCIDENT_DIR:-$STATE_DIR/incidents}"
QUEUE_FILE="${QUEUE_FILE:-$STATE_DIR/alert-queue.jsonl}"
FAIL_FILE="${FAIL_FILE:-$STATE_DIR/consecutive_failures}"
RECOVERY_FILE="${RECOVERY_FILE:-$STATE_DIR/recovery_notice_pending}"
TELEGRAM_HOST="${TELEGRAM_HOST:-api.telegram.org}"
TELEGRAM_TARGET="${TELEGRAM_TARGET:-62403941}"
DRY_RUN="${DRY_RUN:-0}"
FORCE_FAIL="${FORCE_FAIL:-0}"
FORCE_OK="${FORCE_OK:-0}"

TELEGRAM_IPS=(
  "149.154.166.110"
  "149.154.167.220"
  "149.154.167.99"
  "91.108.4.4"
  "91.108.56.1"
)

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" >>"$LOG_FILE"
}

read_fail_count() {
  if [[ -f "$FAIL_FILE" ]]; then
    cat "$FAIL_FILE"
  else
    echo "0"
  fi
}

write_fail_count() {
  printf '%s\n' "$1" >"$FAIL_FILE"
}

send_telegram() {
  local msg="$1"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] telegram message: ${msg:0:160}"
    return 0
  fi

  /root/.openclaw/workspace/scripts/send-guarded-message.sh \
    --channel telegram \
    --target "$TELEGRAM_TARGET" \
    --message "$msg" \
    --context telegram-egress-monitor >/dev/null 2>&1
}

enqueue_alert() {
  local level="$1"
  local msg="$2"
  local snapshot="$3"
  mkdir -p "$STATE_DIR"
  jq -nc \
    --arg id "$(date +%s)-$RANDOM" \
    --arg level "$level" \
    --arg createdAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg msg "$msg" \
    --arg snapshot "$snapshot" \
    '{id:$id,level:$level,createdAt:$createdAt,message:$msg,snapshot:$snapshot}' >>"$QUEUE_FILE"
}

flush_queue() {
  [[ -s "$QUEUE_FILE" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
      continue
    fi
    local msg
    msg="$(echo "$line" | jq -r '.message // empty')"
    if [[ -z "$msg" ]]; then
      continue
    fi
    if send_telegram "$msg"; then
      log "[QUEUE] delivered"
    else
      echo "$line" >>"$tmp_file"
    fi
  done <"$QUEUE_FILE"

  if [[ -s "$tmp_file" ]]; then
    mv "$tmp_file" "$QUEUE_FILE"
  else
    rm -f "$tmp_file" "$QUEUE_FILE"
  fi
}

domain_http_code() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "https://${TELEGRAM_HOST}" || true
}

probe_known_ip() {
  local ip="$1"
  curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 8 \
    --resolve "${TELEGRAM_HOST}:443:${ip}" \
    "https://${TELEGRAM_HOST}" || true
}

capture_snapshot() {
  mkdir -p "$INCIDENT_DIR"
  local ts file
  ts="$(date +%Y%m%d-%H%M%S)"
  file="$INCIDENT_DIR/telegram-egress-$ts.log"

  {
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
    echo "host=$(hostname -f 2>/dev/null || hostname)"
    echo "--- resolv.conf ---"
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "--- getent api.telegram.org ---"
    getent ahostsv4 "$TELEGRAM_HOST" || true
    getent ahostsv6 "$TELEGRAM_HOST" || true
    echo
    echo "--- curl domain ---"
    curl -sS -o /dev/null -w 'code=%{http_code} ip=%{remote_ip} total=%{time_total}\n' \
      --max-time 10 "https://${TELEGRAM_HOST}" || true
    echo
    echo "--- curl known IPs ---"
    for ip in "${TELEGRAM_IPS[@]}"; do
      echo "ip=$ip"
      curl -sS -o /dev/null -w 'code=%{http_code} ip=%{remote_ip} total=%{time_total}\n' \
        --max-time 10 \
        --resolve "${TELEGRAM_HOST}:443:${ip}" \
        "https://${TELEGRAM_HOST}" || true
    done
    echo
    echo "--- route ---"
    ip route get 149.154.166.110 || true
    echo
    if command -v mtr >/dev/null 2>&1; then
      echo "--- mtr tcp/443 149.154.166.110 ---"
      mtr -n -T -P 443 -c 8 -r 149.154.166.110 || true
    fi
  } >"$file" 2>&1

  echo "$file"
}

main() {
  mkdir -p "$STATE_DIR" "$INCIDENT_DIR"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    exit 0
  fi

  local dns_ok=0
  local domain_code="000"
  local ip_ok=0
  local ip_hit=""
  local fail_count

  if [[ "$FORCE_OK" == "1" ]]; then
    dns_ok=1
    domain_code="200"
    ip_ok=1
    ip_hit="forced"
  elif [[ "$FORCE_FAIL" == "1" ]]; then
    dns_ok=0
    domain_code="000"
    ip_ok=0
  else
    if getent ahostsv4 "$TELEGRAM_HOST" >/dev/null 2>&1; then
      dns_ok=1
    fi

    domain_code="$(domain_http_code)"
    if [[ -z "$domain_code" ]]; then
      domain_code="000"
    fi

    for ip in "${TELEGRAM_IPS[@]}"; do
      local code
      code="$(probe_known_ip "$ip")"
      if [[ "$code" != "000" && -n "$code" ]]; then
        ip_ok=1
        ip_hit="$ip:$code"
        break
      fi
    done
  fi

  local healthy=0
  if [[ "$dns_ok" -eq 1 && ( "$domain_code" != "000" || "$ip_ok" -eq 1 ) ]]; then
    healthy=1
  fi

  fail_count="$(read_fail_count)"
  if ! [[ "$fail_count" =~ ^[0-9]+$ ]]; then
    fail_count=0
  fi

  if [[ "$healthy" -eq 1 ]]; then
    if [[ "$fail_count" -ge 3 ]]; then
      echo "1" >"$RECOVERY_FILE"
    fi
    write_fail_count 0

    if [[ -f "$RECOVERY_FILE" ]]; then
      enqueue_alert "info" "✅ Telegram egress recovered at $(date '+%Y-%m-%d %H:%M:%S %Z'). domain_code=${domain_code} ip_hit=${ip_hit:-none}" ""
      rm -f "$RECOVERY_FILE"
    fi
    flush_queue
    log "[OK] healthy dns_ok=$dns_ok domain_code=$domain_code ip_ok=$ip_ok ip_hit=${ip_hit:-none}"
    exit 0
  fi

  fail_count=$((fail_count + 1))
  write_fail_count "$fail_count"

  if [[ "$fail_count" -eq 3 ]]; then
    local snapshot msg
    snapshot="$(capture_snapshot)"
    msg="⚠️ Telegram egress failed 3 times consecutively (dns_ok=${dns_ok}, domain_code=${domain_code}, ip_ok=${ip_ok}). snapshot=${snapshot}"
    enqueue_alert "critical" "$msg" "$snapshot"
    flush_queue
    log "[ALERT] streak=3 snapshot=$snapshot"
  else
    flush_queue
    log "[WARN] unhealthy streak=$fail_count dns_ok=$dns_ok domain_code=$domain_code ip_ok=$ip_ok"
  fi
}

main "$@"
