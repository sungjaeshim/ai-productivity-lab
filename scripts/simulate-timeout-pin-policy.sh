#!/usr/bin/env bash
set -euo pipefail

# D4 timeout pin policy dry-run simulator
# Rule:
# - trigger when >=2 timeout events within 120 minutes
# - pin duration 360 minutes
# - rollback when quiet for 240 minutes

trigger_window_min=120
trigger_count=2
pin_duration_min=360
recovery_quiet_min=240

echo "[policy] trigger: ${trigger_count} timeouts / ${trigger_window_min}m"
echo "[policy] pin: GLM47 for ${pin_duration_min}m"
echo "[policy] rollback: ${recovery_quiet_min}m quiet"

# Scenario A: trigger condition met (events at -110m, -20m)
events_a=(110 20)
count_a=0
for m in "${events_a[@]}"; do
  if (( m <= trigger_window_min )); then
    count_a=$((count_a+1))
  fi
done
if (( count_a >= trigger_count )); then
  echo "[A] ACTION=PIN_GLM47 (events_in_window=${count_a})"
else
  echo "[A] ACTION=NOOP (events_in_window=${count_a})"
fi

# Scenario B: already pinned, quiet window satisfied for rollback
quiet_since_last_timeout_min=260
if (( quiet_since_last_timeout_min >= recovery_quiet_min )); then
  echo "[B] ACTION=ROLLBACK_PRIMARY (quiet=${quiet_since_last_timeout_min}m)"
else
  echo "[B] ACTION=KEEP_PIN (quiet=${quiet_since_last_timeout_min}m)"
fi

# Scenario C: insufficient events (events at -200m, -150m)
events_c=(200 150)
count_c=0
for m in "${events_c[@]}"; do
  if (( m <= trigger_window_min )); then
    count_c=$((count_c+1))
  fi
done
if (( count_c >= trigger_count )); then
  echo "[C] ACTION=PIN_GLM47 (events_in_window=${count_c})"
else
  echo "[C] ACTION=NOOP (events_in_window=${count_c})"
fi

echo "[result] DRY_RUN_OK"
