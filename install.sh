#!/bin/bash
# =============================================================================
# OpenClaw Memory LanceDB — Custom Embedding Edition
# Quick installer
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect OpenClaw install path
if [ -d "$HOME/.npm-global/lib/node_modules/openclaw" ]; then
  OPENCLAW_DIR="$HOME/.npm-global/lib/node_modules/openclaw"
elif [ -d "/opt/homebrew/lib/node_modules/openclaw" ]; then
  OPENCLAW_DIR="/opt/homebrew/lib/node_modules/openclaw"
elif [ -d "/usr/local/lib/node_modules/openclaw" ]; then
  OPENCLAW_DIR="/usr/local/lib/node_modules/openclaw"
else
  OPENCLAW_DIR="$(npm root -g)/openclaw"
fi
PLUGIN_DIR="$OPENCLAW_DIR/extensions/memory-lancedb"

echo "=== OpenClaw Memory LanceDB Custom Installer ==="
echo ""

# Check OpenClaw exists
if [ ! -d "$PLUGIN_DIR" ]; then
  echo "ERROR: OpenClaw not found at $OPENCLAW_DIR"
  echo "Install OpenClaw first: npm install -g openclaw"
  exit 1
fi

# Backup originals
echo "[1/4] Backing up original plugin files..."
for f in index.ts config.ts openclaw.plugin.json; do
  if [ -f "$PLUGIN_DIR/$f" ] && [ ! -f "$PLUGIN_DIR/$f.original" ]; then
    cp "$PLUGIN_DIR/$f" "$PLUGIN_DIR/$f.original"
    echo "  Backed up: $f → $f.original"
  fi
done

# Copy plugin files
echo "[2/4] Installing custom plugin files..."
cp "$SCRIPT_DIR/index.ts" "$PLUGIN_DIR/index.ts"
cp "$SCRIPT_DIR/config.ts" "$PLUGIN_DIR/config.ts"
cp "$SCRIPT_DIR/openclaw.plugin.json" "$PLUGIN_DIR/openclaw.plugin.json"
echo "  Installed: index.ts, config.ts, openclaw.plugin.json"

# Install LanceDB + Apache Arrow
echo "[3/4] Installing @lancedb/lancedb and apache-arrow..."
cd "$OPENCLAW_DIR"
npm install @lancedb/lancedb apache-arrow --legacy-peer-deps --silent 2>/dev/null
node -e "require('@lancedb/lancedb'); console.log('  LanceDB loaded OK')" || {
  echo "  ERROR: LanceDB failed to load. You may need to build from source:"
  echo "    npm install @lancedb/lancedb --build-from-source --legacy-peer-deps"
  exit 1
}

# Patch dist
echo "[4/4] Patching dist schema validation..."
PATCHED=0
for f in dist/manager-*.js; do
  if grep -q "text-embedding-3-small" "$f" 2>/dev/null; then
    sed -i 's/"enum":\["text-embedding-3-small","text-embedding-3-large"\]/"type":"string"/g' "$f"
    sed -i 's/"additionalProperties":false,"properties":{"apiKey":{"type":"string"},"model"/"properties":{"apiKey":{"type":"string"},"baseUrl":{"type":"string"},"model"/g' "$f"
    sed -i 's/"required":\["apiKey"\]/"required":[]/g' "$f"
    PATCHED=$((PATCHED + 1))
  fi
done
if [ "$PATCHED" -gt 0 ]; then
  echo "  Patched $PATCHED dist file(s)"
else
  echo "  Dist already patched (or no matching files found)"
fi

# Verify
echo ""
echo "=========================================="
echo "  Installation complete"
echo "=========================================="
echo ""
echo "Add to your ~/.openclaw/openclaw.json:"
echo ""
echo '  "plugins": {'
echo '    "slots": { "memory": "memory-lancedb" },'
echo '    "entries": {'
echo '      "memory-lancedb": {'
echo '        "enabled": true,'
echo '        "config": {'
echo '          "embedding": {'
echo '            "apiKey": "your-api-key",'
echo '            "model": "nomic-embed-text-v2-moe",'
echo '            "baseUrl": "http://localhost:11434/v1"'
echo '          },'
echo '          "autoCapture": true,'
echo '          "autoRecall": true'
echo '        }'
echo '      }'
echo '    }'
echo '  }'
echo ""
echo "Then: openclaw gateway restart"
