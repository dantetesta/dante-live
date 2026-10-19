#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_TMP="$(mktemp -d)"
BUILD="${DANTE_BUILD_DIR:-build}"
APP="$PWD/$BUILD/Dante Live.app"
HARNESS_PID=""
finish() {
  touch "$TEST_TMP/stop"
  if [[ -n "$HARNESS_PID" ]]; then wait "$HARNESS_PID" || true; fi
  rm -rf "$TEST_TMP"
}
trap finish EXIT
"$BUILD/GuestHarness" "$APP" "$TEST_TMP" "$@" > "$TEST_TMP/harness.log" 2>&1 &
HARNESS_PID=$!
for _ in {1..200}; do
  [[ -f "$TEST_TMP/connection.json" ]] && break
  if ! kill -0 "$HARNESS_PID" 2>/dev/null; then cat "$TEST_TMP/harness.log"; exit 1; fi
  sleep .1
done
[[ -f "$TEST_TMP/connection.json" ]] || { cat "$TEST_TMP/harness.log"; exit 1; }
node Tests/guest-browser.cjs "$TEST_TMP"
cat "$TEST_TMP/harness.log"
