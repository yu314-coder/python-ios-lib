#!/bin/bash
# wrap-binaries-as-frameworks.sh — App Store distribution prep
# ============================================================
# Apple's validator rejects every loose `.so` / `.dylib` inside an
# iOS .app, including ones nested inside SPM resource bundles. The fix:
# wrap each Mach-O as a real `.framework` under `<App>.app/Frameworks/`,
# rewrite cross-extension `LC_LOAD_DYLIB` references so dyld can still
# resolve them, leave a placeholder at the original path so Python's
# `__file__` introspection works, and emit a manifest the runtime
# import hook reads to route module imports to the framework binaries.
#
# This script is DEFENSIVE — it handles every category of breakage
# we've seen in the wild:
#   1. python-stdlib/lib-dynload/*.so  (BeeWare's stdlib)
#   2. python-ios-lib_*.bundle/.../*.so  (numpy, scipy, etc.)
#   3. Inter-extension @rpath dyld deps (scipy.linalg cython_blas etc.)
#   4. Package-local .dylibs/ dirs (scipy's libgfortran/libquadmath)
#   5. PyAV's hardcoded /tmp/ffmpeg-ios/ install_names
#   6. LaTeXEngine's nested .xcframework slices
#   7. __file__ introspection (placeholder stub at original path)
#
# Usage in your iOS app target's Build Phases (Xcode):
#   1. Drop this script in your project (e.g. scripts/wrap_binaries.sh)
#   2. Build Phases → + → New Run Script Phase
#   3. Shell: /bin/bash, point at the script's path
#   4. Place AFTER "Copy Bundle Resources" + any stdlib-copy step
#   5. Build Settings: ENABLE_USER_SCRIPT_SANDBOXING = NO
# ============================================================
set -e

APP="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
FRAMEWORKS="$APP/Frameworks"
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:--}"
MANIFEST="$APP/python-ios-lib_extension_manifest.txt"
RPATH_MAP="${TEMP_DIR:-/tmp}/python-ios-lib_rpath_map_$$.txt"

mkdir -p "$FRAMEWORKS"
: > "$MANIFEST"
: > "$RPATH_MAP"

# ============================================================
# Helpers
# ============================================================

# Sanitize a dotted Python module name → valid framework directory name.
# numpy._core._multiarray_umath  →  numpy_core_multiarray_umath
sanitize() {
    echo "$1" | tr '/.' '__' | sed 's/^_*//' | sed 's/__*/_/g'
}

