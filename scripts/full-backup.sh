#!/bin/bash
# Full workspace backup script <!-- 전체 워크스페이스 백업 -->
# Creates timestamped tar.gz in /root/backups/

set -e

# Load message guard
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true

BACKUP_DIR="/root/backups"
WORKSPACE="/root/.openclaw/workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/jarvis-workspace-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

# Backup workspace (exclude node_modules, large files) <!-- 큰 파일 제외 -->
tar czf "$BACKUP_FILE" \
  -C /root/.openclaw \
  --exclude='workspace/node_modules' \
  --exclude='workspace/skills/auto-backup/backups' \
  --exclude='*.tar.gz' \
  workspace/

# Also backup openclaw config <!-- openclaw 설정도 백업 -->
tar rzf "$BACKUP_FILE" \
  -C /root/.openclaw \
  openclaw.json 2>/dev/null || true

# Also backup systemd services <!-- systemd 서비스 파일도 백업 -->
tar rzf "$BACKUP_FILE" \
  -C /etc/systemd/system \
  strava-webhook.service \
  cloudflared-strava.service \
  strava-webhook-register.service \
  openclaw-gateway.service 2>/dev/null || true

# Git commit (if in repo) <!-- git 커밋 -->
cd "$WORKSPACE"
if [ -d .git ]; then
  git add -A 2>/dev/null
  git commit -m "🤖 Auto backup: ${TIMESTAMP}" 2>/dev/null || true
  # Push if remote exists <!-- 원격 있으면 푸시 -->
  git push 2>/dev/null || true
fi

# Keep only last 7 backups <!-- 최근 7개만 유지 -->
ls -t "${BACKUP_DIR}"/jarvis-workspace-*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true

FILESIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup complete: ${BACKUP_FILE} (${FILESIZE})"
echo "📁 Backups kept: $(ls "${BACKUP_DIR}"/jarvis-workspace-*.tar.gz 2>/dev/null | wc -l)/7"

