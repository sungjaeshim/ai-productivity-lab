# Calibration Pack - Option A

Purpose: sample-log testing first for the local ACP ops-worker pack.

Use this pack to compare local models on the same bounded inputs before any runtime wiring.

Contents:
- `cases/01-timeout-to-summarizer.md`
- `cases/02-restart-loop-to-patterns.md`
- `cases/03-sensitive-truncated-escalate.md`
- `cases/04-healthy-heartbeat-to-summarizer.md`
- `cases/05-mixed-deploy-output.md`
- `manual-execution-guide.md`
- `prompt-sheet.md`
- `scoring-rubric.md`
- `test-run-worksheet.md`
- `scorecard-summary-template.md`

Operator notes:
- run triage first on every sample
- only run downstream worker when triage route is not escalation/reject
- score outputs against schema, route, escalation, and usefulness
- fail closed on secrets, truncation, or mixed-incident ambiguity
