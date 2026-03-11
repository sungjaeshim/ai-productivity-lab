# Local ACP Ops-Worker Pack v1

Purpose: first-pass local worker pack for operational log and status summarization only.

Scope:
- classify noisy ops inputs
- produce short status summaries
- surface repeated patterns worth escalation

Contents:
- `agents/local-ops-triage.md`
- `agents/local-ops-summarizer.md`
- `agents/local-ops-patterns.md`
- `routing-spec.md`
- `tests/README.md`
- `implementation-note.md`

Design principles:
- local-first and low-ceremony
- strict schemas over prose freedom
- escalation before guessing
- concise outputs for operator workflows
