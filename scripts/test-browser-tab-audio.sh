#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="$(uname -m)"
BUILD="${DANTE_TAB_AUDIO_TEST_DIR:-build/browser-tab-audio-qa}"
APP="${DANTE_APP_PATH:-$PWD/build/dev-tab/Dante Live.app}"
mkdir -p "$BUILD"
RUN="$(mktemp -d "$BUILD/run.XXXXXX")"
FILES=()
for file in Sources/App/*.swift; do
  [[ "$file" == Sources/App/DanteLiveApp.swift ]] || FILES+=("$file")
done
xcrun swiftc -parse-as-library -target "$ARCH-apple-macos14.0" \
  -import-objc-header Sources/Bridge/DanteEngine.h "${FILES[@]}" Tests/BrowserTabAudioHarness.swift \
  "$(dirname "$APP")/objects/DanteEngine-$ARCH.o" \
  -F "$APP/Contents/Frameworks" -F vendor/sparkle-2.10.0 -framework Sparkle \
  -framework LiveKitWebRTC -framework libobs -framework AppKit -framework SwiftUI \
  -framework Metal -framework MetalKit -framework AVFoundation -framework ScreenCaptureKit \
  -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o "$BUILD/BrowserTabAudioHarness"
codesign --force --sign - "$BUILD/BrowserTabAudioHarness"
"$BUILD/BrowserTabAudioHarness" "$APP" "$PWD/$RUN" &
HARNESS=$!
trap 'kill "$HARNESS" 2>/dev/null || true; wait "$HARNESS" 2>/dev/null || true; rm -rf "$RUN"' EXIT
for i in {1..100}; do
  [[ -f "$RUN/connection.json" && -f "$RUN/levels.json" ]] && break
  kill -0 "$HARNESS" 2>/dev/null || { wait "$HARNESS"; exit 1; }
  sleep .2
done
[[ -f "$RUN/connection.json" && -f "$RUN/levels.json" ]]
node Tests/browser-tab-audio-native.cjs "$PWD/$RUN"
