#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

INPUT_PATH="${1:-${ROOT_DIR}/input/lab-profile.yaml}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output}"
BASENAME="${3:-$(basename "${INPUT_PATH}")}" 
BASENAME="${BASENAME%.*}"

DOC_DIR="${OUTPUT_DIR}/docs"
VISUAL_DIR="${OUTPUT_DIR}/assets"
DIAGRAM_DIR="${OUTPUT_DIR}/diagram"
TMP_DIR="${ROOT_DIR}/tmp"

ok=0
warn=0
fail=0

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; warn=$((warn+1)); }
log_fail() { echo "[ERROR] $*" >&2; fail=$((fail+1)); }

run_python_step() {
  local name="$1"
  shift
  log_info "${name}"
  if "${PYTHON_BIN}" "$@"; then
    log_ok "${name}"
    ok=$((ok+1))
  else
    log_fail "${name}"
    exit 1
  fi
}

check_file() {
  local path="$1"
  if [[ -s "$path" ]]; then
    log_ok "artifact: $path"
  else
    log_fail "missing artifact: $path"
    exit 1
  fi
}

if [[ ! -f "${INPUT_PATH}" ]]; then
  log_fail "input file not found: ${INPUT_PATH}"
  exit 1
fi

mkdir -p "${DOC_DIR}" "${VISUAL_DIR}" "${DIAGRAM_DIR}" "${TMP_DIR}"

log_info "input      : ${INPUT_PATH}"
log_info "output dir : ${OUTPUT_DIR}"
log_info "basename   : ${BASENAME}"

run_python_step "document generation" \
  "${SCRIPT_DIR}/render_doc.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${DOC_DIR}" \
  --tmp-dir "${TMP_DIR}" \
  --basename "${BASENAME}" \
  --force

run_python_step "visual generation" \
  "${SCRIPT_DIR}/render_visual.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${VISUAL_DIR}" \
  --basename "${BASENAME}" \
  --force

run_python_step "diagram generation" \
  "${SCRIPT_DIR}/render_diagram.py" \
  --input "${INPUT_PATH}" \
  --output-dir "${DIAGRAM_DIR}" \
  --basename "${BASENAME}" \
  --force

DOC_MD="${DOC_DIR}/${BASENAME}.report.md"
DOC_HTML="${TMP_DIR}/${BASENAME}.report.html"
VISUAL_SVG="${VISUAL_DIR}/${BASENAME}.visual.svg"
DIAGRAM_SRC="${DIAGRAM_DIR}/${BASENAME}.diagram.drawio"

check_file "${DOC_MD}"
check_file "${DOC_HTML}"
check_file "${VISUAL_SVG}"
check_file "${DIAGRAM_SRC}"

if command -v soffice >/dev/null 2>&1; then
  PDF_OUT="${DOC_DIR}/${BASENAME}.report.pdf"
  if soffice --headless --convert-to pdf "${DOC_HTML}" --outdir "${DOC_DIR}" >/dev/null 2>&1; then
    GENERATED_PDF="${DOC_DIR}/${BASENAME}.report.pdf"
    if [[ -s "${GENERATED_PDF}" ]]; then
      log_ok "pdf export: ${GENERATED_PDF}"
    else
      ALT_PDF="${DOC_DIR}/$(basename "${DOC_HTML%.html}").pdf"
      if [[ -s "${ALT_PDF}" ]]; then
        log_ok "pdf export: ${ALT_PDF}"
      else
        log_warn "soffice ran but PDF output missing"
      fi
    fi
  else
    log_warn "soffice PDF export skipped"
  fi
else
  log_warn "soffice not found; skipping PDF export"
fi

if command -v inkscape >/dev/null 2>&1; then
  VISUAL_PNG="${VISUAL_DIR}/${BASENAME}.visual.png"
  if inkscape "${VISUAL_SVG}" --export-type=png --export-filename="${VISUAL_PNG}" >/dev/null 2>&1; then
    if [[ -s "${VISUAL_PNG}" ]]; then
      log_ok "visual png export: ${VISUAL_PNG}"
    else
      log_warn "inkscape ran but PNG output missing"
    fi
  else
    log_warn "inkscape PNG export skipped"
  fi
else
  log_warn "inkscape not found; skipping PNG export"
fi

if command -v drawio >/dev/null 2>&1; then
  DIAGRAM_PNG="${DIAGRAM_DIR}/${BASENAME}.diagram.png"
  if drawio --export --format png --output "${DIAGRAM_PNG}" "${DIAGRAM_SRC}" >/dev/null 2>&1; then
    if [[ -s "${DIAGRAM_PNG}" ]]; then
      log_ok "diagram png export: ${DIAGRAM_PNG}"
    else
      log_warn "drawio ran but PNG output missing"
    fi
  else
    log_warn "drawio export skipped"
  fi
else
  log_warn "drawio not found; keeping source only"
fi

printf '\n==> status\n'
echo "  steps_ok:   ${ok}"
echo "  steps_fail: ${fail}"
echo "  warnings:   ${warn}"
