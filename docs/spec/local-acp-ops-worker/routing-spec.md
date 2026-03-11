# Routing Spec

## Input Classes
- `single_error_log`: one bounded failure excerpt with visible error boundary
- `mixed_log_stream`: noisy multi-line stream from one or more services
- `heartbeat_status`: compact health/status payload, check output, or metric snapshot
- `incident_note`: human-written ops note with optional pasted evidence
- `deploy_output`: build/deploy/rollout result text
- `unknown`: anything that does not cleanly match the above

## Route Graph
```text
raw input
  -> preprocess
  -> local-ops-triage
      -> local-ops-summarizer
      -> local-ops-patterns
      -> escalate-human
      -> reject
```
Preferred routes:
- `single_error_log` -> summarizer
- `heartbeat_status` -> summarizer
- `deploy_output` -> summarizer unless repeated failures across runs are present
- `mixed_log_stream` -> patterns when repetition dominates, else summarizer
- `incident_note` -> triage decides based on attached evidence density
- `unknown` -> escalate-human or reject

## Escalation Thresholds
Escalate to human when any threshold is met:
- confidence below `0.65` after triage
- severity `critical` with missing service, host, or timeframe
- more than `2` competing incident candidates in one input
- visible truncation around the likely failure boundary
- any secret/token/PII exposure signal
- repeated auth failures, restart loops, or network partitions affecting more than one service
- any pattern result with `pattern_strength = strong` and `operator_risk = high`

## Preprocessing Guidance for Noisy Logs
Before routing:
1. strip obvious ANSI color codes and terminal prompts
2. collapse duplicate consecutive lines after preserving one example and a count hint
3. preserve timestamps, service names, hostnames, and exit codes when present
4. keep at most the nearest context lines around repeated failure signatures
5. separate human notes from raw machine output when both are present
6. mark visible truncation rather than pretending the input is complete
7. do not redact away structural clues; only flag likely secrets for escalation

## v1 Routing Notes
- Default to summarizer when the input is bounded and the main task is operator comprehension.
- Default to patterns when recurrence or clustering is the main question.
- Fail closed on ambiguity; do not over-route.
