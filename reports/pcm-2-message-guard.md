# PCM-2: Message Tool Channel/Target Guard Implementation Report

**Date:** 2026-03-05
**Task:** Add channel/target mandatory guards to message sending scripts in /root/.openclaw/workspace
**Status:** ✅ COMPLETED

## Summary

Implemented a common validation utility (`lib/message-guard.sh`) and integrated it into 13 message-sending scripts across the workspace. The guard ensures that `channel` and `target` parameters are validated before any message send attempt, preventing silent failures caused by missing configuration.

## Changes Made

### 1. Created Common Validation Utility

**File:** `/root/.openclaw/workspace/scripts/lib/message-guard.sh`

**Features:**
- `validate_message_params()` function that checks for required `--channel` and `--target` parameters
- Color-coded error messages for better visibility
- Supports dry-run mode relaxation (via `MESSAGE_GUARD_DRY_RUN` environment variable)
- Support for strict mode (via `MESSAGE_GUARD_STRICT` environment variable)
- Exit code 0 for validation passed, exit code 1 for validation failed
- Self-contained: can be sourced or executed directly for testing

**Usage:**
```bash
source "$(dirname "$0")/lib/message-guard.sh"

# Basic validation
validate_message_params --channel "$channel" --target "$target" || exit 1

# With dry-run support
MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel "$channel" --target "$target"
```

### 2. Updated Scripts (13 total)

The following scripts now include channel/target validation guards:

| # | Script | Guard Added To |
|---|--------|---------------|
| 1 | `brain-done-broadcast.sh` | `send_msg()` function |
| 2 | `brain-telegram-autopull.sh` | `send_telegram_ack()` function |
| 3 | `brain-route-retry.sh` | `send_telegram_ack()` function |
| 4 | `brain-weekly-knowledge-report.sh` | `send_msg()` function |
| 5 | `brain-inbox-resend-clean.sh` | `send()` function |
| 6 | `brain-discord-autopull.sh` | `send_discord_ack()` function |
| 7 | `brain-nightly-todo-sync.sh` | Direct send before alert |
| 8 | `brain-queue-autoclean.sh` | Alert and recovery notification sends |
| 9 | `brain-router-health-monitor.sh` | `send_discord()` and `send_telegram()` functions |
| 10 | `brain-tag-route.sh` | Discord send before confirmation |
| 11 | `brain-todo-route.sh` | Discord send after Todoist API |
| 12 | `cloud-firewall-drift-guard.sh` | `send_message()` function |
| 13 | `full-backup.sh` | R2 usage alert and prune alert sends |

**Note:** The following scripts were already compliant (had their own validation):
- `send-briefing.sh` - Checks `TELEGRAM_TARGET` and `DISCORD_TARGET` before sending
- `incident-router.sh` - Checks `TELEGRAM_TARGET` before sending
- `brain-link-ingest.sh` - Checks `channel` and `target` before sending
- `brain-note-ingest.sh` - Checks `channel` and `target` before sending

## Test Results

### Test 1: Guard Library - Missing Channel (FAIL ✅)
```bash
$ validate_message_params --target "12345"
✗ message-guard: missing channel parameter
  Usage: openclaw message send --channel CHANNEL --target TARGET
Exit code: 1
```
**Result:** ✅ Correctly failed with exit code 1

### Test 2: Guard Library - Missing Target (FAIL ✅)
```bash
$ validate_message_params --channel "telegram"
✗ message-guard: missing target parameter for channel 'telegram'
  Usage: openclaw message send --channel telegram --target TARGET
  Environment: Set appropriate *_TARGET or *_CHANNEL_ID variable
Exit code: 1
```
**Result:** ✅ Correctly failed with exit code 1

### Test 3: Guard Library - Valid Parameters (PASS ✅)
```bash
$ validate_message_params --channel "telegram" --target "62403941"
Exit code: 0
```
**Result:** ✅ Correctly passed with exit code 0

### Test 4: Guard Library - Discord Channel (PASS ✅)
```bash
$ validate_message_params --channel "discord" --target "123456789"
Exit code: 0
```
**Result:** ✅ Correctly passed with exit code 0

### Test 5: Script Integration - Dry-Run with Valid Defaults (PASS ✅)
```bash
$ TELEGRAM_TARGET="62403941" DISCORD_REVIEW_CHANNEL_ID="123456" ./brain-done-broadcast.sh --dry-run
[DRY-RUN][discord:1477310567906672750] 🧾 DONE 요약 2026-03-05
...
```
**Result:** ✅ Script executed successfully with valid parameters

