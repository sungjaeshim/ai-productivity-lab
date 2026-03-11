# Docker 설치 → sandbox 재강화 플랜

작성: 2026-03-02

## 현재 상태
- `agents.defaults.sandbox.mode = "off"` (임시 완화)
- Docker 미설치: `command -v docker` → NOT FOUND
- 이유: sandbox=all 상태에서 Docker 없으면 `spawn docker ENOENT` 장애 발생

## 재강화 절차 (순서 엄수)

### Step 1: Docker 설치
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
command -v docker && echo "OK"
```

### Step 2: Docker 정상 확인
```bash
docker info 2>&1 | grep "Server Version"
```

### Step 3: sandbox=all 재적용
```bash
openclaw config patch '{"agents":{"defaults":{"sandbox":{"mode":"all"}}}}'
# 또는 gateway config.patch 툴 사용
```

### Step 4: 테스트 실행
```bash
openclaw security audit
# critical 항목이 사라졌는지 확인
```

## 현재 보완 조치
- `tools.deny = ["group:web","browser"]` 는 유지 중 → web 도구 차단으로 부분 완화

## 참고
- security audit critical 1건 잔존: "Small models require sandboxing"
- Docker 설치 후에만 완전 해소 가능