# Upload to Cloudflare R2 <!-- R2 원격 백업 -->
# Required env (or credentials/r2.env):
# - CLOUDFLARE_ACCOUNT_ID
# - R2_BUCKET
# - R2_ACCESS_KEY_ID
# - R2_SECRET_ACCESS_KEY
# Optional:
# - R2_ENDPOINT (default: https://<ACCOUNT_ID>.r2.cloudflarestorage.com)
R2_ENV_FILE="/root/.openclaw/workspace/credentials/r2.env"
if [ -f "$R2_ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$R2_ENV_FILE"
fi

if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${R2_BUCKET:-}" ] && [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_SECRET_ACCESS_KEY:-}" ]; then
  R2_ENDPOINT="${R2_ENDPOINT:-${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com}"
  # rclone Cloudflare S3 endpoint는 scheme 없는 host 형식을 기대함
  R2_ENDPOINT="${R2_ENDPOINT#https://}"
  R2_ENDPOINT="${R2_ENDPOINT#http://}"
  R2_REMOTE=":s3,provider=Cloudflare,access_key_id=${R2_ACCESS_KEY_ID},secret_access_key=${R2_SECRET_ACCESS_KEY},endpoint=${R2_ENDPOINT},no_check_bucket=true"

  echo "☁️ Uploading to Cloudflare R2..."
  if rclone copy "$BACKUP_FILE" "${R2_REMOTE}:${R2_BUCKET}" --checksum --transfers=1 --checkers=4; then
    echo "✅ R2 upload OK: ${R2_BUCKET}/$(basename "$BACKUP_FILE")"
  else
    echo "❌ R2 upload failed"
    exit 1
  fi

  # Usage guardrails (7GB alarm, 5GB target by pruning old backups)
  ALERT_BYTES=$((7 * 1024 * 1024 * 1024))   # 7 GiB
  RESET_BYTES=$((6 * 1024 * 1024 * 1024))   # 6 GiB (alert reset hysteresis)
  TARGET_BYTES=$((5 * 1024 * 1024 * 1024))  # 5 GiB
  ALERT_STATE_FILE="/root/.openclaw/workspace/.state/r2-usage-alert.sent"
  mkdir -p "$(dirname "$ALERT_STATE_FILE")"

  USAGE_JSON=$(rclone size "${R2_REMOTE}:${R2_BUCKET}" --json 2>/dev/null || echo '{}')
  CUR_BYTES=$(echo "$USAGE_JSON" | jq -r '.bytes // 0')
  CUR_GB=$(awk -v b="$CUR_BYTES" 'BEGIN {printf "%.2f", b/1024/1024/1024}')

  if [ "$CUR_BYTES" -ge "$ALERT_BYTES" ]; then
    if [ ! -f "$ALERT_STATE_FILE" ]; then
      echo "🚨 R2 usage alert: ${CUR_GB} GiB (>= 7 GiB)"
      date -Iseconds > "$ALERT_STATE_FILE"

      # Telegram alert (with validation)
      ALERT_CHANNEL="${ALERT_CHANNEL:-telegram}"
      ALERT_TARGET="${ALERT_TARGET:-62403941}"
      ALERT_MSG="🚨 R2 용량 경고: ${CUR_GB} GiB (임계 7 GiB 초과). 5 GiB 초과 시 자동 정리 정책 동작 중."
      if validate_message_params --channel "$ALERT_CHANNEL" --target "$ALERT_TARGET"; then
        openclaw message send --channel "$ALERT_CHANNEL" --target "$ALERT_TARGET" --message "$ALERT_MSG" >/dev/null 2>&1 || true
      else
        echo "[WARN] Alert skipped: missing channel/target" >&2
      fi
    else
      echo "⚠️ R2 usage still high: ${CUR_GB} GiB (alert already sent)"
    fi
  else
    echo "📦 R2 usage: ${CUR_GB} GiB"
    if [ "$CUR_BYTES" -lt "$RESET_BYTES" ] && [ -f "$ALERT_STATE_FILE" ]; then
      rm -f "$ALERT_STATE_FILE"
      echo "✅ R2 alert state reset (< 6 GiB)"
    fi
  fi

  if [ "$CUR_BYTES" -gt "$TARGET_BYTES" ]; then
    echo "🧹 R2 usage > 5 GiB, pruning oldest backups..."
    PRUNED_COUNT=0
    FILES_JSON=$(rclone lsjson "${R2_REMOTE}:${R2_BUCKET}" --files-only --include "jarvis-workspace-*.tar.gz" 2>/dev/null || echo '[]')
    # oldest first by ModTime
    while IFS=$'\t' read -r fpath fsize; do
      [ -z "$fpath" ] && continue
      if [ "$CUR_BYTES" -le "$TARGET_BYTES" ]; then
        break
      fi
      rclone deletefile "${R2_REMOTE}:${R2_BUCKET}/${fpath}" && {
        CUR_BYTES=$((CUR_BYTES - fsize))
        CUR_GB=$(awk -v b="$CUR_BYTES" 'BEGIN {printf "%.2f", b/1024/1024/1024}')
        PRUNED_COUNT=$((PRUNED_COUNT + 1))
        echo "  - deleted ${fpath} (${fsize} bytes), now ${CUR_GB} GiB"
      }
    done < <(echo "$FILES_JSON" | jq -r 'sort_by(.ModTime)[] | "\(.Path)\t\(.Size)"')

    if [ "$PRUNED_COUNT" -gt 0 ]; then
      ALERT_CHANNEL="${ALERT_CHANNEL:-telegram}"
      ALERT_TARGET="${ALERT_TARGET:-62403941}"
      PRUNE_MSG="🧹 R2 자동정리 실행: ${PRUNED_COUNT}개 삭제, 현재 ${CUR_GB} GiB (목표 5 GiB 이하)."
      if validate_message_params --channel "$ALERT_CHANNEL" --target "$ALERT_TARGET"; then
        openclaw message send --channel "$ALERT_CHANNEL" --target "$ALERT_TARGET" --message "$PRUNE_MSG" >/dev/null 2>&1 || true
      else
        echo "[WARN] Prune alert skipped: missing channel/target" >&2
      fi
    fi
  fi

  # Keep last 30 remote backups as secondary guard
  echo "🧹 R2 remote cleanup (keep latest 30)..."
  rclone lsf "${R2_REMOTE}:${R2_BUCKET}" --files-only --include "jarvis-workspace-*.tar.gz" \
    | sort -r \
    | awk 'NR>30' \
    | while read -r oldfile; do
        [ -n "$oldfile" ] && rclone deletefile "${R2_REMOTE}:${R2_BUCKET}/${oldfile}" || true
      done
else
  echo "⚠️ R2 upload skipped: missing credentials (CLOUDFLARE_ACCOUNT_ID/R2_BUCKET/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY)"
fi

# Nightly memory hygiene (promote + recall check + sqlite mirror)
echo "🧠 Running nightly memory hygiene..."
if bash /root/.openclaw/workspace/scripts/nightly-memory-hygiene.sh; then
  echo "✅ Nightly memory hygiene complete"
else
  echo "❌ Nightly memory hygiene failed"
  exit 1
fi
