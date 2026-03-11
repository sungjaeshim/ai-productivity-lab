# local-rescue post-cleanup wrapper-timeout diagnosis — 2026-03-10

## Scope
Post-session-cleanup diagnosis only. No config changes, no restarts.

## Bottom line
After the stale `local-rescue` main-session binding was cleaned up, the wrapper path still fails on a **fresh session**. The strongest current read is:

1. **embedded wrapper/runtime path is failing before any usable model call completes**
2. this is **not limited to `local-rescue`**; another local Ollama lane reproduces it
3. `local-rescue` still has **catalog/patch drift**, but that now looks more like a contributing factor than the primary blocker

## Top 3 remaining causes ranked

### 1) Embedded timeout/wrapper execution path is the primary failure point
**Why #1**
- Fresh `local-rescue` session still aborts with zero usage.
- Raising wrapper timeout from **45s to 120s** only makes it fail later; it does not produce tokens.

**Strongest evidence**
- Fresh post-cleanup run:
  - run `e5a0d11c-1cc6-4203-8302-89e43dcdda26`
  - `embedded run timeout ... timeoutMs=45000`
  - `durationMs: 45064`
  - `aborted: true`
  - fresh session id matched on both `agentMeta` and `systemPromptReport`: `e8ba8d7f-05db-4fcc-99f1-52bd40a00aa4`
- No-change 120s rerun:
  - run `6fc19138-dd43-478d-92c0-0d312231829e`
  - `embedded run timeout ... timeoutMs=120000`
  - `durationMs: 120061`
  - `lastCallUsage.total: 0`
  - payload still only `This operation was aborted`
- Raw Ollama for the same 9B model/prompt returned `LOCAL_RESCUE_OK` in ~3.23s.

**Interpretation**
- This is not “45s was simply too short.”
- The wrapper is hanging or never surfacing the model result, then dying on whatever timeout budget it is given.

### 2) Broader embedded local-agent wrapper instability, not just `local-rescue`
**Why #2**
- `local-rescue-q35-eval` reproduces the same failure signature on a different Ollama model.

**Strongest evidence**
- `local-rescue-q35-eval` exact-marker run:
  - run `fc15e2e0-a303-421b-8b81-2a56c3a9a8b5`
  - `embedded run timeout ... timeoutMs=45000`
  - model `qwen3.5:35b-a3b`
  - `durationMs: 45150`
  - `aborted: true`
  - `lastCallUsage.total: 0`
- Historical q35 session files show repeated Ollama aborts with zero usage across earlier dates as well.

**Interpretation**
- The remaining blocker is more likely in the **embedded local-agent/Ollama wrapper path generally** than in the `local-rescue` agent definition alone.

### 3) `local-rescue`-specific config/catalog/patch drift is real, but now secondary
**Why #3**
- `local-rescue` still has some local-lane inconsistencies that can amplify brittleness.
- But because q35 also fails in the same wrapper shape, this no longer looks like the first thing to fix blindly.

**Strongest evidence**
- `openclaw.json` agent/default alias points `local-rescue` to `ollama/qwen3.5:9b-q4_K_M`.
- `models.providers.ollama.models` currently includes `qwen3.5:35b-a3b` but **does not include** `qwen3.5:9b-q4_K_M`.
- `patches/local-rescue-runtime/README.md` documents old hardening assumptions (`stream:false`, `num_ctx=4096`, local-rescue timeout pinning), but current runtime behavior does not show that hardened path in effect.

**Interpretation**
- This drift is worth fixing later, but current evidence says it is more likely a **lane-specific aggravator** than the root cause of the post-cleanup timeout path.

## What is now ruled out after cleanup
- **Stale `local-rescue` main-session binding as the sole cause**
  - cleanup worked mechanically; a fresh session was created and still failed
- **Raw Ollama/model availability for the exact-marker probe**
  - raw `/api/chat` succeeded quickly on `qwen3.5:9b-q4_K_M`
- **Simple “45s timeout too short” explanation**
  - a 120s wrapper run still aborted with zero usage
- **Prompt/context overload**
  - exact-marker is tiny; injected system prompt is ~7.6k chars with no truncation

## Minimum next safe action
**Do a broader wrapper comparison first, not a config/catalog fix attempt.**

Safest next step:
1. run one more **non-rescue Ollama-backed embedded agent** on the same exact-marker prompt
2. compare raw Ollama vs embedded result shape again for that lane
3. then inspect the active embedded Ollama wrapper/model-resolution path in the current dist build

## Recommendation on next direction
- **Recommend: broader wrapper comparison first**
- **Do not** start with a config/catalog fix attempt yet

Reason:
- The new q35 reproduction plus the 120s no-change rerun both point to a broader embedded wrapper/runtime problem.
- A local-rescue-only catalog patch could be a distraction if the generic embedded Ollama path is what is actually broken.

## Proof bundle

### Files touched
- Added:
  - `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-post-cleanup-wrapper-timeout-diagnosis-2026-03-10.md`

### Evidence used
- `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-fast-path-execution-report-2026-03-10.md`
- `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-side-by-side-comparison-2026-03-10.md`
- `/tmp/openclaw/openclaw-2026-03-10.log`
- `/root/.openclaw/agents/local-rescue/sessions/e8ba8d7f-05db-4fcc-99f1-52bd40a00aa4.jsonl`
- `/root/.openclaw/agents/local-rescue-q35-eval/sessions/*.jsonl`
- `/root/.openclaw/openclaw.json`
- `/root/.openclaw/workspace/patches/local-rescue-runtime/README.md`

### Narrowed recommendation
**Primary diagnosis:** embedded local-agent wrapper/runtime path is failing before token generation is surfaced.

**Best next move:** compare one more non-rescue Ollama embedded lane before attempting any `local-rescue`-specific config/catalog fix.