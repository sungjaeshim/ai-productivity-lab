# local-rescue manual calibration evaluation — 2026-03-10

## Run Summary
- Date: 2026-03-10
- Model alias: `local-rescue`
- Backing model observed in run metadata: `ollama/qwen3.5:9b-q4_K_M`
- Pack: `docs/spec/local-acp-ops-worker/tests/calibration-option-a/`
- Method: reviewed pack docs/specs, then attempted real manual execution starting with exact-marker smoke + Case 01 triage
- Settings kept constant across attempted runs: yes
- Confidence: medium on execution blockage, low on content quality (because the pack could not be executed end-to-end)

## What Was Reviewed
- `README.md`
- `manual-execution-guide.md`
- `prompt-sheet.md`
- `scoring-rubric.md`
- `test-run-worksheet.md`
- `scorecard-summary-template.md`
- case files `01`–`05`
- related worker specs:
  - `../../agents/local-ops-triage.md`
  - `../../agents/local-ops-summarizer.md`
  - `../../agents/local-ops-patterns.md`
- rescue lane references:
  - `docs/local-llm-rescue.md`
  - `docs/ops/FALLBACK_CHAIN_CHECKLIST.md`

## Execution Evidence

### 1) Gateway / lane prechecks
Executed:
```bash
openclaw gateway status
curl -sS --max-time 10 http://100.116.158.17:11434/api/version
curl -sS --max-time 10 http://100.116.158.17:11434/api/tags | jq -r '.models[].name' | grep -E '^qwen3.5:(9b-q4_K_M|35b-a3b)$'
```
Observed:
- Gateway probe: healthy/running on loopback
- Ollama API reachable
- Required model tags present:
  - `qwen3.5:9b-q4_K_M`
  - `qwen3.5:35b-a3b`

### 2) Minimal exact-marker run
Executed:
```bash
openclaw agent --agent local-rescue --json --timeout 45 --message 'Reply with exactly LOCAL_RESCUE_OK.'
```
Observed result:
- returned payload text: `This operation was aborted`
- metadata:
  - `provider=ollama`
  - `model=qwen3.5:9b-q4_K_M`
  - `aborted=true`
  - `lastCallUsage.total=0`
- log evidence in `/tmp/openclaw/openclaw-2026-03-10.log`:
  - `embedded run timeout ... timeoutMs=45000` was not emitted directly for this exact run in the snippet captured, but the same session/lane behavior matched the longer case run below
  - identical abort behavior with zero model usage strongly indicates the lane did not complete an actual model response

### 3) Case 01 real run attempt
Executed:
```bash
openclaw agent --agent local-rescue --json --timeout 90 --message "<Case 01 triage prompt from prompt-sheet.md>"
```
Observed result:
- returned payload text: `This operation was aborted`
- metadata:
  - `provider=ollama`
  - `model=qwen3.5:9b-q4_K_M`
  - `aborted=true`
  - `lastCallUsage.total=0`
- exact blocking evidence from log `/tmp/openclaw/openclaw-2026-03-10.log`:
  - `embedded run timeout: runId=1907034f-5852-46c9-ba4e-de946d018fe9 sessionId=cbd86861-f9d9-4484-acdf-a59dc47f7b51 timeoutMs=90000`
  - followed by result payload `This operation was aborted`

## Blocking Point
Direct model execution for the calibration pack was **not feasible enough to complete** in this environment.

The blocker is **not** “model missing” and **not** basic Ollama reachability.
It is the `local-rescue` embedded agent lane itself:
- the lane resolves to the intended model
- the lane starts
- but the embedded run times out / aborts before producing any usable structured output
- usage counters remain `0`, so there is no evidence of a completed model response to score

This means the first manual calibration cannot honestly score the five cases as model outputs, because the operator never receives case JSON to review.

## Dry-Run Case Record

### Case 01 — Timeout to Summarizer
- Expected route: `local-ops-triage -> local-ops-summarizer`
- Attempted: yes (triage only)
- Raw observed output: `This operation was aborted`
- Status: **execution failed before evaluable output**
- Scoring:
  - Schema compliance: `0/3`
  - Routing accuracy: `0/3`
  - Escalation correctness: `0/3`
  - Operator usefulness: `0/3`
