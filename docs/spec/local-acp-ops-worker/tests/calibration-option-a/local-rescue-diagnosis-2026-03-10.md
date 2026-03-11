# local-rescue abort diagnosis — 2026-03-10

## Summary
`openclaw agent --agent local-rescue --json --timeout ...` is reaching the intended Ollama model name, but the lane aborts before any usable token arrives. The strongest current evidence points to **generation-layer failure/latency on the Ollama side, with OpenClaw embedded-run/session handling as a close secondary contributor**.

## Most likely root causes (ranked)

### 1) Ollama generation availability / model runtime latency problem — **most likely**
**Why it ranks #1**
- Basic connectivity works, but actual generation does not complete in time.
- Raw Ollama generation probes timed out, not just OpenClaw wrapper calls.

**Evidence for**
- `curl http://100.116.158.17:11434/api/version` succeeded.
- `curl http://100.116.158.17:11434/api/tags` showed both:
  - `qwen3.5:9b-q4_K_M`
  - `qwen3.5:35b-a3b`
- But raw `/api/chat` probes timed out:
  - `qwen3.5:9b-q4_K_M` exact-marker request timed out at 60s.
  - `qwen3.5:35b-a3b` exact-marker request also timed out at 70s.
- OpenClaw run metadata repeatedly showed `lastCallUsage.total=0`, consistent with no completed generation.
- Existing local doc `docs/local-rescue-q35-eval.md` already records repeated local-lane timeouts for q35 under OpenClaw.

**Evidence against**
- Model tags are present, so this is not a simple “model missing” case.
- API version/tags are reachable, so the host is not fully down.

**What this means**
- The likely failure is at the **generation step**, not model discovery.
- This could be model load latency, GPU/host saturation, hung generation, or an Ollama-side service health issue.

---

### 2) Embedded runner / runtime integration / session handling problem — **plausible and possibly compounding**
**Why it ranks #2**
- OpenClaw’s embedded path shows repeated timeouts with no tokens, and session behavior looks odd.

**Evidence for**
- Gateway log repeatedly shows `embedded run timeout` for `local-rescue` at 20s, 45s, and 90s.
- Both paths failed the same way:
  - `openclaw agent --agent local-rescue --json ...`
  - `openclaw agent --agent local-rescue --local --json ...`
- Fresh-session experiment did **not** clear the issue:
  - `--session-id diag-local-rescue-local-...` still aborted.
- Session metadata is inconsistent:
  - `systemPromptReport.sessionId` changed on the fresh-session test,
  - but `agentMeta.sessionId` remained `bc880227-6574-474f-9501-36db7e3fc73d`.
- `systemPromptReport.sessionKey` stayed `agent:local-rescue:main`, suggesting the lane is still bound to the same main rescue session identity.
- Existing q35 eval notes already document related embedded-lane instability and transcript reuse concerns.

**Evidence against**
- Because raw Ollama `/api/chat` also timed out, OpenClaw wrapper issues are probably **not the only cause**.

**What this means**
- Even if Ollama is the main blocker, the embedded lane likely has its own fragility: reused session identity, timeout budgeting, or integration overhead.

---

### 3) Model metadata / routing inconsistency — **real, but likely contributing rather than primary**
**Why it ranks #3**
- There are configuration mismatches and past routing mistakes around rescue lanes.

**Evidence for**
- `~/.openclaw/openclaw.json` shows `local-rescue.model.primary = ollama/qwen3.5:9b-q4_K_M`.
- But the provider model catalog under `.models.providers.ollama.models` does **not** include an entry for `qwen3.5:9b-q4_K_M`; it lists q35 and others, not this 9B alias.
- Historical cron jobs show multiple rescue-lane model mismatches / stale model references:
  - `qwen3:14b` not found
  - `hf.co/...Q4_K_M` not found
  - `hf.co/...Q3_K_M` not found
  - `qwen3.5:9b-q4_K_M-nothink` timing out
- `docs/local-rescue-q35-eval.md` explicitly records a prior routing inconsistency where the lane silently rerouted to `glm-4.7` before being fixed.

**Evidence against**
- Current run metadata consistently reports:
  - `provider=ollama`
  - `model=qwen3.5:9b-q4_K_M`
- So the current failure is not best explained by wrong-provider routing alone.

**What this means**
- Metadata drift is a credible source of rescue-lane brittleness and may be worsening diagnosability, but it does not fully explain the no-token aborts by itself.

## Hypotheses explicitly checked

### Ollama / model availability problem
**Status:** supported
- Supported at the generation level.
- Ruled out only in the narrow sense of “model tag missing.”

