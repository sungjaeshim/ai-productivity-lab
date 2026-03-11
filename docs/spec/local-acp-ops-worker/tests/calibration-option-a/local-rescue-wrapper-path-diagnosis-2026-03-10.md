# local-rescue wrapper-path diagnosis — 2026-03-10

## Scope
Diagnosis only. No config changes, no restarts.

Question isolated here:
Why does `openclaw agent --agent local-rescue --json ...` abort while raw Ollama `/api/chat` can succeed for the same model and prompt?

## Narrowed conclusion
**Most likely current break is in the OpenClaw embedded wrapper path, with two strong contributing inconsistencies: (a) stale/incomplete local-rescue integration state, and (b) session identity mismatch behavior.**

The strongest evidence is that:
- raw Ollama can return `LOCAL_RESCUE_OK` for `qwen3.5:9b-q4_K_M`
- the wrapper reaches the intended provider/model identity
- but the wrapper still ends in `embedded run timeout` + `This operation was aborted` + `lastCallUsage.total=0`

So the request is reaching the intended local lane, but usable completion is not being surfaced through the embedded runner.

## Likely root-cause ranking inside wrapper path

### 1) Embedded runner / wrapper integration defect — **most likely**
Why this ranks #1:
- Same model, same prompt, raw Ollama succeeds.
- Wrapper path fails before usable content is surfaced.
- The failure signature is internal timeout/abort, not model-not-found.

Evidence for:
- Side-by-side report: raw `/api/chat` returned `LOCAL_RESCUE_OK` in ~3.23s, while wrapper returned `This operation was aborted` in ~45s.
- Wrapper metadata still showed intended lane identity:
  - `provider: ollama`
  - `model: qwen3.5:9b-q4_K_M`
- Failure signature from wrapper run:
  - `aborted: true`
  - `stopReason: error`
  - `lastCallUsage.total: 0`
- Gateway log captured:
  - `embedded run timeout: ... timeoutMs=45000`
- Current dist code still uses generic Ollama streaming path:
  - `stream: true`
  - `num_ctx: model.contextWindow ?? 65536`
  rather than the documented local-rescue hardening behavior.

Evidence against:
- None stronger than the above in current evidence.

### 2) Stale/incomplete local-rescue integration state (catalog/patch drift) — **strong contributor**
Why this ranks #2:
- The active local-rescue lane is documented and configured for `qwen3.5:9b-q4_K_M`, but the provider catalog does not currently list that model entry.
- The saved local-rescue runtime patch snapshot is partly stale versus current dist filenames.

Evidence for:
- `openclaw.json` agent definition points `local-rescue` at `ollama/qwen3.5:9b-q4_K_M`.
- `agents.defaults.models` also defines alias `local-rescue` for that same model.
- But `models.providers.ollama.models` currently includes:
  - `hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q4_K_M`
  - `hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q3_K_M`
  - `qwen3:14b`
  - `qwen3.5:35b-a3b`
  and **does not include** `qwen3.5:9b-q4_K_M`.
- `patches/local-rescue-runtime/README.md` says local-rescue hardening should include:
  - fresh local-rescue run sessions
  - reduced local-rescue prompt mode
  - `stream:false`
  - `num_ctx=4096`
  - default timeout pinned to `15s`
- But the restore script still references missing legacy dist targets such as:
  - `model-selection-BU6wl1le.js`
  - `model-selection-L7RMwsG-.js`
  - `pi-embedded-C6ITuRXf.js`
  - `pi-embedded-DoQsYfIY.js`
- Current dist instead contains newer files such as:
  - `model-selection-C8ExQCsd.js`
  - `model-selection-Dovilo6b.js`
  - `model-selection-n7SaaZtn.js`
- Current dist snippet shows `stream: true`, which directly conflicts with the documented local-rescue hardening snapshot.

Evidence against:
- Wrapper metadata still reports the intended model string, so this is not a simple “wrong model routed elsewhere” failure.

Interpretation:
- This looks less like a bad user-facing agent definition and more like **wrapper internals not fully aligned with the documented local-rescue lane assumptions**.

### 3) Session key / session id mismatch or stale transcript reuse — **real signal, but secondary**
Why this ranks #3:
- Fresh `--session-id` did not resolve the issue, but the wrapper still shows inconsistent identity fields.

Evidence for:
- Fresh wrapper invocation still failed.
- The failing run showed:
  - `systemPromptReport.sessionId = diag-local-rescue-local-1773106936`
  - `systemPromptReport.sessionKey = agent:local-rescue:main`
  - `agentMeta.sessionId = bc880227-6574-474f-9501-36db7e3fc73d`
