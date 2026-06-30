#!/bin/bash
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
rm -rf build/m4-openvdb
cmake -S src/openvdb-13.0.0 -B build/m4-openvdb -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF \
  -DOPENVDB_USE_DELAYED_LOADING=OFF -DUSE_BLOSC=ON -DUSE_ZLIB=ON -DUSE_IMATH_HALF=ON \
  -DOPENVDB_CORE_SHARED=OFF -DOPENVDB_CORE_STATIC=ON -DOPENVDB_BUILD_BINARIES=OFF \
  -DOPENVDB_BUILD_PYTHON_MODULE=OFF -DUSE_EXPLICIT_INSTANTIATION=OFF -DOPENVDB_BUILD_NANOVDB=OFF \
  -DTBB_ROOT="$PREFIX" -DBlosc_ROOT="$PREFIX" -DImath_ROOT="$PREFIX" > build/m4-openvdb-cfg.log 2>&1 || { echo "CFG FAIL"; grep -iE "error|could not find" build/m4-openvdb-cfg.log | head -8; exit 1; }
echo "configured OK"
cmake --build build/m4-openvdb -j8 > build/m4-openvdb-b.log 2>&1 || { echo "BUILD FAIL"; grep -iE "error:" build/m4-openvdb-b.log | grep -ivE "unguarded|introduced" | sed -E 's/^.*error:/error:/' | sort -u | head -12; exit 1; }
cmake --install build/m4-openvdb > build/m4-openvdb-i.log 2>&1 || true
f=$(find build/m4-openvdb "$PREFIX" -name "libopenvdb.a" 2>/dev/null | head -1); cp "$f" "$PREFIX/lib/" 2>/dev/null
echo "libopenvdb plat=$(otool -l "$PREFIX/lib/libopenvdb.a" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}')"
