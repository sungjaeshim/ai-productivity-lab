#!/bin/bash
# Verification script for Telegram PDF auto-dispatch patch

DISPATCH_FILE="/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js"

echo "=== Telegram PDF Auto-Dispatch Patch Verification ==="
echo ""

# Check if file exists
if [ ! -f "$DISPATCH_FILE" ]; then
    echo "❌ ERROR: dispatch file not found: $DISPATCH_FILE"
    exit 1
fi

echo "✅ Found dispatch file: $DISPATCH_FILE"
echo ""

# Find key markers
echo "--- Finding patch location markers ---"

# Line numbers
MSG_LINE=$(grep -n "const msg = primaryCtx.message;" "$DISPATCH_FILE" | cut -d: -f1)
TOPICCONFIG_LINE=$(grep -n "const { groupConfig, topicConfig } = resolveTelegramGroupConfig" "$DISPATCH_FILE" | cut -d: -f1)
ROUTE_LINE=$(grep -n "let { route, configuredBinding, configuredBindingSessionKey } = resolveTelegramConversationRoute" "$DISPATCH_FILE" | cut -d: -f1)

echo "Line with 'const msg = primaryCtx.message;': $MSG_LINE"
echo "Line with topicConfig resolution: $TOPICCONFIG_LINE"
echo "Line with route resolution: $ROUTE_LINE"
echo ""

# Check for allMedia parameter
echo "--- Checking allMedia parameter ---"
ALLMEDIA_LINE=$(grep -n "allMedia.*replyMedia.*storeAllowFrom" "$DISPATCH_FILE" | grep "buildTelegramMessageContext" | head -1 | cut -d: -f1)
echo "buildTelegramMessageContext allMedia parameter line: $ALLMEDIA_LINE"
echo ""

# Verify injection point
echo "--- Verifying injection point ---"
INJECTION_POINT=$((TOPICCONFIG_LINE + 3))

echo "Suggested injection line: $INJECTION_POINT"
echo "Expected context after injection:"
sed -n "${TOPICCONFIG_LINE},$((ROUTE_LINE - 1))p" "$DISPATCH_FILE" | head -10
echo ""

# Check for existing patch
echo "--- Checking for existing patch ---"
if grep -q "telegram-pdf-autodispatch" "$DISPATCH_FILE"; then
    echo "⚠️  WARNING: Patch may already be applied (found 'telegram-pdf-autodispatch' marker)"
    grep -n "telegram-pdf-autodispatch" "$DISPATCH_FILE"
else
    echo "✅ No existing patch found - safe to apply"
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Patch file location: /root/.openclaw/workspace/docs/patches/telegram-pdf-autodispatch.patch"
echo "Plan document: /root/.openclaw/workspace/docs/telegram-pdf-auto-dispatch-plan.md"
