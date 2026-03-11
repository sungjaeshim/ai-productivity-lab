# local-rescue side-by-side comparison — raw Ollama vs `openclaw agent` — 2026-03-10

## Goal
Run the same exact-marker prompt as close together as practical through:
1. raw Ollama `/api/chat`
2. `openclaw agent --agent local-rescue --json ...`

Prompt used in both paths:
- `Reply with exactly LOCAL_RESCUE_OK.`

Raw model required by the documented `local-rescue` lane:
- `qwen3.5:9b-q4_K_M`

## Separation verdict
**Current broken layer: the OpenClaw wrapper / embedded run path, not raw Ollama generation.**

Why:
- Raw Ollama returned `LOCAL_RESCUE_OK` successfully in ~3.2s.
- Wrapper path returned only `This operation was aborted` after ~45s.
- Wrapper metadata shows `provider=ollama` and `model=qwen3.5:9b-q4_K_M`, but `lastCallUsage.total=0` and `aborted=true`.
- Gateway log shows `embedded run timeout` for the same wrapper run id.

So the request reaches the intended lane/model identity, but the failure occurs in the wrapper/embedded execution path before any usable model content is surfaced.

---

## Side-by-side evidence

### A) Raw Ollama `/api/chat`
Command run:
```bash
/usr/bin/time -f 'elapsed=%E exit=%x' sh -lc \
  "curl -sS -D /tmp/local-rescue-raw-20260310-110430.headers \
    -o /tmp/local-rescue-raw-20260310-110430.json \
    -X POST http://100.116.158.17:11434/api/chat \
    -H 'Content-Type: application/json' \
    --data-binary '{\"model\":\"qwen3.5:9b-q4_K_M\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly LOCAL_RESCUE_OK.\"}],\"stream\":false,\"think\":false,\"options\":{\"temperature\":0,\"num_predict\":8}}'"
```

Result summary:
- success/failure: **success**
- wall time: **3.23s**
- exit code: **0**
- HTTP return shape: **HTTP/1.1 200 OK**, JSON body
- usable content: **yes**
- exact content: **`LOCAL_RESCUE_OK`**

HTTP headers:
```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Date: Tue, 10 Mar 2026 02:04:33 GMT
Content-Length: 320
```

Body excerpt:
```json
{"model":"qwen3.5:9b-q4_K_M","created_at":"2026-03-10T02:04:33.619367455Z","message":{"role":"assistant","content":"LOCAL_RESCUE_OK"},"done":true,"done_reason":"stop","total_duration":3090554631,"load_duration":121107419,"prompt_eval_count":21,"prompt_eval_duration":1758068122,"eval_count":6,"eval_duration":1164772062}
```

Parsed evidence:
```json
{
  "done": true,
  "model": "qwen3.5:9b-q4_K_M",
  "content": "LOCAL_RESCUE_OK",
  "total_duration": 3090554631,
  "load_duration": 121107419
}
```

### B) `openclaw agent --agent local-rescue --json ...`
Command run:
```bash
/usr/bin/time -f 'elapsed=%E exit=%x' sh -lc \
  "openclaw agent --agent local-rescue --json --timeout 45 \
    --session-id diag-local-rescue-20260310-110433 \
    --message 'Reply with exactly LOCAL_RESCUE_OK.' \
    > /tmp/local-rescue-wrapper-20260310-110433.json"
```

Result summary:
- success/failure: **failure at content layer**
- wall time: **48.37s**
- exit code: **0**
- CLI return shape: **JSON object** with `status:"ok"` / `summary:"completed"`, but aborted payload
- usable content: **no model answer**
- returned payload text: **`This operation was aborted`**

Body excerpt:
```json
{
  "runId": "c32f5279-47fe-4302-8c99-d0ef7d207c7a",
  "status": "ok",
  "summary": "completed",
  "result": {
    "payloads": [
      {
        "text": "This operation was aborted",
        "mediaUrl": null
      }
    ],
    "meta": {
      "durationMs": 45072,
      "agentMeta": {
        "sessionId": "bc880227-6574-474f-9501-36db7e3fc73d",
        "provider": "ollama",
        "model": "qwen3.5:9b-q4_K_M",
        "lastCallUsage": {
          "input": 0,
          "output": 0,
          "cacheRead": 0,
          "cacheWrite": 0,
          "total": 0
        }
      },
      "aborted": true,
      "systemPromptReport": {
        "sessionId": "diag-local-rescue-local-1773106936",
        "sessionKey": "agent:local-rescue:main",
        "provider": "ollama",
        "model": "qwen3.5:9b-q4_K_M"
      },
      "stopReason": "error"
    }
  }
}
```

Parsed evidence:
```json
{
  "status": "ok",
  "summary": "completed",
  "payload_text": "This operation was aborted",
  "durationMs": 45072,
  "aborted": true,
  "stopReason": "error",
  "agent_provider": "ollama",
  "agent_model": "qwen3.5:9b-q4_K_M",
  "agent_sessionId": "bc880227-6574-474f-9501-36db7e3fc73d",
  "spr_sessionId": "diag-local-rescue-local-1773106936",
  "spr_sessionKey": "agent:local-rescue:main",
  "usage_total": 0
}
```

Notes:
- I used a fresh wrapper `--session-id` to reduce stale-session ambiguity.
- Even with the fresh wrapper invocation, `systemPromptReport.sessionKey` remained `agent:local-rescue:main`.
- `agentMeta.sessionId` still pointed at `bc880227-6574-474f-9501-36db7e3fc73d`, while `systemPromptReport.sessionId` differed.

---

## Wrapper failure log evidence
Log grep found the corresponding timeout and abort records in `/tmp/openclaw/openclaw-2026-03-10.log`:

```text
embedded run timeout: runId=c32f5279-47fe-4302-8c99-d0ef7d207c7a sessionId=diag-local-rescue-local-1773106936 timeoutMs=45000
[agent] run c32f5279-47fe-4302-8c99-d0ef7d207c7a ended with stopReason=error
This operation was aborted
```

Matching logged result metadata also showed:
- `durationMs: 45072`
- `aborted: true`
- `lastCallUsage.total: 0`
- `provider: ollama`
- `model: qwen3.5:9b-q4_K_M`

---

## What this isolates
### Established now
- Raw model host + raw generation path: **working**
- Intended model identity in wrapper metadata: **correct**
- Wrapper run completion semantics: **misleadingly top-level ok, but content-layer abort**
- Any usable assistant content from wrapper: **none**

### Therefore
The break is **not** currently best explained by:
- missing model
- basic Ollama reachability
- raw Ollama generation failure on this exact marker prompt

The break **is** currently best explained by:
- OpenClaw embedded run / wrapper / session / timeout integration path

---

## Concise final answer
For this exact-marker comparison, **raw Ollama is healthy and the wrapper path is the broken layer now**.

If someone asks “which layer appears broken right now?”, the answer is:
> **OpenClaw’s `local-rescue` wrapper/embedded execution path appears broken; raw Ollama `/api/chat` for `qwen3.5:9b-q4_K_M` is working.**
