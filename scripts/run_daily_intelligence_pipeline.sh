#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/.openclaw/workspace"
SCRIPT_DIR="$ROOT/scripts"
DATE_KST="$(TZ=Asia/Seoul date +%Y-%m-%d)"
SOURCE_FILE="$ROOT/data/intelligence-${DATE_KST}.json"
PAYLOAD_FILE="$ROOT/data/daily-intelligence-payload-${DATE_KST}.json"

timeout 90 bash "$SCRIPT_DIR/daily-intelligence-collector.sh"
python3 "$SCRIPT_DIR/build_daily_intelligence_payload.py" --date "$DATE_KST"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "DAILY_INTEL_PIPELINE_ERROR: missing source file: $SOURCE_FILE" >&2
  exit 1
fi

if [[ ! -f "$PAYLOAD_FILE" ]]; then
  echo "DAILY_INTEL_PIPELINE_ERROR: missing payload file: $PAYLOAD_FILE" >&2
  exit 1
fi

echo "DAILY_INTEL_PIPELINE_OK source=$SOURCE_FILE payload=$PAYLOAD_FILE"
