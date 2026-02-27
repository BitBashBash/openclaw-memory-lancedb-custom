#!/bin/bash
# =============================================================================
# OpenClaw Memory LanceDB — Custom Edition Installer
# v2.0.0 — Smart installer with auto-skip for stock features
#
# What this custom plugin adds over stock:
#   1. Multi-agent memory isolation via agentId
#   2. Extended embedding dimensions map (12+ models)
#   3. Graceful fallback to 768 dims for unknown models
#
# Stock-compatible features:
#   - baseUrl for custom embedding endpoints
#   - dimensions config field for explicit override
#   - Environment variable resolution for baseUrl
#
# The installer auto-detects whether dist patching is needed:
#   - Newer OpenClaw: Stock supports baseUrl/dimensions natively → NO dist patch
#   - Older OpenClaw: Needs dist patch for schema validation bypass
# =============================================================================
set -e

# Cross-platform sed in-place
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

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

echo "=== OpenClaw Memory LanceDB Custom Installer v2.0.0 ==="
echo ""

# Check OpenClaw exists
if [ ! -d "$PLUGIN_DIR" ]; then
  echo "ERROR: OpenClaw not found at $OPENCLAW_DIR"
  echo "Install OpenClaw first: npm install -g openclaw"
  exit 1
fi

# Detect OpenClaw version
OC_VERSION="unknown"
if command -v openclaw &>/dev/null; then
  OC_VERSION=$(openclaw --version 2>&1 | tr -d '[:space:]')
fi
echo "OpenClaw version: $OC_VERSION"
echo "Plugin dir: $PLUGIN_DIR"
echo ""

# Backup originals
echo "[1/4] Backing up original plugin files..."
for f in index.ts config.ts openclaw.plugin.json; do
  if [ -f "$PLUGIN_DIR/$f" ] && [ ! -f "$PLUGIN_DIR/$f.original" ]; then
    cp "$PLUGIN_DIR/$f" "$PLUGIN_DIR/$f.original"
    echo "  Backed up: $f → $f.original"
  fi
done

# Copy custom plugin files (always — these contain agentId isolation)
echo "[2/4] Installing custom plugin files..."
cp "$SCRIPT_DIR/index.ts" "$PLUGIN_DIR/index.ts"
cp "$SCRIPT_DIR/config.ts" "$PLUGIN_DIR/config.ts"
cp "$SCRIPT_DIR/openclaw.plugin.json" "$PLUGIN_DIR/openclaw.plugin.json"
echo "  Installed: index.ts, config.ts, openclaw.plugin.json"

# Install LanceDB + Apache Arrow (if not already present)
echo "[3/4] Checking LanceDB dependency..."
cd "$OPENCLAW_DIR"
if node -e "require('@lancedb/lancedb')" 2>/dev/null; then
  echo "  LanceDB already installed ✓"
else
  echo "  Installing @lancedb/lancedb and apache-arrow..."
  npm install @lancedb/lancedb apache-arrow --legacy-peer-deps --silent 2>/dev/null
  node -e "require('@lancedb/lancedb'); console.log('  LanceDB loaded OK ✓')" || {
    echo "  ERROR: LanceDB failed to load. You may need to build from source:"
    echo "    npm install @lancedb/lancedb --build-from-source --legacy-peer-deps"
    exit 1
  }
fi

# Smart dist patching — auto-skip when stock already supports baseUrl
echo "[4/4] Checking if dist schema patching is needed..."

NEEDS_PATCH=false
PATCHED=0

# Detection: check if any dist/manager-*.js still has the old enum restriction
# Newer OpenClaw uses "type":"string" for model and supports baseUrl — if we see
# the old enum, this is an older version that needs patching
for f in dist/manager-*.js; do
  [ -f "$f" ] || continue
  if grep -q '"enum":\["text-embedding-3-small","text-embedding-3-large"\]' "$f" 2>/dev/null; then
    NEEDS_PATCH=true
    break
  fi
done

if [ "$NEEDS_PATCH" = true ]; then
  echo "  Older OpenClaw detected — applying dist patches..."
  for f in dist/manager-*.js; do
    [ -f "$f" ] || continue
    if grep -q "text-embedding-3-small" "$f" 2>/dev/null; then
      # Replace model enum with generic string type
      sedi 's/"enum":\["text-embedding-3-small","text-embedding-3-large"\]/"type":"string"/g' "$f"
      # Add baseUrl and dimensions to schema properties
      sedi 's/"additionalProperties":false,"properties":{"apiKey":{"type":"string"},"model"/"properties":{"apiKey":{"type":"string"},"baseUrl":{"type":"string"},"dimensions":{"type":"number"},"model"/g' "$f"
      # Remove required apiKey constraint (allows "ollama" placeholder)
      sedi 's/"required":\["apiKey"\]/"required":[]/g' "$f"
      PATCHED=$((PATCHED + 1))
    fi
  done
  echo "  Patched $PATCHED dist file(s) ✓"
else
  echo "  Stock already supports baseUrl/dimensions — dist patch SKIPPED ✓"
fi

# Verify
echo ""
echo "==========================================="
echo "  Installation complete"
echo "==========================================="
echo ""
echo "Custom features active:"
echo "  ✓ Multi-agent memory isolation (agentId)"
echo "  ✓ Extended embedding model support (12+ models)"
echo "  ✓ Graceful 768-dim fallback for unknown models"
echo "  ✓ Environment variable resolution (\${ENV_VAR})"
echo "  ✓ Explicit dimensions override"
if [ "$NEEDS_PATCH" = true ]; then
  echo "  ✓ Dist schema patched for older OpenClaw"
else
  echo "  ✓ No dist patch needed (stock supports baseUrl/dimensions)"
fi
echo ""
echo "Example config for ~/.openclaw/openclaw.json:"
echo ""
echo '  "plugins": {'
echo '    "slots": { "memory": "memory-lancedb" },'
echo '    "entries": {'
echo '      "memory-lancedb": {'
echo '        "enabled": true,'
echo '        "config": {'
echo '          "embedding": {'
echo '            "apiKey": "ollama",'
echo '            "model": "nomic-embed-text-v2-moe",'
echo '            "baseUrl": "http://localhost:11434/v1",'
echo '            "dimensions": 768'
echo '          },'
echo '          "autoCapture": false,'
echo '          "autoRecall": false'
echo '        }'
echo '      }'
echo '    }'
echo '  }'
echo ""
echo "Then: openclaw gateway restart"
