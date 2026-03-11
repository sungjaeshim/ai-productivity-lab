# local-rescue fast-path execution report — 2026-03-10

## Ordered outcome
1. **Pre-change snapshot recorded**
   - File: `local-rescue-session-binding-precleanup-2026-03-10.md`
2. **Session binding cleanup executed**
   - Archived stale binding key: `agent:local-rescue:main`
   - Archived stale session id: `diag-local-rescue-local-1773106936`
   - Archived stale transcript:
     - from: `/root/.openclaw/agents/local-rescue/sessions/bc880227-6574-474f-9501-36db7e3fc73d.jsonl`
     - to: `/root/.openclaw/agents/local-rescue/sessions/archive-20260310-115622/bc880227-6574-474f-9501-36db7e3fc73d.jsonl.archived`
   - Backed up and rewrote only:
     - `/root/.openclaw/agents/local-rescue/sessions/sessions.json`
   - Backup bundle:
     - `/root/.openclaw/agents/local-rescue/sessions/archive-20260310-115622/`
3. **Exact-marker rerun executed**
   - Command:
     - `openclaw agent --agent local-rescue --json --timeout 45 --message 'Reply with exactly LOCAL_RESCUE_OK.'`
   - Result: **failed**
4. **5-case calibration pack**
   - **Not run**, because step 3 did not pass.

## What changed
- Removed only the stale `agent:local-rescue:main` mapping from the live session index.
- Archived the previously bound transcript instead of deleting it.
- Did not touch gateway config, runtime config, services, or unrelated files.

## What was validated
- The stale reused binding was real before cleanup:
  - `sessions.json` pointed `agent:local-rescue:main` to `diag-local-rescue-local-1773106936`
  - bound transcript mixed old `qwen3:14b` history with later `qwen3.5:9b-q4_K_M` aborts
- The cleanup worked mechanically:
  - post-cleanup, the old `agent:local-rescue:main` mapping was gone
  - rerun recreated `agent:local-rescue:main` with a **fresh** session id: `e8ba8d7f-05db-4fcc-99f1-52bd40a00aa4`
  - new session file was fresh and tiny (`7` lines, `1703` bytes)

## Exact-marker result
- **Pass? No**
- Fresh-session evidence:
  - new session id: `e8ba8d7f-05db-4fcc-99f1-52bd40a00aa4`
  - new session file: `/root/.openclaw/agents/local-rescue/sessions/e8ba8d7f-05db-4fcc-99f1-52bd40a00aa4.jsonl`
  - session tail shows one user marker prompt followed by:
    - `openclaw:prompt-error ... error=aborted`
    - assistant error message: `This operation was aborted`
- CLI-visible failure:
  - payload text: `Request timed out before a response was generated. Please try again, or increase agents.defaults.timeoutSeconds in your config.`
  - `durationMs`: `45064`
  - `meta.aborted`: `true`

## 5-case result summary
- **Not applicable / not run**
- Reason: exact-marker preflight failed after clean rebinding.

## Final recommendation
- **reject-for-now**

## Risks / follow-ups
- Session-store stale binding was **a real contributor**, but **not sufficient** to restore functionality.
- Current blocker after fresh rebinding is still in the execution path beyond stale session reuse (likely wrapper/runtime timeout behavior already seen in prior evidence).
- Next safe follow-up should focus on non-session causes using the fresh-session evidence now captured; do **not** claim the lane is fixed based on cleanup alone.
