#!/usr/bin/env bash
# torch_ios/scripts/bundle_xcframework.sh — Phase 1.5
#
# Combines the per-slice static libraries produced by build_libtorch.sh into
# a single `libtorch_ios.xcframework` bundle that can be dropped into an
# Xcode project alongside llama.xcframework, Python.xcframework, etc.
#
# Uses Apple's `libtool -static` to merge the many little .a archives
# (libc10, libtorch_cpu, libkineto, libXNNPACK, libpytorch_qnnpack,
#  libeigen_blas, libfmt, libpthreadpool, libcpuinfo, libclog, libtorch)
# into one fat libtorch.a per slice, then `xcodebuild -create-xcframework`
# glues the slices together.
#
# Usage:
#   ./bundle_xcframework.sh              — uses whatever slices exist
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build/libtorch_ios.xcframework"
rm -rf "$OUT"

SLICES=()
for slice_dir in build/ios-arm64 build/ios-arm64-simulator; do
    if [ -d "$ROOT/$slice_dir/lib" ]; then
        SLICES+=("$slice_dir")
    fi
done

if [ ${#SLICES[@]} -eq 0 ]; then
    echo "No slices built. Run ./scripts/build_libtorch.sh arm64 first."
    exit 1
fi

echo ">>> Slices to bundle: ${SLICES[*]}"

XCF_ARGS=()
for slice_dir in "${SLICES[@]}"; do
    SLICE_NAME="$(basename "$slice_dir")"
    LIB_DIR="$ROOT/$slice_dir/lib"
    # Merge all the static libs for this slice into one uber-archive.
    MERGED="$ROOT/$slice_dir/libtorch_ios_merged.a"
    rm -f "$MERGED"

    echo ">>> Merging ${SLICE_NAME} libs → $(basename "$MERGED")"
    libtool -static -no_warning_for_no_symbols -o "$MERGED" \
        "$LIB_DIR"/libtorch_cpu.a \
        "$LIB_DIR"/libc10.a \
        "$LIB_DIR"/libkineto.a \
        "$LIB_DIR"/libXNNPACK.a \
        "$LIB_DIR"/libpytorch_qnnpack.a \
        "$LIB_DIR"/libeigen_blas.a \
        "$LIB_DIR"/libfmt.a \
        "$LIB_DIR"/libpthreadpool.a \
        "$LIB_DIR"/libcpuinfo.a \
        "$LIB_DIR"/libcpuinfo_internals.a \
        "$LIB_DIR"/libclog.a

    size=$(du -h "$MERGED" | cut -f1)
    echo "    → merged: $size  (arch $(lipo -info "$MERGED" 2>/dev/null | awk '{print $NF}'))"

    XCF_ARGS+=(-library "$MERGED")
done

# The xcframework needs a headers directory with the full libtorch API.
# We collect them from build/pytorch/torch/include (populated by the build)
# and the source tree. Keep only what actually got built — don't ship CUDA
# headers we don't have bits for.
HEADERS_STAGE="$ROOT/build/headers"
rm -rf "$HEADERS_STAGE" && mkdir -p "$HEADERS_STAGE"

PY="$ROOT/build/pytorch"
for h in \
    "$PY/torch/include" \
    "$PY/torch/csrc" \
    "$PY/c10" \
    "$PY/aten/src/ATen" \
; do
    if [ -d "$h" ]; then
        NAME=$(basename "$h")
        mkdir -p "$HEADERS_STAGE/$NAME"
        # Copy only .h / .hpp — skip .cpp / .cu / generated binaries.
        (cd "$h" && find . \( -name "*.h" -o -name "*.hpp" \) -print0 | \
            xargs -0 -I{} cp --parents "{}" "$HEADERS_STAGE/$NAME/" 2>/dev/null) || {
            (cd "$h" && rsync -am --include='*/' --include='*.h' --include='*.hpp' \
                --exclude='*' . "$HEADERS_STAGE/$NAME/")
        }
    fi
done

echo ""
echo ">>> Running xcodebuild -create-xcframework …"
xcodebuild -create-xcframework \
    "${XCF_ARGS[@]}" \
    -headers "$HEADERS_STAGE" \
    -output "$OUT"

echo ""
echo ">>> ✓ libtorch_ios.xcframework created at: $OUT"
du -sh "$OUT"
ls "$OUT"
