# PDF Auto-Dispatch from Telegram Topic 81/doc-worker

## Problem Statement
PDF attachments sent to Telegram topic `81/doc-worker` timeout in normal chat flow instead of being automatically dispatched to `/root/.openclaw/workspace/scripts/pdf_extract.py`.

## Goal
Auto-dispatch incoming PDF attachments from Telegram topic `81/doc-worker` to `pdf_extract.py` without timing out.

## Findings

### 1. Runtime Entry Points Identified

The Telegram inbound message processing flow:

```
/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js
├── buildTelegramMessageContext() (line 84394)
│   ├── Extracts message_thread_id from msg.message_thread_id
│   ├── Calls resolveTelegramGroupConfig(chatId, resolvedThreadId)
│   ├── Checks topicConfig for topic-level configuration
│   └── Returns context with allMedia array
│
└── dispatchTelegramMessage() (line 85312)
    └── Routes to agent/session binding
```

### 2. Key Variables and Data Flow

**Message Context:**
- `chatId` - Telegram chat ID
- `messageThreadId` - Forum topic ID (81 for doc-worker)
- `allMedia[]` - Array of downloaded media objects with `path`, `contentType`

**Group/Topic Config:**
- `groupConfig` - Group-level settings from `channels.telegram.groups[chatId]`
- `topicConfig` - Topic-level settings from `channels.telegram.groups[chatId].topics[messageThreadId]`

**Resolution Chain:**
```javascript
messageThreadId = msg.message_thread_id;  // 81
resolvedThreadId = threadSpec.id;         // 81
{ groupConfig, topicConfig } = resolveTelegramGroupConfig(chatId, resolvedThreadId);
```

### 3. Minimal Patch Points

The **earliest safe intervention point** is in `buildTelegramMessageContext()` just after `allMedia` is populated but before routing:

**Location:** `/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js:84394` area

**Patch Strategy:**
```javascript
// After line 84430 (after topicConfig is resolved)
// BEFORE route resolution (line 84433)

// Check: is this topic 81/doc-worker with PDF attachment?
if (topicConfig?.agentId === "doc-worker" || resolvedThreadId === 81) {
  // Check for PDF in allMedia
  const pdfMedia = allMedia.find(m =>
    m.contentType === "application/pdf" || m.path.endsWith('.pdf')
  );

  if (pdfMedia) {
    // Direct dispatch to pdf_extract.py
    const { spawn } = require('child_process');
    spawn('python3', [
      '/root/.openclaw/workspace/scripts/pdf_extract.py',
      pdfMedia.path
    ], {
      detached: true,
      stdio: 'ignore'
    }).unref();

    // Skip normal chat flow to avoid timeout
    return null;
  }
}
```

### 4. Configuration-Based Alternative (Cleaner)

**Workspace-owned config path** - add topic-level configuration:

```json
// ~/.openclaw/config.json
{
  "channels": {
    "telegram": {
      "groups": {
        "CHAT_ID": {
          "topics": {
            "81": {
              "agentId": "doc-worker",
              "autoDispatch": {
                "enabled": true,
                "contentType": "application/pdf",
                "script": "/root/.openclaw/workspace/scripts/pdf_extract.py",
                "skipNormalFlow": true
              }
            }
          }
        }
      }
    }
  }
}
```

This requires:
1. Runtime to read `topicConfig.autoDispatch`
2. Apply auto-dispatch logic before routing
3. Config schema update to support `autoDispatch`

### 5. doc-worker AGENTS.md Review

The current `/root/.openclaw/workspace/AGENTS.md` is a **workspace policy document**, not an agent binding configuration. It **cannot** influence runtime behavior because:

- Runtime reads `~/.openclaw/config.json` for agent bindings
- AGENTS.md is for session-level behavior guidance (read by agents, not runtime)
- No runtime code reads or applies AGENTS.md rules

**Conclusion:** doc-worker must be configured via `~/.openclaw/config.json` topic binding.

## Recommended Implementation

