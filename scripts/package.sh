#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DANTE_BUILD_DIR="${DANTE_BUILD_DIR:-build}"
[[ "$DANTE_BUILD_DIR" == /* ]] || DANTE_BUILD_DIR="$ROOT/$DANTE_BUILD_DIR"
APP="$DANTE_BUILD_DIR/Dante Live.app"
[[ -x "$APP/Contents/MacOS/DanteLive" ]] || { echo 'Build app first.' >&2; exit 1; }
python3 packaging/runtime.py audit
codesign --verify --deep --strict "$APP"
python3 packaging/package.py
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
hdiutil create -volname "Dante Live $VERSION" -srcfolder "$DANTE_BUILD_DIR/distribution-stage" -ov -format UDZO "dist/Dante-Live-$VERSION-local.dmg"
hdiutil verify "dist/Dante-Live-$VERSION-local.dmg"
shasum -a 256 "dist/Dante-Live-$VERSION-local.dmg" "dist/Dante-Live-$VERSION-source-preparation.zip" > dist/SHA256SUMS.txt
echo 'Local distribution prepared; notarization status must be verified separately.'
