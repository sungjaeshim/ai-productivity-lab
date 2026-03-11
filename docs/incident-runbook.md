# Incident Runbook - 인시던트 처리 가이드

## 개요

이 문서는 Discord 라우팅 + 자동복구 + 4줄 리포트 파이프라인의 운영 가이드입니다.

---

## 1. 인시던트 라우팅 (`incident-router.sh`)

### 사용법

```bash
./scripts/incident-router.sh [OPTIONS] '<JSON>'
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `--dry-run` | Telegram 발송 없이 리포트만 출력 |
| `--tts` | L3 인시던트에 대해 TTS 음성 생성 |

### JSON 입력 필드

| 필드 | 필수 | 설명 | 예시 |
|------|------|------|------|
| project | ✓ | 프로젝트명 | jarvis, api, web |
| severity | ✓ | 심각도 | L1 (낮음), L2 (중간), L3 (높음) |
| title | ✓ | 인시던트 제목 | API 응답 지연 |
| cause | | 원인 | DB 커넥션 풀 고갈 |
| action | | 조치 내용 | 커넥션 풀 증설 |
| verify | | 검증 방법 | 응답시간 < 200ms |
| prevent | | 재발방지 | 모니터링 추가 |

### 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| INCIDENT_TELEGRAM_TARGET | - | Telegram target/chatId (L2/L3 발송용, 필수) |
| DISCORD_WEBHOOK_ALERTS | - | Discord webhook URL for L2/L3 alerts |
| DISCORD_WEBHOOK_PROJECT | - | Discord webhook URL for L1 (project-specific) |
| TELEGRAM_SUMMARY | true | Telegram 요약 전송 여부 |
| PROJECT_CHANNELS | general | L1용 프로젝트 채널 |
| ALERTS_CHANNEL | alerts | L2/L3용 알림 채널 |

### 라우팅 규칙

```
L1 (낮음)  → 프로젝트 전용 채널 (예: #jarvis) + Discord PROJECT webhook
L2 (중간)  → #alerts + Telegram 요약 + Discord ALERTS webhook
L3 (높음)  → #alerts + Telegram + Discord ALERTS + Slack 온콜 + TTS (선택)
```

### 4줄 리포트 포맷

```
🔍 원인: [원인]
🔧 조치: [조치 내용]
✅ 검증: [검증 방법]
🛡️ 재발방지: [재발방지 대책]
```

### 예시

```bash
# L2 인시던트 - Telegram 발송
INCIDENT_TELEGRAM_TARGET=62403941 \
./scripts/incident-router.sh '{
  "project": "jarvis",
  "severity": "L2",
  "title": "API 응답 지연",
  "cause": "DB 커넥션 풀 고갈",
  "action": "커넥션 풀 크기 증설 (20→50)",
  "verify": "응답시간 < 200ms 확인",
  "prevent": "풀 사용률 모니터링 알림 추가"
}'

# L3 인시던트 - Telegram + TTS
INCIDENT_TELEGRAM_TARGET=62403941 \
./scripts/incident-router.sh --tts '{
  "project": "jarvis",
  "severity": "L3",
  "title": "서버 다운",
  "cause": "메모리 부족",
  "action": "재시작 + 메모리 증설",
  "verify": "헬스체크 정상",
  "prevent": "메모리 모니터링 강화"
}'

# 드라이런 테스트
./scripts/incident-router.sh --dry-run '{"severity":"L2","title":"테스트"}'
```

### Telegram 발송

L2/L3 인시던트는 자동으로 Telegram으로 4줄 요약이 발송됩니다:

```
🚨 [L2] jarvis - API 응답 지연

