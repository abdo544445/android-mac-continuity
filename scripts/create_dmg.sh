#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(cat "$WORKSPACE_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
APP_VERSION="${APP_VERSION:-1.0.3}"
DIST_DIR="$WORKSPACE_DIR/dist"
APP_BUNDLE="$DIST_DIR/ContinuityCompanion.app"
DMG_NAME="ContinuityCompanion-macOS-v$APP_VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGE_DIR="$DIST_DIR/dmg_staging"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: $APP_BUNDLE does not exist. Run 'make build-macos' first."
    exit 1
fi

echo "📦 Creating macOS GUI Installer Disk Image ($DMG_NAME)..."

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

# Copy the app bundle
cp -R "$APP_BUNDLE" "$STAGE_DIR/ContinuityCompanion.app"

# Strip quarantine and extended attributes from stage
xattr -cr "$STAGE_DIR/ContinuityCompanion.app" 2>/dev/null || true

# Re-sign with ad-hoc signature
codesign --force --deep --sign - "$STAGE_DIR/ContinuityCompanion.app" 2>/dev/null || true

# Create symlink to /Applications for standard drag-and-drop installation
ln -s /Applications "$STAGE_DIR/Applications"

# Create compressed UDZO DMG
hdiutil create \
    -volname "Continuity Companion" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Also create generic alias ContinuityCompanion.dmg
cp "$DMG_PATH" "$DIST_DIR/ContinuityCompanion.dmg"

# Sign the DMG image as well
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true
codesign --force --sign - "$DIST_DIR/ContinuityCompanion.dmg" 2>/dev/null || true

# Cleanup staging
rm -rf "$STAGE_DIR"

echo "✅ DMG Installer created successfully:"
echo "   $DMG_PATH"
echo "   $DIST_DIR/ContinuityCompanion.dmg"
