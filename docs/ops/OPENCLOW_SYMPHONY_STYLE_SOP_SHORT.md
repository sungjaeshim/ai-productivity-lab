# OpenClaw SOP — Symphony-style Execution v1 (Short)

1. 10분 이상 걸릴 일은 채팅 처리 대신 **task**로 분리한다.
2. 코드/설정 변경은 기본적으로 **isolated run 우선**이다.
3. 메인 세션은 실행장이 아니라 **관제탑**이다.
4. 큰 일 시작 전 아래 4줄을 먼저 고정한다:
   - Task
   - Goal
   - Scope
   - Evidence
5. 비단순 작업 완료 보고는 항상 아래 4블록으로 끝낸다:
   - 변경
   - 검증
   - 결과
   - 리스크/후속
6. “됐다”만 보고하지 말고 **증거**를 같이 낸다.
7. 외부 전송, config 변경, restart, cron 활성화, 배포/merge는 **승인 후 실행**한다.
8. 긴 로그는 메인 채팅에 덤프하지 말고 **압축 보고**한다.
9. 채널 전송은 실행과 분리해서 다룬다:
   - 무엇을
   - 어디에
   - 어떤 증거와 함께 보낼지
10. incident는 바로 inline 추측하지 말고:
    - incident task 생성
    - 조사 run 분리
    - evidence + RCA 보고
11. 작은 일은 inline으로 처리하되, 큰 일만 task화한다.
12. 판단 기준은 단순하다: **격리와 증거가 이득이면 task로 보낸다.**
13. 기본 흐름은 이 6단계다:
    - request
    - task envelope
    - isolated execution
    - proof bundle
    - approval
    - apply/close
14. anti-pattern:
    - main chat에서 오래 끌기
    - 증거 없이 완료 처리
    - 실행 로그와 사용자 보고 혼합
    - 승인 없이 외부 영향 작업 실행
15. 한 줄 원칙:
    **도구를 먼저 바꾸지 말고, 운영 단위를 먼저 바꾼다.**
