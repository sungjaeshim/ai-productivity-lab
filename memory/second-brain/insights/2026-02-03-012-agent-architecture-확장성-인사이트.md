# Agent Architecture 확장성 인사이트

## 출처
- 글: "Agent architectures that scale" (Pau Labarta Bajo)
- 링크: https://tinyurl.com/29ndeh7x

## 핵심 메시지
> "Agentic platforms are no dark magic. They are just a bunch of applications running as containerised services inside a compute platform."

## 3가지 핵심 컴포넌트

### 1. Compute Platform (컴퓨팅 플랫폼)
- **소규모**: AWS Lambda, GCP Cloud Functions (Serverless)
- **성장 후**: Kubernetes로 이동 (비용 곡선 평탄화)
- **이유**: 토큰 볼륨 증가 시 Serverless 비용 폭발

### 2. Agent Workflows (에이전트 워크플로우)
- **Python**: Langchain, Langgraph, Pydantic AI, Llamaindex
- **Rust**: [Rig](https://github.com/0xPlaygrounds/rig) 추천
  - 컴파일된 작은 바이너리
  - 동일 인프라에서 10-50배 더 많은 에이전트 실행
  - 더 안전하고, 빠르고, 저렴

### 3. LLM Servers & Tool Servers
- **LLM Servers**: 텍스트 완성 제공 (추론/응답)
- **Tool Servers**: 에이전트와 외부 서비스 간 게이트웨이

## 표준화 추세
- **Agent-Tool**: Model Context Protocol (Anthropic)
- **Agent-to-Agent**: Agent2Agent protocol (Google)
- → **Micro-Agent Architectures** 시대 도래

## 핵심 인사이트

### 현황
- 많은 회사가 PoC 수준에 머물러 있음
- Python 스크립트 + 덕트테이프 → 프로덕션 진입 실패
- 실패 이유: 너무 느림, 너무 비쌈, 신뢰 부족

### 해결책
1. **Kubernetes 도입**: 장기 비용 절감
2. **Rust 전환**: 인프라 효율 10-50배
3. **좋은 소프트웨어 엔지니어링**: DevOps 베스트 프랙티스

## 자비스에게 적용

### 현재 상황
- Python 기반 (Clawdbot)
- 단일 서버 (2GB RAM)
- Serverless 아님

### 개선 기회
1. **Rust 일부 전환**: 핫 경로를 Rust로 재작성
   - 예: MACD 계산, 백테스팅 엔진
2. **마이크로 에이전트**: 기능별 분리
   - 트레이딅 에이전트
   - 리서치 에이전트
   - 글쓰기 에이전트
3. **표준 프로토콜**: Agent-Tool 통신 표준화

## 질문
성재님의 서비스 환경에서 Kubernetes 도입은 과작설계일까, 아니면 미래 투자일까?

---

*태그: #AI #에이전트 #아키텍처 #확장성 #Rust #Kubernetes*
