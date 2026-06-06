#!/usr/bin/env bash
# Build the cairo_metal CPython extension (macOS, for testing the shim here).
# Links the prebuilt libcairometal.a + Metal frameworks; resolves Python
# symbols at load via -bundle -undefined dynamic_lookup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Make sure the static lib + shaders exist (build via the Makefile if not).
if [ ! -f build/libcairometal.a ] || [ ! -f build/default.metallib ]; then
  echo "[build.sh] building libcairometal.a + default.metallib via make ..."
  make >/dev/null
fi

SUF="$(python3-config --extension-suffix)"
OUT="$ROOT/python/cairo_metal$SUF"
echo "[build.sh] compiling $OUT"

xcrun clang -arch arm64 -O2 -Wall \
  $(python3-config --includes) \
  -I"$ROOT/include" \
  "$ROOT/python/cairo_metal_ext.c" \
  "$ROOT/build/libcairometal.a" \
  -framework Metal -framework MetalKit -framework QuartzCore \
  -framework CoreVideo -framework IOSurface -framework Foundation \
  -bundle -undefined dynamic_lookup \
  -o "$OUT"

echo "[build.sh] built: $OUT"
