# Brain Pipeline - Telegram → Discord → Second-Brain

Auto-pipeline for processing Telegram links into brain-inbox and second-brain. Ops threads are opt-in when deep work starts.

## Overview

```
Telegram Link → brain-link-ingest.sh → Discord (brain-inbox only) + second-brain/links.md
                         ↓
              brain-thread-manage.sh --init (when deep work starts)
                         ↓
              Thread-based status updates in brain-ops (TODO/DOING/DONE/BLOCKED)
                         ↓
              brain-daily-done-summary.sh → Daily summary → memory/YYYY-MM-DD.md
```

## Critical Rules (READ FIRST)

### 1. 4-Field Requirement
Every brain entry MUST have all 4 fields before auto-send:
- **URL** (required)
- **Title** (required)
- **Summary** (required)
- **My Opinion** (required)

Missing fields → Entry is queued for manual review, NOT auto-sent.

**Bypass:** Use `--force` to send incomplete entries.

### 2. Thread-Based Ops Model
brain-ops is created only when you actually start developing a specific inbox item:
- **Main channel (inbox):** one link = one message
- **Ops thread:** created on-demand via `brain-thread-manage.sh --init`
- **Thread replies:** all status updates (TODO → DOING → DONE/BLOCKED)
- **Why:** inbox stays clean, ops keeps only active deep-work traces

### 3. Initial Flood Prevention
First run with `--init-now` to set checkpoint to current time:
```bash
./scripts/brain-telegram-autopull.sh --init-now
```

**Safety guard:** Max 50 URLs per run (prevents historical flood).

### 4. System URL Filtering
These URL patterns are automatically filtered from auto-capture:
- `scanner.tradingview.com` (TradingView scanner)
- `example.com`, `example.org` (documentation examples)
- `discord.com/api/webhooks` (Discord webhooks)
- `sentry.io/api`, `ingest.sentry.io` (Sentry ingestion)
- `localhost`, `127.0.0.1`, `0.0.0.0` (local addresses)
- `*.internal.*`, `*.local` (internal domains)
- `ngrok.io` (tunnel endpoints)
- `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com` (API endpoints)

## Prerequisites

### Environment Variables

Set in `.env` or export before running:

```bash
export BRAIN_INBOX_CHANNEL_ID="1234567890123456789"  # Discord brain-inbox channel
export BRAIN_OPS_CHANNEL_ID="1234567890123456789"    # Discord brain-ops channel
```

### Discord Setup

1. Create `brain-inbox` channel - for incoming link notifications
2. Create `brain-ops` channel - for processing messages (thread-based)
3. Get channel IDs: Right-click channel → Copy ID (Developer Mode required)

## Scripts

### 1. brain-link-ingest.sh

Process incoming links with 4-field validation and fallback handling.

```bash
# Complete entry (all 4 fields)
./scripts/brain-link-ingest.sh \
  --url "https://example.com/article" \
  --title "Article Title" \
  --summary "Brief description of the content" \
  --my-opinion "Why this matters to me"

# Incomplete entry (will be queued for manual review)
./scripts/brain-link-ingest.sh \
  --url "https://example.com/article" \
  --title "Article Title"
# Output: INCOMPLETE: Missing fields: summary my-opinion

# Force send incomplete entry
./scripts/brain-link-ingest.sh \
  --url "https://example.com/article" \
  --title "Article Title" \
  --force

# Dry run (no actual send)
./scripts/brain-link-ingest.sh \
  --url "https://example.com" \
  --title "Test" \
  --summary "Test summary" \
  --my-opinion "Test opinion" \
  --dry-run
```

**What it does:**
1. **4-Field validation:** Checks URL, TITLE, SUMMARY, MY_OPINION
2. **Dedup check:** SHA256 hash of canonical URL → `.url-registry.jsonl`
3. **Junk filter:** Removes ad/tracking links automatically
4. **Discord send:** brain-inbox notification + brain-ops message (with My Opinion)
5. **Local write:** Prepends to `memory/second-brain/links.md` (includes My Opinion)
6. **Queue for retry:** If Discord fails or incomplete, writes to `.pending-queue.jsonl`

