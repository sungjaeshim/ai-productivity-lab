# Jarvis Learning Transfer OS v1 — 1차 구현 설계서

작성일: 2026-03-10
상태: Draft
기준 문서: `docs/ops/JARVIS_LEARNING_TRANSFER_OS_V1_DRAFT.md`
목적: v1 Draft를 실제 구현 가능한 1차 설계/작업 단위로 고정한다.

---

## 1. Definition of Done

1차 구현 범위 안에서 아래 4가지가 실제로 연결되면 완료로 본다.

1. 저녁 회고 흐름에서 `learning card` 1개 이상이 생성된다.
2. 생성된 카드가 `review queue`에 D0/D1 기준으로 등록된다.
3. 모닝 브리핑이 해당 queue의 due item을 1~3개 재노출한다.
4. 카드 상태가 `new → reviewing → applied/stale` 최소 수준으로 갱신 가능하다.

즉, 이번 1차 구현은 **learning lane의 최소 폐루프(minimum closed loop)** 를 만드는 것이다.

---

## 2. 구현 원칙

### 원칙 1. Learning Lane만 먼저 닫는다
이번 라운드에서는 action lane 전체 개편, inbox 상태머신 완성, memory 자동 승격까지 욕심내지 않는다.

포함 범위:
- learning card 생성
- review queue 등록
- morning/evening 연결
- 최소 상태 전이

제외 범위:
- Notion 완전 연동
- full auto memory promotion
- 전 채널 통합 재설계
- cron 대규모 추가/재편

### 원칙 2. 기존 시스템 위에 얹는다
새 시스템을 독립적으로 다시 만드는 대신, 이미 있는 morning/evening/review/memory 자산에 learning lane을 끼워 넣는다.

### 원칙 3. 문서/파일 기반으로 시작한다
초기에는 DB보다 **파일 기반(JSON/MD)** 으로 시작한다.
이유:
- 현재 OpenClaw 운영 문맥과 잘 맞음
- diff/검토/복구가 쉬움
- 구조 검증이 끝나기 전 과한 영속성 설계를 피할 수 있음

### 원칙 4. 상태 보고는 증거 기반으로 한다
구현 중/완료 보고는 항상 아래를 남긴다.
- 상태
- 생성 파일/변경 파일
- 샘플 산출물
- 검증 결과

---

## 3. 1차 범위 고정

### 포함
1. `learning-cards/` 저장 구조 신설
2. `review-queue/` 저장 구조 신설
3. 저녁 회고에서 learning card 생성
4. learning card 생성 시 D0/D1 review queue 등록
5. 모닝 브리핑에서 due review item 1~3개 노출
6. 카드 상태 최소 관리 (`new`, `reviewing`, `applied`, `stale`)
7. 운영 규칙/검증 규칙 문서화

### 제외
1. inbox 전체 재분류 자동화
2. `action / learning / reference / noise` 완전 자동 triage
3. Todoist 양방향 심화 연동
4. memory 승격 자동 판정 엔진
5. D3/D7/D30 완전 자동화 고도화
6. 크로스채널 동기화 재설계

---

## 4. 제안 파일 구조

```text
/root/.openclaw/workspace/
  learning-cards/
    2026/
      2026-03-10/
        lc-20260310-001.md
        lc-20260310-002.md

  review-queue/
    queue.json
    history/
      2026-03-10-review-log.jsonl

  docs/ops/
    JARVIS_LEARNING_TRANSFER_OS_V1_DRAFT.md
    JARVIS_LEARNING_TRANSFER_OS_V1_IMPLEMENTATION_PLAN.md

  scripts/
    learning/
      create-learning-card.js
      register-review-queue.js
      get-due-reviews.js
      mark-review-result.js
```

### 구조 설명

#### `learning-cards/`
- 카드 원본 저장소
- 날짜 기준 디렉토리 분리
- 사람이 읽기 쉬운 MD 포맷 우선

#### `review-queue/queue.json`
- 현재 활성 review item의 단일 기준 저장소
- 1차는 단일 파일로 충분

#### `review-queue/history/`
- 어떤 review가 언제 수행되었는지 append-only 로그 보관
- 추후 recall 품질 분석 근거로 활용

