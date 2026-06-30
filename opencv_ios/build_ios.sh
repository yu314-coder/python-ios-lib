#!/usr/bin/env bash
# ============================================================================
# build_ios.sh — cross-build OpenCV (curated modules) + cv2 python binding
# for iOS arm64. "Full CV, not big": core, imgproc, imgcodecs(jpeg+png), photo,
# features2d, calib3d, objdetect, video, ml, flann + python3 bindings.
# Dropped (size): dnn, gapi, highgui, videoio, world, tiff/webp/openexr/jasper.
# cv2 links via -undefined dynamic_lookup (OpenCV's Apple path) — no libpython.
# Set CONFIGURE_ONLY=1 to stop after the config summary.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
SRC="$ROOT/opencv-4.10.0"
BUILD="$ROOT/build-ios"
PYXC="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PYINC="$PYXC/include/python3.14"; [ -f "$PYINC/Python.h" ] || PYINC="$PYXC/Python.framework/Headers"
NUMPYINC="/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64/numpy/_core/include"
HOSTPY="$(command -v python3)"

if [ "${CONFIGURE_ONLY:-0}" = "1" ] || [ ! -f "$BUILD/build.ninja" ]; then
  rm -rf "$BUILD"; mkdir -p "$BUILD"
  echo "[ocv] configure $(date '+%H:%M:%S')"
  cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_LIST=core,imgproc,imgcodecs,photo,features2d,calib3d,objdetect,video,ml,flann,python3 \
    -DBUILD_opencv_python3=ON -DBUILD_opencv_python2=OFF \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF -DBUILD_opencv_apps=OFF \
    -DBUILD_opencv_java=OFF -DBUILD_opencv_js=OFF -DBUILD_opencv_objc=OFF \
    -DWITH_FFMPEG=OFF -DWITH_QT=OFF -DWITH_GTK=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF \
    -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_PROTOBUF=OFF -DWITH_ADE=OFF -DWITH_EIGEN=OFF \
    -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_OPENEXR=OFF -DWITH_JASPER=OFF \
    -DWITH_JPEG=ON -DWITH_PNG=ON -DBUILD_JPEG=ON -DBUILD_PNG=ON -DBUILD_ZLIB=ON \
    -DPYTHON3_EXECUTABLE="$HOSTPY" \
    -DPYTHON3_INCLUDE_PATH="$PYINC" \
    -DPYTHON3_NUMPY_INCLUDE_DIRS="$NUMPYINC" \
    -DPYTHON3_LIBRARIES="$PYXC/lib/libpython3.14.dylib" \
    -DPYTHON3_VERSION_STRING=3.14.0 -DPYTHON3_VERSION_MAJOR=3 -DPYTHON3_VERSION_MINOR=14 \
    -DOPENCV_PYTHON3_VERSION=3.14 -DOPENCV_SKIP_PYTHON_LOADER=ON \
    -DOPENCV_PYTHON3_INSTALL_PATH="python" \
    > /tmp/ocv_cfg.log 2>&1 || { echo "CONFIGURE FAILED:"; grep -iE "CMake Error" -A4 /tmp/ocv_cfg.log | head -20; exit 1; }
  echo "[ocv] --- Python 3 summary ---"; grep -A6 -iE "^--   Python 3:" /tmp/ocv_cfg.log | head -8
  echo "[ocv] --- modules to be built ---"; grep -A2 "To be built:" /tmp/ocv_cfg.log | head -4
fi
[ "${CONFIGURE_ONLY:-0}" = "1" ] && { echo "[ocv] configure-only done"; exit 0; }

echo "[ocv] build $(date '+%H:%M:%S') (long) ..."
# Build the cv2 module target specifically (not 'all') — avoids the
# copy_opencv_typing_stubs target, whose .pyi we intentionally skip on iOS
# (see the gen2.py patch: typing stubs abort on gapi's GProtoArg).
ninja -C "$BUILD" opencv_python3

# ---- locate + assemble cv2 ------------------------------------------------
CV2="$(find "$BUILD" -name 'cv2*.so' | head -1)"
echo "[ocv] built cv2: $CV2"
[ -n "$CV2" ] || { echo "FATAL: cv2*.so not found"; exit 1; }
OUT="$ROOT/out"; mkdir -p "$OUT"
cp "$CV2" "$OUT/cv2.cpython-314-iphoneos.so"
xcrun --sdk iphoneos strip -x "$OUT/cv2.cpython-314-iphoneos.so" 2>/dev/null || true

echo "========================================================"
SO="$OUT/cv2.cpython-314-iphoneos.so"
file "$SO"
xcrun --sdk iphoneos vtool -show-build "$SO" 2>/dev/null | grep -iE "platform|minos" || true
echo "--- PyInit export ---"; nm -gU "$SO" 2>/dev/null | grep -i "PyInit_cv2" || echo "  !! missing"
echo "--- size ---"; du -h "$SO" | cut -f1
echo "[ocv] DONE"