### Network / connectivity problem
**Status:** mostly ruled out as primary
**For**
- Raw generation calls timed out over HTTP.

**Against**
- Gateway loopback is healthy.
- Ollama `version` and `tags` endpoints respond normally.
- This does not look like total network loss; it looks more like generation never finishes.

### Agent prompt / context overload problem
**Status:** largely ruled out as primary
**Evidence against**
- Exact-marker prompt (`Reply with exactly LOCAL_RESCUE_OK.`) still aborted.
- System prompt size is modest for this lane:
  - about `7.5k` chars total
  - no bootstrap truncation
  - tiny local-rescue workspace files only
- Workspace rules are minimal and no extra skills/tools were injected.

### Embedded runner timeout / runtime integration problem
**Status:** supported
- Strongly supported by repeated `embedded run timeout` logs and weird session metadata behavior.
- Probably a compounding factor with #1, not the sole cause.

### Stale session / transcript problem
**Status:** not ruled out, but weaker
**Evidence for**
- Existing q35 doc says rescue-like eval lanes can accumulate failed transcript turns.
- `sessionKey` remains `agent:local-rescue:main`.

**Evidence against**
- Fresh explicit `--session-id` still failed the same way.
- Exact-marker prompt is too small for transcript bloat to be a satisfying primary explanation.

### Model metadata / routing inconsistency problem
**Status:** supported as contributing factor
- Real config drift exists.
- But current metadata still points to the intended 9B model, so this is unlikely to be the first blocker.

## What is ruled out vs not ruled out

### Ruled out or mostly ruled out
- **Simple missing-model failure**: model tag exists in Ollama.
- **Prompt/context overload as primary cause**: exact-marker run fails too.
- **Basic gateway outage**: gateway probe is healthy.
- **Basic Ollama reachability outage**: `version` and `tags` respond.

### Not ruled out
- **Ollama generation stall / model load latency / host saturation**
- **Embedded-run timeout budgeting / session integration bug**
- **Session-key reuse or stale transcript side-effects**
- **Metadata/catalog drift making the lane brittle**

## Specific to `local-rescue`, or broader local-lane instability?
**Assessment:** broader local-lane instability, with `local-rescue` having extra rescue-lane-specific brittleness.

Why:
- Current raw `/api/chat` probes timed out for both 9B and q35.
- Existing q35 evaluation doc already reports the same class of embedded timeout behavior.
- `local-rescue` specifically also has historical model/routing inconsistency and stale rescue-lane baggage.

So this does **not** look like a clean “only `local-rescue` is broken” case.
It looks more like:
1. broader local Ollama generation instability or slowness, plus
2. rescue-lane integration fragility.

## Minimum next safe action
No config changes, no restart, no promotion.

Safest next diagnostic action:
```bash
python3 - <<'PY'
import json, time, urllib.request
url='http://100.116.158.17:11434/api/chat'
payload={"model":"qwen3.5:9b-q4_K_M","messages":[{"role":"user","content":"Reply with exactly LOCAL_RESCUE_OK."}],"stream":False,"options":{"temperature":0}}
data=json.dumps(payload).encode()
req=urllib.request.Request(url,data=data,headers={'Content-Type':'application/json'})
t0=time.time()
with urllib.request.urlopen(req,timeout=180) as r:
    print(r.read().decode())
print(f"elapsed={time.time()-t0:.1f}s")
PY
```

Reason:
- It cleanly isolates raw generation without changing config.
- If this still hangs/fails, the blocker is upstream of `local-rescue` prompt design.
- If it succeeds, focus shifts back to OpenClaw embedded runner/session handling.

## Commands / evidence used
- `openclaw gateway status`
- `openclaw status`
- `jq ... ~/.openclaw/openclaw.json`
- `curl -sS http://100.116.158.17:11434/api/version`
- `curl -sS http://100.116.158.17:11434/api/tags`
- `openclaw agent --agent local-rescue --json --timeout 45 --message 'Reply with exactly LOCAL_RESCUE_OK.'`
- `openclaw agent --agent local-rescue --json --timeout 45 --session-id ... --message 'Reply with exactly LOCAL_RESCUE_OK.'`
- `openclaw agent --agent local-rescue --local --json --timeout 45 --session-id ... --message 'Reply with exactly LOCAL_RESCUE_OK.'`
- raw `/api/chat` probes for `qwen3.5:9b-q4_K_M` and `qwen3.5:35b-a3b`
- log review in `/tmp/openclaw/openclaw-2026-03-10.log`
- prior local lane findings in `docs/local-rescue-q35-eval.md`
