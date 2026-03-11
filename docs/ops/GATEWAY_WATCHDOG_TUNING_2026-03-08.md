# Gateway Watchdog Tuning

Updated: 2026-03-08

## Why This Exists

- gateway service was often `running` while local health probes still timed out
- repeated health probe failures were followed by auto-restarts
- journal showed this happening during:
  - `lane wait exceeded: lane=main`
  - embedded run timeouts
  - compaction-related slowdown

This means the old watchdog thresholds were too aggressive for the current runtime load.

## Applied Draft

File:

- `/root/.config/systemd/user/openclaw-watchdog-health.service.d/10-tuning.conf`

New values:

- `HEALTH_FAIL_THRESHOLD=3`
- `HEALTH_PROBE_RETRIES=1`
- `HEALTH_PROBE_BACKOFF_SEC=2`
- `HEALTH_HTTP_TIMEOUT_SEC=15`
- `HEALTH_STARTUP_GRACE_SEC=60`
- `HEALTH_RESTART_GRACE_SEC=60`
- `HEALTH_RESTART_COOLDOWN_SEC=1800`

## Intent

- reduce false-positive restarts during temporary lane saturation
- give the gateway more time to recover from brief event-loop stalls
- avoid restart churn that creates `1012 service restart` closures for active callers

## Tradeoff

- real outages may take longer to auto-restart
- but the gateway should restart less often for transient overload alone

## Next Validation

Watch these after reload:

- `openclaw status --json`
- `journalctl --user -u openclaw-gateway.service -f`
- `journalctl --user -u openclaw-watchdog-health.service -f`

Success signals:

- fewer health probe `curl (28)` timeouts
- fewer `1012 service restart` closures
- fewer `lane wait exceeded: lane=main` cascades ending in restart

Failure signals:

- health probe timeouts still cluster
- gateway still restarts under short transient stalls
- recovery takes too long during real gateway hangs
