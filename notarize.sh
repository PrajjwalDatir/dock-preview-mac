#!/bin/bash
# Sign with Developer ID + notarize dock-preview.app so other Macs open it without
# Gatekeeper warnings. Requires an Apple Developer account and a stored notary
# profile. This is the D1 distribution step — it CANNOT run with the ad-hoc signature
# ./build.sh produces; you need real credentials.
#
# One-time setup:
#   xcrun notarytool store-credentials "DockPeek" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Set your identity here (from `security find-identity -v -p codesigning`):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
set -euo pipefail
cd "$(dirname "$0")"

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: … (TEAMID)' identity}"
PROFILE="${NOTARY_PROFILE:-DockPeek}"
APP="dock-preview.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ZIP="dist/dock-preview-${VERSION}.zip"

./build.sh   # produces the bundle (ad-hoc); re-sign below with Developer ID

echo "▶︎ Signing with Developer ID (hardened runtime)…"
codesign --force --deep --options runtime --timestamp \
    --sign "${DEVELOPER_ID}" "${APP}"

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "▶︎ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "${ZIP}" --keychain-profile "${PROFILE}" --wait

echo "▶︎ Stapling ticket…"
xcrun stapler staple "${APP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "✓ Notarized & stapled: ${ZIP}"
