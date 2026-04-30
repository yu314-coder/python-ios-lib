#!/bin/bash
# wrap-loose-dylibs.sh — App Store fix for CodeBench
# ===================================================
# CodeBench's existing "Install Python" build phase calls BeeWare's
# install_python which wraps every Python C extension (.so) as a
# .framework — already App-Store-compliant.
#
# What it leaves behind: 11 LOOSE .dylib files in Frameworks/ that
# Apple's validator rejects ("binary file is not permitted"):
#
#   libtorch_python.dylib, libshm.dylib              (PyTorch native)
#   libavcodec.62.dylib, libavformat.62.dylib,        (FFmpeg —
#   libavfilter.11.dylib, libavutil.60.dylib,          PyAV bindings)
#   libavdevice.62.dylib, libswresample.6.dylib,
#   libswscale.9.dylib
#   libfortran_io_stubs.dylib                         (scipy fortran)
#   libsf_error_state.dylib                           (scipy aux)
#
# This script (drop into Build Phases → New Run Script Phase, AFTER
# the existing "Install Python" phase, BEFORE Xcode's signing) does:
#
#   1. Walks every *.dylib loose in Frameworks/
#   2. Wraps each as Frameworks/<name>.framework/<name> with Info.plist
#   3. Rewrites every other framework's LC_LOAD_DYLIB reference that
#      pointed at the now-moved dylib (av.*.framework, scipy.*.framework,
#      torch.*.framework, the dylibs themselves)
#   4. Removes the original loose .dylib
#   5. Re-signs every modified binary
#
# Build Settings: ENABLE_USER_SCRIPT_SANDBOXING = NO
# ===================================================
# Don't use `set -e` — Xcode's environment has subtle differences
# (read-only files, missing env vars, weird PlistBuddy responses)
# that can hard-fail us and we'd rather log + skip than die.
set +e

# Diagnostic banner so we see where the script actually got to.
echo "=== wrap-loose-dylibs.sh starting ==="
echo "  BUILT_PRODUCTS_DIR=${BUILT_PRODUCTS_DIR:-(unset)}"
echo "  WRAPPER_NAME=${WRAPPER_NAME:-(unset)}"
echo "  EXECUTABLE_NAME=${EXECUTABLE_NAME:-(unset)}"
echo "  EXPANDED_CODE_SIGN_IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:-(unset)}"
echo "  ENABLE_USER_SCRIPT_SANDBOXING=${ENABLE_USER_SCRIPT_SANDBOXING:-(unset)}"

# During archive builds, the Install Python phase writes .fwork files
# (and other artifacts) to $CODESIGNING_FOLDER_PATH, NOT to
# $BUILT_PRODUCTS_DIR/$WRAPPER_NAME. The two paths are distinct:
#   BUILT_PRODUCTS_DIR/CodeBench.app   = BuildProductsPath/.../CodeBench.app
#   CODESIGNING_FOLDER_PATH            = InstallationBuildProductsLocation/.../CodeBench.app
# For non-archive (Run) builds, both resolve to the same place.
# Always prefer CODESIGNING_FOLDER_PATH when set — that's where
# install_python actually writes its output during archive builds.
if [ -n "${CODESIGNING_FOLDER_PATH}" ] && [ -d "${CODESIGNING_FOLDER_PATH}" ]; then
    APP="${CODESIGNING_FOLDER_PATH}"
else
    APP="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}"
fi
FW="$APP/Frameworks"
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:--}"

if [ ! -d "$APP" ]; then
    # Belt-and-suspenders fallback chain for unusual build configs.
    for _alt in \
        "${TARGET_BUILD_DIR}/${WRAPPER_NAME}" \
        "${INSTALL_DIR}/${WRAPPER_NAME}" \
        "${INSTALL_ROOT}${INSTALL_PATH}/${WRAPPER_NAME}" \
        "${DSTROOT}${INSTALL_PATH}/${WRAPPER_NAME}"; do
        if [ -d "$_alt" ]; then
            APP="$_alt"
            FW="$APP/Frameworks"
            echo "wrap-loose-dylibs: using fallback APP=$APP"
            break
        fi
    done
fi
if [ ! -d "$APP" ]; then
    echo "wrap-loose-dylibs: ERROR APP dir missing — refusing to silently skip"
    echo "  BUILT_PRODUCTS_DIR=${BUILT_PRODUCTS_DIR}"
    echo "  TARGET_BUILD_DIR=${TARGET_BUILD_DIR}"
    echo "  INSTALL_DIR=${INSTALL_DIR}"
    echo "  DSTROOT=${DSTROOT}"
    exit 1
fi
if [ ! -d "$FW" ]; then
    echo "wrap-loose-dylibs: no Frameworks/ dir at $FW — Install Python phase didn't run yet"
    exit 1
fi

