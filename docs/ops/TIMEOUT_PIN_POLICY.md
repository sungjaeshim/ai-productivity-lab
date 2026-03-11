# Timeout Pin Policy (D4)

## Policy
- Trigger: **2 timeouts within 2 hours**
- Action: temporarily pin primary model to **GLM47** for **6 hours**
- Recovery: rollback to normal primary after **4 hours no-timeout**

## Decision Rationale
- Prevent repeated lane saturation and cascading retries during unstable windows.
- Keep rollback explicit and measurable to avoid sticky emergency mode.

## Operational Variables
- `trigger_count`: number of timeout events in rolling window
- `trigger_window_minutes`: 120
- `pin_duration_minutes`: 360
- `recovery_quiet_minutes`: 240

## Dry-run command

```bash
bash scripts/simulate-timeout-pin-policy.sh
```

## Expected dry-run
- Scenario A (2 in 2h): `ACTION=PIN_GLM47`
- Scenario B (quiet 4h): `ACTION=ROLLBACK_PRIMARY`
- Scenario C (insufficient events): `ACTION=NOOP`
