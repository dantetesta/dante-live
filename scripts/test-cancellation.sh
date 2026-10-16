#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${DANTE_APP_PATH:-$ROOT/build/final/Dante Live.app}"
mkdir -p build/tests evidence/runtime
xcrun clang++ -std=c++17 -fobjc-arc -O2 -target "$(uname -m)-apple-macos14.0" \
 -I vendor/obs-studio/libobs -I vendor/simde -I build/generated -I Sources/Bridge \
 -F "$APP/Contents/Frameworks" Sources/Bridge/DanteEngine.mm Tests/ConnectionCancellation.mm \
 -framework AppKit -framework Foundation -framework VideoToolbox -framework LiveKitWebRTC -framework libobs \
 -Wl,-rpath,"$APP/Contents/Frameworks" -o build/tests/ConnectionCancellation
codesign --force --sign - build/tests/ConnectionCancellation
build/tests/ConnectionCancellation "$APP" "$ROOT/evidence/runtime/connection-cancellation.json"
