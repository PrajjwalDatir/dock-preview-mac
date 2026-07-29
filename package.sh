#!/bin/bash
# Package dock-preview.app into a distributable .zip and .dmg (in dist/).
# Run ./build.sh first (or this script will do it for you).
set -euo pipefail
cd "$(dirname "$0")"

APP="dock-preview.app"
DIST="dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0.1.0)"

[ -d "${APP}" ] || ./build.sh
mkdir -p "${DIST}"

echo "▶︎ Zipping…"
ZIP="${DIST}/dock-preview-${VERSION}.zip"
rm -f "${ZIP}"
# ditto preserves the bundle + code signature correctly (unlike plain zip).
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
echo "  ${ZIP}"

echo "▶︎ Building DMG…"
DMG="${DIST}/dock-preview-${VERSION}.dmg"
rm -f "${DMG}"
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install target
hdiutil create -volname "DockPeek" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"
echo "  ${DMG}"

echo "✓ Packaged version ${VERSION} into ${DIST}/"
