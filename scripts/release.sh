#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ $# == 1 ]] || { echo 'Usage: bash scripts/release.sh /absolute/path/release-notes.txt'; exit 1; }
NOTES="$1"
[[ -f "$NOTES" ]] || exit 1
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo 'Use the clean public main checkout.'; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
export DANTE_BUILD_DIR="${DANTE_BUILD_DIR:-build/release-$VERSION}"
bash scripts/build.sh
bash scripts/test-app.sh
bash scripts/package.sh
python3 packaging/source-inventory.py --download
python3 packaging/source-bundle.py
python3 scripts/publish-release.py --dmg "dist/Dante-Live-$VERSION-local.dmg" \
  --source "dist/Dante-Live-$VERSION-corresponding-source.zip" --notes "$NOTES"
