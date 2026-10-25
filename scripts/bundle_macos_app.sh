#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ContinuityCompanion"
DIST_DIR="$WORKSPACE_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Bundling $APP_NAME.app into $DIST_DIR..."

# Build the latest SPM binary
cd "$WORKSPACE_DIR/apps/macos"
swift build --target "$APP_NAME"

# Locate the compiled binary
BIN_PATH="$WORKSPACE_DIR/apps/macos/.build/arm64-apple-macosx/debug/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$WORKSPACE_DIR/apps/macos/.build/debug/$APP_NAME"
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
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

# Ad-hoc codesign the bundle for macOS Gatekeeper compatibility
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully created: $APP_BUNDLE"
