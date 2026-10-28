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

# Derive build number (e.g. 1.0.4 -> 4)
BUILD_NUM=$(echo "$REL_VERSION" | awk -F. '{print ($1*100) + ($2*10) + $3}')
if [ -z "$BUILD_NUM" ] || [ "$BUILD_NUM" -le 0 ]; then
    BUILD_NUM=4
fi

# Sync version into Android build.gradle.kts and SettingsScreen.kt
sed -i '' "s/versionCode = [0-9]*/versionCode = $BUILD_NUM/" apps/android/app/build.gradle.kts
sed -i '' "s/versionName = \".*\"/versionName = \"$REL_VERSION\"/" apps/android/app/build.gradle.kts
sed -i '' "s/text = \"v[0-9.]* (Build [0-9]*)\"/text = \"v$REL_VERSION (Build $BUILD_NUM)\"/" apps/android/app/src/main/java/com/continuity/ecosystem/ui/screens/SettingsScreen.kt

# Build both platforms
make build-macos
make build-android

# Create version-mapped release artifacts in dist/
APK_OUT="dist/Continuity-Android-v$REL_VERSION.apk"
MAC_DMG="dist/ContinuityCompanion-macOS-v$REL_VERSION.dmg"
MAC_ZIP="dist/ContinuityCompanion-macOS-v$REL_VERSION.zip"

if [ -f "dist/app-release.apk" ]; then
    cp dist/app-release.apk "$APK_OUT"
else
    cp dist/app-debug.apk "$APK_OUT"
fi

# Generate GUI DMG Installer and Gatekeeper-friendly ZIP package
./scripts/create_dmg.sh
./scripts/create_zip.sh

echo "📦 Created versioned assets:"
echo "  - $APK_OUT"
echo "  - $MAC_DMG"
echo "  - $MAC_ZIP"

# Git Commit & Tag
git add .
git commit -m "chore(release): bump version to v$REL_VERSION: $REL_NOTES" || true
git tag -fa "v$REL_VERSION" -m "Release v$REL_VERSION"
git push origin main --tags || true

# GitHub Release Creation
if command -v gh >/dev/null 2>&1; then
    echo "🚀 Publishing release to GitHub..."
    gh release create "v$REL_VERSION" \
        "$APK_OUT" \
        "$MAC_DMG" \
        "$MAC_ZIP" \
        --title "Continuity v$REL_VERSION" \
        --notes "$REL_NOTES" || echo "gh release create failed or release already exists"
fi

echo "🎉 Release v$REL_VERSION published successfully!"
