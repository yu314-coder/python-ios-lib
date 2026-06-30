#!/usr/bin/env bash
# ============================================================================
# build_ios.sh — cross-build sentencepiece (full module) for iOS arm64.
# ----------------------------------------------------------------------------
# Produces (iphoneos, device):
#   out/sentencepiece/_sentencepiece.cpython-314-iphoneos.so   (SWIG binding)
#   out/sentencepiece/{__init__,_version,*_pb2}.py             (pure-python)
#
# Self-contained: builds the bundled protobuf-lite + sentencepiece core as a
# STATIC lib, then compiles the PRE-GENERATED swig wrapper (no swig needed)
# and links the core in. An iphoneos .so can't run on macOS — verified
# statically (Mach-O arm64 + PyInit__sentencepiece export). Maintainer copies
# out/sentencepiece into app_packages/site-packages.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
SRC="$ROOT/sentencepiece-0.2.0"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANGXX="$(xcrun --sdk iphoneos --find clang++)"
TARGET="arm64-apple-ios13.0"
MINVER="13.0"

PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/include/python3.14"
[ -f "$PYINC/Python.h" ] || PYINC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/Python.framework/Headers"
[ -f "$PYINC/Python.h" ] || { echo "FATAL: iOS Python.h not found"; exit 1; }
echo "[spm] SDK=$SDK"
echo "[spm] PYINC=$PYINC"

# ---- 1) core static lib (bundled protobuf-lite) for iphoneos arm64 ----------
# Shim: sentencepiece's src/CMakeLists.txt calls `set_xcode_property` on the
# CLI-tool targets when SYSTEM_NAME==iOS. That macro only exists in the
# bundled leetal ios.toolchain (which we deliberately don't use — native
# cmake iOS is cleaner). It only sets XCODE_ATTRIBUTE_* props, which Ninja
# ignores, so a no-op of matching arity lets configure succeed.
SHIM="$ROOT/xcode_shim.cmake"
cat > "$SHIM" <<'CMK'
macro(set_xcode_property TARGET XCODE_PROPERTY XCODE_VALUE XCODE_RELVERSION)
endmacro()
CMK

BUILD="$ROOT/build-ios"
rm -rf "$BUILD"; mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINVER" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_PROJECT_INCLUDE="$SHIM" \
  -DSPM_ENABLE_SHARED=OFF \
  -DSPM_USE_BUILTIN_PROTOBUF=ON \
  >/dev/null
# Only the two static libs — never the CLI tools / tests (they'd cross-link
# iOS executables and one test target even runs during build).
ninja -C "$BUILD" sentencepiece-static sentencepiece_train-static

LIB="$(find "$BUILD" -name 'libsentencepiece.a' | head -1)"
LIBT="$(find "$BUILD" -name 'libsentencepiece_train.a' | head -1)"
echo "[spm] core lib:  $LIB"
echo "[spm] train lib: $LIBT"
[ -n "$LIB" ] && [ -n "$LIBT" ] || { echo "FATAL: static libs not built"; exit 1; }

# ---- 2) compile the pre-generated SWIG wrapper into the Python ext ----------
OUT="$ROOT/out/sentencepiece"
mkdir -p "$OUT"
"$CLANGXX" \
  -arch arm64 -target "$TARGET" -isysroot "$SDK" -mios-version-min="$MINVER" \
  -O2 -std=c++17 -fvisibility=hidden \
  -I"$PYINC" -I"$SRC/src" -I"$SRC" \
  -DNDEBUG \
  -bundle -undefined dynamic_lookup \
  "$SRC/python/src/sentencepiece/sentencepiece_wrap.cxx" \
  "$LIBT" "$LIB" \
  -o "$OUT/_sentencepiece.cpython-314-iphoneos.so"

# strip local/debug symbols to keep it lean
xcrun --sdk iphoneos strip -x "$OUT/_sentencepiece.cpython-314-iphoneos.so" 2>/dev/null || true

# ---- 3) assemble the pure-python package files -----------------------------
for f in __init__.py _version.py sentencepiece_pb2.py sentencepiece_model_pb2.py; do
  cp "$SRC/python/src/sentencepiece/$f" "$OUT/$f"
done

# ---- 4) static verification ------------------------------------------------
echo "========================================================"
echo "[spm] artifact: $OUT/_sentencepiece.cpython-314-iphoneos.so"
file "$OUT/_sentencepiece.cpython-314-iphoneos.so"
echo "--- platform (must say PLATFORM_IOS) ---"
xcrun --sdk iphoneos vtool -show-build "$OUT/_sentencepiece.cpython-314-iphoneos.so" 2>/dev/null | grep -iE "platform|minos" || true
echo "--- PyInit export (must be present) ---"
nm -gU "$OUT/_sentencepiece.cpython-314-iphoneos.so" 2>/dev/null | grep -i "PyInit__sentencepiece" || echo "  !! PyInit missing"
echo "--- size ---"; du -h "$OUT/_sentencepiece.cpython-314-iphoneos.so" | cut -f1
echo "--- undefined Python symbols resolve via dynamic_lookup (sample) ---"
nm -u "$OUT/_sentencepiece.cpython-314-iphoneos.so" 2>/dev/null | grep -i "_Py" | head -3
echo "[spm] DONE"
