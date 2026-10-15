#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${DANTE_BUILD_DIR:-build/final}"
[[ "$BUILD" == /* ]] || BUILD="$ROOT/$BUILD"
FRAMEWORKS="${DANTE_FRAMEWORKS:-$BUILD/Dante Live.app/Contents/Frameworks}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
python3 packaging/fetch-build-deps.py
mkdir -p "$BUILD/outputs-objects" "$BUILD/generated"
python3 - "$BUILD" <<'PY'
import pathlib,shutil,sys
root=pathlib.Path.cwd(); build=pathlib.Path(sys.argv[1]); target=build/'outputs-source'
if target.exists(): shutil.rmtree(target)
shutil.copytree(root/'vendor/obs-studio/plugins/obs-outputs',target)
if not (build/'generated/obsconfig.h').exists():
    (build/'generated/obsconfig.h').write_text('#pragma once\n#define OBS_RELEASE_CANDIDATE 0\n#define OBS_BETA 0\n')
PY
if [[ -f packaging/patches/obs-outputs-connect-lifecycle.patch ]]; then
  patch -d "$BUILD/outputs-source" -p1 < packaging/patches/obs-outputs-connect-lifecycle.patch
elif [[ "${DANTE_OUTPUTS_BASELINE:-0}" != 1 ]]; then
  echo 'Required RTMP lifecycle patch missing; refusing unpatched build.' >&2
  exit 1
fi
SOURCES=("$BUILD"/outputs-source/*.c "$BUILD"/outputs-source/librtmp/*.c
  vendor/obs-studio/shared/bpm/bpm.c vendor/obs-studio/shared/happy-eyeballs/happy-eyeballs.c
  vendor/obs-studio/shared/opts-parser/opts-parser.c)
BINARIES=()
for ARCH in ${DANTE_ARCHS:-arm64 x86_64}; do
  CAPTION_OBJECTS=()
  for unit in caption cea708 eia608 eia608_charmap eia608_from_utf8 mpeg scc srt utf8 xds; do
    object="$BUILD/outputs-objects/caption-$unit-$ARCH.o"
    xcrun clang -c "vendor/obs-studio/deps/libcaption/src/$unit.c" -O2 \
      -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
      -I vendor/obs-studio/deps/libcaption -I vendor/obs-studio/deps/libcaption/caption \
      -o "$object"
    CAPTION_OBJECTS+=("$object")
  done
  xcrun ar rcs "$BUILD/outputs-objects/libcaption-$ARCH.a" "${CAPTION_OBJECTS[@]}"
  xcrun clang -bundle "${SOURCES[@]}" -std=gnu17 -O2 -DUSE_MBEDTLS -DCRYPTO -DENABLE_HEVC \
    -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers \
    -target "$ARCH-apple-macos14.0" -isysroot "$SDK" \
    -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" \
    -I vendor/obs-deps-universal/include -I vendor/obs-studio/shared/bpm \
    -I vendor/obs-studio/shared/happy-eyeballs -I vendor/obs-studio/shared/opts-parser \
    -I vendor/obs-studio/deps/libcaption -I vendor/obs-studio/deps/libcaption/caption \
    -F "$FRAMEWORKS" -framework libobs -framework Foundation -framework Security \
    -L "$FRAMEWORKS" -lmbedtls -lmbedcrypto -lmbedx509 -lz \
    vendor/obs-deps-universal/lib/libjansson.a "$BUILD/outputs-objects/libcaption-$ARCH.a" \
    -Wl,-rpath,@executable_path/../Frameworks -o "$BUILD/outputs-objects/obs-outputs-$ARCH"
  BINARIES+=("$BUILD/outputs-objects/obs-outputs-$ARCH")
done
xcrun lipo -create "${BINARIES[@]}" -output "$BUILD/outputs-objects/obs-outputs"
if [[ "${DANTE_INSTALL_OUTPUTS:-0}" == 1 ]]; then
  cp "$BUILD/outputs-objects/obs-outputs" "$BUILD/Dante Live.app/Contents/PlugIns/obs-outputs.plugin/Contents/MacOS/obs-outputs"
  LICENSES="$BUILD/Dante Live.app/Contents/Resources/Licenses"
  mkdir -p "$LICENSES/jansson"
  cp vendor/obs-deps/licenses/jansson/LICENSE "$LICENSES/jansson/LICENSE"
  cp vendor/obs-studio/deps/libcaption/LICENSE.txt "$LICENSES/libcaption-LICENSE.txt"
  cp packaging/THIRD-PARTY-NOTICES.txt "$LICENSES/THIRD-PARTY-NOTICES.txt"
fi
echo "Compiled source-built obs-outputs: $BUILD/outputs-objects/obs-outputs"
