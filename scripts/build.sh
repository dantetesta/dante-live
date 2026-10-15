#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export MACOSX_DEPLOYMENT_TARGET=14.0
export DANTE_ARCHS="${DANTE_ARCHS:-arm64 x86_64}"
ARCHS="$DANTE_ARCHS"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
export DANTE_BUILD_DIR="${DANTE_BUILD_DIR:-build}"
[[ "$DANTE_BUILD_DIR" == /* ]] || DANTE_BUILD_DIR="$ROOT/$DANTE_BUILD_DIR"
BUILD="$DANTE_BUILD_DIR"
APP="$BUILD/Dante Live.app"
[[ -f Sources/Bridge/DanteEngine.mm && -f Sources/Bridge/DanteEngine.h ]] || { echo 'Engine sources missing.' >&2; exit 1; }
scripts/fetch-reference.sh
if [[ "$ARCHS" == *x86_64* ]]; then
  [[ -d vendor/obs-intel/OBS.app ]] || python3 packaging/fetch-intel.py
fi
python3 packaging/fetch-sparkle.py
python3 packaging/runtime.py prepare
python3 packaging/fetch-sparkle.py --embed
if [[ ! -f "$BUILD/DanteLive.icns" || packaging/generate-icon.swift -nt "$BUILD/DanteLive.icns" ]]; then
  xcrun swift packaging/generate-icon.swift "$BUILD/DanteLive.iconset"
  xcrun iconutil -c icns "$BUILD/DanteLive.iconset" -o "$BUILD/DanteLive.icns"
fi
cp "$BUILD/DanteLive.icns" "$APP/Contents/Resources/DanteLive.icns"
mkdir -p "$BUILD/generated" "$BUILD/objects"
cat > "$BUILD/generated/obsconfig.h" <<'EOF'
#pragma once
#define OBS_DATA_PATH "Resources"
#define OBS_PLUGIN_PATH "PlugIns"
#define OBS_PLUGIN_DESTINATION "PlugIns"
#define OBS_INSTALL_PREFIX ""
#define OBS_RELEASE_CANDIDATE 0
#define OBS_BETA 0
EOF
for ARCH in $ARCHS; do
  [[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || exit 1
  xcrun clang -bundle packaging/DanteRTMP.c vendor/obs-studio/plugins/rtmp-services/rtmp-custom.c \
    -std=c17 -O2 -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
    -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" \
    -F "$APP/Contents/Frameworks" -framework libobs \
    -Wl,-rpath,@executable_path/../Frameworks -o "$BUILD/objects/rtmp-services-$ARCH"
  xcrun clang++ -c Sources/Bridge/DanteEngine.mm -std=c++17 -fobjc-arc -O2 \
    -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
    -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" -I Sources/Bridge \
    -F "$APP/Contents/Frameworks" -o "$BUILD/objects/DanteEngine-$ARCH.o"
  xcrun swiftc Sources/App/*.swift "$BUILD/objects/DanteEngine-$ARCH.o" \
    -O -whole-module-optimization -target "$ARCH-apple-macos14.0" -sdk "$SDK" \
    -import-objc-header Sources/Bridge/DanteEngine.h -I Sources/Bridge \
    -F "$ROOT/vendor/sparkle-2.10.0" -F "$APP/Contents/Frameworks" -framework Sparkle -framework libobs -framework SwiftUI \
    -framework AppKit -framework Metal -framework MetalKit -framework AVFoundation \
    -framework ScreenCaptureKit -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$BUILD/objects/DanteLive-$ARCH"
done
BINARIES=()
for ARCH in $ARCHS; do BINARIES+=("$BUILD/objects/DanteLive-$ARCH"); done
xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DanteLive"
SERVICES=()
for ARCH in $ARCHS; do SERVICES+=("$BUILD/objects/rtmp-services-$ARCH"); done
xcrun lipo -create "${SERVICES[@]}" -output "$APP/Contents/PlugIns/rtmp-services.plugin/Contents/MacOS/rtmp-services"
DANTE_INSTALL_OUTPUTS=1 scripts/build-outputs.sh
python3 packaging/runtime.py audit
python3 packaging/sign.py
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built locally: $APP (signing mode reported above)"
