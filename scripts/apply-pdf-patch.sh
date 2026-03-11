#!/bin/bash
# Apply Telegram PDF auto-dispatch patch

DISPATCH_FILE="/usr/lib/node_modules/openclaw/dist/plugin-sdk/dispatch-BCrTbhbt.js"
BACKUP_FILE="${DISPATCH_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
PATCH_FILE="/root/.openclaw/workspace/docs/patches/telegram-pdf-autodispatch.patch"
INJECTION_LINE=84412

echo "=== Applying Telegram PDF Auto-Dispatch Patch ==="
echo ""

# Check if patch already applied
if grep -q "telegram-pdf-autodispatch" "$DISPATCH_FILE"; then
    echo "❌ Patch already applied. Remove existing patch first or skip."
    grep -n "telegram-pdf-autodispatch" "$DISPATCH_FILE"
    exit 1
fi

# Create backup
echo "📦 Creating backup: $BACKUP_FILE"
cp "$DISPATCH_FILE" "$BACKUP_FILE"

# Insert patch before line 84412
echo "🔧 Inserting patch at line $INJECTION_LINE"

# Read patch content
PATCH_CONTENT=$(cat "$PATCH_FILE")

# Use sed to insert patch before the target line
sed -i "${INJECTION_LINE}i\\
\\
${PATCH_CONTENT}
" "$DISPATCH_FILE"

# Verify patch applied
if grep -q "telegram-pdf-autodispatch" "$DISPATCH_FILE"; then
    echo "✅ Patch applied successfully!"
    echo ""
    echo "Verifying patch location:"
    grep -n "telegram-pdf-autodispatch" "$DISPATCH_FILE" | head -3
    echo ""
    echo "Showing patched context:"
    sed -n "$((INJECTION_LINE - 5)),$((INJECTION_LINE + 25))p" "$DISPATCH_FILE"
    echo ""
    echo "✅ To revert patch: cp $BACKUP_FILE $DISPATCH_FILE"
else
    echo "❌ Patch application failed!"
    echo "Restoring from backup..."
    cp "$BACKUP_FILE" "$DISPATCH_FILE"
    exit 1
fi

echo ""
echo "=== Restart Gateway to apply changes ==="
echo "   openclaw gateway restart"
