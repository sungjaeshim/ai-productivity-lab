# 패턴 라이브러리 (Second Brain)

## 복합 장애 분리 원칙
- **날짜**: 2026-03-03
- **상황**: "All models failed (4)" 장애 발생 시
- **판단**: 단일 원인이 아니라 상위 provider 타임아웃 + 하위 fallback 불일치 조합일 가능성이 큼
- **재사용 조건**: 모델 장애 메시지("All models failed", "FailoverError") 수신 시 상위 provider 상태와 fallback 체인(인증/모델 존재)을 동시에 검증

## 설정 드리프트 방지
- **날짜**: 2026-03-03
- **상황**: config patch와 파일 직접 수정이 섞인 경우
- **판단**: 최종 상태를 `openclaw status + grep`로 이중 검증해야 드리프트 위험을 줄일 수 있음
- **재사용 조건**: config 변경 후 실제 반영 여부 확인 시

## IPv4 우선 가설
- **날짜**: 2026-03-02
- **상황**: fetch failed/ETIMEDOUT/ENETUNREACH, Telegram media download 실패
- **판단**: IPv6 관련 장애 빈도가 높으므로 IPv4 우선 가설을 1순위로 점검
- **재사용 조건**: 네트워크 관련 장애 발생 시

## 대용량 콘텐츠 파이프라인 배치 체크포인트
- **날짜**: 2026-03-05
- **상황**: Weinberg PDF (112 TOC 항목) → Second-brain Article 변환 파이프라인
- **판단**: 한 번에 완료 대신 5개 단위 배치 + 진행 카운터 유지 방식 선택 (user feedback 2회 반영)
- **직관/이유**: 긴 작업에서 중간 보고가 없으면 진행 여부 불투명 → 정기적 체크포인트가 사용자 신뢰와 파이프라인 안정성 모두 향상
- **재사용 조건**: 50개 이상 단위의 반복 작업 실행 시
- **구현**: 5개 완료 시마다 count/last file 체크 + 인덱스 동기화

## DRM 경계 확정 원칙
- **날짜**: 2026-03-05
- **상황**: Internet Archive 대여 콘텐츠 접근 시도 (DRM-protected 파일 403, pdftotext EBX_HANDLER 실패)
- **판단**: 자동화 도구 접근 차단 시, 사용자 측 캡처(text/image)만 지원 경로로 확정
- **직관/이유**: 브라우저 세션/쿠키 위임 없는 서버측 접근은 DRM 회로를 우회할 수 없음 → 불가능 경로 빠른 포기가 효율적
- **재사용 조건**: 대여/구독형 콘텐츠 접근 시도 시

## Empty Payload Detection Pattern
- **날짜**: 2026-03-07
- **상황**: "No response generated" 장애 발생
- **판단**: 빈 응답 장애는 모델 timeout이 아니라 outbound payload-empty failure일 가능성이 큼
- **직관/이유**: gateway 로그에서 `telegram final reply failed: ... empty formatted text and empty plain fallback` 발견 시 전송 경로 문제
- **재사용 조건**: "No response generated" 또는 "empty formatted text" 에러 발생 시 즉시 gateway 로그 확인 → gateway 재시작

## Zone-Based Training Framework
- **날짜**: 2026-03-08
- **상황**: 러닝 코칭 훈련 계획 수립
- **판단**: VO2 Max 테스트 기반으로 훈련 구역 체계화
- **직관/이유**: 구간별 강도를 체계화하여 부상 방지와 성장 동시 달성
- **재사용 조건**: 훈련 계획 설계, 강도 구조화 필요 시
