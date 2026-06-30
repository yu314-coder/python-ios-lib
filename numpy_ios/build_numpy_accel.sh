#!/bin/bash
# Rebuild numpy 2.3.5 for iOS arm64 WITH Apple Accelerate (AMX) BLAS+LAPACK,
# instead of the no-BLAS fallback the original build_numpy_ios.sh used.
#
# Matches scipy (which already links Accelerate / $NEWLAPACK). The new
# Accelerate LAPACK needs iOS ≥16.4 — the app targets 17.0, so the
# accel cross-file uses min 16.4. The iOS OWNDATA resize patch lives in the
# source (shape.c v5), so it's preserved by this rebuild.
#
# Output: numpy/*.cpython-314-iphoneos.so into build-accel/, ready to swap
# into app_packages/site-packages/numpy/.
set -euo pipefail
cd "$(dirname "$0")"

SRC="$PWD/numpy-2.3.5"
BUILD="$PWD/build-accel"
INSTALL="$PWD/install-accel"
CROSS="$PWD/ios-arm64-cross-accel.ini"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
echo "iOS SDK: $IOS_SDK"
[ -d "$SRC" ] || { echo "numpy source missing"; exit 1; }
[ -f "$PY_HDRS/Python.h" ] || { echo "Python.h missing"; exit 1; }

# Keep the accel cross-file's SDK path current (but NOT the min version).
sed -i '' "s|/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS[0-9.]*\.sdk|$IOS_SDK|g" "$CROSS"

rm -rf "$BUILD" "$INSTALL"

cat > "$PWD/native.ini" <<EOF
[binaries]
python = 'python3'
[properties]
python_version = '3.14'
python_include_dir = '$PY_HDRS'
EOF

export NPY_DISABLE_SVML=1

VMESON="$SRC/vendored-meson/meson/meson.py"
[ -f "$VMESON" ] || { echo "vendored meson missing"; exit 1; }

echo "==> meson setup (blas/lapack = accelerate) ..."
python3 "$VMESON" setup "$BUILD" "$SRC" \
    --cross-file="$CROSS" \
    --native-file="$PWD/native.ini" \
    -Dpython.platlibdir="lib/python3.14/site-packages" \
    -Dpython.purelibdir="lib/python3.14/site-packages" \
    -Dblas=accelerate \
    -Dlapack=accelerate \
    -Ddisable-svml=true \
    -Ddisable-highway=true \
    -Dpkgconfig.relocatable=false \
    --prefix="$INSTALL" 2>&1 | tail -40

echo
echo "==> confirming meson resolved Accelerate ..."
grep -iE "blas|lapack|accelerate" "$BUILD/meson-logs/meson-log.txt" 2>/dev/null | grep -iE "accelerate|found|library" | tail -8 || true

echo
echo "==> meson compile ..."
python3 "$VMESON" compile -C "$BUILD" 2>&1 | tail -20

echo
echo "==> built extensions ..."
find "$BUILD" -name "*iphoneos*.so" | head
echo "==> Accelerate linkage check (the whole point):"
MA="$(find "$BUILD" -name '_multiarray_umath*.so' | head -1)"
otool -L "$MA" 2>/dev/null | grep -iE "accelerate" && echo "  ✓ numpy core links Accelerate" || echo "  ✗ NO Accelerate — investigate"
echo "==> OWNDATA patch compiled in (string marker present)?"
strings "$MA" 2>/dev/null | grep -i "ios-patch-v5" | head -1 && echo "  ✓ OWNDATA patch preserved" || echo "  (marker not found as string — verify separately)"
echo "[numpy-accel] DONE"
