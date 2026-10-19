#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ $# == 1 ]] || { echo 'Usage: bash scripts/release.sh /absolute/path/release-notes.txt'; exit 1; }
NOTES="$1"
[[ -f "$NOTES" ]] || exit 1
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo 'Use the clean public main checkout.'; exit 1; }
: "${DANTE_SIGN_IDENTITY:?Set a local Developer ID Application identity}"
: "${DANTE_NOTARY_PROFILE:?Set a local notarytool Keychain profile name}"
[[ "$DANTE_SIGN_IDENTITY" != - ]] || { echo 'Official releases require Developer ID signing.'; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
export DANTE_BUILD_DIR="${DANTE_BUILD_DIR:-build/release-$VERSION}"
bash scripts/build.sh
bash scripts/test-app.sh
DANTE_APP_PATH="$ROOT/$DANTE_BUILD_DIR/Dante Live.app"
[[ "$DANTE_BUILD_DIR" != /* ]] || DANTE_APP_PATH="$DANTE_BUILD_DIR/Dante Live.app"
DANTE_APP_PATH="$DANTE_APP_PATH" bash scripts/test-capture.sh
DANTE_BUILD_DIR="$ROOT/build/chat-qa" DANTE_APP_PATH="$DANTE_APP_PATH" bash scripts/test-chat.sh
DANTE_APP_PATH="$DANTE_APP_PATH" bash scripts/test-browser-tab-audio.sh
DANTE_APP_PATH="$DANTE_APP_PATH" bash scripts/test-scene-graphics.sh
python3 packaging/notarize.py --app "$DANTE_BUILD_DIR/Dante Live.app"
bash scripts/package.sh
python3 packaging/notarize.py --dmg "dist/Dante-Live-$VERSION-local.dmg"
python3 packaging/source-inventory.py --download
python3 packaging/source-bundle.py
python3 scripts/publish-release.py --dmg "dist/Dante-Live-$VERSION-local.dmg" \
  --source "dist/Dante-Live-$VERSION-corresponding-source.zip" --notes "$NOTES"
