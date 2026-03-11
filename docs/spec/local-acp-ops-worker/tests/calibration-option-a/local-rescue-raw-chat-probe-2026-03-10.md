# local-rescue raw Ollama `/api/chat` separation probe — 2026-03-10

## Summary
Long-timeout raw Ollama `/api/chat` probes **succeeded** on both:
- `qwen3.5:9b-q4_K_M` (the current documented `local-rescue` lane target)
- `qwen3.5:35b-a3b` (quick comparison model already documented for q35 eval)

This means the current evidence **does not support “pure Ollama generation failure” as the blocker**. At probe time, the Ollama host responded normally and returned the exact marker. Suspicion now shifts back to the **OpenClaw embedded wrapper / session / timeout integration path**.

## Lane selection
Documented local-rescue lane target found in existing docs:
- `docs/local-llm-rescue.md`: current lane target `ollama/qwen3.5:9b-q4_K_M`
- `docs/ops/FALLBACK_CHAIN_CHECKLIST.md`: `local-rescue` primary `ollama/qwen3.5:9b-q4_K_M`

So the primary probe used **`qwen3.5:9b-q4_K_M`**, not an undocumented guess.

## Probe prompt
Minimal exact-marker prompt used:
- `Reply with exactly LOCAL_RESCUE_OK.`

Low generation budget used:
- `temperature: 0`
- `num_predict: 8`
- `stream: false`
- `think: false`

## Commands run
```bash
python3 /tmp/ollama_probe.py qwen3.5:9b-q4_K_M 180
python3 /tmp/ollama_probe.py qwen3.5:35b-a3b 180
```

Probe body:
```json
{
  "model": "<model>",
  "messages": [{"role": "user", "content": "Reply with exactly LOCAL_RESCUE_OK."}],
  "stream": false,
  "think": false,
  "options": {"temperature": 0, "num_predict": 8}
}
```

## Evidence

### 1) `qwen3.5:9b-q4_K_M` (current local-rescue lane)
- HTTP reachability:
  - `/api/version`: OK in `0.142s`
  - `/api/tags`: OK in `0.083s`
  - `/api/ps`: OK in `0.072s`
- `/api/chat` result:
  - HTTP `200`
  - completed in `3.136s`
  - valid JSON returned
  - `done: true`
  - `message.content: "LOCAL_RESCUE_OK"`
- timing metadata from Ollama:
  - `load_duration: 110219302` ns (~`0.11s`)
  - `total_duration: 3063807534` ns (~`3.06s`)

Raw response excerpt:
```json
{"model":"qwen3.5:9b-q4_K_M","message":{"role":"assistant","content":"LOCAL_RESCUE_OK"},"done":true,"total_duration":3063807534,"load_duration":110219302}
```

### 2) `qwen3.5:35b-a3b` (quick comparison probe)
- HTTP reachability:
  - `/api/version`: OK in `0.115s`
  - `/api/tags`: OK in `0.071s`
  - `/api/ps`: OK in `0.072s`
- `/api/chat` result:
  - HTTP `200`
  - completed in `18.700s`
  - valid JSON returned
  - `done: true`
  - `message.content: "LOCAL_RESCUE_OK"`
- timing metadata from Ollama:
  - `load_duration: 14434398986` ns (~`14.43s`)
  - `total_duration: 18609873240` ns (~`18.61s`)

Raw response excerpt:
```json
{"model":"qwen3.5:35b-a3b","message":{"role":"assistant","content":"LOCAL_RESCUE_OK"},"done":true,"total_duration":18609873240,"load_duration":14434398986}
```

## Separation verdict

### What is established
- **HTTP responds**: yes, quickly, on version/tags/ps and on `/api/chat`.
- **Valid completion returned**: yes, exact marker returned on both models.
- **Timeout behavior**:
  - 9B lane completed comfortably inside timeout (`~3.1s`).
  - q35 completed inside timeout but much slower (`~18.7s`, mostly load time).

### Final isolation result
**At the time of this probe, raw Ollama generation is working.**

So this probe **shifts suspicion back to OpenClaw wrapper/integration behavior** rather than isolating Ollama generation as the active blocker.

Most likely interpretation now:
1. Ollama itself can serve the exact-marker request correctly.
2. The failure seen in `openclaw agent --agent local-rescue ...` is more likely in the embedded path:
   - session reuse / transcript state,
   - wrapper request shaping,
   - timeout budgeting,
   - or other OpenClaw integration overhead.

## Concise conclusion
The recommended long-timeout raw `/api/chat` probe **passed**. Current separation verdict:
- **Not a pure Ollama generation failure at probe time**
- **Primary suspicion shifts back to OpenClaw embedded wrapper/session integration**
