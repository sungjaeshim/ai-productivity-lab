#!/usr/bin/env bash
set -euo pipefail

set +u
source "$(dirname "$0")/env-loader.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/message-guard.sh" 2>/dev/null || true
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENDER_SCRIPT="${SCRIPT_DIR}/visual-render.sh"
PUBLISH_SCRIPT="${SCRIPT_DIR}/visual-notion-publish.py"
DEFAULT_OUT_DIR="${WORKSPACE_DIR}/out"
DEFAULT_REVIEW_TARGET="${VISUAL_REVIEW_TELEGRAM_TARGET:-${TELEGRAM_TARGET:-${TELEGRAM_CHAT_ID:-}}}"
DEFAULT_REVIEW_THREAD_ID="${VISUAL_REVIEW_TELEGRAM_THREAD_ID:-}"

usage() {
  cat <<'USAGE'
Usage:
  visual-flow.sh render <file.mmd> [--out-dir DIR]
  visual-flow.sh publish <file.mmd> <meta.json> [--database DB] [--out-dir DIR]
  visual-flow.sh all <file.mmd> <meta.json> [--database DB] [--out-dir DIR] [--send-review] [--target ID] [--thread-id ID] [--message TEXT] [--dry-run]
  visual-flow.sh review <file.mmd> [--out-dir DIR]
  visual-flow.sh review-send <file.mmd> [--out-dir DIR] [--meta FILE] [--target ID] [--thread-id ID] [--message TEXT] [--dry-run]
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

review_visual() {
  local file="$1"
  local out_dir="$2"
  local base_name
  local missing=0

  [[ -f "${file}" ]] || die "Mermaid file not found: ${file}"
  base_name="$(basename "${file}")"
  base_name="${base_name%.*}"

  printf 'Source: %s\n' "$(realpath "${file}")"
  printf 'Output directory: %s\n' "$(realpath "${out_dir}")"
  printf 'Lines: %s\n' "$(wc -l < "${file}")"

  for ext in png pdf svg; do
    local artifact="${out_dir}/${base_name}.${ext}"
    if [[ -f "${artifact}" ]]; then
      printf '%s: OK (%s bytes) %s\n' "${ext^^}" "$(stat -c '%s' "${artifact}")" "$(realpath "${artifact}")"
    else
      printf '%s: MISSING %s\n' "${ext^^}" "${artifact}"
      missing=1
    fi
  done

  return "${missing}"
}

send_review_to_telegram() {
  local file="$1"
  local out_dir="$2"
  local meta_file="$3"
  local target="$4"
  local thread_id="$5"
  local message="$6"
  local dry_run="$7"
  local png_path
  local base_name
  local -a cmd

  [[ -f "${file}" ]] || die "Mermaid file not found: ${file}"
  base_name="$(basename "${file}")"
  base_name="${base_name%.*}"
  png_path="${out_dir}/${base_name}.png"

  [[ -f "${png_path}" ]] || die "PNG review artifact missing: ${png_path}. Run render first."
  validate_message_params --channel telegram --target "${target}" || die "Telegram target is required for review-send"

  if [[ -z "${message}" ]]; then
    if [[ -n "${meta_file}" ]]; then
      [[ -f "${meta_file}" ]] || die "Meta file not found: ${meta_file}"
      message="$(python3 - <<'PY' "${meta_file}" "${base_name}" "${png_path}"
import json
import sys
from pathlib import Path

meta_path = Path(sys.argv[1])
base_name = sys.argv[2]
png_path = sys.argv[3]

try:
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"ERROR: failed to read meta file: {exc}", file=sys.stderr)
    raise SystemExit(2)

title = str(meta.get("title") or base_name).strip()
subtitle = str(meta.get("subtitle") or "").strip()
purpose = str(meta.get("purpose") or "").strip()
questions = meta.get("questions") or []
if not isinstance(questions, list):
    questions = []
questions = [str(item).strip() for item in questions if str(item).strip()]

lines = [f"Visualization review: {title}"]
if subtitle:
    lines.append(subtitle)
if purpose:
    lines.append(f"Purpose: {purpose}")
lines.append(f"Artifact: {base_name}.png")
if questions:
    lines.append(f"Check: {questions[0]}")
lines.append("Reply with readability or structure fixes.")

message = "\n".join(lines)
if len(message) > 900:
    message = message[:897].rstrip() + "..."
print(message)
PY
)"
    else
      message=$'Visualization review\n'"- File: ${base_name}.mmd"$'\n'"- Artifact: ${png_path}"
    fi
  fi

  cmd=(
    openclaw message send
    --channel telegram
    --target "${target}"
    --message "${message}"
    --media "${png_path}"
  )

  if [[ -n "${thread_id}" ]]; then
    cmd+=(--thread-id "${thread_id}")
  fi

  if [[ "${dry_run}" == "true" ]]; then
    cmd+=(--dry-run)
  fi

  if ! "${cmd[@]}"; then
    echo "ERROR: telegram review send failed" >&2
    exit 40
  fi
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 1
}

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
esac

