#!/usr/bin/env bash
# torch_ios/scripts/package_wheel.sh — Phase 3 of Track B.
#
# After Phase 1 (libtorch_lite.a) and Phase 2 (_C.so + friends) succeed,
# this packages the result into an installable wheel:
#   torch-2.1.2-cp314-cp314-ios_17_0_arm64.whl
# drop into app_packages/site-packages/ and `import torch` works.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PYTORCH_DIR="$ROOT/build/pytorch"
STAGE="$ROOT/build/wheel_stage"
DIST="$ROOT/build/dist"

rm -rf "$STAGE" && mkdir -p "$STAGE" "$DIST"
mkdir -p "$STAGE/torch"

# 1. Copy Python source tree (torch/, torch.utils.data/, torch.nn/, …)
cp -R "$PYTORCH_DIR/torch" "$STAGE/"

# 2. Overlay the compiled extension modules produced by Phase 2.
#    (These don't exist yet — Phase 2 is the unfinished hard part.)
EXT_DIR="$ROOT/build/ios-arm64/python_ext"
if [ -d "$EXT_DIR" ]; then
    echo ">>> Overlaying compiled .so extensions from $EXT_DIR"
    cp -v "$EXT_DIR"/*.so "$STAGE/torch/" || true
else
    echo "⚠ No $EXT_DIR — Phase 2 not yet completed. Wheel will be Python-only"
    echo "  and will fail on first `import torch._C`."
fi

# 3. Write WHEEL + METADATA + RECORD.
VERSION="2.1.2"
PLATFORM="ios_17_0_arm64"
PYVER="cp314"

WHEEL_NAME="torch-${VERSION}-${PYVER}-${PYVER}-${PLATFORM}.whl"
INFO_DIR="$STAGE/torch-${VERSION}.dist-info"
mkdir -p "$INFO_DIR"

cat > "$INFO_DIR/WHEEL" <<EOF
Wheel-Version: 1.0
Generator: torch_ios/package_wheel.sh
Root-Is-Purelib: false
Tag: ${PYVER}-${PYVER}-${PLATFORM}
EOF

cat > "$INFO_DIR/METADATA" <<EOF
Metadata-Version: 2.1
Name: torch
Version: ${VERSION}
Summary: PyTorch (lite interpreter) for iOS. Bundled via python-ios-lib.
Requires-Python: >=3.14
EOF

# 4. Zip it up as a wheel.
cd "$STAGE"
OUT="$DIST/$WHEEL_NAME"
rm -f "$OUT"
zip -r "$OUT" torch "torch-${VERSION}.dist-info" -x "*/__pycache__/*"

echo ">>> Wrote $OUT"
ls -la "$OUT"
echo ""
echo "To install into the app:"
echo "  cp -R torch torch-${VERSION}.dist-info \\"
echo "       /path/to/OfflinAi/app_packages/site-packages/"
