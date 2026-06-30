#!/usr/bin/env bash
# ============================================================================
# build_ios.sh -- cross-build MLX (libmlx + metal backend + mlx.metallib) for
# iOS arm64 (device / iphoneos), and optionally the nanobind `core` Python
# extension against the iOS CPython 3.14 headers.
# ----------------------------------------------------------------------------
# Mirrors the cairo(metal) ethos: single-quote/absolute paths, pin the iOS
# Python headers, drive the native build directly (here CMake, since MLX is
# CMake-native), ship a precompiled mlx.metallib colocated with the binary.
#
# An iphoneos .so/.a cannot RUN on macOS; it can only be loaded on a real
# device / "My Mac (Designed for iPad)". We verify artifacts statically.
#
# Usage:
#   ./build_ios.sh             # configure + build libmlx + mlx.metallib
#   ./build_ios.sh python      # also attempt the nanobind core extension
# ============================================================================
set -euo pipefail

ROOT="/Volumes/D/OfflinAi/mlx-ios"
SRC="$ROOT/mlx"
STAGE="${1:-core}"   # "core" (libmlx+metallib) or "python"

# Stage-specific build dir. The two stages set BUILD_SHARED_LIBS differently
# (static libmlx.a for "core", shared libmlx.dylib for the "python" extension),
# so they cannot share one CMake build tree.
if [ "$STAGE" = "python" ]; then
  BUILD="$ROOT/build-ios-py"
else
  BUILD="$ROOT/build-ios"
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
DEPLOY="17.0"
CLANG="$(xcrun -sdk iphoneos -f clang)"
CLANGXX="$(xcrun -sdk iphoneos -f clang++)"

# iOS CPython 3.14 headers (Python.h). Pinned; fall back to a search.
PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/include/python3.14"
if [ ! -f "$PYINC/Python.h" ]; then
  echo "[ios] Python.h not at pinned PYINC; searching ..." >&2
  found="$(find /Volumes/D/OfflinAi/Frameworks -name Python.h -path '*ios-arm64*' 2>/dev/null | head -n1 || true)"
  [ -n "$found" ] && PYINC="$(dirname "$found")"
fi

echo "[ios] SDK=$SDK"
echo "[ios] deployment target=$DEPLOY  PYINC=$PYINC  stage=$STAGE"

COMMON_ARGS=(
  -S "$SRC" -B "$BUILD" -G Ninja
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_SYSROOT="$SDK"
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY"
  -DCMAKE_C_COMPILER="$CLANG"
  -DCMAKE_CXX_COMPILER="$CLANGXX"
  -DCMAKE_BUILD_TYPE=Release
  # ccache off (cross toolchain); avoid surprises
  -DMLX_USE_CCACHE=OFF
  -DMLX_BUILD_METAL=ON
  -DMLX_BUILD_CPU=ON
  -DMLX_METAL_JIT=OFF
  -DMLX_BUILD_TESTS=OFF
  -DMLX_BUILD_EXAMPLES=OFF
  -DMLX_BUILD_BENCHMARKS=OFF
  -DMLX_BUILD_GGUF=ON
  -DMLX_BUILD_SAFETENSORS=ON
  -DMLX_METAL_SDK=iphoneos
  # iOS toolchain: we are cross-compiling; tell CMake not to try to run target
  # binaries and to search the sysroot for libs/includes.
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
  # BOTH (not ONLY) so find_package(Python) can see the pinned xcframework
  # include dir, which lives outside the iphoneos sysroot.
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
)

if [ "$STAGE" = "python" ]; then
  # The iOS xcframework ships a real arm64 libpython3.14 dylib (the framework
  # binary). Point find_package(Python Development.Module) at the xcframework
  # headers + that dylib. We still link the extension with
  # -undefined dynamic_lookup so Python C-API symbols resolve at load (the host
  # app provides them), matching the cairo(metal) pattern.
  PYLIB='/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/Python.framework/Python'
  COMMON_ARGS+=(
    -DMLX_BUILD_PYTHON_BINDINGS=ON
    -DBUILD_SHARED_LIBS=ON
    -DMLX_BUILD_PYTHON_STUBS=OFF
    -DPython_EXECUTABLE="$(command -v python3)"
    -DPython_INCLUDE_DIR="$PYINC"
    -DPython_INCLUDE_DIRS="$PYINC"
    -DPython_LIBRARY="$PYLIB"
    -DPython_NumPy_INCLUDE_DIRS="$PYINC"
  )
else
  COMMON_ARGS+=(
    -DMLX_BUILD_PYTHON_BINDINGS=OFF
    -DBUILD_SHARED_LIBS=OFF
  )
fi

echo "[ios] configuring ..."
cmake "${COMMON_ARGS[@]}"

echo "[ios] building ..."
if [ "$STAGE" = "python" ]; then
  cmake --build "$BUILD" --target core -j"$(sysctl -n hw.ncpu)"
else
  cmake --build "$BUILD" --target mlx mlx-metallib -j"$(sysctl -n hw.ncpu)"
fi

echo
echo "[ios] ===== artifacts ====="
find "$BUILD" -name "*.metallib" -o -name "libmlx.a" -o -name "core*.so" 2>/dev/null | while read -r f; do
  ls -la "$f"; file "$f"
done
