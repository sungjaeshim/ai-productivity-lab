#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/repo-backup-release-targets.json}"
DISCORD_TARGET_DEFAULT="${DISCORD_RELEASE_TARGET:-${DISCORD_BRIEFING_LOG_CHANNEL_ID:-1477462915509387314}}"

usage() {
  cat <<'EOF'
Usage:
  repo-backup-release.sh <target> [--dry-run] [--no-release]
EOF
}

log() {
  printf '[repo-backup-release] %s\n' "$*"
}

die() {
  printf '[repo-backup-release] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_cmd git
need_cmd jq
need_cmd tar

verify_vercel_link() {
  local project_dir="$1"
  local expected_project="$2"

  [[ -n "$expected_project" && "$expected_project" != "null" ]] || return 0

  local vercel_project_file="${project_dir}/.vercel/project.json"
  [[ -f "$vercel_project_file" ]] || die "missing Vercel link file: $vercel_project_file"

  local linked_project
  linked_project="$(jq -r '.projectName // empty' "$vercel_project_file")"
  [[ -n "$linked_project" ]] || die "unable to resolve linked Vercel project from $vercel_project_file"

  if [[ "$linked_project" != "$expected_project" ]]; then
    die "Vercel link mismatch: linked=${linked_project}, expected=${expected_project}. Re-link this repo before release."
  fi
}

send_discord_summary() {
  local message="$1"
  local target="${DISCORD_TARGET_DEFAULT:-}"

  if [[ -z "$target" ]]; then
    log "discord summary skipped: missing target"
    return 0
  fi

  if [[ ! -x "${SCRIPT_DIR}/discord-send-safe.sh" ]]; then
    log "discord summary skipped: missing discord-send-safe.sh"
    return 0
  fi

  if ! "${SCRIPT_DIR}/discord-send-safe.sh" --channel-id "$target" --message "$message" >/tmp/"${TARGET}"-discord-summary.log 2>&1; then
    cat /tmp/"${TARGET}"-discord-summary.log >&2 || true
    log "discord summary failed (ignored)"
    return 0
  fi
}

TARGET="${1:-}"
[[ -n "$TARGET" ]] || {
  usage
  exit 1
}
shift || true

DRY_RUN="${DRY_RUN:-0}"
RUN_RELEASE="${RUN_RELEASE:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-release)
      RUN_RELEASE=0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
  shift
done

[[ -f "$CONFIG_PATH" ]] || die "missing config: $CONFIG_PATH"

cfg() {
  jq -r --arg target "$TARGET" ".targets[\$target]$1" "$CONFIG_PATH"
}

ENABLED="$(cfg '.enabled')"
PROJECT_DIR="$(cfg '.projectDir')"
BRANCH="$(cfg '.branch')"
REPO_NAME="$(cfg '.repo')"
VERCEL_PROJECT="$(cfg '.vercelProject')"
COMMIT_NAME="${BACKUP_GIT_NAME:-$(cfg '.commitName')}"
COMMIT_EMAIL="${BACKUP_GIT_EMAIL:-$(cfg '.commitEmail')}"
RELEASE_COMMAND="$(cfg '.releaseCommand')"
NOTE="$(cfg '.note')"

[[ "$ENABLED" == "true" ]] || die "target '$TARGET' is disabled"
[[ -d "$PROJECT_DIR/.git" ]] || die "not a git repo: $PROJECT_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/backups/${TARGET}"
BACKUP_FILE="${BACKUP_DIR}/${TARGET}-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

log "target: $TARGET"
log "project: $PROJECT_DIR"
log "repo: $REPO_NAME"
log "vercel project: $VERCEL_PROJECT"
log "backup file: $BACKUP_FILE"
log "commit author: $COMMIT_NAME <$COMMIT_EMAIL>"
log "release enabled: $RUN_RELEASE"
log "note: $NOTE"

cd "$PROJECT_DIR"

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run: would create tar.gz backup"
else
  tar czf "$BACKUP_FILE" \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='.vercel' \
    --exclude='dist' \
    --exclude='playwright-report' \
    --exclude='test-results' \
    .
fi

mapfile -t STAGED_PATHS < <(git status --porcelain=v1 | awk '{print $2}' | sed '/^$/d')

if [[ ${#STAGED_PATHS[@]} -eq 0 ]]; then
  log "no eligible tracked changes"
  printf '{ "ok": true, "target": "%s", "committed": false, "pushed": false, "released": false, "backup": "%s", "dry_run": %s }\n' "$TARGET" "$BACKUP_FILE" "$([[ "$DRY_RUN" == "1" ]] && printf 'true' || printf 'false')"
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  printf '[repo-backup-release] dry-run: would stage %s path(s)\n' "${#STAGED_PATHS[@]}"
  printf '%s\n' "${STAGED_PATHS[@]}" | sed 's/^/[repo-backup-release]   - /'
  log "dry-run: would commit with target-aware author"
  log "dry-run: would push origin $BRANCH"
  if [[ "$RUN_RELEASE" == "1" ]]; then
    log "dry-run: would run release command: $RELEASE_COMMAND"
  fi
  printf '{ "ok": true, "target": "%s", "committed": false, "pushed": false, "released": false, "backup": "%s", "dry_run": true }\n' "$TARGET" "$BACKUP_FILE"
  exit 0
fi

git add -A
GIT_AUTHOR_NAME="$COMMIT_NAME" \
GIT_AUTHOR_EMAIL="$COMMIT_EMAIL" \
GIT_COMMITTER_NAME="$COMMIT_NAME" \
GIT_COMMITTER_EMAIL="$COMMIT_EMAIL" \
git commit -m "🤖 ${TARGET} autobackup: ${TIMESTAMP}" || true
git pull --rebase --autostash origin "$BRANCH"
git push origin "$BRANCH"

if [[ "$RUN_RELEASE" == "1" ]]; then
  if [[ "$RELEASE_COMMAND" == *"vercel"* ]]; then
    verify_vercel_link "$PROJECT_DIR" "$VERCEL_PROJECT"
  fi
  bash -lc "cd '$PROJECT_DIR' && ${RELEASE_COMMAND}"
fi

SUMMARY=$'📦 자동 백업 + 릴리즈 완료\n'"- target: ${TARGET}"$'\n'"- repo: ${REPO_NAME}"$'\n'"- branch: ${BRANCH}"$'\n'"- release: $([[ "$RUN_RELEASE" == "1" ]] && printf 'yes' || printf 'no')"$'\n'"- backup: $(basename "$BACKUP_FILE")"
send_discord_summary "$SUMMARY"

printf '{ "ok": true, "target": "%s", "committed": true, "pushed": true, "released": %s, "backup": "%s" }\n' "$TARGET" "$([[ "$RUN_RELEASE" == "1" ]] && printf 'true' || printf 'false')" "$BACKUP_FILE"
