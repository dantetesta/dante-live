#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${DANTE_BUILD_DIR:-$ROOT/build}"
[[ "$BUILD" == /* ]] || BUILD="$ROOT/$BUILD"
APP="${DANTE_APP_PATH:-$BUILD/Dante Live.app}"
ARCH="$(uname -m)"
mkdir -p build/tests build/framing-qa
SOURCES=()
for file in Sources/App/*.swift; do
  [[ "$file" == Sources/App/DanteLiveApp.swift ]] || SOURCES+=("$file")
done
xcrun swiftc -parse-as-library -target "$ARCH-apple-macos14.0" \
  -import-objc-header Sources/Bridge/DanteEngine.h "${SOURCES[@]}" Tests/CanvasFramingTests.swift \
  "$BUILD/objects/DanteEngine-$ARCH.o" -F "$APP/Contents/Frameworks" -F vendor/sparkle-2.10.0 \
  -framework Sparkle -framework LiveKitWebRTC -framework libobs -framework AppKit -framework SwiftUI \
  -framework Metal -framework MetalKit -framework AVFoundation -framework ScreenCaptureKit \
  -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o build/tests/CanvasFramingTests
build/tests/CanvasFramingTests "$APP" "$ROOT/build/framing-qa"
