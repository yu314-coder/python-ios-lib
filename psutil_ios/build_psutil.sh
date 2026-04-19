#!/bin/bash
# Cross-compile psutil 5.9.8 for iOS arm64 (using macOS build path — shared
# mach/BSD APIs). Some features (proc iteration, kvm) are sandboxed on iOS;
# the compiled .so loads, and unsupported calls raise PermissionError.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
PSUTIL_SRC="$ROOT/psutil-5.9.8"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"

[ -d "$PSUTIL_SRC" ] || { echo "extract psutil-5.9.8.tar.gz first"; exit 1; }

# `-F .` in BLDSHARED — symlink Python.framework into build dir
rm -f "$PSUTIL_SRC/Python.framework"
ln -sf "$PY_XCF/Python.framework" "$PSUTIL_SRC/Python.framework"

export IOS_SDK_VERSION
export IPHONEOS_DEPLOYMENT_TARGET=13.0
export PKG_CONFIG=/usr/bin/false

export CC="$IOS_CLANG"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -I$PY_HDRS -I$ROOT/shim_include -Wno-error=implicit-function-declaration"
export LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -F$PSUTIL_SRC"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export PYTHONPATH="$PY_SYSCONFIG${PYTHONPATH:+:$PYTHONPATH}"
export _PYTHON_HOST_PLATFORM="ios-13.0-arm64"
export PYTHONDONTWRITEBYTECODE=1

cd "$PSUTIL_SRC"
rm -rf build
python3 setup.py build_ext --inplace 2>&1 | tee /tmp/psutil_build.log | tail -30
echo ""
echo "=== .so files ==="
find psutil -name "*.so" | head
