# TOOLS.md - Local Notes

## Network Quirks
- Telegram/Node.js (undici) may show IPv6 instability:
  - `fetch failed`
  - `ETIMEDOUT`
  - `ENETUNREACH`
  - `Failed to download media`
- First-line mitigation:
  - `channels.telegram.network.autoSelectFamily=false`
  - `channels.telegram.network.dnsResultOrder=ipv4first`
  - Re-test with one image after restart

## Operating Cheat Sheet
- Workspace root: `/root/.openclaw/workspace`
- OpenClaw docs: `/root/.openclaw/workspace/docs`
- Gateway status: `openclaw gateway status`
- Gateway restart: `openclaw gateway restart`
- Session status: use `session_status`
- Logs follow: `openclaw logs --follow`
- Codex route/timeouts: `docs/ops/OPENAI_CODEX_ROUTE_AND_TELEGRAM_TIMEOUT_RUNBOOK.md`
- Fast recheck: `chat.history` for latest `api` field, then `sessions.reset` for bloated Telegram direct sessions

## Messaging Notes
- Discord/WhatsApp: no markdown tables
- Discord multiple links: wrap in `<>`
- Telegram NQ MACD: full-format only, never summary-only

## Task Ops Quick Checklist
- 10분+ / 코드·설정 변경 / 증거 필요 작업이면 inline 대신 task로 분리
- 시작 전 4줄 고정: `Task / Goal / Scope / Evidence`
- 구현·탐색·장시간 진단은 `sessions_spawn` 또는 isolated run 우선
- 완료 보고는 `변경 / 검증 / 결과 / 리스크·후속` 4블록 고정
- 외부 전송 / config 변경 / restart / cron 부작용 / merge·deploy는 승인 후 실행
- cross-channel 전송은 main에서 억지로 보내지 말고 delivery 경로를 따로 설계

## Environment Notes
- Put environment-specific IDs, camera names, SSH aliases, and voice prefs here.
- Keep secrets out of this file unless explicitly requested.
