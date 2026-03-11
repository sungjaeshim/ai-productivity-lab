#!/usr/bin/env bash
set -euo pipefail

SRC_WS="/root/.openclaw/workspace"
DST_SITE="/root/workspace/growth-site"
DST_DATA="$DST_SITE/data"

mkdir -p "$DST_DATA/second-brain"
mkdir -p "$DST_DATA/captures/images"

rsync -a "$SRC_WS/memory/second-brain/" "$DST_DATA/second-brain/"
cp -f "$SRC_WS/data/capture-log.jsonl" "$DST_DATA/capture-log.jsonl"
rsync -a "$SRC_WS/data/captures/images/" "$DST_DATA/captures/images/" 2>/dev/null || true

INSIGHTS_COUNT=$(find "$DST_DATA/second-brain/insights" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
CAPTURE_LINES=$(wc -l < "$DST_DATA/capture-log.jsonl" | tr -d ' ')
UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')

cat > "$DST_DATA/second-brain-sync-status.json" <<JSON
{
  "updatedAt": "$UPDATED_AT",
  "insightsCount": $INSIGHTS_COUNT,
  "captureLines": $CAPTURE_LINES,
  "source": "$SRC_WS"
}
JSON

echo "SYNC_OK insights=$INSIGHTS_COUNT captures=$CAPTURE_LINES"
