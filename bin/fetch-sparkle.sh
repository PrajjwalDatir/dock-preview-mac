#!/bin/bash
# Fetch and vendor Sparkle (the Sparkle.xcframework plus the signing tools) with curl.
#
# We vendor rather than use Sparkle as a remote SwiftPM dependency because SwiftPM's
# binary-artifact downloader is unreliable in some sandboxed/CI environments, whereas
# a plain curl of the release asset is not. Idempotent: no-op if already present.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.9.4"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-for-Swift-Package-Manager.zip"
DEST="Vendor"

if [ -d "${DEST}/Sparkle.xcframework" ] && [ -x "${DEST}/bin/generate_appcast" ]; then
    exit 0
fi

echo "▶︎ Fetching Sparkle ${VERSION}…"
mkdir -p "${DEST}/_dl" "${DEST}/_x"
curl -fsSL -o "${DEST}/_dl/spm.zip" "${URL}"
unzip -q -o "${DEST}/_dl/spm.zip" -d "${DEST}/_x"
rm -rf "${DEST}/Sparkle.xcframework" "${DEST}/bin"
mv "${DEST}/_x/Sparkle.xcframework" "${DEST}/Sparkle.xcframework"
mv "${DEST}/_x/bin" "${DEST}/bin"
rm -rf "${DEST}/_x" "${DEST}/_dl"
echo "✓ Vendored Sparkle into ${DEST}/"
