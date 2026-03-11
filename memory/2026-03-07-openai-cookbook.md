# Session: 2026-03-07 07:21:28 UTC

- **Session Key**: agent:main:telegram:direct:62403941
- **Session ID**: 18e3ad98-155b-4cfe-802d-ebc9d5ddf860
- **Source**: telegram

## Conversation Summary

user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26499",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:05 GMT+9"
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

https://developers.openai.com/cookbook/
assistant: [[reply_to_current]] 완료 정의 1줄: 링크의 핵심을 **“내가 바로 활용할 수 있는 관점”**으로 압축 전달.

🎯 최상위 기준: **지금 써먹을 수 있는가**  
- **Visibility:** 이 사이트에서 얻는 것 3가지 명확화  
- **Measurability:** 오늘 당장 따라할 레시피 1개 선택 가능

## 요약
OpenAI Cookbook은 “모델 사용법 설명”이 아니라, **실무용 레시피 모음집**이야.  
에이전트, RAG, 파인튜닝, eval, 리얼타임 오디오 같은 걸 **코드 중심**으로 바로 적용하게 해줌.

## 핵심 3줄
1) 초급~고급까지 단계별 예제가 있고, 단순 튜토리얼보다 “실전 구현” 비중이 큼.  
2) 최근 흐름은 **장시간/자율형 에이전트 운영**(self-evolving, multi-hour problem solving) 쪽으로 확실히 이동 중.  
3) Databricks/Stripe/GitLab/LangChain 같은 외부 툴 연동 예시가 많아, 제품화에 유리함.

## 네가 쓸만한 포인트 (빠른 적용)
- **에이전트 운영:** 장기 작업 분해/재계획 패턴
- **RAG 품질:** 벡터DB + 검색/평가 루프
- **평가체계(Evals):** 감으로 개선하지 않고 지표로 개선

## 선택지 A/B
- **A)** 내가 Cookbook에서 **너한테 맞는 Top 5 레시피**만 골라 실행 우선순위로 정리  
- **B)** “하루 1개” 기준으로 **7일 학습+적용 플랜** 만들어줄게

## 다음 액션 1줄
“A”라고 하면, 네 업무 기준(자동화/에이전트 운영)에 맞춰 **바로 따라할 레시피 5개** 뽑아줄게.

Source: https://developers.openai.com/cookbook/ (summarize CLI 결과)
user: [Queued messages while agent was busy]

---
Queued #1
Conversation info (untrusted metadata):
```json
{
  "message_id": "26500",
  "reply_to_id": "26498",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:06 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "완료 정의 1줄: 네가 말한 “구글 CLI”가 현재 환경에 실제로 있는지 확인하고, 바로 다음 액션까지 정리.\n\n🎯 최상위 기준: 기억이 아니라 실행 결과로 확인\n\n• Visibility: 설치 유무/버전 표시\n• Measurability: 명령 1회로 존재 여부 확정\n\n요약\n\n맞아, 네가 예전에 보여줬을 가능성은 높아.\n다만 메모 검색엔 명확한 기록이 약해서, 내가 직접 실행으로 확인했어.\n\n핵심 3줄\n\n1. gog CLI는 현재 설치되어 있음: /usr/local/bin/gog\n2. 버전: v0.11.0 (91c4c15, 2026-02-15)\n3. gcloud는 현재 없음 (별도 설치 상태)\n\n지금 결론 (네가 쓸만한 포인트)\n\n• 네가 말한 “구글 CLI”를 gog 기준으로 보면, 이 환경에서 바로 사용 가능.\n• 즉, Gmail/Calendar/Drive 등 자동화 흐름 붙일 수 있음.\n\n선택지 A/B\n\n• A) 바로 gog로 가능한 명령 10개(메일/캘린더/드라이브) 실전 치트시트 만들어줄게\n• B) 네 루틴 기준으로 아침 브리핑 자동화(메일+일정) 1개를 내가 바로 설계해줄게\n\n다음 액션 1줄\n\n“A로 가자”라고 하면, 복붙해서 바로 쓰는 gog 명령 세트부터 즉시 줄게."
}
```

