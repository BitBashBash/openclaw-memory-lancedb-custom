#!/usr/bin/env bash
# =============================================================================
# OpenClaw Update — Full Pipeline
# Backs up → updates core → upgrades lossless-claw → pulls custom plugin →
# re-applies → restarts
# Usage: ~/scripts/openclaw-update.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$HOME/openclaw-memory-lancedb-custom"
BACKUP_SCRIPT="$HOME/scripts/pre-update-backup.sh"
LCM_EXT_DIR="$HOME/.openclaw/extensions/lossless-claw"
LCM_BACKUP_DIR="$HOME/backups"
LCM_PACKAGE="@martian-engineering/lossless-claw"

echo "=== OpenClaw Full Update Pipeline ==="
echo ""

# 1. Pre-update backup
echo "[1/6] Running pre-update backup..."
if [ -x "$BACKUP_SCRIPT" ]; then
  "$BACKUP_SCRIPT"
else
  echo "  WARN: $BACKUP_SCRIPT not found or not executable — skipping backup"
fi
echo ""

# 2. Update core
OLD_VER=$(openclaw --version 2>&1 | tr -d '[:space:]')
echo "[2/6] Updating OpenClaw (current: $OLD_VER)..."
openclaw update --no-restart --yes
# Re-hash so shell picks up the new binary
hash -r 2>/dev/null || true
NEW_VER=$(openclaw --version 2>&1 | tr -d '[:space:]')
echo "  $OLD_VER → $NEW_VER"
echo ""

# 3. Upgrade lossless-claw plugin from npm
echo "[3/6] Checking lossless-claw plugin..."
OLD_LCM_VER="unknown"
if [ -f "$LCM_EXT_DIR/package.json" ]; then
  OLD_LCM_VER=$(sed -n 's/.*"version".*"\([^"]*\)".*/\1/p' "$LCM_EXT_DIR/package.json" | head -1)
fi
NEW_LCM_VER=$(npm view "$LCM_PACKAGE" version 2>/dev/null || echo "")
if [ -z "$NEW_LCM_VER" ]; then
  echo "  WARN: could not query npm for $LCM_PACKAGE — skipping upgrade"
elif [ "$OLD_LCM_VER" = "$NEW_LCM_VER" ]; then
  echo "  lossless-claw already at v$NEW_LCM_VER — no change"
else
  echo "  lossless-claw: v$OLD_LCM_VER → v$NEW_LCM_VER"
  STAMP=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$LCM_BACKUP_DIR"
  if [ -d "$LCM_EXT_DIR" ]; then
    # Move old version outside ~/.openclaw/extensions/ — OpenClaw scans that
    # tree and treats every subdir with a plugin manifest as registered, so a
    # backup left in place triggers a duplicate-id warning on boot.
    mv "$LCM_EXT_DIR" "$LCM_BACKUP_DIR/lossless-claw-v${OLD_LCM_VER}.bak-${STAMP}"
    echo "  backed up old version to $LCM_BACKUP_DIR/lossless-claw-v${OLD_LCM_VER}.bak-${STAMP}"
  fi
  mkdir -p "$LCM_EXT_DIR"
  TARBALL=$(npm view "$LCM_PACKAGE@$NEW_LCM_VER" dist.tarball 2>/dev/null || echo "")
  if [ -z "$TARBALL" ]; then
    echo "  ERROR: could not resolve tarball URL for $LCM_PACKAGE@$NEW_LCM_VER"
    exit 1
  fi
  TMP_TGZ=$(mktemp --suffix=.tgz)
  trap 'rm -f "$TMP_TGZ"' EXIT
  curl -fsSL "$TARBALL" -o "$TMP_TGZ"
  tar -xzf "$TMP_TGZ" -C "$LCM_EXT_DIR" --strip-components=1
  rm -f "$TMP_TGZ"
  trap - EXIT
  (cd "$LCM_EXT_DIR" && npm install --omit=dev --no-audit --no-fund --silent)
  echo "  lossless-claw v$NEW_LCM_VER installed"
fi
echo ""

# 4. Pull latest custom LanceDB plugin
echo "[4/6] Pulling custom plugin repo..."
if [ -d "$REPO_DIR/.git" ]; then
  cd "$REPO_DIR" && git pull --ff-only
else
  echo "  WARN: $REPO_DIR not a git repo — using local files as-is"
fi
echo ""

# 5. Re-apply custom LanceDB plugin
echo "[5/6] Re-applying custom LanceDB plugin..."
cd "$REPO_DIR"
chmod +x install.sh scripts/*.sh 2>/dev/null || true
./install.sh
echo ""

# 6. Restart
echo "[6/6] Restarting gateway..."
openclaw gateway restart
echo ""

# Extract LanceDB plugin version from package.json (cross-platform, no grep -P)
PLUGIN_VER=$(sed -n 's/.*"version".*"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -1)
FINAL_LCM_VER="${NEW_LCM_VER:-$OLD_LCM_VER}"

echo "=== Update Complete ==="
echo "  OpenClaw:       $OLD_VER → $NEW_VER"
echo "  LanceDB plugin: v${PLUGIN_VER:-unknown}"
echo "  lossless-claw:  v${FINAL_LCM_VER}"
echo ""
echo "Verify: openclaw status"
echo "Logs:   openclaw logs --follow"