#### `scripts/learning/`
- 생성/조회/상태갱신 로직 분리
- 기존 cron 또는 briefing/review 흐름에서 재사용 가능하게 함

---

## 5. 데이터 모델

## 5.1 Learning Card 스키마

초기 버전은 MD frontmatter + 본문 구조 또는 JSON 중 하나로 갈 수 있으나,
1차는 사람이 검토하기 쉬운 **MD + frontmatter** 를 권장한다.

### 예시

```md
---
item_id: lc-20260310-001
created_at: 2026-03-10T11:40:00+09:00
source_type: conversation
source_ref: telegram-topic-79
source_title: Jarvis Learning Transfer OS 설계 대화
status: new
tags:
  - learning-transfer
  - review-loop
review:
  first_due_at: 2026-03-10T21:00:00+09:00
  last_reviewed_at:
  next_due_at: 2026-03-10T21:00:00+09:00
  review_count: 0
apply:
  action: "learning card + review queue를 1차 구현 범위로 고정"
  evidence:
transfer_score:
---

# 큰 그림은 고정하고 구현은 작게 나눈다

## Summary
자비스는 브리핑/알림 시스템이 아니라 배움-행동-기억-전이 시스템으로 진화해야 한다.

## Key Points
- learning lane을 먼저 닫는다
- 기존 morning/evening 자산을 재사용한다
- 저장이 아니라 재호출과 적용이 핵심이다

## Recall Questions
1. 왜 inbox를 학습 저장소로 계속 쓰면 안 되는가?
2. 이번 1차 구현에서 닫아야 할 최소 루프는 무엇인가?
3. learning card와 Todoist action은 어떻게 구분되는가?

## Connect Points
- morning briefing은 정보 전달이 아니라 recall interface가 되어야 한다
- 저녁 회고는 기록이 아니라 same-day consolidation 역할을 해야 한다

## Apply Action
내일 morning briefing에 due review 1개를 반드시 노출한다.
```

### 필드 설명
- `item_id`: 카드 고유 ID
- `source_type`: conversation/article/briefing/manual 등
- `source_ref`: 대화, 문서, 링크 등 출처 포인터
- `status`: `new / reviewing / applied / stale`
- `review.*`: 복습 관련 메타
- `apply.action`: 실제 행동 연결 문장
- `transfer_score`: 추후 승격 판단용 여지 필드

---

## 5.2 Review Queue 스키마

`review-queue/queue.json` 예시:

```json
{
  "items": [
    {
      "queue_id": "rq-20260310-001-d0",
      "card_id": "lc-20260310-001",
      "review_type": "d0",
      "mode": "recall",
      "due_at": "2026-03-10T21:00:00+09:00",
      "status": "pending",
      "origin": "evening-review",
      "created_at": "2026-03-10T11:40:00+09:00",
      "completed_at": null
    },
    {
      "queue_id": "rq-20260310-001-d1",
      "card_id": "lc-20260310-001",
      "review_type": "d1",
      "mode": "explain",
      "due_at": "2026-03-11T08:00:00+09:00",
      "status": "pending",
      "origin": "evening-review",
      "created_at": "2026-03-10T11:40:00+09:00",
      "completed_at": null
    }
  ]
}
```

### 필드 설명
- `queue_id`: review item 고유 ID
- `card_id`: 연결된 learning card ID
- `review_type`: `d0 / d1 / d3 / d7 / d30`
- `mode`: `recall / explain / connect / apply`
- `status`: `pending / done / skipped / stale`
- `origin`: 어떤 흐름에서 생성됐는지

---

## 6. 상태 전이 설계

### Learning Card 상태
- `new`: 생성 직후, 아직 실제 review 미시행
- `reviewing`: 최소 1회 이상 review 진행 중
- `applied`: 실제 행동/적용 근거가 남음
- `stale`: review 미이행 또는 전이 실패로 사실상 휴면

### 최소 전이 규칙
1. 카드 생성 시 `new`
2. 첫 review 완료 시 `reviewing`
3. `apply evidence`가 남으면 `applied`
4. 일정 기간 방치되거나 반복 미응답이면 `stale`

1차에서는 복잡한 점수화 대신 **명시적 이벤트 기반 전이** 로 충분하다.

---