todoist 할일로 올려줘
assistant: [[reply_to_current]] 완료 정의 1줄: 요청하신 내용을 **Todoist 할 일로 실제 등록**.

✅ 등록 완료  
- 제목: `[Jarvis] Google CLI(gog) 실전 명령 10개 치트시트 받기`  
- 상태: `TODO`  
- 프로젝트: `queue`  
- Todoist ID: `6g7Hh6GW24M5gm46`

검증  
- 드라이런 선확인 후 실행  
- 로컬 sync registry에 `item_id=tg-26500-gog-cheatsheet` + 위 ID 기록 확인됨

다음 액션 1줄  
원하면 이 할 일에 맞춰 내가 바로 **gog 실전 명령 10개** 본문도 지금 붙여줄게.
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26502",
  "reply_to_id": "26501",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:07 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "완료 정의 1줄: 링크의 핵심을 **“내가 바로 활용할 수 있는 관점”**으로 압축 전달.\n\n🎯 최상위 기준: 지금 써먹을 수 있는가\n\n• Visibility: 이 사이트에서 얻는 것 3가지 명확화\n• Measurability: 오늘 당장 따라할 레시피 1개 선택 가능\n\n요약\n\nOpenAI Cookbook은 “모델 사용법 설명”이 아니라, 실무용 레시피 모음집이야.\n에이전트, RAG, 파인튜닝, eval, 리얼타임 오디오 같은 걸 코드 중심으로 바로 적용하게 해줌.\n\n핵심 3줄\n\n1. 초급~고급까지 단계별 예제가 있고, 단순 튜토리얼보다 “실전 구현” 비중이 큼.\n2. 최근 흐름은 장시간/자율형 에이전트 운영(self-evolving, multi-hour problem solving) 쪽으로 확실히 이동 중.\n3. Databricks/Stripe/GitLab/LangChain 같은 외부 툴 연동 예시가 많아, 제품화에 유리함.\n\n네가 쓸만한 포인트 (빠른 적용)\n\n• 에이전트 운영: 장기 작업 분해/재계획 패턴\n• RAG 품질: 벡터DB + 검색/평가 루프\n• 평가체계(Evals): 감으로 개선하지 않고 지표로 개선\n\n선택지 A/B\n\n• A) 내가 Cookbook에서 너한테 맞는 Top 5 레시피만 골라 실행 우선순위로 정리\n• B) “하루 1개” 기준으로 7일 학습+적용 플랜 만들어줄게\n\n다음 액션 1줄\n\n“A”라고 하면, 네 업무 기준(자동화/에이전트 운영)에 맞춰 바로 따라할 레시피 5개 뽑아줄게.\n\nSource: https://developers.openai.com/cookbook/ (summarize CLI 결과)"
}
```

• 에이전트 운영: 장기 작업 분해/재계획 패턴
• RAG 품질: 벡터DB + 검색/평가 루프
• 평가체계(Evals): 감으로 개선하지 않고 지표로 개선 <- 이거 3개 너무 좋은데? 기존에서 이 문서로 얼마나 어떻게 개선가능한지 숫자로 비교표 만들어줄래 ?
assistant: 완료 정의 1줄: 요청하신 내용을 **Todoist 할 일로 실제 등록**.

✅ 등록 완료
- 제목: `[Jarvis] Google CLI(gog) 실전 명령 10개 치트시트 받기`
- 상태: `TODO`
- 프로젝트: `queue`
- Todoist ID: `6g7Hh6GW24M5gm46`

검증
- 드라이런 선확인 후 실행
- 로컬 sync registry에 `item_id=tg-26500-gog-cheatsheet` + 위 ID 기록 확인됨

다음 액션 1줄
원하면 이 할 일에 맞춰 내가 바로 **gog 실전 명령 10개** 본문도 지금 붙여줄게.
assistant: [[reply_to_current]] 완료 정의 1줄: 네가 고른 3축(에이전트/RAG/Evals)에 대해 **기존 대비 개선 가능폭을 숫자 비교표**로 제시.

🎯 최상위 기준: **“품질↑ + 리드타임↓를 동시에 달성”**  
- **Visibility:** 3개 축별 KPI/Before/After/개선율 표시  
- **Measurability:** 2주 내 실측 가능한 지표만 사용

## 요약
좋은 포인트 잡았어.  
아래는 **실무에서 바로 쓰는 보수적 추정치** 기준 비교표야.  
(확정값 아님, 네 로그로 보정하면 정확도 확 올라감)

## 핵심 3줄
1) 에이전트 운영은 보통 **리드타임 25~45% 단축** 효과가 가장 큼.  
2) RAG 품질 루프는 **정답근거율/환각률 개선**이 핵심(30~60% 개선 가능).  
3) Evals는 “감”을 제거해서 **회귀 결함 40~70% 조기 탐지**가 가능해짐.

---

## 숫자 비교표 (보수적 추정)

```text
[1] 에이전트 운영 (장기 작업 분해/재계획)

