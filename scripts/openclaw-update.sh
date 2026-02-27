#!/usr/bin/env bash
# =============================================================================
# OpenClaw Update — Full Pipeline
# Backs up → updates core → pulls custom plugin → re-applies → restarts
# Usage: ~/scripts/openclaw-update.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$HOME/openclaw-memory-lancedb-custom"
BACKUP_SCRIPT="$HOME/scripts/pre-update-backup.sh"

echo "=== OpenClaw Full Update Pipeline ==="
echo ""

# 1. Pre-update backup
echo "[1/5] Running pre-update backup..."
if [ -x "$BACKUP_SCRIPT" ]; then
  "$BACKUP_SCRIPT"
else
  echo "  WARN: $BACKUP_SCRIPT not found or not executable — skipping backup"
fi
echo ""

# 2. Update core
OLD_VER=$(openclaw --version 2>&1 | tr -d '[:space:]')
echo "[2/5] Updating OpenClaw (current: $OLD_VER)..."
openclaw update --no-restart --yes
# Re-hash so shell picks up the new binary
hash -r 2>/dev/null || true
NEW_VER=$(openclaw --version 2>&1 | tr -d '[:space:]')
echo "  $OLD_VER → $NEW_VER"
echo ""

# 3. Pull latest custom plugin
echo "[3/5] Pulling custom plugin repo..."
if [ -d "$REPO_DIR/.git" ]; then
  cd "$REPO_DIR" && git pull --ff-only
else
  echo "  WARN: $REPO_DIR not a git repo — using local files as-is"
fi
echo ""

# 4. Re-apply custom plugin
echo "[4/5] Re-applying custom LanceDB plugin..."
cd "$REPO_DIR"
chmod +x install.sh
./install.sh
echo ""

# 5. Restart
echo "[5/5] Restarting gateway..."
openclaw gateway restart
echo ""

# Extract plugin version from package.json (cross-platform, no grep -P)
PLUGIN_VER=$(sed -n 's/.*"version".*"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -1)

echo "=== Update Complete ==="
echo "  OpenClaw: $OLD_VER → $NEW_VER"
echo "  Plugin: custom LanceDB (v${PLUGIN_VER:-unknown})"
echo ""
echo "Verify: openclaw status"
echo "Logs:   openclaw logs --follow"
