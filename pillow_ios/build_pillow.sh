#!/bin/bash
# Cross-compile Pillow for iOS arm64 against our in-repo libjpeg + libpng + libfreetype.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
PILLOW_SRC="$ROOT/pillow-11.0.0"
INSTALL="$ROOT/install"       # libjpeg-turbo prefix
CAIRO_LIB="/Volumes/D/OfflinAi/cairo/lib"
CAIRO_INC="/Volumes/D/OfflinAi/cairo/include"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"

[ -d "$PILLOW_SRC" ] || { echo "run: tar xzf $ROOT/pillow-11.0.0.tar.gz"; exit 1; }
[ -f "$INSTALL/lib/libjpeg.a" ] || { echo "run: $ROOT/build_libjpeg.sh first"; exit 1; }

# Point Pillow's setup.py at our pre-built libs
export JPEG_ROOT="$INSTALL"
export FREETYPE_ROOT="/Volumes/D/OfflinAi/cairo"
export ZLIB_ROOT="$IOS_SDK/usr"  # iOS SDK has zlib.h + libz.tbd

# Block pkg-config and homebrew path discovery for disabled libraries.
# Without this, setup.py would pull in /opt/homebrew paths for libtiff, libwebp, lcms, etc.
export PKG_CONFIG=/usr/bin/false

# BeeWare's iOS sysconfigdata expects these wrapper env vars
export IOS_SDK_VERSION
export IPHONEOS_DEPLOYMENT_TARGET=13.0

# The iOS BLDSHARED is "arm64-apple-ios-clang -dynamiclib -F . -framework Python ..."
# i.e. it looks for Python.framework in the CURRENT directory.
# Symlink the real framework into the build dir so the -F . lookup resolves.
BUILD_STAGE="$PILLOW_SRC"
rm -f "$BUILD_STAGE/Python.framework"
ln -sf "$PY_XCF/Python.framework" "$BUILD_STAGE/Python.framework"

# Cross-compile config for setuptools.Extension
export CC="$IOS_CLANG"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -I$PY_HDRS -I$INSTALL/include -I$CAIRO_INC -I$CAIRO_INC/freetype2"
export LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -F$BUILD_STAGE -L$INSTALL/lib -L$CAIRO_LIB"
export PYTHONDONTWRITEBYTECODE=1
# sysconfigdata for iOS
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export PYTHONPATH="$PY_SYSCONFIG${PYTHONPATH:+:$PYTHONPATH}"
# tell setuptools we're cross-compiling — use iOS Python's platform tag
export _PYTHON_HOST_PLATFORM="ios-13.0-arm64"

# Build Pillow. Disable features we don't ship libs for.
cd "$PILLOW_SRC"
rm -rf build dist *.egg-info
python3 setup.py build_ext \
    --inplace \
    --disable-platform-guessing \
    --disable-tiff --disable-webp --disable-lcms \
    --disable-jpeg2000 --disable-imagequant --disable-xcb \
    --enable-jpeg --enable-zlib --enable-freetype 2>&1 | tee /tmp/pillow_build.log | tail -40
echo ""
echo "=== ld errors ==="
grep -E "^ld:|error:|undefined" /tmp/pillow_build.log | head -30 || true

echo ""
echo "=== compiled .so files ==="
find . -name "*.so" -maxdepth 3 2>/dev/null
