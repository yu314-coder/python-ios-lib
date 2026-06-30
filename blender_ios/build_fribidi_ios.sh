#!/bin/bash
# Cross-compile fribidi 1.0.16 for iOS arm64 (static) for Blender WITH_FRIBIDI /
# WITH_INTERNATIONAL (Unicode bidi for RTL text in translations).
#
# Source: https://github.com/fribidi/fribidi  tag v1.0.16 (extract to
#   src/fribidi-1.0.16). fribidi uses meson, so we cross-build with an iOS
#   meson cross-file (written here from the live iphoneos SDK path).
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SRC=src/fribidi-1.0.16

cat > "$SRC/ios-cross.txt" <<EOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=16.4']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-miphoneos-version-min=16.4']
EOF

rm -rf "$SRC/build-ios"
meson setup "$SRC/build-ios" "$SRC" --cross-file "$SRC/ios-cross.txt" --prefix="$PREFIX" \
  -Ddocs=false -Dtests=false -Dbin=false -Ddefault_library=static --buildtype=release
meson compile -C "$SRC/build-ios"
meson install -C "$SRC/build-ios"
echo "=== fribidi installed ==="; ls -la "$PREFIX"/lib/libfribidi.a
