# 2026-03-02 Ralph Loop (야간 자율 작업)

## 로그 분석 (2026-03-01 기준)

### 주요 에러 패턴
1. **group-sonnet API 키 누락**: `FailoverError: No API key found for provider "zai"/"anthropic"`
   - 파일: `/root/.openclaw/agents/group-sonnet/agent/auth-profiles.json`
   - 해결: auth-profiles.json 복사 필요

2. **Ollama 모델 누락**: `model 'qwen2.5:14b' not found`
   - 원인: 로컬 Ollama에 모델 미설치
   - 해결: `ollama pull qwen2.5:14b`

3. **Browser Port 충돌**: `Port 18800 is already in use`
   - 원인: 이전 세션 브라우저 프로세스 정리 미완료
   - 해결: `pkill -f "browser.*18800"` 또는 재시작

4. **Edit 툴 매칭 실패**: `Could not find the exact text`
   - 원인: whitespace/newline 미스매치
   - 해결: 정확한 텍스트 확인 후 edit 실행

5. **Memory 파일 누락**: `MEMORY.md`, `2026-02-28.md` 존재하지 않음
   - 원인: 파일 경로 변경/초기화
   - 해결: 필요 시 복구 또는 경로 업데이트

## CDE 전문성 회고
- 어제 세션 전문성 순간: Cron 오류 복구 (NQ MACD, 저녁 회고)
- 패턴: "실패 원인 분리 → 모델 경로 → 실행 경로 → 검증" 3단계 접근
- 재사용 조건: cron 반복 실패 시 항상 (1) 모델/인증 → (2) 스크립트 의존성 → (3) env 주입 순서로 진단

## 다음 액션
1. group-sonnet auth-profiles.json 복사
2. qwen2.5:14b 모델 설치
3. steering.md, retry-queue.md, improvement-tracker.md 파일 생성
