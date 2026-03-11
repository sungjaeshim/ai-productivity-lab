# local-rescue mini-diagnosis #3 — session mismatch / stale reuse — 2026-03-10

## verdict
**supports** for session mismatch / stale transcript reuse as a primary plausible cause of the current `local-rescue` wrapper aborts.

## evidence for
- Fresh wrapper invocation still did **not** get an isolated transcript path in practice:
  - side-by-side run used `--session-id diag-local-rescue-20260310-110433`
  - wrapper metadata still reported `systemPromptReport.sessionKey = agent:local-rescue:main`
  - `agentMeta.sessionId = bc880227-6574-474f-9501-36db7e3fc73d`
  - `systemPromptReport.sessionId = diag-local-rescue-local-1773106936`
- Session store shows the active key `agent:local-rescue:main` currently maps to:
  - `sessionId = diag-local-rescue-local-1773106936`
  - but `sessionFile = .../bc880227-6574-474f-9501-36db7e3fc73d.jsonl`
- That same old `bc880...jsonl` file contains many later runs under **different** logical session ids, including:
  - `cbd86861-f9d9-4484-acdf-a59dc47f7b51`
  - `diag-local-rescue-local-1773106936`
  - plus runIds whose `sessionId` stayed pinned to an older id while runId changed
- The reused transcript file also contains older incompatible history, including early `qwen3:14b` 404/fetch-failed runs from 2026-03-06 before later `qwen3.5:9b-q4_K_M` aborts.
- This points to **session-key-level binding to a stale backing transcript file**, not clean per-run isolation.

## evidence against
- The wrapper failure still surfaces as an explicit `embedded run timeout` / abort path, so a generic wrapper timeout mechanism is definitely present.
- Fresh logical session ids do appear in metadata and in prompt-error records, so the system is not ignoring new ids completely; it is mixing them with an older backing session/file.

## what is ruled out
- Not a clean "fresh `--session-id` always gives a fresh isolated run" story for `local-rescue`.
- Not a simple raw-model failure explanation: raw Ollama succeeded on the same marker prompt while wrapper runs kept appending aborts into the reused local-rescue session file.
- Not just one bad run id: the same reuse pattern appears across multiple run ids and session ids.

## minimum next safe action
- Run one **no-change** validation comparing transcript/file behavior for:
  1. `local-rescue` with fresh `--session-id`
  2. one other local agent/lane with fresh `--session-id`
- Goal: confirm whether this is `local-rescue`-specific session binding breakage or broader embedded session-handling fragility.
