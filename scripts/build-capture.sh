#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${DANTE_BUILD_DIR:-build/capture-qa}"
[[ "$BUILD" == /* ]] || BUILD="$ROOT/$BUILD"
FRAMEWORKS="${DANTE_FRAMEWORKS:-$BUILD/Dante Live.app/Contents/Frameworks}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$BUILD/capture-objects" "$BUILD/generated"
python3 - "$BUILD" <<'PY'
import pathlib, shutil, sys
root=pathlib.Path.cwd(); build=pathlib.Path(sys.argv[1]); target=build/'capture-source'
if target.exists(): shutil.rmtree(target)
shutil.copytree(root/'vendor/obs-studio/plugins/mac-capture',target)
if not (build/'generated/obsconfig.h').exists():
    (build/'generated/obsconfig.h').write_text('#pragma once\n#define OBS_RELEASE_CANDIDATE 0\n#define OBS_BETA 0\n')
PY
patch -d "$BUILD/capture-source" -p1 < packaging/patches/mac-capture-hide-host.patch
SOURCES=(audio-device-enum.c mac-audio.c mac-display-capture.m mac-sck-audio-capture.m
  mac-sck-common.m mac-sck-video-capture.m mac-window-capture.m plugin-main.c window-utils.m)
BINARIES=()
for ARCH in ${DANTE_ARCHS:-arm64 x86_64}; do
  OBJECTS=()
  for source in "${SOURCES[@]}"; do
    object="$BUILD/capture-objects/${source%.*}-$ARCH.o"
    xcrun clang -c "$BUILD/capture-source/$source" -std=gnu17 -O2 -fblocks \
      -Wno-deprecated-declarations -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
      -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" -o "$object"
    OBJECTS+=("$object")
  done
  xcrun clang -bundle "${OBJECTS[@]}" -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
    -F "$FRAMEWORKS" -framework libobs -framework AudioUnit -framework Cocoa \
    -framework CoreAudio -framework CoreFoundation -framework CoreMedia -framework CoreVideo \
    -framework IOSurface -framework ScreenCaptureKit \
    -Wl,-rpath,@executable_path/../Frameworks -o "$BUILD/capture-objects/mac-capture-$ARCH"
  BINARIES+=("$BUILD/capture-objects/mac-capture-$ARCH")
done
xcrun lipo -create "${BINARIES[@]}" -output "$BUILD/capture-objects/mac-capture"
if [[ "${DANTE_INSTALL_CAPTURE:-0}" == 1 ]]; then
  PLUGIN="$BUILD/Dante Live.app/Contents/PlugIns/mac-capture.plugin/Contents"
  cp "$BUILD/capture-objects/mac-capture" "$PLUGIN/MacOS/mac-capture"
  for locale in en-US pt-BR pt-PT; do
    cp "$BUILD/capture-source/data/locale/$locale.ini" "$PLUGIN/Resources/locale/$locale.ini"
  done
fi
echo "Compiled source-built mac-capture: $BUILD/capture-objects/mac-capture"
