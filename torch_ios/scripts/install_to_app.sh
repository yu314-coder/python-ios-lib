#!/usr/bin/env bash
# torch_ios/scripts/install_to_app.sh — Phase 3 installer.
#
# Modes:
#   ./install_to_app.sh              full   — wipe and reinstall the whole torch package
#   ./install_to_app.sh dylibs       quick  — refresh just the .dylib + _C.so artifacts
#   ./install_to_app.sh hot          fast   — quick + push directly into the
#                                              Xcode DerivedData app bundle and
#                                              re-sign so you can re-launch
#                                              without an Xcode rebuild
#
# Why "hot" exists: Xcode's "Embed Frameworks" build phase only re-copies a
# framework if its source mtime is newer than the bundle copy. cp -p preserves
# mtime. So an in-place rebuild of libtorch_python.dylib that doesn't bump the
# mtime can leave a stale dylib in the live app bundle, and the next launch
# silently runs the OLD version. The "hot" mode bypasses Xcode entirely:
# copies into the app bundle, rewrites @loader_path → @rpath install_names,
# and codesigns each dylib + the outer .app so the device-side install flow
# still validates.
set -euo pipefail

MODE="${1:-full}"
case "$MODE" in
    full|dylibs|hot) ;;
    *) echo "Usage: $0 {full|dylibs|hot}" ; exit 2 ;;
esac

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PYTORCH="$ROOT/build/pytorch"
LIBDIR="$ROOT/build/ios-arm64/lib"

# torch_ios: libshm.dylib is built statically against libtorch_cpu.a, which
# means whole-archive linking pulls in every TORCH_LIBRARY init function from
# torch_cpu (incl. the throwing quantized one). The two MUST be rebuilt
# together — if libshm is stale and libtorch_python is fresh, the stale
# libshm's embedded copy of the old library.cpp init still throws at dlopen.
# Force-rebuild both before installing if either is older than the static
# archive they're linked against.
if [ -f "$LIBDIR/libtorch_cpu.a" ]; then
    NEEDS_RELINK=0
    [ "$LIBDIR/libshm.dylib"          -ot "$LIBDIR/libtorch_cpu.a" ] && NEEDS_RELINK=1
    [ "$LIBDIR/libtorch_python.dylib" -ot "$LIBDIR/libtorch_cpu.a" ] && NEEDS_RELINK=1
    if [ "$NEEDS_RELINK" = "1" ]; then
        echo ">>> libshm/libtorch_python older than libtorch_cpu.a → relinking…"
        ( cd "$ROOT/build/ios-arm64" && \
          rm -f lib/libshm.dylib lib/libtorch_python.dylib && \
          ninja shm torch_python ) >/dev/null 2>&1 || {
            echo "    relink failed — fall back to existing dylibs"
        }
    fi
fi

# Source-of-truth app_packages location (what Xcode reads at build time).
APP_SP="${APP_SITE_PACKAGES:-/Volumes/D/OfflinAi/app_packages/site-packages}"
TORCH_DST="$APP_SP/torch"

[ -d "$PYTORCH/torch" ] || { echo "Phase 1 build missing: $PYTORCH/torch"; exit 1; }
[ -f "$LIBDIR/_C.so" ] || { echo "Phase 2 build missing: $LIBDIR/_C.so"; exit 1; }
[ -d "$APP_SP" ] || { echo "App site-packages not found: $APP_SP"; exit 1; }

# ──────────────────────────────────────────────────────────────────────────────
# helper: rewrite install names + rpaths on the deployed dylib so dyld can find
# its siblings under torch/lib/. Idempotent.
fix_install_names() {
    local DST_DIR="$1"   # e.g. .../torch
    install_name_tool -add_rpath "@loader_path/lib" "$DST_DIR/_C.so" 2>/dev/null || true
    install_name_tool -change "@rpath/libtorch_python.dylib" \
                              "@loader_path/lib/libtorch_python.dylib" \
                              "$DST_DIR/_C.so" 2>/dev/null || true
    install_name_tool -change "@rpath/libshm.dylib" \
                              "@loader_path/libshm.dylib" \
                              "$DST_DIR/lib/libtorch_python.dylib" 2>/dev/null || true
}

# helper: copy ONE dylib with forced mtime bump so Xcode notices.
copy_dylib() {
    local SRC="$1" DST="$2"
    cp "$SRC" "$DST"
    touch "$DST"   # bump mtime so Xcode's incremental copy phase fires
}