KPI                     기존(예시)     개선 후(예시)   개선폭
- 평균 완료시간          10.0h          6.5~7.5h        -25% ~ -35%
- 중간 멈춤/재시작 횟수   4.0회          2.0~2.8회       -30% ~ -50%
- 기한 내 완료율         62%            75~85%          +13%p ~ +23%p


[2] RAG 품질 (벡터DB + 검색/평가 루프)

KPI                     기존(예시)     개선 후(예시)   개선폭
- Top-3 근거 포함 정답률  48%            65~78%          +17%p ~ +30%p
- 환각/무근거 응답률      22%            9~15%           -32% ~ -59%
- 검색 실패율            18%            8~12%           -33% ~ -56%


[3] Evals 체계 (지표 기반 개선)

KPI                     기존(예시)     개선 후(예시)   개선폭
- 릴리스 전 회귀 탐지율    35%            60~80%          +25%p ~ +45%p
- 장애 평균 복구시간(MTTR) 120분          70~95분         -21% ~ -42%
- 품질 이슈 재발률        28%            12~18%          -36% ~ -57%
```

---

## 해석 (네가 바로 써먹는 포인트)
- **1순위 투자:** 에이전트 운영 + Evals 동시 적용 (속도/안정성 둘 다 먹힘)
- **2순위:** RAG는 “검색 품질 + 근거 제시”를 묶어서 측정해야 실제 개선이 보임
- **주의:** 지표 1개만 보면 왜곡됨 → 최소 2개(속도+품질) 같이 봐야 함

## 선택지 A/B
- **A)** 내가 지금 표를 **네 실제 운영 로그 기준 실측판**으로 다시 계산  
- **B)** 14일 파일럿용으로 KPI 대시보드 템플릿(수집항목+주간 리포트 포맷) 바로 제작

## 다음 액션 1줄
A로 가면, 너의 실제 baseline(최근 2주) 넣어서 **“예상치가 아닌 실측 비교표”**로 바로 바꿔줄게.
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26508",
  "reply_to_id": "26504",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:09 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "완료 정의 1줄: 네가 고른 3축(에이전트/RAG/Evals)에 대해 기존 대비 개선 가능폭을 숫자 비교표로 제시.\n\n🎯 최상위 기준: “품질↑ + 리드타임↓를 동시에 달성”\n\n• Visibility: 3개 축별 KPI/Before/After/개선율 표시\n• Measurability: 2주 내 실측 가능한 지표만 사용\n\n요약\n\n좋은 포인트 잡았어.\n아래는 실무에서 바로 쓰는 보수적 추정치 기준 비교표야.\n(확정값 아님, 네 로그로 보정하면 정확도 확 올라감)\n\n핵심 3줄\n\n1. 에이전트 운영은 보통 리드타임 25~45% 단축 효과가 가장 큼.\n2. RAG 품질 루프는 정답근거율/환각률 개선이 핵심(30~60% 개선 가능).\n3. Evals는 “감”을 제거해서 회귀 결함 40~70% 조기 탐지가 가능해짐.\n\n───\n\n숫자 비교표 (보수적 추정)\n\n[1] 에이전트 운영 (장기 작업 분해/재계획)\n\nKPI 기존(예시) 개선 후(예시) 개선폭\n- 평균 완료시간 10.0h 6.5~7.5h -25% ~ -35%\n- 중간 멈춤/재시작 횟수 4.0회 2.0~2.8회 -30% ~ -50%\n- 기한 내 완료율 62% 75~85% +13%p ~ +23%p\n\n\n[2] RAG 품질 (벡터DB + 검색/평가 루프)\n\nKPI 기존(예시) 개선 후(예시) 개선폭\n- Top-3 근거 포함 정답률 48% 65~78% +17%p ~ +30%p\n- 환각/무근거 응답률 22% 9~15% -32% ~ -59%\n- 검색 실패율 18% 8~12% -33% ~ -56%\n\n\n[3] Evals 체계 (지표 기반 개선)\n\nKPI 기존(예시) 개선 후(예시) 개선폭\n- 릴리스 전 회귀 탐지율 35% 60~80% +25%p ~ +45%p\n- 장애 평균 복구시간(MTTR) 120분 70~95분 -21% ~ -42%\n- 품질 이슈 재발률 28% 12~18% -36% ~ -57%\n\n───\n\n해석 (네가 바로 써먹는 포인트)\n\n• 1순위 투자: 에이전트 운영 + Evals 동시 적용 (속도/안정성 둘 다 먹힘)\n• 2순위: RA"
}
```

