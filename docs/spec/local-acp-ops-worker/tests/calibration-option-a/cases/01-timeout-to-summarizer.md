# Case 01 - Timeout to Summarizer

## Input
```text
2026-03-10T09:14:02Z service=orders env=prod host=api-2 request_id=8f2b upstream=payments timeout after 30000ms
2026-03-10T09:14:03Z service=orders env=prod host=api-2 retry=1 cause=upstream_timeout
2026-03-10T09:14:34Z service=orders env=prod host=api-2 request_id=8f3a upstream=payments timeout after 30000ms
2026-03-10T09:14:35Z service=orders env=prod host=api-2 queue_depth=47 error_rate=0.18
```

## Intended Worker Path
`local-ops-triage -> local-ops-summarizer`

## Expected Validation Checklist
- triage `input_class = single_error_log`
- triage route = `local-ops-summarizer`
- triage includes timeout signal with direct evidence
- summarizer `status = degraded` or `failing`
- summarizer facts mention repeated timeout and impacted service/host
- summarizer does not invent remediation or root cause certainty

## Common Failure Modes
- routes to patterns just because the timeout appears twice in one bounded excerpt
- drops `host=api-2` or `upstream=payments`
- labels system `healthy` because retries are present
- claims database/network root cause without evidence