# helper: copy the torch_shm_manager helper binary (used by torch's
# manager_path() — torch.__init__ raises RuntimeError at import time if
# this file is missing). Lives at torch/bin/torch_shm_manager.
copy_shm_manager() {
    local DST_DIR="$1"   # e.g. .../torch
    local SRC="$ROOT/build/ios-arm64/bin/torch_shm_manager"
    if [ -f "$SRC" ]; then
        mkdir -p "$DST_DIR/bin"
        cp "$SRC" "$DST_DIR/bin/torch_shm_manager"
        touch "$DST_DIR/bin/torch_shm_manager"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "full" ]; then
    echo ">>> [full] Reinstalling torch/ at $TORCH_DST"
    rm -rf "$TORCH_DST"
    mkdir -p "$TORCH_DST/lib"

    echo "    [1/3] Copying pure Python sources…"
    # torch_ios: previously excluded testing/_internal/ but it ships
    # logging_tensor.py which torch.utils.checkpoint imports at module load.
    # Keep _internal; only drop test/ (the test runners, not infra).
    rsync -a --exclude='__pycache__/' --exclude='*.pyc' \
          --exclude='csrc/' --exclude='lib/' \
          --exclude='test/' \
          "$PYTORCH/torch/" "$TORCH_DST/"
    # torch_ios: torchgen is a sibling package to torch in the upstream repo
    # (used by torch._custom_op and a few other modules at import time).
    # Pip-installed torch ships it; we have to copy it manually.
    if [ -d "$PYTORCH/torchgen" ]; then
        rsync -a --exclude='__pycache__/' --exclude='*.pyc' \
              "$PYTORCH/torchgen/" "$APP_SP/torchgen/"
    fi

    # torch_ios: if a venv at .venv_hf/ exists with transformers+hf deps
    # installed, copy those packages too. See docs/libs/pytorch.md for
    # which HF libs are supported on iPad.
    VENV_SP="$ROOT/.venv_hf/lib/python3.14/site-packages"
    if [ -d "$VENV_SP/transformers" ]; then
        echo "    copying transformers + huggingface_hub + filelock + regex-shim…"
        for pkg in transformers huggingface_hub filelock ; do
            [ -d "$VENV_SP/$pkg" ] || continue
            rsync -a --exclude='__pycache__/' --exclude='*.pyc' \
                  "$VENV_SP/$pkg/" "$APP_SP/$pkg/"
        done
        # Skip the venv's `regex` (macOS-only .so) — we keep the shim that
        # forwards to stdlib `re`. If the shim isn't already there, create it.
        if [ ! -f "$APP_SP/regex/__init__.py" ]; then
            mkdir -p "$APP_SP/regex"
            cat > "$APP_SP/regex/__init__.py" <<'REGEXEOF'
# torch_ios: `regex` shim — forwards to stdlib `re`.
import re as _re
from re import *  # noqa: F401,F403
__version__ = "shim-to-re"
V0 = V1 = BESTMATCH = ENHANCEMATCH = REVERSE = POSIX = WORD = 0
REGEXEOF
        fi
    fi

    echo "    [2/3] Installing _C.so + dylibs + shm_manager…"
    copy_dylib "$LIBDIR/_C.so"                  "$TORCH_DST/_C.so"
    copy_dylib "$LIBDIR/libtorch_python.dylib"  "$TORCH_DST/lib/libtorch_python.dylib"
    copy_dylib "$LIBDIR/libshm.dylib"           "$TORCH_DST/lib/libshm.dylib"
    copy_shm_manager                            "$TORCH_DST"

    echo "    [3/3] Rewriting @rpath entries…"
    fix_install_names "$TORCH_DST"
fi

if [ "$MODE" = "dylibs" ] || [ "$MODE" = "hot" ]; then
    echo ">>> [$MODE] Refreshing dylibs only at $TORCH_DST/lib"
    [ -d "$TORCH_DST/lib" ] || { echo "ERROR: run with 'full' first to bootstrap"; exit 1; }
    copy_dylib "$LIBDIR/_C.so"                  "$TORCH_DST/_C.so"
    copy_dylib "$LIBDIR/libtorch_python.dylib"  "$TORCH_DST/lib/libtorch_python.dylib"
    copy_dylib "$LIBDIR/libshm.dylib"           "$TORCH_DST/lib/libshm.dylib"
    copy_shm_manager                            "$TORCH_DST"
    fix_install_names "$TORCH_DST"
fi