# Minimal Info.plist for a wrapped extension framework.
write_plist() {
    local name="$1" out="$2"
    cat > "$out" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>${name}</string>
    <key>CFBundleIdentifier</key>            <string>ai.codebench.pythonext.${name}</string>
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

sign_lib() {
    codesign --force --sign "$IDENT" --timestamp=none \
        --preserve-metadata=identifier,entitlements,flags "$1" 2>/dev/null \
        || codesign --force --sign "$IDENT" --timestamp=none "$1" 2>/dev/null \
        || true
}

# Wrap one Mach-O at $src as Frameworks/<name>.framework/<name>.
# Records: original_path → framework_name in $RPATH_MAP for later rewriting.
# Records: dotted_module → framework_name in $MANIFEST for runtime hook.
wrap_one() {
    local src="$1" module_name="$2"
    local name; name="$(sanitize "$module_name")"
    local fw="$FRAMEWORKS/${name}.framework"

    # If a framework with this name already exists, dedup — second .so
    # with the same sanitized name is rare but possible (scipy has both
    # _zeros and optimize/_zeros). Append a hash of the source path.
    if [ -d "$fw" ]; then
        local hash; hash=$(echo -n "$src" | shasum | head -c 6)
        name="${name}_${hash}"
        fw="$FRAMEWORKS/${name}.framework"
    fi

    mkdir -p "$fw"
    # Move binary in with clean name (no .so / .dylib suffix).
    mv -f "$src" "$fw/$name"
    # New self-id so dyld can resolve @rpath references.
    install_name_tool -id "@rpath/${name}.framework/${name}" "$fw/$name" 2>/dev/null || true
    write_plist "$name" "$fw/Info.plist"

    # Record original-path → new-binary-path for cross-reference rewriting.
    # Also record original .so basename → new path (some LC_LOAD_DYLIB
    # entries use bare basename via @rpath).
    local original_basename; original_basename=$(basename "$src")
    echo "$src|$fw/$name|$original_basename|$name" >> "$RPATH_MAP"

    # Manifest entry — the dotted Python name → sanitized framework name.
    echo "${module_name}=${name}" >> "$MANIFEST"

    # Leave a 0-byte placeholder at the original path so packages that
    # check for file existence or read __file__'s parent dir don't
    # AttributeError. Python won't try to dlopen this — the import hook
    # intercepts the import before fileio. NOTE: we'll create these
    # AFTER all the .so collection passes so we don't double-process.
}

# ============================================================
# 1. Collect every Mach-O we need to wrap (stdlib + SPM bundles + Frameworks/ dylibs)
# ============================================================

# Use a temp-file work-list so we can do a clean pass-1 (collect+wrap),
# pass-2 (rewrite cross-refs), pass-3 (placeholders + signing).
WORKLIST="${TEMP_DIR:-/tmp}/python-ios-lib_worklist_$$.txt"
: > "$WORKLIST"

# 1a. python-stdlib/lib-dynload/*.so  →  module name "stdlib_<modname>"
DYNLOAD="$APP/python-stdlib/lib-dynload"
if [ -d "$DYNLOAD" ]; then
    while IFS= read -r -d '' so; do
        base=$(basename "$so")
        mod="${base%%.cpython-*}"; mod="${mod%.abi3.so}"; mod="${mod%.so}"
        echo "$so|stdlib.${mod}" >> "$WORKLIST"
    done < <(find "$DYNLOAD" -name "*.so" -print0)
fi

# 1b. python-ios-lib_*.bundle/.../*.{so,dylib}  →  dotted module name
for bundle in "$APP"/python-ios-lib_*.bundle; do
    [ -d "$bundle" ] || continue
    while IFS= read -r -d '' so; do
        rel="${so#$bundle/}"
        # Strip .cpython-XYZ.so / .abi3.so / .so / .dylib
        stripped=$(echo "$rel" | sed -E 's/\.(cpython-[^.]+|abi3)\.(so|dylib)$//' \
                                       | sed -E 's/\.(so|dylib)$//')
        # numpy/_core/_multiarray_umath  →  numpy._core._multiarray_umath
        module_name=$(echo "$stripped" | tr '/' '.')
        echo "$so|$module_name" >> "$WORKLIST"
    done < <(find "$bundle" \( -name "*.so" -o -name "*.dylib" \) -print0)
done

# 1c. Loose dylibs already in Frameworks/ from earlier README script
# (libfortran_io_stubs, libsf_error_state, ffmpeg dylibs, etc.). They
# need to be framework-wrapped too — App Store rejects loose dylibs in
# Frameworks/ that aren't inside .framework/ directories.
while IFS= read -r -d '' loose; do
    # Skip stuff that's already inside a .framework directory.
    case "$loose" in *.framework/*) continue ;; esac
    case "$loose" in *.xcframework/*) continue ;; esac
    base=$(basename "$loose"); name="${base%.dylib}"; name="${name%.so}"
    # Strip version suffix (libavcodec.62.29.101 → libavcodec)
    name=$(echo "$name" | sed -E 's/\.[0-9]+(\.[0-9]+)*$//')
    echo "$loose|loose.${name}" >> "$WORKLIST"
done < <(find "$FRAMEWORKS" -maxdepth 1 \( -name "*.so" -o -name "*.dylib" \) -print0 2>/dev/null)

# ============================================================
# 2. Pass 1: wrap every collected binary
# ============================================================
WRAPPED_COUNT=0
while IFS='|' read -r src module_name; do
    [ -z "$src" ] && continue
    [ -f "$src" ] || continue
    wrap_one "$src" "$module_name"
    WRAPPED_COUNT=$((WRAPPED_COUNT + 1))
done < "$WORKLIST"

# ============================================================
# 3. Pass 2: rewrite LC_LOAD_DYLIB cross-references in every wrapped binary
# ============================================================
# For each wrapped binary, scan its `otool -L` output for references to
# any other wrapped binary's original path/basename, and rewrite to
# @rpath/<new_framework>/<new_binary>.
rewrite_cross_refs() {
    local target="$1"
    [ -f "$target" ] || return
    # otool -L outputs:  <load_path> (compatibility version X, current version Y)
    while IFS= read -r line; do
        local old_path
        old_path=$(echo "$line" | awk '{print $1}' | grep -v '^$' || true)
        [ -z "$old_path" ] && continue
        # Skip system libraries
        case "$old_path" in
            /usr/lib/*|/System/*|@rpath/Python.framework/*|@executable_path/*)
                continue ;;
        esac
        local old_basename; old_basename=$(basename "$old_path")
        # Try to find matching entry in RPATH_MAP — first by full path,
        # then by basename (for @rpath/<basename> style references).
        local new_load=""
        while IFS='|' read -r orig new_full orig_base new_name; do
            [ -z "$orig" ] && continue
            if [ "$orig" = "$old_path" ] || [ "$orig_base" = "$old_basename" ]; then
                new_load="@rpath/${new_name}.framework/${new_name}"
                break
            fi
        done < "$RPATH_MAP"
        # Common case: PyAV's /tmp/ffmpeg-ios/install/lib/libavcodec.62.dylib
        # → strip path, look up by basename, including version variants.
        if [ -z "$new_load" ]; then
            local stripped_base; stripped_base=$(echo "$old_basename" | sed -E 's/\.[0-9]+(\.[0-9]+)*\.dylib$/.dylib/')
            while IFS='|' read -r orig new_full orig_base new_name; do
                [ -z "$orig" ] && continue
                if [ "$orig_base" = "$old_basename" ] || [ "$orig_base" = "$stripped_base" ]; then
                    new_load="@rpath/${new_name}.framework/${new_name}"
                    break
                fi
            done < "$RPATH_MAP"
        fi
        if [ -n "$new_load" ] && [ "$new_load" != "$old_path" ]; then
            install_name_tool -change "$old_path" "$new_load" "$target" 2>/dev/null || true
        fi
    done < <(otool -L "$target" 2>/dev/null | tail -n +2)

    # Add @loader_path/.. to rpath so dyld searches sibling frameworks
    # in Frameworks/ when @rpath/<x>.framework/... references fire.
    install_name_tool -add_rpath "@loader_path/.." "$target" 2>/dev/null || true
    install_name_tool -add_rpath "@executable_path/Frameworks" "$target" 2>/dev/null || true
}

while IFS= read -r -d '' bin; do
    rewrite_cross_refs "$bin"
done < <(find "$FRAMEWORKS" -name "*.framework" -type d -print0 | \
         while IFS= read -r -d '' fw; do
             find "$fw" -maxdepth 1 -type f -print0
         done)

# ============================================================
# 4. Pass 3: re-sign every framework now that install_name_tool changes
#    are in (codesign invalidates after any binary mutation)
# ============================================================
while IFS= read -r -d '' bin; do
    sign_lib "$bin"
done < <(find "$FRAMEWORKS" -name "*.framework" -type d -print0 | \
         while IFS= read -r -d '' fw; do
             find "$fw" -maxdepth 1 -type f -print0
         done)
while IFS= read -r -d '' fw; do
    codesign --force --sign "$IDENT" --timestamp=none "$fw" 2>/dev/null || true
done < <(find "$FRAMEWORKS" -name "*.framework" -type d -print0)

# ============================================================
# 5. LaTeXEngine: lift native xcframeworks out of the resource bundle
# ============================================================
LATEX_BUNDLE="$APP/python-ios-lib_LaTeXEngine.bundle/latex"
if [ -d "$LATEX_BUNDLE" ]; then
    case "$PLATFORM_NAME" in
        iphoneos)        SLICE="ios-arm64" ;;
        iphonesimulator) SLICE="ios-arm64_x86_64-simulator" ;;
        *)               SLICE="ios-arm64" ;;
    esac
    for xcf_dir in "$LATEX_BUNDLE"/*.xcframework; do
        [ -d "$xcf_dir" ] || continue
        local_slice=""
        for candidate in "$xcf_dir/$SLICE" "$xcf_dir"/ios-arm64*; do
            if [ -d "$candidate" ]; then local_slice="$candidate"; break; fi
        done
        [ -n "$local_slice" ] || continue
        for fw in "$local_slice"/*.framework; do
            [ -d "$fw" ] || continue
            fw_name=$(basename "$fw" .framework)
            if [ ! -d "$FRAMEWORKS/$fw_name.framework" ]; then
                cp -R "$fw" "$FRAMEWORKS/"
                sign_lib "$FRAMEWORKS/$fw_name.framework/$fw_name"
                codesign --force --sign "$IDENT" --timestamp=none \
                    "$FRAMEWORKS/$fw_name.framework" 2>/dev/null || true
            fi
        done
        rm -rf "$xcf_dir"
    done
fi

# ============================================================
# 6. __file__ placeholders — leave a 0-byte stub at every original path
#    so Python packages that read `os.path.dirname(__file__)` for data-
#    file lookup don't crash. The import hook intercepts the actual
#    import before any dlopen would happen.
# ============================================================
while IFS='|' read -r orig new_full orig_base new_name; do
    [ -z "$orig" ] && continue
    [ -e "$orig" ] && continue
    mkdir -p "$(dirname "$orig")"
    : > "$orig"
done < "$RPATH_MAP"

# ============================================================
# 7. Final cleanup
# ============================================================
rm -f "$WORKLIST" "$RPATH_MAP"

echo "wrap-binaries: framework-wrapped $WRAPPED_COUNT extensions/dylibs."
echo "  manifest: $MANIFEST"
echo "  Frameworks/: $(find "$FRAMEWORKS" -name "*.framework" -type d | wc -l | tr -d ' ') framework dirs"
