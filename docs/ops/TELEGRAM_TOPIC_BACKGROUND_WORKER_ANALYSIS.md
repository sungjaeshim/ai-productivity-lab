# Duplicate Reply Mitigation Analysis

## Current Mitigation in reply-DeXK9BLT.js

### Location
File: `/usr/lib/node_modules/openclaw/dist/reply-DeXK9BLT.js`

### Key Code Sections

#### 1. Subagent announce reply instruction (Line ~29296-29298)
```javascript
function buildAnnounceReplyInstruction(params) {
  if (params.requesterIsSubagent)
    return `Convert this completion into a concise internal orchestration update for your parent agent in your own words.
     Keep this internal context private (don't mention system/log/stats/session details or announce type).
     If this result is duplicate or no update is needed, reply ONLY: ${SILENT_REPLY_TOKEN}.`;

  if (params.expectsCompletionMessage)
    return `A completed ${params.announceType} is ready for user delivery.
     Convert this result above into your normal assistant voice and send that user-facing update now.
     Keep this internal context private (don't mention system/log/stats/details or announce type).`;

  return `A completed ${params.announceType} is ready for user delivery.
     Convert this result above into your normal assistant voice and send that user-visible update now.
     Keep this internal context private (don't mention system/log/stats/details or announce type),
     and do not copy internal event text verbatim.
     Reply ONLY: ${SILENT_REPLY_TOKEN} if this exact result was already delivered to user in this same turn.`;
}
```

**Analysis:**
- Instructs subagents to use `SILENT_REPLY_TOKEN` if duplicate
- Relies on main agent checking if worker already delivered
- **Race condition possible**: Main agent may process before worker delivery completes
- No atomic delivery tracking mechanism

#### 2. TTS tool description (Line ~30894)
```javascript
{
  description: `Convert text to speech. Audio is delivered automatically from the tool result —
   reply with ${SILENT_REPLY_TOKEN} after a successful call to avoid duplicate messages.`
}
```

**Analysis:**
- Specific to TTS tool
- Good pattern: tool delivers directly, agent should be silent
- **Applicable pattern for audio worker**: Worker should deliver, agent should check

#### 3. System prompt instructions (Line ~37824)
```javascript
`- If you use \`message\` (\`action=send\`) to deliver your user-visible reply,
   respond with ONLY: ${SILENT_REPLY_TOKEN} (avoid duplicate replies).`
```

**Analysis:**
- General instruction for message tool usage
- Agent self-regulation, not enforced by runtime
- Still subject to race conditions

## Assessment

### Does it likely help for audio-STT-document worker flow?

**Partial yes, but insufficient:**

✅ **What helps:**
1. Subagent announce mechanism recognizes need for duplicate prevention
2. `SILENT_REPLY_TOKEN` pattern exists and is well-integrated
3. Tool-based delivery (like TTS) provides a model to follow

❌ **What's missing:**
1. **No atomic delivery tracking** - Worker can't claim delivery before main agent checks
2. **Race condition window** - Main agent may generate reply before worker delivery completes
3. **Turn-based duplicate check is fragile** - "same turn" timing is not guaranteed under load
4. **No worker-specific suppression** - Worker should always be silent in its own topic

### Specific Issues for Audio Worker Flow

**Scenario: User uploads 15MB audio file**

```
Timeline:
T0: User uploads to main topic T
T1: Main agent routes to worker topic W (route B)
T2: Worker receives in topic W
T3: Worker starts STT (30-60 seconds)
T4: Main agent may generate interim reply (or complete if timeout)
T5: Worker completes STT, generates document
T6: Worker sends result to main topic T
T7: Main agent sends its own completion to main topic T
```

**Problem:** At T7, main agent doesn't know worker already delivered at T6. Both replies appear.

## Safer Long-Term Fix Points

### 1. Delivery Token Claim (Recommended)

```typescript
// In deliver-CpeI9Z4f.js or new delivery-token module
interface DeliveryClaim {
  token: string;              // Unique ID for this delivery
  claimedAt: number;          // Timestamp
  ttlMs: number;              // Time-to-live
  claimedBy: string;          // Session key or agent ID
}

async function claimDeliveryToken(params: {
  token: string;
  ttlMs: number;
  claimedBy: string;
}): Promise<{ success: boolean; existingClaim?: DeliveryClaim }> {
  // Atomic claim operation
}

async function checkDeliveryToken(params: {
  token: string;
}): Promise<DeliveryClaim | null> {
  // Check if claimed
}
```

**Worker flow:**
```typescript
1. Worker generates delivery token: `worker-<jobId>-<timestamp>`
2. Worker claims token: `claimDeliveryToken({ token, ttlMs: 60000, claimedBy: sessionKey })`
3. If claim fails (already claimed), worker suppresses send
4. Worker sends result to main topic with token in metadata
5. Worker marks complete
```

**Main agent flow:**
```typescript
1. Before sending reply, check if delivery token exists for current turn
2. If token exists and claimed, use `SILENT_REPLY_TOKEN`
3. Otherwise, send reply as normal
```

### 2. Explicit Reply Threading (Fallback)

```typescript
// Worker always replies to original message ID
await message.send({
  channel: "telegram",
  to: mainTopicId,
  message: resultText,
  replyTo: originalMessageId  // ← Thread reply
});
```

**Main agent:**
- Does NOT reply if `replyTo` points to its own message
- This creates a reply chain, preventing parallel top-level replies

### 3. Worker Self-Suppression (Worker-Side Guard)

```javascript
// In worker's system prompt
"When completing tasks in your dedicated worker topic, ALWAYS respond with
 ${SILENT_REPLY_TOKEN} for ALL outputs that are intended for the main topic.
 Use the message tool to send to main topic, then reply with SILENT_REPLY_TOKEN
 to avoid creating duplicate messages in your own topic."
```

### 4. Configurable Duplicate Detection Policy

```json5
{
  "workers": {
    "audio": {
      "delivery": {
        "mode": "token-claim",  // or "reply-threading" or "none"
        "tokenTtlMs": 60000,
        "fallbackToThreading": true
      }
    }
  }
}
```

## Implementation Recommendation

### Phase 1 (Immediate - No dist patch required)
1. Add worker self-suppression system prompt in `workers.audio.example.json`
2. Use explicit `replyTo` threading in worker delivery
3. Document this as interim solution

### Phase 2 (Safe - Minimal dist patch)
1. Add delivery token claim/check functions to existing `sessions-DTVAB3HG.js`
2. Integrate into message delivery pipeline
3. Update `buildAnnounceReplyInstruction()` to check tokens

### Phase 3 (Robust - Architecture change)
1. Implement delivery claim service with Redis/file-based state
2. Atomic delivery token with CAS (compare-and-swap)
3. Metrics and observability for duplicate detection

## Code Touchpoints for Delivery Token Implementation

### 1. New module (can be workspace-owned initially)
`/root/.openclaw/workspace/scripts/delivery_token.js`

### 2. Runtime integration (dist patch)
`/usr/lib/node_modules/openclaw/dist/deliver-CpeI9Z4f.js`
- Add `claimDeliveryToken()` import
- Check before `deliverOutboundPayloads()`

### 3. Agent behavior (dist patch)
`/usr/lib/node_modules/openclaw/dist/reply-DeXK9BLT.js`
- Update `buildAnnounceReplyInstruction()` to check delivery token
- Add token metadata to completion context

## Validation Test Cases

1. **Single worker job**
   - Upload 15MB audio → worker processes → single delivery

2. **Concurrent worker jobs**
   - Upload 3x 15MB files → 3 workers → 3 deliveries, no duplicates

3. **Worker unavailable**
   - Worker topic offline → fallback to inline route A

4. **Race condition**
   - Main agent times out, worker completes later → no duplicate

5. **Delivery token TTL**
   - Old tokens expire after 60s → allow retry if needed

## Conclusion

**Current mitigation:** Helpful as a pattern, but insufficient for preventing duplicates in async worker flows due to race conditions and lack of atomic delivery tracking.

**Recommended approach:** Implement delivery token claim/check mechanism (Phase 2) with reply threading as fallback (Phase 1 interim).

**Risk:** Low if incremental; start with Phase 1, validate, then Phase 2.
