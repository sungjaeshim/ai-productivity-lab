#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT="${SCRIPT:-${REPO_ROOT}/scripts/brain-link-ingest.sh}"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "✅ $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "❌ $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    pass "$msg"
  else
    fail "$msg"
    echo "   ↳ expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    fail "$msg"
    echo "   ↳ expected NOT to contain: $needle"
  else
    pass "$msg"
  fi
}

run_capture() {
  local out_file err_file
  out_file=$(mktemp)
  err_file=$(mktemp)

  set +e
  "$@" >"$out_file" 2>"$err_file"
  local status=$?
  set -e

  local stdout stderr
  stdout=$(cat "$out_file")
  stderr=$(cat "$err_file")
  rm -f "$out_file" "$err_file"

  printf '%s\n__EXIT_CODE__=%s\n__STDERR__\n%s\n' "$stdout" "$status" "$stderr"
}

extract_exit_code() {
  sed -n 's/^__EXIT_CODE__=//p' <<<"$1" | head -n1
}

extract_stdout() {
  sed '/^__EXIT_CODE__=/,$d' <<<"$1"
}

extract_stderr() {
  sed -n '/^__STDERR__$/,$p' <<<"$1" | tail -n +2
}

echo "Running brain-link-ingest regression checks..."

# Case 1: default mode should skip ops entry
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 bash "$SCRIPT" \
  --url "https://example.com/a" \
  --title "A title" \
  --summary "Quick summary" \
  --my-opinion "Worth reading" \
  --dry-run)

stdout=$(extract_stdout "$result")
stderr=$(extract_stderr "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "default mode exits 0" || fail "default mode exits 0"
assert_contains "$stdout" "INFO: Ops entry skipped (use --ops-init when deep work starts)" "default mode skips ops"
assert_not_contains "$stdout" "Link Processing Entry" "default mode does not render ops payload"
assert_contains "$stdout" "OK: Pipeline complete" "default mode completes pipeline"
assert_not_contains "$stderr" "ERROR" "default mode has no stderr error"

# Case 2: --ops-init should include ops payload
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 bash "$SCRIPT" \
  --url "https://example.com/b" \
  --title "B title" \
  --summary "Another summary" \
  --my-opinion "Deep dive needed" \
  --ops-init \
  --dry-run)

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "ops-init mode exits 0" || fail "ops-init mode exits 0"
assert_contains "$stdout" "Link Processing Entry" "ops-init renders ops payload"
assert_not_contains "$stdout" "INFO: Ops entry skipped" "ops-init does not show skip notice"

# Case 3: missing required field should queue (without --force)
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 bash "$SCRIPT" \
  --url "https://example.com/c" \
  --title "C title" \
  --my-opinion "Missing summary on purpose" \
  --dry-run)

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "incomplete entry exits 0 after queue" || fail "incomplete entry exits 0 after queue"
assert_contains "$stdout" "INCOMPLETE: Missing fields: summary" "incomplete entry reports missing field"
assert_contains "$stdout" "[DRY-RUN] Would queue:" "incomplete entry goes to queue"
assert_contains "$stdout" "ACTION: Run with --force or provide missing fields to complete" "incomplete entry prints next action"

# Case 4: --force should bypass 4-field gate
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 bash "$SCRIPT" \
  --url "https://example.com/d" \
  --title "D title" \
  --my-opinion "Force path" \
  --force \
  --dry-run)

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "force mode exits 0" || fail "force mode exits 0"
assert_not_contains "$stdout" "INCOMPLETE:" "force mode bypasses incomplete warning"
assert_contains "$stdout" "OK: Pipeline complete" "force mode still completes pipeline"

# Case 5: URL required must fail hard
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 bash "$SCRIPT" --dry-run)
stdout=$(extract_stdout "$result")
stderr=$(extract_stderr "$result")
status=$(extract_exit_code "$result")

[[ "$status" != "0" ]] && pass "missing URL exits non-zero" || fail "missing URL exits non-zero"
assert_contains "$stderr" "ERROR: --url required" "missing URL prints explicit error"
assert_not_contains "$stdout" "Pipeline complete" "missing URL does not continue"

echo
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
