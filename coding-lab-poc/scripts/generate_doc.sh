#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

INPUT_PATH="${1:-${ROOT_DIR}/input/lab-profile.yaml}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/docs}"
TMP_DIR="${3:-${ROOT_DIR}/tmp}"
BASENAME="${4:-$(basename "${INPUT_PATH}")}"
BASENAME="${BASENAME%.*}"

mkdir -p "${OUTPUT_DIR}" "${TMP_DIR}"

"${PYTHON_BIN}" "${SCRIPT_DIR}/render_doc.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${OUTPUT_DIR}" \
  --tmp-dir "${TMP_DIR}" \
  --basename "${BASENAME}" \
  --force

HTML_OUT="${TMP_DIR}/${BASENAME}.report.html"
if command -v soffice >/dev/null 2>&1; then
  soffice --headless --convert-to pdf "${HTML_OUT}" --outdir "${OUTPUT_DIR}" >/dev/null 2>&1 || echo "[WARN] soffice PDF export skipped"
else
  echo "[WARN] soffice not found; skipping PDF export"
fi

echo "[OK] ${OUTPUT_DIR}/${BASENAME}.report.md"
