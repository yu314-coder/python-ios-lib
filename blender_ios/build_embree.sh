#!/bin/bash
cd "$(dirname "$0")"; export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"; rm -rf build/m4-embree
cmake -S src/embree-4.4.1 -B build/m4-embree -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF \
  -DEMBREE_ISPC_SUPPORT=OFF -DEMBREE_TUTORIALS=OFF -DEMBREE_STATIC_LIB=ON \
  -DEMBREE_ISA_NEON=ON -DEMBREE_ISA_NEON2X=OFF -DEMBREE_ISA_SSE2=OFF -DEMBREE_ISA_SSE42=OFF \
  -DEMBREE_ISA_AVX=OFF -DEMBREE_ISA_AVX2=OFF -DEMBREE_ISA_AVX512=OFF \
  -DEMBREE_TASKING_SYSTEM=TBB -DEMBREE_TBB_ROOT="/Volumes/D/OfflinAi/blender_ios/deps-install" -DTBB_ROOT="/Volumes/D/OfflinAi/blender_ios/deps-install" -DTBB_DIR="/Volumes/D/OfflinAi/blender_ios/deps-install/lib/cmake/TBB" \
  -DEMBREE_FILTER_FUNCTION=ON -DEMBREE_RAY_MASK=ON > build/m4-embree-cfg.log 2>&1 || { echo "CFG FAIL"; grep -iE "error|could not find" build/m4-embree-cfg.log | head -8; exit 1; }
echo "configured"
cmake --build build/m4-embree -j8 > build/m4-embree-b.log 2>&1 || { echo "BUILD FAIL"; grep -iE "error:" build/m4-embree-b.log | grep -ivE "unguarded|introduced" | sed -E 's/^.*error:/error:/' | sort -u | head -10; exit 1; }
cmake --install build/m4-embree > build/m4-embree-i.log 2>&1 || true
f=$(find build/m4-embree "$PREFIX" -name "libembree4.a" 2>/dev/null | head -1); cp "$f" "$PREFIX/lib/" 2>/dev/null
echo "libembree4 plat=$(otool -l "$PREFIX/lib/libembree4.a" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}')"
