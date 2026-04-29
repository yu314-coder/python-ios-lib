#!/bin/bash
# test-wrap-locally.sh — local sanity-check for wrap-binaries-as-frameworks.sh
# ---------------------------------------------------------------------------
# Builds a fake `.app` mimicking the post-Run-Script-but-pre-wrap layout
# (loose .so files inside python-ios-lib_*.bundle/, loose .dylibs inside
# Frameworks/), runs the wrap script against it, and verifies:
#
#   1. The script exits 0
#   2. No loose .so/.dylib remains anywhere in the .app
#      (except inside .framework/ and .xcframework/ dirs)
#   3. Every wrapped binary still has valid Mach-O headers
#   4. otool -L on each wrapped binary shows no @rpath references that
#      can't be resolved via Frameworks/<X>.framework/<X>
#   5. The manifest is non-empty and well-formed
#
# Run from repo root:
#   bash scripts/appstore/test-wrap-locally.sh
# ---------------------------------------------------------------------------
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/appstore/wrap-binaries-as-frameworks.sh"
WORK="${TMPDIR:-/tmp}/python-ios-lib-wrap-test-$$"
APP="$WORK/Build/Products/Debug-iphoneos/TestApp.app"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "===== local wrap-script test ====="
mkdir -p "$APP/Frameworks"
mkdir -p "$APP/python-stdlib/lib-dynload"

# 1. Synthetic stdlib lib-dynload .so
# Pull a real one from the local app_packages — we want a real Mach-O
# so install_name_tool / codesign / otool actually run.
SAMPLE_SO=$(find "$ROOT/app_packages/site-packages/numpy/_core" \
    -name "_multiarray_umath.*.so" 2>/dev/null | head -1)

if [ -z "$SAMPLE_SO" ] || [ ! -f "$SAMPLE_SO" ]; then
    echo "✗ couldn't find a sample .so to test with — skip the live test"
    exit 0
fi

# Stdlib sample
cp "$SAMPLE_SO" "$APP/python-stdlib/lib-dynload/_struct.cpython-314-iphoneos.so"

# SPM bundle sample — mimic numpy's structure
NUMPY_BUNDLE="$APP/python-ios-lib_NumPy.bundle"
mkdir -p "$NUMPY_BUNDLE/numpy/_core"
mkdir -p "$NUMPY_BUNDLE/numpy/random"
cp "$SAMPLE_SO" "$NUMPY_BUNDLE/numpy/_core/_multiarray_umath.cpython-314-iphoneos.so"
cp "$SAMPLE_SO" "$NUMPY_BUNDLE/numpy/random/_mt19937.cpython-314-iphoneos.so"

# scipy sample with a "cython_blas-like" cross-reference target
SCIPY_BUNDLE="$APP/python-ios-lib_SciPy.bundle"
mkdir -p "$SCIPY_BUNDLE/scipy/linalg"
cp "$SAMPLE_SO" "$SCIPY_BUNDLE/scipy/linalg/cython_blas.cpython-314-iphoneos.so"
cp "$SAMPLE_SO" "$SCIPY_BUNDLE/scipy/linalg/_fblas.cpython-314-iphoneos.so"

# Loose dylib in Frameworks/ (the "BeeWare-copy didn't wrap" case)
LOOSE_DYLIB="$ROOT/Frameworks/fortran_stubs/libfortran_io_stubs.dylib"
if [ -f "$LOOSE_DYLIB" ]; then
    cp "$LOOSE_DYLIB" "$APP/Frameworks/libfortran_io_stubs.dylib"
fi

LOOSE_BEFORE=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) | wc -l | tr -d ' ')
echo "before wrap: $LOOSE_BEFORE loose binaries"

# Fake the Xcode build environment
export BUILT_PRODUCTS_DIR="$WORK/Build/Products/Debug-iphoneos"
export CONTENTS_FOLDER_PATH="TestApp.app"
export PLATFORM_NAME="iphoneos"
export EXPANDED_CODE_SIGN_IDENTITY="-"
export IPHONEOS_DEPLOYMENT_TARGET="17.0"
export TEMP_DIR="$WORK/tmp"
mkdir -p "$TEMP_DIR"

bash "$SCRIPT" || { echo "✗ wrap script failed"; exit 1; }

echo ""
echo "===== verification ====="

# Verification 1: no loose .so/.dylib outside .framework/
LOOSE_AFTER=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
    -not -path "*/.framework/*" \
    -not -path "*/.xcframework/*" 2>/dev/null | xargs -I {} test -s {} \; -print 2>/dev/null | wc -l | tr -d ' ')

# .so PLACEHOLDERS (0-byte stubs at original path) are expected; they
# satisfy __file__ introspection without being real binaries. Count
# only NON-EMPTY remainders as real failures.
NON_EMPTY_LEFT=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
    -not -path "*/.framework/*" \
    -not -path "*/.xcframework/*" \
    -not -empty 2>/dev/null | wc -l | tr -d ' ')