기존에 우리 시스템에서 뭘 어떻게 업그레이드 하는거야 비교해서 알려줘
assistant: [[reply_to_current]] 완료 정의 1줄: **우리 현재 시스템(As-Is) 대비, 3축 업그레이드(To-Be)를 “어디를 어떻게 바꾸는지 + 숫자 목표”로 비교**해 설명.

🎯 **최상위 기준: “복원은 유지(현재 강점), 검색정확도·운영자동화·품질게이트를 끌어올린다.”**  
- **Visibility:** 바꿀 파일/모듈을 명시  
- **Measurability:** 각 축 KPI를 현재값→목표값으로 제시

## 요약
좋은 질문이고, 핵심은 이거야:  
지금 시스템은 **파이프라인 안정성은 이미 좋음**(복원 점수 PASS)인데,  
네가 고른 3축 기준으로 보면 **RAG 정확도/에이전트 재계획/전역 eval 게이트**가 업그레이드 포인트야.

## 핵심 3줄
1) **현재 강점:** 운영 파이프라인 규칙화 + 복원 readiness 100점.  
2) **현재 병목:** semantic 검색이 사실상 placeholder/fallback 구조라 RAG 품질 지표가 약함.  
3) **업그레이드 방향:** Agent 운영 루프화 + Hybrid RAG 실전화 + Eval 게이트 자동화.

---

## 1) 에이전트 운영 (장기 작업 분해/재계획)

`As-Is`
- 링크/메모 → ingest → thread 상태(TODO/DOING/DONE/BLOCKED)로 운영됨  
- 우선순위 p1/p2 자동 승격, p3 대기 (규칙형 운영)  
- 즉, **흐름은 안정적이나 “자동 재계획” 루프는 약함**

`To-Be`
- 작업을 `Plan → Execute → Check → Replan` 30~60분 루프로 자동 재평가
- BLOCKED 원인 코드화(AUTH/2FA/LEGAL/PHYSICAL/UI_LOCK) 후 자동 분기
- WIP limit(예: 동시 DOING 3개) 적용해 체류시간 줄임

`바꾸는 곳`
- `scripts/brainctl.sh` (오케스트레이션 분기)
- `brain-thread-manage` 계열 상태 전이 로직
- 운영 규칙 문서(`docs/brain-pipeline.md`)

`숫자 목표 (2주 파일럿)`
- 평균 완료시간: **-25~35%**
- BLOCKED 평균 체류: **-30%**
- 기한 내 완료율: **+10~20%p**

Source: `docs/brain-pipeline.md#L1-L37`, `docs/script-inventory.md#L7-L16`

---

## 2) RAG 품질 (벡터DB + 검색/평가 루프)

