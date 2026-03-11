# Local Rescue Revalidation

Date: 2026-03-08
Status: not ready

## Goal

Re-check whether the newly tuned local Qwen models can be used as an OpenClaw rescue model.

Evaluation order:

1. Verify current rescue routing and model availability.
2. Re-run rescue-lane smoke checks.
3. Test raw Ollama behavior on currently available local models.
4. Produce concrete requests for the model owner.

## Current facts

- `local-rescue` still points to `ollama/qwen3:14b`, but that model is not present on the Ollama host anymore.
- Current Ollama host model list includes:
  - `qwen3.5:4b`
  - `qwen3.5:9b-q4_K_M`
  - `qwen3.5:35b-a3b`
- OpenClaw status currently reports:
  - `gateway.mode=local`
  - `gateway.url=ws://127.0.0.1:18789`
  - `gateway.reachable=false`
  - `error=timeout`

## Step 1. Rescue path verification

### Result

Fail.

### Evidence

- The configured rescue model ID is stale:
  - config expects `qwen3:14b`
  - Ollama host does not list `qwen3:14b`
- Dedicated eval lane still exists:
  - `local-rescue-q35-eval`
  - pinned to `ollama/qwen3.5:35b-a3b`

### Meaning

The old rescue lane cannot work as configured, even before prompt quality is considered.

## Step 2. OpenClaw rescue-lane re-test

Command used:

```bash
bash /root/.openclaw/workspace/scripts/local-rescue-q35-eval.sh
```

### Result

Fail before model execution.

### Observed output

All three cases failed at job creation time:

- `smoke`: `gateway closed (1006 abnormal closure)`
- `format`: `gateway closed (1006 abnormal closure)`
- `failsoft`: `gateway closed (1006 abnormal closure)`

### Meaning

Today, OpenClaw rescue evaluation is blocked by gateway instability before the local model is even exercised.

## OpenClaw-side root causes found after re-check

### A. `agentMeta.model` stale display is a session-reuse artifact

What we found:

- the embedded runner builds error metadata from the last assistant message in `messagesSnapshot`
- in the current build, that logic prefers `lastAssistant.model` over the current run model on timeout/error paths
- when `local-rescue` reuses the long-lived `agent:local-rescue:main` session, an old `qwen3:14b` assistant can still be the last assistant visible at snapshot time
- the current run's `systemPromptReport.model` can already be `qwen3.5:9b-q4_K_M`, so the two metadata fields diverge

Meaning:

- the stale `agentMeta.model=qwen3:14b` output does not prove the current turn actually selected `qwen3:14b`
- it proves the error metadata path is not isolating the current turn cleanly enough

### B. `openclaw agent --session-id ...` is not enough to isolate a direct agent lane

What we found:

- for `openclaw agent --agent local-rescue`, the command first derives an explicit session key from the agent id
- because that explicit session key already exists as `agent:local-rescue:main`, the direct lane keeps reusing the same store entry
- the lookup-by-session-id fallback is skipped in this path
- a fresh manual run still reported `systemPromptReport.sessionId=<new id>` while `agentMeta.sessionId=<existing local-rescue main session id>`

Meaning:

- `--session-id` is not a reliable isolation mechanism for this direct agent path
- for local-rescue canaries, this contaminates both transcript history and timeout/error metadata

### B-1. Practical workaround that does work today

What we verified:

- `local-rescue` can be forced onto a clean isolated cron lane if:
  - the canary uses `openclaw cron add --session isolated`
  - `local-rescue.subagents.model` is pinned to the same local Ollama model
- after pinning `local-rescue.subagents.model`, the new isolated cron session stored:
  - `model=qwen3.5:9b-q4_K_M`
  - `modelProvider=ollama`
- the earlier false-positive `glm-4.7` success path disappeared in this lane

Current limitation:

- even with the clean isolated lane, the run still timed out at about `45s`
- meaning: routing contamination can be reduced now, but model/runtime latency is still the blocker

### C. gateway timeout is primarily an OpenClaw runtime saturation problem

What we found:

- gateway service can be `running` while RPC probe still reports `reachable=false`, `error=timeout`
- gateway journal shows repeated:
  - `lane wait exceeded: lane=main`
  - `timed out during compaction`
  - `gateway closed (1012): service restart` or `1006 abnormal closure`
- watchdog health checks also recorded repeated HTTP probe timeouts against local gateway health endpoints
- the health watchdog is configured to auto-restart the gateway after repeated probe failures

Meaning:

- the rescue lane is currently colliding with broader gateway responsiveness problems
- at least part of the observed failure is upstream of the local model itself
- until gateway responsiveness is stabilized, OpenClaw-side local rescue tests remain noisy

### D. config drift also interfered with clean reproduction

What we fixed:

