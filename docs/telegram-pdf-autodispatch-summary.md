# 변경 (Changes)

## Created Documentation
1. `/root/.openclaw/workspace/docs/telegram-pdf-auto-dispatch-plan.md` - Complete implementation plan with analysis
2. `/root/.openclaw/workspace/docs/patches/telegram-pdf-autodispatch.patch` - Ready-to-apply patch code
3. `/root/.openclaw/workspace/scripts/verify-pdf-patch.sh` - Verification script to check patch location
4. `/root/.openclaw/workspace/scripts/apply-pdf-patch.sh` - Automated patch application script

## Key Findings
- **Runtime Entry Point:** `buildTelegramMessageContext()` in `/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js:84394`
- **Injection Point:** Line 84412 (after `topicConfig` resolution, before `resolveTelegramConversationRoute`)
- **Available Variables:** `chatId`, `messageThreadId`, `resolvedThreadId`, `topicConfig`, `allMedia[]`
- **AGENTS.md Review:** Cannot influence runtime behavior - workspace policy only, not runtime config

## Patch Strategy
The patch intercepts PDF attachments in topic 81/doc-worker before normal chat routing:
1. Checks if `resolvedThreadId === 81` or `topicConfig?.agentId === 'doc-worker'`
2. Finds PDF in `allMedia` array (by `contentType` or `.pdf` extension)
3. Spawns detached process: `python3 /root/.openclaw/workspace/scripts/pdf_extract.py <pdf_path>`
4. Returns `null` to skip normal chat flow (prevents timeout)
5. Includes error handling to continue normal flow on spawn failure

---

# 검증 (Verification)

## Evidence: File Locations & Line Numbers
```bash
# Key runtime file
/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js

# Critical lines verified:
84394: function buildTelegramMessageContext(allMedia, ...)
84395: const msg = primaryCtx.message;
84400: const messageThreadId = msg.message_thread_id;
84404: const resolvedThreadId = threadSpec.scope === "forum" ? threadSpec.id : void 0;
84409: const { groupConfig, topicConfig } = resolveTelegramGroupConfig(chatId, resolvedThreadId ?? dmThreadId);
84411: const freshCfg = loadConfig();  # <-- INJECT PATCH AFTER THIS LINE
84412: let { route, ... } = resolveTelegramConversationRoute({...});  # <-- BEFORE THIS LINE
```

## Evidence: allMedia Data Flow
- `allMedia` parameter passed to `buildTelegramMessageContext()` (line 84394)
- Contains array of `{ path, contentType, placeholder? }` objects
- Populated upstream by Telegram media download handlers

## Evidence: Topic 81 Detection
- `messageThreadId` extracted from `msg.message_thread_id` (line 84400)
- Converted to `resolvedThreadId` via `threadSpec` (line 84404)
- Used for `topicConfig` lookup (line 84409)
- Available for patch condition check: `resolvedThreadId === 81`

## Verification Script Output
```
=== Telegram PDF Auto-Dispatch Patch Verification ===

✅ Found dispatch file: /usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js

Line with 'const msg = primaryCtx.message;': 84395
Line with topicConfig resolution: 84409
Line with route resolution: 84412

Suggested injection line: 84412

✅ No existing patch found - safe to apply
```

---

# 결과 (Results)

## Minimal Touch Points Identified
Only **1 runtime file** requires modification:
```
/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js
  → Line 84412: Insert PDF auto-dispatch logic
  → ~25 lines of code (including comments & error handling)
```

## Developer-Ready Artifacts Delivered
1. **Implementation Plan** (`telegram-pdf-auto-dispatch-plan.md`)
   - Problem analysis
   - Runtime flow diagram
   - Two implementation options (quick vs. sustainable)
   - Risk assessment
   - Verification steps

2. **Ready-to-Apply Patch** (`telegram-pdf-autodispatch.patch`)
   - Clean, commented code
   - Error handling
   - Logging for debugging
   - Returns `null` to skip normal flow

3. **Automation Scripts**
   - `verify-pdf-patch.sh`: Pre-flight check
   - `apply-pdf-patch.sh`: One-command application with backup

## No Workspace-Owned Hook Path Found
- OpenClaw runtime does not currently support per-topic auto-dispatch hooks
- AGENTS.md is session-level policy, not runtime configuration
- Requires runtime patch (Option A) for immediate fix
- Config-driven approach (Option B) needs upstream schema changes

---

# 리스크·후속 (Risks & Follow-up)

## Risks
**Low Risk:**
- ✅ Patch location is early in message processing (before routing)
- ✅ Returns `null` cleanly to skip normal flow
- ✅ Detached spawn process prevents blocking
- ✅ Error handling continues normal flow on failure
- ✅ No direct file manipulation by runtime

**Medium Risk:**
- ⚠️ Patch on dist file (overwritten on OpenClaw update)
- ⚠️ Hardcoded topic ID (81) - requires update if topic changes
- ⚠️ Depends on `allMedia` populated correctly upstream

**Mitigations:**
- Backup created automatically before patch
- Logging added for post-patch debugging
- Easy rollback with single command

## Follow-up Actions

### Immediate (Apply Patch)
```bash
# 1. Verify patch location
/root/.openclaw/workspace/scripts/verify-pdf-patch.sh

# 2. Apply patch
/root/.openclaw/workspace/scripts/apply-pdf-patch.sh

# 3. Restart Gateway
openclaw gateway restart
```

### Test After Patch
```bash
# Send test PDF to Telegram topic 81/doc-worker
# Verify pdf_extract.py runs:
ls -lth /root/.openclaw/workspace/documents/*.json | head -5

# Check logs for autodispatch:
journalctl -u openclaw -f | grep "telegram-pdf-autodispatch"
```

### Long-term (Sustainable Solution)
Consider **Option B** from implementation plan:
1. Extend `TelegramTopicConfig` schema for `autoDispatch` support
2. Add config to `~/.openclaw/config.json`:
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
3. Submit PR to OpenClaw upstream for config-driven auto-dispatch

### Rollback (If Needed)
```bash
# Restore from backup
cp ~/.openclaw/config.json.bak-YYYYMMDD-HHMMSS ~/.openclaw/config.json
# Or use backup created by apply script
cp /usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js.bak-* \
   /usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js

openclaw gateway restart
```

## Artifacts Summary
```
/root/.openclaw/workspace/
├── docs/
│   ├── telegram-pdf-auto-dispatch-plan.md    (Implementation plan)
│   └── patches/
│       └── telegram-pdf-autodispatch.patch  (Patch code)
└── scripts/
    ├── pdf_extract.py                        (Target script)
    ├── verify-pdf-patch.sh                   (Pre-flight check)
    └── apply-pdf-patch.sh                    (Apply automation)
```

**Task Complete:** Minimal runtime integration points identified and documented. Ready for patch application.
