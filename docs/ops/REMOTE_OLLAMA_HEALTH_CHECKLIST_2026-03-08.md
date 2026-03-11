# Remote Ollama Health Checklist

Updated: 2026-03-08

## Goal

Use this checklist before blaming OpenClaw for `local-rescue` failures.

Current finding:

- OpenClaw-side `think:false` passthrough was patched
- stale skill snapshot reuse was patched
- `local-rescue` tool exposure was reduced to `toolCount: 0`
- but raw Ollama minimal requests are timing out again on the remote host

Because of that, remote Ollama health must be checked first.

## Target Host

- Ollama base URL: `http://100.116.158.17:11434`
- target model: `qwen3.5:9b-q4_K_M`

## Step 1. Basic API reachability

Run:

```bash
curl -sS --max-time 10 http://100.116.158.17:11434/api/version
curl -sS --max-time 10 http://100.116.158.17:11434/api/tags | jq '{models:[.models[]?.name]}'
curl -sS --max-time 10 http://100.116.158.17:11434/api/ps | jq '.'
```

Pass:

- `/api/version` returns quickly
- `qwen3.5:9b-q4_K_M` is listed in `/api/tags`
- `/api/ps` returns valid JSON

Fail:

- this is an Ollama server or network problem first
- do not continue rescue model evaluation until fixed

## Step 2. Known-good minimal `/api/generate`

Run:

```bash
TIMEFORMAT='real=%3R'
time curl -sS -m 60 \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:9b-q4_K_M","prompt":"Reply with exactly LOCAL_RESCUE_OK.","stream":false,"think":false,"options":{"temperature":0,"num_predict":8}}' \
  http://100.116.158.17:11434/api/generate | jq '{done,response,eval_count,prompt_eval_count,load_duration,total_duration}'
```

Pass:

- returns `LOCAL_RESCUE_OK`
- no timeout
- ideally under `20s`, at worst still clearly below rescue timeout

Fail:

- model/runtime is not healthy enough for rescue promotion
- this is not an OpenClaw-only issue

## Step 3. Known-good minimal `/api/chat`

Run:

```bash
TIMEFORMAT='real=%3R'
time curl -sS -m 60 \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:9b-q4_K_M","messages":[{"role":"user","content":"Reply with exactly LOCAL_RESCUE_OK."}],"stream":false,"think":false,"options":{"temperature":0,"num_predict":8}}' \
  http://100.116.158.17:11434/api/chat | jq '{done,message,eval_count,prompt_eval_count,load_duration,total_duration}'
```

Pass:

- returns `message.content = LOCAL_RESCUE_OK`
- no timeout

Fail:

- Ollama chat path is unstable or too slow
- OpenClaw replay results are not trustworthy until this passes

## Step 4. Runtime load snapshot during failure

If Step 2 or 3 times out, capture this immediately.

Run on the Ollama host:

```bash
ollama ps
journalctl -u ollama -n 200 --no-pager
free -h
uptime
```

If GPU-backed:

```bash
nvidia-smi
```

Look for:

- model stuck loading
- repeated restarts
- OOM or memory pressure
- GPU memory exhaustion
- one request blocking all others

## Step 5. OpenClaw replay body

If raw minimal requests pass but OpenClaw still fails, compare with the dumped OpenClaw body.

Local debug dump path:

```bash
/tmp/openclaw-ollama-dump.json
```

Inspect:

```bash
jq '{model:.body.model,think:.body.think,toolCount,messageCount,options:.body.options}' /tmp/openclaw-ollama-dump.json
jq '.body.messages[0]' /tmp/openclaw-ollama-dump.json
```

Current known state:

- `think: false`
- `toolCount: 0`
- direct lane still has large message history
- system prompt remains around `7.6k` chars

## Decision rule

Promote `local-rescue` only if all are true:

1. raw minimal `/api/generate` passes
2. raw minimal `/api/chat` passes
3. OpenClaw isolated cron lane passes
4. exact marker output is stable
5. fixed short format output is stable

If Step 2 or 3 fails, stop there and treat the remote Ollama host as unhealthy first.
