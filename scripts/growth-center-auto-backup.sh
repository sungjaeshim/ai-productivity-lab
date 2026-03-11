#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/root/.openclaw/workspace/growth-center}"
BACKUP_DIR="${BACKUP_DIR:-/root/backups/growth-center}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/growth-center-${TIMESTAMP}.tar.gz"
BRANCH_NAME="${BRANCH_NAME:-master}"
DRY_RUN="${DRY_RUN:-0}"
COMMIT_NAME="${BACKUP_GIT_NAME:-sungjaeshim}"
COMMIT_EMAIL="${BACKUP_GIT_EMAIL:-mujigi@naver.com}"
RUN_RELEASE_PROD="${RUN_RELEASE_PROD:-1}"

log() {
  printf '[growth-center-backup] %s\n' "$*"
}

die() {
  printf '[growth-center-backup] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_cmd git
need_cmd tar

[[ -d "$PROJECT_DIR" ]] || die "missing project dir: $PROJECT_DIR"
[[ -d "$PROJECT_DIR/.git" ]] || die "not a git repo: $PROJECT_DIR"

mkdir -p "$BACKUP_DIR"

log "project: $PROJECT_DIR"
log "backup file: $BACKUP_FILE"
log "commit author: $COMMIT_NAME <$COMMIT_EMAIL>"
log "post-push release: $RUN_RELEASE_PROD"

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run: would create tar.gz backup"
else
  tar czf "$BACKUP_FILE" \
    -C "$PROJECT_DIR" \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='playwright-report' \
    --exclude='test-results' \
    --exclude='.vercel' \
    --exclude='*.tar.gz' \
    .
  log "backup created"
fi

# Keep last 7 backups.
if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run: would prune old backups beyond latest 7"
else
  ls -t "${BACKUP_DIR}"/growth-center-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
fi

cd "$PROJECT_DIR"

log "staging tracked changes (excluding transient artifacts)"
STAGED_JSON="$(python3 - <<'PY'
import json
import subprocess
from pathlib import Path

excluded_prefixes = (
    "playwright-report/",
    "test-results/",
    ".vercel/",
    "node_modules/",
)

cmd = ["git", "status", "--porcelain=v1", "-z"]
raw = subprocess.check_output(cmd)
items = []
for entry in raw.decode("utf-8", errors="ignore").split("\0"):
    if not entry:
        continue
    path = entry[3:]
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    if any(path == prefix[:-1] or path.startswith(prefix) for prefix in excluded_prefixes):
        continue
    items.append(path)

print(json.dumps(items, ensure_ascii=False))
PY
)"

mapfile -t STAGED_PATHS < <(printf '%s' "$STAGED_JSON" | jq -r '.[]')

if [[ "$DRY_RUN" == "1" ]]; then
  if [[ ${#STAGED_PATHS[@]} -eq 0 ]]; then
    log "dry-run: no eligible paths to stage"
  else
    printf '[growth-center-backup] dry-run: would stage %s path(s)\n' "${#STAGED_PATHS[@]}"
    printf '%s\n' "${STAGED_PATHS[@]}" | sed 's/^/[growth-center-backup]   - /'
  fi
else
  if [[ ${#STAGED_PATHS[@]} -gt 0 ]]; then
    git add -A -- "${STAGED_PATHS[@]}"
  fi
fi

STATUS_SUMMARY="$(git status --short -- . ':(exclude)playwright-report' ':(exclude)test-results' ':(exclude).vercel' ':(exclude)node_modules' || true)"
if [[ -z "$STATUS_SUMMARY" ]]; then
  log "no tracked changes to commit"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '{ "ok": true, "committed": false, "pushed": false, "backup": "%s", "dry_run": true }\n' "$BACKUP_FILE"
  else
    printf '{ "ok": true, "committed": false, "pushed": false, "backup": "%s" }\n' "$BACKUP_FILE"
  fi
  exit 0
fi

COMMIT_MSG="🤖 growth-center autobackup: ${TIMESTAMP}"
if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run: would commit with message: $COMMIT_MSG"
  log "dry-run: would push origin $BRANCH_NAME"
  printf '{ "ok": true, "committed": false, "pushed": false, "backup": "%s", "dry_run": true }\n' "$BACKUP_FILE"
  exit 0
fi

GIT_AUTHOR_NAME="$COMMIT_NAME" \
GIT_AUTHOR_EMAIL="$COMMIT_EMAIL" \
GIT_COMMITTER_NAME="$COMMIT_NAME" \
GIT_COMMITTER_EMAIL="$COMMIT_EMAIL" \
git commit -m "$COMMIT_MSG" >/tmp/growth-center-autobackup-commit.log 2>&1 || {
  if git diff --cached --quiet; then
    log "nothing new to commit after staging"
    printf '{ "ok": true, "committed": false, "pushed": false, "backup": "%s" }\n' "$BACKUP_FILE"
    exit 0
  fi
  cat /tmp/growth-center-autobackup-commit.log >&2 || true
  die "git commit failed"
}

log "syncing with remote ${BRANCH_NAME} before push"
git fetch origin "$BRANCH_NAME" >/tmp/growth-center-autobackup-fetch.log 2>&1 || {
  cat /tmp/growth-center-autobackup-fetch.log >&2 || true
  die "git fetch failed"
}

git pull --rebase --autostash origin "$BRANCH_NAME" >/tmp/growth-center-autobackup-rebase.log 2>&1 || {
  cat /tmp/growth-center-autobackup-rebase.log >&2 || true
  die "git rebase failed"
}

git push origin "$BRANCH_NAME" >/tmp/growth-center-autobackup-push.log 2>&1 || {
  cat /tmp/growth-center-autobackup-push.log >&2 || true
  die "git push failed"
}

if [[ "$RUN_RELEASE_PROD" == "1" ]]; then
  log "running production release"
  bash "$PROJECT_DIR/scripts/release-prod.sh" >/tmp/growth-center-autobackup-release.log 2>&1 || {
    cat /tmp/growth-center-autobackup-release.log >&2 || true
    die "release:prod failed"
  }
else
  log "skipping production release"
fi

FILESIZE="$(du -h "$BACKUP_FILE" | cut -f1)"
printf '{ "ok": true, "committed": true, "pushed": true, "released": %s, "backup": "%s", "backup_size": "%s", "branch": "%s" }\n' "$([[ "$RUN_RELEASE_PROD" == "1" ]] && printf 'true' || printf 'false')" "$BACKUP_FILE" "$FILESIZE" "$BRANCH_NAME"
