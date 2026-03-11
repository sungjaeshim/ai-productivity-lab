#!/usr/bin/env bash
set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_OUT_DIR="${WORKSPACE_DIR}/out"
DEFAULT_PUPPETEER_CONFIG="${MERMAID_PUPPETEER_CONFIG:-${WORKSPACE_DIR}/puppeteer-mermaid.json}"

TMP_PUPPETEER_CONFIG=""

usage() {
  cat <<'USAGE'
Usage:
  visual-render.sh <file.mmd> [--out-dir DIR]
  visual-render.sh --help

Renders Mermaid input to PNG, PDF, and SVG in the output directory.

Environment:
  MMDC_BIN                  Override Mermaid CLI binary path
  MERMAID_PUPPETEER_CONFIG  Override Puppeteer config path
USAGE
}

cleanup() {
  if [[ -n "${TMP_PUPPETEER_CONFIG}" && -f "${TMP_PUPPETEER_CONFIG}" ]]; then
    rm -f "${TMP_PUPPETEER_CONFIG}"
  fi
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

find_mmdc() {
  local candidate

  if [[ -n "${MMDC_BIN:-}" ]]; then
    [[ -x "${MMDC_BIN}" ]] || die "MMDC_BIN is not executable: ${MMDC_BIN}"
    printf '%s\n' "${MMDC_BIN}"
    return 0
  fi

  candidate="$(command -v mmdc 2>/dev/null || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  candidate="${WORKSPACE_DIR}/node_modules/.bin/mmdc"
  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  candidate="$(find "${HOME}/.npm/_npx" -path '*/node_modules/.bin/mmdc' 2>/dev/null | head -n 1 || true)"
  if [[ -n "${candidate}" && -e "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  die "Mermaid CLI not found. Set MMDC_BIN or install mmdc."
}

ensure_puppeteer_config() {
  if [[ -f "${DEFAULT_PUPPETEER_CONFIG}" ]]; then
    printf '%s\n' "${DEFAULT_PUPPETEER_CONFIG}"
    return 0
  fi

  if [[ "$(id -u)" == "0" ]]; then
    TMP_PUPPETEER_CONFIG="$(mktemp)"
    cat > "${TMP_PUPPETEER_CONFIG}" <<'JSON'
{
  "args": ["--no-sandbox", "--disable-setuid-sandbox"]
}
JSON
    printf '%s\n' "${TMP_PUPPETEER_CONFIG}"
    return 0
  fi

  printf '%s\n' ""
}

run_render() {
  local format="$1"
  local output_path="$2"
  local output
  local -a cmd=("${MMDC}" -i "${INPUT_FILE}" -o "${output_path}")

  if [[ -n "${PUPPETEER_CONFIG}" ]]; then
    cmd+=(-p "${PUPPETEER_CONFIG}")
  fi

  if ! output="$("${cmd[@]}" 2>&1)"; then
    if [[ -n "${output}" ]]; then
      echo "${output}" >&2
    fi
    die "Mermaid render failed for ${format}: ${INPUT_FILE}"
  fi
}

INPUT_FILE=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "${INPUT_FILE}" ]]; then
        INPUT_FILE="$1"
        shift
      else
        die "Unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -n "${INPUT_FILE}" ]] || {
  usage >&2
  exit 1
}

trap cleanup EXIT

INPUT_FILE="$(realpath "${INPUT_FILE}")"
[[ -f "${INPUT_FILE}" ]] || die "Input file not found: ${INPUT_FILE}"

OUT_DIR="${OUT_DIR:-${DEFAULT_OUT_DIR}}"
mkdir -p "${OUT_DIR}"
OUT_DIR="$(realpath "${OUT_DIR}")"

MMDC="$(find_mmdc)"
PUPPETEER_CONFIG="$(ensure_puppeteer_config)"
BASE_NAME="$(basename "${INPUT_FILE}")"
BASE_NAME="${BASE_NAME%.*}"

PNG_OUT="${OUT_DIR}/${BASE_NAME}.png"
PDF_OUT="${OUT_DIR}/${BASE_NAME}.pdf"
SVG_OUT="${OUT_DIR}/${BASE_NAME}.svg"

run_render "png" "${PNG_OUT}"
run_render "pdf" "${PDF_OUT}"
run_render "svg" "${SVG_OUT}"

printf 'PNG: %s\n' "${PNG_OUT}"
printf 'PDF: %s\n' "${PDF_OUT}"
printf 'SVG: %s\n' "${SVG_OUT}"
