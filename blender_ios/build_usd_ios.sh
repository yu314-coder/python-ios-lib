#!/bin/bash
# Cross-compile OpenUSD 26.03 for iOS arm64 as a minimal monolithic library for
# the Blender (bpy) USD I/O integration (WITH_USD).
#
# Source: https://github.com/PixarAnimationStudios/OpenUSD  tag v26.03
#   (extract to src/OpenUSD-26.03)
#
# Key choices that make USD cross-compile for iOS WITHOUT pulling in Boost:
#   - PXR_ENABLE_PYTHON_SUPPORT=OFF  + PXR_ENABLE_OPENVDB_SUPPORT=OFF
#       USD's find_package(Boost REQUIRED) is gated on those two; disabling both
#       avoids Boost entirely. (The Python USD-hook bridge in Blender's
#       io/usd/usd_hook.cc is stubbed instead — see bpy_ios_source.patch.)
#   - PXR_ENABLE_GL_SUPPORT=OFF / VULKAN off / METAL off
#       no GL on iOS, and with Metal OFF too USD reports "Skipping hdStorm" and
#       omits the GL/Metal render plugin ENTIRELY. This is load-bearing: if ANY
#       HGI backend stays enabled, hdStorm fails to compile and that failure
#       HALTS the monolithic link, producing a libusd_ms.dylib with NO imaging
#       symbols (HdMeshTopology missing) -> "symbol not found" at `import bpy`.
#       Metal OFF makes the monolithic build complete cleanly WITH imaging.
#       Blender needs no render delegate (WITH_HYDRA=OFF).
#   - PXR_BUILD_IMAGING=ON + PXR_BUILD_USD_IMAGING=ON
#       Blender's usd_reader_shape needs usdImaging adapters (capsule/sphere...).
#       Imaging builds GPU-agnostic without GL; uses the bundled OpenSubdiv.
#   - PXR_ENABLE_MATERIALX_SUPPORT=ON
#       Blender's usd_writer_material needs usdMtlx (build MaterialX first:
#       ./build_materialx_ios.sh).
#   - PXR_BUILD_MONOLITHIC=ON  -> one libusd_ms.dylib (Blender FindUSD wants usd_ms)
#   - PXR_SET_INTERNAL_NAMESPACE=pxrBlender_v26_03  (Blender's USD_NAMESPACE for v26.03)
#
# Deploy for the CodeBench app: libusd_ms.dylib + lib/usd + plugin/usd are bundled
# under app_packages/site-packages/bpy/{lib,usd_resources}/ and discovered at
# runtime via PXR_PLUGINPATH_NAME (set in PythonRuntime.swift).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
SRC=src/OpenUSD-26.03

cmake -S "$SRC" -B build/usd-ios -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DPXR_ENABLE_PYTHON_SUPPORT=OFF -DPXR_ENABLE_OPENVDB_SUPPORT=OFF \
  -DPXR_BUILD_IMAGING=ON -DPXR_BUILD_USD_IMAGING=ON \
  -DPXR_ENABLE_GL_SUPPORT=OFF -DPXR_ENABLE_VULKAN_SUPPORT=OFF -DPXR_ENABLE_METAL_SUPPORT=OFF \
  -DPXR_ENABLE_MATERIALX_SUPPORT=ON -DPXR_ENABLE_OSL_SUPPORT=OFF -DPXR_ENABLE_HDF5_SUPPORT=OFF \
  -DPXR_BUILD_MONOLITHIC=ON -DPXR_BUILD_TESTS=OFF -DPXR_BUILD_EXAMPLES=OFF \
  -DPXR_BUILD_TUTORIALS=OFF -DPXR_BUILD_USDVIEW=OFF \
  -DPXR_BUILD_OPENIMAGEIO_PLUGIN=OFF -DPXR_BUILD_OPENCOLORIO_PLUGIN=OFF \
  -DPXR_SET_INTERNAL_NAMESPACE=pxrBlender_v26_03

# With GL+Metal+Vulkan all OFF, USD skips hdStorm entirely, so the monolithic
# build completes cleanly — there is no plugin failure to mask. Build strictly:
# a non-zero exit here is a REAL error (do not swallow it).
cmake --build build/usd-ios -j6
cmake --install build/usd-ios
echo "=== USD installed ==="
ls -la "$PREFIX"/lib/libusd_ms.dylib
# Sanity gate: the monolithic lib MUST contain the usdImaging symbols, or
# `import bpy` fails at runtime ("symbol not found: ...HdMeshTopology..."). This
# is the exact failure PXR_ENABLE_METAL_SUPPORT=OFF prevents — verify it stuck.
if ! nm "$PREFIX"/lib/libusd_ms.dylib | grep -q HdMeshTopology; then
  echo "ERROR: libusd_ms.dylib is missing imaging (HdMeshTopology) — an HGI" \
       "backend was pulled back in and halted the monolithic link. Re-check the" \
       "PXR_ENABLE_{GL,METAL,VULKAN}_SUPPORT=OFF flags above." >&2
  exit 1
fi
echo "imaging OK: HdMeshTopology present ($(nm "$PREFIX"/lib/libusd_ms.dylib | grep -c HdMeshTopology) syms)"
