# MEMORY.md

Curated long-term memory view (B-track normalized).
Last updated: 2026-03-09 18:56

## Promotion Rules
- Deduplicate by normalized sentence key.
- Keep only high-confidence facts (score >= 0.72).
- Cap each section to avoid memory bloat.
- Prefer user preference, explicit decisions, and durable operating rules.
- Auto-demote stale Active Context (> 2 days old) into Operating Rules.
- Age-decay Decisions/Rules when not reconfirmed for 14+ days.
- Manual reconfirm supported from daily notes (`reconfirm: <item>` or `재확인: <item>`).

## User Preferences (durable)
- (no stable items yet)

## Confirmed Decisions (recent)
- User selected **B안** for AC2 visibility issue: immediate routing patch instead of manual/keep-as-is flow. _(src: memory/2026-03-06.md, score: 1.00)_
- Confirmed policy: AC2-related messages should land in AC2 path, not only generic `ideas.md`. _(src: memory/2026-03-06.md, score: 1.00)_
- CI incident (`brain-link-ingest-test` failure on run `22541969102`) was treated as path-hardcoding regression; confirmed fixed in later commits. _(src: memory/2026-03-05.md, score: 1.00)_
- User chose **B**: sync `master -> main` immediately. Merge/push executed and validated. _(src: memory/2026-03-05.md, score: 1.00)_
- NQ Telegram output: keep **full-format** but improve readability/visual hierarchy (no summary-only format). _(src: memory/2026-03-05.md, score: 1.00)_
- Adopted NQ v2 message structure with section cards + gauges + mini charts. _(src: memory/2026-03-05.md, score: 1.00)_
- For cross-channel updates (Telegram + Discord), chose isolated-cron mirroring instead of direct cross-context sends from Telegram-bound session. _(src: memory/2026-03-05.md, score: 1.00)_
- User approved PCM work and requested sub-agent parallel kickoff. _(src: memory/2026-03-05.md, score: 1.00)_
- `chunk-processor`는 **B안(즉시 패치)**로 진행하기로 결정. _(src: memory/2026-03-04.md, score: 1.00)_
- 짧은 `--text` 입력도 반드시 통과하도록 최소 1청크 fallback 정책 채택. _(src: memory/2026-03-04.md, score: 1.00)_
- `datetime.utcnow()` 경고는 운영 로그 품질 저하 요인이므로 timezone-aware로 정리. _(src: memory/2026-03-04.md, score: 1.00)_
- OpenClaw health 이슈는 즉시 원인 분석 + 재발방지 설정 적용 방향으로 진행. _(src: memory/2026-03-04.md, score: 1.00)_

## Operating Rules
- Root cause was routing design mismatch (ideas-only ingest), not ingest failure. _(src: memory/2026-03-06.md, score: 1.00)_
- Fastest fix was router-level support (`#ac2` + keyword mirror) rather than post-hoc manual promotion. _(src: memory/2026-03-06.md, score: 1.00)_
- Direct `message send` to Discord from Telegram-bound main session can hit `Cross-context messaging denied`; isolated execution path is reliable workaround. _(src: memory/2026-03-05.md, score: 1.00)_
- CI failure diagnosis should use exact run logs (downloaded logs showed broad assertion failures tied to path assumptions). _(src: memory/2026-03-05.md;reconfirm:memory/2026-03-06.md, score: 1.00)_
- For user-facing trading alerts, structural readability + visual cues improved acceptance while preserving full payload. _(src: memory/2026-03-05.md, score: 1.00)_
- 기능 패치 완료 후에도 운영 안정성(메모리/헬스체크 주기)까지 같이 점검해야 실제 장애 대응이 끝남. _(src: memory/2026-03-04.md, score: 1.00)_
- 짧은 입력 경로(`--text`)는 파일 경로(`--file`)와 별도 회귀 테스트가 필요. _(src: memory/2026-03-04.md, score: 1.00)_
- 경고(Deprecation)도 누적되면 운영 시그널을 흐리므로 조기 제거가 유효. _(src: memory/2026-03-04.md, score: 1.00)_

## Active Context (short horizon)
- No technical blocker in reporting pipeline identified in this session. _(src: memory/2026-03-07.md, score: 0.65)_
- Ongoing market-side noise/volatility (high VIX regime) remains analysis uncertainty, not system failure. _(src: memory/2026-03-07.md, score: 0.65)_
- KIS live verification remains blocked by `AUTH` dependency if appkey/appsecret/account/market subscription are not fully provisioned. _(src: memory/2026-03-07.md, score: 0.65)_
- Discord role hardening is only partially complete: B-plan target still missing effective `ManageRoles` and `ModerateMembers`. _(src: memory/2026-03-08.md, score: 0.65)_
- OpenClaw update items `2) Telegram/ACP topic bindings`, `3) Telegram/topic agent routing`, and `7) Context Engine Plugin Interface` were **not yet applied** because they require structure/config inspection and likely explicit design choices. _(src: memory/2026-03-08.md, score: 0.65)_

## Notes
- Raw auto-capture remains in `memory/MEMORY.md`.
- Daily distills remain in `memory/YYYY-MM-DD.md`.
