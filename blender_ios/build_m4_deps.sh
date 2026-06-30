#!/bin/bash
# Cross-build M4 (full-bpy) dependencies for iOS arm64. Bash (NOT zsh) so the
# flag array word-splits correctly. Harvests .a from build trees (most deps
# ignore CMAKE_INSTALL_PREFIX). Each dep verified platform=iOS(2) after.
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

cfg_build() {  # <tag> <srcdir> [extra cmake args...]
  local tag="$1" sub="$2"; shift 2
  echo "== $tag =="
  rm -rf "build/m4-$tag"
  cmake -S "src/$sub" -B "build/m4-$tag" -G Ninja "${IOS[@]}" "$@" > "build/m4-$tag-cfg.log" 2>&1 \
    || { echo "  CFG FAIL"; tail -6 "build/m4-$tag-cfg.log"; return 1; }
  cmake --build "build/m4-$tag" -j8 > "build/m4-$tag-b.log" 2>&1 \
    || { echo "  BUILD FAIL"; tail -10 "build/m4-$tag-b.log"; return 1; }
  echo "  built"
}

harvest() {  # <tag> <pattern> <dest-name>
  local tag="$1" pat="$2" dest="$3" f
  f=$(find "build/m4-$tag" -name "$pat" | head -1)
  [ -z "$f" ] && { echo "  HARVEST MISS $pat"; return 1; }
  chmod u+w "$PREFIX/lib/$dest" 2>/dev/null || true
  cp "$f" "$PREFIX/lib/$dest"
  echo "  $dest plat=$(plat "$PREFIX/lib/$dest")"
}

# ---- OpenSubdiv (subdivision surfaces). TBB already in deps-install. ----
cfg_build opensubdiv OpenSubdiv-3_7_0 \
  -DNO_TUTORIALS=ON -DNO_EXAMPLES=ON -DNO_REGRESSION=ON -DNO_DOC=ON -DNO_OMP=ON \
  -DNO_CUDA=ON -DNO_OPENCL=ON -DNO_DX=ON -DNO_TESTS=ON -DNO_GLTESTS=ON -DNO_GLEW=ON -DNO_GLFW=ON \
  -DNO_PTEX=ON -DNO_TBB=OFF -DNO_METAL=OFF -DNO_OPENGL=ON
harvest opensubdiv "libosdCPU.a" libosdCPU.a
harvest opensubdiv "libosdGPU.a" libosdGPU.a || true
mkdir -p "$PREFIX/include/opensubdiv"
cp -R src/OpenSubdiv-3_7_0/opensubdiv "$PREFIX/include/opensubdiv/" 2>/dev/null || true
# headers: OpenSubdiv installs include/opensubdiv/{far,osd,...}
find src/OpenSubdiv-3_7_0/opensubdiv -name "*.h" >/dev/null 2>&1 && \
  (cd src/OpenSubdiv-3_7_0 && find opensubdiv -name "*.h" | while read h; do mkdir -p "$PREFIX/include/$(dirname "$h")"; cp "$h" "$PREFIX/include/$h"; done)

# ---- draco (mesh compression for glTF) ----
cfg_build draco draco-1.5.7 -DDRACO_TESTS=OFF
harvest draco "libdraco.a" libdraco.a
mkdir -p "$PREFIX/include/draco"
(cd src/draco-1.5.7/src && find draco -name "*.h" | while read h; do mkdir -p "$PREFIX/include/$(dirname "$h")"; cp "$h" "$PREFIX/include/$h"; done)
cp build/m4-draco/draco/draco_features.h "$PREFIX/include/draco/" 2>/dev/null || true

echo "=== M4 dep batch done ==="
ls -la "$PREFIX"/lib/libosdCPU.a "$PREFIX"/lib/libdraco.a 2>/dev/null | awk '{print $NF, $5}'
