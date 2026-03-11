# OpenAI Codex Route And Telegram Timeout Runbook

Use this when `openai-codex/gpt-5.4` behaves inconsistently across channels, or when Telegram says `API rate limit reached` / times out while Discord still works.

## Fast Triage

1. Check the actual model route, not the user-visible error text.

```bash
openclaw gateway call chat.history --json --params '{"sessionKey":"agent:main:telegram:direct:62403941","limit":20}'
```

Look at the latest assistant message fields:

- `api: "openai-codex-responses"` means the route is correct.
- `api: "openai-completions"` means the route is wrong for `openai-codex/gpt-5.4`.

2. If `gpt-5.4` resolves to `openai-completions`, inspect `~/.openclaw/openclaw.json`.

- A custom `models.providers.openai-codex` block can override the built-in forward-compat path.
- If that block points to `https://api.openai.com/v1` with `api: "openai-completions"`, `gpt-5.4` will inherit the wrong template.

3. If Discord works but Telegram direct fails, compare session size before blaming OAuth or quota.

```bash
wc -lc ~/.openclaw/agents/main/sessions/<telegram-session>.jsonl \
       ~/.openclaw/agents/main/sessions/<discord-session>.jsonl
```

- Telegram direct can carry old image/base64 payloads and become much larger than Discord.
- In that case, the visible symptom can be `Request was aborted` or a 120s timeout, even after the route is already fixed.

4. If Telegram direct history shows a fresh `System: [Post-compaction context refresh] ... Execute your Session Startup sequence now` turn and later user input appears under `[Queued messages while agent was busy]`, the timeout can be self-inflicted by post-compaction refresh injection.

- This is different from route/auth/session-bloat failures.
- Symptom pattern: the real user message gets queued behind the injected startup turn, then the model aborts around 120s with `Request was aborted`.

5. If the latest Telegram direct transcript includes `provider: "openclaw"` / `model: "delivery-mirror"` entries from cron or automation right before or during the stuck turn, check for outbound mirror collisions.

- `gpt-5.4` can still be the real selected model even when the user only sees `↪️ Fallback: openclaw/delivery-mirror`.
- Common pattern: an isolated cron session uses the `message send` tool to DM the same Telegram direct target, and the runtime mirrors that outbound text back into the user's direct session transcript.
- This is not a Telegram transport failure. It is session cross-talk between automation and the live direct chat.

## Known Good Signals

- `openclaw models status --agent main --json` shows:
  - `defaultModel: openai-codex/gpt-5.4`
  - `openai-codex:default` OAuth status `ok`
- Session transcript shows:
  - `provider: "openai-codex"`
  - `model: "gpt-5.4"`
  - `api: "openai-codex-responses"`

## Recovery Steps

### A. Fix wrong route

Remove the custom `models.providers.openai-codex` override from `~/.openclaw/openclaw.json` if it forces `openai-completions`.

Then restart:

```bash
openclaw gateway restart
```

### B. Reset bloated Telegram sessions

Reset the Telegram direct session and the shared `main` session:

```bash
openclaw gateway call sessions.reset --json --timeout 60000 --params '{"key":"agent:main:telegram:direct:62403941"}'
openclaw gateway call sessions.reset --json --timeout 60000 --params '{"key":"agent:main:telegram:slash:62403941"}'
openclaw gateway call sessions.reset --json --timeout 60000 --params '{"key":"agent:main:main"}'
```

Notes:

- `sessions.reset` archives the old transcript and assigns a new `sessionId`.
- Use `sessions.delete` only for non-main sessions that should disappear entirely.

### C. Stop post-compaction refresh from hitting messaging sessions

If the timeout follows an injected startup refresh in Telegram direct, patch the runtime so `readPostCompactionContext(...)` is queued only for internal/webchat sessions, not for Telegram/Discord/Slack messaging sessions.

Then reapply the local runtime snapshot and reset the affected Telegram session.

### D. Stop cron/tool outbound mirror from polluting Telegram direct sessions

If an isolated cron/hook/node session sends to a Telegram direct target through the `message send` tool, patch `handleSendAction(...)` so target-session mirroring is skipped for system-source sessions when `outboundRoute.chatType === "direct"`.

Keep the actual outbound Telegram send enabled; only suppress the extra `delivery-mirror` append into the user's direct transcript.

## Clean Recheck

Send a direct test into the exact Telegram direct session:

```bash
openclaw gateway call chat.send --json --params '{"sessionKey":"agent:main:telegram:direct:62403941","message":"Reply with exactly ROUTE_OK.","idempotencyKey":"routecheck-<ts>","timeoutMs":120000}'
openclaw gateway call chat.history --json --params '{"sessionKey":"agent:main:telegram:direct:62403941","limit":20}'
```

Success criteria:

- Latest user message is `Reply with exactly ROUTE_OK.`
- Latest assistant message is `ROUTE_OK`
- Latest assistant message uses `api: "openai-codex-responses"`

## What This Incident Taught

- OAuth being `ok` does not prove the route is correct.
- A user-visible `rate limit` message can be stale context from an older transcript.
- Discord-vs-Telegram divergence can come from session state size, not model auth.
- Telegram direct can also fail because a post-compaction startup refresh was injected into the live messaging session and starved the real user turn.
- Telegram direct can also fail because cron/tool outbound sends mirrored themselves into the same DM transcript and collided with a live user run.
- For `gpt-5.4` incidents, inspect `model-snapshot` first, then session size, then only after that blame quota.
