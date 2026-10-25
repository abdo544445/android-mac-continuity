#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_DIR"

REL_VERSION="${1:-$(cat VERSION | tr -d '[:space:]')}"
REL_NOTES="${2:-Release v$REL_VERSION}"

if [ -z "$REL_VERSION" ]; then
    echo "❌ Error: Version not specified and VERSION file is empty."
    exit 1
fi

echo "$REL_VERSION" > VERSION
echo "🚀 Preparing Release v$REL_VERSION..."

# Sync version into Android build.gradle.kts and SettingsScreen.kt
sed -i '' "s/versionName = \".*\"/versionName = \"$REL_VERSION\"/" apps/android/app/build.gradle.kts
sed -i '' "s/text = \"v[0-9.]* (/text = \"v$REL_VERSION (/" apps/android/app/src/main/java/com/continuity/ecosystem/ui/screens/SettingsScreen.kt

# Build both platforms
make build-macos
make build-android

# Create version-mapped release artifacts in dist/
APK_OUT="dist/Continuity-Android-v$REL_VERSION.apk"
MAC_ZIP="dist/ContinuityCompanion-macOS-v$REL_VERSION.zip"

cp dist/app-debug.apk "$APK_OUT"
cd dist
rm -f "ContinuityCompanion-macOS-v$REL_VERSION.zip"
zip -r -y "ContinuityCompanion-macOS-v$REL_VERSION.zip" ContinuityCompanion.app
cd "$WORKSPACE_DIR"

echo "📦 Created versioned assets:"
echo "  - $APK_OUT"
echo "  - $MAC_ZIP"
