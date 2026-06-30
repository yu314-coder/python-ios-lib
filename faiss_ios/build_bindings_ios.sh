#!/usr/bin/env bash
# ============================================================================
# build_bindings_ios.sh — compile faiss swig bindings + assemble the package.
# Prereq: build_core_ios.sh produced build-ios/faiss/libfaiss.a, and swig
# already generated out/swigfaiss_wrap.cxx + out/swigfaiss.py.
# Produces out/faiss/ (full python package) for app_packages/site-packages.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
SRC="$ROOT/faiss-1.9.0"
SHIM="$ROOT/omp_shim"
MINVER="13.0"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANGXX="$(xcrun --sdk iphoneos --find clang++)"
PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/include/python3.14"
[ -f "$PYINC/Python.h" ] || PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/Python.framework/Headers"
NUMPYINC="/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64/numpy/_core/include"
LIB="$(find "$ROOT/build-ios" -name 'libfaiss.a' | head -1)"
[ -n "$LIB" ] || { echo "FATAL: libfaiss.a missing — run build_core_ios.sh"; exit 1; }
[ -f "$ROOT/out/swigfaiss_wrap.cxx" ] || { echo "FATAL: run swig first"; exit 1; }

PKG="$ROOT/out/faiss"
mkdir -p "$PKG"

echo "[faiss] compiling 9MB swig wrapper (slow) ..."
"$CLANGXX" \
  -arch arm64 -target "arm64-apple-ios${MINVER}" -isysroot "$SDK" -mios-version-min="$MINVER" \
  -std=c++17 -O1 -fvisibility=hidden \
  -I"$PYINC" -I"$NUMPYINC" -I"$SRC" -I"$SHIM" \
  -Dnil=nil \
  -Wno-unknown-pragmas -Wno-deprecated-declarations -Wno-unused-command-line-argument \
  -bundle -undefined dynamic_lookup \
  "$ROOT/out/swigfaiss_wrap.cxx" \
  "$SRC/faiss/python/python_callbacks.cpp" \
  "$LIB" \
  -framework Accelerate \
  -o "$PKG/_swigfaiss.cpython-314-iphoneos.so"

xcrun --sdk iphoneos strip -x "$PKG/_swigfaiss.cpython-314-iphoneos.so" 2>/dev/null || true

# ---- assemble the python package ------------------------------------------
cp "$ROOT/out/swigfaiss.py" "$PKG/swigfaiss.py"
for f in __init__.py loader.py class_wrappers.py array_conversions.py extra_wrappers.py gpu_wrappers.py; do
  cp "$SRC/faiss/python/$f" "$PKG/$f"
done

# ---- verify ---------------------------------------------------------------
SO="$PKG/_swigfaiss.cpython-314-iphoneos.so"
echo "========================================================"
file "$SO"
echo "--- platform ---"; xcrun --sdk iphoneos vtool -show-build "$SO" 2>/dev/null | grep -iE "platform|minos" || true
echo "--- PyInit export ---"; nm -gU "$SO" 2>/dev/null | grep -i "PyInit__swigfaiss" || echo "  !! missing"
echo "--- size ---"; du -h "$SO" | cut -f1
echo "--- dangling NON-python/numpy/system symbols (should be empty) ---"
nm -u "$SO" 2>/dev/null | grep -ivE "_Py|_npy|PyArray|PyUFunc|dyld|___|__Z|libc\+\+|_omp_|cblas|_sgemm|_sgeqrf|_sgesvd|_sgetri|_sgetrf|_dgemm|^$" | head
echo "[faiss] BINDINGS DONE"
