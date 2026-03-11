# Call-Me v1 - 전화 없는 알림 시스템

## 개요

Call-Me v1은 전화 없이 L1/L2 레벨 알림을 제공하는 경량 알림 시스템입니다.

| 레벨 | 설명 | 채널 | 특징 |
|------|------|------|------|
| **L1** | 일반 이벤트 | Discord/Telegram | 요약 메시지 |
| **L2** | 중요 이벤트 | Telegram + TTS | 텍스트 + 음성 재알림 |

> **Note**: L3 (전화)는 v1에서 제외됨

## 설치

```bash
# 스크립트 실행 권한 부여
chmod +x scripts/callme-v1-dispatch.sh
```

## 입력 JSON 형식

```json
{
  "eventType": "build-failed",      // 이벤트 유형
  "project": "api-gateway",         // 프로젝트명
  "severity": "high",               // low | medium | high | critical
  "summary": "빌드 실패",           // 요약 (1줄)
  "details": "컴파일 에러 발생...", // 상세 내용
  "retryCount": 2,                  // 재시도 횟수
  "needApprovalMinutes": 45,        // 승인 필요까지 남은 시간(분)
  "occurredAt": "2026-03-01T08:00:00Z"  // ISO timestamp
}
```

## 레벨 판정 규칙

### L2 (중요) 조건
다음 중 **하나라도** 만족하면 L2:
- `retryCount >= 3`
- `severity` in `["high", "critical"]`
- `needApprovalMinutes >= 30`

### L1 (일반)
- L2 조건에 해당하지 않는 모든 이벤트

## 사용법

### 기본 사용

```bash
# 이벤트 JSON 파일 생성
cat > /tmp/event.json <<'EOF'
{
  "eventType": "build-failed",
  "project": "api-gateway",
  "severity": "high",
  "summary": "프로덕션 빌드 실패",
  "details": "TypeScript 컴파일 에러: Cannot find module 'xyz'",
  "retryCount": 2,
  "needApprovalMinutes": 45,
  "occurredAt": "2026-03-01T08:00:00Z"
}
EOF

# L1/L2 자동 판정 후 Telegram 전송
./scripts/callme-v1-dispatch.sh --event /tmp/event.json

# 양쪽 채널 모두 전송
./scripts/callme-v1-dispatch.sh --event /tmp/event.json --channel both

# dry-run (실제 전송 안 함)
./scripts/callme-v1-dispatch.sh --event /tmp/event.json --dry-run
```

### 프로그래밍 방식 사용 (Node.js)

```javascript
const { route, getLevel } = require('./scripts/callme-v1-router.js');

const event = {
  eventType: "payment-failed",
  project: "billing-service",
  severity: "critical",
  summary: "결제 게이트웨이 응답 없음",
  details: "Timeout after 30s",
  retryCount: 5,
  needApprovalMinutes: 60,
  occurredAt: new Date().toISOString()
};

const result = route(event);
console.log(result.level);        // "L2"
console.log(result.message);      // 포맷된 메시지
console.log(result.ttsMessage);   // TTS용 짧은 문구
console.log(result.needsTTS);     // true
```

## 메시지 포맷 예시

### L1 메시지 (Discord/Telegram)

```
🟠 **[api-gateway] build-failed**
> 프로덕션 빌드 실패
📅 2026.03.01 17:00 | 심각도: HIGH
```

### L2 메시지 (Telegram)

```
🚨 **[billing-service] payment-failed** 🚨
> 결제 게이트웨이 응답 없음

📋 상세:
Timeout after 30s

🚨 🔄 재시도 5회 | ⏰ 승인까지 60분
📅 2026.03.01 17:00 | 심각도: **CRITICAL**
```

### TTS 메시지 (음성)

```
긴급 알림입니다. billing-service 프로젝트에서 payment-failed 발생. 결제 게이트웨이 응답 없음
```

## 운영 룰

### L1 (일반)
- **빈도**: 자유로움
- **예시**: 
  - 빌드 성공/실패 (저심각도)
  - 배포 완료
  - 일반 로그 알림
  - 재시도 2회 이하

### L2 (중요)
- **빈도**: 과도한 알림 주의
- **예시**:
  - 재시도 3회 이상
  - 승인 대기 30분 이상
  - 장애 상황 (high/critical)
  - 금전적 영향 이벤트

### 운영 가이드
1. **L2 남용 금지** - 중요한 이벤트만 L2로 판정되도록 severity 설정
2. **retryCount 누적** - 재시도 누적은 자동으로 L2 승격
3. **승인 타이머** - needApprovalMinutes로 긴급도 조절
4. **TTS는 Telegram 전용** - Discord는 텍스트만

## CLI 옵션

```
Usage: callme-v1-dispatch.sh [OPTIONS]

Options:
  --event FILE     이벤트 JSON 파일 (필수)
  --channel CH     telegram | discord | both (기본: telegram)
  --dry-run        실제 전송 없이 명령만 출력
  --help           도움말
```

## 의존성

- **Node.js** (v14+): 라우터 실행용
- **jq**: JSON 파싱용
- **openclaw CLI** (선택): 실제 메시지 전송용
  - 없으면 전송 명령만 출력

## 트러블슈팅

### openclaw CLI 없음
```bash
# fallback 모드로 전송 명령 출력
./scripts/callme-v1-dispatch.sh --event /tmp/event.json --dry-run
```

### TTS 실패
- openclaw tts CLI 없으면 수동 명령 출력
- macOS: `say` 명령
- Linux: `espeak` 명령

## 파일 구조

```
scripts/
├── callme-v1-router.js      # 이벤트 라우터 (레벨 판정 + 포맷)
└── callme-v1-dispatch.sh    # 디스패치 스크립트 (전송)

docs/
└── callme-v1.md             # 이 문서
```

## 버전

- **v1** (2026-03-01): L1/L2 구현, 전화 없음
- **v2** (계획): L3 전화 알림 추가

## 작성자

Jarvis - Sungjae's AI Assistant
