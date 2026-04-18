#!/usr/bin/env bash
# torch_ios/scripts/build_libtorch.sh — Phase 1 of Track B.
#
# Cross-compiles libtorch_lite.a + c10.a + friends for one iOS slice:
#   ./build_libtorch.sh arm64       → ios-arm64 (real device)
#   ./build_libtorch.sh simulator   → ios-arm64-simulator
#
# Prerequisites:
#   - ./fetch.sh already ran (pytorch v2.1.2 + submodules in build/pytorch/)
#   - Xcode 16+, CMake 3.18+, ninja, python3 with pyyaml+typing_extensions
#       python3 -m pip install --user pyyaml typing_extensions
#
# NOTE: configure has been verified to succeed on Xcode 17 + CMake 4.3 +
#       iOS SDK 26.2. The wedges required to get there are all baked in
#       below — see ../BUILD_NOTES.md for the archaeology.
set -euo pipefail

SLICE="${1:-arm64}"
case "$SLICE" in
    arm64)      IOS_PLATFORM=OS        ; ARCH=arm64 ; OUT=build/ios-arm64 ;;
    simulator)  IOS_PLATFORM=SIMULATOR ; ARCH=arm64 ; OUT=build/ios-arm64-simulator ;;
    *) echo "Usage: $0 {arm64|simulator}" ; exit 2 ;;
esac

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_ROOT="$ROOT/$OUT"
PYTORCH_DIR="$ROOT/build/pytorch"
TOOLCHAIN="$ROOT/cmake/iOS.toolchain.cmake"

[ -d "$PYTORCH_DIR" ] || { echo "Run ./scripts/fetch.sh first"; exit 1; }
[ -f "$TOOLCHAIN" ]   || { echo "Missing $TOOLCHAIN"; exit 1; }

mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

# ── Derived paths that MUST be computed at runtime ─────────────────────
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
VECLIB_HEADERS="$SDK/System/Library/Frameworks/Accelerate.framework/Frameworks/vecLib.framework/Headers"
PYEXE="$(command -v python3)"

# Sanity-check host python deps (pytorch's codegen step runs on host).
$PYEXE -c "import yaml, typing_extensions" 2>/dev/null || {
    echo "ERROR: host python3 is missing yaml or typing_extensions."
    echo "       Run:  python3 -m pip install --user pyyaml typing_extensions"
    exit 1
}

echo ">>> Configuring Phase 1 (libtorch_lite for ios-$SLICE)…"
cmake "$PYTORCH_DIR" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5    `# CMake 4 compat w/ pre-2018 submodules` \
    -DPYTHON_EXECUTABLE="$PYEXE" \
    -DPython3_EXECUTABLE="$PYEXE" \
    -DIOS_PLATFORM="$IOS_PLATFORM" \
    -DIOS_ARCH="$ARCH" \
    -DIOS_DEPLOYMENT_TARGET=17.0 \
    \
    -DBUILD_LITE_INTERPRETER=OFF          `# full JIT frontend — required so Python bindings (sugared_value, ir_emitter, schema_parser, …) resolve at dlopen time; lite mode was for loading precompiled .ptl, not for "import torch"` \
    -DUSE_LIGHTWEIGHT_DISPATCH=OFF        `# v2.1.2 codegen bug: at::sym_* missing` \
    -DTRACING_BASED=OFF \
    -DUSE_PYTORCH_METAL=ON                `# iPad GPU backend` \
    -DUSE_COREML_DELEGATE=ON              `# Neural Engine dispatch` \
    \
    -DBUILD_CAFFE2_OPS=OFF \
    -DBUILD_CUSTOM_PROTOBUF=OFF \
    -DBUILD_TEST=OFF -DBUILD_BINARY=OFF -DBUILD_PYTHON=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    \
    -DUSE_MKLDNN=OFF -DUSE_OPENMP=OFF -DUSE_DISTRIBUTED=OFF -DUSE_NUMPY=OFF \
    -DUSE_CUDA=OFF -DUSE_CUDNN=OFF -DUSE_FBGEMM=OFF -DUSE_NCCL=OFF \
    -DUSE_MPI=OFF -DUSE_GLOO=OFF -DUSE_TENSORPIPE=OFF -DUSE_NNPACK=OFF \
    -DUSE_KINETO=ON                       `# required — profiler_edge.cpp uses KinetoEdgeCPUProfiler unconditionally` \
    -DLIBKINETO_NOCUPTI=ON -DLIBKINETO_NOROCTRACER=ON  `# no GPU tracing — iOS has neither` \
    -DUSE_BREAKPAD=OFF -DUSE_ROCM=OFF -DUSE_MAGMA=OFF \
    -DUSE_ITT=OFF -DUSE_GFLAGS=OFF -DUSE_OPENCV=OFF \
    -DUSE_LMDB=OFF -DUSE_LEVELDB=OFF \
    \
    -DUSE_XNNPACK=ON -DUSE_QNNPACK=ON -DUSE_PYTORCH_QNNPACK=ON \
    -DUSE_LITE_INTERPRETER_PROFILER=OFF \
    \
    -DUSE_BLAS=ON -DBLAS=vecLib           `# Apple historic name for Accelerate` \
    -DvecLib_INCLUDE_DIR="$VECLIB_HEADERS" \
    -DUSE_LAPACK=1                        `# torch_ios: force-enable LAPACK; Apple's Accelerate.framework provides it (cheev_/dgesvd_/etc). Cross-compile check_function_exists test fails silently otherwise.` \
    -DLAPACK_LIBRARIES=-framework\ Accelerate \
    -DLAPACK_FOUND=TRUE \
    -DCAFFE2_USE_ACCELERATE=ON \
    \
    -DCMAKE_THREAD_LIBS_INIT=-lpthread \
    -DCMAKE_HAVE_THREADS_LIBRARY=1 \
    -DCMAKE_USE_PTHREADS_INIT=1 \
    -DCMAKE_CXX_FLAGS=-fobjc-arc \
    \
    -DCMAKE_BUILD_TYPE=MinSizeRel

echo ""
echo ">>> Compiling (this takes 2–4 hours on an M-series Mac)…"
echo ">>> Tail -f $BUILD_ROOT/.ninja_log  in another terminal to watch progress."
ninja -j "$(sysctl -n hw.ncpu)"

echo ""
echo ">>> ✓ Built libraries:"
find . -maxdepth 3 -name "*.a" | sort | head -20