🔍 원인: DB 커넥션 풀 고갈
🔧 조치: 커넥션 풀 크기 증설
✅ 검증: 응답시간 < 200ms 확인
🛡️ 재발방지: 풀 모니터링 알림 추가
```

- 발송 실패 시 1회 재시도
- `INCIDENT_TELEGRAM_TARGET` 환경변수 필수

### TTS (L3 전용)

`--tts` 플래그 사용 시 L3 인시던트에 대해 음성 알림이 생성됩니다:

```
긴급 인시던트 발생. [제목]. 원인은 [원인]. 조치는 [조치] 완료.
```

---

## 2. 안전 자동복구 (`safe-autorepair.sh`)

### 사용법

```bash
./scripts/safe-autorepair.sh <action> [service] [options]
```

**기본 동작**: 계획 모드 (no-op) — 실제 실행 없이 계획만 출력

### 안전 작업

| 작업 | 설명 | 예시 |
|------|------|------|
| restart | 서비스 재시작 | `restart nginx` |
| reload | 설정 리로드 | `reload nginx` |
| status | 서비스 상태 확인 | `status nginx` |
| health-check | 전체 헬스체크 | `health-check` |

### 서비스 allowlist

다음 서비스만 restart/reload/status 허용:

- `openclaw`
- `growth-center`
- `nginx`
- `cloudflared`

### 위험 작업 (항상 거부)

다음 키워드가 포함된 작업은 거부됩니다:

- DB 변경: `DROP`, `DELETE`, `TRUNCATE`, `ALTER TABLE`
- 파일 삭제: `rm -rf`
- 권한 변경: `chmod 777`
- 전원: `shutdown`, `reboot`, `halt`, `poweroff`

### 옵션

| 옵션 | 설명 |
|------|------|
| `--execute` | 실제 실행 모드 (기본: 계획 모드) |
| `--yes` | 실행 전 확인 프롬프트 생략 |
| `--log FILE` | 로그 파일 지정 (기본: logs/incident-autorepair.log) |

### 예시

```bash
# 계획 모드 (기본) - 실행 없이 계획만 출력
./scripts/safe-autorepair.sh restart nginx

# 실제 실행 (--yes 없으면 확인 프롬프트 표시)
./scripts/safe-autorepair.sh restart nginx --execute

# 확인 없이 바로 실행
./scripts/safe-autorepair.sh restart nginx --execute --yes

# allowlist에 없는 서비스 (거부됨)
./scripts/safe-autorepair.sh restart mysql --execute
# → 🚫 서비스 거부

# 위험 작업 시도 (거부됨)
./scripts/safe-autorepair.sh "DROP" "TABLE"
# → 🚫 실행 거부
```

### 로그 파일

기본 경로: `logs/incident-autorepair.log`

모든 실행/거부/취소 내역이 타임스탬프와 함께 기록됩니다.

---

## 3. 통합 파이프라인

### 인시던트 발생 시 워크플로우

```
1. 인시던트 감지
   ↓
2. incident-router.sh로 라우팅 + 리포트 생성
   ↓
3. safe-autorepair.sh로 안전조치 시도
   ↓
4. 성공 → 리포트 전송
   실패 → 승인 요청 / 에스컬레이션
```

### 통합 예시 스크립트

```bash
#!/bin/bash
# handle-incident.sh - 통합 인시던트 처리

INCIDENT_JSON='{"project":"jarvis","severity":"L2",...}'

# 1. 라우팅 및 리포트
./scripts/incident-router.sh "$INCIDENT_JSON"

# 2. 안전 복구 시도
./scripts/safe-autorepair.sh restart jarvis-api

