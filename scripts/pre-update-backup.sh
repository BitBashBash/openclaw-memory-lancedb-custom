#!/usr/bin/env bash
# =============================================================================
# OpenClaw Pre-Update Backup
# Run this BEFORE openclaw update or custom plugin changes
# Creates a timestamped snapshot of everything needed for rollback
# =============================================================================
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/backups/openclaw-$TIMESTAMP"

# Auto-detect OpenClaw install path
if [ -d "$HOME/.npm-global/lib/node_modules/openclaw" ]; then
  OC_DIR="$HOME/.npm-global/lib/node_modules/openclaw"
elif [ -d "/opt/homebrew/lib/node_modules/openclaw" ]; then
  OC_DIR="/opt/homebrew/lib/node_modules/openclaw"
elif [ -d "/usr/local/lib/node_modules/openclaw" ]; then
  OC_DIR="/usr/local/lib/node_modules/openclaw"
else
  OC_DIR="$(npm root -g)/openclaw"
fi

PLUGIN_DIR="$OC_DIR/extensions/memory-lancedb"
CONFIG_DIR="$HOME/.openclaw"
CUSTOM_REPO="$HOME/openclaw-memory-lancedb-custom"

echo "=== OpenClaw Pre-Update Backup ==="
echo "Timestamp: $TIMESTAMP"
echo "Backup dir: $BACKUP_DIR"
echo ""

mkdir -p "$BACKUP_DIR"

# 1. OpenClaw version
echo "[1/6] Recording OpenClaw version..."
openclaw --version 2>&1 | head -1 > "$BACKUP_DIR/openclaw-version.txt"
echo "  $(cat "$BACKUP_DIR/openclaw-version.txt")"

# 2. Plugin source files (the ones we're about to overwrite)
echo "[2/6] Backing up current plugin files..."
mkdir -p "$BACKUP_DIR/plugin"
for f in index.ts config.ts openclaw.plugin.json package.json; do
  if [ -f "$PLUGIN_DIR/$f" ]; then
    cp "$PLUGIN_DIR/$f" "$BACKUP_DIR/plugin/$f"
    echo "  $f ✓"
  fi
done
# Also grab any .original files from previous installs
for f in "$PLUGIN_DIR"/*.original; do
  [ -f "$f" ] && cp "$f" "$BACKUP_DIR/plugin/" && echo "  $(basename "$f") ✓"
done

# 3. Dist files (the ones that get sed-patched)
echo "[3/6] Backing up dist manager files..."
mkdir -p "$BACKUP_DIR/dist"
DIST_COUNT=0
for f in "$OC_DIR"/dist/manager-*.js; do
  [ -f "$f" ] || continue
  cp "$f" "$BACKUP_DIR/dist/"
  DIST_COUNT=$((DIST_COUNT + 1))
done
echo "  $DIST_COUNT dist file(s) ✓"

# 4. OpenClaw config
echo "[4/6] Backing up openclaw.json..."
mkdir -p "$BACKUP_DIR/config"
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
  cp "$CONFIG_DIR/openclaw.json" "$BACKUP_DIR/config/openclaw.json"
  echo "  openclaw.json ✓"
fi
# Agent workspaces (just the .md files, not the full workspace)
for ws in workspace personal pf-support; do
  WS_DIR="$CONFIG_DIR/$ws"
  if [ -d "$WS_DIR" ]; then
    mkdir -p "$BACKUP_DIR/config/$ws"
    find "$WS_DIR" -maxdepth 1 -name "*.md" -exec cp {} "$BACKUP_DIR/config/$ws/" \;
    echo "  $ws/*.md ✓"
  fi
done

# 5. LanceDB data (the actual vector memories)
echo "[5/6] Backing up LanceDB data..."
LANCE_DIR="$CONFIG_DIR/memory/lancedb"
if [ -d "$LANCE_DIR" ]; then
  mkdir -p "$BACKUP_DIR/lancedb"
  cp -r "$LANCE_DIR"/* "$BACKUP_DIR/lancedb/" 2>/dev/null || true
  LANCE_SIZE=$(du -sh "$BACKUP_DIR/lancedb" 2>/dev/null | cut -f1)
  echo "  LanceDB data: $LANCE_SIZE ✓"
else
  echo "  No LanceDB data found (first run?)"
fi

# 6. Custom repo state
echo "[6/6] Recording custom repo state..."
if [ -d "$CUSTOM_REPO/.git" ]; then
  cd "$CUSTOM_REPO"
  git rev-parse HEAD > "$BACKUP_DIR/custom-repo-commit.txt"
  git status --short > "$BACKUP_DIR/custom-repo-status.txt" 2>/dev/null || true
  echo "  Commit: $(cat "$BACKUP_DIR/custom-repo-commit.txt")"
else
  echo "  Custom repo not found at $CUSTOM_REPO (skip)"
fi

# Summary
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
echo ""
echo "==========================================="
echo "  Backup complete: $BACKUP_DIR"
echo "  Total size: $TOTAL_SIZE"
echo "==========================================="
echo ""
echo "To restore if things go south:"
echo ""
echo "  # Restore plugin files"
echo "  cp $BACKUP_DIR/plugin/* $PLUGIN_DIR/"
echo ""
echo "  # Restore dist files"
echo "  cp $BACKUP_DIR/dist/* $OC_DIR/dist/"
echo ""
echo "  # Restore config"
echo "  cp $BACKUP_DIR/config/openclaw.json $CONFIG_DIR/"
echo ""
echo "  # Restore LanceDB data"
echo "  cp -r $BACKUP_DIR/lancedb/* $LANCE_DIR/"
echo ""
echo "  # Restart"
echo "  openclaw gateway restart"
