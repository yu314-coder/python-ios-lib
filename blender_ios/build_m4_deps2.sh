#!/bin/bash
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
plat() { otool -l "$1" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}'; }
build() { local tag="$1" sub="$2"; shift 2; echo "== $tag =="; rm -rf "build/m4-$tag"
  cmake -S "src/$sub" -B "build/m4-$tag" -G Ninja "${IOS[@]}" "$@" > "build/m4-$tag-cfg.log" 2>&1 || { echo "  CFG FAIL"; tail -8 "build/m4-$tag-cfg.log"; return 1; }
  cmake --build "build/m4-$tag" -j8 > "build/m4-$tag-b.log" 2>&1 || { echo "  BUILD FAIL"; tail -12 "build/m4-$tag-b.log"; return 1; }
  cmake --install "build/m4-$tag" > "build/m4-$tag-i.log" 2>&1 || true
  echo "  built+installed"
}

# meshoptimizer (glTF mesh compression)
build meshopt meshoptimizer-1.1 -DMESHOPT_BUILD_DEMO=OFF -DMESHOPT_BUILD_TOOLS=OFF -DMESHOPT_BUILD_SHARED_LIBS=OFF
f=$(find build/m4-meshopt "$PREFIX" -name "libmeshoptimizer.a" 2>/dev/null | head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/" && echo "  libmeshoptimizer plat=$(plat "$PREFIX/lib/libmeshoptimizer.a")"

# c-blosc (OpenVDB compression dep)
build blosc c-blosc-1.21.1 -DBUILD_SHARED=OFF -DBUILD_STATIC=ON -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_FUZZERS=OFF -DPREFER_EXTERNAL_ZLIB=ON
f=$(find build/m4-blosc -name "libblosc.a" 2>/dev/null | head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/" && echo "  libblosc plat=$(plat "$PREFIX/lib/libblosc.a")"
mkdir -p "$PREFIX/include"; cp src/c-blosc-1.21.1/blosc/blosc.h src/c-blosc-1.21.1/blosc/blosc-export.h "$PREFIX/include/" 2>/dev/null || true

# Alembic (.abc I/O) — needs Imath (already in deps-install)
build alembic alembic-1.8.8 -DUSE_TESTS=OFF -DALEMBIC_SHARED_LIBS=OFF -DUSE_BINARIES=OFF -DALEMBIC_ILMBASE_LINK_STATIC=ON -DImath_DIR="$PREFIX/lib/cmake/Imath"
f=$(find build/m4-alembic "$PREFIX" -name "libAlembic.a" 2>/dev/null | head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/" && echo "  libAlembic plat=$(plat "$PREFIX/lib/libAlembic.a")"

echo "=== batch 2 done ==="
ls -la "$PREFIX"/lib/libmeshoptimizer.a "$PREFIX"/lib/libblosc.a "$PREFIX"/lib/libAlembic.a 2>/dev/null | awk '{print $NF, $5}'