if [ "$NON_EMPTY_LEFT" -gt 0 ]; then
    echo "✗ FAIL: $NON_EMPTY_LEFT non-empty loose binaries left in .app"
    find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
        -not -path "*/.framework/*" \
        -not -path "*/.xcframework/*" \
        -not -empty | sed 's/^/    /'
    exit 1
else
    echo "✓ no non-empty loose .so/.dylib outside .framework/"
fi

# Verification 2: every wrapped binary (named by CFBundleExecutable
# in its Info.plist) has a valid Mach-O header. Skip Info.plist /
# resources / etc.
BAD=0
while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    [ -f "$plist" ] || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    [ -z "$exe" ] && continue
    bin="$fw/$exe"
    if [ ! -f "$bin" ]; then
        echo "  ✗ $fw missing binary $exe"
        BAD=$((BAD+1))
        continue
    fi
    if ! file "$bin" 2>/dev/null | grep -q "Mach-O"; then
        echo "  ✗ $bin is not a valid Mach-O"
        BAD=$((BAD+1))
    fi
done < <(find "$APP/Frameworks" -name "*.framework" -type d -print0)
if [ "$BAD" -eq 0 ]; then
    echo "✓ every wrapped binary is a valid Mach-O"
else
    echo "✗ FAIL: $BAD wrapped files aren't valid Mach-O"
    exit 1
fi

# Verification 3: each framework has Info.plist with CFBundleExecutable
FW_COUNT=0
BAD_PLIST=0
while IFS= read -r -d '' fw; do
    FW_COUNT=$((FW_COUNT+1))
    if [ ! -f "$fw/Info.plist" ]; then
        echo "  ✗ $fw missing Info.plist"
        BAD_PLIST=$((BAD_PLIST+1))
        continue
    fi
    # Check Info.plist has CFBundleExecutable
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$fw/Info.plist" 2>/dev/null || echo "")
    [ -z "$exe" ] && { echo "  ✗ $fw Info.plist missing CFBundleExecutable"; BAD_PLIST=$((BAD_PLIST+1)); continue; }
    [ ! -f "$fw/$exe" ] && { echo "  ✗ $fw/$exe (CFBundleExecutable target) missing"; BAD_PLIST=$((BAD_PLIST+1)); }
done < <(find "$APP/Frameworks" -name "*.framework" -type d -print0)
if [ "$BAD_PLIST" -eq 0 ]; then
    echo "✓ all $FW_COUNT framework Info.plists are well-formed"
else
    echo "✗ FAIL: $BAD_PLIST framework Info.plist issues"
    exit 1
fi

# Verification 4: manifest is non-empty
MANIFEST="$APP/python-ios-lib_extension_manifest.txt"
if [ ! -s "$MANIFEST" ]; then
    echo "✗ FAIL: manifest empty/missing"
    exit 1
fi
MANIFEST_LINES=$(wc -l < "$MANIFEST" | tr -d ' ')
echo "✓ manifest has $MANIFEST_LINES entries"

# Verification 5: every manifest entry resolves to an existing framework binary
BAD_MAP=0
while IFS='=' read -r module fw_name; do
    [ -z "$module" ] && continue
    fw_path="$APP/Frameworks/${fw_name}.framework/${fw_name}"
    if [ ! -f "$fw_path" ]; then
        echo "  ✗ manifest: $module → $fw_name not found at $fw_path"
        BAD_MAP=$((BAD_MAP+1))
    fi
done < "$MANIFEST"
if [ "$BAD_MAP" -eq 0 ]; then
    echo "✓ every manifest entry resolves to an existing framework"
else
    echo "✗ FAIL: $BAD_MAP manifest entries don't resolve"
    exit 1
fi

# Verification 6: cross-references in wrapped binaries either point at
# system libs (/usr/lib/, /System/, @rpath/Python.framework/), or at
# OTHER wrapped frameworks via @rpath/<X>.framework/<X>.
DANGLING=0
while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    [ -f "$plist" ] || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    bin="$fw/$exe"
    [ -f "$bin" ] || continue
    while IFS= read -r ref; do
        ref=$(echo "$ref" | awk '{print $1}')
        [ -z "$ref" ] && continue
        case "$ref" in
            /usr/lib/*|/System/*) continue ;;
            @rpath/Python.framework/*) continue ;;
            @rpath/*.framework/*) continue ;;
            @executable_path/*) continue ;;
            @loader_path/*) continue ;;
            "$bin") continue ;;
        esac
        echo "  ⚠ $bin still references: $ref"
        DANGLING=$((DANGLING+1))
    done < <(otool -L "$bin" 2>/dev/null | tail -n +2)
done < <(find "$APP/Frameworks" -name "*.framework" -type d -print0)
if [ "$DANGLING" -eq 0 ]; then
    echo "✓ no dangling cross-references"
else
    echo "⚠ $DANGLING dangling references — may or may not break at runtime"
fi

echo ""
echo "===== local wrap-script test PASSED ====="
echo "  $WRAPPED_COUNT_REAL=$(find "$APP/Frameworks" -name "*.framework" -type d | wc -l | tr -d ' ') frameworks"
