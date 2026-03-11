# 운영 체크리스트 고정판 (2026-03-07)

- 기준 범위: 2026-03-04 ~ 2026-03-07
- 집계: 총 12건 (완료 8 / 진행중 3 / 보류 1)
- 완료율: 66.7%

## 1) 항목별 상태

1. [DONE] chunk-processor 즉시 패치 + 회귀검증
   - 담당: Jarvis
   - 완료기한: 2026-03-04
   - 완료조건: --text/--file 성공 + utc 경고 제거

2. [DONE] PCM+GLM+Codex 운영루프 문서화
   - 담당: Jarvis
   - 완료기한: 2026-03-04
   - 완료조건: `memory/second-brain/pcm-glm-codex-loop.md` 생성

3. [DONE] TM v1 SQL 작성 + Codex 검수 반영
   - 담당: Jarvis
   - 완료기한: 2026-03-04
   - 완료조건: schema/queries/readme 반영 + 샘플 실행 검증

4. [DONE] Todoist 라우팅/동기화 dry-run 점검
   - 담당: Jarvis
   - 완료기한: 2026-03-04
   - 완료조건: route/sync dry-run 정상 파싱

5. [WIP] gateway timeout 원인 추적 및 안정화
   - 담당: Jarvis
   - 다음기한: 2026-03-07
   - 완료조건: 재발 기준시간 무장애 + 원인/완화 문서화

6. [DONE] Telegram 장애 원인분석 + 복구 확인
   - 담당: Jarvis
   - 완료기한: 2026-03-05
   - 완료조건: 로그 기준 원인 식별 + 송신 정상 확인

7. [DONE] 잔존 Codex 프로세스 정리
   - 담당: Jarvis
   - 완료기한: 2026-03-05
   - 완료조건: 잔존 프로세스 0 + 세션 완료 상태 확인

8. [DONE] growth-center 배포 재발방지 하드닝
   - 담당: Jarvis
   - 완료기한: 2026-03-06
   - 완료조건: validate-required-scripts/release preflight 적용

9. [DONE] DVMR 응답 계약 반영
   - 담당: Jarvis
   - 완료기한: 2026-03-06
   - 완료조건: USER.md/working-preferences 반영

10. [DONE] qwen3.5 fallback 제거 정책 적용
    - 담당: Jarvis
    - 완료기한: 2026-03-06
    - 완료조건: config 상 qwen3.5 fallback/alias 제거 확인

11. [WIP] KIS 후속 실행 (P0~P3)
    - 담당: Jarvis
    - 다음기한: 2026-03-07
    - 완료조건: P0 커밋분리 + P1 dry_run + P2 체크리스트 + P3 사전연동점검

12. [HOLD] 취침시간 묶음 30분 모니터링
    - 담당: Jarvis
    - 다음기한: 오늘 밤
    - 완료조건: 30분 모니터링 + 결과 요약 1회 보고

---

## 2) 오늘 우선순위 (실행 순서)

- P1. KIS P0~P3 실행 시작 ([11])
- P2. timeout 재발 추적 마무리 ([5])
- P3. 취침시간 묶음 모니터링 실행 ([12])

## 3) 운영 규칙

- 신규 항목은 반드시 `[DONE|WIP|HOLD]` 중 하나로만 기록
- 상태 변경 시 완료조건을 함께 업데이트
- 다음 보고부터 이 파일을 단일 소스(SOT)로 사용

---

## 4) 의사결정 잠금 (2026-03-07 08:20 KST)

- 범위: 사용자 지정 우선순위 `2 → 3 → 4` (※ 1번은 타 채널 진행)

### D2. 중복코드 후속 방식
- 결정: **2A 채택**
- 실행: DDD 방식 + 재발방지 게이트(pre-commit/CI) 먼저 적용
- 상태: **DONE (2026-03-07 08:24 KST)**
- 완료증거:
  - 중복 baseline 리포트 생성: `projects/kis-auto-trading/reports/dup/jscpd-report.json` (0.29%)
  - 회귀 테스트 baseline 고정: `pytest -q` → `139 passed, 2 skipped`
  - 게이트 초과 차단 검증: `./scripts/check_duplication.sh 0.10` → `EXIT:2`
- 적용 산출물:
  - `projects/kis-auto-trading/scripts/check_duplication.sh`
  - `projects/kis-auto-trading/docs/DUPLICATION_GATE.md`
  - `projects/kis-auto-trading/.github/workflows/duplication-gate.yml`

### D3. 모아이×코덱스 실체 추적
- 결정: **3A 채택**
- 실행: 레포/브랜치/커밋/산출물 증거 매핑 + 완료율(%) 리포트 생성
- 상태: **DONE (2026-03-07 08:25 KST)**
- 완료증거:
  - 리포트: `reports/moai-codex-trace-2026-03-07.md`
  - 증거 매핑 표 포함 (레포/브랜치/커밋/산출물)
  - 완료율 산출: **80%**
  - 미완 항목 다음 액션 3줄 포함

### D4. timeout 대응 운영정책
- 결정: **4A 채택** (조건부 자동 pin)
- 발동조건: `2회/2시간 timeout`
- 조치: `primary=GLM47` 임시 pin `6시간`
- 복귀조건: `4시간 무장애` 확인 시 원복
- 상태: **DONE (2026-03-07 08:27 KST)**
- 완료증거:
  - 문서화: `docs/ops/TIMEOUT_PIN_POLICY.md`
  - 드라이런: `scripts/simulate-timeout-pin-policy.sh` → `DRY_RUN_OK`
  - 드라이런 결과: `PIN_GLM47 / ROLLBACK_PRIMARY / NOOP` 3시나리오 확인

---

## 5) 추가 의사결정 잠금 (2026-03-07 08:33 KST)

- 입력: `1A 2A 3B 4A`

### D5-1. 모아이×코덱스 종결 방식
- 결정: **1A 채택**
- 상태: **DONE**
- 실행: final sign-off 1장 생성 후 100% 종결
- 근거 문서: `reports/moai-codex-final-signoff-2026-03-07.md`

### D5-2. timeout 정책 운영 모드
- 결정: **2A 채택**
- 상태: **ACTIVE**
- 실행: 정책을 자동 발동 기준으로 운영 (`2회/2h` → `6h pin`, `4h quiet` rollback)
- 기준 문서: `docs/ops/TIMEOUT_PIN_POLICY.md`

### D5-3. 취침 30분 모니터링 시간
- 결정: **3B 채택**
- 상태: **SCHEDULED(HOLD)**
- 실행: 고정시각이 아니라 **취침 직전 트리거형**으로 실행

### D5-4. KIS 완료 기준
- 결정: **4A 채택**
- 상태: **WIP**
- 실행: AUTH 준비 전 `P0~P2` 우선 종결, AUTH 준비 후 `P3` 종결
