#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${DANTE_CAPTURE_TEST_BUILD:-build/capture-qa}"
[[ "$BUILD" == /* ]] || BUILD="$ROOT/$BUILD"
APP="${DANTE_APP_PATH:-$ROOT/build/Dante Live.app}"
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$BUILD"
DANTE_BUILD_DIR="$BUILD" DANTE_FRAMEWORKS="$FRAMEWORKS" bash scripts/build-capture.sh
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun clang Tests/CapturePropertiesTests.m -std=gnu17 -fblocks -Wno-deprecated-declarations \
  -target "$(uname -m)-apple-macos14.0" -isysroot "$SDK" \
  -I "$BUILD/capture-source" -I vendor/obs-studio/libobs -I vendor/simde -I "$BUILD/generated" \
  -F "$FRAMEWORKS" -framework libobs -framework Cocoa -framework ScreenCaptureKit \
  -framework CoreMedia -framework CoreVideo -framework IOSurface \
  -Wl,-rpath,"$FRAMEWORKS" -o "$BUILD/CapturePropertiesTests"
"$BUILD/CapturePropertiesTests"
python3 - "$BUILD" <<'PY'
import pathlib, sys
source=pathlib.Path(sys.argv[1])/'capture-source'
for locale in ('en-US','pt-BR','pt-PT'):
    line=next(s for s in (source/f'data/locale/{locale}.ini').read_text().splitlines() if s.startswith('DisplayCapture.HideOBS='))
    assert 'Dante Live' in line and 'OBS' not in line.split('=',1)[1]
print('PASS: capture control names Dante Live; persisted hide_obs key retained.')
PY