SUBCOMMAND="$1"
shift

OUT_DIR="${DEFAULT_OUT_DIR}"
DATABASE_ID=""
REVIEW_META_FILE=""
REVIEW_TARGET="${DEFAULT_REVIEW_TARGET}"
REVIEW_THREAD_ID="${DEFAULT_REVIEW_THREAD_ID}"
REVIEW_MESSAGE=""
DRY_RUN=false
SEND_REVIEW=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --database)
      [[ $# -ge 2 ]] || die "--database requires a value"
      DATABASE_ID="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      REVIEW_TARGET="$2"
      shift 2
      ;;
    --meta)
      [[ $# -ge 2 ]] || die "--meta requires a value"
      REVIEW_META_FILE="$2"
      shift 2
      ;;
    --thread-id)
      [[ $# -ge 2 ]] || die "--thread-id requires a value"
      REVIEW_THREAD_ID="$2"
      shift 2
      ;;
    --message)
      [[ $# -ge 2 ]] || die "--message requires a value"
      REVIEW_MESSAGE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --send-review)
      SEND_REVIEW=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

case "${SUBCOMMAND}" in
  render)
    [[ ${#POSITIONAL[@]} -eq 1 ]] || die "render requires <file.mmd>"
    "${RENDER_SCRIPT}" "${POSITIONAL[0]}" --out-dir "${OUT_DIR}"
    ;;
  publish)
    [[ ${#POSITIONAL[@]} -eq 2 ]] || die "publish requires <file.mmd> <meta.json>"
    cmd=(python3 "${PUBLISH_SCRIPT}" "${POSITIONAL[0]}" "${POSITIONAL[1]}" --out-dir "${OUT_DIR}")
    if [[ -n "${DATABASE_ID}" ]]; then
      cmd+=(--database "${DATABASE_ID}")
    fi
    "${cmd[@]}"
    ;;
  all)
    [[ ${#POSITIONAL[@]} -eq 2 ]] || die "all requires <file.mmd> <meta.json>"
    if ! "${RENDER_SCRIPT}" "${POSITIONAL[0]}" --out-dir "${OUT_DIR}"; then
      echo "ERROR: render step failed" >&2
      exit 10
    fi
    cmd=(python3 "${PUBLISH_SCRIPT}" "${POSITIONAL[0]}" "${POSITIONAL[1]}" --out-dir "${OUT_DIR}")
    if [[ -n "${DATABASE_ID}" ]]; then
      cmd+=(--database "${DATABASE_ID}")
    fi
    if ! "${cmd[@]}"; then
      echo "ERROR: publish step failed" >&2
      exit 20
    fi
    if [[ "${SEND_REVIEW}" == "true" ]]; then
      send_review_to_telegram "${POSITIONAL[0]}" "${OUT_DIR}" "${POSITIONAL[1]}" "${REVIEW_TARGET}" "${REVIEW_THREAD_ID}" "${REVIEW_MESSAGE}" "${DRY_RUN}"
    fi
    ;;
  review)
    [[ ${#POSITIONAL[@]} -eq 1 ]] || die "review requires <file.mmd>"
    if ! review_visual "${POSITIONAL[0]}" "${OUT_DIR}"; then
      echo "ERROR: review found missing artifacts" >&2
      exit 30
    fi
    ;;
  review-send)
    [[ ${#POSITIONAL[@]} -eq 1 ]] || die "review-send requires <file.mmd>"
    send_review_to_telegram "${POSITIONAL[0]}" "${OUT_DIR}" "${REVIEW_META_FILE}" "${REVIEW_TARGET}" "${REVIEW_THREAD_ID}" "${REVIEW_MESSAGE}" "${DRY_RUN}"
    ;;
  *)
    usage >&2
    die "Unknown subcommand: ${SUBCOMMAND}"
    ;;
esac
