# Telegram Topic/Group Dedicated Background Worker Flow
## Developer Request for Audio-STT-Document Conversion

**Status:** Draft
**Created:** 2026-03-10
**Priority:** High

---

## Problem Statement

Current OpenClaw behavior:
1. Audio files are transcribed inline within the main chat flow
2. Large audio files (>10MB) block main chat responsiveness
3. Multiple rapid audio inputs create processing bottlenecks
4. No dedicated workspace for audio→STT→document workflows
5. Duplicate final replies occur when:
   - Worker completes and sends update
   - Main agent also generates completion
   - Both arrive in same turn, causing user-visible duplication

## Goals

1. **Dedicated Telegram topic/group routing** - Route audio-heavy workflows to isolated topic(s)
2. **Background worker flow** - Process audio→STT→document asynchronously without blocking main chat
3. **Single source of truth for final delivery** - Eliminate duplicate replies
4. **Workspace isolation** - Each topic/worker gets its own workspace context
5. **Status visibility** - Main chat shows minimal progress, not full logs

## Proposed Solution

### 1. Routing Layer

Create per-topic worker routing via `bindings[]` configuration:

```json5
{
  "agents": {
    "list": [
      {
        "id": "audio-worker",
        "workspace": "~/.openclaw/workspace-audio-worker",
        "runtime": {
          "type": "acp",
          "acp": {
            "agent": "codex",
            "backend": "acpx",
            "mode": "persistent",
            "cwd": "/workspace/audio"
          }
        }
      }
    ]
  },
  "bindings": [
    {
      "type": "acp",
      "agentId": "audio-worker",
      "match": {
        "channel": "telegram",
        "accountId": "default",
        "peer": {
          "kind": "group",
          "id": "-1001234567890:topic:42"
        }
      },
      "acp": {
        "label": "audio-worker-42",
        "mode": "persistent"
      }
    }
  ]
}
```

### 2. Background Worker Flow

```
User uploads audio → Main topic T
                    ↓
              [Router checks size]
                    ↓
    ≤10MB ────────────────> >10MB
        │                        │
        ↓                        ↓
   Inline STT              Worker topic W
        │                        │
        ↓                        ↓
   Document ←────────────────── Document
        │                        │
        └────────────> Final reply ←┘
```

**Key invariants:**
- Main topic T receives the audio file
- If `size > threshold`, route to worker topic W
- Worker topic W processes: download → STT (Whisper/Deepgram) → document → summary
- Worker sends final result ONLY to main topic T
- Worker uses `SILENT_REPLY_TOKEN` for its own topic to avoid double-replies

### 3. Duplicate Reply Prevention

**Current mitigation (in reply-DeXK9BLT.js):**
- `buildAnnounceReplyInstruction()` includes:
  > `Reply ONLY: ${SILENT_REPLY_TOKEN} if this exact result was already delivered to user in this same turn.`

**Problem:** This relies on the main agent checking if the worker already delivered. Race condition exists.

**Safer long-term fix:**
1. Worker should mark delivery in shared state before sending
2. Main agent should check state before generating its own reply
3. Or: use explicit `reply_to` threading to avoid double delivery

**Proposed implementation:**
```typescript
// Worker-side delivery contract
async function deliverWorkerResult(params: {
  targetChatId: string;
  result: WorkerOutput;
  deliveryToken: string;
}) {
  // 1. Claim delivery token atomically
  const claimed = await claimDeliveryToken({
    token: params.deliveryToken,
    ttlMs: 60_000 // 1 minute
  });

  if (!claimed) {
    // Another worker/handler already claimed this result
    return { status: "duplicate", suppressed: true };
  }

  // 2. Send to target topic
  await message.send({
    channel: "telegram",
    to: params.targetChatId,
    message: formatWorkerResult(params.result),
    replyTo: params.result.originalMessageId
  });

  // 3. Mark delivered
  await markDeliveryComplete({ token: params.deliveryToken });

  return { status: "delivered", suppressed: false };
}
```

### 4. Workspace Isolation

Each worker topic gets:
- `~/.openclaw/workspace-audio-worker-<topicId>/`
- Separate session store
- Isolated ACP session (persistent mode)
- Audio download directory: `<workspace>/tmp/downloads/`
- Transcript directory: `<workspace>/transcripts/`
- Document output directory: `<workspace>/documents/`

### 5. Status Updates (Main Topic Visibility)

Main topic shows ONLY:
```
📎 received <filename> (12.5 MB)
⏳ processing (route B) → worker topic
✅ done: summary link
```

Worker topic shows detailed logs:
```
→ Downloaded to /workspace/tmp/downloads/audio_abc123.ogg (12.5 MB)
→ Whisper starting: model=medium, timeout=1800s
→ Transcript saved to /workspace/transcripts/audio_abc123.txt
→ Document generated: /workspace/documents/audio_abc123.md
→ Summary sent to main topic
```

## Configuration Schema Extensions

### New config section: `workers.audio`

```json5
{
  "workers": {
    "audio": {
      "enabled": true,
      "thresholdMB": 10.0,
      "routes": {
        "A": {
          "description": "Inline / speed-first",
          "model": "small",
          "timeoutSec": 600,
          "inline": true
        },
        "B": {
          "description": "Worker / quality-first",
          "model": "medium",
          "timeoutSec": 1800,
          "workerTopic": "-1001234567890:topic:42",
          "inline": false
        }
      },
      "delivery": {
        "tokenTtlMs": 60000,
        "retryAttempts": 3,
        "retryDelayMs": 2000
      }
    }
  }
}
```

## Implementation Phases