## 7. 기존 자산 매핑

## 7.1 모닝 브리핑

### 현재 역할
- 정보 전달
- 오늘 할 일/상태 리마인드

### 새 역할
- 오늘 할 일 3개
- due review 카드 1~3개
- 오늘 적용할 learning 1개 제안

### 필요한 연결
- `get-due-reviews.js` 호출
- due item이 있으면 브리핑 본문 중 `Learning Review` 섹션 삽입

---

## 7.2 저녁 회고

### 현재 역할
- 하루 회고
- Todoist 정리

### 새 역할
- 오늘 배운 것 1개를 learning card로 정리
- same-day recall 수행
- D0/D1 queue 등록

### 필요한 연결
- 회고 산출 텍스트 중 learning-worthy 항목 1개 선택
- `create-learning-card.js`
- `register-review-queue.js`

---

## 7.3 메타인지 넛지

### 현재 역할
- 일반적인 메타 질문

### 새 역할
- due review가 있으면 그것을 우선 질문
- 없으면 기존 메타 질문 유지

### 1차 구현 판단
- 구조상 고려는 하되 이번 라운드의 필수 구현에서는 제외 가능
- 단, 인터페이스는 미리 열어두는 것이 좋음

---

## 7.4 주간 메모리 유지보수

### 현재 역할
- 메모리 정리/승격/유지보수

### 새 역할
- learning card 중 `applied` 누적 항목만 승격 후보로 검토

### 1차 구현 판단
- 자동 승격은 제외
- 단, `applied` 상태와 증거 필드를 남겨 차후 연결 준비

---

## 8. 구현 단위 (Step-by-Step)

## Step 1. 저장 구조 만들기

### 목표
- `learning-cards/`
- `review-queue/queue.json`
- `review-queue/history/`
기본 구조를 만든다.

### 산출물
- 디렉토리/빈 파일
- README 또는 주석 템플릿(선택)

### 검증
- 파일 생성 확인
- 샘플 카드/샘플 queue item 수동 저장 가능

---

## Step 2. Learning Card 생성기

### 목표
입력 텍스트를 받아 learning card MD 파일 1개를 생성하는 스크립트를 만든다.

### 입력
- title
- source
- summary
- key points
- recall questions
- apply action

### 출력
- `learning-cards/YYYY/YYYY-MM-DD/lc-*.md`

### 검증
- 샘플 입력으로 카드 1개 생성
- frontmatter 필수 필드 누락 없음

---

## Step 3. Review Queue 등록기

### 목표
생성된 card_id 기준으로 D0/D1 review item을 `queue.json`에 추가한다.

### 규칙
- D0: 당일 저녁 또는 회고 직후 시점
- D1: 다음날 아침 브리핑 직전/직후 읽히기 좋은 시점

### 검증
- queue item 2개 생성
- card_id 연결 일치
- due_at 정렬 가능

---

## Step 4. 저녁 회고 연결

### 목표
기존 저녁 회고 흐름에서 learning-worthy 항목을 1개 뽑아 카드+queue 등록을 실행한다.

### 1차 방식
- 완전 자동 추출보다 **반자동/규칙 기반 1개 생성** 으로 시작 가능
- 예: 회고 요약 중 핵심 배움 1문장을 우선 카드화

### 검증
- 실제 회고 1회에서 카드가 생성되는가
- queue가 함께 등록되는가

---

## Step 5. 모닝 브리핑 연결

### 목표
모닝 브리핑 생성 시 due review item을 읽어 본문에 삽입한다.

### 출력 예시
- 오늘 review due 2개
- 질문형 1개
- 적용형 1개

### 검증
- due item 없을 때 조용히 skip
- due item 있으면 1~3개만 노출
- 브리핑 길이 과도 증가 방지

---

## Step 6. 최소 상태 갱신

### 목표
review 수행/적용 여부에 따라 카드 상태를 갱신할 수 있게 한다.

### 최소 이벤트
- review completed → `reviewing`
- apply evidence added → `applied`
- 일정 기간 미리뷰 → `stale`

### 검증
- 수동/스크립트 기반 상태 변경 가능
- 상태가 카드 메타와 queue 상태에 모순 없이 반영됨

---

## 9. 인터페이스 초안

