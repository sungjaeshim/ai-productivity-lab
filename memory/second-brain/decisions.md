# 📋 주요 결정사항

성재님과 논의하여 내려진 중요한 결정들.

---

## 2026-02-22

### QMD v2 메모리 검색 시스템 확정
- **Provider**: OpenAI text-embedding-3-small (로컬 GGUF 실패 → API 전환)
- **DB**: sqlite-vec (하이브리드 벡터 + FTS)
- **비용**: ~$0.01/월
- **결정 이유**: 4GB RAM 서버에서 로컬 GGUF 불가, HuggingFace QMD 미지원
- **정리**: 구 RAG/ChromaDB/GGUF 전부 제거

### 모델 라우팅 3단 구성
- **텔레그램 DM** → Opus 4.6 (복잡 판단)
- **크론/서브에이전트** → GLM 4.7 (무료)
- **그룹챗** → Sonnet 4.6 (중간, agent binding)
- **결정 이유**: 비용 최적화 + 채널별 성능 차별화

### OpenClaw iOS 앱 빌드 연기
- **상태**: Todoist 등록, 담주 진행
- **이유**: App Store 미배포, Xcode 소스 빌드 필요

## 2026-02-20

### Rate Limit Fallback 체인
- glm-5 → glm-4.7 → DeepSeek-V3.1 → QwQ-32B
- **이유**: 하나의 타임아웃이 연쇄 효과

### VIX Alert 추가
- VIX 20 돌파 시 자동 알림

---

## 2026-01-31

### 수동 소득 첫 번째 상품 결정
- **선택**: 글쓰기 템플릿 팩 (이메일, 제안서, 보고서)
- **기반**: alive-writing 스킬 (성재님 검증된 시스템)
- **가격대**: ₩29,000 ~ ₩49,000
- **판매처**: Gumroad, Notion Marketplace
- **다음 단계**: 템플릿 2-3개 제작 → 랜딩 페이지 초안

### ML 트레이딩 백테스트 결정
- **데이터 소스**: Databento ($49/월, 2년 1분봉 히스토리)
- **검증 방식**: Walk-forward validation (Overfitting 방지)
- **재학습 주기**: 주간 (Concept Drift 대응)
- **상태**: 승인 대기 중

---

## 2026-01-30

### 모델 분리 전략
- **Opus**: 복잡한 판단/통합
- **Sonnet**: 코딩/분석 작업
- **Haiku**: 단순 수집/검색
- **목적**: 비용 절약 + 성능 최적화

### 병렬 처리 한도 설정
- **최대 8개 병렬** (CPU 100% 경험 후)
- **10개 동시 실행 시 부하 발생** → 자동 조절 필요
- **안정성 우선** 원칙

---

## 2026-01-28

### NQ 물타기 전략 채택
- **방식**: 피보나치 황금비율 기반
- **기대 수익**: 연 67%
- **리스크**: 조정 없을 경우 손실 가능

### 다롄 여행 예약 완료
- **일정**: 4/9-12
- **상태**: 예약 완료

---

## 의사결정 패턴 (통합)

### 투자 성향
- 필요성 명확하면 과감히 투자, 불필요한 지출은 싫어함, ROI 중시

### 의사결정 스타일
- 빠른 결정 선호, 완벽보다 실행, 옵션+추천 제시하면 빠르게 선택

### 커뮤니케이션
- 간결함 최우선, 핵심만, 표/리스트 형식 선호

---

## [2026-02-24] 핵심 가치 발견: 자유

### 발견 경로
Governing Value 탐색 (Double Loop Learning 적용):
1. "자본흐름이 무너지면 안 된다"
2. 왜? → "자유롭지 못할 것 같아"
3. 뿌리: **"돈의 노예가 되기 싫다"**

### 핵심 가치
> **자유** — 이게 성재의 가장 깊은 동기

### 역설 (Double Loop 질문)
- 자유를 지키기 위해 → 자본흐름 사수
- 자본흐름을 위해 → 17년 같은 직장
- **지금 이 전략이 자유를 만들고 있나, 아니면 자유에 대한 두려움을 관리하고 있나?**

### 분기 점검 질문
1. "지금 내 삶에서 진짜 자유로운 영역이 어디야?"
2. "자본흐름 전략이 자유를 늘리고 있나, 줄이고 있나?"
3. "돈의 노예가 되지 않으려고 만든 구조가 나를 묶고 있진 않나?"

### 연결된 프레임워크
- Double Loop Learning → `growth-frameworks.md`
- Effectuation (Affordable Loss) → 실험 가능한 최소 단위
- Personal Mastery (Creative Tension) → 이 gap이 에너지원

---

## [2026-02-24] 자아(Self) 발견 — 빙산 최하층

### 성재가 되고 싶은 사람
> "내가 원하는 시간을 맘대로 쓰고,
>  내가 원하는 사람을 만나고,
>  내가 원하는 것을 하는 사람."

### 핵심: 삶의 주도권 (3가지 자유)
- **시간 자유**: 내가 원하는 때에 원하는 것
- **관계 자유**: 내가 원하는 사람과
- **행동 자유**: 내가 원하는 것을

### Jarvis 코칭 레퍼런스
이 비전이 나올 때마다 → 지금 구조가 이 방향으로 가고 있는지 점검:
"지금 이 결정이 주도권을 늘리나, 줄이나?"

## [2026-03-03 15:12:09] #decision 태그 라우터 적용 승인 2026-03-03 15:12:09
- event_id: decision-5f8ae69e208c4bcf
- source_ts: 2026-03-03T06:12:09Z
- field2: one-way sync only
- field3: low-risk rollout
- raw: #decision 태그 라우터 적용 승인 2026-03-03 15:12:09 | one-way sync only | low-risk rollout

## [2026-03-03 15:13:35] #decision 경고제거 검증 2026-03-03 15:13:35
- event_id: decision-f15b28687a6ed780
- source_ts: 2026-03-03T06:13:35Z
- field2: quick-check
- field3: ok
- raw: #decision 경고제거 검증 2026-03-03 15:13:35 | quick-check | ok

## [2026-03-03 15:18:13] #decision 오늘 라우팅 방식 유지 결정
- event_id: decision-fc6e22e7f03d2eb0
- source_ts: 2026-03-03T06:17:05.233000Z
- field2: one-way sync
- field3: 적용
- raw: #decision 오늘 라우팅 방식 유지 결정 | one-way sync | 적용

## [2026-03-03 19:31:30] #decision Conversation info (untrusted metadata): Sender (untrusted metadata): 현재 기준르로 뉴스 리포트 브리핑 받고 싶어
- event_id: decision-e85a24ef6a4ac5a5
- source_ts: 2026-03-03T10:12:47.933000Z
- field2: none
- field3: none
- raw: #decision Conversation info (untrusted metadata): Sender (untrusted metadata): 현재 기준르로 뉴스 리포트 브리핑 받고 싶어

