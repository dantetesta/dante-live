#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${DANTE_BUILD_DIR:-build/release-0.1.9}"
APP="$PWD/$BUILD/Dante Live.app"
FILES=()
for f in Sources/App/*.swift; do
  [[ "$f" == Sources/App/DanteLiveApp.swift ]] || FILES+=("$f")
done
xcrun swiftc -parse-as-library -Onone -target arm64-apple-macos14.0 \
  -import-objc-header Sources/Bridge/DanteEngine.h "${FILES[@]}" Tests/GuestHarness.swift \
  "$BUILD/objects/DanteEngine-arm64.o" -F vendor/sparkle-2.10.0 -F "$APP/Contents/Frameworks" \
  -framework Sparkle -framework LiveKitWebRTC -framework libobs -framework SwiftUI -framework AppKit -framework Metal -framework MetalKit \
  -framework AVFoundation -framework ScreenCaptureKit -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o "$BUILD/GuestHarness"
codesign --force --sign - --timestamp=none "$BUILD/GuestHarness"
