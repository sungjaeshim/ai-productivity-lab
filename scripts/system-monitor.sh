#!/usr/bin/env bash
# Compatibility wrapper for legacy system-monitor callers.
# Canonical alert flow remains callme-v1-dispatch.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPATCH_SCRIPT="${SCRIPT_DIR}/callme-v1-dispatch.sh"
MEM_WARN="${SYSTEM_MONITOR_MEM_WARN:-80}"
MEM_CRIT="${SYSTEM_MONITOR_MEM_CRIT:-90}"
DISK_WARN="${SYSTEM_MONITOR_DISK_WARN:-80}"
DISK_CRIT="${SYSTEM_MONITOR_DISK_CRIT:-90}"
CPU_WARN="${SYSTEM_MONITOR_CPU_WARN:-90}"
CPU_CRIT="${SYSTEM_MONITOR_CPU_CRIT:-95}"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 [--dry-run]

Legacy-compatible system monitor wrapper.
Builds a callme-v1 event when memory/cpu/disk thresholds are exceeded.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$DISPATCH_SCRIPT" ]]; then
  echo "SYSTEM_MONITOR_ERROR: dispatch script missing: $DISPATCH_SCRIPT" >&2
  exit 1
fi

mem_percent="$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')"
disk_percent="$(df / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
cpu_percent="$(top -bn1 | awk -F',' '/Cpu\(s\)/ {gsub(/[^0-9.]/, "", $1); if ($1 == "") print 0; else print int($1 + 0.5)}')"
cpu_percent="${cpu_percent:-0}"

alerts=()
severity="high"
if (( mem_percent >= MEM_WARN )); then
  alerts+=("Memory ${mem_percent}%")
fi
if (( disk_percent >= DISK_WARN )); then
  alerts+=("Disk ${disk_percent}%")
fi
if (( cpu_percent >= CPU_WARN )); then
  alerts+=("CPU ${cpu_percent}%")
fi

if (( mem_percent >= MEM_CRIT || disk_percent >= DISK_CRIT || cpu_percent >= CPU_CRIT )); then
  severity="critical"
fi

if [[ ${#alerts[@]} -eq 0 ]]; then
  echo "HEARTBEAT_OK"
  exit 0
fi

event_file="$(mktemp)"
python3 - <<'PY' "$event_file" "$severity" "$mem_percent" "$cpu_percent" "$disk_percent" "$MEM_WARN" "$CPU_WARN" "$DISK_WARN"
import json
import sys
from datetime import datetime, timezone

target, severity, mem, cpu, disk, mem_warn, cpu_warn, disk_warn = sys.argv[1:9]
obj = {
    "eventType": "system-monitor",
    "project": "ops",
    "severity": severity,
    "summary": "System monitor threshold exceeded",
    "details": (
        f"Memory: {mem}% (warn {mem_warn}%)\n"
        f"CPU: {cpu}% (warn {cpu_warn}%)\n"
        f"Disk: {disk}% (warn {disk_warn}%)"
    ),
    "retryCount": 0,
    "needApprovalMinutes": 0,
    "occurredAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(target, "w", encoding="utf-8") as fh:
    json.dump(obj, fh, ensure_ascii=False, indent=2)
PY

if $DRY_RUN; then
  cat "$event_file"
  rm -f "$event_file"
  exit 0
fi

"$DISPATCH_SCRIPT" --event "$event_file"
rm -f "$event_file"
