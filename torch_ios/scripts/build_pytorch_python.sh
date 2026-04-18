#!/usr/bin/env bash
# torch_ios/scripts/build_pytorch_python.sh — Phase 2 of Track B.
#
# Builds the Python C extension modules (_C.so, _C_flatbuffer.so, etc.)
# as signed iOS `.framework` bundles, linking against libtorch from
# Phase 1 and the Python.xcframework that the host app already ships.
#
# ⚠ This is the HARD phase. Current status: scaffolding only — the
# actual build is expected to fail with linker errors around CPython
# extension init hooks and pybind11's `dlopen`-based module loader.
# See README.md → "Current status per phase".
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PYTORCH_DIR="$ROOT/build/pytorch"
PHASE1_ARM64="$ROOT/build/ios-arm64"
PHASE1_SIM="$ROOT/build/ios-arm64-simulator"

[ -d "$PHASE1_ARM64" ] || { echo "Run ./scripts/build_libtorch.sh arm64 first"; exit 1; }

# Path to the Python headers + tbd we link against. Must match the
# Python.xcframework that the OfflinAi app embeds (currently Python 3.14).
PYTHON_XCFRAMEWORK="$ROOT/../Frameworks/Python.xcframework"
PYTHON_HEADERS="$PYTHON_XCFRAMEWORK/ios-arm64/Python.framework/Headers"
PYTHON_TBD="$PYTHON_XCFRAMEWORK/ios-arm64/Python.framework/Python.tbd"

echo ">>> Phase 2 is not implemented yet."
echo ""
echo "Expected steps once a working path is found:"
cat <<'EOF'

  1. For each Python extension module in pytorch/torch/_C*/, produce a
     .dylib that exports CPython's PyInit_* entry point.
     Build with:  clang++ -dynamiclib -target arm64-apple-ios17.0 \
                           -I$PYTHON_HEADERS -lPython -lc++ \
                           -L$PHASE1_ARM64 -ltorch_cpu -lc10 -ltorch \
                           torch/csrc/Module.cpp -o _C.dylib

  2. Wrap each .dylib in a *.framework with an Info.plist, code-sign
     with the app's provisioning profile (iOS refuses to dlopen unsigned
     dylibs from the sandbox).

  3. Copy the signed frameworks into app_packages/site-packages/torch/_C.so
     (rename .dylib → .so so CPython's import system finds it).

  4. Add a rpath so the runtime loader finds libtorch:
       install_name_tool -add_rpath \
         "@loader_path/../Frameworks" \
         torch/_C.so

  5. Test: a Python script that does `import torch; print(torch.__file__)`
     and doesn't crash.

  6. Then test `torch.tensor([1,2,3])` and iterate on missing symbols
     until forward passes work.

Blockers identified so far:
  - pybind11 on iOS: works in principle but requires RTLD_LOCAL guards.
  - CPython's `dl_open`-based ext loading uses flags (RTLD_GLOBAL|RTLD_LAZY)
    that iOS dyld silently downgrades. Torch's internal extension-to-
    extension references may fail at first use.
  - `torch.utils.cpp_extension` must be amputated (it spawns clang at
    runtime, which iOS forbids).
  - `torch.distributed`, `torch.multiprocessing` pull in fork()+pipe()
    paths that need stubs.
EOF
exit 1
