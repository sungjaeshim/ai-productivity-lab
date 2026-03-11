# local-rescue mini diagnosis #02 — runtime model resolution

Date: 2026-03-10  
Scope: model metadata / runtime resolution only

## verdict
**weakens** runtime-resolution as the **primary** current cause, while confirming the `local-rescue` lane is **brittle/inconsistent**.

## evidence for
- `local-rescue` is configured to resolve to `ollama/qwen3.5:9b-q4_K_M`:
  - agent primary = `ollama/qwen3.5:9b-q4_K_M`
  - alias `local-rescue` = `ollama/qwen3.5:9b-q4_K_M`
- Historical runtime evidence shows real drift/mismatch:
  - `docs/local-llm-rescue.md` and `docs/ops/FALLBACK_CHAIN_CHECKLIST.md` record a 2026-03-08 canary where `agentMeta.model=qwen3:14b` while `systemPromptReport.model=qwen3.5:9b-q4_K_M`.
- Active provider catalog is incomplete for this lane:
  - `models.providers.ollama.models[]` contains `qwen3.5:35b-a3b`
  - it does **not** contain `qwen3.5:9b-q4_K_M`
- That means `local-rescue` depends on alias/agent-level resolution to a live model id that the provider catalog does not describe, which is a brittle agent-specific state.

## evidence against
- In the fresh 2026-03-10 wrapper comparison, runtime metadata matched the configured target:
  - `agentMeta.provider = ollama`
  - `agentMeta.model = qwen3.5:9b-q4_K_M`
  - `systemPromptReport.provider = ollama`
  - `systemPromptReport.model = qwen3.5:9b-q4_K_M`
- Raw Ollama also succeeded with the same model id (`qwen3.5:9b-q4_K_M`), so current failure is **not** explained by model-name resolution alone.
- Current wrapper failure signature is abort/timeout with zero surfaced usage, which points beyond simple wrong-model routing.

## what is ruled out
- **Ruled out as primary current explanation:** “wrapper is failing because it is currently resolving to the wrong model id.”
- **Ruled out:** missing-live-model on the Ollama host for `qwen3.5:9b-q4_K_M`.
- **Not ruled out:** model-resolution brittleness as a contributing factor, especially because the provider catalog omits the active 9B lane and historical runs showed metadata drift.

## minimum next safe action
Run one **no-change** comparison through the same embedded path using a catalog-present Ollama target (for example `local-rescue-q35-eval`) and compare:
1. resolved runtime metadata
2. request behavior
3. abort vs success

If the catalog-present lane behaves differently, that strengthens catalog/resolution brittleness as a contributor. If it aborts the same way, suspicion shifts further toward generic embedded-wrapper behavior.

## bottom line
`local-rescue` runtime resolution is **not clean**: there is historical model drift and the active 9B target is absent from the provider catalog. But on the latest fresh run, runtime metadata still resolved to the intended 9B model, so runtime-resolution mismatch is **not the best primary explanation for the current aborts**; it looks more like a brittle contributing condition than the main broken layer.
