# Implementation Note

This pack is config-free by design. It is a documentation scaffold for later ACP/OpenClaw wiring.

Suggested later integration path:
1. register three local ACP worker definitions using the system prompts and schemas in `agents/`
2. wire one small router layer that runs preprocessing, then `local-ops-triage`, then dispatches by `route`
3. validate outputs against the schemas before any downstream posting or storage
4. keep these workers read-only and summary-only; do not attach remediation actions in v1
5. log worker input class, chosen route, confidence, and escalation reason for later tuning

Suggested runtime contract:
- input: raw text plus optional metadata `{source, service, host, timeframe}`
- output: schema-valid JSON only
- failure mode: escalate or reject, never free-form guesswork

Do not change gateway config yet. Use this pack as the reviewable source of truth before integration.
