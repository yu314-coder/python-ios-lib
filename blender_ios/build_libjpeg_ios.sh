#!/bin/bash
# Build libjpeg-turbo 3.1.1 for iOS arm64 as JPEG_LIB_VERSION 80 (v8 API), static.
#
# WHY (the JPEG-save bug): deps-install/include is the 3.1.1 header set whose
# jconfig.h defines JPEG_LIB_VERSION 80, and EVERY libjpeg consumer in the tree was
# compiled against it -- Blender's native imbuf/intern/format_jpeg.cc, libtiff
# (tif_jpeg), and OpenImageIO (jpeginput/jpegoutput) all emit
#     jpeg_CreateCompress(cinfo, 80, sizeof(v80 struct)=584 /*0x248*/).
# But redo_ios_deps.sh copied pillow_ios's libjpeg.a, which is libjpeg-turbo 3.0.4
# built with the DEFAULT ABI: JPEG_LIB_VERSION 62 (struct 520 /*0x208*/). Its
# jpeg_CreateCompress does `cmp w1,#0x3e` (62) and rejects the version-80 caller with
# ERREXIT(JERR_BAD_LIB_VERSION, 80, 62). Blender's save_stdjpeg() setjmp handler then
# longjmps, remove()s the output file, and returns false with errno still 0 -- exactly
# the observed "cannot save: ...fmt_JPEG.jpg / Undefined error: 0". JPEG was the ONLY
# broken format precisely because it is the only writer that calls libjpeg directly;
# PNG/EXR/TIFF/WebP/JP2/etc. never enter libjpeg. (Routing JPEG through OIIO would NOT
# help -- OIIO's jpeg plugin is v80 too, so it hits the identical mismatch.)
#
# FIX: rebuild libjpeg at v80 so the ABI matches the headers. One lib swap repairs the
# native Blender JPEG writer, OIIO's jpeg plugin, and libtiff's JPEG codec at once.
# Options mirror the installed jconfig.h exactly (v80, arith enc/dec on, mem-srcdst on,
# SIMD off -> `#undef WITH_SIMD`; SIMD off also avoids NEON asm on the cross build).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
SRC="$PWD/src/libjpeg-turbo-3.1.1"

IOS=(
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX"
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

rm -rf build/libjpeg-ios
cmake -S "$SRC" -B build/libjpeg-ios -G Ninja "${IOS[@]}" \
  -DENABLE_SHARED=0 -DENABLE_STATIC=1 \
  -DWITH_JPEG8=1 -DWITH_ARITH_ENC=1 -DWITH_ARITH_DEC=1 \
  -DWITH_SIMD=0 -DWITH_TURBOJPEG=0 -DWITH_JAVA=0

# Build ONLY the static lib target (skips cjpeg/djpeg, which as iOS "executables" are
# useless and just slow the build).
cmake --build build/libjpeg-ios --target jpeg-static -j8

NEW=$(find "$PWD/build/libjpeg-ios" -name 'libjpeg.a' | head -1)
[ -z "$NEW" ] && { echo "ERROR: libjpeg.a not built" >&2; exit 1; }

# --- Verify the built ABI is v80 BEFORE installing (this is the whole point). ---------
# The lib's jpeg_CreateCompress must compare `version` against 0x50 (80) and `structsize`
# against 0x248 (584). A v62 build uses 0x3e (62) / 0x208 (520) -- refuse to install that.
VDIR="$PWD/build/libjpeg-ios/_verify"; rm -rf "$VDIR"; mkdir -p "$VDIR"
( cd "$VDIR" && ar x "$NEW" jcapimin.c.o )
ASM=$(otool -tvV "$VDIR/jcapimin.c.o" 2>/dev/null | \
      awk '/^_jpeg_CreateCompress:/{f=1} f{print} /^_jpeg_destroy_compress:/{exit}')
if echo "$ASM" | grep -q "w1, #0x50" && echo "$ASM" | grep -q "#0x248"; then
  echo "  verify OK: built libjpeg.a enforces JPEG_LIB_VERSION 80 (compress struct 584)."
else
  echo "ERROR: built libjpeg.a is NOT v80 -- refusing to install." >&2
  echo "$ASM" | grep -E "cmp|#0x(3e|50|208|248)" | head >&2
  exit 1
fi
lipo -info "$NEW" 2>/dev/null | grep -q arm64 || { echo "ERROR: not arm64" >&2; exit 1; }

# --- Install: swap the lib, pin the matching header set (back up the mismatched v62). --
cp -f "$PREFIX/lib/libjpeg.a" "$PREFIX/lib/libjpeg.a.v62pillow.bak" 2>/dev/null || true
chmod u+w "$PREFIX/lib/libjpeg.a" 2>/dev/null || true
cp -f "$NEW" "$PREFIX/lib/libjpeg.a"
# Install the header set from THIS build so lib+headers are provably one version. These
# are already v80 (that is what the tree compiled against), so this is a no-op in normal
# runs -- but it guarantees the two can never drift again.
cp -f build/libjpeg-ios/jconfig.h "$PREFIX/include/jconfig.h"
cp -f "$SRC/src/jpeglib.h" "$SRC/src/jmorecfg.h" "$SRC/src/jerror.h" "$PREFIX/include/"

echo "=== libjpeg (v80) installed: $(stat -f%z "$PREFIX/lib/libjpeg.a")B," \
     "platform=$(otool -l "$PREFIX/lib/libjpeg.a" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}')(2=iOS)," \
     "JPEG_LIB_VERSION=$(grep -m1 'define JPEG_LIB_VERSION' "$PREFIX/include/jconfig.h" | awk '{print $3}') ==="
echo "Next: relink bpy -> ninja -C build/blender blender   (picks up the new libjpeg.a)"
