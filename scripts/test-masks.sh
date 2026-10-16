#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${DANTE_BUILD_DIR:-build/release-0.1.9}"
APP="$PWD/$BUILD/Dante Live.app"
ARCH="$(uname -m)"
xcrun clang++ Tests/CameraMaskTests.mm "$BUILD/objects/DanteEngine-$ARCH.o" -std=c++17 -fobjc-arc -O2 \
 -target "$ARCH-apple-macos14.0" -I Sources/Bridge -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" \
 -F "$APP/Contents/Frameworks" -framework LiveKitWebRTC -framework libobs -framework AppKit -framework Metal -framework VideoToolbox \
 -Wl,-rpath,"$APP/Contents/Frameworks" -o "$BUILD/CameraMaskTests"
codesign --force --sign "${DANTE_SIGN_IDENTITY:--}" --timestamp "$BUILD/CameraMaskTests"
"$BUILD/CameraMaskTests" "$APP"
