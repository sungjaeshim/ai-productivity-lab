# Case 02 - Restart Loop to Patterns

## Input
```text
2026-03-10T08:02:11Z service=worker env=prod pod=worker-7 exit_code=137 restarting
2026-03-10T08:02:43Z service=worker env=prod pod=worker-7 exit_code=137 restarting
2026-03-10T08:03:16Z service=worker env=prod pod=worker-7 exit_code=137 restarting
2026-03-10T08:03:49Z service=worker env=prod pod=worker-7 exit_code=137 restarting
2026-03-10T08:04:20Z service=worker env=prod pod=worker-7 backoff_seconds=30
2026-03-10T08:04:52Z service=worker env=prod pod=worker-7 exit_code=137 restarting
```

## Intended Worker Path
`local-ops-triage -> local-ops-patterns`

## Expected Validation Checklist
- triage `input_class = mixed_log_stream`
- triage route = `local-ops-patterns`
- triage severity is `high` or `critical`
- patterns includes `restart_loop`
- `pattern_strength = moderate` or `strong`
- evidence samples show repeated restart signature, not only one line
- escalation is required if operator risk is high

## Common Failure Modes
- routes to summarizer instead of patterns
- misses restart-loop label and describes lines independently
- weak pattern claim with only one evidence sample
- ignores backoff signal that increases operator risk
