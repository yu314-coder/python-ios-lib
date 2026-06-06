#!/usr/bin/env bash
# ============================================================================
# build_ios.sh -- cross-build the FULL cairo_metal CPython extension for iOS
# ----------------------------------------------------------------------------
# Produces (iOS arm64, device / iphoneos):
#   build/ios/cairo_metal.cpython-314-iphoneos.so   (the full pycairo binding)
#   build/ios/default.metallib                       (compiled fill.metal)
#
# These are what the CodeBench app loads when the GPU-manim toggle is on.
#
# This builds the SAME source the macOS Makefile / `swift build` builds: ALL
# 24 implementation files (11 C + 13 Obj-C, ARC) + the single fill.metal shader
# + python/cairo_metal_ext.c. The inventory below is kept byte-for-byte in sync
# with the Makefile's C_SRCS / OBJC_SRCS / METAL_SRCS (single source of truth).
#
# NOTE: this only PROVES it compiles+links for the iOS target. An iphoneos .so
# cannot be *run* on macOS; it can only be loaded on a real device / "My Mac
# (Designed for iPad)" -- that is the final functional test. We verify the
# artifacts statically at the end (Mach-O arm64 bundle + _PyInit_cairo_metal
# export + a non-empty shaders metallib).
#
# Output is confined to build/ios/. This script never touches app_packages/ or
# the Swift app -- the maintainer does the bundle swap.
# ============================================================================
set -euo pipefail

# Resolve the package root (parent of this script's dir). The folder name has
# parentheses, which is exactly why we always work from an absolute path.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- toolchain / target ----------------------------------------------------
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TARGET="arm64-apple-ios17.0"

# iOS CPython headers (Python.h). Verify; fall back to a search if the pinned
# path ever moves so the script fails loud with a useful hint instead of a
# cryptic "Python.h not found".
PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/include/python3.14"
if [ ! -f "$PYINC/Python.h" ]; then
  echo "[ios] Python.h not at pinned PYINC ($PYINC); searching ..." >&2
  found="$(find /Volumes/D/OfflinAi/Frameworks -name Python.h -path '*ios-arm64*' 2>/dev/null | head -n1 || true)"
  if [ -z "$found" ]; then
    echo "[ios] FATAL: could not locate iOS arm64 Python.h under /Volumes/D/OfflinAi/Frameworks" >&2
    exit 1
  fi
  PYINC="$(dirname "$found")"
  echo "[ios] using PYINC=$PYINC" >&2
fi

OUT="$ROOT/build/ios"
OBJ="$OUT/obj"
mkdir -p "$OBJ"

# ---- flags -----------------------------------------------------------------
# Mirror the Makefile: C11, -O2, the same include dirs, and -fmodules so the
# Obj-C sources `@import`/auto-link their system frameworks cleanly. ARC is on
# for the .m files only. We pass -isysroot/-target for the iphoneos SDK.
WARN="-Wall -Wextra -Wno-unused-parameter"
COMMON="-arch arm64 -target $TARGET -isysroot $SDK -O2 -std=c11 $WARN -Iinclude -Isrc -fmodules"
CFLAGS="$COMMON"
OBJCFLAGS="$COMMON -fobjc-arc"

# ---- source inventory (must match the macOS Makefile exactly) --------------
C_SRCS="
  src/cm_matrix.c
  src/cm_surface_format.c
  src/cm_surface_similar.c
  src/cm_state.c
  src/cm_pattern.c
  src/cm_mesh.c
  src/cm_raster.c
  src/cm_query.c
  src/cm_region.c
  src/cm_font.c
  src/cm_ft.c
"

OBJC_SRCS="
  src/cairo_metal.m
  src/cm_surface.m
  src/cm_surface_png.m
  src/cm_recording.m
  src/cm_device.m
  src/cm_clip.m
  src/cm_group.m
  src/cm_compose.m
  src/cm_text.m
  src/cm_path.m
  src/cm_fill.m
  src/cm_stroke.m
  src/cm_paint.m
"

