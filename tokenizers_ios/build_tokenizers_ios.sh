#!/bin/bash
# build_tokenizers_ios.sh — cross-compile HuggingFace tokenizers 0.19.1 for iOS arm64,
# linking against BeeWare's Python.xcframework (Python 3.14.2).
#
# Output:
#   ./tokenizers/bindings/python/target/aarch64-apple-ios/release/libtokenizers.dylib
#   (gets renamed + signed for drop-in into app_packages/site-packages/tokenizers/)

set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
SRC="$ROOT/tokenizers/bindings/python"

# ---- Rust + cargo ---------------------------------------------------------
source "$HOME/.cargo/env"

# ---- iOS SDK + Python framework paths -------------------------------------
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IOS_CLANG=$(xcrun --sdk iphoneos --find clang)
IOS_AR=$(xcrun --sdk iphoneos --find ar)
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_FW="$PY_XCF/Python.framework"
PY_LIB_DIR="$PY_FW"                   # contains `Python` dylib
PY_INCLUDE_DIR="$PY_FW/Headers"
# _sysconfigdata lives in platform-config/ — PyO3 needs it to know build flags.
PY_SYSCONFIG_DIR="$PY_XCF/platform-config/arm64-iphoneos"

echo "iOS SDK:         $IOS_SDK"
echo "iOS clang:       $IOS_CLANG"
echo "Python lib dir:  $PY_LIB_DIR"
echo "Python headers:  $PY_INCLUDE_DIR"

# ---- PyO3 cross-compile config --------------------------------------------
# PyO3 needs to know where headers + lib live so it can generate correct bindings.
export PYO3_CROSS=1
# Must point to a dir containing _sysconfigdata*.py (BeeWare ships it in
# platform-config/, not in lib/). PyO3's build.rs reads sysconfigdata to
# pick up target-specific build flags, install paths, etc.
export PYO3_CROSS_LIB_DIR="$PY_SYSCONFIG_DIR"
export PYO3_CROSS_PYTHON_VERSION="3.14"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
# pyo3 build.rs runs `python` and does `importlib.import_module(SYSCONFIGDATA_NAME)`.
# It needs the module on sys.path.
export PYTHONPATH="$PY_SYSCONFIG_DIR${PYTHONPATH:+:$PYTHONPATH}"
# PyO3 0.21 maxes out at 3.12. Force stable-ABI (abi3) build so the same
# .so works on 3.14 without the compat check failing.
export PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1

# ---- C cross-compile (for onig + any other C deps) ------------------------
# The `onig` crate compiles Oniguruma C sources via the `cc` build crate.
# cc honors CC_<target> and CFLAGS_<target>.
export CC_aarch64_apple_ios="$IOS_CLANG"
export AR_aarch64_apple_ios="$IOS_AR"
export CFLAGS_aarch64_apple_ios="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -fembed-bitcode=off"
export CXXFLAGS_aarch64_apple_ios="$CFLAGS_aarch64_apple_ios"

# ---- Rust linker config ---------------------------------------------------
# cargo uses this to invoke the linker for aarch64-apple-ios target.
# We point it at Xcode's clang with -isysroot + -F for Python.framework.
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$IOS_CLANG"
# RUSTFLAGS: pass framework search path + link against Python dylib.
# -undefined dynamic_lookup lets us defer Python symbol resolution to runtime
# (Python symbols are provided by the host app when it loads our .so).
export CARGO_TARGET_AARCH64_APPLE_IOS_RUSTFLAGS="\
-C link-arg=-isysroot -C link-arg=$IOS_SDK \
-C link-arg=-miphoneos-version-min=13.0 \
-C link-arg=-F$PY_FW/.. \
-C link-arg=-framework -C link-arg=Python \
-C link-arg=-undefined -C link-arg=dynamic_lookup"

# ---- Cargo build ----------------------------------------------------------
cd "$SRC"

# Disable the `extension-module` feature — that feature tells pyo3 NOT to link
# libpython (because on Linux/macOS the host Python interp provides symbols).
# We want that exact behavior on iOS too — symbols resolve at dlopen time.
echo
echo "==> Building tokenizers for aarch64-apple-ios (release)..."
cargo build --release --target aarch64-apple-ios \
    --no-default-features \
    --features "pyo3/extension-module" 2>&1 | tail -40

OUT="$SRC/target/aarch64-apple-ios/release/libtokenizers.dylib"
if [ ! -f "$OUT" ]; then
    OUT_ALT="$SRC/target/aarch64-apple-ios/release/deps/libtokenizers.dylib"
    if [ -f "$OUT_ALT" ]; then
        OUT="$OUT_ALT"
    else
        echo "✗ build output not found at $OUT"
        echo "  Searching target/aarch64-apple-ios/release/ for artifacts..."
        find "$SRC/target/aarch64-apple-ios/release" -maxdepth 2 -name "libtokenizers*" 2>/dev/null
        exit 1
    fi
fi

echo
echo "✓ Build succeeded: $OUT"
file "$OUT"
echo
echo "Size: $(stat -f '%z' "$OUT" | awk '{printf "%.1f MB\n", $1/1024/1024}')"