# ──────────────────────────────────────────────────────────────────────────────
# "hot" mode also pushes directly into the live app bundles in DerivedData,
# rewriting install_names to @rpath/ and re-codesigning. After this you can
# launch from Xcode without a rebuild and the device gets the fresh dylib.
if [ "$MODE" = "hot" ]; then
    DD="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
    APP_NAME="${APP_NAME:-OfflinAi}"
    SIGN_ID="${CODE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development:/ {print $2; exit}' \
        | xargs -I{} security find-certificate -c "{}" -Z 2>/dev/null \
        | awk '/SHA-1 hash:/ {print $3; exit}')}"

    if [ -z "$SIGN_ID" ]; then
        echo "WARNING: couldn't auto-detect code-signing identity."
        echo "         Set CODE_SIGN_ID=<sha1-hex> or run \`security find-identity -v -p codesigning\`."
        echo "         Skipping hot patch."
        exit 0
    fi

    echo ">>> [hot] Pushing into live app bundles + re-signing"
    echo "    Code sign identity: $SIGN_ID"

    DYLIBS_FOUND=$(find "$DD" -path "*/$APP_NAME.app/Frameworks/libtorch_python.dylib" 2>/dev/null)
    if [ -z "$DYLIBS_FOUND" ]; then
        echo "    No app bundle dylibs found under $DD — has Xcode built the app yet?"
        exit 0
    fi

    echo "$DYLIBS_FOUND" | while read APP_DYLIB; do
        APP_DIR="$(dirname "$(dirname "$APP_DYLIB")")"     # .../OfflinAi.app
        echo "    -> $APP_DYLIB"

        # libtorch_python + libshm
        for fname in libtorch_python.dylib libshm.dylib; do
            [ -f "$LIBDIR/$fname" ] || continue
            DST="$APP_DIR/Frameworks/$fname"
            cp "$LIBDIR/$fname" "$DST"
            install_name_tool -id "@rpath/$fname" "$DST" 2>/dev/null || true
            for dep in $(otool -L "$DST" 2>/dev/null | grep -oE '@loader_path/[^ ]+'); do
                install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$DST" 2>/dev/null || true
            done
            codesign --force --sign "$SIGN_ID" -o runtime --timestamp=none \
                     --generate-entitlement-der "$DST" 2>/dev/null \
              || codesign --force --sign "$SIGN_ID" "$DST"
        done

        # torch_shm_manager helper executable — torch.__init__'s manager_path()
        # raises if this file is missing, so it must exist in the bundle.
        if [ -f "$ROOT/build/ios-arm64/bin/torch_shm_manager" ]; then
            BIN_DIR="$APP_DIR/app_packages/site-packages/torch/bin"
            mkdir -p "$BIN_DIR"
            cp "$ROOT/build/ios-arm64/bin/torch_shm_manager" "$BIN_DIR/torch_shm_manager"
            codesign --force --sign "$SIGN_ID" -o runtime --timestamp=none \
                     --generate-entitlement-der "$BIN_DIR/torch_shm_manager" 2>/dev/null \
              || codesign --force --sign "$SIGN_ID" "$BIN_DIR/torch_shm_manager"
        fi

        # site-packages.torch._C.framework binary still references
        # @loader_path/lib/libtorch_python.dylib — rewrite to @rpath/.
        for fw in "$APP_DIR/Frameworks/site-packages.torch._C.framework" \
                  "$APP_DIR/Frameworks/site-packages.torch._C_flatbuffer.framework"; do
            [ -d "$fw" ] || continue
            BIN="$fw/$(basename "$fw" .framework)"
            [ -f "$BIN" ] || continue
            for dep in $(otool -L "$BIN" 2>/dev/null | grep -oE '@loader_path/lib/[^ ]+'); do
                install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$BIN" 2>/dev/null || true
            done
            # Wipe stale codesign artifacts left over from a prior interrupted
            # signing run — these manifest as "0xe800801c No code signature
            # found" at install time.
            rm -f  "$fw"/*.cstemp 2>/dev/null || true
            rm -rf "$fw/_CodeSignature" 2>/dev/null || true
            codesign --force --sign "$SIGN_ID" -o runtime --timestamp=none \
                     --generate-entitlement-der "$fw" 2>/dev/null \
              || codesign --force --sign "$SIGN_ID" "$fw"
        done

        # Re-sign outer app so its embedded-framework hashes match.
        codesign --force --sign "$SIGN_ID" -o runtime --timestamp=none \
                 --generate-entitlement-der \
                 --preserve-metadata=entitlements,flags "$APP_DIR" 2>/dev/null \
          || codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements,flags "$APP_DIR"
    done
fi

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Done ($MODE)."
echo ""
case "$MODE" in
    full|dylibs)
        echo "Next: rebuild the app in Xcode so the new bytes get embedded."
        echo "      (Or rerun with 'hot' to push into the live app bundle now.)"
        ;;
    hot)
        echo "Next: launch from Xcode (Run, ⌘R) — no rebuild needed."
        echo "      Or  xcrun simctl install booted <path-to-.app>"
        ;;
esac