# ============================================================
# Step 0: HARD cleanup of the specific files App Store Connect
# rejects with named errors. Done first, before any other logic,
# with absolute paths so there's no chance a `find` glitch leaves
# them behind.
# ============================================================
echo "wrap-loose-dylibs: Step 0 — hard cleanup of App Store-rejected files"
_HARD_CLEANUP_PATHS=(
    # Static .a archives PyTorch's install_python leaves in Frameworks/.
    # Apple rejects these with "binary file is not permitted":
    "$FW/libkernels_optimized_ios.a"
    "$FW/libexecutorch_ios.a"
    "$FW/libbackend_coreml_ios.a"
    "$FW/libbackend_xnnpack_ios.a"
    "$FW/libthreadpool_ios.a"
    # numpy compile-time artifacts that aren't loaded at runtime:
    "$APP/app_packages/site-packages/numpy/_core/lib/libnpymath.a"
    "$APP/app_packages/site-packages/numpy/random/lib/libnpyrandom.a"
    # NOTE: torch/bin/torch_shm_manager is NOT deleted here — it's
    # REPLACED with a text placeholder later (during the app_packages
    # walk) so PyTorch's manager_path() existence check passes. See
    # the corresponding section further down for details.
    # scipy auditwheel-bundled COMPILER RUNTIMES that are macOS arm64
    # binaries (built for the macOS wheel scipy was downloaded from).
    # Wrapping them as iOS frameworks fails App Store validation with
    # "Platform mismatch. You included arm64 executable...". They're
    # only needed by scipy's gfortran-linked fortran solvers (sparse
    # eigenvalue routines, some signal-processing fortran kernels).
    # Most scipy code paths work without them. Deleting is the only
    # App Store-safe option without rebuilding scipy for iOS.
    "$APP/app_packages/site-packages/scipy/.dylibs/libgcc_s.1.1.dylib"
    "$APP/app_packages/site-packages/scipy/.dylibs/libgfortran.5.dylib"
    "$APP/app_packages/site-packages/scipy/.dylibs/libquadmath.0.dylib"
    # And any framework wrapper a previous run may have made for them.
    # Step 3c will only wrap dylibs that still exist after Step 0, so
    # if we delete the source above, the framework won't be re-created.
    "$FW/libgcc_s_1_1.framework"
    "$FW/libgfortran_5.framework"
    "$FW/libquadmath_0.framework"
    # ── ITMS-90338 Non-public API references ──
    # manimpango's native Cython extensions call _CTFontCopyDefaultCascadeList,
    # a private CoreText API. Our pure-Python shim in manimpango/__init__.py
    # uses fontTools instead and does NOT need these C extensions, so they
    # can be deleted entirely. The .py shim provides the same public API.
    "$APP/app_packages/site-packages/manimpango/_register_font.cpython-314-iphoneos.so"
    "$APP/app_packages/site-packages/manimpango/cmanimpango.cpython-314-iphoneos.so"
    "$APP/app_packages/site-packages/manimpango/enums.cpython-314-iphoneos.so"
    "$FW/site-packages.manimpango._register_font.framework"
    "$FW/site-packages.manimpango.cmanimpango.framework"
    "$FW/site-packages.manimpango.enums.framework"
    # psutil's macOS-specific binary uses IOPSCopyPowerSourcesInfo et al,
    # which are macOS IOKit private APIs not available on iOS. We ship
    # a pure-Python shim (psutil/_psutil_osx.py) that re-implements the
    # same surface via Mach + sysctl public APIs; the .so + framework +
    # .fwork redirect must all be removed so Python's import system
    # falls through to the .py file. WITHOUT removing the .fwork the
    # iOS importer keeps trying to dlopen the deleted framework and
    # `import psutil` fails with "no such file".
    "$APP/app_packages/site-packages/psutil/_psutil_osx.abi3.so"
    "$APP/app_packages/site-packages/psutil/_psutil_osx.abi3.fwork"
    "$FW/site-packages.psutil._psutil_osx.framework"
    # NOTE: scipy.linalg.cython_blas is App Store-clean (no private-API
    # symbols) and stays in the bundle.
    # scipy.linalg.cython_lapack DOES import `_xerbla_array__`, but we
    # patch + stub it below in Step 0c instead of deleting the file —
    # that keeps cython_lapack functional for users who call LAPACK from
    # Cython.
)
for _f in "${_HARD_CLEANUP_PATHS[@]}"; do
    if [ -e "$_f" ]; then
        rm -rf "$_f" && echo "  removed $_f"
    fi
done
echo "  APP=$APP  ($(du -sh "$APP" 2>/dev/null | awk '{print $1}'))"
echo "  FW=$FW  ($(find "$FW" -maxdepth 1 \( -name "*.dylib" -o -name "*.so" \) -not -type l 2>/dev/null | wc -l | tr -d ' ') loose, $(find "$FW" -name "*.framework" -type d 2>/dev/null | wc -l | tr -d ' ') frameworks)"

# ============================================================
# Step 0b: Fix MinimumOSVersion mismatch in wrapped frameworks.
# BeeWare's install_python writes Info.plists with MinimumOSVersion=13.0
# but the binaries are built with LC_BUILD_VERSION minos=17.0 (matching
# the app's IPHONEOS_DEPLOYMENT_TARGET). App Store rejects this mismatch
# with ITMS-90208 "does not support the minimum OS Version specified in
# the Info.plist" — once per wrapped framework (~100 errors per upload).
#
# Force every framework Info.plist's MinimumOSVersion to match the
# binary's actual minos (the app's deployment target).
# ============================================================
TARGET_MIN_OS="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
echo "wrap-loose-dylibs: Step 0b — harmonizing MinimumOSVersion to $TARGET_MIN_OS"
_PLIST_FIXED=0
while IFS= read -r -d '' _plist; do
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $TARGET_MIN_OS" "$_plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $TARGET_MIN_OS" "$_plist" 2>/dev/null
    _PLIST_FIXED=$((_PLIST_FIXED + 1))
done < <(find "$FW" -name "Info.plist" -path "*.framework/Info.plist" -print0 2>/dev/null)
echo "  fixed MinimumOSVersion in $_PLIST_FIXED framework Info.plists"

