# Jarvis Learning Transfer OS v1 — Draft

작성일: 2026-03-10
상태: Draft
목적: 오늘 합의한 중요한 대화를 세션 리셋 전에 보존하고, 이후 개발/설계의 기준 문서로 사용한다.

---

## 1. 왜 이 문서를 만들었나

오늘 대화에서 확인된 핵심 문제는 다음과 같다.

### 현재 상태 (Before)
- 좋은 글 읽음
- 브리핑 봄
- 인사이트 생김
- 며칠 뒤 잊음

### 목표 상태 (After)
- 좋은 글 읽음
- 학습카드 생성
- 당일 회상
- 1/3/7/30일 재호출
- 실제 적용 여부 점검
- 살아남은 것만 메모리 승격

즉, 자비스를 단순 브리핑/알림 시스템이 아니라 **배움 → 행동 → 기억 → 전이**를 관리하는 운영체제로 바꾸는 것이 목적이다.

---

## 2. 오늘 합의한 핵심 결정

1. **큰 그림은 하나, 구현은 작은 단계로 간다.**
   - 전체 아키텍처는 한 번 문서로 고정
   - 구현은 작은 SPEC/Phase 단위로 진행

2. **기존 시스템을 버리지 않고 재배선한다.**
   - smart router
   - Discord inbox / today
   - Todoist
   - 모닝 브리핑 / 저녁 회고 / 메타인지 넛지 / 메모리 유지보수
   를 최대한 살린다.

3. **1차 구현은 Learning Loop 우선이다.**
   - learning card
   - review queue
   - 저녁 회고에서 카드 생성
   - 모닝 브리핑에서 due review 재노출

4. **Discord inbox 병목은 구조 문제다.**
   - inbox가 capture/backlog/reference/action 후보를 동시에 담당하고 있음
   - 따라서 입력을 분류해야 함: `action / learning / reference / noise`

5. **Todoist는 실행 엔진(SoT)로 유지한다.**
   - 실행 상태의 단일 기준은 Todoist
   - learning 자체는 Todoist에 넣지 않고, learning에서 나온 action만 Todoist와 연결

6. **브리핑은 정보 전달이 아니라 재호출 인터페이스가 되어야 한다.**
   - 모닝 = 정보 + 학습 재호출 + 행동 선택
   - 저녁 = 회고 + 학습 고정

7. **상태 보고는 증거 기반으로 바꾼다.**
   - 준비 / 탐색 / 실행 / 검증 / 완료 구분
   - 산출물 없이 ‘진행 중’ 금지

---

## 3. 현재 시스템 파편 요약 (오늘 탐색 기준)

### 이미 존재하는 것

#### A. 입력/라우팅 축
- `docs/brain-pipeline.md`
- Telegram → Discord brain-inbox → second-brain 구조 존재
- p1/p2는 ops(today) 승격, p3는 inbox 잔류 원칙 존재

#### B. 실행 축
- `docs/brain-todoist-sync.md`
- `docs/brain-todoist-ops.md`
- `growth-center/routes/todoist.js`
- `growth-center/routes/ac2.js`
- Todoist today 조회/완료/루틴 통계/health 등 이미 구현 흔적 존재

#### C. 브리핑/회고/넛지 축
실제 cron 존재:
- 🌅 모닝 브리핑 + 목표 설정
- 🌙 저녁 회고 + Todoist 정리
- 🧠 메타인지 넛지
- 📡 Daily Intelligence 리포트
- 📊 inbox→today 3일 리포트
- 메모리 유지보수 (주간)

#### D. 지식 저장 축
- `memory/`
- `MEMORY.md`
- `growth-center`
- `second-brain`
- quick memo / insights / decisions / patterns 구조 존재

### 이미 드러난 문제
1. inbox가 너무 많은 역할을 동시에 함
2. learning lane과 action lane이 분리되지 않음
3. 브리핑/회고/넛지가 하나의 review queue를 공유하지 않음
4. 좋은 글/인사이트가 저장은 되지만 행동 전이까지 닫히지 않음

---

## 4. 살릴 것 / 버릴 것

### 살릴 것
1. brain-pipeline 기본 철학
2. Todoist를 SoT로 두는 구조
3. 모닝/저녁/넛지/주간 유지보수 cron
4. inbox→today 분리 원칙
5. reaction/status sync 철학

### 버릴 것
1. inbox가 모든 것을 먹는 구조
2. 좋은 글 → 저장에서 끝나는 흐름
3. 브리핑 = 정보 전달이라는 가정
4. 증거 없는 ‘진행 중’ 보고

