# onnxruntime — native ONNX inference with the CoreML execution provider

> **Version:** 1.26.0 | **Providers:** `CoreMLExecutionProvider` (Neural Engine / GPU), `CPUExecutionProvider` | **Bindings:** CPython 3.14 (pybind11 3.0.2) | **Module:** `onnxruntime/capi/onnxruntime_pybind11_state` (25.9 MB) | **Recipe:** `onnxruntime_ios/build_onnxruntime_ios.sh`

First public iOS build of the real onnxruntime Python package. Two-phase
build: the official `build.py --ios --use_coreml` (Xcode generator) for the
static core + CoreML EP, then a reconfigure that cross-compiles the pybind11
bindings against the iOS CPython 3.14 headers.

## Quick start

```python
import onnxruntime as ort
import numpy as np

print(ort.get_available_providers())
# ['CoreMLExecutionProvider', 'CPUExecutionProvider']

sess = ort.InferenceSession(
    "model.onnx",
    providers=["CoreMLExecutionProvider", "CPUExecutionProvider"])
y = sess.run(None, {"x": np.ones((1, 3, 32, 32), np.float32)})[0]
```

## Device-verified (Mac Designed-for-iPad, M-series)

| Check | Result |
|---|---|
| CPU vs CoreML numerical agreement (Conv/Relu/MaxPool/GAP) | max abs diff 6e-08 |
| CoreML exact values on MatMul+Add | fp16 rounding ≤ 4e-04 |
| 2×Conv @128×128, 15 timed runs | **CPU ~2.2 ms vs CoreML ~0.17 ms (12–14×)** |
| dynamic batch (N=1/5/32), multi-output fetch, `OrtValue`+`IOBinding`, session profiling | all pass |

## Notes & limitations

- **Export models on the host.** The bundled iOS torch 2.1 strips the ONNX
  export JIT passes (`torch._C._jit_pass_onnx_*`), so `torch.onnx.export`
  fails on-device. Export on a Mac/PC, copy the `.onnx` over, run on device.
- The `onnx` package (model authoring/checking) is not bundled — build test
  models on the host too.
- CoreML EP runs fp16 on the ANE — expect ~1e-3-level rounding vs CPU fp32;
  use tolerances accordingly.
- App Store packaging: ship ONLY the python package tree; `capi/*.a` and
  `capi/libonnxruntime*.dylib` must be excluded (ITMS-90171 rejects loose
  static libraries in the bundle).
- Platform validation warnings are patched to accept `ios`/`ipados`, and a
  `build_and_package_info.py` is bundled so import is warning-free.

## Build gotchas (documented in the recipe)

1. `--cmake_generator Xcode` is mandatory for `--ios`.
2. `CMAKE_POLICY_VERSION_MINIMUM=3.5` — CMake 4 refuses the psimd dep's
   ancient `cmake_minimum_required`.
3. The phase-B reconfigure must pass `--compile-no-warning-as-error`, or
   CoreML's iOS-17.4/18 availability warnings become errors at the 16.4
   deploy target.
4. FindPython artifact overrides point compilation at the iOS
   `Python.framework/Headers` + iOS numpy includes; `_Py*` symbols stay
   undefined and resolve at load from the app's Python (dynamic_lookup).
