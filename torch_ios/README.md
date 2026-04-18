# torch_ios — Full `import torch` Wheel Build for iOS/iPadOS

**Status:** 🚧 Experimental / research. Expect weeks of debugging.

This directory holds the build infrastructure for producing a `torch` Python
wheel that loads on iOS and gives users real `import torch` inside the
OfflinAi app (Track B of the PyTorch migration plan).

Unlike [ExecuTorch](../Frameworks/ExecuTorch/) (Track C — already shipping in
the app), which only exposes a Swift API for running precompiled `.pte` models,
this build pipeline targets the **full PyTorch Python surface** — tensors,
autograd, nn.Module, JIT, optimizers — so HuggingFace `transformers` and
anything else that does `import torch` works out of the box.

## Why this is hard

Facebook removed `scripts/build_ios.sh` from PyTorch main around v2.2 (mid-
2024) when they pivoted to ExecuTorch. The last commit that still has a
working iOS build script is **`v2.1.2`** (tag `v2.1.2`, Dec 2023). Even that
target only produced `libtorch` static libs for C++/Swift — NOT a Python
extension module. To get `import torch` working we additionally need:

1. Build `libtorch_lite` (C++ inference runtime) for `arm64-apple-ios`.
2. Build every PyTorch Python C extension (`_C.so`, `_C_flatbuffer.so`,
   `_dl.so`, `_distributed_c10d.so`, etc.) as iOS dylibs.
3. Sign each `.so` as an individual `*.framework` (iOS refuses to
   `dlopen()` unsigned bare `.so` files).
4. Stub or no-op every POSIX call PyTorch uses that iOS forbids (`fork`,
   `execve`, `dlopen` of writable pages, `MAP_JIT` without the entitlement…).
5. Replace OpenMP/MKL with Apple's **Accelerate** framework.
6. Ship the whole thing as an installable wheel that drops into the app's
   `app_packages/site-packages/` alongside `numpy`, `scipy`, etc.

No one has successfully shipped this publicly. Closest references:

- **BeeWare `python-apple-support`** — builds Python stdlib + a few packages
  for iOS, but explicitly does NOT include `torch`.
- **Facebook `libtorch-iOS` Mobile** (pre-2024) — C++ only, no Python.
- **PyTorch `BUILD_LITE_INTERPRETER=1`** — still only yields static libs.

## File layout

```
torch_ios/
├── README.md              ← this file
├── cmake/
│   └── iOS.toolchain.cmake  ← cross-compile toolchain for ios-arm64
├── patches/
│   └── 0001-torch-ios-disable-fork.patch   (stub patches applied to pytorch
│   └── 0002-torch-ios-accelerate-blas.patch  source tree before the build)
├── scripts/
│   ├── fetch.sh           ← clone pytorch v2.1.2 + needed submodules
│   ├── build_libtorch.sh  ← Phase 1: C++ static libs  (~2–4 h)
│   ├── build_pytorch_python.sh  ← Phase 2: Python C extensions  (HARD)
│   └── package_wheel.sh   ← Phase 3: bundle into an .ios-arm64.whl
└── build/                 ← gitignored, holds CMake build dirs
```

## Quickstart (once patches exist)

```bash
# Prerequisites: Xcode 16+, CMake 3.27+, Python 3.14 (to match the
# Python.xcframework the app ships), ninja, ccache recommended.

cd torch_ios
./scripts/fetch.sh                     # ~5 GB clone, ~30 min first time
./scripts/build_libtorch.sh arm64      # Phase 1 — ~2 h on an M-series Mac
./scripts/build_libtorch.sh simulator  #        same, for simulator slice
./scripts/build_pytorch_python.sh      # Phase 2 — currently FAILS; see NOTES
./scripts/package_wheel.sh             # Phase 3 — packages the result
```

The resulting wheel lands at `torch_ios/build/dist/torch-2.1.2-ios_arm64.whl`.
Drop it into `app_packages/site-packages/` to enable `import torch`.

## Current status per phase

