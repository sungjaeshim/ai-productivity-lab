# Resend/Sentry 실운영 검증 보고서

**검증 일시:** 2026-03-01 10:10 KST
**프로젝트:** /root/Projects/growth-center
**서버 상태:** 실행 중 (port 18800, PID 1013284)

---

## 1. 검증 결과 요약

| 항목 | 상태 | 비고 |
|------|------|------|
| **Resend 의존성** | ✅ 설치됨 | `resend@6.9.3` |
| **Sentry 의존성** | ✅ 설치됨 | `@sentry/node@10.40.0` |
| **Resend 설정** | 🚫 **BLOCKER** | env 3개 누락 |
| **Sentry 설정** | 🚫 **BLOCKER** | DSN 미설정 |
| **코드 경로** | ✅ 일치 | routes/system.js, utils/mail.js |
| **API 엔드포인트** | ✅ 정상 | GET/POST /api/system/email-test |

---

## 2. Resend 검증 상세

### 2.1 API 응답 (GET /api/system/email-test)

```json
{
  "success": true,
  "data": {
    "configured": false,
    "from": null,
    "to": null,
    "missing": ["RESEND_API_KEY", "RESEND_FROM", "RESEND_TO"],
    "hint": "Set these environment variables: RESEND_API_KEY, RESEND_FROM, RESEND_TO"
  }
}
```

### 2.2 코드 구현 확인

- **위치:** `utils/mail.js`
- **클라이언트 초기화:** `new Resend(process.env.RESEND_API_KEY)`
- **발송 함수:** `sendTestEmail()` — API 키 없으면 즉시 실패
- **엔드포인트:** `routes/system.js` — GET/POST 모두 구현됨

---

## 3. Sentry 검증 상세

### 3.1 현재 상태

- **서버 로그:** "Sentry initialized" 미출력 → 비활성 상태
- **서버 시작 로그:** "📊 Sentry: Disabled (set SENTRY_DSN to enable)" 예상
- **프로세스 환경:** SENTRY_DSN 미설정 확인

### 3.2 코드 구현 확인

```javascript
// server.js (요약)
const SENTRY_DSN = process.env.SENTRY_DSN;
if (SENTRY_DSN) {
  Sentry = require('@sentry/node');
  Sentry.init({ dsn: SENTRY_DSN });
  console.log('🔍 Sentry initialized');
} else {
  // no-op fallback
}
```

- **requestHandler:** 라우팅 전 배치 (line 73)
- **errorHandler:** 기존 에러 핸들러 전 배치 (line 286)
- **captureException:** 글로벌 에러 핸들러에서 호출 (line 156)

---

## 4. Blocker 분석

### 4.1 Resend Blocker

| ENV 변수 | 필수 | 용도 | 획득 방법 |
|----------|------|------|-----------|
| `RESEND_API_KEY` | ✅ | Resend API 인증 | https://resend.com/api-keys |
| `RESEND_FROM` | ✅ | 발신자 이메일 | Resend에서 도메인 인증 후 사용 |
| `RESEND_TO` | ✅ | 테스트 수신자 | 실제 수신 가능한 이메일 |

### 4.2 Sentry Blocker

| ENV 변수 | 필수 | 용도 | 획득 방법 |
|----------|------|------|-----------|
| `SENTRY_DSN` | ✅ | Sentry 프로젝트 DSN | https://sentry.io/settings/projects/ |

---

## 5. 서비스 파일 현황

```ini
# /etc/systemd/system/growth-center.service
[Service]
WorkingDirectory=/root/Projects/growth-center
ExecStart=/usr/bin/node server.js
Environment=NODE_ENV=production
# ⚠️ EnvironmentFile 미설정 → env 파일 로드 안 됨
```

---

## 6. Env 주입 체크리스트

### 6.1 사전 준비

- [ ] Resend 계정 생성 및 도메인 인증
- [ ] Resend API Key 발급 (re_xxx 형식)
- [ ] Sentry 프로젝트 생성
- [ ] Sentry DSN 복사 (https://xxx@xxx.ingest.sentry.io/xxx)

### 6.2 Env 파일 생성

```bash
# /root/Projects/growth-center/.env 생성
cat > /root/Projects/growth-center/.env << 'EOF'
# Resend
RESEND_API_KEY=re_xxxxxxxxxxxx
RESEND_FROM=noreply@yourdomain.com
RESEND_TO=your-email@example.com

# Sentry
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
EOF

chmod 600 /root/Projects/growth-center/.env
```

### 6.3 서비스 파일 수정

```bash
# EnvironmentFile 추가
sudo sed -i '/^Environment=/a EnvironmentFile=/root/Projects/growth-center/.env' /etc/systemd/system/growth-center.service
sudo systemctl daemon-reload
sudo systemctl restart growth-center
```

### 6.4 검증

```bash
# 1. Sentry 활성화 확인
journalctl -u growth-center -n 5 | grep -i sentry
# 예상: "📊 Sentry: Enabled (production)"

# 2. Resend 설정 확인
curl -s http://127.0.0.1:18800/api/system/email-test | jq '.data.configured'
# 예상: true

# 3. 테스트 이메일 발송
curl -X POST http://127.0.0.1:18800/api/system/email-test
```

---

## 7. 다음 액션

1. **Resend/Sentry 계정 및 키 준비** — 사용자가 직접 발급 필요
2. **.env 파일 생성** — 위 체크리스트 6.2 참조
3. **서비스 파일 수정 후 재시작** — 체크리스트 6.3 참조

---

## 8. Smoke Test 스크립트

검증용 스크립트: `/root/.openclaw/workspace/scripts/resend-sentry-smoke.sh`

```bash
bash /root/.openclaw/workspace/scripts/resend-sentry-smoke.sh
```

---

**작성자:** PCM Task 4 Subagent
**검증 완료:** 2026-03-01 10:15 KST
