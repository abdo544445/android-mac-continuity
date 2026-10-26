#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(cat "$WORKSPACE_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
APP_VERSION="${APP_VERSION:-1.0.4}"
DIST_DIR="$WORKSPACE_DIR/dist"
APP_BUNDLE="$DIST_DIR/ContinuityCompanion.app"
ZIP_NAME="ContinuityCompanion-macOS-v$APP_VERSION.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
STAGE_DIR="$DIST_DIR/zip_staging"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: $APP_BUNDLE does not exist. Run 'make build-macos' first."
    exit 1
fi

echo "📦 Creating Gatekeeper-Friendly ZIP Package ($ZIP_NAME)..."

rm -rf "$STAGE_DIR" "$ZIP_PATH"
mkdir -p "$STAGE_DIR"

# Copy the app bundle
cp -R "$APP_BUNDLE" "$STAGE_DIR/ContinuityCompanion.app"

# Copy non-technical onboarding guide
if [ -f "$WORKSPACE_DIR/resources/How to Open.html" ]; then
    cp "$WORKSPACE_DIR/resources/How to Open.html" "$STAGE_DIR/How to Open.html"
fi

# Create symlink to /Applications for standard drag-and-drop installation
ln -s /Applications "$STAGE_DIR/Applications"

# Strip quarantine and extended attributes from stage, then ad-hoc sign the app in stage
xattr -cr "$STAGE_DIR/ContinuityCompanion.app" 2>/dev/null || true
codesign --force --deep --sign - "$STAGE_DIR/ContinuityCompanion.app" 2>/dev/null || true

# Compress using ditto to preserve macOS bundle permissions, resource forks, and symlinks
cd "$STAGE_DIR"
ditto -c -k --keepParent "ContinuityCompanion.app" "$ZIP_PATH"
# Also add How to Open.html and Applications symlink into the zip
zip -g -y "$ZIP_PATH" "How to Open.html" "Applications" 2>/dev/null || ditto -c -k . "$ZIP_PATH"
cd "$WORKSPACE_DIR"

# Cleanup staging
rm -rf "$STAGE_DIR"

echo "✅ Gatekeeper-friendly ZIP created successfully:"
echo "   $ZIP_PATH"
