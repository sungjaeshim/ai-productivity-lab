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

make_mock_analyzer() {
  local script
  script=$(mktemp)
  cat >"$script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${MOCK_ANALYZER_JSON:-{}}"
EOF
  chmod +x "$script"
  printf '%s\n' "$script"
}

echo "Running brain-link-ingest regression checks..."

# Case 1: default mode should skip ops entry
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=false BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
  --url "https://example.com/a" \
  --title "A title" \
  --summary "Quick summary" \
  --my-opinion "Worth reading" \
  --dry-run)

stdout=$(extract_stdout "$result")
stderr=$(extract_stderr "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "default mode exits 0" || fail "default mode exits 0"
assert_contains "$stdout" "INFO: Ops entry skipped" "default mode skips ops"
assert_not_contains "$stdout" "Link Processing Entry" "default mode does not render ops payload"
assert_contains "$stdout" "OK: Pipeline complete" "default mode completes pipeline"
assert_not_contains "$stderr" "ERROR" "default mode has no stderr error"

# Case 2: --ops-init should include ops payload
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=false BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
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
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=false BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
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
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=false BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
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

# Case 5: analyzer should use opinion when summary is placeholder
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=true BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
  --url "https://github.com/example/repo/issues/1" \
  --title "Fix urgent OpenClaw routing issue" \
  --summary "Auto-captured from Telegram" \
  --my-opinion "바로 수정 필요한 운영 이슈다" \
  --dry-run)

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "placeholder summary path exits 0" || fail "placeholder summary path exits 0"
assert_not_contains "$stdout" "INCOMPLETE:" "placeholder summary gets analyzer-filled summary"
assert_contains "$stdout" "OK: Pipeline complete" "placeholder summary still completes full pipeline"

# Case 6: analyzer should combine valid summary + opinion and preserve completion
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=true BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" \
  --url "https://github.com/example/repo/pull/2" \
  --title "OpenClaw automation improvement" \
  --summary "openclaw cron routing 개선안" \
  --my-opinion "바로 실행 태스크로 쪼개야 한다" \
  --dry-run)

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "summary+opinion analyzer path exits 0" || fail "summary+opinion analyzer path exits 0"
assert_contains "$stdout" "OK: Pipeline complete" "summary+opinion analyzer path completes pipeline"
assert_not_contains "$stdout" "INCOMPLETE:" "summary+opinion analyzer path stays complete"

# Case 7: analyzer override should control final priority/category/ops fields when path is injected
MOCK_ANALYZER=$(make_mock_analyzer)
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=true BRAIN_OPS_AUTO_INIT=false ANALYZER_SCRIPT="$MOCK_ANALYZER" \
  MOCK_ANALYZER_JSON='{"summary":"Mocked summary","my_opinion":"Mocked opinion","next_action":"Mocked action","priority":"p1","category":"system","should_ops":true,"ops_score":95,"ops_reasons":["priority:p1","intent_hint"],"essence_summary":"Mocked essence","key_points":["K1","K2","K3"],"our_apply":"Mocked apply"}' \
  bash "$SCRIPT" \
  --url "https://example.com/override" \
  --title "Override title" \
  --summary "Original summary" \
  --my-opinion "Original opinion" \
  --ops-init \
  --dry-run)
rm -f "$MOCK_ANALYZER"

stdout=$(extract_stdout "$result")
status=$(extract_exit_code "$result")

[[ "$status" == "0" ]] && pass "analyzer override path exits 0" || fail "analyzer override path exits 0"
assert_contains "$stdout" "**Summary:** Mocked summary" "override replaces summary in final ops message"
assert_contains "$stdout" "**My Opinion:** Mocked opinion" "override replaces opinion in final ops message"
assert_contains "$stdout" "**Next Action:** Mocked action" "override replaces next action in final ops message"
assert_contains "$stdout" "핵심 1줄" "override test still renders analyzer brief block"
assert_contains "$stdout" "Mocked essence" "override replaces essence summary in inbox/brief message"
assert_contains "$stdout" "• K1" "override replaces key point 1 in brief message"
assert_contains "$stdout" "• K2" "override replaces key point 2 in brief message"
assert_contains "$stdout" "Link Processing Entry" "override still reaches ops-entry render path"
assert_contains "$stdout" "**Next Action:** Mocked action" "override reaches final threaded payload with mocked action"
assert_contains "$stdout" "**Summary:** Mocked summary" "override reaches final threaded payload with mocked summary"
assert_contains "$stdout" "**Summary:** Mocked summary" "override persisted summary in output"
assert_contains "$stdout" "Link Processing Entry" "override test still renders ops payload"

# Case 8: URL required must fail hard
result=$(run_capture env BRAIN_INBOX_CHANNEL_ID=123 BRAIN_OPS_CHANNEL_ID=456 BRAIN_INBOX_ANALYZE_AUTO=false BRAIN_OPS_AUTO_INIT=false bash "$SCRIPT" --dry-run)
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
