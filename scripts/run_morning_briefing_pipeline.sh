#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/.openclaw/workspace"
SCRIPT_DIR="$ROOT/scripts"
MORNING_SKILL_DIR="$ROOT/skills/morning-briefing"
DATE_KST="$(TZ=Asia/Seoul date +%Y-%m-%d)"
PAYLOAD_FILE="$ROOT/data/morning-briefing-payload-${DATE_KST}.json"
BODY_FILE="$ROOT/data/morning-briefing-body-${DATE_KST}.txt"
SEND_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --send)
      SEND_MODE="true"
      shift
      ;;
    *)
      echo "MORNING_BRIEFING_PIPELINE_ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

bash "$MORNING_SKILL_DIR/morning-data-collector.sh"
bash "$SCRIPT_DIR/run_daily_intelligence_pipeline.sh"
python3 "$SCRIPT_DIR/build_morning_briefing_payload.py" --date "$DATE_KST"

if [[ ! -f "$PAYLOAD_FILE" ]]; then
  echo "MORNING_BRIEFING_PIPELINE_ERROR: missing payload file: $PAYLOAD_FILE" >&2
  exit 1
fi

if [[ ! -f "$BODY_FILE" ]]; then
  echo "MORNING_BRIEFING_PIPELINE_ERROR: missing body file: $BODY_FILE" >&2
  exit 1
fi

if [[ "$SEND_MODE" == "true" ]]; then
  bash "$SCRIPT_DIR/send-briefing.sh" --message-file "$BODY_FILE"
fi

echo "MORNING_BRIEFING_PIPELINE_OK payload=$PAYLOAD_FILE body=$BODY_FILE sent=$SEND_MODE"
