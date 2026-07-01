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
  -DWITH_RUBBERBAND=OFF -DWITH_LIBMV=ON \
  `# libmv ON: motion tracking / camera solver. ceres-solver 2.2.0 cross-built for` \
  `# iOS (build_ceres_ios.sh) against Blender's own Eigen 5.0.1 -- ceres' find_package` \
  `# (Eigen3 3.3) SameMajor guard was dropped so it accepts Eigen 5.x (same ABI as libmv).` \
  -DWITH_TRACY=OFF \
  -DWITH_USD=ON -DWITH_HYDRA=OFF -DWITH_MATERIALX=ON \
  `# USD = OpenUSD 26.03 built minimal-for-iOS (no boost: python+openvdb off; no GL;` \
  `# imaging/usdImaging + MaterialX support ON; monolithic libusd_ms.dylib). Hydra OFF` \
  `# (needs a live GPU context). See bpy_ios_source.patch for the io/usd compile guards.` \
  \
  -DWITH_CODEC_FFMPEG=ON -DWITH_CODEC_SNDFILE=ON -DWITH_JACK=OFF \
  `# sndfile ON: libsndfile cross-built minimal (build_sndfile_ios.sh, no FLAC/Ogg/` \
  `# Vorbis) -> aud/VSE can load uncompressed audio (WAV/AIFF/AU/CAF/W64).` \
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
  -DHOST_MSGFMT="$PWD/build/blender/host_msgfmt" \
  `# .po->.mo built by a host msgfmt shim, not the un-runnable cross msgfmt (below).` \
  \
  "$@"

echo "=== configure exit: $? ==="

# --- host msgfmt shim (WITH_INTERNATIONAL) -----------------------------------
# The cross-compiled msgfmt is an iOS arm64 binary and cannot run on the host
# (SIGKILL/exit 137), yet ninja must turn each locale/po/*.po into a .mo during
# the build. The durable fix is source-side (see bpy_ios_source.patch):
#   - macros.cmake msgfmt_simple() uses HOST_MSGFMT (this shim) for the .po->.mo
#     custom commands instead of the cross `msgfmt` target, and depends on the
#     shim file rather than the target;
#   - the msgfmt target is EXCLUDE_FROM_ALL when HOST_MSGFMT is set, so ninja
#     never links the iOS binary at all (no clobbering, even on incremental
#     rebuilds that relink msgfmt's dependency libs).
# Install the shim at the HOST_MSGFMT path with an OLD mtime (so the .mo are
# generated once, not on every incremental build). Idempotent.
HOST_MSGFMT_PATH="$PWD/build/blender/host_msgfmt"
cat > "$HOST_MSGFMT_PATH" <<'SHIM_EOF'
#!/bin/bash
# Host shim for Blender's iOS-cross-compiled msgfmt (see configure_blender.sh).
# Blender's msgfmt.cc CLI: msgfmt <input.po> <output.mo> (positional, no flags).
# GNU msgfmt wants: msgfmt <input.po> -o <output.mo>. Translate; on any failure
# fall back to a minimal valid empty .mo so one malformed/incompatible .po never
# hard-fails the whole build -- but emit a stderr warning so a SYSTEMIC failure
# (msgfmt missing entirely) is visible in the build log rather than silent.
set -u
IN="$1"; OUT="$2"
# Robust host-msgfmt discovery (not hardcoded to one Homebrew prefix).
REAL="$(command -v msgfmt 2>/dev/null)"
[ -z "$REAL" ] && for c in /opt/homebrew/bin/msgfmt /usr/local/bin/msgfmt /usr/bin/msgfmt; do
  [ -x "$c" ] && { REAL="$c"; break; }
done

if [ -n "$REAL" ] && "$REAL" "$IN" -o "$OUT" >/dev/null 2>&1 && [ -s "$OUT" ]; then
  exit 0
fi

echo "msgfmt-shim: WARNING falling back to EMPTY .mo for $IN (real msgfmt='${REAL:-NONE}' failed/missing)" >&2
# Minimal valid empty GNU .mo: magic, revision=0, nstrings=0, orig/trans/hash
# table offsets all 28 (right after this 28-byte header), hash size 0.
printf '\336\022\004\225\000\000\000\000\000\000\000\000\034\000\000\000\034\000\000\000\000\000\000\000\034\000\000\000' > "$OUT"
exit 0
SHIM_EOF
chmod +x "$HOST_MSGFMT_PATH"
touch -t 200001010000 "$HOST_MSGFMT_PATH"
echo "=== msgfmt host shim installed: $HOST_MSGFMT_PATH ==="