| Phase | Status | Blocker |
|---|---|---|
| 1. libtorch C++ static libs for iOS (arm64) | ✅ **DONE** — 185 MB libtorch_cpu.a (full JIT) | — |
| 1b. libtorch simulator slice + xcframework bundle | 🟡 needs `build_libtorch.sh simulator` | - |
| 2. Python extension modules — `libtorch_python.dylib` + `_C.so` | ✅ **DONE** — 98 MB dylib + 48 KB stub, arm64 iOS 17, `PyInit__C` exported | — |
| 3. App bundle integration — code-signed `.framework` + install_name rewrite | ✅ **DONE** — `site-packages.torch._C.framework` installed + signed in app bundle, rpaths resolve to sibling dylibs | — |
| 4. `import torch` + full acceptance test on iPad | ✅ **DONE (2026-04-18)** — **57/57 tests pass** on iPad-on-Mac including 6-section training loop with SGD. `import torch` takes ~6.3 s. | — |
| 5. Run on real iPad device (cellular iPad Air M3) | 🟡 simulator/Mac works; device build hits the same codepath but needs fresh install | - |

### What tests pass today

`torch_test_all.py` (auto-installed to `Workspace/`) exercises:

```
 1. import ─── import torch, torch.nn, torch.nn.functional
 2. tensor creation ─── tensor, zeros, ones, arange, randn, eye
 3. arithmetic + broadcasting
 4. reductions + indexing ─── sum, mean, max, argmax, boolean mask
 5. shape manipulation ─── reshape, flatten, cat, stack, permute, squeeze
 6. linear algebra (LAPACK via Accelerate) ─── det, inv, norm, svd
 7. autograd ─── backward(), no_grad()
 8. nn.Module forward pass
 9. activation + loss ─── relu, sigmoid, tanh, softmax, MSE, CE
10. **end-to-end training loop** ─── SGD fits w=3 b=1 to final loss 0.00011
11. device/backend availability probes
12. serialization ─── torch.save / torch.load / load_state_dict

57/57 pass.  No C-side failures after static-init phase.
```

## Why v2.1.2 specifically

- Last tag with `scripts/build_ios.sh` + `cmake/iOS.cmake` present.
- Matches the ExecuTorch version we're already shipping (1.3 branches off of
  torch 2.1.x), so shared symbols won't clash if both are loaded in one app.
- Old enough to be conservative; new enough that HF transformers still works.

Later tags can work but require re-porting the iOS toolchain.

## Running `transformers` once `torch` works

Once the wheel installs and `import torch` works, `transformers` is *mostly*
a pure-Python package and will install from PyPI without a rebuild:

```python
import subprocess, sys
subprocess.check_call([sys.executable, "-m", "pip", "install",
                       "transformers", "--target",
                       "/var/mobile/Containers/.../site-packages"])
```

Exceptions:
- `transformers[tokenizers]` uses a Rust-backed `.so` — need a separate iOS
  build (probably easier than torch).
- `transformers[onnx]`, `xformers` — NOT portable to iOS (CUDA, Rust, etc.).

## Contributing

This is a long-running research effort. Expected milestones:

- [ ] **M1:** `libtorch_lite.xcframework` built cleanly from v2.1.2 on
      Xcode 16 / macOS 15+.
- [ ] **M2:** Minimal `_C.so` compiles + iOS-code-signs as a framework.
- [ ] **M3:** `import torch` succeeds on an iPad; `torch.tensor([1,2,3])`
      evaluates.
- [ ] **M4:** `torch.nn.Linear(3,2)(x)` runs a forward pass on device.
- [ ] **M5:** `AutoModel.from_pretrained(...)` loads a small HF model.
- [ ] **M6:** GPU (MPS) and Neural Engine (CoreML-dispatch) backends wired up.

Open issues and progress will be tracked in the repo's GitHub issues.

## Alternative recommendation

**Most users should use ExecuTorch (already shipped)** via the `offlinai_torch`
Python bridge. See `app_packages/site-packages/offlinai_torch/__init__.py`.
Precompile your PyTorch model on a desktop, ship the `.pte` with the app,
and call `offlinai_torch.Module("...").forward(numpy_array)` from Python.
Covers ~95% of "I need torch in the app" use cases at a fraction of the
integration cost.

This `torch_ios/` effort exists for the other 5% — research workflows that
need the full training-capable `torch` Python API on-device.
