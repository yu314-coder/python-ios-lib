#!/bin/bash
# test-wrap-realistic.sh — large-scale real-binary stress test
# ============================================================
# Builds a realistic .app structure populated with the ACTUAL .so/.dylib
# files from app_packages/site-packages and Frameworks/, then runs
# wrap-binaries-as-frameworks.sh against it. Surfaces real-world issues
# (cross-extension dyld deps, /tmp/ffmpeg-ios/ install_names, scipy's
# .dylibs/, etc.) that the synthetic test can't reach.
#
# Reads from:
#   $OFFLINAI_DIR/app_packages/site-packages/*       (real .so files)
#   $OFFLINAI_DIR/Frameworks/{ffmpeg,fortran_stubs,scipy_aux}/*.dylib
#
# Default: /Volumes/D/OfflinAi (override with OFFLINAI_DIR=...)
# ============================================================
set -e

OFFLINAI_DIR="${OFFLINAI_DIR:-/Volumes/D/OfflinAi}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/appstore/wrap-binaries-as-frameworks.sh"
WORK="${TMPDIR:-/tmp}/python-ios-lib-realistic-$$"
APP="$WORK/Build/Products/Debug-iphoneos/CodeBench.app"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -d "$OFFLINAI_DIR/app_packages/site-packages" ]; then
    echo "✗ OFFLINAI_DIR not found: $OFFLINAI_DIR/app_packages/site-packages"
    exit 1
fi

echo "===== realistic wrap test ====="
echo "  source: $OFFLINAI_DIR"
echo "  target: $APP"
echo ""

# Recreate the post-stdlib-copy + post-SPM-resource-copy layout that
# Xcode would have produced in step 4 of the README.
mkdir -p "$APP/Frameworks"
mkdir -p "$APP/python-stdlib/lib-dynload"

# Copy Python C extensions from each major package into a synthetic
# python-ios-lib_<Pkg>.bundle. Keep the in-package directory layout.
copy_pkg() {
    local src_pkg="$1" target_bundle="$2" subdir="$3"
    local src_dir="$OFFLINAI_DIR/app_packages/site-packages/$src_pkg"
    [ -d "$src_dir" ] || { echo "  ! skip $src_pkg (not in site-packages)"; return; }
    mkdir -p "$APP/$target_bundle/$subdir"
    cp -R "$src_dir" "$APP/$target_bundle/$subdir/"
}

echo "  populating .app with real packages…"
copy_pkg numpy        python-ios-lib_NumPy.bundle      ""
copy_pkg scipy        python-ios-lib_SciPy.bundle      ""
copy_pkg PIL          python-ios-lib_Pillow.bundle     ""
copy_pkg cairo        python-ios-lib_CairoGraphics.bundle ""
copy_pkg av           python-ios-lib_FFmpegPyAV.bundle ""
copy_pkg manimpango   python-ios-lib_Manim.bundle      ""
copy_pkg pathops      python-ios-lib_Manim.bundle      ""
copy_pkg sklearn      python-ios-lib_Sklearn.bundle    ""
copy_pkg mapbox_earcut python-ios-lib_Mapbox_earcut.bundle ""
copy_pkg psutil       python-ios-lib_Psutil.bundle     ""

# scipy_runtime dir mimicking what the SciPy SPM target ships
mkdir -p "$APP/python-ios-lib_SciPy.bundle/scipy_runtime"
[ -f "$OFFLINAI_DIR/Frameworks/fortran_stubs/libfortran_io_stubs.dylib" ] && \
    cp "$OFFLINAI_DIR/Frameworks/fortran_stubs/libfortran_io_stubs.dylib" \
       "$APP/python-ios-lib_SciPy.bundle/scipy_runtime/"
[ -f "$OFFLINAI_DIR/Frameworks/scipy_aux/libsf_error_state.dylib" ] && \
    cp "$OFFLINAI_DIR/Frameworks/scipy_aux/libsf_error_state.dylib" \
       "$APP/python-ios-lib_SciPy.bundle/scipy_runtime/"