## 9.1 create-learning-card

입력 예시:

```bash
node scripts/learning/create-learning-card.js \
  --title "큰 그림은 고정하고 구현은 작게 나눈다" \
  --source-type conversation \
  --source-ref telegram-topic-79 \
  --summary "학습 전이 OS는 큰 그림을 먼저 고정하고 구현은 작은 phase로 나눠야 한다" \
  --key-point "learning lane 우선" \
  --key-point "existing assets reuse" \
  --key-point "review queue 중심" \
  --recall-question "왜 learning lane을 먼저 닫아야 하는가?" \
  --recall-question "왜 inbox를 그대로 지식저장소로 쓰면 안 되는가?" \
  --recall-question "이번 1차 구현의 완료 기준은 무엇인가?" \
  --apply-action "morning briefing에 due review 1개를 노출한다"
```

---

## 9.2 register-review-queue

입력:
- `card_id`
- `anchor_time`

출력:
- D0, D1 queue item 생성

---

## 9.3 get-due-reviews

입력:
- 현재 시각
- 최대 개수

출력:
- due item 리스트
- 브리핑용 압축 텍스트 또는 구조화 데이터

---

## 9.4 mark-review-result

입력:
- `queue_id`
- `result` (`done/skipped`)
- `notes`
- 필요 시 `apply_evidence`

출력:
- queue 상태 갱신
- card 상태 갱신
- history append

---

## 10. 검증 기준

## 기능 검증
1. 카드 생성이 되는가?
2. queue 등록이 되는가?
3. morning에서 due 조회가 되는가?
4. review 후 상태 갱신이 되는가?

## 운영 검증
1. 사람이 카드 내용을 읽고 수정하기 쉬운가?
2. 브리핑 길이가 과도하게 늘어나지 않는가?
3. 기존 cron 흐름을 깨지 않고 끼워 넣을 수 있는가?
4. 장애 시 카드/queue 파일만 보고 상태 복구가 가능한가?

## 성공 기준
- 3일 연속으로 최소 1개 카드가 생성된다.
- 최소 1개 카드가 D0/D1 review를 실제로 거친다.
- morning briefing에서 due review가 실사용 가능한 길이로 노출된다.

---

## 11. 리스크와 방지책

### 리스크 1. 카드 생성 품질이 들쭉날쭉함
- 방지: 1차는 하루 1개 핵심 카드만 생성
- 방지: 템플릿 강제

### 리스크 2. 브리핑이 너무 길어짐
- 방지: due review 1~3개 cap
- 방지: 질문형 우선, 장문 요약 금지

### 리스크 3. review queue가 금방 쌓임
- 방지: 1차는 D0/D1만 기본 운영
- 방지: D3/D7/D30은 후속 단계로 확장

### 리스크 4. action lane과 learning lane 경계가 흐려짐
- 방지: learning은 이해/전이 단위
- 방지: Todoist는 실행 action의 SoT 유지

---

## 12. Phase 분리

### Phase 1 (이번 범위)
- 저장 구조
- card 생성
- queue 등록
- evening 연결
- morning 연결
- 최소 상태 갱신

### Phase 2
- D3/D7/D30 확장
- 메타인지 넛지 우선순위 연동
- applied/stale 판단 개선
- review quality 로그 분석

### Phase 3
- memory 승격 semi-auto
- triage 자동화 강화
- action-learning linkage 분석
- 채널별 intake 정교화

---

## 13. 바로 다음 작업 제안

가장 자연스러운 다음 순서는 아래다.

1. `learning-cards/`, `review-queue/` 구조 생성
2. `create-learning-card.js` / `register-review-queue.js` 인터페이스 초안 작성
3. 샘플 카드 1개와 샘플 queue 2개를 수동 생성
4. 이후 morning/evening 연결 포인트 탐색

즉, 다음 구현 턴의 목표는 **설계 완료**가 아니라 **파일 구조 + 샘플 산출물 + 최소 생성기 인터페이스 확정** 이다.

---

## 14. 한 줄 요약

1차 구현은 **learning card와 review queue를 파일 기반으로 도입하고, 저녁 회고에서 생성 → 모닝 브리핑에서 재노출되는 최소 learning loop를 실제로 닫는 작업**이다.
