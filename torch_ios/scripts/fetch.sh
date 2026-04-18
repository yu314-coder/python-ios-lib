#!/usr/bin/env bash
# torch_ios/scripts/fetch.sh — clone PyTorch v2.1.2 + only the submodules
# needed for an iOS libtorch_lite build. Keeps the checkout to ~1 GB
# instead of the full ~5 GB of pytorch/pytorch + all 37 submodules.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="$(pwd)/build"
mkdir -p "$BUILD_DIR"

PYTORCH_DIR="$BUILD_DIR/pytorch"
PYTORCH_TAG="v2.1.2"

# --- Submodules actually needed for libtorch_lite iOS ----------------------
# Derived from pytorch/.gitmodules + the .gitmodules entries referenced by
# scripts/build_ios.sh, cmake/Dependencies.cmake in v2.1.2.
NEEDED_SUBMODULES=(
    third_party/pybind11
    third_party/pthreadpool
    third_party/cpuinfo
    third_party/XNNPACK
    third_party/FP16
    third_party/FXdiv
    third_party/psimd
    third_party/sleef
    third_party/fmt
    third_party/eigen
    third_party/foxi
    third_party/onnx
    third_party/flatbuffers
    third_party/protobuf
    third_party/pocketfft   # FFT header-only — needed by ATen/native/mkl/SpectralOps.cpp
    third_party/kineto      # profiler shim — torch/csrc/profiler/kineto_shim.h is unconditional
)
# Kineto has nested submodules (dynolog) — fetch recursively once kineto is initialized.
RECURSIVE_SUBMODULES=(
    third_party/kineto
)

if [ ! -d "$PYTORCH_DIR/.git" ]; then
    echo ">>> Cloning pytorch $PYTORCH_TAG (shallow)…"
    git clone --depth=1 --branch="$PYTORCH_TAG" \
        https://github.com/pytorch/pytorch.git "$PYTORCH_DIR"
else
    echo ">>> PyTorch tree already present at $PYTORCH_DIR"
fi

cd "$PYTORCH_DIR"

echo ">>> Fetching only the ${#NEEDED_SUBMODULES[@]} submodules we need…"
for sm in "${NEEDED_SUBMODULES[@]}"; do
    if [ ! -d "$sm/.git" ] && [ -z "$(ls -A "$sm" 2>/dev/null)" ]; then
        echo "    - $sm"
        git submodule update --init --depth=1 "$sm" || {
            echo "    !! submodule $sm failed to init; continuing"
        }
    fi
done

# Recurse into submodules that have their own submodules (e.g. kineto/dynolog).
for parent in "${RECURSIVE_SUBMODULES[@]}"; do
    if [ -d "$parent/.git" ] || [ -f "$parent/.git" ]; then
        echo "    - recursing into $parent"
        (cd "$parent" && git submodule update --init --depth=1 2>/dev/null) || \
            echo "    !! recursion into $parent failed"
    fi
done

# Apply local iOS patches.
PATCH_DIR="$(cd ../.. && pwd)/patches"
if [ -d "$PATCH_DIR" ] && ls "$PATCH_DIR"/*.patch >/dev/null 2>&1; then
    echo ">>> Applying patches from $PATCH_DIR"
    for p in "$PATCH_DIR"/*.patch; do
        if git apply --check "$p" 2>/dev/null; then
            git apply "$p"
            echo "    applied: $(basename "$p")"
        else
            echo "    skipped (already applied or incompatible): $(basename "$p")"
        fi
    done
fi

echo ">>> Fetch done. Checkout at: $PYTORCH_DIR"
du -sh "$PYTORCH_DIR"
