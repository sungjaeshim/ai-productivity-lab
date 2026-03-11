#!/usr/bin/env bash
set -euo pipefail

PATCH_ROOT="/root/.openclaw/workspace/patches/local-rescue-runtime"
FILES_DIR="$PATCH_ROOT/files"
CHECKSUMS_FILE="$PATCH_ROOT/SHA256SUMS"

RESTART_GATEWAY=1
VERIFY_ONLY=0
CORE_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  reapply-local-rescue-runtime.sh [--verify-only] [--no-restart] [--core-only]

What it does:
  1. Restores the saved local-rescue runtime patch snapshot into the OpenClaw dist install.
  2. Runs node --check on the restored bundles.
  3. Restarts openclaw-gateway unless --no-restart is set.

Options:
  --verify-only   Check that snapshot files and checksums exist, then exit.
  --no-restart    Skip gateway restart after restore.
  --core-only     Restore only the current core keep-set (compact/reply/pi-embedded variants).
                 Legacy full restore targets are retained for archive/reference only unless re-baselined.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    --no-restart)
      RESTART_GATEWAY=0
      shift
      ;;
    --core-only)
      CORE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$FILES_DIR" ]]; then
  echo "missing snapshot dir: $FILES_DIR" >&2
  exit 1
fi

if [[ ! -f "$CHECKSUMS_FILE" ]]; then
  echo "missing checksums file: $CHECKSUMS_FILE" >&2
  exit 1
fi

pushd "$FILES_DIR" >/dev/null
sha256sum -c "$CHECKSUMS_FILE"
popd >/dev/null

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  echo "snapshot verification passed"
  exit 0
fi

CORE_RESTORE_FILES=(
  "/usr/lib/node_modules/openclaw/dist/compact-D3emcZgv.js"
  "/usr/lib/node_modules/openclaw/dist/reply-DeXK9BLT.js"
  "/usr/lib/node_modules/openclaw/dist/pi-embedded-CrsFdYam.js"
  "/usr/lib/node_modules/openclaw/dist/pi-embedded-jHMb7qEG.js"
)

FULL_RESTORE_LEGACY_FILES=(
  "/usr/lib/node_modules/openclaw/dist/auth-profiles-5CHn7vq1.js"
  "/usr/lib/node_modules/openclaw/dist/compact-B247y5Qt.js"
  "/usr/lib/node_modules/openclaw/dist/gateway-cli-BCNMwzNq.js"
  "/usr/lib/node_modules/openclaw/dist/model-selection-BU6wl1le.js"
  "/usr/lib/node_modules/openclaw/dist/model-selection-L7RMwsG-.js"
  "/usr/lib/node_modules/openclaw/dist/pi-embedded-C6ITuRXf.js"
  "/usr/lib/node_modules/openclaw/dist/pi-embedded-DoQsYfIY.js"
  "/usr/lib/node_modules/openclaw/dist/reply-C5LKjXcC.js"
)

if [[ "$CORE_ONLY" -eq 1 ]]; then
  targets=("${CORE_RESTORE_FILES[@]}")
else
  targets=("${FULL_RESTORE_LEGACY_FILES[@]}")
fi

for target in "${targets[@]}"; do
  base_name="$(basename "$target")"
  snapshot="$FILES_DIR/$base_name"
  if [[ ! -f "$snapshot" ]]; then
    echo "missing snapshot file: $snapshot" >&2
    exit 1
  fi
  if [[ ! -f "$target" ]]; then
    echo "missing install target: $target" >&2
    echo "OpenClaw dist file name changed. Re-baseline the snapshot for the new build." >&2
    exit 1
  fi
  install -m 0644 "$snapshot" "$target"
  echo "restored $base_name"
done

for file in "${targets[@]}"; do
  node --check "$file"
done

if [[ "$RESTART_GATEWAY" -eq 1 ]]; then
  systemctl --user restart openclaw-gateway.service
  echo "gateway restarted"
else
  echo "gateway restart skipped"
fi

echo "local-rescue runtime patch restore complete"
