# Case 04 - Healthy Heartbeat to Summarizer

## Input
```text
2026-03-10T10:00:00Z service=brain-router status=ok latency_ms=82 queue_depth=1 retries=0 host=router-1
2026-03-10T10:00:00Z service=sender status=ok latency_ms=94 queue_depth=0 retries=0 host=sender-2
2026-03-10T10:00:00Z service=memory-sync status=ok latency_ms=71 queue_depth=2 retries=0 host=mem-1
```

## Intended Worker Path
`local-ops-triage -> local-ops-summarizer`

## Expected Validation Checklist
- triage `input_class = heartbeat_status`
- triage route = `local-ops-summarizer`
- summarizer `status = healthy`
- facts stay observational and include at least two services
- `open_questions` may be empty
- operator summary stays short and does not manufacture risk

## Common Failure Modes
- overstates minor queue depth as degradation
- routes to patterns just because there are three lines
- omits one service and loses the snapshot character
- adds unnecessary escalation with no evidence conflict
