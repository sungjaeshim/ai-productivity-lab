# non-rescue embedded agent comparison — 2026-03-10

## Chosen agent
- **Agent used:** `local-rescue-q35-eval`
- **Why this one:** there is **no truly non-rescue Ollama-backed agent** defined in the current `~/.openclaw/openclaw.json`; this is the closest available control lane because it is a **separate embedded agent** from `local-rescue`, uses a **different Ollama model** (`qwen3.5:35b-a3b`), has its **own workspace/session key**, and its model is **present in the provider catalog**.

## Exact-marker result
Prompt used:
- `Reply with exactly LOCAL_RESCUE_OK.`

### Raw Ollama probe for the same model
- **Pass**
- Model: `qwen3.5:35b-a3b`
- Result: `LOCAL_RESCUE_OK`
- Timing: `total_duration ≈ 17.50s`, `load_duration ≈ 13.83s`

### Embedded wrapper run
- **Fail**
- Command target: `openclaw agent --agent local-rescue-q35-eval --json --timeout 45 ...`
- Result payload text: `This operation was aborted`
- `aborted: true`
- `durationMs: 45080`
- `agentMeta.provider/model: ollama / qwen3.5:35b-a3b`
- `agentMeta.lastCallUsage.total: 0`
- `systemPromptReport.sessionKey: agent:local-rescue-q35-eval:main`

## Comparison vs established `local-rescue` behavior
This fresh q35 control run matches the already-established `local-rescue` wrapper failure shape closely:
- raw Ollama succeeds on the same exact-marker prompt
- embedded wrapper returns only `This operation was aborted`
- abort lands right at the wrapper timeout budget (~45s)
- usage stays at zero
- model/provider metadata still resolves to Ollama correctly

## What this says
- This is **not just a `local-rescue`-specific failure**.
- Current evidence points to a **broader embedded Ollama wrapper/runtime instability**.
- `local-rescue` may still have extra lane-specific brittleness, but that does **not** explain the full failure pattern by itself because a separate Ollama-backed embedded lane reproduces it.

## Minimum next safe action
- **Do not change config yet.**
- Inspect the active embedded Ollama wrapper/runtime path for why successful raw model responses are not surfacing before timeout.
- Any `local-rescue`-only catalog/patch fix should wait until that generic wrapper path is explained.

## Proof bundle
### Commands run
```bash
curl -sS -o /tmp/nonrescue-q35-raw-20260310-1232.json -X POST 'http://100.116.158.17:11434/api/chat' \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"qwen3.5:35b-a3b","messages":[{"role":"user","content":"Reply with exactly LOCAL_RESCUE_OK."}],"stream":false,"think":false,"options":{"temperature":0,"num_predict":8}}'

openclaw agent --agent local-rescue-q35-eval --json --timeout 45 \
  --session-id diag-nonrescue-q35-20260310-1232 \
  --message 'Reply with exactly LOCAL_RESCUE_OK.' \
  > /tmp/nonrescue-q35-wrapper-20260310-1232.json
```

### Files touched
- Added: `docs/spec/local-acp-ops-worker/tests/calibration-option-a/non-rescue-embedded-agent-comparison-2026-03-10.md`
- Evidence captured:
  - `/tmp/nonrescue-q35-raw-20260310-1232.json`
  - `/tmp/nonrescue-q35-wrapper-20260310-1232.json`

### Comparison verdict
- **Verdict:** broader embedded Ollama wrapper failure reproduced; not isolated to `local-rescue`.