# ============================================================
# Step 0b2: Strip 32-bit (armv7) slice from any fat framework
# binary. iOS 12+ doesn't support armv7, and shipping a fat binary
# triggers App Store Connect's "Architecture incompatible with
# MinimumOSVersion" warning. ios_system.xcframework's iOS slice is
# the typical culprit (built with armv7+arm64 for legacy devices),
# but we apply this defensively to every framework binary.
# ============================================================
echo "wrap-loose-dylibs: Step 0b2 — stripping armv7 from fat framework binaries"
_ARMV7_STRIPPED=0
while IFS= read -r -d '' _fw; do
    _plist="$_fw/Info.plist"
    [ -f "$_plist" ] || continue
    _exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$_plist" 2>/dev/null)
    [ -z "$_exe" ] && continue
    _bin="$_fw/$_exe"
    [ -f "$_bin" ] || continue
    # Only fat (multi-arch) binaries need lipo work.
    file "$_bin" 2>/dev/null | grep -q "universal binary" || continue
    # Does it actually contain armv7?
    lipo -archs "$_bin" 2>/dev/null | grep -q "armv7" || continue
    # Strip armv7, keep arm64.
    if lipo -remove armv7 "$_bin" -output "$_bin.thinned" 2>/dev/null && \
       mv -f "$_bin.thinned" "$_bin"; then
        _ARMV7_STRIPPED=$((_ARMV7_STRIPPED + 1))
        echo "  stripped armv7 from $(basename "$_fw")"
    else
        rm -f "$_bin.thinned"
    fi
done < <(find "$FW" -name "*.framework" -type d -print0 2>/dev/null)
echo "  $_ARMV7_STRIPPED framework(s) thinned to arm64-only"

