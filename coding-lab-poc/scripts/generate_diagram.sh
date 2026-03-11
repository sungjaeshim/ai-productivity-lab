#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

INPUT_PATH="${1:-${ROOT_DIR}/input/lab-profile.yaml}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/diagram}"
BASENAME="${3:-$(basename "${INPUT_PATH}")}"
BASENAME="${BASENAME%.*}"

mkdir -p "${OUTPUT_DIR}"

"${PYTHON_BIN}" "${SCRIPT_DIR}/render_diagram.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${OUTPUT_DIR}" \
  --basename "${BASENAME}" \
  --force

DRAWIO_OUT="${OUTPUT_DIR}/${BASENAME}.diagram.drawio"
if command -v drawio >/dev/null 2>&1; then
  drawio --export --format png --output "${OUTPUT_DIR}/${BASENAME}.diagram.png" "${DRAWIO_OUT}" >/dev/null 2>&1 || echo "[WARN] drawio export skipped"
else
  echo "[WARN] drawio not found; keeping source only"
fi

echo "[OK] ${DRAWIO_OUT}"