`As-Is`
- recall router의 semantic이 코드상 “future vector index placeholder”
- 결과 없으면 lexical로 fallback하는 구조
- 현재 상태파일에서 `top3_hit_rate=0.0` (개선 여지 큼)

`To-Be`
- MEMORY/daily/docs 대상 **실제 벡터 인덱스** 구축
- `hybrid retrieval + rerank + citation` 기본화
- 평가셋(쿼리 100+) 고정하고 nightly 자동 평가

`바꾸는 곳`
- `scripts/recall_router.py` (semantic 실제화)
- `scripts/recall_router_eval.py` + `data/recall_eval_samples.json` (평가셋 확장)
- `.state/*metrics.json` 대시보드화

`숫자 목표 (2주 파일럿)`
- top3_hit_rate: **0.0 → 70%+**
- citation 포함 응답률: **30%대 → 90%+**
- fallback 의존률: **-40% 이상**

Source: `scripts/recall_router.py#L212-L249`, `.state/recall_router_eval_metrics.json#L3-L13`, `docs/ops/RECALL_ADOPTION.md#L70-L90`

---

## 3) 평가체계(Evals) (감 → 지표 운영)

`As-Is`
- Recall 쪽 eval은 존재(좋음), 하지만 전 워크플로우 공통 게이트는 약함
- 즉, “특정 모듈 평가는 있음 / 전체 릴리스 품질게이트는 분산”

`To-Be`
- 공통 Eval Gate 3종 도입:
  1) Retrieval quality gate
  2) Agent task completion gate
  3) Incident regression gate
- 릴리스 전 `pass/fail` 자동 판정 + rollback 조건 자동 출력

`바꾸는 곳`
- CI 스크립트(게이트 실행)
- `docs/ops/*`에 기준치 고정
- nightly cron 리포트(Discord/Telegram 브리핑 동시 기록)

`숫자 목표 (4주)`
- 릴리스 전 회귀 탐지율: **+25~45%p**
- 장애 MTTR: **-20~40%**
- 재작업률: **-30%+**

---

## 선택지 A/B
- **A)** 내가 이걸 바로 **실행계획 14일 스프린트**(D1~D14, 담당/산출물/KPI 포함)로 쪼개서 줄게  
- **B)** 먼저 가장 임팩트 큰 **RAG 축만 이번 주 즉시 패치 플랜**으로 시작할게

## 다음 액션 1줄
원하면 지금 바로 A로, “파일 수정 순서 + 검증 커맨드 + 완료 기준”까지 실행형으로 뽑아줄게.
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26514",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:15 GMT+9"
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Google Compute Engine 이게 뭐야 ?
assistant: [[reply_to_current]] 완료 정의 1줄: **Google Compute Engine(GCE)을 한 번에 이해되게 설명**.

🎯 최상위 기준: **“이걸 언제 쓰는지”까지 감 잡기**  
- **Visibility:** 개념 + 핵심 구성요소 + 사용 케이스  
- **Measurability:** 내 서비스에 적합한지 1분 내 판단 가능

## 요약
**Google Compute Engine(GCE)**은  
구글 클라우드에서 제공하는 **가상 서버(VM) 서비스**야.  
쉽게 말해 “내 컴퓨터 대신, 구글 데이터센터의 리눅스/윈도우 서버를 빌려 쓰는 것”.

## 핵심 3줄
1) 원하는 CPU/RAM/디스크/OS로 서버를 만들어 앱·DB·배치 작업을 돌릴 수 있음.  
2) 사용량 기반 과금(켜져 있으면 과금, 끄면 일부만 과금).  
3) AWS EC2의 구글 버전이라고 보면 거의 맞음.

## 구성요소 (아주 실무형)
- **VM 인스턴스:** 실제 서버 1대
- **이미지(Image):** 우분투/데비안 등 OS 템플릿
- **디스크:** 부팅디스크 + 추가 데이터디스크
- **네트워크/VPC + 방화벽:** 외부 접근 제어(SSH, HTTP 등)
- **스냅샷:** 백업/복구 포인트
- **Managed Instance Group(옵션):** 자동 확장/자가복구

