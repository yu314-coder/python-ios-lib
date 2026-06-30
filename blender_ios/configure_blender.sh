#!/bin/bash
# Configure Blender as an iOS arm64 Python module (bpy.cpython-314-iphoneos / bin/bpy/__init__.so).
# Resumable source-of-truth for the OfflinAi Blender port. See PLAN.md.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
PYROOT=/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64

# Clean configure (a stale cache keeps the macOS-forced sysroot/deployment).
rm -rf build/blender

cmake -S blender -B build/blender -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DLIBDIR="$PREFIX" \
  -DCMAKE_HAVE_LIBC_PTHREAD=1 -DTHREADS_PREFER_PTHREAD_FLAG=OFF \
  -DHOST_TOOLS_DIR="$PWD/build/host-tools" \
  -DWITH_PYTHON=ON -DWITH_PYTHON_MODULE=ON -DWITH_PYTHON_INSTALL=OFF -DPYTHON_VERSION=3.14 \
  -DPYTHON_INCLUDE_DIR="$PYROOT/include/python3.14" -DPYTHON_INCLUDE_CONFIG_DIR="$PYROOT/include/python3.14" \
  -DPYTHON_LIBRARY="$PYROOT/lib/libpython3.14.dylib" -DPYTHON_LIBPATH="$PYROOT/lib" \
  -DFREETYPE_INCLUDE_DIRS="$PREFIX/include/freetype2" -DFREETYPE_LIBRARY="$PREFIX/lib/libfreetype.a" \
  -DWITH_HEADLESS=ON -DWITH_CYCLES=ON -DWITH_CYCLES_DEVICE_METAL=ON -DWITH_GPU_BACKEND=none -DWITH_METAL_BACKEND=OFF \
  -DWITH_VULKAN_BACKEND=OFF -DWITH_OPENGL=OFF \
  -DWITH_BLENDER_THUMBNAILER=OFF \
  `# macOS-only QuickLook .appex; pulls in AppKit/NSImage which isn't on iOS` \
  -DWITH_OPENIMAGEIO=ON -DWITH_OPENCOLORIO=ON -DWITH_IMAGE_OPENEXR=ON -DWITH_TBB=ON \
  -DWITH_CYCLES_OSL=OFF \
  -DWITH_RUBBERBAND=OFF -DWITH_LIBMV=OFF \
  `# libmv OFF: needs ceres-solver, which rejects Blender's Eigen 5.0.1 (API clash)` \
  -DWITH_TRACY=OFF \
  -DWITH_USD=ON -DWITH_HYDRA=OFF -DWITH_MATERIALX=ON \
  `# USD = OpenUSD 26.03 built minimal-for-iOS (no boost: python+openvdb off; no GL;` \
  `# imaging/usdImaging + MaterialX support ON; monolithic libusd_ms.dylib). Hydra OFF` \
  `# (needs a live GPU context). See bpy_ios_source.patch for the io/usd compile guards.` \
  \
  -DWITH_CODEC_FFMPEG=ON -DWITH_CODEC_SNDFILE=OFF -DWITH_JACK=OFF \
  -DWITH_PULSEAUDIO=OFF -DWITH_COREAUDIO=OFF -DWITH_OPENAL=OFF -DWITH_SDL=OFF -DWITH_AUDASPACE=ON \
  `# audaspace ON gives the 'aud' module; backends OFF (no playback) is fine headless.` \
  `# The aud bindings need numpy C headers — point at the bundled iOS numpy:` \
  -DPYTHON_NUMPY_PATH=/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64 \
  -DPYTHON_NUMPY_INCLUDE_DIRS=/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64/numpy/_core/include \
  -DWITH_INPUT_NDOF=OFF -DWITH_XR_OPENXR=OFF -DWITH_BOOST=OFF \
  -DWITH_FRIBIDI=ON -DWITH_INTERNATIONAL=ON \
  `# i18n: fribidi cross-built (src/fribidi-1.0.16, meson); .mo built with a host msgfmt` \
  `# shim (build/blender/bin/msgfmt.app/msgfmt) since the cross msgfmt can't run on host.` \
  -DWITH_BUILDINFO=OFF \
  -DWITH_IMAGE_CINEON=ON \
  \
  "$@"

echo "=== configure exit: $? ==="