- Existing local docs already warned about rescue-lane metadata mismatch and stale routing/reporting behavior.

Evidence against:
- A fresh session id did not clear the failure.
- The exact-marker prompt is tiny; transcript bloat alone is not a satisfying primary explanation.

Interpretation:
- This is probably a **symptom of wrapper session plumbing** rather than the sole blocker.

### 4) Timeout budget too short / not aligned with local lane — **possible symptom, not best primary cause**
Evidence for:
- Wrapper run dies exactly on an embedded timeout boundary (`45000ms`).
- The saved runtime snapshot expected a special local-rescue timeout policy, but current run behavior does not reflect that hardened state.

Evidence against:
- Raw 9B Ollama probe succeeded in ~3.23s on the same exact-marker prompt.
- So the main issue is not that 45s is objectively too short for the model on this probe.

Interpretation:
- Timeout is the **observed failure mode**, but likely because the wrapper path fails to complete correctly, not because the model inherently needs more time for this request.

### 5) Wrong or stale user-facing agent definition — **least likely of the listed causes**
Evidence for:
- There is stale local-rescue patch/documentation state around the wrapper path.

Evidence against:
- The current agent definition itself is coherent and minimal:
  - workspace-local-rescue
  - no skills
  - memorySearch disabled
  - minimal tools
  - primary model string set to the intended 9B lane
- Wrapper metadata reflects that same intended model.

Interpretation:
- The visible agent definition is probably not the main bug. The fragility looks deeper in the wrapper/runtime layer.

## What appears agent-specific vs wrapper-generic

### Agent-specific / local-rescue-specific
- `local-rescue` depends on a model id (`qwen3.5:9b-q4_K_M`) that is **not present in the configured provider model catalog**.
- `local-rescue` has a documented hardening snapshot, but that snapshot appears only partially applicable to the current build because some target dist filenames no longer exist.
- Historical docs for this lane already note metadata/reporting inconsistencies.

### Broader wrapper-generic
- Raw Ollama success + embedded wrapper abort means the **generic embedded execution path** is implicated, not the model alone.
- The session-id/session-key inconsistency looks like a wrapper/session-plumbing issue, not just a bad prompt.
- Current dist code path for Ollama streaming appears generic rather than local-rescue-specialized.

## Minimum next safe action
No restart, no config change.

Best next safe validation:
1. **Compare one non-local agent on the same Ollama provider through the same embedded path**
   - goal: determine whether the abort is `local-rescue`-specific or any embedded Ollama agent can reproduce it
   - keep the prompt as the same exact marker
2. **Capture one fresh wrapper run and one fresh raw run back-to-back again**
   - confirm the failure remains contemporaneous, not intermittent drift
3. **Inspect the active dist path that constructs embedded Ollama requests for model resolution**
   - specifically whether missing provider-catalog entry for `qwen3.5:9b-q4_K_M` causes fallback/default model shaping

## Key evidence references
- `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-side-by-side-comparison-2026-03-10.md`
- `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-raw-chat-probe-2026-03-10.md`
- `/root/.openclaw/openclaw.json`
- `/root/.openclaw/workspace/patches/local-rescue-runtime/README.md`
- `/root/.openclaw/workspace/scripts/reapply-local-rescue-runtime.sh`
- `/tmp/openclaw/openclaw-2026-03-10.log`
- current dist snippets under `/usr/lib/node_modules/openclaw/dist/model-selection-*.js`

## Proof bundle

### Files touched
- Added:
  - `docs/spec/local-acp-ops-worker/tests/calibration-option-a/local-rescue-wrapper-path-diagnosis-2026-03-10.md`

### Key evidence
- Raw Ollama success exists for the same model/prompt (`LOCAL_RESCUE_OK` in ~3.23s).
- Wrapper run for same model/prompt aborts in ~45s with:
  - `embedded run timeout`
  - `This operation was aborted`
  - `lastCallUsage.total = 0`
- `openclaw.json` local-rescue agent points to `ollama/qwen3.5:9b-q4_K_M`, but the provider catalog omits that model entry.
- Saved local-rescue patch notes expect `stream:false` + `num_ctx=4096` + local-rescue session hardening, but current dist shows generic `stream:true` behavior and the patch script references partly missing legacy dist filenames.
- Fresh `--session-id` did not prevent the wrapper failure; session metadata still showed mismatched ids.

### Narrowed diagnosis
**Current highest-probability diagnosis: embedded wrapper/integration defect, amplified by stale local-rescue integration drift (catalog + patch drift), with session-identity mismatch as a secondary symptom.**