- removed invalid per-agent `thinkingDefault` keys that were rejected by the current OpenClaw schema

Meaning:

- some embedded fallback attempts were failing for config-validation reasons, not only model/runtime reasons
- this had to be cleaned up before the newer reproductions could be trusted

## Step 3. Raw Ollama tests on current models

Short direct `generate` checks were run against the current host.

### `qwen3.5:9b-q4_K_M`

Result: responds, but unusable for current OpenClaw rescue path.

Observed shape:

```json
{
  "response": "",
  "thinking": "Thinking Process:\n\n1.  **",
  "done_reason": "length"
}
```

Measured duration:

- about `18.6s` total for an 8-token exact-marker prompt

Meaning:

- content is emitted into `thinking`
- `response` is empty
- this matches the earlier q35 incompatibility pattern

### `qwen3.5:9b-q4_K_M` with explicit `think:false`

Result: raw Ollama is fast enough for rescue budget; load time is not the main blocker.

Observed:

- `/api/generate` with `think:false`, `temperature=0`, `num_predict=8`:
  - returned `LOCAL_RESCUE_OK`
  - `wall_ms=33215`
  - `load_duration=372341590` ns (about `0.37s`)
- `/api/chat` with `think:false`, `temperature=0`, `num_predict=8`:
  - returned `LOCAL_RESCUE_OK`
  - `wall_ms=37908`
  - `load_duration=247038200` ns (about `0.25s`)

Meaning:

- current timeout behavior is not primarily caused by Ollama model loading
- the same model can answer inside about `33-38s` when:
  - hidden reasoning is disabled
  - output is tightly bounded
- this strongly suggests the remaining blocker is on the OpenClaw side:
  - large system prompt overhead
  - sticky direct-session reuse
  - and likely missing propagation of `think:false`

### OpenClaw local-rescue timing after param pin

Result: still timed out at `45s`.

Observed:

- OpenClaw debug showed:
  - `systemPromptChars=37042`
  - `historyTextChars=402`
  - `promptChars=35`
- the alias params `temperature=0` and `maxTokens=8` were applied
- but debug logging did not show `think:false` inside the wrapped stream params
- the run still ended with:
  - `embedded run timeout ... timeoutMs=45000`
  - `lastCallUsage.total=0`

Meaning:

- prompt size and OpenClaw runtime path are the main suspect now
- `think:false` appears to help at raw Ollama level, but is not yet clearly propagating through OpenClaw's extraParams wrapper
- the 45s timeout is therefore much closer to an OpenClaw integration problem than a pure Ollama load-time problem

### `qwen3.5:4b`

Result: timed out.

Observed:

- timed out at `20s`
- timed out again at `35s`

Meaning:

- not reliable enough for rescue use in its current served form

### `qwen3.5:35b-a3b`

Result: timed out.

Observed:

- timed out at `25s`
- timed out again at `40s`

Meaning:

- too slow or too unstable for current rescue requirements

## Overall verdict

No currently available local model is ready to be promoted into the main rescue chain.

### Why not

1. OpenClaw rescue lane is currently blocked by gateway instability.
2. The direct `local-rescue` lane still reuses a sticky main session key, so timeout/error metadata is not cleanly isolated.
3. The old rescue config originally targeted a missing model ID, and that stale state polluted older direct-session history.
4. The best-looking live candidate (`qwen3.5:9b-q4_K_M`) can respond in time when raw Ollama uses `think:false`, but OpenClaw still times out before returning tokens.
5. OpenClaw currently appears to propagate `temperature/maxTokens` but not clearly `think:false` for this model path.
6. The other live candidates (`4b`, `35b`) do not return a short exact output within a practical rescue timeout.

## Practical recommendation

### Do now

- Keep local rescue disabled in the main fallback chain.
- Do not point production fallback at `qwen3.5:4b`, `qwen3.5:9b-q4_K_M`, or `qwen3.5:35b-a3b` yet.
- Fix gateway reachability first, otherwise OpenClaw-side rescue evaluation is noisy and misleading.
- For future local-rescue smoke tests, prefer the isolated cron lane over direct `openclaw agent --agent local-rescue`.

### Best next local-model target

If the model owner can modify one candidate first, the best current target is:

- `qwen3.5:9b-q4_K_M` or a dedicated `nothink` derivative of it

Reason:

- it at least returned a completed result
- the current failure looks more like response-format incompatibility than total incapability

## Requests for the model owner

Ask for these changes in priority order.

### Priority A. Must-have

1. Provide a rescue-specific model tag that does not emit hidden reasoning into `thinking`.
2. Ensure the final answer is returned in the normal `response` or `message.content` field.
3. Optimize for exact short obedience:
   - exact marker output
   - fixed two-line format
   - short fail-soft replies
4. Keep first-token latency low enough for rescue:
   - target under `10s` for trivial prompts
   - under `20s` worst-case on a cold-ish run