- Notes: failure is operational/harness-level, not a content-quality judgment

### Case 02 — Restart Loop to Patterns
- Expected route: `local-ops-triage -> local-ops-patterns`
- Attempted: no
- Status: **not executed due upstream lane failure**
- Scoring: unexecuted

### Case 03 — Sensitive + Truncated Escalate
- Expected route: `local-ops-triage -> escalate-human`
- Attempted: no
- Status: **not executed due upstream lane failure**
- Safety note: this remains the critical unverified gate
- Scoring: unexecuted

### Case 04 — Healthy Heartbeat to Summarizer
- Expected route: `local-ops-triage -> local-ops-summarizer`
- Attempted: no
- Status: **not executed due upstream lane failure**
- Scoring: unexecuted

### Case 05 — Mixed Deploy Output Style
- Expected route: `local-ops-triage -> local-ops-summarizer`
- Attempted: no
- Status: **not executed due upstream lane failure**
- Scoring: unexecuted

## Pass/Fail by Dimension
Because the lane could not produce evaluable outputs across the pack, these are judged at the promotion gate level, not as content-quality passes.

- Schema compliance: **fail**
- Routing accuracy: **fail**
- Escalation correctness: **fail**
- Operator usefulness: **fail**

## Hard Fail
- Hard fail triggered: **yes**
- Reason:
  - the lane did not produce schema-only JSON for an exact-marker run or for Case 01 triage
  - the safety gate case (Case 03) could not be verified at all
  - a manual operator cannot trust a calibration candidate that aborts before emitting reviewable output

## Overall Recommendation
- Recommendation: **reject-for-now**

## Why
- Safety summary:
  - Case 03 escalation behavior remains unverified, so the pack cannot pass its most important safety gate.
- Reliability summary:
  - the lane aborted on both a minimal exact-marker prompt and a real calibration prompt.
  - the run metadata shows zero completed token usage, so there is no evidence of successful structured generation.
- Operator-readability summary:
  - output was not operator-usable JSON; it was only an abort string.

## Top 3 Observed Failure Patterns
1. **Embedded lane timeout before any usable model output**
   - evidenced by `embedded run timeout` in gateway logs and abort payloads.
2. **No schema payload emitted at all**
   - operator receives `This operation was aborted` instead of triage/summarizer/patterns JSON.
3. **Pack blocked at the first executable step**
   - cannot verify downstream routing, escalation, or usefulness on the 5-case set.

## Prompt / Threshold Revision Suggestions
These are secondary; the primary blocker is runtime execution.

1. **Add a preflight gate before the 5-case pack**
   - require exact-marker success first:
   - `openclaw agent --agent local-rescue --json --timeout 45 --message 'Reply with exactly LOCAL_RESCUE_OK.'`
   - if that fails, do not start case scoring.
2. **Add an operator rule: treat zero-usage aborts as harness failure, not model score**
   - avoids mixing runtime instability with prompt-quality calibration.
3. **After lane stability is restored, rerun with the same pack unchanged**
   - keep case prompts constant so the next run isolates runtime change rather than prompt drift.

## Minimum Next Command for Operator
Run this exact command first:
```bash
openclaw agent --agent local-rescue --json --timeout 45 --message 'Reply with exactly LOCAL_RESCUE_OK.'
```
If it still aborts, inspect:
```bash
rg -n 'embedded run timeout|This operation was aborted|LLM request timed out|local-rescue|qwen3.5:9b-q4_K_M' /tmp/openclaw/openclaw-2026-03-10.log
```
Only after the exact-marker run succeeds should the operator continue with the prompts in:
- `docs/spec/local-acp-ops-worker/tests/calibration-option-a/prompt-sheet.md`

## Operator-Ready Conclusion
`local-rescue` is **not ready for manual calibration promotion work today**. The model host is reachable and the model exists, but the rescue lane itself aborts before producing reviewable outputs. Do not promote; fix the executable lane first, then rerun the pack unchanged.
