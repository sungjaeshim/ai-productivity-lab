# Local Rescue Q35 Eval

Updated: 2026-03-08

## Role

Purpose:
- evaluate `ollama/qwen3.5:35b-a3b` in a dedicated rescue-only lane
- remove ambiguity from the older `local-rescue` path
- keep canary disabled until this lane passes manual smoke tests

## Operating Rules

Rules:
- no fallback providers
- no memory search
- minimal tools only
- short outputs only
- exact-format prompts must be obeyed exactly

Manual evaluation:

```bash
/root/.openclaw/workspace/scripts/local-rescue-q35-eval.sh
```

## Pass Bar

Pass bar:
- all cases must use `ollama/qwen3.5:35b-a3b`
- no `aborted`, `fetch failed`, or timeout
- smoke case must return exact marker text
- format case must keep the requested two-line shape
- fail-soft case must stay short and conservative

## Canary Status

Canary status:
- off
- do not promote until manual eval is stable

## Current Findings

- gateway routing mismatch root cause was real: `runCronIsolatedAgentTurn` was inheriting the global `agents.defaults.subagents.model.primary`, so this eval lane was silently re-routed to `zai/glm-4.7`
- workaround is applied: `local-rescue-q35-eval` pins both `model.primary` and `subagents.model.primary` to `ollama/qwen3.5:35b-a3b`
- gateway cron routing is now correct, but q35 still times out inside OpenClaw before producing any tokens
- the `openclaw agent --agent local-rescue-q35-eval` path uses session key `agent:local-rescue-q35-eval:main`, so prompt mode stays `full`, not `minimal`
- that same main session is reused across runs, so failed test turns accumulate in the transcript unless the session is reset
- current rescue verdict remains `not ready`

## Latest Validation

- old false-positive smoke:
  - gateway smoke job `ce545b2f-9b50-4886-aa49-6e4625786a8a`: returned `LOCAL_RESCUE_OK` in about 10.6s, but the run still used `provider=zai`, `model=glm-4.7`
- routing fix validation:
  - gateway smoke job `0ab8debb-e112-413f-a523-5d0f467cc3c4`: session metadata now shows `provider=ollama`, `model=qwen3.5:35b-a3b`
  - gateway smoke job `22ca0f94-5fa6-4b4f-aa22-c20f69d26579`: session metadata also shows `provider=ollama`, `model=qwen3.5:35b-a3b`
  - both gateway jobs still ended with cron timeout at about 20s
- direct runtime validation against Ollama host:
  - direct `node fetch` non-stream to `http://100.116.158.17:11434/api/chat` succeeded with `LOCAL_RESCUE_OK`
  - cold-ish direct request took about `20.2s` total with about `15.0s` in `load_duration`
  - direct streaming request also succeeded and returned `LOCAL_RESCUE_OK`, with about `31.1s` total and about `25.0s` in `load_duration`
- embedded smoke command:

```bash
openclaw agent --agent local-rescue-q35-eval --local --message 'Reply with exactly LOCAL_RESCUE_OK.' --timeout 45 --json
```

- earlier embedded result: `provider=ollama`, `model=qwen3.5:35b-a3b`, `durationMs=50308`, `aborted=true`
- post-warm embedded result:
  - command: `openclaw agent --agent local-rescue-q35-eval --local --session-id q35-postwarm-20260306-1146 --message 'Reply with exactly LOCAL_RESCUE_OK.' --timeout 60 --json`
  - result: `provider=ollama`, `model=qwen3.5:35b-a3b`, `durationMs=63253`, `aborted=true`
  - system prompt report: `systemPrompt.chars=7016`, `projectContextChars=1227`, `nonProjectContextChars=5789`
  - no tokens were returned before timeout (`lastCallUsage.total=0`)
  - session transcript recorded `This operation was aborted`
- debug context on the same agent path:
  - `openclaw --log-level debug agent --agent local-rescue-q35-eval --local ... --timeout 1`
  - pre-prompt context showed `messages=26`, `historyTextChars=319`, `systemPromptChars=7016`
  - this confirms the eval lane is not stateless; it keeps retrying on the same `main` session transcript
- prompt override experiment:
  - attempted internal-hook prompt replacement was not observed on either local CLI or gateway `agent` runs
  - inference: a true tiny-prompt rescue lane is not currently reachable through `openclaw agent` without deeper OpenClaw changes or a different session-key path
- 2026-03-08 rerun with `/root/.openclaw/workspace/scripts/local-rescue-q35-eval.sh`:
  - `smoke`: `FAIL`, `DURATION_MS=20031`, `Error: cron: job execution timed out`
  - `format`: `FAIL`, `DURATION_MS=20031`, `Error: cron: job execution timed out`
  - `failsoft`: `FAIL`, `DURATION_MS=20028`, `Error: cron: job execution timed out`
  - meaning: the dedicated eval lane still does not produce usable output within the current 20s model timeout budget

## Implication

- keep canary off
- do not attach this lane to main fallback
- the remaining problem is no longer routing; it is rescue-lane latency under OpenClaw's embedded prompt/runtime overhead
- q35 looks usable as a raw Ollama model, but not yet usable as an OpenClaw rescue model
- a true `minimal` rescue lane likely requires one of:
  - an OpenClaw core change that lets `openclaw agent` force `promptMode=minimal|none`
  - a stateless rescue session key that is treated like `cron` or `subagent`
  - a dedicated runner path that does not reuse `agent:...:main`

## Current Status

Current mode: manual eval only

Not promoted because:
- all three 2026-03-08 eval cases timed out at about 20s
- the lane still depends on OpenClaw cron execution that does not finish in the current timeout budget
- rescue output is not consistently available through the embedded OpenClaw path