# fill.metal is the single shader source; it defines every entry point the
# device module references (cm_vs_* / cm_fs_*). Compiled with the iphoneos
# Metal toolchain -> AIR -> default.metallib. Do NOT pass a CPU -arch to metal.
METAL_SRCS="shaders/fill.metal"

# Frameworks the FULL engine needs. -fmodules already auto-links the @import'd
# ones from the .m files, but we list them explicitly on the final link so the
# binding links robustly regardless of module behaviour:
#   Metal/MetalKit/QuartzCore/CoreVideo/IOSurface/Foundation -> device/surface/encode
#   CoreText                                                  -> cm_text.m / cm_font.c
#   CoreGraphics/ImageIO/UniformTypeIdentifiers               -> cm_surface_png.m
#   CoreFoundation                                            -> CF types throughout
FRAMEWORKS="
  -framework Metal
  -framework MetalKit
  -framework QuartzCore
  -framework CoreVideo
  -framework IOSurface
  -framework Foundation
  -framework CoreFoundation
  -framework CoreText
  -framework CoreGraphics
  -framework ImageIO
  -framework UniformTypeIdentifiers
"

# ============================================================================
# 1. Compile all 24 library sources (C with -fmodules, Obj-C with ARC) -> .o
# ============================================================================
echo "[ios] compiling CairoMetal library (11 C + 13 Obj-C) for $TARGET"
OBJS=""

compile() {  # $1 = compiler flags, $2 = source path
  local flags="$1" src="$2"
  local o="$OBJ/$(basename "${src%.*}").o"
  echo "  CC  $src"
  xcrun -sdk iphoneos clang $flags -c "$src" -o "$o"
  OBJS="$OBJS $o"
}

for s in $C_SRCS;    do compile "$CFLAGS"    "$s"; done
for s in $OBJC_SRCS; do compile "$OBJCFLAGS" "$s"; done

echo "[ios] archiving build/ios/libcairometal.a"
rm -f "$OUT/libcairometal.a"
xcrun -sdk iphoneos libtool -static -o "$OUT/libcairometal.a" $OBJS

# ============================================================================
# 2. Compile the shader -> default.metallib
#    (single fill.metal; no -arch -- metal targets AIR, the SDK picks the GPU)
# ============================================================================
echo "[ios] compiling shaders -> build/ios/default.metallib"
AIRS=""
for m in $METAL_SRCS; do
  a="$OUT/$(basename "${m%.*}").air"
  echo "  METAL $m"
  xcrun -sdk iphoneos metal -c "$m" -o "$a"
  AIRS="$AIRS $a"
done
xcrun -sdk iphoneos metallib $AIRS -o "$OUT/default.metallib"

# ============================================================================
# 3. Link the Python extension binding into the iphoneos .so bundle.
#    Python C-API symbols are resolved at load via -undefined dynamic_lookup.
# ============================================================================
SO="$OUT/cairo_metal.cpython-314-iphoneos.so"
echo "[ios] linking $(basename "$SO")"
xcrun -sdk iphoneos clang -arch arm64 -target "$TARGET" -isysroot "$SDK" -O2 \
  -I"$PYINC" -Iinclude -Isrc -fobjc-arc \
  "$ROOT/python/cairo_metal_ext.c" "$OUT/libcairometal.a" \
  $FRAMEWORKS \
  -bundle -undefined dynamic_lookup \
  -o "$SO"

# ============================================================================
# 4. Static verification (an iphoneos .so cannot be run on macOS).
# ============================================================================
echo
echo "[ios] built artifacts:"
ls -la "$SO" "$OUT/default.metallib"
echo
echo "[ios] file:"
file "$SO"
echo
echo "[ios] PyInit export (expect _PyInit_cairo_metal):"
nm -gU "$SO" | grep -i PyInit || { echo "[ios] FATAL: no PyInit export" >&2; exit 1; }
echo
echo "[ios] shader entry points in metallib (expect > 0):"
strings "$OUT/default.metallib" | grep -c cm_ || true

echo
echo "[ios] done."