### 보류할 것
1. Notion 완전 통합
2. full auto memory promotion
3. cron 대규모 추가
4. 모든 채널 E2E 자동화 재설계

---

## 5. 1차 설계 초안

### 이름
**Jarvis Learning Transfer OS v1**

부제:
Discord inbox → Today → Todoist → Review Queue → Memory Promotion

### 핵심 구조

#### Layer 1. Intake
- 입력: Telegram / Discord inbox / 브리핑 / 좋은 글 / 대화 / 메모
- 역할: raw capture

#### Layer 2. Triage
입력을 4가지로 분류:
- action
- learning
- reference
- noise

#### Layer 3. Action Lane
- action → today → Todoist → 실행 → 결과 리포트

#### Layer 4. Learning Lane
- learning → learning card → review queue → D0/D1/D3/D7/D30 → 적용 여부 확인

#### Layer 5. Memory / Transfer
- 실제 적용되고 살아남은 것만 memory 승격 후보
- 목표는 저장이 아니라 행동 변화와 전이

---

## 6. 새로 필요한 중심축

### A. Learning Card
최소 필드 초안:
- item_id
- title
- source
- summary
- key_points[3]
- recall_questions[3]
- connect_points[2]
- apply_action[1]
- status (`new/reviewing/applied/transferred/stale`)

### B. Review Queue
최소 필드 초안:
- card_id
- due_at
- review_type (`d0/d1/d3/d7/d30`)
- mode (`recall/explain/connect/apply`)
- status

---

## 7. 기존 cron의 새 역할

### 모닝 브리핑
새 역할:
- 오늘 할 일 3개
- 오늘 review due 카드 1~3개
- 오늘 적용할 배움 1개

### 저녁 회고
새 역할:
- 오늘 배운 것 1개 카드 생성
- same-day recall 수행
- 적용 여부 기록
- review queue 등록

### 메타인지 넛지
새 역할:
- review queue due item 우선 질문
- due 없을 때만 기존 메타 질문

### 주간 메모리 유지보수 / 주간 리뷰
새 역할:
- applied / transferred / stale 판정
- 승격 후보만 메모리 검토

---

## 8. 1차 구현 범위 (고정)

### 포함
1. `learning-cards/` 구조 추가
2. `review-queue` 구조 추가
3. 저녁 회고에 learning card 생성 연결
4. 모닝 브리핑에 due review 연결
5. 상태 보고 규칙 문서화

### 제외
1. Notion 완전 통합
2. 완전 자동 메모리 승격
3. 전체 inbox 상태머신 완성
4. 대규모 cron 재편
5. 전 채널 full automation

---

## 9. 상태 보고 규칙 (오늘 별도 합의)

### 상태 정의
- 대기
- 준비
- 탐색 중
- 실행 중
- 검증 중
- 완료

### 규칙
- 산출물 없으면 ‘진행 중’이라고 하지 않음
- 검증 근거 없으면 ‘완료’라고 하지 않음
- 비사소한 작업은 항상 아래 포맷 우선:
  - 상태
  - 증거
  - 다음 액션

### 이유
중간 유실/공수표/체감 불신을 줄이기 위해서

---

## 10. 현재 세션 런타임 이슈 메모

오늘 대화 중 아래 fallback 문구가 반복 발생했다.
- "No response generated. Please try again."
- "Something went wrong while processing your request. Please try again."

1차 판단:
- 내용 문제보다 **런타임/전달 레이어 fallback** 가능성 큼
- 현재 Telegram group 세션 컨텍스트가 무거워 긴 응답 직출 시 실패 가능성 증가

운영 대응:
- 긴 구조 설계는 파일/문서로 저장
- 채팅에는 요약만 보고
- 이후 필요 시 세션 리셋 후 이 문서를 기준으로 재개

---

## 11. 다음 액션

### 바로 다음 할 일
1. 이 문서를 기준으로 후속 설계 이어가기
2. 실제 구현 설계 문서 추가 작성:
   - 파일 구조
   - 기존 파일 매핑
   - 1차 구현 순서
3. 이후 세션 리셋 시 이 문서를 먼저 읽고 재개

### 추천 순서
- Step 1. 세션 리셋
- Step 2. 이 문서 읽고 컨텍스트 복구
- Step 3. 1차 구현 설계 문서 작성
- Step 4. learning-cards / review-queue부터 구현

---

## 12. 한 줄 요약

**오늘 합의한 핵심은, 자비스를 브리핑/알림 시스템에서 배움-행동-기억-전이 시스템으로 진화시키되, 기존 파편을 버리지 않고 learning card + review queue 중심으로 재배선하자는 것이다.**
