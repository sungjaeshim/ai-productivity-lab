# Local LLM Rescue Mode

Updated: 2026-03-08

## Role

`local-rescue` exists only for degraded rescue mode.

Use it only when:
- the normal cloud path is failing or timing out
- a short fallback answer is better than total failure
- the task does not require web access, browsing, or long tool chains

Do not use it for:
- normal Telegram or Discord conversations
- long analytical replies
- coding or multi-tool workflows
- memory-heavy prompts

## Model Verdict

Current lane target: `ollama/qwen3.5:9b-q4_K_M`

Reason:
- `qwen3.5:9b-q4_K_M` is the best current live candidate on the Ollama host
- it can produce a completed direct result, unlike the missing old `qwen3:14b`
- it still failed promotion because output currently lands in `thinking`, not the normal final answer field
- OpenClaw-side rescue eval is also blocked by gateway instability today

Implication:
- keep the rescue lane defined with a live experimental target
- do not promote it into the main fallback chain yet
- treat `local-rescue` as manual experiment only until the promotion gates pass

## Operating Rules

- Keep prompts short and explicit.
- Target a reply length of 3-6 lines.
- Prefer direct answers over chain-of-thought style reasoning.
- No web, browser, or remote fetch expectations.
- No automatic channel bindings.
- No automatic promotion into the `main` fallback chain.
- Disable all skills for this agent.
- Keep the tool surface at `minimal` only.

Manual smoke test:

```bash
/root/.openclaw/workspace/scripts/local-rescue-canary.sh
```

Manual agent run:

```bash
openclaw agent --agent local-rescue --message "Reply in 3 short lines: service degraded, retry later."
```

## Promotion Gates

Do not connect `local-rescue` to the `main` fallback chain until all gates pass.

Required gates:
- 7 consecutive days of canary runs
- model exists and Ollama endpoint is reachable on every canary run
- no `model not found`, `fetch failed`, or `aborted` errors
- failure rate <= 2%
- p95 response time <= 45s for the rescue prompt
- short output remains coherent in Korean and follows formatting instructions

If any gate fails, keep the model in manual rescue mode only.

## Current Status

Current mode: manual experimental rescue only

Not promoted because:
- the Ollama endpoint is not consistently reachable from this host
- today's current local candidates did not pass the rescue smoke gate
- the old `qwen3:14b` target was stale and has been removed from the active rescue lane
- the current `qwen3.5:9b-q4_K_M` target still returns content in `thinking`, not `response`
- the 2026-03-08 canary hit `gateway timeout after 75000ms`, then the embedded fallback also timed out
- the same 2026-03-08 canary showed metadata mismatch: `agentMeta.model=qwen3:14b` while `systemPromptReport.model=qwen3.5:9b-q4_K_M`
- the latest forced probe on 2026-03-06 ended with a gateway loopback close and embedded Ollama timeout
- previous local runs showed missing-model and aborted-request failures
- local fallback must not be allowed to degrade the primary chat path again

Prompt status:
- the actual rescue path is lighter now because `local-rescue` disables all skills and keeps tools at `minimal`
- new isolated rescue runs dropped to a small prompt/input footprint, so the remaining blocker is model availability rather than prompt bloat
- `local-rescue-q35-eval` remains a separate eval lane for `qwen3.5:35b-a3b`
