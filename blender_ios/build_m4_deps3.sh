#!/bin/bash
cd "$(dirname "$0")"; export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
IOS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF)
plat() { otool -l "$1" 2>/dev/null|grep -A3 LC_BUILD_VERSION|grep platform|head -1|awk '{print $2}'; }
b() { local t="$1" s="$2"; shift 2; echo "== $t =="; rm -rf "build/m4-$t"; cmake -S "src/$s" -B "build/m4-$t" -G Ninja "${IOS[@]}" "$@" > "build/m4-$t-cfg.log" 2>&1 || { echo "  CFG FAIL"; grep -iE "error|could not find" "build/m4-$t-cfg.log"|head -6; return 1; }; cmake --build "build/m4-$t" -j8 > "build/m4-$t-b.log" 2>&1 || { echo "  BUILD FAIL"; grep -iE "error:" "build/m4-$t-b.log"|grep -ivE "unguarded|introduced"|sed -E 's/^.*error:/error:/'|sort -u|head -8; return 1; }; cmake --install "build/m4-$t" > "build/m4-$t-i.log" 2>&1 || true; echo "  ok"; }

b haru libharu-2.4.5 -DLIBHPDF_SHARED=OFF -DLIBHPDF_STATIC=ON -DLIBHPDF_EXAMPLES=OFF -DBUILD_SHARED_LIBS=OFF
f=$(find build/m4-haru "$PREFIX" -name "libhpdf*.a" 2>/dev/null|head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/libhpdf.a" && echo "  libhpdf plat=$(plat "$PREFIX/lib/libhpdf.a")"

b harfbuzz harfbuzz-10.0.1 -DHB_HAVE_FREETYPE=ON -DHB_BUILD_SUBSET=OFF -DHB_HAVE_GLIB=OFF -DHB_HAVE_ICU=OFF
f=$(find build/m4-harfbuzz "$PREFIX" -name "libharfbuzz.a" 2>/dev/null|head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/" && echo "  libharfbuzz plat=$(plat "$PREFIX/lib/libharfbuzz.a")"

b openpgl openpgl-0.7.1 -DOPENPGL_BUILD_STATIC=ON -DOPENPGL_ISA_NEON=ON -DOPENPGL_ISA_AVX2=OFF -DOPENPGL_ISA_AVX512=OFF -DOPENPGL_ISA_SSE4=OFF -DOPENPGL_TBB_ROOT="$PREFIX" -DTBB_DIR="$PREFIX/lib/cmake/TBB"
f=$(find build/m4-openpgl "$PREFIX" -name "libopenpgl.a" 2>/dev/null|head -1); [ -n "$f" ] && cp "$f" "$PREFIX/lib/" && echo "  libopenpgl plat=$(plat "$PREFIX/lib/libopenpgl.a")"