### Phase 1: Minimal viable routing (workspace-only)
- [ ] Add `workers.audio.routes` config schema
- [ ] Implement route selector (size-based)
- [ ] Route to worker topic if size > threshold
- [ ] Worker ACP session binding via existing `bindings[]`
- [ ] Workspace isolation per topic
- **Evidence:** Config file update + worker topic routing works

### Phase 2: Background worker execution
- [ ] Worker receives audio in its topic
- [ ] Downloads to `<workspace>/tmp/downloads/`
- [ ] Runs STT (Whisper/Deepgram) with timeout
- [ ] Saves transcript to `<workspace>/transcripts/`
- [ ] Generates document from transcript
- [ ] Sends result back to main topic
- **Evidence:** End-to-end audio → document flow

### Phase 3: Duplicate reply prevention
- [ ] Implement `claimDeliveryToken()` / `markDeliveryComplete()` in shared state
- [ ] Worker claims token before sending
- [ ] Main agent checks token before sending its own reply
- [ ] Fallback: use explicit `reply_to` threading
- **Evidence:** No duplicate messages under load

### Phase 4: Status visibility
- [ ] Main topic shows minimal status (received → processing → done)
- [ ] Worker topic shows detailed logs
- [ ] Error handling with failure codes (FETCH_DENIED, TIMEOUT, etc.)
- **Evidence:** Clean main topic, verbose worker topic

### Phase 5: Hardening
- [ ] Config validation on startup
- [ ] Worker health checks (timeout recovery)
- [ ] Graceful fallback to inline if worker unavailable
- [ ] Metrics: route usage, success rate, latency
- **Evidence:** Production-ready under failure conditions

## Code Touchpoints

### Core runtime (dist patch required)
1. `/usr/lib/node_modules/openclaw/dist/deliver-CpeI9Z4f.js`
   - Add `claimDeliveryToken()` / `checkDeliveryToken()` functions
   - Integrate with outbound payload delivery

2. `/usr/lib/node_modules/openclaw/dist/send-CLv9RIs5.js`
   - Add worker-aware message routing
   - Support topic-to-topic message forwarding

3. `/usr/lib/node_modules/openclaw/dist/reply-DeXK9BLT.js`
   - Enhance `buildAnnounceReplyInstruction()` to check delivery token
   - Add worker result acknowledgment logic

### Workspace-owned artifacts
1. `/root/.openclaw/workspace/docs/ops/WORKER_AUDIO_CONFIG_SCHEMA.md`
   - Full config schema documentation

2. `/root/.openclaw/workspace/scripts/audio_worker.sh`
   - Worker entrypoint (route A vs B, download, STT, document)

3. `/root/.openclaw/workspace/config/workers.audio.example.json`
   - Example configuration

## Validation Plan

1. **Unit tests**
   - Route selector logic (threshold boundary cases)
   - Delivery token claim/release
   - Duplicate detection

2. **Integration tests**
   - Small file (≤10MB) → inline route A
   - Large file (>10MB) → worker route B
   - Worker sends result back to main topic
   - No duplicate messages under concurrent uploads

3. **Manual testing**
   - Upload 5MB file → inline processing in main topic
   - Upload 15MB file → worker processing in topic 42
   - Verify main topic shows minimal status
   - Verify worker topic shows detailed logs
   - Upload 3 files rapidly → verify no duplicates

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|---------|------------|
| Worker ACP session unavailable | High | Graceful fallback to inline route |
| Delivery token race condition | High | Atomic claim + TTL + retry |
| Worker topic deletion during job | Medium | Job state persisted in workspace |
| STT timeout on large files | Medium | Configurable timeout per route |
| Network failure during download | Low | Retry with exponential backoff |

## Dependencies

- Existing ACP bindings infrastructure (Phase 1 complete per docs)
- `scripts/audio_route.py` (already exists - can be adapted)
- Deepgram/Whisper integration (already exists in `tools.media.audio`)

## Open Questions

1. Should worker topics be auto-created or pre-configured?
   - Recommendation: Pre-configured for stability, with docs for manual setup

2. Should we support multiple concurrent workers (one per large file)?
   - Recommendation: Single worker topic per route for simplicity, can scale later

3. How should errors be surfaced to main topic?
   - Recommendation: Minimal error summary with code, full logs in worker topic

## Success Criteria

- [ ] Audio >10MB routes to worker topic without blocking main chat
- [ ] Worker processes audio→STT→document end-to-end
- [ ] Zero duplicate final replies under concurrent uploads
- [ ] Main topic remains clean (received → processing → done)
- [ ] Worker topic shows detailed logs
- [ ] Graceful fallback if worker unavailable

---

## Appendix: Current Duplicate Reply Mitigation

**File:** `/usr/lib/node_modules/openclaw/dist/reply-DeXK9BLT.js`

**Lines 29296-29298:**
```javascript
if (params.requesterIsSubagent) return `... reply ONLY: ${SILENT_REPLY_TOKEN}.`;
return `A completed ${params.announceType} is ready for user delivery. Convert this result above into your normal assistant voice and send that user-facing update now. Keep this internal context private (don't mention system/log/stats/details or announce type), and do not copy internal event text verbatim. Reply ONLY: ${SILENT_REPLY_TOKEN} if this exact result was already delivered to user in this same turn.`;
```

**Analysis:**
- Relies on main agent checking if worker already delivered
- No atomic delivery token mechanism
- Race condition possible if main agent processes before worker delivery completes

**Safer fix points:**
1. Implement delivery token claim before any send
2. Check token state in main agent before generating its own reply
3. Use explicit `reply_to` threading as fallback
4. Worker always uses `SILENT_REPLY_TOKEN` in its own topic (no self-replies)
