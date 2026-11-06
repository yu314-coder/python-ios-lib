#!/bin/bash
# Rebuild libavcodec for iOS arm64 with python-ios-lib's VideoToolbox patch
# (videotoolbox_max_pending.patch) and install it as
#   Frameworks/ffmpeg/libavcodec.62.29.101.dylib
# (Sources/FFmpegPyAV/ffmpeg, the SwiftPM product, is a symlink to that folder).
#
# The app's FFmpeg is the git snapshot "git-2026-04-07-0510aff" (av_version_info
# of the bundled libavutil), libavcodec 62.29.101. This builds that exact commit
# with the configure line embedded in the bundled libraries (avutil_configuration),
# plus --disable-lzma: the original links no liblzma, and a Mac with Homebrew's
# Intel liblzma in /usr/local would otherwise pick it up and fail to link. Only
# libavcodec changes, so the other six libraries and PyAV are untouched. The
# rebuilt library exports the same 445 symbols and imports three more from
# libSystem: clock_gettime and pthread_cond_timedwait (the patch's wait) and
# wcslen (this SDK's build; nothing else changed).
#
# The patch: VideoToolbox takes frames as fast as they come and keeps a copy of
# each until it is encoded, so a sender quicker than the hardware leaves it
# holding a queue of whole frames. The new encoder option max_pending_frames
# (default 0, no limit) makes sending wait while that many are being encoded
# (counted by its output callback, once per frame; at most 2 s per wait; not
# with frame reordering). manim's writer sets it (settings.encoder_pending_frames).
#
# Usage: ffmpeg_ios/build_libavcodec_ios.sh [workdir]     (needs network)
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
WORK="${1:-${TMPDIR:-/tmp}/ffmpeg_ios_build}"
COMMIT=0510aff
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$WORK"

if [ ! -f "$WORK/src/configure" ]; then
    mkdir -p "$WORK/src"
    curl -fsSL "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/$COMMIT" \
        | tar -xz -C "$WORK/src" --strip-components=1
    patch -d "$WORK/src" -p1 < "$REPO/ffmpeg_ios/videotoolbox_max_pending.patch"
fi
grep -q "max_pending_frames" "$WORK/src/libavcodec/videotoolboxenc.c"

mkdir -p "$WORK/build"
cd "$WORK/build"
../src/configure --enable-cross-compile --target-os=darwin --arch=arm64 \
    --cc="clang -target arm64-apple-ios17.0 -isysroot $SDK" \
    --cxx="clang++ -target arm64-apple-ios17.0 -isysroot $SDK" \
    --sysroot="$SDK" \
    --extra-cflags='-miphoneos-version-min=17.0 -fPIC' \
    --extra-ldflags='-miphoneos-version-min=17.0' \
    --disable-static --enable-shared --disable-programs --disable-doc \
    --disable-debug --disable-network --disable-lzma \
    --prefix=/tmp/ffmpeg-ios/install > configure.log
make -j"$(sysctl -n hw.ncpu)" > make.log

OUT="$WORK/libavcodec.62.29.101.dylib"
cp libavcodec/libavcodec.62.dylib "$OUT"
install_name_tool -id @rpath/libavcodec.62.dylib \
    -change /tmp/ffmpeg-ios/install/lib/libswresample.6.dylib @rpath/libswresample.6.dylib \
    -change /tmp/ffmpeg-ios/install/lib/libavutil.60.dylib @rpath/libavutil.60.dylib \
    "$OUT" 2>/dev/null
"$(xcrun --sdk iphoneos --find strip)" -x "$OUT"
codesign -f -s - "$OUT"

ORIG="$REPO/Frameworks/ffmpeg/libavcodec.62.29.101.dylib"
if ! diff <(nm -gU "$ORIG" | awk '{print $3}' | sort) <(nm -gU "$OUT" | awk '{print $3}' | sort) >/dev/null; then
    echo "exported symbols differ from the installed libavcodec; not installing" >&2
    exit 1
fi
cp "$OUT" "$ORIG"
echo "installed $ORIG"
