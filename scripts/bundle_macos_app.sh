#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ContinuityCompanion"
APP_VERSION="$(cat "$WORKSPACE_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
APP_VERSION="${APP_VERSION:-1.0.4}"
DIST_DIR="$WORKSPACE_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Bundling $APP_NAME.app into $DIST_DIR..."

# Build the latest SPM product executable
cd "$WORKSPACE_DIR/apps/macos"
swift build --product "$APP_NAME"

# Locate the compiled binary
SHOW_BIN="$(swift build --show-bin-path 2>/dev/null)"
if [ -n "$SHOW_BIN" ] && [ -f "$SHOW_BIN/$APP_NAME" ]; then
    BIN_PATH="$SHOW_BIN/$APP_NAME"
elif [ -f "$WORKSPACE_DIR/apps/macos/.build/arm64-apple-macosx/debug/$APP_NAME" ]; then
    BIN_PATH="$WORKSPACE_DIR/apps/macos/.build/arm64-apple-macosx/debug/$APP_NAME"
elif [ -f "$WORKSPACE_DIR/apps/macos/.build/debug/$APP_NAME" ]; then
    BIN_PATH="$WORKSPACE_DIR/apps/macos/.build/debug/$APP_NAME"
else
    BIN_PATH="$(find "$WORKSPACE_DIR/apps/macos/.build" -type f -name "$APP_NAME" 2>/dev/null | head -n 1)"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Error: Could not find compiled binary at $BIN_PATH"
    exit 1
fi

# Clean and recreate .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

if [ -f "$WORKSPACE_DIR/resources/AppIcon.icns" ]; then
    cp "$WORKSPACE_DIR/resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy binary
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Create Info.plist
cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Continuity Companion</string>
    <key>CFBundleExecutable</key>
    <string>ContinuityCompanion</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.continuity.macos.companion</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Continuity Companion</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_continuity._tcp</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Continuity requires access to your local network to discover and connect with paired Android devices.</string>
</dict>
</plist>
EOF

# Copy CLI binary to dist as well for easy access
CLI_PATH="$WORKSPACE_DIR/apps/macos/.build/arm64-apple-macosx/debug/ContinuityCLI"
if [ ! -f "$CLI_PATH" ]; then
    CLI_PATH="$WORKSPACE_DIR/apps/macos/.build/debug/ContinuityCLI"
fi
if [ -f "$CLI_PATH" ]; then
    cp "$CLI_PATH" "$DIST_DIR/ContinuityCLI"
    chmod +x "$DIST_DIR/ContinuityCLI"
fi

# Strip quarantine and extended attributes, then ad-hoc codesign the bundle
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully created: $APP_BUNDLE"