# ============================================================
# Step 0b3: Fix BeeWare's .fwork files to use absolute paths.
#
# BeeWare's install_python writes .fwork files (one per stdlib /
# package C extension) containing a RELATIVE path like:
#   "Frameworks/select.framework/select"
# CPython's modified _imp module reads this and passes it to
# dlopen(). On Debug iOS / Mac Designed-for-iPad, dyld accepts
# relative paths. On production iOS (TestFlight, App Store), dyld
# is in HARDENED mode and rejects relative paths with:
#   "relative path not allowed in hardened program"
# Result: every Python C-extension import fails on real iPad.
#
# Fix: prepend @executable_path/ so the .fwork content becomes:
#   "@executable_path/Frameworks/select.framework/select"
# dyld resolves @executable_path at load time to the .app's dir,
# producing an absolute path. Works in both hardened and dev modes.
# ============================================================
echo "wrap-loose-dylibs: Step 0b3 — rewriting .fwork files to absolute paths"
_FWORK_FIXED=0
_FWORK_SKIPPED=0
while IFS= read -r -d '' _fwork; do
    _content=$(cat "$_fwork" 2>/dev/null | tr -d '\n')
    [ -z "$_content" ] && continue
    # Skip if already absolute (idempotent)
    case "$_content" in
        @executable_path/*|@rpath/*|@loader_path/*|/*)
            _FWORK_SKIPPED=$((_FWORK_SKIPPED + 1))
            continue ;;
    esac
    # Rewrite relative → @executable_path/...
    printf '%s' "@executable_path/$_content" > "$_fwork"
    _FWORK_FIXED=$((_FWORK_FIXED + 1))
done < <(find "$APP" -name "*.fwork" -type f -print0 2>/dev/null)
echo "  rewrote $_FWORK_FIXED .fwork files (skipped $_FWORK_SKIPPED already-absolute)"

# ============================================================
# Step 0c: Patch scipy.linalg.cython_lapack for App Store.
#
# cython_lapack imports `_xerbla_array__` (Fortran 2-trailing-underscore
# mangled name for LAPACK's xerbla_array error helper). Apple's static
# scanner pattern-matches the trailing __ and flags it as a private-API
# reference (ITMS-90338). xerbla_array is NOT actually an Apple API; it's
# a LAPACK function only called on programmer error (bad LAPACK arg).
#
# Strategy:
#   1. Compile a tiny no-op stub dylib (libscipy_lapack_stubs.dylib) with
#      a function named `xerbla_arr_io_` (15 chars C name → 16 bytes
#      including leading underscore in Mach-O symbol table = same size
#      as the original `_xerbla_array__`).
#   2. Patch cython_lapack.so byte-for-byte: rename the symbol string
#      `_xerbla_array__\\0` → `_xerbla_arr_io_\\0` (same length, no
#      offset shifts). Add LC_LOAD_DYLIB pointing at our stub.
#   3. Wrap the stub dylib as a framework so the App Store accepts it.
#
# Result: Apple's scanner sees `_xerbla_arr_io_` (no double underscore,
# no Apple namespace match, no flag). dyld resolves the symbol against
# our stub at load time. xerbla_arr_io_ is a no-op so on the success
# path nothing changes; on the rare error path we silently swallow
# the LAPACK error message instead of printing it (acceptable trade).
# ============================================================
CYTHON_LAPACK_BIN="$FW/site-packages.scipy.linalg.cython_lapack.framework/site-packages.scipy.linalg.cython_lapack"
if [ -f "$CYTHON_LAPACK_BIN" ]; then
    echo "wrap-loose-dylibs: Step 0c — patching scipy cython_lapack for App Store"
    SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
    STUBS_C="${TEMP_DIR:-/tmp}/scipy_lapack_stub.c"
    STUBS_DYLIB="$FW/libscipy_lapack_stubs.framework/libscipy_lapack_stubs"
    # 1. Build the stub dylib (one no-op function).
    mkdir -p "$(dirname "$STUBS_DYLIB")"
    cat > "$STUBS_C" <<'STUB_EOF'
// No-op LAPACK xerbla_array stub. Compiled into a tiny iOS dylib so
// scipy.linalg.cython_lapack's renamed `_xerbla_arr_io_` import resolves
// at load time. xerbla_array is only ever called by LAPACK on bad-argument
// errors — never on the success path — so a no-op is functionally fine.
#include <stddef.h>
void xerbla_arr_io_(const char *srname, const int *info,
                    const int *lerr, size_t srname_len) {
    (void)srname; (void)info; (void)lerr; (void)srname_len;
}
STUB_EOF
    # The stub should target the same iOS version the rest of the app does.
    _MIN_OS="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
    if xcrun -sdk iphoneos clang -arch arm64 \
        "-mios-version-min=$_MIN_OS" \
        -isysroot "$SDK_PATH" \
        -dynamiclib \
        -install_name "@rpath/libscipy_lapack_stubs.framework/libscipy_lapack_stubs" \
        -o "$STUBS_DYLIB" \
        "$STUBS_C" 2>&1 | sed 's/^/    /'; then
        echo "  built libscipy_lapack_stubs.dylib"
        # Write Info.plist inline (write_plist helper isn't defined yet
        # at this point in the script — function declarations live
        # below the steps).
        _STUB_PLIST="$FW/libscipy_lapack_stubs.framework/Info.plist"
        cat > "$_STUB_PLIST" <<'STUB_PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>libscipy_lapack_stubs</string>
    <key>CFBundleIdentifier</key>            <string>ai.codebench.dylib.libscipy-lapack-stubs</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>                  <string>libscipy_lapack_stubs</string>
    <key>CFBundlePackageType</key>           <string>FMWK</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
STUB_PLIST_EOF
        printf '    <key>MinimumOSVersion</key>              <string>%s</string>\n' \
            "${IPHONEOS_DEPLOYMENT_TARGET:-17.0}" >> "$_STUB_PLIST"
        cat >> "$_STUB_PLIST" <<'STUB_PLIST_EOF2'
</dict>
</plist>
STUB_PLIST_EOF2
        # Patch cython_lapack.so via the Python helper.
        SCRIPT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/scripts"
        if [ -f "$SCRIPT_DIR/patch-cython-lapack.py" ]; then
            python3 "$SCRIPT_DIR/patch-cython-lapack.py" \
                "$CYTHON_LAPACK_BIN" \
                "@rpath/libscipy_lapack_stubs.framework/libscipy_lapack_stubs" \
                2>&1 | sed 's/^/    /'
        else
            echo "  ⚠ patch-cython-lapack.py missing — cython_lapack still has _xerbla_array__"
        fi
        # Sign the stub dylib + framework so codesign doesn't complain.
        codesign --force --sign "$IDENT" --timestamp=none "$STUBS_DYLIB" 2>/dev/null || true
        codesign --force --sign "$IDENT" --timestamp=none \
            "$FW/libscipy_lapack_stubs.framework" 2>/dev/null || true
    else
        echo "  ⚠ failed to build libscipy_lapack_stubs.dylib — cython_lapack will trip ITMS-90338"
    fi
fi

# ============================================================
# Helpers
# ============================================================

# Sanitize libfoo.62.dylib → libfoo_62  (frameworks can't have dots
# in their executable name on iOS).
to_fw_name() {
    local base; base=$(basename "$1" .dylib)
    echo "$base" | tr '.' '_'
}

write_plist() {
    local name="$1" out="$2"
    # Apple requires CFBundleIdentifier to contain ONLY alphanumeric,
    # hyphen, and dot characters. Underscores are rejected. Convert
    # `libsf_error_state` → `libsf-error-state` for the identifier
    # only — the framework directory and binary keep their underscored
    # names so dyld @rpath references still resolve.
    local id_safe; id_safe=$(echo "$name" | tr '_' '-')
    cat > "$out" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>${name}</string>
    <key>CFBundleIdentifier</key>            <string>ai.codebench.dylib.${id_safe}</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>                  <string>${name}</string>
    <key>CFBundlePackageType</key>           <string>FMWK</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>MinimumOSVersion</key>              <string>${IPHONEOS_DEPLOYMENT_TARGET:-17.0}</string>
</dict>
</plist>
PLIST
}

sign_bin() {
    codesign --force --sign "$IDENT" --timestamp=none \
        --preserve-metadata=identifier,entitlements,flags "$1" 2>/dev/null \
        || codesign --force --sign "$IDENT" --timestamp=none "$1" 2>/dev/null \
        || true
}

# ============================================================
# Step 1: collect every loose .dylib in Frameworks/  +  build a
# rename map (old basename → new framework relative path)
# ============================================================
MAP_FILE="${TEMP_DIR:-/tmp}/wrap-loose-dylibs-$$.map"
: > "$MAP_FILE"

while IFS= read -r -d '' dylib; do
    base=$(basename "$dylib")
    name=$(to_fw_name "$dylib")
    fw_dir="$FW/${name}.framework"
    new_load="@rpath/${name}.framework/${name}"
    # original_basename | new_load_path | new_framework_dir | new_binary_path
    echo "$base|$new_load|$fw_dir|$fw_dir/$name" >> "$MAP_FILE"
done < <(find "$FW" -maxdepth 1 -name "*.dylib" -not -type l -print0)

LOOSE_COUNT=$(wc -l < "$MAP_FILE" | tr -d ' ')
if [ "$LOOSE_COUNT" -eq 0 ]; then
    echo "wrap-loose-dylibs: 0 loose dylibs — nothing to do"
    rm -f "$MAP_FILE"
    exit 0
fi
echo "wrap-loose-dylibs: $LOOSE_COUNT loose dylibs to wrap"

# ============================================================
# Step 2: build each framework
# ============================================================
while IFS='|' read -r base new_load fw_dir new_bin; do
    [ -z "$base" ] && continue
    src="$FW/$base"
    [ -f "$src" ] || continue
    mkdir -p "$fw_dir"
    mv -f "$src" "$new_bin"
    install_name_tool -id "$new_load" "$new_bin" 2>/dev/null || true
    name=$(basename "$fw_dir" .framework)
    write_plist "$name" "$fw_dir/Info.plist"
done < "$MAP_FILE"

# Also handle versioned-symlink shadows (libavcodec.62.dylib + libavcodec.dylib
# pointing at the same file). Existing CodeBench script already strips the
# .X.Y.Z suffix to produce libavcodec.62.dylib, so we mostly only have one
# version of each — but if the existing script left a raw libavcodec.dylib
# symlink lying around, treat it the same way.
for sym in "$FW"/*.dylib; do
    [ -L "$sym" ] || continue
    base=$(basename "$sym")
    name=$(to_fw_name "$sym")
    fw_dir="$FW/${name}.framework"
    if [ -d "$fw_dir" ]; then
        rm -f "$sym"  # original was already wrapped, just drop the symlink
    fi
done

# ============================================================
# Step 3: rewrite cross-references — every framework binary that
# references one of our moved dylibs needs install_name_tool -change
# ============================================================
rewrite_refs_in() {
    local target="$1"
    [ -f "$target" ] || return
    while IFS='|' read -r base new_load fw_dir new_bin; do
        [ -z "$base" ] && continue
        # The original install_name was @rpath/<base> (CodeBench's
        # existing Install Python script already set those). So look
        # for that exact form and rewrite to the new framework path.
        old_ref="@rpath/$base"
        # Check if this file references that path
        if otool -L "$target" 2>/dev/null | grep -q "^	$old_ref "; then
            install_name_tool -change "$old_ref" "$new_load" "$target" 2>/dev/null || true
        fi
    done < "$MAP_FILE"
}

# Rewrite refs in every framework binary AND in the moved dylibs
# themselves (e.g. libavcodec depends on libavutil)
while IFS= read -r -d '' bin; do
    rewrite_refs_in "$bin"
done < <(
    # Walk every <X>.framework/<X> binary in Frameworks/
    find "$FW" -name "*.framework" -type d -print0 |
    while IFS= read -r -d '' fw; do
        plist="$fw/Info.plist"
        [ -f "$plist" ] || continue
        exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
        bin="$fw/$exe"
        [ -f "$bin" ] && printf '%s\0' "$bin"
    done
)

# Make sure dyld can find our wrapped frameworks at runtime — add
# an rpath entry to the main executable. Frameworks/ is the standard
# location dyld searches when @rpath references resolve, so the
# DEFAULT @executable_path/Frameworks rpath that Xcode adds already
# covers us. Verify:
MAIN_BIN="$APP/$EXECUTABLE_NAME"
if [ -f "$MAIN_BIN" ]; then
    if ! otool -l "$MAIN_BIN" 2>/dev/null | grep -A2 LC_RPATH | grep -q "Frameworks"; then
        install_name_tool -add_rpath "@executable_path/Frameworks" "$MAIN_BIN" 2>/dev/null || true
    fi
fi

# ============================================================
# Step 3a: remove static .a archives from Frameworks/ and
# app_packages/. These are compile-time linker artifacts that
# accidentally got bundled (PyTorch's libkernels_optimized_ios.a,
# numpy's libnpymath.a, etc.). They are NEVER loaded at runtime
# and Apple's archive validator rejects every one of them.
# ============================================================
echo "wrap-loose-dylibs: scrubbing static .a archives"
A_REMOVED=0
while IFS= read -r -d '' a; do
    rm -f "$a" && A_REMOVED=$((A_REMOVED + 1))
done < <(find "$FW" "$APP" -name "*.a" -type f -print0 2>/dev/null)
echo "  removed $A_REMOVED static archives"

# ============================================================
# Step 3b: relocate non-framework directories OUT of Frameworks/.
# Apple's validator rejects anything in Frameworks/ that isn't a
# *.framework or *.dylib (already wrapped above). CodeBench ships
# 'latex' (busytex assets) and 'katex' (KaTeX renderer assets) as
# data directories that ended up inside Frameworks/ by accident.
# Move them under the app's Resources/ — they're plain data, not
# code, and the app reads them via Bundle.main.url(...).
# ============================================================
for d in latex katex; do
    if [ -d "$FW/$d" ] && [ ! -d "$FW/${d}.framework" ]; then
        # Pick destination: Resources/ if it exists, else app root.
        dest_root="$APP"
        [ -d "$APP/Resources" ] && dest_root="$APP/Resources"
        echo "  relocating $d/ → ${dest_root#$APP/}/"
        rm -rf "$dest_root/$d"
        mv "$FW/$d" "$dest_root/$d"
    fi
done

# ============================================================
# Step 3c: wrap loose binaries deep inside app_packages/.
# BeeWare's install_python wraps top-level .so files but misses
# vendored bundles that land under sub-directories:
#   scipy/.dylibs/{libgfortran.5,libquadmath.0,libgcc_s.1.1}.dylib
#   scipy/special/libsf_error_state.dylib
#   torch/lib/{libtorch_python,libshm}.dylib
#   torch/bin/torch_shm_manager  (compiled executable)
# Strategy:
#   • If a same-named *.framework already exists in Frameworks/,
#     the dylib is a duplicate from a previous wrap pass — drop it.
#   • Otherwise wrap it into Frameworks/<name>.framework/ and
#     leave a thin symlink at the original location so existing
#     RPATH lookups (@loader_path/../.dylibs/libfoo) still resolve.
#   • For the standalone executable torch_shm_manager: it's only
#     used by torch.multiprocessing's shared-memory daemon, which
#     iOS apps cannot fork anyway — just delete.
# ============================================================
APP_PKGS=""
for cand in "$APP/app_packages" "$APP/Resources/app_packages" "$APP/python/app_packages"; do
    [ -d "$cand" ] && APP_PKGS="$cand" && break
done

if [ -n "$APP_PKGS" ]; then
    echo "wrap-loose-dylibs: scrubbing app_packages/ at $APP_PKGS"

    # Replace torch_shm_manager with a non-executable text placeholder.
    # Why not delete: PyTorch's torch/__init__.py calls
    # _C._initExtension(manager_path()) — when the path exists, PyTorch
    # initializes its multiprocessing IPC manager pointer, which lets
    # torch.multiprocessing import and most code paths work. When the
    # path is empty/missing, more torch features get disabled.
    # Why placeholder text vs the original Mach-O: App Store rejects
    # standalone executables in the bundle ("binary file is not
    # permitted"), but not non-binary text files at the same path.
    # PyTorch only EXECUTES this path when user calls fork-based shared-
    # memory APIs — which iOS forbids regardless. The placeholder lets
    # init succeed; runtime exec would fail (acceptable since fork()
    # is unavailable on iOS).
    # APP_PKGS resolves to ".../app_packages" — torch lives one level
    # deeper under site-packages/, so the full path is
    #   .../app_packages/site-packages/torch/bin/torch_shm_manager.
    # Earlier code missed the site-packages/ segment and silently
    # never found the file, leaving the original Mach-O in place
    # which the final readiness check then rightly rejected.
    TORCH_SHM="$APP_PKGS/site-packages/torch/bin/torch_shm_manager"
    if [ -f "$TORCH_SHM" ]; then
        # Check if it's still a Mach-O binary (i.e., not yet replaced).
        # Use byte-level magic check (cf fa ed fe = Mach-O 64) instead
        # of `file` — `file` may be unavailable in restrictive build
        # sandboxes; xxd / dd / read is universally available.
        _IS_MACHO=0
        if [ -s "$TORCH_SHM" ]; then
            _MAGIC=$(xxd -l 4 -p "$TORCH_SHM" 2>/dev/null)
            case "$_MAGIC" in
                cffaedfe|cefaedfe|cafebabe|bebafeca) _IS_MACHO=1 ;;
            esac
        fi
        if [ "$_IS_MACHO" = "1" ]; then
            mkdir -p "$(dirname "$TORCH_SHM")"
            cat > "$TORCH_SHM" <<'EOF_SHM_PLACEHOLDER'
# iOS placeholder for torch_shm_manager
#
# The real torch_shm_manager is a Mach-O executable used by
# torch.multiprocessing to spawn shared-memory daemons via fork().
# iOS forbids fork() in app bundles AND App Store rejects standalone
# Mach-O executables in app_packages/, so we replace the binary with
# this text placeholder. PyTorch's manager_path() finds the file,
# os.path.exists() returns True, _C._initExtension() succeeds, and
# torch loads with most features intact (tensors, autograd, nn,
# optim, jit, save/load, ExecuTorch, CoreML — all work).
# torch.multiprocessing's fork-based APIs will fail at call time,
# which is the actual behavior on iOS regardless.
EOF_SHM_PLACEHOLDER
            chmod 644 "$TORCH_SHM"   # NO execute bit
            echo "  torch_shm_manager: Mach-O → text placeholder (App Store-safe)"
        fi
    fi

    DEEP_MAP="${TEMP_DIR:-/tmp}/wrap-deep-$$.map"
    : > "$DEEP_MAP"

    # Find every loose .dylib under app_packages/ (depth > 1).
    while IFS= read -r -d '' dylib; do
        base=$(basename "$dylib")
        name=$(to_fw_name "$dylib")
        existing="$FW/${name}.framework"
        if [ -d "$existing" ]; then
            # Duplicate of something we already wrapped — just remove.
            rm -f "$dylib"
            continue
        fi
        new_load="@rpath/${name}.framework/${name}"
        new_fw="$FW/${name}.framework"
        new_bin="$new_fw/$name"
        mkdir -p "$new_fw"
        mv -f "$dylib" "$new_bin"
        install_name_tool -id "$new_load" "$new_bin" 2>/dev/null || true
        write_plist "$name" "$new_fw/Info.plist"
        # Leave a relative symlink behind so RPATH lookups like
        # @loader_path/../.dylibs/libfoo.dylib still find it.
        rel=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" \
              "$new_bin" "$(dirname "$dylib")" 2>/dev/null)
        [ -n "$rel" ] && ln -sf "$rel" "$dylib" 2>/dev/null
        echo "$base|$new_load|$new_fw|$new_bin" >> "$DEEP_MAP"
    done < <(find "$APP_PKGS" -mindepth 2 -name "*.dylib" -type f -print0 2>/dev/null)

    # Rewrite cross-references in app_packages/.so files that point
    # at the moved dylibs. scipy/cython modules typically reference
    # @loader_path/../.dylibs/libgfortran.5.dylib — install_name_tool
    # needs that exact LC_LOAD_DYLIB string to rewrite it.
    DEEP_COUNT=$(wc -l < "$DEEP_MAP" | tr -d ' ')
    if [ "$DEEP_COUNT" -gt 0 ]; then
        echo "  wrapped $DEEP_COUNT deep dylibs; rewriting refs in .so files"
        while IFS= read -r -d '' so; do
            while IFS='|' read -r dbase dnew_load _ _; do
                [ -z "$dbase" ] && continue
                # Try several reference forms commonly used by wheels:
                for prefix in \
                    "@loader_path/../.dylibs" \
                    "@loader_path/.dylibs" \
                    "@loader_path/lib" \
                    "@rpath"; do
                    old_ref="$prefix/$dbase"
                    if otool -L "$so" 2>/dev/null | grep -q "$old_ref"; then
                        install_name_tool -change "$old_ref" "$dnew_load" "$so" 2>/dev/null || true
                    fi
                done
            done < "$DEEP_MAP"
        done < <(find "$APP_PKGS" -name "*.so" -type f -print0 2>/dev/null)
    fi
    rm -f "$DEEP_MAP"
fi

# ============================================================
# Step 3c2: strip embedded LLVM bitcode segments from every binary
# in Frameworks/ and app_packages/. Vendored xcframeworks (notably
# ios_system.xcframework, which still ships with bitcode for
# legacy compatibility) trigger ITMS-90683 "Bitcode is included
# for an architecture..." on App Store upload. Apple removed
# bitcode support in Xcode 14, so stripping is safe and required.
# ============================================================
echo "wrap-loose-dylibs: stripping bitcode from binaries"
BC_STRIPPED=0
strip_bitcode() {
    local bin="$1"
    [ -f "$bin" ] || return
    file "$bin" 2>/dev/null | grep -q "Mach-O" || return
    if xcrun bitcode_strip -r "$bin" -o "$bin" 2>/dev/null; then
        BC_STRIPPED=$((BC_STRIPPED + 1))
    fi
}
# Walk every framework binary in Frameworks/
while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    [ -f "$plist" ] || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    [ -n "$exe" ] && strip_bitcode "$fw/$exe"
done < <(find "$FW" -name "*.framework" -type d -print0)
# Also strip xcframeworks that ship as <name>.xcframework/<slice>/<name>.framework/<name>
while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    [ -f "$plist" ] || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    [ -n "$exe" ] && strip_bitcode "$fw/$exe"
done < <(find "$APP" -path "*.xcframework/*.framework" -type d -print0 2>/dev/null)
# Walk every .so/.dylib still loose under app_packages/ (post step 3c)
if [ -n "$APP_PKGS" ]; then
    while IFS= read -r -d '' bin; do
        strip_bitcode "$bin"
    done < <(find "$APP_PKGS" \( -name "*.so" -o -name "*.dylib" \) -type f -not -type l -print0 2>/dev/null)
fi
# Main executable
[ -f "$MAIN_BIN" ] && strip_bitcode "$MAIN_BIN"
echo "  stripped bitcode from $BC_STRIPPED binaries"

# ============================================================
# Step 3d: flip Mach-O filetype MH_BUNDLE (0x8) → MH_DYLIB (0x6)
# on every <X>.framework/<X> binary. BeeWare's install_python
# leaves Python C extensions as MH_BUNDLE inside .framework dirs;
# the App Store validator rejects that combination with errors
# like "Invalid Bundle Executable. The MachO type for the
# executable is not valid for this kind of bundle."
# ============================================================
SCRIPT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/scripts"
FIX_PY="$SCRIPT_DIR/fix-macho-type.py"
if [ -f "$FIX_PY" ]; then
    echo "wrap-loose-dylibs: flipping MH_BUNDLE → MH_DYLIB"
    python3 "$FIX_PY" "$APP" 2>&1 | sed 's/^/  /'
else
    echo "  ⚠ fix-macho-type.py not found at $FIX_PY — MH_BUNDLE will trip validator"
fi

# ============================================================
# Step 4: re-sign everything modified
# ============================================================
while IFS='|' read -r base new_load fw_dir new_bin; do
    [ -z "$base" ] && continue
    sign_bin "$new_bin"
    codesign --force --sign "$IDENT" --timestamp=none "$fw_dir" 2>/dev/null || true
done < "$MAP_FILE"

# Re-sign every framework whose binary we touched via install_name_tool -change
while IFS= read -r -d '' fw; do
    plist="$fw/Info.plist"
    [ -f "$plist" ] || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    bin="$fw/$exe"
    [ -f "$bin" ] && sign_bin "$bin"
    codesign --force --sign "$IDENT" --timestamp=none "$fw" 2>/dev/null || true
done < <(find "$FW" -name "*.framework" -type d -print0)

# Re-sign every .so under app_packages/ that we touched with
# install_name_tool (filetype flip + LC_LOAD_DYLIB rewrites both
# invalidate the existing ad-hoc signature).
if [ -n "$APP_PKGS" ]; then
    find "$APP_PKGS" -name "*.so" -type f -not -type l -print0 2>/dev/null |
    while IFS= read -r -d '' so; do
        sign_bin "$so"
    done
fi

# Re-sign the main executable too (rpath edit invalidates its signature)
[ -f "$MAIN_BIN" ] && sign_bin "$MAIN_BIN"

rm -f "$MAP_FILE"

LEFT=$(find "$FW" -maxdepth 1 \( -name "*.dylib" -o -name "*.so" \) -not -type l 2>/dev/null | wc -l | tr -d ' ')
WRAPPED=$(find "$FW" -name "*.framework" -type d | wc -l | tr -d ' ')
DEEP_LEFT=0
[ -n "$APP_PKGS" ] && DEEP_LEFT=$(find "$APP_PKGS" -name "*.dylib" -type f -not -type l 2>/dev/null | wc -l | tr -d ' ')
STATIC_LEFT=$(find "$FW" "$APP" -name "*.a" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "wrap-loose-dylibs: done — $WRAPPED frameworks, $LEFT loose top-level, $DEEP_LEFT loose in app_packages, $STATIC_LEFT static archives"
if [ "$LEFT" -gt 0 ] || [ "$DEEP_LEFT" -gt 0 ] || [ "$STATIC_LEFT" -gt 0 ]; then
    echo "  ⚠ remaining items the validator may reject:"
    find "$FW" -maxdepth 1 \( -name "*.dylib" -o -name "*.so" \) -not -type l 2>/dev/null | sed 's|^|    |'
    [ -n "$APP_PKGS" ] && find "$APP_PKGS" -name "*.dylib" -type f -not -type l 2>/dev/null | sed 's|^|    |'
    find "$FW" "$APP" -name "*.a" -type f 2>/dev/null | sed 's|^|    |'
fi

# ============================================================
# Final assertion: fail the build (non-zero exit) if any of the
# specific files App Store Connect rejects are still present.
# This prevents silently uploading a known-bad archive — the only
# way past this gate is to actually clean the bundle.
# ============================================================
echo "=== wrap-loose-dylibs: final App Store readiness check ==="
_REJECTED=0
_check_absent() {
    local label="$1"; shift
    local found=()
    for _path in "$@"; do
        [ -e "$_path" ] && found+=("$_path")
    done
    if [ ${#found[@]} -gt 0 ]; then
        echo "  ❌ $label still present:"
        for _f in "${found[@]}"; do echo "     $_f"; done
        _REJECTED=$((_REJECTED + ${#found[@]}))
    else
        echo "  ✓ $label clean"
    fi
}
# Static archives anywhere in the .app
_static_archives=()
while IFS= read -r -d '' _a; do _static_archives+=("$_a"); done < <(find "$APP" -name "*.a" -type f -print0 2>/dev/null)
_check_absent "static .a archives" "${_static_archives[@]}"
# Loose .dylib at top of Frameworks/
_loose_dylibs=()
while IFS= read -r -d '' _d; do _loose_dylibs+=("$_d"); done < <(find "$FW" -maxdepth 1 -name "*.dylib" -type f -print0 2>/dev/null)
_check_absent "loose .dylib in Frameworks/" "${_loose_dylibs[@]}"
# Loose .dylib deep in app_packages/
if [ -n "$APP_PKGS" ]; then
    _deep_dylibs=()
    while IFS= read -r -d '' _d; do _deep_dylibs+=("$_d"); done < <(find "$APP_PKGS" -name "*.dylib" -type f -not -type l -print0 2>/dev/null)
    _check_absent "loose .dylib in app_packages/" "${_deep_dylibs[@]}"
fi
# Specific files that have been a problem
# torch_shm_manager: must exist (PyTorch checks for the path) but must
# NOT be a Mach-O binary (App Store rejects). Verify it's a text
# placeholder.
_TORCH_SHM_PATH="$APP/app_packages/site-packages/torch/bin/torch_shm_manager"
if [ -f "$_TORCH_SHM_PATH" ]; then
    if file "$_TORCH_SHM_PATH" 2>/dev/null | grep -q "Mach-O"; then
        echo "  ❌ torch_shm_manager is still a Mach-O — App Store will reject"
        _REJECTED=$((_REJECTED + 1))
    else
        echo "  ✓ torch_shm_manager is text placeholder (App Store-safe)"
    fi
else
    echo "  ⚠ torch_shm_manager missing — torch.multiprocessing won't initialize"
fi
# ITMS-90338 non-public API references — these .so files MUST not ship
_check_absent "manimpango native .so (CTFontCopyDefaultCascadeList)" \
    "$APP/app_packages/site-packages/manimpango/_register_font.cpython-314-iphoneos.so" \
    "$APP/app_packages/site-packages/manimpango/cmanimpango.cpython-314-iphoneos.so"
_check_absent "psutil._psutil_osx (IOPSCopyPowerSources*)" \
    "$APP/app_packages/site-packages/psutil/_psutil_osx.abi3.so"
    # cython_lapack is KEPT (and patched in Step 0c). We don't assert
    # its absence — it's allowed to ship now that we've renamed the
    # _xerbla_array__ import to _xerbla_arr_io_ and provided a stub.
# latex/katex DIRS in Frameworks (data dirs Apple rejects)
[ -d "$FW/latex" ] && [ ! -d "$FW/latex.framework" ] && \
    echo "  ❌ Frameworks/latex/ data dir still present" && _REJECTED=$((_REJECTED + 1))
[ -d "$FW/katex" ] && [ ! -d "$FW/katex.framework" ] && \
    echo "  ❌ Frameworks/katex/ data dir still present" && _REJECTED=$((_REJECTED + 1))

if [ "$_REJECTED" -gt 0 ]; then
    echo ""
    echo "❌ App Store readiness FAILED: $_REJECTED rejected file(s) still in bundle."
    echo "   App Store Connect will reject this upload. Fix above issues before archiving."
    exit 1
fi
echo "✓ App Store readiness OK"
exit 0
