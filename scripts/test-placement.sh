#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${DANTE_APP_PATH:-$ROOT/build/final/Dante Live.app}"
mkdir -p build/tests evidence/runtime
xcrun clang++ -std=c++17 -fobjc-arc -O2 -target "$(uname -m)-apple-macos14.0" \
 -I vendor/obs-studio/libobs -I vendor/simde -I build/generated -I Sources/Bridge \
 -F "$APP/Contents/Frameworks" Sources/Bridge/DanteEngine.mm Tests/SourcePlacement.mm \
 -framework AppKit -framework Foundation -framework VideoToolbox -framework libobs \
 -Wl,-rpath,"$APP/Contents/Frameworks" -o build/tests/SourcePlacement
codesign --force --sign - build/tests/SourcePlacement
build/tests/SourcePlacement "$APP" "$ROOT/evidence/runtime/source-placement.json"
