#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

INPUT_PATH="${1:-${ROOT_DIR}/input/lab-profile.yaml}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/assets}"
BASENAME="${3:-$(basename "${INPUT_PATH}")}"
BASENAME="${BASENAME%.*}"

mkdir -p "${OUTPUT_DIR}"

"${PYTHON_BIN}" "${SCRIPT_DIR}/render_visual.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${OUTPUT_DIR}" \
  --basename "${BASENAME}" \
  --force

SVG_OUT="${OUTPUT_DIR}/${BASENAME}.visual.svg"
if command -v inkscape >/dev/null 2>&1; then
  inkscape "${SVG_OUT}" --export-type=png --export-filename="${OUTPUT_DIR}/${BASENAME}.visual.png" >/dev/null 2>&1 || echo "[WARN] inkscape PNG export skipped"
else
  echo "[WARN] inkscape not found; skipping PNG export"
fi

echo "[OK] ${SVG_OUT}"
