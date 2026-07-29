#!/bin/bash
# Build DockPeek and assemble the distributable dock-preview.app bundle.
#
# SwiftPM produces a bare executable, but macOS privacy permissions (Accessibility,
# Screen Recording) key off a real app bundle with a stable bundle identifier and
# code signature. This script wraps the built binary in dock-preview.app and ad-hoc
# signs it so TCC has a stable identity to remember. The result sits in the project
# root and launches on double-click.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
TARGET_BIN="DockPeek"          # SwiftPM product name
APP_NAME="dock-preview"        # shipped bundle / executable name
BUILD_DIR=".build/${CONFIG}"
APP="${APP_NAME}.app"

echo "▶︎ Compiling (${CONFIG})…"
swift build -c "${CONFIG}"

echo "▶︎ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "${BUILD_DIR}/${TARGET_BIN}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"
[ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

# Prefer a stable Developer ID identity so macOS privacy grants (Accessibility,
# Screen Recording) survive rebuilds — ad-hoc changes the cdhash every build, which
# silently invalidates the permission and makes the app ask again. Override with
# SIGN_ID="…"; set SIGN_ID="-" to force ad-hoc.
if [ -z "${SIGN_ID:-}" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
SIGN_ID="${SIGN_ID:--}"

if [ "${SIGN_ID}" = "-" ]; then
    echo "▶︎ Ad-hoc code signing (grants won't persist across rebuilds)…"
    codesign --force --deep --sign - "${APP}"
else
    echo "▶︎ Code signing with: ${SIGN_ID}"
    codesign --force --deep --options runtime --sign "${SIGN_ID}" "${APP}"
fi

# Make sure a freshly built local app isn't Gatekeeper-quarantined.
xattr -dr com.apple.quarantine "${APP}" 2>/dev/null || true

echo "✓ Built ${APP}"
echo
echo "Run it:  open ./${APP}   (or double-click dock-preview.app in Finder)"
echo "First launch walks you through granting Accessibility + Screen Recording."