**Output format in links.md:**
```markdown
## [2026-03-01 10:00:00] example.com
- URL: https://example.com/article
- Canonical: https://example.com/article
- Hash: a1b2c3d4e5f6g7h8
- Status: TODO
- Added: 2026-03-01
- Summary: Brief description of the content
- My Opinion: Why this matters to me
```

### 2. brain-thread-manage.sh

Thread-based status management.

```bash
# Create new thread entry
./scripts/brain-thread-manage.sh \
  --init \
  --title "Article Title" \
  --url "https://example.com/article"

# Update status in thread
./scripts/brain-thread-manage.sh \
  --status DOING \
  --thread-id "brain-a1b2c3d4e5f6g7h8" \
  --url "https://example.com/article"

# With note
./scripts/brain-thread-manage.sh \
  --status DONE \
  --thread-id "brain-a1b2c3d4e5f6g7h8" \
  --url "https://example.com/article" \
  --note "Processed and filed"

# Dry run
./scripts/brain-thread-manage.sh \
  --status BLOCKED \
  --thread-id "brain-a1b2c3d4e5f6g7h8" \
  --dry-run
```

**Valid statuses:**
| Status  | Emoji | Meaning                    |
|---------|-------|----------------------------|
| TODO    | 📋    | Queued for processing      |
| DOING   | 🔄    | Currently being processed  |
| DONE    | ✅    | Completed                  |
| BLOCKED | 🚫    | Blocked, needs attention   |

### 3. brain-telegram-autopull.sh

Auto-capture URLs from Telegram sessions.

```bash
# First-time setup (set checkpoint to NOW)
./scripts/brain-telegram-autopull.sh --init-now

# Normal run
./scripts/brain-telegram-autopull.sh

# Dry run (see what would be captured)
./scripts/brain-telegram-autopull.sh --dry-run

# Combined
./scripts/brain-telegram-autopull.sh --init-now --dry-run
```

**Dry-run output (per-URL format):**
```
brain-autopull: found 3 new url(s) since 2026-03-01T10:00:00Z
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[DRY-RUN] Entry #1 of 3
  URL:    https://example.com/article1
  Title:  example.com
  Time:   2026-03-01T10:05:00Z
  Action: Would call brain-link-ingest.sh
          (will be INCOMPLETE - missing summary/my-opinion)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[DRY-RUN] Entry #2 of 3
  ...
```

