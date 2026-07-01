#!/bin/bash
# Cross-compile libsndfile 1.2.2 for iOS arm64 (static, minimal) so Blender's
# WITH_CODEC_SNDFILE gives the `aud` module + VSE the ability to load/read
# uncompressed audio (WAV/AIFF/AU/CAF/W64/...). External codecs (Ogg/Vorbis/
# FLAC/Opus/MPEG) are OFF because those libs aren't built for iOS -- so .ogg/
# .flac/.mp3 are not supported, but the common uncompressed formats are.
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

rm -rf build/sndfile-ios
cmake -S src/libsndfile-1.2.2 -B build/sndfile-ios -G Ninja "${IOS[@]}" \
  -DENABLE_EXTERNAL_LIBS=OFF -DENABLE_MPEG=OFF -DENABLE_CPACK=OFF \
  -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DENABLE_BOW_DOCS=OFF

cmake --build build/sndfile-ios -j8
cmake --install build/sndfile-ios

echo "=== sndfile installed ==="
ls -la "$PREFIX"/lib/libsndfile*.a 2>/dev/null | awk '{print $5, $NF}'
echo "  platform: $(otool -l "$PREFIX"/lib/libsndfile.a 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}') (2=iOS)"
echo "  sndfile.h: $(ls "$PREFIX"/include/sndfile.h 2>/dev/null && echo present || echo MISSING)"
