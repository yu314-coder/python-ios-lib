#!/bin/bash
# Cross-compile numpy 2.3.5 for iOS arm64 against BeeWare's Python.xcframework.
#
# Output: numpy/*.cpython-314-iphoneos.so files installed into
#   /Volumes/D/OfflinAi/app_packages/site-packages/numpy/

set -euo pipefail
cd "$(dirname "$0")"

SRC="$PWD/numpy-2.3.5"
BUILD="$PWD/build"
INSTALL="$PWD/install"
CROSS="$PWD/ios-arm64-cross.ini"

# Locate iOS SDK + iOS Python.framework for headers/lib
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_LIB="$PY_XCF/Python.framework/Python"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"

echo "iOS SDK:       $IOS_SDK"
echo "Python hdrs:   $PY_HDRS"
echo "Python dylib:  $PY_LIB"
echo "sysconfig:     $PY_SYSCONFIG"

[ -d "$SRC" ] || { echo "numpy source not found at $SRC"; exit 1; }
[ -f "$PY_HDRS/Python.h" ] || { echo "Python.h missing"; exit 1; }

# The cross-file has a hard-coded iPhoneOS26.2.sdk; if we're on a different
# Xcode version, regenerate the cross-file on the fly.
if [ ! -f "$IOS_SDK/SDKSettings.plist" ]; then
    echo "iOS SDK path invalid"; exit 1
fi
# Update cross-file's isysroot arg to current SDK
sed -i '' "s|/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS[0-9.]*\.sdk|$IOS_SDK|g" "$CROSS"

# Clean stale build
rm -rf "$BUILD" "$INSTALL"

# Setup meson with cross-file.  Numpy's pyproject-level meson-python handles
# a lot of the Python wiring, but we use bare meson so we can control paths.
# Pass --native-file to point at iOS Python's include/lib.
cat > "$PWD/native.ini" <<EOF
[binaries]
python = 'python3'

[properties]
python_version = '3.14'
python_include_dir = '$PY_HDRS'
# numpy looks up the interpreter's numpy.distutils config; we don't have one,
# so we'll point include paths directly.
EOF

echo
echo "==> meson setup..."
# Use numpy's VENDORED meson (1.8.3) — has the custom `features` module
# numpy's meson_cpu/ uses, which system meson doesn't ship.
VMESON="$SRC/vendored-meson/meson/meson.py"
[ -f "$VMESON" ] || { echo "vendored meson not found"; exit 1; }

# Feed numpy's meson a few environment overrides.
# NPY_DISABLE_SVML=1: skip SIMD intrinsics that reference SVML (Intel-only).
# BLAS=none: numpy looks up BLAS/LAPACK; we'll disable for iOS minimal build.
export NPY_DISABLE_SVML=1
export NPY_BLAS_ORDER=""
export NPY_LAPACK_ORDER=""

python3 "$VMESON" setup "$BUILD" "$SRC" \
    --cross-file="$CROSS" \
    --native-file="$PWD/native.ini" \
    -Dpython.platlibdir="lib/python3.14/site-packages" \
    -Dpython.purelibdir="lib/python3.14/site-packages" \
    -Dblas=none \
    -Dlapack=none \
    -Dallow-noblas=true \
    -Ddisable-svml=true \
    -Ddisable-highway=true \
    -Dpkgconfig.relocatable=false \
    --prefix="$INSTALL" 2>&1 | tail -30

echo
echo "==> meson compile..."
python3 "$VMESON" compile -C "$BUILD" 2>&1 | tail -30

echo
echo "==> locating compiled .so files..."
find "$BUILD" -name "*.cpython-*iphoneos*.so" -o -name "*.cpython-314*.so" | head -10