**Safety features:**
- Max 50 URLs per run (prevents historical flood)
- System URL filtering (see Critical Rules #4)
- Clear per-URL dry-run output

### 4. brain-daily-done-summary.sh

Generate 3-line DONE summary for today.

```bash
# Today's summary
./scripts/brain-daily-done-summary.sh

# Specific date
./scripts/brain-daily-done-summary.sh --date 2026-03-01

# Dry run (stdout only)
./scripts/brain-daily-done-summary.sh --dry-run
```

**Output format:**
```markdown
# 📋 Daily DONE Summary: 2026-03-01

**✅ Completed:** 3 item(s)

### Top Items:
- Article Title 1
- Article Title 2
- Article Title 3
```

## Cross-Context Constraints & Workarounds

### Discord Thread API Limitations

**Issue:** Discord's thread creation API may be unavailable or rate-limited in certain contexts.

**Workaround:** Thread-based message tracking
- Main channel: Only initial entry (thread parent)
- Thread replies: All status updates (keeps channel clean)
- Thread ID stored in `.thread-registry.jsonl` for local tracking
- Status maintained in local `links.md` (source of truth)

**Fallback chain:**
1. Try Discord thread reply
2. On failure → post to main channel with thread reference
3. On complete failure → write to `.pending-queue.jsonl`

### CLI Bypass for Cross-Context

When Discord API is unavailable:
1. Scripts write locally first (links.md always succeeds)
2. Queue entries for async sync
3. Manual retry via cron or on-demand

## Rollback Procedures

### 1. Undo last link entry

```bash
# Restore from backup
cp /root/.openclaw/workspace/memory/second-brain/links.md.bak \
   /root/.openclaw/workspace/memory/second-brain/links.md

# Remove from URL registry (get hash from links.md first)
HASH="a1b2c3d4e5f6g7h8"
grep -v "\"hash\":\"$HASH\"" .url-registry.jsonl > .url-registry.jsonl.tmp
mv .url-registry.jsonl.tmp .url-registry.jsonl

# Also remove from thread registry if exists
grep -v "\"thread_id\":\"brain-$HASH\"" .thread-registry.jsonl > .thread-registry.jsonl.tmp
mv .thread-registry.jsonl.tmp .thread-registry.jsonl
```

### 2. Reset checkpoint (for autopull)

```bash
# Set checkpoint to NOW (skip all historical)
./scripts/brain-telegram-autopull.sh --init-now

# Or manually set to specific time
echo '{"last_ts":"2026-03-01T12:00:00Z","updated_at":"2026-03-01T12:00:00Z"}' \
  > /root/.openclaw/workspace/memory/second-brain/.brain-autopull-checkpoint.json
```

### 3. Clear pending queue

```bash
# View pending
cat /root/.openclaw/workspace/memory/second-brain/.pending-queue.jsonl

# Process pending entries (add missing fields manually)
while read -r entry; do
  URL=$(echo "$entry" | jq -r '.url')
  echo "Process: $URL"
  # Manually run with complete fields
done < /root/.openclaw/workspace/memory/second-brain/.pending-queue.jsonl

# Clear all pending
> /root/.openclaw/workspace/memory/second-brain/.pending-queue.jsonl
```

### 4. Rebuild registries

```bash
# Rebuild URL registry from links.md
awk '/^- Hash:/ { print $3 }' links.md | while read hash; do
    grep "\"hash\":\"$hash\"" .url-registry.jsonl || \
    echo "{\"hash\":\"$hash\",\"rebuilt\":true}" >> .url-registry.jsonl
done

# Rebuild thread registry from links.md
grep -E "^## |^- URL: |^- Hash: " links.md | \
  awk 'BEGIN{RS="## "; FS="\n"} 
  NF>0 {
    title=$1
    for(i=2;i<=NF;i++) {
      if($i ~ /^- URL:/) url=$i
      if($i ~ /^- Hash:/) hash=$i
    }
    if(url && hash) {
      gsub(/^- URL: /,"",url)
      gsub(/^- Hash: /,"",hash)
      print "{\"thread_id\":\"brain-"hash"\",\"url\":\""url"\",\"title\":\""title"\",\"rebuilt\":true}"
    }
  }' >> .thread-registry.jsonl
```

### 5. Full reset (nuclear option)

```bash
# Backup first
tar -czf brain-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
    /root/.openclaw/workspace/memory/second-brain/

# Reset files
cd /root/.openclaw/workspace/memory/second-brain/
rm -f links.md .url-registry.jsonl .pending-queue.jsonl .thread-registry.jsonl .brain-autopull-checkpoint.json
touch links.md .url-registry.jsonl .pending-queue.jsonl .thread-registry.jsonl

# Reset checkpoint
/root/.openclaw/workspace/scripts/brain-telegram-autopull.sh --init-now
```

## Filter Rules

### Ad/Junk Filter (brain-link-ingest.sh)

Links matching these patterns are automatically filtered:

- `utm_source`, `utm_medium`, `utm_campaign` (tracking params)
- `fbclid`, `gclid` (Facebook/Google click IDs)
- `ads.`, `advertisement`, `promo.`, `sponsor`
- `click.`, `tracker`, `doubleclick`
- `googleadservices`, `adservice`, `googlesyndication`

**Bypass:** Use `--force` flag to process anyway.

### System URL Filter (brain-telegram-autopull.sh)

URLs matching these patterns are excluded from auto-capture:

- `scanner.tradingview.com` (TradingView scanner)
- `example.com`, `example.org` (documentation examples)
- `discord.com/api/webhooks` (Discord webhooks)
- `sentry.io/api`, `ingest.sentry.io` (Sentry ingestion)
- `localhost`, `127.0.0.1`, `0.0.0.0` (local addresses)
- `*.internal.*`, `*.local` (internal domains)
- `ngrok.io` (tunnel endpoints)
- `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com` (API endpoints)

**Note:** This filter is in autopull only, not in manual ingest.

## Error Handling

- **Retry logic:** 1 retry on Discord send failure
- **Graceful degradation:** Continues pipeline even if Discord fails
- **Backup:** Creates `.bak` file before modifying `links.md`
- **Queue:** Failed Discord sends or incomplete entries → `.pending-queue.jsonl`

## File Locations

| File                           | Purpose                      |
|--------------------------------|------------------------------|
| `scripts/brain-link-ingest.sh` | Main link ingestion (4-field validation) |
| `scripts/brain-thread-manage.sh`| Thread-based status management |
| `scripts/brain-telegram-autopull.sh`| Auto-capture from Telegram |
| `scripts/brain-daily-done-summary.sh`| Daily summary generator |
| `memory/second-brain/links.md` | Persistent link storage (includes My Opinion) |
| `memory/second-brain/.url-registry.jsonl` | URL hash registry |
| `memory/second-brain/.thread-registry.jsonl` | Thread ID mapping |
| `memory/second-brain/.pending-queue.jsonl` | Incomplete/failed entries |
| `memory/second-brain/.brain-autopull-checkpoint.json` | Last processed timestamp |
| `docs/brain-pipeline.md`       | This documentation           |

## Troubleshooting

### "INCOMPLETE: Missing fields: ..."
- Entry is missing required fields (title/summary/my-opinion)
- Entry queued for manual review
- Add missing fields or use `--force` to send anyway

### "Channel ID must be set"
- Verify `BRAIN_INBOX_CHANNEL_ID` and `BRAIN_OPS_CHANNEL_ID` are exported
- Check `.env` file exists and is loaded

### "Discord send failed"
- Verify Discord bot has access to target channels
- Check bot token is valid in OpenClaw config
- Check `.pending-queue.jsonl` for queued items

### "Too many URLs (> 50)"
- Safety guard triggered (prevents historical flood)
- Run `--init-now` to reset checkpoint to current time
- Or process in batches

### "URL not found in links.md"
- URL must match exactly (including http/https)
- Check for URL encoding differences

### "Duplicate URL detected"
- URL already processed (hash in registry)
- Use `--force` to reprocess

## Integration with Telegram Bot

The main agent can call these scripts when a link is detected:

```bash
# In AGENTS.md auto-capture section
# URL/이미지/포워드/텍스트≥30자 → auto-capture + brain-link-ingest

# Example hook in message processing
if [[ "$TEXT" =~ https?:// ]]; then
    # Auto-captured entries will be INCOMPLETE (no summary/opinion)
    # They get queued for manual review
    ./scripts/brain-link-ingest.sh --url "$MATCHED_URL" --title "$DOMAIN"
fi
```

## Future Improvements

- [x] ~~Auto-fetch title from URL via curl~~
- [x] ~~4-field validation~~
- [x] ~~Thread-based ops model~~
- [x] ~~System URL filtering~~
- [x] ~~Flood prevention (max 50)~~
- [ ] AI-generated summaries via Qwen/GLM
- [ ] `brain-sync-pending.sh` for retry queue processing
- [ ] Integration with Todoist for action items
- [ ] Weekly digest to Telegram
- [ ] Automatic retry via cron (every 5 min)
