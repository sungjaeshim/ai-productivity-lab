# local-rescue mini diagnosis #01 — agent/config

Date: 2026-03-10
Scope: agent definition + config/catalog only

## verdict
**supports** agent-definition/config as a plausible primary cause.

## evidence for
- `local-rescue` agent is pinned to `ollama/qwen3.5:9b-q4_K_M` with no fallbacks:
  - `agents.list[].id=local-rescue`
  - `model.primary=ollama/qwen3.5:9b-q4_K_M`
  - `subagents.model.primary=ollama/qwen3.5:9b-q4_K_M`
- Docs point the same lane at `qwen3.5:9b-q4_K_M`:
  - `docs/local-llm-rescue.md`
  - `docs/ops/FALLBACK_CHAIN_CHECKLIST.md`
- **But the active Ollama provider catalog in `~/.openclaw/openclaw.json` does not list `qwen3.5:9b-q4_K_M` at all.** It lists:
  - `hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q4_K_M`
  - `hf.co/unsloth/Qwen3-30B-A3B-GGUF:Q3_K_M`
  - `qwen3:14b`
  - `qwen3.5:35b-a3b`
- Live Ollama `/api/tags` **does** list `qwen3.5:9b-q4_K_M`, so runtime reality and provider catalog are currently out of sync.
- That makes `local-rescue` uniquely brittle versus `local-rescue-q35-eval`, whose primary (`qwen3.5:35b-a3b`) is present in both the agent config and provider catalog.

## evidence against
- Current `local-rescue` agent definition itself is internally simple and not obviously malformed:
  - no fallback chain
  - minimal tools
  - skills disabled
  - memory search disabled
- Current docs and current agent definition agree on the intended target (`qwen3.5:9b-q4_K_M`).
- Raw Ollama sees the 9B model live, so this is **not** a simple “model missing from Ollama host” case.

## what is ruled out
- Not ruled in as a stale `qwen3:14b` active agent definition problem: current `local-rescue` is set to `qwen3.5:9b-q4_K_M`, not `qwen3:14b`.
- Not an obvious main-fallback contamination issue: `local-rescue` is still documented/configured as an isolated manual lane, not attached to the main fallback chain.
- Not a missing-live-model problem for 9B on the Ollama host at check time.

## minimum next safe action
- Do a **single no-change validation** of how OpenClaw resolves `local-rescue` model metadata at runtime versus `models.providers.ollama.models[]` resolution.
- Specifically compare:
  1. resolved agent model id for `local-rescue`
  2. provider catalog entry used for that model
  3. whether missing provider-catalog metadata for `qwen3.5:9b-q4_K_M` causes wrapper-specific failure while raw Ollama still works

## bottom line
Config is **not clean**: the `local-rescue` lane target is live and documented, but its model id is absent from the active provider catalog. That is a real agent/config inconsistency and makes an agent-specific config-layer explanation more plausible than a fully generic wrapper failure.