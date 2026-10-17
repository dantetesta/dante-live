#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${DANTE_BUILD_DIR:-build/chat-qa}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
APP="${DANTE_APP_PATH:-$PWD/build/release-$VERSION/Dante Live.app}"
ARCH="$(uname -m)"
GENERATED="${DANTE_GENERATED_DIR:-$(dirname "$APP")/generated}"
mkdir -p "$BUILD"
xcrun clang++ -c Sources/Bridge/DanteEngine.mm -std=c++17 -fobjc-arc -O1 \
  -target "$ARCH-apple-macos14.0" -I vendor/obs-studio/libobs -I vendor/simde \
  -I "$GENERATED" -I Sources/Bridge \
  -F vendor/guest-runtime/LiveKitWebRTC.xcframework/macos-arm64_x86_64 -F "$APP/Contents/Frameworks" \
  -o "$BUILD/DanteEngine-$ARCH.o"
FILES=()
for file in Sources/App/*.swift; do
  [[ "$file" == Sources/App/DanteLiveApp.swift ]] || FILES+=("$file")
done
xcrun swiftc -parse-as-library -target "$ARCH-apple-macos14.0" \
  -import-objc-header Sources/Bridge/DanteEngine.h "${FILES[@]}" \
  Tests/YouTubeTests.swift Tests/YouTubeChatTests.swift Tests/ChatOverlayHarness.swift "$BUILD/DanteEngine-$ARCH.o" \
  -F "$APP/Contents/Frameworks" -F vendor/sparkle-2.10.0 -framework Sparkle \
  -framework LiveKitWebRTC -framework libobs -framework AppKit -framework SwiftUI \
  -framework Metal -framework MetalKit -framework AVFoundation -framework ScreenCaptureKit \
  -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o "$BUILD/ChatTests"
"$BUILD/ChatTests" "$APP"

xcrun clang++ Tests/ChatOverlayNative.mm "$BUILD/DanteEngine-$ARCH.o" \
  -std=c++17 -fobjc-arc -target "$ARCH-apple-macos14.0" \
  -I Sources/Bridge -I vendor/obs-studio/libobs -I vendor/simde -I "$GENERATED" \
  -F "$APP/Contents/Frameworks" -framework LiveKitWebRTC -framework libobs \
  -framework AppKit -framework VideoToolbox -Wl,-rpath,"$APP/Contents/Frameworks" -o "$BUILD/ChatNativeTests"
"$BUILD/ChatNativeTests" "$APP"
