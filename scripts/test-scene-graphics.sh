#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="$PWD/build/scene-graphics-qa"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
APP="${DANTE_APP_PATH:-$PWD/build/release-$VERSION/Dante Live.app}"
ARCH="$(uname -m)"
mkdir -p "$BUILD"
xcrun swiftc -parse-as-library Sources/App/ProjectStore.swift Sources/App/QRCodeContent.swift Sources/App/QRCodeArtwork.swift Tests/SceneGraphicsTests.swift -framework AppKit -framework Security -o "$BUILD/SceneGraphicsTests"
"$BUILD/SceneGraphicsTests"
xcrun clang++ -c Sources/Bridge/DanteEngine.mm -std=c++17 -fobjc-arc -O1 -target "$ARCH-apple-macos14.0" \
  -I vendor/obs-studio/libobs -I vendor/simde -I "$(dirname "$APP")/generated" -I Sources/Bridge \
  -F vendor/guest-runtime/LiveKitWebRTC.xcframework/macos-arm64_x86_64 -F "$APP/Contents/Frameworks" -o "$BUILD/DanteEngine-$ARCH.o"
xcrun clang++ Tests/SceneGraphicsNative.mm "$BUILD/DanteEngine-$ARCH.o" -std=c++17 -fobjc-arc -target "$ARCH-apple-macos14.0" \
  -I Sources/Bridge -I vendor/obs-studio/libobs -I vendor/simde -I "$(dirname "$APP")/generated" \
  -F "$APP/Contents/Frameworks" -framework LiveKitWebRTC -framework libobs -framework AppKit -framework Vision -framework VideoToolbox \
  -Wl,-rpath,"$APP/Contents/Frameworks" -o "$BUILD/SceneGraphicsNative"
"$BUILD/SceneGraphicsNative" "$APP"
