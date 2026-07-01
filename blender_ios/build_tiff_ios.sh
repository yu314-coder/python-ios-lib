#!/bin/bash
# Rebuild libtiff 4.7.1 for iOS arm64 (static) WITHOUT the LZMA codec. The
# original deps-install libtiff.a referenced liblzma (which isn't cross-built for
# iOS), so linking it into the bpy module (now that OIIO has the TIFF plugin) left
# an undefined `lzma_*` symbol. LZMA-compressed TIFF is rare; dropping it keeps
# libtiff self-contained against the libs we DO have (zlib, libdeflate, zstd,
# jpeg, webp). Same 4.7.1 headers -> OIIO's already-built tiff plugin still links.
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

rm -rf build/tiff-ios
cmake -S src/tiff-4.7.1 -B build/tiff-ios -G Ninja "${IOS[@]}" \
  -Dlzma=OFF -Djbig=OFF -Dlerc=OFF \
  -Dzlib=ON -Dlibdeflate=ON -Dzstd=ON -Djpeg=ON -Dwebp=ON -Dold-jpeg=OFF \
  -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-docs=OFF -Dtiff-contrib=OFF -Dtiff-deprecated=OFF

cmake --build build/tiff-ios -j8
NEW=$(find build/tiff-ios -name 'libtiff.a' | head -1)
# Count REAL undefined lzma symbols; exclude nm's "object.o:" header lines (the
# tif_lzma.c.o filename itself matches 'lzma' but carries no lzma symbol).
LZMA_REFS=$(nm -u "$NEW" 2>/dev/null | grep -vE ':$' | grep -ic 'lzma' || true)
echo "  built libtiff.a; real undefined lzma symbols (want 0): $LZMA_REFS"
if [ "$LZMA_REFS" -ne 0 ]; then
  echo "ERROR: rebuilt libtiff still references lzma -- not installing." >&2; exit 1
fi
cp -f "$PREFIX/lib/libtiff.a" "$PREFIX/lib/libtiff.a.lzma.bak" 2>/dev/null
chmod u+w "$PREFIX/lib/libtiff.a" 2>/dev/null || true
cp -f "$NEW" "$PREFIX/lib/libtiff.a"
echo "=== libtiff (no lzma) installed: $(stat -f%z "$PREFIX/lib/libtiff.a")B, platform=$(otool -l "$PREFIX/lib/libtiff.a" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}')(2=iOS) ==="
