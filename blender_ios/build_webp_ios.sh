#!/bin/bash
# Rebuild libwebp 1.6.0 for iOS arm64 WITH the demux + mux sub-libraries and the
# installed WebPConfig.cmake. The original deps-install/libwebp.a had only the
# core encoder/decoder (no WebPDemux*/WebPMux* and no cmake config), so OIIO's
# webp.imageio (which links WebP::webp WebP::webpdemux WebP::libwebpmux) could
# not find it. This produces libwebp.a + libwebpdemux.a + libwebpmux.a +
# libsharpyuv.a + lib/cmake/WebP/WebPConfig.cmake.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"

IOS=(
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX"
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF
)

rm -rf build/webp-ios
cmake -S src/libwebp-1.6.0 -B build/webp-ios -G Ninja "${IOS[@]}" \
  -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_ANIM_ENCODER=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF `# skip the webpmux TOOL (fails as an iOS bundle exe)` \
  -DWEBP_BUILD_LIBWEBPMUX=ON `# but DO build the libwebpmux library OIIO links` \
  -DWEBP_LINK_STATIC=ON

cmake --build build/webp-ios -j8
cmake --install build/webp-ios

echo "=== webp installed ==="
ls -la "$PREFIX"/lib/libwebp*.a "$PREFIX"/lib/libsharpyuv*.a 2>/dev/null | awk '{print $5, $NF}'
echo "  WebPConfig.cmake: $(find "$PREFIX" -iname 'WebPConfig.cmake' 2>/dev/null | head -1)"
echo "  demux syms: $(nm "$PREFIX"/lib/libwebpdemux.a 2>/dev/null | grep -c WebPDemux)  mux syms: $(nm "$PREFIX"/lib/libwebpmux.a 2>/dev/null | grep -c WebPMux)"