## 언제 쓰면 좋나
- 백엔드 API 서버 운영
- 크론/배치/크롤러/ML 추론 서버
- Docker/쿠버네티스 이전 단계의 단일 서버 운영
- “앱 코드 + 시스템 패키지”를 직접 제어해야 할 때

## GCE vs Cloud Run (빠른 구분)
- **GCE:** 서버를 내가 직접 관리(유연성↑, 운영부담↑)
- **Cloud Run:** 컨테이너만 올리면 운영 자동(편의↑, 저수준 제어↓)

## 선택지 A/B
- **A)** 네 용도 기준으로 GCE/Cloud Run/GKE 중 뭐가 맞는지 1장 비교표  
- **B)** GCE로 시작할 때 필요한 최소 체크리스트(보안/백업/모니터링) 바로 제공

## 다음 액션 1줄
원하면 A로, 네 현재 워크로드 기준 **가장 싼·안정적인 선택안** 바로 추천해줄게.
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26516",
  "reply_to_id": "26513",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:16 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "• 장애 MTTR: -20~40%\n• 재작업률: -30%+\n\n───\n\n선택지 A/B\n\n• A) 내가 이걸 바로 실행계획 14일 스프린트(D1~D14, 담당/산출물/KPI 포함)로 쪼개서 줄게\n• B) 먼저 가장 임팩트 큰 RAG 축만 이번 주 즉시 패치 플랜으로 시작할게\n\n다음 액션 1줄\n\n원하면 지금 바로 A로, “파일 수정 순서 + 검증 커맨드 + 완료 기준”까지 실행형으로 뽑아줄게."
}
```

B 부터 하고 전부다 하고싶은데. 어떻게 해?
assistant: [[reply_to_current]] 완료 정의 1줄: **B(RAG)부터 시작해서 2주 내 A(전체 3축)까지 이어지는 실행 경로**를 확정.

🎯 최상위 기준: **“RAG 정확도 먼저 올리고, 그 위에 에이전트 운영+Evals를 얹는다.”**  
- **Visibility:** 단계별 산출물(파일/지표) 명확  
- **Measurability:** 각 단계마다 통과 KPI 지정

## 요약
맞아, 가장 좋은 순서는 **B 먼저**가 맞아.  
이유: 지금은 RAG 쪽이 병목이라(semantic placeholder 구조), 여기 먼저 고치면 나머지 2축 효율이 같이 올라가.

## 핵심 3줄
1) **1단계(이번 주): RAG 축 패치** — 검색 정확도/근거율부터 복구  
2) **2단계(다음 주): 에이전트 운영 루프화** — Plan→Execute→Check→Replan  
3) **3단계: 공통 Evals 게이트** — 릴리스 전 자동 pass/fail로 고정

---

## 실행 로드맵 (B → 전체)

### Phase B-1 (D1~D3) — RAG 즉시 패치
- `recall_router.py`의 semantic placeholder 구간 실전화
- eval 샘플 확장(20 → 100+)
- citation 포함 응답률 측정 추가

**통과 기준**
- `top3_hit_rate`: **0.0 → 50%+ (D3)**  
- `route_p95.hybrid`: **< 300ms 유지**

(현재 baseline: `top3_hit_rate=0.0`, `route_p95.hybrid≈5.14ms`)  
Source: `.state/recall_router_eval_metrics.json#L3-L10`, `scripts/recall_router.py#L212-L249`

---

### Phase B-2 (D4~D7) — RAG 안정화
- fallback 의존률 감소
- retrieval 실패 케이스 회귀 테스트 추가
- 운영 리포트 자동화(일일)

**통과 기준**
- `top3_hit_rate`: **70%+**
- `fallback_rate_estimate`: **30% 이하**
- `error_count`: **0 유지**

Source: `docs/ops/RECALL_ADOPTION.md#L70-L90`

---

### Phase A-1 (D8~D10) — 에이전트 운영 업그레이드
- 상태 전이 루프 강화(TODO/DOING/BLOCKED 처리 자동화)
- BLOCKED 원인 코드화 + 자동 분기
- WIP limit 도입

