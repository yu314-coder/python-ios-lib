#!/bin/bash
# Rebuild the deps that ended up macOS-platform (arm64 but LC_BUILD_VERSION=macOS,
# harvested wrong during the dep phase) as real iOS-arm64 static libs. Static
# archiving never caught the mismatch; only the final bpy link does. Headers in
# deps-install/include are arch-independent, so we only replace the .a files.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"

IOS_FLAGS=(
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX"
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF
)

# build_dep <tag> <src-subdir> [extra cmake args...]
build_dep() {
  local tag="$1" sub="$2"; shift 2
  echo "== building $tag for iOS =="
  rm -rf "build/redo-$tag"
  cmake -S "src/$sub" -B "build/redo-$tag" -G Ninja "${IOS_FLAGS[@]}" "$@" \
    > "build/redo-$tag-cfg.log" 2>&1 || { echo "  CFG FAIL ($tag)"; tail -5 "build/redo-$tag-cfg.log"; return 1; }
  cmake --build "build/redo-$tag" -j8 > "build/redo-$tag-b.log" 2>&1 \
    || { echo "  BUILD FAIL ($tag)"; tail -8 "build/redo-$tag-b.log"; return 1; }
  echo "  built $tag"
}

# harvest <built.a basename pattern> -> copy first match from build tree to deps-install/lib/<dest>
harvest() {
  local tag="$1" pat="$2" dest="$3"
  local f; f=$(find "build/redo-$tag" -name "$pat" | head -1)
  if [ -z "$f" ]; then echo "  HARVEST MISS $tag/$pat"; return 1; fi
  cp "$f" "$PREFIX/lib/$dest"
  local plat; plat=$(otool -l "$PREFIX/lib/$dest" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}')
  echo "  harvested $dest (platform=$plat $([ "$plat" = 2 ] && echo iOS✓ || echo BAD))"
}

# --- jpeg: build libjpeg-turbo 3.1.1 at JPEG_LIB_VERSION 80 to MATCH the v80 headers in
# deps-install/include. Do NOT copy pillow_ios's libjpeg.a here: it is v62 (libjpeg's
# DEFAULT ABI, struct 520), and its jpeg_CreateCompress rejects the version-80 callers
# baked into Blender's format_jpeg.cc, OpenImageIO and libtiff with JERR_BAD_LIB_VERSION
# -> JPEG save fails silently ("cannot save ...", errno 0; the output file is removed).
# build_libjpeg_ios.sh builds v80 and self-checks the ABI (0x50/0x248) before installing.
./build_libjpeg_ios.sh

build_dep fmt fmt-12.1.0 -DFMT_TEST=OFF -DFMT_DOC=OFF -DFMT_INSTALL=ON
harvest fmt "libfmt.a" libfmt.a

build_dep png libpng-1.6.44 -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF
harvest png "libpng*.a" libpng.a

build_dep expat expat-2.6.4 -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_SHARED_LIBS=OFF
harvest expat "libexpat*.a" libexpat.a

build_dep pugixml pugixml-1.14
harvest pugixml "libpugixml.a" libpugixml.a

build_dep yamlcpp yaml-cpp-0.8.0 -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_BUILD_SHARED_LIBS=OFF
harvest yamlcpp "libyaml-cpp*.a" libyaml-cpp.a

build_dep freetype freetype-2.13.3 -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_ZLIB=ON
harvest freetype "libfreetype.a" libfreetype.a

build_dep tiff tiff-4.7.1 -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-docs=OFF -Dtiff-contrib=OFF -Djpeg=OFF -Dzstd=OFF -Dlzma=OFF -Dwebp=OFF
harvest tiff "libtiff.a" libtiff.a

echo "=== done simple deps; OpenEXR + minizip handled separately ==="
