# Sentry Project Mapping

## 개요
프로젝트별 Sentry DSN 매핑 및 주입 가이드. 실제 키는 절대 이 문서에 작성 금지.

---

## 프로젝트별 DSN 변수명 표준

| 프로젝트 | 변수명 | Sentry Project (예상) |
|---------|--------|----------------------|
| Growth Center | `SENTRY_DSN_GROWTH_CENTER` | `growth-center` |
| Blog | `SENTRY_DSN_BLOG` | `blog` |
| CEO AI | `SENTRY_DSN_CEO_AI` | `ceo-ai` |
| MACD Bot | `SENTRY_DSN_MACD_BOT` | `macd-bot` |

---

## 주입 경로 (Injection Paths)

### 1. Growth Center
```
서비스: Growth Center Web/App
환경변수 파일:
  - 프로덕션: /opt/growth-center/.env.production
  - 스테이징: /opt/growth-center/.env.staging
  - 로컬: projects/growth-center/.env.local

주입 방식:
  - Docker: docker-compose.yml의 environment 섹션
  - Kubernetes: ConfigMap/Secret (sentry-dsn-secret)
  - Systemd: /etc/systemd/system/growth-center.service의 EnvironmentFile
```

### 2. Blog
```
서비스: Blog Platform
환경변수 파일:
  - 프로덕션: /opt/blog/.env.production
  - 스테이징: /opt/blog/.env.staging
  - 로컬: projects/blog/.env.local

주입 방식:
  - Docker: docker-compose.yml의 environment 섹션
  - Kubernetes: ConfigMap/Secret (blog-sentry-secret)
  - Vercel/Netlify: 대시보드 Environment Variables
```

### 3. CEO AI
```
서비스: CEO AI Assistant
환경변수 파일:
  - 프로덕션: /opt/ceo-ai/.env.production
  - 스테이징: /opt/ceo-ai/.env.staging
  - 로컬: projects/ceo-ai/.env.local

주입 방식:
  - Docker: docker-compose.yml의 environment 섹션
  - Kubernetes: ConfigMap/Secret (ceo-ai-sentry-secret)
  - Systemd: /etc/systemd/system/ceo-ai.service의 EnvironmentFile
```

### 4. MACD Bot
```
서비스: MACD Trading Bot
환경변수 파일:
  - 프로덕션: /opt/macd-bot/.env.production
  - 스테이징: /opt/macd-bot/.env.staging
  - 로컬: projects/macd-bot/.env.local

주입 방식:
  - Docker: docker-compose.yml의 environment 섹션
  - Systemd: /etc/systemd/system/macd-bot.service의 EnvironmentFile
  - Cron: ~/.macd-bot.env (source 후 실행)
```

---

## 환경별 DSN 구성

| 환경 | 접두어 | 예시 |
|-----|--------|------|
| Production | (없음) | `SENTRY_DSN_GROWTH_CENTER` |
| Staging | `STAGING_` | `STAGING_SENTRY_DSN_GROWTH_CENTER` |
| Development | `DEV_` | `DEV_SENTRY_DSN_GROWTH_CENTER` |

---

## Sentry 프로젝트 생성 체크리스트

1. [ ] Sentry 팀에서 4개 프로젝트 생성
2. [ ] 각 프로젝트별 DSN 발급 (Settings > Projects > [Project] > Client Keys)
3. [ ] 환경별 DSN 복사 (prod/staging/dev)
4. [ ] 보안 저장소(1Password/Vault 등)에 DSN 백업
5. [ ] 각 서비스의 env 파일에 주입
6. [ ] smoke-check.sh로 검증

---

## 보안 주의사항

- DSN은 공개 저장소에 커밋 금지
- `.env` 파일은 `.gitignore`에 포함 확인
- 프로덕션 DSN은 Secret 관리 도구 사용 권장
- DSN 탈취 시 Sentry에서 재생성 가능

---

## 관련 파일

- 템플릿: `config/sentry-dsn-template.env`
- 검증 스크립트: `scripts/sentry-smoke-check.sh`

---

## 업데이트 이력

| 날짜 | 내용 | 작성자 |
|-----|------|--------|
| 2026-03-01 | 초안 작성 | Jarvis |
