# Resend/Sentry 실운영 Go-Live 체크리스트

**프로젝트:** Growth Center  
**서버:** jarvis (158.247.193.74)  
**작성일:** 2026-03-01

---

## 📊 현재 상태

| 항목 | 상태 | 비고 |
|------|------|------|
| Growth Center 서비스 | ✅ Active | 포트 18800, 정상 작동 |
| Resend 패키지 | ✅ 설치됨 | resend@6.9.3 |
| Sentry 패키지 | ✅ 설치됨 | @sentry/node@10.40.0 |
| 환경변수 주입 | ❌ 없음 | systemd override 필요 |
| RESEND_API_KEY | ❌ 미설정 | BLOCKER |
| RESEND_FROM | ❌ 미설정 | BLOCKER |
| RESEND_TO | ❌ 미설정 | BLOCKER |
| SENTRY_DSN | ❌ 미설정 | 선택 (미설정 시 비활성화) |

---

## 🚫 Blockers

### 1. Resend 환경변수 없음 (3개)
- `RESEND_API_KEY` - Resend API 키
- `RESEND_FROM` - 발신자 이메일 (Resend에서 검증된 도메인 필요)
- `RESEND_TO` - 기본 수신자 이메일

### 2. systemd에 환경변수 주입 메커니즘 없음
현재 `/etc/systemd/system/growth-center.service`:
```ini
[Service]
Environment=NODE_ENV=production  # 이것만 있음
```

---

## ✅ 해결 방안: systemd EnvironmentFile

### 선택 이유
1. **보안**: 키를 별도 파일로 관리, chmod 600 보호
2. **표준**: systemd 공식 권장 방식
3. **유지보수**: 서비스 파일 수정 없이 env만 교체 가능
4. **호환성**: Node.js dotenv 불필요, 네이티브 환경변수

### 구조
```
/root/Projects/growth-center/.env  (chmod 600)
    ↓
/etc/systemd/system/growth-center.service.d/override.conf
    ↓ EnvironmentFile
systemd → node process.env
```

---

## 🔧 실행 절차

### Step 1: 키 획득

| 변수 | 획득처 |
|------|--------|
| `RESEND_API_KEY` | https://resend.com/api-keys |
| `RESEND_FROM` | Resend 대시보드 → Domains → 검증된 도메인 사용 |
| `RESEND_TO` | 본인 이메일 |
| `SENTRY_DSN` | (선택) Sentry 프로젝트 Settings → Client Keys DSN |

### Step 2: 스크립트 실행 (dry-run)
```bash
/root/.openclaw/workspace/scripts/growth-center-env-setup.sh --dry-run
```

### Step 3: 실제 적용
```bash
RESEND_API_KEY=re_xxx \
RESEND_FROM=noreply@yourdomain.com \
RESEND_TO=you@example.com \
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx \
  /root/.openclaw/workspace/scripts/growth-center-env-setup.sh --apply
```

### Step 4: 검증
```bash
# 이메일 설정 확인
curl -s http://127.0.0.1:18800/api/system/email-test

# 테스트 이메일 발송
curl -X POST http://127.0.0.1:18800/api/system/email-test

# Sentry 로그 확인
journalctl -u growth-center -n 20 | grep -i sentry
```

---

## 📋 Go-Live 체크리스트

### 사전 준비
- [ ] Resend 계정 생성
- [ ] Resend에서 도메인 검증 (DNS 레코드 설정)
- [ ] Resend API 키 생성
- [ ] (선택) Sentry 프로젝트 생성 및 DSN 획득

### 실행
- [ ] 환경변수 값 준비 완료
- [ ] `--dry-run`으로 변경사항 미리보기
- [ ] `--apply`로 실제 적용
- [ ] 서비스 재시작 확인

### 검증
- [ ] `GET /api/system/email-test` → `configured: true`
- [ ] `POST /api/system/email-test` → 이메일 수신 확인
- [ ] Sentry 로그에 "Sentry initialized" 메시지 (DSN 설정 시)

---

## 🛡️ 보안 주의사항

1. **.env 파일 절대 커밋 금지**
   - `.gitignore`에 `.env` 포함됨 (확인됨)
   
2. **파일 권한**
   - `.env` 파일은 `chmod 600` (소유자만 읽기/쓰기)
   
3. **키 교체**
   - 의심스러운 활동 시 즉시 API 키 재발급
   - 재발급 후 스크립트 재실행

---

## 📁 생성 파일

| 파일 | 용도 |
|------|------|
| `/root/Projects/growth-center/.env` | 환경변수 저장 (chmod 600) |
| `/etc/systemd/system/growth-center.service.d/override.conf` | systemd override |

---

## 🔍 문제 해결

### 이메일 발송 실패
```bash
# 1. 환경변수 확인
curl -s http://127.0.0.1:18800/api/system/email-test

# 2. 서비스 로그
journalctl -u growth-center -f

# 3. Resend 대시보드에서 전송 로그 확인
```

### Sentry 미작동
```bash
# SENTRY_DSN 설정 확인
systemctl show growth-center --property=Environment | grep -i sentry

# 서비스 로그에서 초기화 메시지 확인
journalctl -u growth-center | grep -i sentry
```

---

## 📞 연락처/참고

- Resend Docs: https://resend.com/docs
- Sentry Node Docs: https://docs.sentry.io/platforms/node/
- 스크립트 위치: `/root/.openclaw/workspace/scripts/growth-center-env-setup.sh`
