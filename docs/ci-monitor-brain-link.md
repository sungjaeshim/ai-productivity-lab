# GitHub CI Failure Monitor - brain-link-ingest-test

## Overview
Monitors GitHub Actions failures for `sungjaeshim/ai-productivity-lab` workflow `brain-link-ingest-test` using REST API (no gh auth required).

## Script
- **Location:** `/root/.openclaw/workspace/scripts/github-ci-monitor.sh`
- **Cron Schedule:** Every 5 minutes (`*/5 * * * *`)
- **Log File:** `/tmp/monitor-brain-link-ci.log`

## Alert Target
- **Telegram Chat ID:** `62403941`

## Logic
1. Resolve workflow ID by name/path
2. Fetch recent runs (per_page=10)
3. Check MOST RECENT run status:
   - If `success` → Clear failure state, exit quietly
   - If `failure` → Check against last reported failure ID
4. If NEW failure (different run ID) → Send alert
5. Update state file with reported run ID

## State Files
- `/root/.openclaw/workspace/.state/brain-link-ci-last-failure.txt` - Last reported failure run ID
- `/root/.openclaw/workspace/.state/brain-link-ci-last-error.txt` - Last error fingerprint (for deduplication)

## Alert Format
```
🚨 brain-link-ingest-test 실패 감지

Branch: <branch>
Commit: <sha7>
시간: <KST time>
URL: <run url>

로그 확인 후 fix/push하면 다음 성공으로 자동 정상화
```

## Error Handling
- Error deduplication by fingerprint (HTTP_CODE + endpoint + short_error)
- Only alerts on ERROR STATE CHANGES, not on every error
- Workflow ID resolution is robust (checks both path and name)

## Workflow Details
- **Repo:** `sungjaeshim/ai-productivity-lab`
- **Workflow:** `brain-link-ingest-test`
- **Workflow ID:** `240082223` (auto-resolved)

## Cron Entry
```cron
*/5 * * * * /root/.openclaw/workspace/scripts/github-ci-monitor.sh >> /tmp/monitor-brain-link-ci.log 2>&1
```

## Testing
```bash
# Run manually to test
/root/.openclaw/workspace/scripts/github-ci-monitor.sh

# Check recent output
tail -20 /tmp/monitor-brain-link-ci.log

# View state
cat /root/.openclaw/workspace/.state/brain-link-ci-last-failure.txt
```

## Legacy Note

- Old entrypoint `monitor-brain-link-ci.sh` moved to `scripts/_attic/2026-03/`
- Current canonical script is `github-ci-monitor.sh`
