# Fallback Chain Checklist

Updated: 2026-03-08

## Current Production Chain

- `agents.defaults.model`: `openai/gpt-5.4 -> zai/glm-5 -> zai/glm-4.7`
- `agents.defaults.subagents.model`: `zai/glm-4.7 -> zai/glm-5`
- `canary-safe`: `zai/glm-4.7-flash -> zai/glm-4.7`
- `local-rescue`: isolated manual lane only
- `local-rescue-q35-eval`: isolated eval lane only

## Expected State

- main production traffic prefers `gpt-5.4`
- cloud fallback is limited to GLM providers only
- no local Ollama model is attached to the main fallback chain
- `local-rescue` points to a live experimental model id
- `local-rescue-q35-eval` stays pinned to `qwen3.5:35b-a3b`

## Config Verification

Run:

```bash
openclaw config get agents.defaults.model
openclaw config get agents.defaults.subagents.model
openclaw config get agents.list[4].model
openclaw config get agents.list[5].model
openclaw config get agents.list[6].model
```

Expect:

- defaults model primary: `openai/gpt-5.4`
- defaults model fallbacks: `zai/glm-5`, `zai/glm-4.7`
- defaults subagents primary: `zai/glm-4.7`
- defaults subagents fallbacks: `zai/glm-5`
- `canary-safe` primary: `zai/glm-4.7-flash`
- `local-rescue` primary: `ollama/qwen3.5:9b-q4_K_M`
- `local-rescue-q35-eval` primary: `ollama/qwen3.5:35b-a3b`

## Ollama Verification

Run:

```bash
curl -sS --max-time 10 http://100.116.158.17:11434/api/tags | jq -r '.models[].name'
```

Confirm:

- `qwen3.5:9b-q4_K_M` exists
- `qwen3.5:35b-a3b` exists
- stale ids like `qwen3:14b` are not used by active rescue lanes

## Canary Verification

Run:

```bash
bash /root/.openclaw/workspace/scripts/local-rescue-canary.sh
```

Pass means:

- Ollama `/api/version` responds
- `qwen3.5:9b-q4_K_M` exists on the configured host
- `openclaw agent --agent local-rescue` completes without gateway or missing-model errors

Fail means:

- keep `local-rescue` manual only
- do not attach any local model to the main fallback chain
- record the failure against the rescue revalidation report
- inspect model metadata carefully if embedded fallback runs:
  - on 2026-03-08, `agentMeta.model` still showed `qwen3:14b`
  - while `systemPromptReport.model` showed `qwen3.5:9b-q4_K_M`
  - treat that as a routing or reporting inconsistency until explained

## Promotion Rule

Only revisit local-model promotion after:

- gateway reachability is healthy
- exact-marker prompt is stable
- fixed-format prompt is stable
- output lands in `response` or `message.content`
- rescue latency is within the practical timeout budget

Reference:

- `docs/local-llm-rescue.md`
- `docs/local-rescue-q35-eval.md`
- `reports/local-rescue-revalidation-2026-03-08.md`