# 3. 결과 전송 (후속 구현)
# ./scripts/send-to-discord.sh ...
# ./scripts/send-to-telegram.sh ...
```

---

## 4. 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| PROJECT_CHANNELS | general | L1용 프로젝트 채널 |
| ALERTS_CHANNEL | alerts | L2/L3용 알림 채널 |
| DISCORD_WEBHOOK_ALERTS | - | Discord webhook URL for L2/L3 |
| DISCORD_WEBHOOK_PROJECT | - | Discord webhook URL for L1 |
| TELEGRAM_SUMMARY | true | Telegram 요약 전송 여부 |
| LOG_FILE | logs/incident-autorepair.log | 로그 파일 |

---

## 5. 차기 작업 TODO

### Phase 1 (완료)
- [x] incident-router.sh 기본 구조
- [x] safe-autorepair.sh 안전 작업 스텁
- [x] 4줄 리포트 포맷
- [x] bash -n 검증

### Phase 2 (완료)
- [x] 실제 systemctl 연동 (restart/reload/status/health-check)
- [x] 서비스 allowlist 적용
- [x] --execute 플래그 기본 no-op 모드
- [x] 실행 전 확인 프롬프트 (--yes 옵션)
- [x] 로그 파일 기록 (logs/incident-autorepair.log)
- [x] Telegram Bot API 연동 (openclaw message send)
- [x] L2/L3 자동 발송 로직
- [x] --dry-run 모드
- [x] L3 TTS 옵션 (--tts 플래그)
- [x] 재시도 로직 (1회)

### Phase 3 (완료)
- [x] 인시던트 DB 저장 (SQLite + JSONL 폴백)
- [x] 민감정보 마스킹 (password, token, api_key, 이메일, 전화번호)
- [x] 최근 N건 조회 (--list)
- [x] 상태 업데이트 (--status)
- [x] Discord Webhook 연동 (DISCORD_WEBHOOK_ALERTS/PROJECT)
- [ ] Slack 온콜 연동 (L3)

### Phase 4 (고도화)
- [ ] 통계 및 대시보드
- [ ] 자동 에스컬레이션
- [ ] 장애 패턴 학습

---

## 7. 인시던트 DB (`incident-db.sh`)

### 사용법

```bash
./scripts/incident-db.sh <COMMAND> [ARGS]
```

### 명령어

| 명령어 | 설명 |
|--------|------|
| `insert '<JSON>'` | 인시던트 저장 |
| `--list [N]` | 최근 N건 조회 (기본: 20) |
| `--get <ID>` | 단건 조회 |
| `--status <ID> <S>` | 상태 업데이트 |

### 스키마

| 필드 | 타입 | 설명 |
|------|------|------|
| id | INTEGER | 자동 증가 ID |
| occurred_at | TEXT | 발생 시각 (ISO 8601) |
| project | TEXT | 프로젝트명 |
| severity | TEXT | 심각도 (L1/L2/L3) |
| level | TEXT | 상세 레벨 |
| title | TEXT | 제목 |
| cause | TEXT | 원인 |
| action | TEXT | 조치 내용 |
| verify | TEXT | 검증 방법 |
| prevent | TEXT | 재발방지 대책 |
| status | TEXT | 상태 (open/resolved/closed) |
| created_at | TEXT | 생성 시각 |

### 민감정보 마스킹

자동 마스킹 대상:
- `password=***`
- `token=***`
- `api_key=***`
- `secret=***`
- `credential=***`
- 이메일 주소
- 전화번호 (XXX-XXXX-XXXX)

### 폴백

sqlite3 없을 경우 자동으로 JSONL 파일로 저장:
- 경로: `data/incidents.jsonl`
- 포맷: 한 줄에 하나의 JSON 객체

### 예시

```bash
# 저장
./scripts/incident-db.sh insert '{"project":"jarvis","severity":"L2","title":"API 지연"}'

# 목록 조회
./scripts/incident-db.sh --list 10

# 상태 변경
./scripts/incident-db.sh --status 1 resolved
```

---

## 8. 문제 해결

### jq 없이 실행 시

```bash
# Ubuntu/Debian
sudo apt-get install jq

# 또는 내장 파싱 사용 (자동 폴백)
```

### 로그 파일 권한

```bash
sudo touch /var/log/autorepair.log
sudo chown $USER /var/log/autorepair.log
```

### 테스트

```bash
# 드라이런으로 테스트
./scripts/safe-autorepair.sh restart nginx --dry-run

# 샘플 JSON으로 라우팅 테스트
./scripts/incident-router.sh '{"project":"test","severity":"L1","title":"테스트"}'
```

---

*Last updated: 2026-03-01*
