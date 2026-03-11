# Test Pack

Purpose: validate structure, routing intent, and fail-closed behavior.

## Case 1: Single Timeout Log -> Summarizer
### Sample Input
```text
2026-03-10T00:10:11Z api timeout after 30000ms
2026-03-10T00:10:12Z api retry 1
2026-03-10T00:10:42Z api timeout after 30000ms
service=orders env=prod host=api-2
```
### Expected Validation
- triage `input_class = single_error_log`
- triage route = `local-ops-summarizer`
- summarizer `status` is not `healthy`
- summarizer has at least 2 `facts`
- summarizer `operator_summary` mentions timeout impact

## Case 2: Mixed Repeated Restart Stream -> Patterns
### Sample Input
```text
web-1 restarting exit=137
web-1 restarting exit=137
cache warmup ok
web-1 restarting exit=137
worker-2 heartbeat ok
web-1 restarting exit=137
```
### Expected Validation
- triage `input_class = mixed_log_stream`
- triage route = `local-ops-patterns`
- patterns `pattern_strength` is `moderate` or `strong`
- one pattern label is `restart_loop`
- `evidence_samples` has at least 2 items

## Case 3: Ambiguous Truncated Incident -> Escalate
### Sample Input
```text
... connection reset by peer
... token=sk-live-xxxxx
... [truncated]
```
### Expected Validation
- triage route = `escalate-human`
- triage `needs_preprocessing = true`
- triage `missing_context` is non-empty
- reason mentions truncation and/or sensitive data

## Case 4: Heartbeat Healthy Snapshot -> Summarizer
### Sample Input
```text
service=brain-router status=ok latency_ms=83 queue_depth=1 retries=0
service=sender status=ok latency_ms=91 queue_depth=0 retries=0
```
### Expected Validation
- triage `input_class = heartbeat_status`
- route = `local-ops-summarizer`
- summarizer `status = healthy` or `degraded`
- `open_questions` may be empty

## Minimal Acceptance Checklist
- every worker returns only schema fields
- empty or non-ops text rejects cleanly
- low-confidence critical inputs escalate
- recurrence claims require repeated evidence
