# Call-Me v1 운영 런북

Call-Me v1은 전화 없이 L1/L2 알림을 자동화하는 시스템입니다.

## 개요

| 항목 | 설명 |
|------|------|
| L1 | 일반 알림 (저심각도) → Telegram |
| L2 | 중요 알림 (high/critical, 재시도 3회+, 승인 30분-) → Telegram + TTS |

## 운영 상태 (2026-03-01 기준)

| 트리거 | 상태 | 경로 |
|--------|------|------|
| system-monitor.sh | ✅ 연결됨 | legacy wrapper `system-monitor.sh` → `callme-v1-dispatch.sh` |
| 샘플 이벤트 | ✅ 작동 | callme-v1-sample-event.sh → dispatch |
| TTS | ⚠️ 제한적 | 에이전트 세션에서만 작동 (CLI 미지원) |

## 트리거 연결 경로

```
┌─────────────────────────────────────────────────────────────┐
│                     Call-Me v1 Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  cron (2시간마다)                                           │
│    │                                                        │
│    ▼                                                        │
│  system-monitor.sh ────┐                                    │
│    │                   │                                    │
│    │ 리소스 임계초과    │                                    │
│    ▼                   │                                    │
│  이벤트 JSON 생성      │                                    │
│    │                   │                                    │
│    ▼                   ▼                                    │
│  callme-v1-router.js ──► 레벨 판정 (L1/L2)                  │
│    │                                                        │
│    ▼                                                        │
│  callme-v1-dispatch.sh                                      │
│    │                                                        │
│    ├─► L1: Telegram 메시지                                  │
│    │                                                        │
│    └─► L2: Telegram 메시지 + TTS (에이전트 세션)            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 설치

### 1. 사전 요구사항

```bash
# 필수 패키지
sudo apt-get install -y jq curl

# OpenClaw CLI 확인
openclaw --version
```

### 2. 환경 설정

`.env` 파일에 다음 항목 필요:

```bash
# 필수
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=62403941
```

### 3. 헬스체크

```bash
/root/.openclaw/workspace/scripts/callme-v1-healthcheck.sh
```

모든 항목 PASS 확인 후 진행.

## 운영 명령

### 수동 알림 발송

```bash
# L1 알림 (일반)
cat > /tmp/alert.json <<'EOF'
{
  "eventType": "manual-alert",
  "project": "ops",
  "severity": "medium",
  "summary": "알림 메시지",
  "details": "상세 내용",
  "retryCount": 0,
  "needApprovalMinutes": 0,
  "occurredAt": "2026-03-01T00:00:00Z"
}
EOF
/root/.openclaw/workspace/scripts/callme-v1-dispatch.sh --event /tmp/alert.json

# L2 알림 (중요) - severity를 high/critical로 설정
```

### dry-run (실제 전송 안 함)

```bash
/root/.openclaw/workspace/scripts/callme-v1-dispatch.sh --event /tmp/alert.json --dry-run
```

### 샘플 이벤트 테스트

```bash
# L1 샘플
/root/.openclaw/workspace/scripts/callme-v1-sample-event.sh l1

# L2 샘플
/root/.openclaw/workspace/scripts/callme-v1-sample-event.sh l2
```

## Cron 연동 (현재 활성)

```bash
# 사용자 crontab 확인
crontab -l | grep -E "(system-monitor|callme)"

# 현재 등록 예시:
# 0 */2 * * * /root/.openclaw/workspace/scripts/system-monitor.sh
```

### Cron 등록 절차

1. 헬스체크 통과 확인
2. 테스트 이벤트 발송 성공 확인
3. 운영자 승인 획득
4. `crontab -e`로 등록

## 롤백

### 서비스 중지

```bash
# cron에서 제거
crontab -e
# system-monitor.sh 라인 주석 처리 또는 삭제
```

## 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| Telegram 전송 실패 | 토큰 만료 | `.env` 토큰 갱신 |
| TTS 작동 안 함 | CLI 미지원 | 에이전트 세션에서 tts 툴 사용 |
| cron 실행 안 됨 | 권한 문제 | 스크립트 실행 권한 확인 |
| JSON 파싱 오류 | jq 미설치 | `sudo apt-get install jq` |
| L2인데 TTS 없음 | 정상 동작 | CLI tts 미지원, 메시지만 전송됨 |

## 파일 구조

```
scripts/
├── callme-v1-router.js      # 이벤트 라우터 (레벨 판정)
├── callme-v1-dispatch.sh    # 디스패치 스크립트 (전송)
├── callme-v1-healthcheck.sh # 헬스체크
├── callme-v1-sample-event.sh # 샘플 이벤트 생성
└── system-monitor.sh        # legacy compatibility wrapper -> callme-v1-dispatch.sh

events/callme/               # 이벤트 JSON 저장소
docs/
├── callme-v1.md             # 시스템 문서
└── callme-v1-runbook.md     # 이 문서
```

## 연락처

- 운영자: 성재님
- 채널: Telegram (ID: 62403941)

---

**마지막 업데이트**: 2026-03-01
**상태**: 운영 중 (canonical dispatch = callme-v1-dispatch.sh, system-monitor는 compat wrapper)
