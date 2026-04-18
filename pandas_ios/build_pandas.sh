#!/bin/bash
# Cross-compile pandas 2.0.3 for iOS arm64
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
PANDAS_SRC="$ROOT/pandas-2.0.3"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"

[ -d "$PANDAS_SRC" ] || { echo "extract pandas-2.0.3.tar.gz first"; exit 1; }

# The iOS BLDSHARED has `-F .` — symlink Python.framework into build dir
rm -f "$PANDAS_SRC/Python.framework"
ln -sf "$PY_XCF/Python.framework" "$PANDAS_SRC/Python.framework"

export IOS_SDK_VERSION
export IPHONEOS_DEPLOYMENT_TARGET=13.0
export PKG_CONFIG=/usr/bin/false

# numpy headers from the host (arch doesn't matter for headers)
NUMPY_INC=$(python3 -c "import numpy; print(numpy.get_include())")

export CC="$IOS_CLANG"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -I$PY_HDRS -I$NUMPY_INC"
export LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -F$PANDAS_SRC"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export PYTHONPATH="$PY_SYSCONFIG${PYTHONPATH:+:$PYTHONPATH}"
export _PYTHON_HOST_PLATFORM="ios-13.0-arm64"
export PYTHONDONTWRITEBYTECODE=1

cd "$PANDAS_SRC"
rm -rf build
python3 setup.py build_ext --inplace 2>&1 | tee /tmp/pandas_build.log | tail -30
echo ""
echo "=== .so files ==="
find pandas -name "*.cpython-314-iphoneos.so" | wc -l
find pandas -name "*.cpython-314-iphoneos.so" | head -20
