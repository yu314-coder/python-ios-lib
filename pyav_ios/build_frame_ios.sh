#!/bin/bash
# Rebuild PyAV's av.video.frame module for iOS arm64 (cpython-314-iphoneos)
# from the bundled sources, with python-ios-lib's copy_array_to_plane patch:
# VideoFrame.from_ndarray copies the array once, with the GIL released,
# instead of tobytes() plus a second copy, both holding the GIL.
#
# The bundled PyAV is a 17.0.1 pre-release snapshot built against the app's
# FFmpeg (libavcodec 62.29, libavutil 60.29). This compiles the bundled
# av/*.py + *.pxd (so every type layout matches the other bundled modules),
# PyAV 17.0.1's include/*.pxd (FFmpeg declarations; video/frame is the same
# in both) and FFmpeg 8.1.1's headers (same majors: 62 / 60; fields are only
# ever appended within a major). The result replaces
#   app_packages/site-packages/av/video/frame.cpython-314-iphoneos.so
# (Sources/FFmpegPyAV/av, the SwiftPM product, is a symlink to that folder)
# with the same load commands as the original (/tmp/ffmpeg-ios/... names,
# which scripts/fix_ffmpeg_paths.sh and the App Store wrap rewrite to @rpath).
# Checked: 309 from_ndarray cases (20 formats, odd sizes, strided and
# Fortran-order arrays) give the same plane bytes as the stock module.
#
# Usage: pyav_ios/build_frame_ios.sh [workdir]     (needs network the first time)
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
WORK="${1:-${TMPDIR:-/tmp}/pyav_ios_build}"
mkdir -p "$WORK"

AV_SRC="$REPO/app_packages/site-packages/av"
PY_XCF="$REPO/Frameworks/Python.xcframework/ios-arm64"
FF_LIBS="$REPO/Frameworks/ffmpeg"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"
MIN=13.0
OUT_NAME=frame.cpython-314-iphoneos.so

# --- inputs -------------------------------------------------------------------
if [ ! -d "$WORK/ffmpeg/libavcodec" ]; then
    mkdir -p "$WORK/ffmpeg"
    curl -fsSL https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n8.1.1.tar.gz \
        | tar -xz -C "$WORK/ffmpeg" --strip-components=1
fi
mkdir -p "$WORK/ffinc/libavutil"
cat > "$WORK/ffinc/libavutil/avconfig.h" <<'EOF'
/* What ffmpeg's configure writes for little-endian arm64. */
#ifndef AVUTIL_AVCONFIG_H
#define AVUTIL_AVCONFIG_H
#define AV_HAVE_BIGENDIAN 0
#define AV_HAVE_FAST_UNALIGNED 1
#endif /* AVUTIL_AVCONFIG_H */
EOF
if [ ! -d "$WORK/av-17.0.1/include" ]; then
    url=$(curl -fsSL https://pypi.org/pypi/av/17.0.1/json | python3 -c \
        "import json,sys; print([u['url'] for u in json.load(sys.stdin)['urls'] if u['packagetype']=='sdist'][0])")
    curl -fsSL "$url" | tar -xz -C "$WORK"
fi
if [ ! -x "$WORK/venv/bin/cython" ]; then
    uv venv -q -p 3.14 "$WORK/venv"
    uv pip install -q -p "$WORK/venv/bin/python" "cython>=3.1,<4"
fi

# --- source tree: the bundled sources + PyAV's FFmpeg declarations -------------
rm -rf "$WORK/tree"
mkdir -p "$WORK/tree"
rsync -a --include='*/' --include='*.py' --include='*.pxd' --exclude='*' "$AV_SRC/" "$WORK/tree/av/"
cp -R "$WORK/av-17.0.1/include" "$WORK/tree/include"
grep -q "python-ios-lib: one copy" "$WORK/tree/av/video/frame.py" || {
    echo "av/video/frame.py does not carry the copy_array_to_plane patch" >&2; exit 1; }

# --- cythonize (PyAV's setup.py directives) and cross-compile ------------------
( cd "$WORK/tree" && "$WORK/venv/bin/cython" -3 --module-name av.video.frame -I . -I include \
    -X c_string_type=str -X c_string_encoding=ascii -X embedsignature=True \
    -X binding=False -X freethreading_compatible=True \
    av/video/frame.py -o "$WORK/frame.c" )
"$IOS_CLANG" -arch arm64 -isysroot "$IOS_SDK" -miphoneos-version-min=$MIN -O3 -fPIC -w \
    -I"$PY_XCF/Python.framework/Headers" -I"$WORK/ffinc" -I"$WORK/ffmpeg" \
    -c "$WORK/frame.c" -o "$WORK/frame.o"
libs=()
for name in avdevice.62 avfilter.11 avformat.62 avcodec.62 swscale.9 swresample.6 avutil.60; do
    libs+=("$FF_LIBS/lib$name.dylib")
done
"$IOS_CLANG" -arch arm64 -isysroot "$IOS_SDK" -miphoneos-version-min=$MIN -bundle \
    -headerpad_max_install_names -F"$PY_XCF" -framework Python \
    "$WORK/frame.o" "${libs[@]}" -o "$WORK/$OUT_NAME"
for name in avdevice.62 avfilter.11 avformat.62 avcodec.62 swscale.9 swresample.6 avutil.60; do
    install_name_tool -change "@rpath/lib$name.dylib" \
        "/tmp/ffmpeg-ios/install/lib/lib$name.dylib" "$WORK/$OUT_NAME"
done
install_name_tool -id "build/lib.ios-13.0-arm64-iphoneos-cpython-314/av/video/$OUT_NAME" "$WORK/$OUT_NAME"
"$(xcrun --sdk iphoneos --find strip)" -x "$WORK/$OUT_NAME"
codesign -f -s - "$WORK/$OUT_NAME"

echo "load commands:"
otool -L "$WORK/$OUT_NAME" | sed 1d
# Sources/FFmpegPyAV/av (the SwiftPM product) is a symlink to this folder.
cp "$WORK/$OUT_NAME" "$AV_SRC/video/$OUT_NAME"
echo "installed $AV_SRC/video/$OUT_NAME"
