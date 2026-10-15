#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT=ba2f32bdf791005443988a4955e963663e16b1ed
mkdir -p "$ROOT/vendor"
if [[ ! -d "$ROOT/vendor/obs-studio/.git" ]]; then
  git clone --branch 32.2.2 --depth 1 https://github.com/obsproject/obs-studio.git "$ROOT/vendor/obs-studio"
fi
[[ "$(git -C "$ROOT/vendor/obs-studio" rev-parse HEAD)" == "$COMMIT" ]] || { echo 'Unexpected OBS reference commit; refusing to modify checkout.' >&2; exit 1; }
echo "OBS reference: $COMMIT"
SIMDE_COMMIT=71fd833d9666141edcd1d3c109a80e228303d8d7
if [[ ! -d "$ROOT/vendor/simde/.git" ]]; then
  git clone --branch v0.8.2 --depth 1 https://github.com/simd-everywhere/simde.git "$ROOT/vendor/simde"
fi
[[ "$(git -C "$ROOT/vendor/simde" rev-parse HEAD)" == "$SIMDE_COMMIT" ]] || { echo 'Unexpected SIMDe reference.' >&2; exit 1; }
DEPS_COMMIT=8683107a02300923abe4f293920f4b5edc8cb624
if [[ ! -d "$ROOT/vendor/obs-deps/.git" ]]; then
  git clone --branch 2026-07-15 --depth 1 https://github.com/obsproject/obs-deps.git "$ROOT/vendor/obs-deps"
fi
[[ "$(git -C "$ROOT/vendor/obs-deps" rev-parse HEAD)" == "$DEPS_COMMIT" ]] || { echo 'Unexpected obs-deps reference.' >&2; exit 1; }