# Stdlib lib-dynload — copy the real BeeWare extensions if present
BEEWARE_DYN="$OFFLINAI_DIR/Python.xcframework/ios-arm64/lib-arm64/python3.14/lib-dynload"
[ ! -d "$BEEWARE_DYN" ] && BEEWARE_DYN="$OFFLINAI_DIR/python-stdlib/lib-dynload"
if [ -d "$BEEWARE_DYN" ]; then
    cp "$BEEWARE_DYN"/*.so "$APP/python-stdlib/lib-dynload/" 2>/dev/null || true
fi

# Loose dylibs in Frameworks/ from the README's existing copy step
for d in "$OFFLINAI_DIR/Frameworks/ffmpeg" "$OFFLINAI_DIR/Frameworks/fortran_stubs" "$OFFLINAI_DIR/Frameworks/scipy_aux"; do
    [ -d "$d" ] || continue
    cp -f "$d"/*.dylib "$APP/Frameworks/" 2>/dev/null || true
done

# Also pull pdftex.xcframework + kpathsea + ios_system if available
for sub in pdftex kpathsea ios_system; do
    src="$OFFLINAI_DIR/Frameworks/latex/${sub}.xcframework"
    [ -d "$src" ] || continue
    mkdir -p "$APP/python-ios-lib_LaTeXEngine.bundle/latex"
    cp -R "$src" "$APP/python-ios-lib_LaTeXEngine.bundle/latex/"
done

# Strip __pycache__ — they bloat the test
find "$APP" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

LOOSE_BEFORE=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) 2>/dev/null | wc -l | tr -d ' ')
SIZE_BEFORE=$(du -sh "$APP" 2>/dev/null | awk '{print $1}')
echo "  before wrap: $LOOSE_BEFORE loose binaries, $SIZE_BEFORE total"
echo ""

# ============================================================
# Run the wrap script with realistic Xcode env vars
# ============================================================
export BUILT_PRODUCTS_DIR="$WORK/Build/Products/Debug-iphoneos"
export CONTENTS_FOLDER_PATH="CodeBench.app"
export PLATFORM_NAME="iphoneos"
export EXPANDED_CODE_SIGN_IDENTITY="-"  # ad-hoc; real archive uses team identity
export IPHONEOS_DEPLOYMENT_TARGET="17.0"
export TEMP_DIR="$WORK/tmp"
mkdir -p "$TEMP_DIR"

echo "===== running wrap script ====="
START=$(date +%s)
bash "$SCRIPT" 2>&1 | tail -10
ELAPSED=$(($(date +%s) - START))
echo "  elapsed: ${ELAPSED}s"
echo ""

# ============================================================
# Verifications
# ============================================================
echo "===== verification ====="

# 1. Count remaining loose binaries (placeholder 0-byte stubs OK)
NON_EMPTY=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
    -not -path "*/.framework/*" \
    -not -path "*/.xcframework/*" \
    -not -empty 2>/dev/null | wc -l | tr -d ' ')
PLACEHOLDERS=$(find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
    -not -path "*/.framework/*" \
    -not -path "*/.xcframework/*" \
    -empty 2>/dev/null | wc -l | tr -d ' ')

if [ "$NON_EMPTY" -gt 0 ]; then
    echo "✗ FAIL: $NON_EMPTY non-empty loose binaries remain (App Store would reject)"
    find "$APP" \( -name "*.so" -o -name "*.dylib" \) \
        -not -path "*/.framework/*" \
        -not -path "*/.xcframework/*" \
        -not -empty 2>/dev/null | head -20 | sed 's|^|    |'
    exit 1
fi
echo "✓ no non-empty loose .so/.dylib remain ($PLACEHOLDERS empty placeholders OK)"

# 2. Every framework has a valid Mach-O binary at CFBundleExecutable
FW_TOTAL=0; FW_BAD=0
while IFS= read -r -d '' fw; do
    FW_TOTAL=$((FW_TOTAL+1))
    plist="$fw/Info.plist"
    [ -f "$plist" ] || { FW_BAD=$((FW_BAD+1)); echo "  ✗ no plist: $fw"; continue; }
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    [ -z "$exe" ] && { FW_BAD=$((FW_BAD+1)); echo "  ✗ no CFBundleExecutable: $fw"; continue; }
    bin="$fw/$exe"
    if ! file "$bin" 2>/dev/null | grep -q "Mach-O"; then
        FW_BAD=$((FW_BAD+1))
        echo "  ✗ not Mach-O: $fw/$exe"
    fi
done < <(find "$APP/Frameworks" -name "*.framework" -type d -print0)
[ "$FW_BAD" -eq 0 ] && echo "✓ all $FW_TOTAL frameworks have valid Mach-O binaries" \
    || { echo "✗ FAIL: $FW_BAD of $FW_TOTAL frameworks broken"; exit 1; }

# 3. Manifest entries all resolve
MANIFEST="$APP/python-ios-lib_extension_manifest.txt"
MAN_LINES=$(wc -l < "$MANIFEST" | tr -d ' ')
MAN_BAD=0
while IFS='=' read -r module fw_name; do
    [ -z "$module" ] && continue
    [ -f "$APP/Frameworks/${fw_name}.framework/${fw_name}" ] || \
        { MAN_BAD=$((MAN_BAD+1)); echo "  ✗ unresolved: $module"; }
done < "$MANIFEST"
[ "$MAN_BAD" -eq 0 ] && echo "✓ manifest: $MAN_LINES entries, all resolve" \
    || { echo "✗ FAIL: $MAN_BAD manifest entries don't resolve"; exit 1; }

# 4. Cross-references — count dangling refs by category
# (macOS ships bash 3.2, no associative arrays — use a tempfile)
echo ""
echo "===== cross-reference analysis ====="
UNRESOLVED_LOG="$WORK/unresolved.txt"
: > "$UNRESOLVED_LOG"
dangling_at_rpath=0; dangling_loader=0; dangling_abs=0; dangling_tmp=0

while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    bin="$fw/$exe"
    [ -f "$bin" ] || continue
    while IFS= read -r ref; do
        ref=$(echo "$ref" | awk '{print $1}')
        [ -z "$ref" ] && continue
        case "$ref" in
            /usr/lib/*|/System/*) continue ;;
            @rpath/Python.framework/*) continue ;;
            @executable_path/*) continue ;;
            "$bin") continue ;;
            @rpath/*.framework/*)
                target_fw=$(echo "$ref" | sed -E 's|@rpath/([^/]+\.framework)/.*|\1|')
                if [ ! -d "$APP/Frameworks/$target_fw" ]; then
                    dangling_at_rpath=$((dangling_at_rpath+1))
                    echo "$ref" >> "$UNRESOLVED_LOG"
                fi
                ;;
            @rpath/*)
                dangling_at_rpath=$((dangling_at_rpath+1))
                echo "$ref" >> "$UNRESOLVED_LOG"
                ;;
            @loader_path/*)
                target=$(echo "$ref" | sed 's|@loader_path/||')
                if [ ! -f "$fw/$target" ] && [ ! -f "$(dirname "$fw")/$target" ]; then
                    dangling_loader=$((dangling_loader+1))
                    echo "$ref" >> "$UNRESOLVED_LOG"
                fi
                ;;
            /tmp/*)
                dangling_tmp=$((dangling_tmp+1))
                echo "$ref" >> "$UNRESOLVED_LOG"
                ;;
            /*)
                dangling_abs=$((dangling_abs+1))
                echo "$ref" >> "$UNRESOLVED_LOG"
                ;;
        esac
    done < <(otool -L "$bin" 2>/dev/null | tail -n +2)
done < <(find "$APP/Frameworks" -name "*.framework" -type d -print0)

echo "  dangling @rpath:        $dangling_at_rpath"
echo "  dangling @loader_path:  $dangling_loader"
echo "  hardcoded /tmp/ paths:  $dangling_tmp"
echo "  other absolute paths:   $dangling_abs"

if [ -s "$UNRESOLVED_LOG" ]; then
    echo ""
    echo "  top 20 unresolved references (count refs):"
    sort "$UNRESOLVED_LOG" | uniq -c | sort -rn | head -20 | sed 's/^/  /'
fi

# 5. Final sizing
SIZE_AFTER=$(du -sh "$APP" 2>/dev/null | awk '{print $1}')
FW_COUNT=$(find "$APP/Frameworks" -name "*.framework" -type d | wc -l | tr -d ' ')
echo ""
echo "===== summary ====="
echo "  before:    $LOOSE_BEFORE loose binaries, $SIZE_BEFORE"
echo "  after:     $FW_COUNT frameworks, $SIZE_AFTER"
echo "  manifest:  $MAN_LINES entries"
echo ""

if [ "$dangling_at_rpath" -gt 0 ] || [ "$dangling_loader" -gt 0 ] || \
   [ "$dangling_tmp" -gt 0 ] || [ "$dangling_abs" -gt 0 ]; then
    echo "⚠ Dangling references found — these MAY cause dyld errors at runtime."
    echo "  The wrap script's heuristic missed them. We need to extend the"
    echo "  cross-reference rewriter to handle the patterns listed above."
    exit 2
fi

echo "✓ realistic wrap test PASSED — all cross-refs resolved cleanly"
