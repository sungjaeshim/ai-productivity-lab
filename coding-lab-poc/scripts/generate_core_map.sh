#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

INPUT_PATH="${1:-${ROOT_DIR}/core_map_nodes.json}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/core-map}"
LAYOUT="${3:-radial}"
BASENAME="${4:-core-map-${LAYOUT}}"

mkdir -p "${OUTPUT_DIR}"
SVG_OUT="${OUTPUT_DIR}/${BASENAME}.svg"

"${PYTHON_BIN}" "${SCRIPT_DIR}/render_core_map.py" \
  --input "${INPUT_PATH}" \
  --layout "${LAYOUT}" \
  --output "${SVG_OUT}"

if command -v inkscape >/dev/null 2>&1; then
  inkscape "${SVG_OUT}" --export-type=png --export-filename="${OUTPUT_DIR}/${BASENAME}.png" >/dev/null 2>&1 || echo "[WARN] inkscape PNG export skipped"
else
  echo "[WARN] inkscape not found; skipping PNG export"
fi

echo "[OK] ${SVG_OUT}"
