# 🔄 개선 추적기

시스템 자동 개선 항목 추적.

---

## 진행 중

### captures 파이프라인 복구
- **상태**: 진행 중
- **시작**: 2026-03-02
- **이슈**: 원천 로그 파일(capture-log.jsonl) 부재
- **해결방안**: 쓰기 주체 재연결

### Memory Embeddings Query Timeout
- **상태**: 진행 중
- **시작**: 2026-03-07
- **최종 업데이트**: 2026-03-08
- **이슈**: memory embeddings query가 반복적으로 60s timeout 발생, memory search 실패 스크리트 3 도달
- **로그 확인**: 2026-03-07 로그에서 "FailoverError: LLM request timed out." 반복 발생
- **해결방안**: rag-memory 스킬 또는 Ollama 로컬 임베딩 최적화 검토

---

## 대기 중

### 브라우저 포트 충돌
- **상태**: 대기 중
- **시작**: 2026-03-02
- **이슈**: Port 18800 이미 사용 중 (growth-center.service)
- **해결방안**: 충돌 감지 시 자동 재시작 로직 추가

### Second Brain 데이터 소실
- **상태**: 대기 중
- **시작**: 2026-03-02
- **이슈**: 마크다운 소스 비어있음, 데이터 소스 공백
- **해결방안**: second-brain-data.json 기반 마크다운 복원 검토

### Docker 도입 및 sandbox 재강화
- **상태**: 대기 중
- **시작**: 2026-03-02
- **이슈**: sandbox=all 적용 후 ENOENT 장애, Docker 미설치
- **해결방안**: Docker 설치 후 sandbox=all 재전환

---

## 완료된 개선

### LLM Timeout 대응 (qwen3.5 제거)
- **상태**: 완료
- **시작**: 2026-03-06
- **완료**: 2026-03-06
- **내용**: ollama/qwen3.5:35b-a3b를 모든 fallback 체인에서 제거, 모델 정의 삭제
- **결과**: timeout 패턴 감소, fallback 경로 정상화

### API Key 설정 동기화
- **상태**: 완료
- **시작**: 2026-03-02
- **완료**: 2026-03-02
- **내용**: group-sonnet, ralph 에이전트의 auth-profiles.json 복사 완료
- **결과**: fallback provider 인증 문제 해소

### Ollama 모델 문제 해결
- **상태**: 완료
- **시작**: 2026-03-02
- **완료**: 2026-03-02
- **내용**: qwen2.5:14b → qwen3:14b 전역 교체, 모든 agent models.json 업데이트
- **결과**: 404 모델 에러 해결, fallback 경로 정상화

### memory_search 비용 최적화
- **상태**: 완료
- **시작**: 2026-03-02
- **완료**: 2026-03-02
- **내용**: provider: openai → local + fallback: openai, 검색 파라미터 튜닝
- **결과**: 예상 비용 절감 80-98%, 검색 폭 확대

### 워치독 헬스체크 방식 전환
- **상태**: 완료
- **시작**: 2026-03-01
- **완료**: 2026-03-02
- **내용**: 포트 기반 단일 판정 → `/health`/`/ready` HTTP probe 우선 방식 전환
- **결과**: 오탐 감소, 서비스 준비 상태 확인 정확도 향상

### 보안 critical 대응 (임시)
- **상태**: 완료 (임시)
- **시작**: 2026-03-01
- **완료**: 2026-03-02
- **내용**: sandbox=all → off 전환, tools.deny=["group:web", "browser"] 유지
- **결과**: ENOENT 장애 해소, Docker 도입 후 재강화 필요

---