### Option A: Minimal Runtime Patch (Quick)

**File:** `/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js`

**Patch Location:** After line 84430 (after `topicConfig` resolution, before `resolveTelegramConversationRoute`)

**Patch Code:**
```javascript
// Auto-dispatch PDF attachments for doc-worker topic
if (resolvedThreadId === 81 || topicConfig?.agentId === 'doc-worker') {
  const pdfMedia = allMedia.find(m =>
    m.contentType === 'application/pdf' || m.path?.endsWith('.pdf')
  );

  if (pdfMedia && pdfMedia.path) {
    try {
      const { spawn } = require('child_process');
      const child = spawn('python3', [
        '/root/.openclaw/workspace/scripts/pdf_extract.py',
        pdfMedia.path
      ], {
        detached: true,
        stdio: 'ignore',
        cwd: '/root/.openclaw/workspace'
      });
      child.unref();

      logger?.info?.({
        topic: 'telegram-pdf-autodispatch',
        chatId,
        threadId: resolvedThreadId,
        pdfPath: pdfMedia.path
      }, 'Auto-dispatched PDF to pdf_extract.py');

      // Skip normal chat flow to prevent timeout
      return null;
    } catch (err) {
      logger?.error?.({
        topic: 'telegram-pdf-autodispatch',
        error: String(err),
        pdfPath: pdfMedia.path
      }, 'Failed to auto-dispatch PDF');
      // Continue with normal flow on error
    }
  }
}
```

**Pros:**
- No config changes required
- Works immediately after patch
- Minimal code footprint

**Cons:**
- Patched on dist file (overwritten on OpenClaw update)
- Hardcoded topic ID (81)

### Option B: Config-Driven Extension (Sustainable)

**Step 1:** Extend `TelegramTopicConfig` schema to support `autoDispatch`

**Step 2:** Add config to `~/.openclaw/config.json`:
```json
{
  "channels": {
    "telegram": {
      "groups": {
        "<CHAT_ID>": {
          "topics": {
            "81": {
              "agentId": "doc-worker",
              "autoDispatch": {
                "enabled": true,
                "contentTypes": ["application/pdf"],
                "script": "/root/.openclaw/workspace/scripts/pdf_extract.py"
              }
            }
          }
        }
      }
    }
  }
}
```

**Step 3:** Patch runtime to read and apply `autoDispatch` config (same location as Option A, but config-driven)

**Pros:**
- Configurable per topic
- Survives OpenClaw updates (if merged upstream)
- Reusable for other topics/file types

**Cons:**
- Requires schema changes
- More implementation effort
- Still needs runtime patch initially

## Verification Steps

1. **Locate exact line numbers:**
   ```bash
   grep -n "resolveTelegramConversationRoute" /usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js | head -1
   ```

2. **Apply patch:** Insert PDF auto-dispatch logic before the matched line

3. **Test:**
   - Send PDF to Telegram topic 81/doc-worker
   - Verify pdf_extract.py runs (check `/root/.openclaw/workspace/documents/*.json`)
   - Verify no timeout error in logs

4. **Check logs:**
   ```bash
   journalctl -u openclaw -f | grep "pdf-autodispatch"
   ```

## Risk Assessment

**Low Risk:**
- Patch is in message context building (early in flow)
- Returns `null` to skip normal flow (prevents double-processing)
- Detached spawn prevents blocking

**Mitigations:**
- Error handling continues normal flow if spawn fails
- Logging for debugging
- No direct file manipulation by runtime

## Summary

**Change Required:** Single function injection in `buildTelegramMessageContext()`

**Patch Location:** `/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js` (line ~84430)

**Touch Points:**
1. `messageThreadId` → `resolvedThreadId` (line 84399-84401)
2. `topicConfig` resolution (line 84428)
3. `allMedia` array (populated earlier in call stack)
4. `pdf_extract.py` script invocation

**Next Action:** Apply Option A patch for immediate fix, then consider Option B for long-term maintainability.
