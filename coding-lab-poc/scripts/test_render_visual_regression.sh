#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ASSET_DIR="${ROOT_DIR}/output/assets"

CASES=(
  "lab-profile.yaml"
  "lab-profile.long-korean.yaml"
  "lab-profile.long-english.yaml"
  "lab-profile.mixed-stress.yaml"
)

info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }

render_png() {
  local svg="$1"
  local png="$2"

  if command -v inkscape >/dev/null 2>&1; then
    inkscape "$svg" --export-type=png --export-filename="$png" >/dev/null 2>&1 || fail "PNG export failed via inkscape: $svg"
  elif command -v convert >/dev/null 2>&1; then
    convert -background none "$svg" "$png" >/dev/null 2>&1 || fail "PNG export failed via convert: $svg"
  else
    fail "No SVG->PNG converter found (need inkscape or convert)"
  fi
}

assert_nonempty() {
  local path="$1"
  [[ -s "$path" ]] || fail "Missing or empty artifact: $path"
}

assert_svg_content() {
  local svg="$1"
  grep -q "<svg" "$svg" || fail "Invalid SVG root: $svg"
  grep -q "font-family=" "$svg" || fail "Missing font-family in SVG: $svg"
  grep -q "<rect" "$svg" || fail "Missing rect element in SVG: $svg"
  grep -q "<text" "$svg" || fail "Missing text element in SVG: $svg"
}

mkdir -p "$ASSET_DIR"

count=0
for case_file in "${CASES[@]}"; do
  input_path="${ROOT_DIR}/input/${case_file}"
  [[ -f "$input_path" ]] || fail "Input missing: $input_path"

  base="${case_file%.yaml}"
  svg_out="${ASSET_DIR}/${base}.visual.svg"
  png_out="${ASSET_DIR}/${base}.visual.png"

  info "render: ${case_file}"
  "$PYTHON_BIN" "${SCRIPT_DIR}/render_visual.py" \
    --input "$input_path" \
    --output-dir "$ASSET_DIR" \
    --basename "$base" \
    --force >/dev/null

  assert_nonempty "$svg_out"
  assert_svg_content "$svg_out"

  render_png "$svg_out" "$png_out"
  assert_nonempty "$png_out"

  ok "passed: ${case_file}"
  count=$((count+1))
done

echo
echo "[OK] visual regression suite passed (${count} cases)"
