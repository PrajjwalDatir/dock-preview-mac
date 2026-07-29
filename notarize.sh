#!/bin/bash
# Notarize dock-preview.app for distribution outside the App Store.
#
# build.sh already produces a fully Developer-ID-signed, hardened-runtime,
# timestamped bundle (including the embedded, individually-signed Sparkle.framework),
# so this script does NOT re-sign — it just zips, submits to Apple, and staples.
#
# One-time setup (stores an app-specific password in the keychain):
#   xcrun notarytool store-credentials "DockPeek" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Then:
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   ./notarize.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: … (TEAMID)' identity}"
PROFILE="${NOTARY_PROFILE:-DockPeek}"
APP="dock-preview.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ZIP="dist/dock-preview-${VERSION}.zip"

echo "▶︎ Building signed bundle…"
SIGN_ID="${DEVELOPER_ID}" ./build.sh

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "▶︎ Submitting to Apple notary service (a few minutes)…"
xcrun notarytool submit "${ZIP}" --keychain-profile "${PROFILE}" --wait

echo "▶︎ Stapling ticket into the app…"
xcrun stapler staple "${APP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "✓ Notarized & stapled: ${ZIP}"
