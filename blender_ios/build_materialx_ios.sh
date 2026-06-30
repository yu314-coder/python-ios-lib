#!/bin/bash
# Cross-compile MaterialX 1.39.4 for iOS arm64 (static) for Blender WITH_MATERIALX
# and as a dependency of the iOS USD build (PXR_ENABLE_MATERIALX_SUPPORT).
#
# Source: https://github.com/AcademySoftwareFoundation/MaterialX  tag v1.39.4
#   (extract to src/MaterialX-1.39.4)
#
# MaterialX 1.39 has built-in iOS support: MATERIALX_BUILD_APPLE_EMBEDDED is set
# automatically for an iphoneos sysroot, which turns OFF the GLSL/OSL shader-gen
# back-ends (no OpenGL on iOS) while keeping Core/Format/GenShader/GenMsl/GenMdl.
# Static (no shared libs), no render/python/viewer/tests.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"

cmake -S src/MaterialX-1.39.4 -B build/materialx-ios -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DMATERIALX_BUILD_PYTHON=OFF -DMATERIALX_BUILD_VIEWER=OFF -DMATERIALX_BUILD_GRAPH_EDITOR=OFF \
  -DMATERIALX_BUILD_TESTS=OFF -DMATERIALX_BUILD_SHARED_LIBS=OFF -DMATERIALX_BUILD_OIIO=OFF \
  -DMATERIALX_BUILD_RENDER=OFF -DMATERIALX_INSTALL_PYTHON=OFF

cmake --build build/materialx-ios -j6
cmake --install build/materialx-ios
echo "=== MaterialX installed ==="; ls -la "$PREFIX"/lib/libMaterialX*.a
