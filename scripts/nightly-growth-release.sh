#!/usr/bin/env bash
set -euo pipefail

export HOME=/root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LOCK_FILE="/tmp/nightly-growth-release.lock"
PROJECT_DIR="/root/Projects/growth-center"
RELEASE_SCRIPT="$PROJECT_DIR/scripts/release-prod.sh"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[nightly-growth-release] another run is in progress; skip."
  exit 0
fi

if [[ ! -x "$RELEASE_SCRIPT" ]]; then
  echo "[nightly-growth-release] release script missing or not executable: $RELEASE_SCRIPT"
  exit 1
fi

echo "[nightly-growth-release] start $(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
cd "$PROJECT_DIR"
bash "$RELEASE_SCRIPT"
echo "[nightly-growth-release] done  $(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
