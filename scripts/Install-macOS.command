#!/bin/bash
# ==============================================================================
# Continuity Companion - macOS One-Click Installer & Dependency Launcher
# ==============================================================================

set -e

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ContinuityCompanion.app"
SOURCE_APP="$SCRIPT_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

clear
echo -e "${BOLD}${BLUE}======================================================${NC}"
echo -e "${BOLD}${BLUE}   Continuity Companion - macOS Setup & Launcher       ${NC}"
echo -e "${BOLD}${BLUE}======================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# 1. Dependency Check: Homebrew, scrcpy, adb
# ------------------------------------------------------------------------------
echo -e "${BOLD}Step 1/4: Checking Mirroring & ADB Dependencies...${NC}"

# Detect Homebrew path
if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if command -v brew >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Homebrew detected."

    # Check for ADB
    if command -v adb >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Android ADB detected at $(which adb)"
    else
        echo -e "  ${YELLOW}!${NC} Installing android-platform-tools (ADB)..."
        brew install --cask android-platform-tools || brew install android-platform-tools || true
    fi

    # Check for scrcpy (60fps ultra-low latency mirroring)
    if command -v scrcpy >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} scrcpy detected at $(which scrcpy)"
    else
        echo -e "  ${YELLOW}!${NC} Installing scrcpy (for 60fps screen mirroring)..."
        brew install scrcpy || true
    fi
else
    echo -e "  ${YELLOW}! Homebrew is not installed.${NC}"
    echo -e "    Continuity will use built-in high-speed wireless mirror engine."
    echo -e "    (To enable optional 60fps scrcpy mirror, install Homebrew from https://brew.sh)"
fi

echo ""

# ------------------------------------------------------------------------------
# 2. Locate App Bundle
# ------------------------------------------------------------------------------
echo -e "${BOLD}Step 2/4: Locating Application Bundle...${NC}"

if [ ! -d "$SOURCE_APP" ]; then
    # Check parent directory or dist
    if [ -d "$SCRIPT_DIR/dist/$APP_NAME" ]; then
        SOURCE_APP="$SCRIPT_DIR/dist/$APP_NAME"
    elif [ -d "$SCRIPT_DIR/../dist/$APP_NAME" ]; then
        SOURCE_APP="$SCRIPT_DIR/../dist/$APP_NAME"
    elif [ -d "/Applications/$APP_NAME" ]; then
        SOURCE_APP="/Applications/$APP_NAME"
    fi
fi

if [ ! -d "$SOURCE_APP" ]; then
    echo -e "  ${RED}✗ Error: Could not find $APP_NAME next to this installer.${NC}"
    echo "    Please make sure $APP_NAME and Install-macOS.command are in the same folder."
    read -p "Press [Enter] to exit..."
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Found source: $SOURCE_APP"
echo ""

# ------------------------------------------------------------------------------
# 3. Install to /Applications
# ------------------------------------------------------------------------------
echo -e "${BOLD}Step 3/4: Installing to /Applications...${NC}"

# Kill any running instances first
pkill -f "ContinuityCompanion" >/dev/null 2>&1 || true
sleep 0.5

if [ "$SOURCE_APP" != "$TARGET_APP" ]; then
    rm -rf "$TARGET_APP"
    cp -R "$SOURCE_APP" "$TARGET_APP"
    echo -e "  ${GREEN}✓${NC} Copied to $TARGET_APP"
else
    echo -e "  ${GREEN}✓${NC} Already located in /Applications"
fi

# ------------------------------------------------------------------------------
# 4. Remove Gatekeeper Quarantine & Re-sign
# ------------------------------------------------------------------------------
echo -e "${BOLD}Step 4/4: Bypassing macOS Gatekeeper Quarantine...${NC}"

# Strip quarantine attributes downloaded by browser/macOS Gatekeeper
xattr -cr "$TARGET_APP" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Stripped com.apple.quarantine attribute"

# Re-sign with ad-hoc signature so macOS Gatekeeper approves execution
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$TARGET_APP" >/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} Applied valid ad-hoc code signature"
fi

echo ""
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo -e "${BOLD}${GREEN}   Installation Successful! Launching Continuity...   ${NC}"
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo ""

open "$TARGET_APP"
sleep 1
exit 0
