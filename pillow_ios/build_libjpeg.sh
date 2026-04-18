#!/bin/bash
# Cross-compile libjpeg-turbo for iOS arm64
set -euo pipefail

SRC=/Volumes/D/OfflinAi/pillow_ios/libjpeg-turbo-3.0.4
BUILD=/Volumes/D/OfflinAi/pillow_ios/build_libjpeg
INSTALL=/Volumes/D/OfflinAi/pillow_ios/install

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

cmake "$SRC" \
    -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DWITH_SIMD=OFF \
    -DWITH_TURBOJPEG=OFF 2>&1 | tail -10

ninja 2>&1 | tail -5
ninja install 2>&1 | tail -3

echo ""
echo "✓ libjpeg installed:"
ls "$INSTALL/lib"/*.a "$INSTALL/include"/*.h 2>&1 | head
