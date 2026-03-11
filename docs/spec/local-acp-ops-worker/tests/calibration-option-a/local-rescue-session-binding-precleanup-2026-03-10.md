# local-rescue session binding pre-cleanup snapshot — 2026-03-10

## Scope
Capture the current affected `local-rescue` session-store state before any cleanup.

## Active stale binding observed
- session key: `agent:local-rescue:main`
- session id: `diag-local-rescue-local-1773106936`
- session file: `/root/.openclaw/agents/local-rescue/sessions/bc880227-6574-474f-9501-36db7e3fc73d.jsonl`
- updatedAt: `1773109921507` (`2026-03-10T02:32:01.507000+00:00`)
- provider/model: `ollama / qwen3.5:9b-q4_K_M`
- contextTokens: `200000`
- abortedLastRun: `true`
- `systemPromptReport.sessionKey`: `agent:local-rescue:main`
- `systemPromptReport.sessionId`: `diag-local-rescue-local-1773106936`

## Session file snapshot
- line count: `97`
- byte count: `34730`
- earliest visible model in file head: `qwen3:14b`
- latest visible events in file tail: repeated exact-marker attempts ending in `This operation was aborted`

## Why this qualifies as stale binding evidence
- The long-lived `agent:local-rescue:main` binding still points at a reused diagnostic session id.
- The bound transcript file contains mixed historical model state (`qwen3:14b` head, `qwen3.5:9b-q4_K_M` tail).
- Tail entries show repeated exact-marker retries appending aborts into the same bound session history.

## Safety plan
- Do not delete evidence.
- Archive the current bound transcript file under the same session-store tree.
- Remove only the `agent:local-rescue:main` mapping from `sessions.json` so the next run can create a fresh binding.
