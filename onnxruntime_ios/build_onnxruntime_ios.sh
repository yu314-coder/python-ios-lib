#!/bin/zsh
# build_onnxruntime_ios.sh — onnxruntime v1.26.0 for iOS arm64 with the
# CoreML execution provider + CPython 3.14 bindings.
#
# Proven fixes baked in:
#   * CMAKE_POLICY_VERSION_MINIMUM=3.5 — CMake 4.x refuses the ancient
#     cmake_minimum_required in the fetched psimd dep.
#   * --cmake_generator Xcode        — mandatory for --ios in build.py.
#   * Phase-B reconfigure must pass  --compile-no-warning-as-error, or the
#     regenerated project re-enables -Werror and CoreML's iOS-17.4/18
#     availability warnings become errors at deploy target 16.4.
#   * pybind11 v3.0.2 (pinned by v1.26.0) supports CPython 3.14.
#   * FindPython artifact overrides point compilation at the iOS Python
#     headers + iOS numpy headers; _Py* stay undefined (dynamic_lookup,
#     resolved from the app's loaded Python.framework).
#
# Install step: copy build_ios/MinSizeRel/MinSizeRel-iphoneos/onnxruntime/
# → app_packages/site-packages/onnxruntime (EXCLUDING capi/*.a and
# capi/libonnxruntime*.dylib — App Store rejects loose static libs).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
IOS_PY=/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/Python.framework
NP_INC=/Volumes/D/OfflinAi/numpy_ios/headers-ios-arm64/numpy/_core/include
export TMPDIR=/Volumes/D/tmp

[ -d "$SRC" ] || git clone --depth 1 --branch v1.26.0 \
    https://github.com/microsoft/onnxruntime.git "$SRC"

echo "→ Phase A: core static libs + CoreML EP"
cd "$SRC"
python3 tools/ci_build/build.py \
  --build_dir ../build_ios \
  --config MinSizeRel \
  --ios --apple_sysroot iphoneos --osx_arch arm64 --apple_deploy_target 16.4 \
  --cmake_generator Xcode \
  --use_coreml \
  --parallel --skip_tests \
  --compile_no_warning_as_error \
  --skip_submodule_sync \
  --cmake_extra_defines CMAKE_POLICY_VERSION_MINIMUM=3.5

echo "→ Phase B: python bindings (cross overrides)"
B="$HERE/build_ios/MinSizeRel"
/opt/homebrew/bin/cmake "$B" \
  --compile-no-warning-as-error \
  -Donnxruntime_ENABLE_PYTHON=ON \
  -DPython_EXECUTABLE=/usr/local/bin/python3 \
  -DPython_INCLUDE_DIR="$IOS_PY/Headers" \
  -DPython_LIBRARY="$IOS_PY/Python" \
  -DPython_NumPy_INCLUDE_DIR="$NP_INC" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
/opt/homebrew/bin/cmake --build "$B" --config MinSizeRel \
  --target onnxruntime_pybind11_state --parallel 10

echo "done. package at: $B/MinSizeRel-iphoneos/onnxruntime/"