### Test 6: Guard Library - Empty String Parameters (FAIL ✅)
```bash
$ validate_message_params --channel "" --target "12345"
✗ message-guard: missing channel parameter
  Usage: openclaw message send --channel CHANNEL --target TARGET
Exit code: 1

$ validate_message_params --channel "telegram" --target ""
✗ message-guard: missing target parameter for channel 'telegram'
  Usage: openclaw message send --channel telegram --target TARGET
  Environment: Set appropriate *_TARGET or *_CHANNEL_ID variable
Exit code: 1
```
**Result:** ✅ Correctly failed for empty string parameters

## Implementation Details

### Guard Behavior

1. **Normal Mode:**
   - Validates both `channel` and `target` before sending
   - Returns exit code 0 if both present and non-empty
   - Returns exit code 1 if either is missing or empty
   - Prints error message to stderr with helpful usage hint

2. **Dry-Run Mode (relaxed):**
   - Skips validation if `MESSAGE_GUARD_DRY_RUN="true"`
   - Allows dry-run scripts to execute without configuration
   - Still validates if `MESSAGE_GUARD_STRICT="true"`

3. **Strict Mode:**
   - Forces validation even in dry-run mode
   - Set via `MESSAGE_GUARD_STRICT="true"`

### Error Messages

**Missing channel:**
```
✗ message-guard: missing channel parameter
  Usage: openclaw message send --channel CHANNEL --target TARGET
```

**Missing target:**
```
✗ message-guard: missing target parameter for channel 'telegram'
  Usage: openclaw message send --channel telegram --target TARGET
  Environment: Set appropriate *_TARGET or *_CHANNEL_ID variable
```

### Pattern Used in Scripts

Most scripts follow this pattern:

```bash
# Source the guard library
source "${SCRIPT_DIR}/lib/message-guard.sh" 2>/dev/null || true

# In send function:
send_msg() {
  local channel="$1"
  local target="$2"
  local message="$3"

  # Validate before sending
  if ! MESSAGE_GUARD_DRY_RUN="$DRY_RUN" validate_message_params --channel "$channel" --target "$target"; then
    echo "[ERROR] message validation failed: channel=$channel, target=$target" >&2
    return 1
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN][$channel:$target] $message"
    return 0
  fi
  openclaw message send --channel "$channel" --target "$target" --message "$message" --silent >/dev/null
}
```

## Compliance Status

### Scripts Updated ✅ (13)
1. brain-done-broadcast.sh
2. brain-telegram-autopull.sh
3. brain-route-retry.sh
4. brain-weekly-knowledge-report.sh
5. brain-inbox-resend-clean.sh
6. brain-discord-autopull.sh
7. brain-nightly-todo-sync.sh
8. brain-queue-autoclean.sh
9. brain-router-health-monitor.sh
10. brain-tag-route.sh
11. brain-todo-route.sh
12. cloud-firewall-drift-guard.sh
13. full-backup.sh

### Scripts Already Compliant ✅ (4)
1. send-briefing.sh
2. incident-router.sh
3. brain-link-ingest.sh
4. brain-note-ingest.sh

### Scripts Not Modified (as per constraints) ⚠️
- Todoist-related scripts (not modified per constraints)
- cron timeout scripts (not modified per constraints)
- telegram command整理 scripts (not modified per constraints)

## Constraints Compliance

✅ **Todoist/cron timeout/텔레그램 명령 정리는 건드리지 말 것** - Complied
✅ **파괴적 명령 금지** - All changes are additive (guards only, no destructive changes)
✅ **누락 방지 코드 반영** - Completed
✅ **누락 입력 테스트(실패) + 정상 입력 테스트(통과) 각 1건** - Completed

## Recommendations

1. **Monitoring:** Consider adding logs to track how often validation fails to identify configuration issues.

2. **Documentation:** Update relevant documentation to mention the required environment variables:
   - `TELEGRAM_TARGET` or `TELEGRAM_CHAT_ID`
   - `DISCORD_*_CHANNEL_ID` (various channel-specific variables)
   - `ALERT_CHANNEL`, `ALERT_TARGET`, etc.

3. **Testing:** Consider adding integration tests that verify scripts fail gracefully with missing configuration.

4. **Future:** Consider extending the guard to validate other `openclaw message` actions (e.g., `read`, `react`, etc.) if needed.

## Completion Checklist

- [x] Created common validation utility (`lib/message-guard.sh`)
- [x] Updated 13 scripts with guards
- [x] Verified existing validation in 4 other scripts
- [x] Tested failure case (missing channel)
- [x] Tested failure case (missing target)
- [x] Tested success case (valid parameters)
- [x] Tested empty string parameters
- [x] Documented results in this report

## Sign-off

**Task:** PCM-2 - Message tool channel/target mandatory guards
**Status:** ✅ COMPLETED
**Date:** 2026-03-05
**Subagent:** pcm-message-channel-guard
