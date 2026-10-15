#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="${DANTE_BUILD_DIR:-$ROOT/build}"
[[ "$BUILD" == /* ]] || BUILD="$ROOT/$BUILD"
APP="${DANTE_APP_PATH:-$BUILD/Dante Live.app}"
ARCH="$(uname -m)"
mkdir -p build/tests evidence/runtime
xcrun swiftc -O -target "$ARCH-apple-macos14.0" Sources/App/ProjectStore.swift Tests/ProjectStoreTests.swift \
  -framework Security -o build/tests/ProjectStoreTests
build/tests/ProjectStoreTests > evidence/runtime/project-store-tests.txt
cat evidence/runtime/project-store-tests.txt
xcrun swiftc -O -target "$ARCH-apple-macos14.0" Sources/App/CanvasGeometry.swift Tests/CanvasGeometryTests.swift \
  -o build/tests/CanvasGeometryTests
build/tests/CanvasGeometryTests > evidence/runtime/canvas-geometry-tests.txt
cat evidence/runtime/canvas-geometry-tests.txt
xcrun swiftc -O -target "$ARCH-apple-macos14.0" Sources/App/LivePresets.swift Tests/LivePresetsTests.swift \
  -o build/tests/LivePresetsTests
build/tests/LivePresetsTests > evidence/runtime/live-presets-tests.txt
cat evidence/runtime/live-presets-tests.txt
xcrun swiftc -O -target "$ARCH-apple-macos14.0" Sources/App/UploadProbe.swift Tests/UploadProbeTests.swift \
  -o build/tests/UploadProbeTests
build/tests/UploadProbeTests > evidence/runtime/upload-probe-tests.txt
cat evidence/runtime/upload-probe-tests.txt
xcrun swiftc -parse-as-library -O -target "$ARCH-apple-macos14.0" \
  -import-objc-header Sources/Bridge/DanteEngine.h Tests/PreviewLifecycleTests.swift \
  "$BUILD/objects/DanteEngine-$ARCH.o" -F "$APP/Contents/Frameworks" \
  -framework libobs -framework AppKit -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o build/tests/PreviewLifecycleTests
build/tests/PreviewLifecycleTests "$APP" > evidence/runtime/preview-lifecycle-tests.txt
cat evidence/runtime/preview-lifecycle-tests.txt

EDITOR_SOURCES=()
for file in Sources/App/*.swift; do
  [[ "$file" == Sources/App/DanteLiveApp.swift ]] || EDITOR_SOURCES+=("$file")
done
xcrun swiftc -parse-as-library -O -target "$ARCH-apple-macos14.0" \
  -import-objc-header Sources/Bridge/DanteEngine.h "${EDITOR_SOURCES[@]}" Tests/EditorInteractionTests.swift Tests/LiveSettingsTests.swift Tests/YouTubeTests.swift Tests/UpdateTests.swift \
  "$BUILD/objects/DanteEngine-$ARCH.o" -F "$APP/Contents/Frameworks" \
  -F "$ROOT/vendor/sparkle-2.10.0" -framework Sparkle -framework libobs -framework AppKit -framework SwiftUI -framework Metal -framework MetalKit \
  -framework AVFoundation -framework ScreenCaptureKit -framework Security -framework CoreAudio -framework VideoToolbox -lc++ \
  -Xlinker -rpath -Xlinker "$APP/Contents/Frameworks" -o build/tests/EditorInteractionTests
build/tests/EditorInteractionTests "$APP" > evidence/runtime/editor-interaction-tests.txt
cat evidence/runtime/editor-interaction-tests.txt
python3 Tests/update_feed_tests.py
