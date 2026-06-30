#!/bin/bash
# Cross-compile pandas 2.2.3 for iOS arm64 using meson-python.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
PANDAS_SRC="$ROOT/pandas-2.2.3"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"

[ -d "$PANDAS_SRC" ] || { echo "extract pandas-2.2.3.tar.gz first"; exit 1; }

# Use the iOS Python headers + iOS bundled numpy headers
NUMPY_INC=/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64/numpy/_core/include

# Generate a meson cross-file targeted at this SDK
CROSS_FILE="$ROOT/ios-arm64-cross-pandas.ini"
cat > "$CROSS_FILE" <<EOF
[binaries]
c = ['$IOS_CLANG', '-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-I$PY_HDRS', '-I$NUMPY_INC']
cpp = ['${IOS_CLANG}++', '-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-I$PY_HDRS', '-I$NUMPY_INC']
ar = '$(xcrun --sdk iphoneos --find ar)'
strip = '$(xcrun --sdk iphoneos --find strip)'
cython = ['/opt/homebrew/opt/python@3.14/bin/python3.14', '-m', 'cython']
python = 'python3'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-I$PY_HDRS', '-I$NUMPY_INC']
cpp_args = ['-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-I$PY_HDRS', '-I$NUMPY_INC']
c_link_args = ['-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-undefined', 'dynamic_lookup']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$IOS_SDK', '-miphoneos-version-min=13.0', '-undefined', 'dynamic_lookup']

[properties]
needs_exe_wrapper = true
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
system = 'darwin'
longdouble_format = 'IEEE_DOUBLE_LE'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
subsystem = 'ios'
EOF

echo "Wrote cross-file: $CROSS_FILE"
cd "$PANDAS_SRC"

# Configure with meson
BUILD_DIR="$PANDAS_SRC/build-ios"
rm -rf "$BUILD_DIR"
meson setup "$BUILD_DIR" --cross-file "$CROSS_FILE" --buildtype release 2>&1 | tail -20
echo ""
echo "=== Compile ==="
meson compile -C "$BUILD_DIR" 2>&1 | tee /tmp/pandas_meson_build.log | tail -40
echo ""
echo "=== .so files ==="
find "$BUILD_DIR" -name "*.so" | head -20
find "$BUILD_DIR" -name "*.so" | wc -l