**통과 기준**
- 평균 완료시간 **-20% 이상**
- BLOCKED 체류시간 **-25% 이상**

Source: `docs/brain-pipeline.md#L7-L37`

---

### Phase A-2 (D11~D14) — 공통 Evals 게이트
- RAG/에이전트/운영 3종 gate를 릴리스 전 자동 실행
- pass/fail + rollback 조건 자동 출력

**통과 기준**
- 릴리스 전 회귀 탐지율 **+25%p**
- 재작업률 **-30%**

---

## 네가 지금 할 일 (최소)
1) **“시작” 한마디만**  
2) 나는 D1 작업부터 바로 실행  
3) 매일 저녁 숫자 리포트(완료율/재작업률/핵심 KPI)로 보고

## 선택지 A/B
- **A)** 오늘 바로 D1~D3 착수 (코드 수정+eval 돌려서 첫 결과 보고)  
- **B)** 먼저 30분 킥오프 문서(작업분할/리스크/롤백)만 받고 내일 시작

## 다음 액션 1줄
**“A 시작”** 주면, 지금 바로 B-1 패치 들어가서 첫 KPI 스냅샷까지 가져올게.
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26520",
  "reply_to_id": "26519",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:17 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "• 상태 전이 루프 강화(TODO/DOING/BLOCKED 처리 자동화)\n• BLOCKED 원인 코드화 + 자동 분기\n• WIP limit 도입\n\n통과 기준\n\n• 평균 완료시간 -20% 이상\n• BLOCKED 체류시간 -25% 이상\n\nSource: docs/brain-pipeline.md#L7-L37\n\n───\n\nPhase A-2 (D11~D14) — 공통 Evals 게이트\n\n• RAG/에이전트/운영 3종 gate를 릴리스 전 자동 실행\n• pass/fail + rollback 조건 자동 출력\n\n통과 기준\n\n• 릴리스 전 회귀 탐지율 +25%p\n• 재작업률 -30%\n\n───\n\n네가 지금 할 일 (최소)\n\n1. “시작” 한마디만\n2. 나는 D1 작업부터 바로 실행\n3. 매일 저녁 숫자 리포트(완료율/재작업률/핵심 KPI)로 보고\n\n선택지 A/B\n\n• A) 오늘 바로 D1~D3 착수 (코드 수정+eval 돌려서 첫 결과 보고)\n• B) 먼저 30분 킥오프 문서(작업분할/리스크/롤백)만 받고 내일 시작\n\n다음 액션 1줄\n\n“A 시작” 주면, 지금 바로 B-1 패치 들어가서 첫 KPI 스냅샷까지 가져올게."
}
```

A 시작
user: Conversation info (untrusted metadata):
```json
{
  "message_id": "26522",
  "reply_to_id": "26521",
  "sender_id": "62403941",
  "sender": "SUNGJAE Shim",
  "timestamp": "Sat 2026-03-07 16:21 GMT+9",
  "has_reply_context": true
}
```

Sender (untrusted metadata):
```json
{
  "label": "SUNGJAE Shim (62403941)",
  "id": "62403941",
  "name": "SUNGJAE Shim"
}
```

Replied message (untrusted, for context):
```json
{
  "sender_label": "뮤지기 자비스",
  "body": "⚠️ Agent failed before reply: All models failed (3): openai-codex/gpt-5.3-codex: LLM request timed out. (unknown) | zai/glm-5: No API key found for provider \"zai\". Auth store: /root/.openclaw/agents/main/agent/auth-profiles.json (agentDir: /root/.openclaw/agents/main/agent). Configure auth for this agent (openclaw agents add <id>) or copy auth-profiles.json from the main agentDir. (auth) | zai/glm-4.7: No API key found for provider \"zai\". Auth store: /root/.openclaw/agents/main/agent/auth-profiles.json (agentDir: /root/.openclaw/agents/main/agent). Configure auth for this agent (openclaw agents add <id>) or copy auth-profiles.json from the main agentDir. (auth).\nLogs: openclaw logs --follow"
}
```

타임아웃 원인인거같아 일단 분석해줘. 원인파악해주고
