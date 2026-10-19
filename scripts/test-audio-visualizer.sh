#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="$(uname -m)"
BUILD="${DANTE_BUILD_DIR:-$PWD/build}"
APP="${DANTE_APP_PATH:-$BUILD/Dante Live.app}"
mkdir -p "$BUILD/tests" "$BUILD/generated"
xcrun clang++ Tests/AudioVisualizerNative.mm "$BUILD/objects/DanteEngine-$ARCH.o" \
  -std=c++17 -fobjc-arc -O1 -target "$ARCH-apple-macos14.0" \
  -I Sources/Bridge -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" \
  -F "$APP/Contents/Frameworks" -framework LiveKitWebRTC -framework libobs \
  -framework AppKit -framework VideoToolbox -Wl,-rpath,"$APP/Contents/Frameworks" \
  -o "$BUILD/tests/AudioVisualizerNative"
"$BUILD/tests/AudioVisualizerNative" "$APP"