### Priority B. Strongly recommended

1. Ship a dedicated `nothink` or `rescue` tag, not a general-purpose thinking tag.
2. Tune for deterministic short responses at `temperature=0`.
3. Validate these prompts before handoff:
   - `Reply with exactly LOCAL_RESCUE_OK.`
   - `다음 형식으로만 답하라.\n1) 상태: 정상\n2) 안내: 잠시 후 다시 시도`
   - `모르면 모른다고만 짧게 답하라: 오늘 미국 CPI 수치 알려줘.`
4. Test both Ollama endpoints:
   - `/api/generate`
   - `/api/chat`

### Priority C. Nice-to-have

1. Keep output token budget reasonable for rescue:
   - short prompts should not need large outputs
   - but avoid pathological truncation at extremely low limits
2. Provide one small, one medium rescue tag:
   - fast tag for heartbeat or marker checks
   - slightly stronger tag for short fail-soft summaries

## Boundary between our side and the model-owner side

### Our side

- fix OpenClaw gateway reachability
- update stale rescue model IDs
- re-run rescue-lane eval once the gateway is healthy

### Model-owner side

- remove or disable thinking-field-only behavior for rescue tag
- reduce latency
- improve exact short-format obedience
- provide a stable Ollama tag specifically for rescue use

## 2026-03-08 patch follow-up

Two OpenClaw-side issues were patched in the installed dist runtime.

### Patch A. `think:false` passthrough

- `createStreamFnWithExtraParams(...)` now forwards boolean `think`
- patched bundles:
  - `compact-B247y5Qt.js`
  - `reply-C5LKjXcC.js`
  - `pi-embedded-C6ITuRXf.js`
  - `pi-embedded-DoQsYfIY.js`

### Patch B. stale skill snapshot refresh

- direct embedded runs now refresh `skillsSnapshot` when `skillFilter` changed
- patched bundles:
  - `compact-B247y5Qt.js`
  - `reply-C5LKjXcC.js`

### What changed after the patch

Direct `local-rescue` debug run now shows:

- wrapper params include `{"temperature":0,"maxTokens":8,"think":false}`
- `skills.promptChars` dropped from about `29684` to `0`
- `systemPromptChars` dropped from about `37042` to `6780`
- `agentMeta.model` now reports `qwen3.5:9b-q4_K_M` instead of stale `qwen3:14b`

This confirms both suspected issues were real and are now corrected enough for evaluation.

### What did NOT change

- direct `openclaw --local` still timed out with:
  - `45s` timeout
  - `90s` timeout
- both runs ended with `lastCallUsage.total = 0`
- isolated cron lane also still timed out at about `45s`, even with:
  - `provider=ollama`
  - `model=qwen3.5:9b-q4_K_M`
  - `skillFilter=[]`
  - `skills.promptChars=0`

### Updated conclusion

The remaining blocker is no longer:

- Ollama model load time
- stale `qwen3:14b` metadata
- bloated bundled skills prompt
- missing `think:false` passthrough

The remaining blocker is now much more likely inside OpenClaw's Ollama integration/runtime path after prompt construction.

## 2026-03-08 late follow-up: request-shape and Ollama runtime

Additional tracing was done after the patches.

### What we captured

- the Ollama request body now receives:
  - `temperature: 0`
  - `num_predict: 8`
  - `think: false`
- `local-rescue.tools.deny = ["session_status"]` removed the last tool entry:
  - `toolCount: 0`
  - `tools.entries: []`

### What the exact body looked like

- provider endpoint: `/api/chat`
- top-level `think: false`
- `toolCount: 0`
- message history still large on direct lane:
  - around `40` messages
- system prompt still includes OpenClaw runtime instructions:
  - about `7.6k` chars

### Replay results

Replaying the exact dumped body directly to raw Ollama still timed out.

- `/api/chat` replay: `120s` timeout
- reduced `user-only + think:false` body: `120s` timeout
- known-good minimal `/api/chat` body: `120s` timeout
- known-good minimal `/api/generate` body: `60s` timeout

### Updated interpretation

At this point, two things are true at once:

1. OpenClaw-side issues were real and have been reduced:
   - `think:false` propagation
   - stale skills snapshot reuse
   - lingering `session_status` tool exposure
2. the remote Ollama runtime is currently too slow or unhealthy even for the minimal known-good body

Because of that, the remaining failure cannot currently be attributed to OpenClaw alone.

## Promotion bar for the next retry

Promote only if all are true:

1. rescue lane job creation succeeds with no gateway `1006` closure
2. exact marker prompt succeeds consistently
3. two-line format prompt keeps exact shape
4. fail-soft prompt stays short and conservative
5. model output lands in `response` or `message.content`
6. trivial prompts finish within practical rescue timeout
