#!/bin/bash
# Rebuild OpenImageIO 3.1.13.1 for iOS arm64 WITH the tiff/webp/jpeg format
# plugins. The originally-shipped libOpenImageIO.a was built before libtiff/
# libwebp were available, so it has no tiff/webp output plugins -> Blender's
# format_tiff.cc / format_webp.cc (which write via OIIO) fail at runtime. All the
# codec libs + headers are already in deps-install; this build just enables them.
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

# ORDER MATTERS: OIIO's webp plugin is optional (checked_find_package, not REQUIRED),
# so if libwebp's demux/mux + WebPConfig.cmake aren't installed yet, OIIO silently
# builds WITHOUT WebP output. Run build_webp_ios.sh first. Fail fast if it hasn't.
if [ ! -f "$PREFIX/share/WebP/cmake/WebPConfig.cmake" ] && [ ! -f "$PREFIX/lib/cmake/WebP/WebPConfig.cmake" ]; then
  echo "ERROR: WebPConfig.cmake not found in deps-install -- run ./build_webp_ios.sh first," >&2
  echo "       otherwise OIIO builds silently without the WebP output plugin." >&2
  exit 1
fi

rm -rf build/oiio-ios
cmake -S src/OpenImageIO-3.1.13.1 -B build/oiio-ios -G Ninja "${IOS[@]}" \
  -DCMAKE_CXX_STANDARD=17 -DUSE_SIMD=0 \
  -DOIIO_BUILD_TOOLS=OFF -DOIIO_BUILD_TESTS=OFF -DBUILD_DOCS=OFF -DINSTALL_DOCS=OFF \
  -DUSE_PYTHON=OFF -DUSE_QT=OFF -DLINKSTATIC=ON -DEMBEDPLUGINS=ON \
  -DUSE_TIFF=ON -DUSE_WEBP=ON -DUSE_JPEGTURBO=ON -DUSE_OPENJPEG=ON \
  -DUSE_PNG=ON -DUSE_OPENEXR=ON -DUSE_OPENCOLORIO=ON -DUSE_TBB=ON \
  -DUSE_EXTERNAL_PUGIXML=OFF `# deps-install pugixml has no cmake config; use OIIO's bundled copy` \
  -DUSE_NUKE=OFF -DUSE_OPENVDB=OFF -DUSE_FREETYPE=OFF -DUSE_DCMTK=OFF -DUSE_GIF=OFF \
  -DUSE_OPENCV=OFF -DUSE_FFMPEG=OFF -DUSE_PTEX=OFF -DUSE_LIBHEIF=OFF -DUSE_LIBRAW=OFF \
  -DUSE_JXL=OFF -DUSE_R3DSDK=OFF -DUSE_BZIP2=OFF -DUSE_DICOM=OFF -DUSE_FIELD3D=OFF

cmake --build build/oiio-ios -j8

# verify the tiff/webp plugins are now compiled in BEFORE clobbering the good lib
NEW=$(find build/oiio-ios -name 'libOpenImageIO.a' | head -1)
for fmt in tiff webp jpeg png; do
  echo "  built $fmt plugin syms: $(nm "$NEW" 2>/dev/null | grep -ciE "${fmt}output|${fmt}_output")"
done
if [ "$(nm "$NEW" 2>/dev/null | grep -ciE 'tiffoutput')" -eq 0 ]; then
  echo "ERROR: rebuilt OIIO missing the TIFF plugin -- NOT installing." >&2
  exit 1
fi
if [ "$(nm "$NEW" 2>/dev/null | grep -ciE 'webpoutput|weboutput')" -eq 0 ]; then
  echo "WARN: OIIO WebP plugin still absent -- installing with TIFF (WebP output stays unavailable)."
fi

# back up the working libs, then harvest the new ones
for l in libOpenImageIO.a libOpenImageIO_Util.a; do
  [ -f "$PREFIX/lib/$l" ] && cp -f "$PREFIX/lib/$l" "$PREFIX/lib/$l.pretiff.bak"
  f=$(find build/oiio-ios -name "$l" | head -1)
  chmod u+w "$PREFIX/lib/$l" 2>/dev/null || true
  cp -f "$f" "$PREFIX/lib/$l"
  echo "  installed $l ($(stat -f%z "$PREFIX/lib/$l")B)"
done
echo "=== OIIO rebuilt with tiff/webp/jpeg ==="
