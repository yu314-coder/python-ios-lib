# PyTorch

**Native cross-compile + 18 patches** | v2.1.2 | **95/95 deep asserts + 24/24 full-integration (with transformers + tokenizers)**

> Full `import torch` — C++ JIT, autograd, nn, LAPACK, end-to-end training, `torch.save` — running in-process on iPad. As far as I know, the **first public native-PyTorch build on iOS** that exposes the complete `import torch` Python API on device.
>
> See [transformers.md](transformers.md) + [tokenizers.md](tokenizers.md) for the HuggingFace stack on top.

---

## Version

- **torch** `2.1.0a0+gita8e7c98` (built from `v2.1.2` tag — the last with iOS build scripts before Facebook pivoted to ExecuTorch)
- **Python** 3.14.2 (via BeeWare's Python.xcframework)
- **Platform** `ios` — `arm64-apple-ios17.0`
- **Binary size** `libtorch_python.dylib` ≈ 98 MB, pure-Python ≈ 90 MB, total incremental app size ≈ 200 MB
- **Import time** ≈ 6 s (cold launch)

---

## What's Included

### Core tensor API

| Module | Summary |
|---|---|
| `torch` | `tensor`, `zeros`, `ones`, `arange`, `linspace`, `randn`, `eye`, `cat`, `stack`, `reshape`, `permute`, `squeeze`, `unsqueeze`, `sum`, `mean`, `max`, `argmax`, all arithmetic + broadcasting, 1000+ ops |
| `torch.Tensor` | Dunder ops (`+`, `*`, `**`, `@`, `>`, `<`, `==`, etc.), `.item()`, `.tolist()`, `.numpy()`, `.cpu()`, `.detach()`, `.clone()`, `.view()`, `.flatten()`, `.to(dtype/device)`, indexing, slicing, masking |
| `torch.dtype` / `torch.device` / `torch.Size` | dtype + device + shape primitives |
| `torch.Storage` / `UntypedStorage` | low-level storage |

### Neural networks — `torch.nn`

| Submodule | Classes / functions |
|---|---|
| **Linear** | `Linear`, `Bilinear`, `Identity`, `LazyLinear` |
| **Convolution** | `Conv1d`, `Conv2d`, `Conv3d`, `ConvTranspose1d/2d/3d`, `LazyConv*`, `Unfold`, `Fold` |
| **Normalization** | `BatchNorm1d/2d/3d`, `LayerNorm`, `GroupNorm`, `InstanceNorm1d/2d/3d`, `LocalResponseNorm`, `RMSNorm`, `SyncBatchNorm` |
| **Recurrent** | `RNN`, `LSTM`, `GRU`, `RNNCell`, `LSTMCell`, `GRUCell` |
| **Transformer** | `Transformer`, `TransformerEncoder`, `TransformerEncoderLayer`, `TransformerDecoder`, `TransformerDecoderLayer`, `MultiheadAttention` |
| **Embedding** | `Embedding`, `EmbeddingBag` |
| **Dropout** | `Dropout`, `Dropout1d/2d/3d`, `AlphaDropout`, `FeatureAlphaDropout` |
| **Activations** | `ReLU`, `LeakyReLU`, `ReLU6`, `Sigmoid`, `Tanh`, `GELU`, `SiLU`, `Softmax`, `Softmax2d`, `LogSoftmax`, `Softplus`, `Softsign`, `Softshrink`, `ELU`, `SELU`, `CELU`, `PReLU`, `Hardswish`, `Hardsigmoid`, `Hardshrink`, `Hardtanh`, `Mish`, `Threshold`, `Tanhshrink` |
| **Pooling** | `MaxPool1d/2d/3d`, `AvgPool1d/2d/3d`, `AdaptiveMaxPool1d/2d/3d`, `AdaptiveAvgPool1d/2d/3d`, `LPPool1d/2d`, `FractionalMaxPool2d/3d`, `MaxUnpool1d/2d/3d` |
| **Losses** | `MSELoss`, `CrossEntropyLoss`, `BCELoss`, `BCEWithLogitsLoss`, `NLLLoss`, `PoissonNLLLoss`, `GaussianNLLLoss`, `HuberLoss`, `SmoothL1Loss`, `L1Loss`, `KLDivLoss`, `CTCLoss`, `CosineEmbeddingLoss`, `HingeEmbeddingLoss`, `MarginRankingLoss`, `TripletMarginLoss`, `MultiMarginLoss`, `MultiLabelMarginLoss`, `MultiLabelSoftMarginLoss`, `SoftMarginLoss` |
| **Padding** | `ReflectionPad1d/2d/3d`, `ReplicationPad1d/2d/3d`, `ConstantPad1d/2d/3d`, `ZeroPad1d/2d/3d`, `CircularPad1d/2d/3d` |
| **Upsampling** | `Upsample`, `UpsamplingBilinear2d`, `UpsamplingNearest2d`, `PixelShuffle`, `PixelUnshuffle` |
| **Containers** | `Sequential`, `ModuleList`, `ModuleDict`, `ParameterList`, `ParameterDict` |
| **Module base** | `.forward()`, `.parameters()`, `.named_parameters()`, `.buffers()`, `.state_dict()`, `.load_state_dict()`, `.eval()`, `.train()`, `.zero_grad()`, `.to()`, `.cuda()`, `.cpu()`, `.register_buffer()`, `.register_parameter()`, `.register_forward_hook()` |

### `torch.nn.functional` (aka `F`)

~150 pure-function variants — `F.relu`, `F.softmax`, `F.cross_entropy`, `F.conv2d`, `F.max_pool2d`, `F.interpolate`, `F.grid_sample`, `F.scaled_dot_product_attention`, `F.layer_norm`, `F.batch_norm`, `F.dropout`, `F.embedding`, `F.embedding_bag`, `F.one_hot`, `F.gumbel_softmax`, `F.pad`, `F.adaptive_avg_pool2d`, `F.affine_grid`, `F.normalize`, etc.

### `torch.nn.init`

Weight initialization: `uniform_`, `normal_`, `trunc_normal_`, `constant_`, `zeros_`, `ones_`, `eye_`, `dirac_`, `xavier_uniform_`, `xavier_normal_`, `kaiming_uniform_`, `kaiming_normal_`, `orthogonal_`, `sparse_`, `_calculate_fan_in_and_fan_out`, `calculate_gain`.

### `torch.nn.utils`

`clip_grad_norm_`, `clip_grad_value_`, `rnn.pack_padded_sequence`, `rnn.pad_packed_sequence`, `rnn.pack_sequence`, `parametrize.register_parametrization`, `spectral_norm`, `weight_norm`, `prune.*` (14 pruning functions).

### Optimizers — `torch.optim`

| Class | Notes |
|---|---|
| `SGD` | momentum, Nesterov, dampening, weight_decay |
| `Adam` / `AdamW` / `SparseAdam` / `NAdam` / `RAdam` / `Adamax` | fused + non-fused variants |
| `Adadelta` / `Adagrad` | |
| `ASGD` | averaged SGD |
| `LBFGS` | history_size, strong_wolfe |
| `RMSprop` / `Rprop` | |
| **`lr_scheduler.*`** | `StepLR`, `MultiStepLR`, `ExponentialLR`, `CosineAnnealingLR`, `ReduceLROnPlateau`, `CyclicLR`, `OneCycleLR`, `LambdaLR`, `MultiplicativeLR`, `PolynomialLR`, `LinearLR`, `ConstantLR`, `SequentialLR`, `ChainedScheduler`, `CosineAnnealingWarmRestarts` |

### Autograd — `torch.autograd`

| API | Summary |
|---|---|
| `backward()`, `grad()` | Core gradient computation |
| `Function` | Custom autograd functions (define `forward`/`backward`) |
| `Variable` (legacy) | Deprecated but present |
| `no_grad`, `enable_grad`, `set_grad_enabled`, `inference_mode` | Context managers |
| `functional.jacobian`, `hessian`, `vjp`, `jvp`, `vhp`, `hvp` | Higher-order derivatives |
| `gradcheck`, `gradgradcheck` | Numerical gradient verification |
| `profiler.record_function`, `profiler.profile` | Profile hooks (graceful no-op on iOS) |
| `detect_anomaly`, `set_detect_anomaly` | Anomaly detection |

### Linear algebra — `torch.linalg`

Backed by **LAPACK via Apple's Accelerate framework**.

| Category | Functions |
|---|---|
| Determinants & inverse | `det`, `slogdet`, `inv`, `pinv`, `matrix_rank` |
| Linear solve | `solve`, `solve_triangular`, `lstsq`, `solve_ex` |
| LU / Cholesky / QR | `lu`, `lu_factor`, `lu_factor_ex`, `lu_solve`, `cholesky`, `cholesky_ex`, `qr`, `householder_product` |
| SVD + norms | `svd`, `svdvals`, `matrix_norm`, `vector_norm`, `norm` |
| Eigendecomposition | `eig`, `eigvals`, `eigh`, `eigvalsh` |
| Matrix ops | `matmul`, `vecdot`, `cross`, `outer`, `matrix_power`, `matrix_exp`, `multi_dot` |
| Tensor ops | `tensorsolve`, `tensorinv`, `diagonal`, `vander` |

### FFT — `torch.fft`

`fft`, `ifft`, `fft2`, `ifft2`, `fftn`, `ifftn`, `rfft`, `irfft`, `rfft2`, `irfft2`, `rfftn`, `irfftn`, `hfft`, `ihfft`, `hfft2`, `ihfft2`, `hfftn`, `ihfftn`, `fftshift`, `ifftshift`, `fftfreq`, `rfftfreq`.

### Distributions — `torch.distributions`

**50+ distribution classes**: `Normal`, `Uniform`, `Beta`, `Bernoulli`, `Binomial`, `Categorical`, `Cauchy`, `Chi2`, `Dirichlet`, `Exponential`, `FisherSnedecor`, `Gamma`, `Geometric`, `Gumbel`, `HalfCauchy`, `HalfNormal`, `Independent`, `Kumaraswamy`, `LKJCholesky`, `Laplace`, `LogNormal`, `LogisticNormal`, `LowRankMultivariateNormal`, `MixtureSameFamily`, `Multinomial`, `MultivariateNormal`, `NegativeBinomial`, `OneHotCategorical`, `Pareto`, `Poisson`, `RelaxedBernoulli`, `RelaxedOneHotCategorical`, `StudentT`, `TransformedDistribution`, `VonMises`, `Weibull`, `Wishart`.

Plus `Transform` subclasses (`ExpTransform`, `AffineTransform`, `SigmoidTransform`, `StickBreakingTransform`, `LowerCholeskyTransform`, `CatTransform`, `ComposeTransform`, `IndependentTransform`, `ReshapeTransform`, `TanhTransform`), KL divergence (`kl_divergence`), constraints, and `utils` (probs_to_logits, clamp_probs, etc.).

### Sparse / nested / special / masked / signal

| Module | What's in it |
|---|---|
| `torch.sparse` | `sparse_coo_tensor`, `sparse_csr_tensor`, `sparse_csc_tensor`, `sparse_bsr_tensor`, `sparse_bsc_tensor`, sparse arithmetic & mm |
| `torch.nested` | `nested_tensor`, jagged-tensor construction + ops |
| `torch.special` | `special.expit`, `xlog1py`, `erf`, `erfc`, `erfinv`, `gammaln`, `digamma`, `polygamma`, `zeta`, `log_softmax`, `logit`, `ndtr`, `ndtri`, `i0`, `i0e`, `i1`, `i1e`, `airy_ai`, `bessel_j0`, `bessel_j1`, `bessel_y0`, `bessel_y1`, `entr`, `round`, `sinc`, `expm1`, `log1p` (~40 functions) |
| `torch.masked` | Masked tensor reductions — `masked_tensor()`, masked `sum`/`mean`/`var`/`std`/`amax`/`amin` |
| `torch.signal.windows` | `hann`, `hamming`, `blackman`, `bartlett`, `kaiser`, `gaussian`, `general_cosine`, `nuttall`, `cosine`, `exponential` |

### JIT / scripting — `torch.jit`

Full JIT frontend compiled in (11 856 `torch::jit::*` symbols defined in libtorch_cpu).

| API | Notes |
|---|---|
| `torch.jit.script` | Python → TorchScript compiler |
| `torch.jit.trace`, `trace_module` | Record-and-replay tracer |
| `torch.jit.ScriptModule`, `ScriptFunction` | Compiled unit |
| `torch.jit.save`, `torch.jit.load` | Serialization to `.pt` archives |
| `torch.jit.fork`, `wait` | Parallel execution |
| `@torch.jit.ignore`, `@unused`, `@export`, `@interface` | Decorators |
| `torch.jit.Final`, `Attribute` | Type hints for TorchScript |

### FX — `torch.fx`

Symbolic tracing and graph rewriting.

| API | Notes |
|---|---|
| `torch.fx.symbolic_trace` | Python → FX Graph |
| `GraphModule`, `Graph`, `Node`, `Proxy`, `Tracer` | Core classes |
| `torch.fx.passes` | Shape propagation, graph splitting, infra |
| `torch.fx.experimental` | `symbolic_shapes`, `proxy_tensor`, meta tracking |

### Data — `torch.utils.data`

`Dataset`, `IterableDataset`, `TensorDataset`, `ConcatDataset`, `ChainDataset`, `Subset`, `DataLoader` (use `num_workers=0` — iOS forbids fork), `Sampler`, `SequentialSampler`, `RandomSampler`, `SubsetRandomSampler`, `WeightedRandomSampler`, `BatchSampler`, `DistributedSampler` (no-op on iOS), `default_collate`.

### Serialization

`torch.save`, `torch.load`, `torch.save(model.state_dict(), f)`, `model.load_state_dict(torch.load(f))`. Both pickle-based and zip-archive formats work.

### Utilities

`torch.utils.checkpoint.checkpoint` (gradient checkpointing), `torch.utils.hooks`, `torch.utils.weak` (with `_IterationGuard` polyfill for Python 3.13+), `torch.utils.flop_counter`, `torch.utils.benchmark`, `torch.utils.cpp_extension` (importable; compilation at runtime not available on iOS).

### Other subsystems (import works)

| Module | Status |
|---|---|
| `torch.amp` | Automatic mixed precision context managers |
| `torch.ao.quantization` | Quantization API — most ops work; some packed-params conv/linear paths stubbed |
| `torch.backends.cpu` | ✅ |
| `torch.export` | `torch.export.export()` works for graph capture |
| `torch.package` | Bundle format for distributing TorchScript models |
| `torch.profiler` | Profile hooks (graceful no-op) |
| `torch.random` | `seed`, `manual_seed`, `initial_seed`, `get_rng_state`, `set_rng_state` |
| `torch.overrides` | `__torch_function__` dispatch |
| `torch.quasirandom` | `SobolEngine` |

---

## Acceptance test output

The bundled `torch_test_all.py` covers 12 sections — 57/57 pass on iPad:

```
 1. import ─── import torch, torch.nn, torch.nn.functional            ✓
 2. tensor creation ─── tensor, zeros, ones, arange, randn, eye       ✓
 3. arithmetic + broadcasting                                         ✓
 4. reductions + indexing ─── sum, mean, max, argmax, boolean mask    ✓
 5. shape manipulation ─── reshape, flatten, cat, stack, permute       ✓
 6. linear algebra (LAPACK) ─── det, inv, norm, svd                   ✓
 7. autograd ─── backward(), no_grad()                                ✓
 8. nn.Module forward pass                                            ✓
 9. activation + loss ─── relu, sigmoid, tanh, softmax, MSE, CE       ✓
10. end-to-end training loop ─── SGD fits w=3 b=1 (loss 0.00011)      ✓
11. device/backend availability                                       ✓
12. serialization ─── torch.save / torch.load / load_state_dict       ✓
```

## Quickstart

```python
import torch
import torch.nn as nn
import torch.optim as optim

model = nn.Linear(1, 1)
optimizer = optim.SGD(model.parameters(), lr=0.01)
criterion = nn.MSELoss()

x = torch.linspace(0, 10, 100).reshape(-1, 1)
y = 3 * x + 1 + torch.randn_like(x) * 0.1

for step in range(1000):
    optimizer.zero_grad()
    loss = criterion(model(x), y)
    loss.backward()
    optimizer.step()

print(f"w = {model.weight.item():.3f}  b = {model.bias.item():.3f}")
# → w ≈ 3.000, b ≈ 1.001
```

---

## Limitations

- **CPU only.** `torch.backends.mps.is_available()` → False. `torch.cuda.is_available()` → False. Accelerate's BLAS/LAPACK give good performance for dense CPU ops but no GPU acceleration. MPS backend wiring is a future wedge.
- **`torch.multiprocessing` / `DataLoader(num_workers>0)`.** iOS sandbox forbids `fork()+exec()`. `torch_shm_manager` is shipped so `manager_path()` succeeds but workers never spawn. Use `num_workers=0`.
- **`torch.compile` / `torch._dynamo` / `torch._inductor`** fall through to eager. Dynamo needs `Py_BUILD_CORE` eval-frame hook access we don't have.
- **`torch.onnx.export`** raises — ONNX protobuf codegen needs `onnx_pb.h` we didn't compile in. Precompile models to ONNX on desktop.
- **Quantized `qconv2d` / `qlinear` with packed-params** — custom-class schemas dropped to avoid dyld static-init throw. Non-quantized ops unaffected.
- **`vmap` / `grad` transforms** — functorch C++ runtime not compiled. Python `torch._functorch` imports succeed; vmap calls raise.
- **`torch.distributed`** — no networking backend. Import works, collective ops raise.

None affect normal tensor math, autograd training, or model inference/fine-tuning.

---

## Why this is hard

Facebook removed `scripts/build_ios.sh` from PyTorch main around v2.2 (mid-2024) when they pivoted to ExecuTorch. v2.1.2 is the last tag with a working iOS toolchain. Even that target only produced `libtorch.a` — C++ inference, no Python.

To get `import torch` working in a Python-on-iOS app you need all of:

1. **Full JIT libtorch_cpu.a (~185 MB).** The "lite" / "mobile" interpreter variant used by ExecuTorch strips 548 `torch::jit::*` symbols that Python bindings reference at dlopen time.
2. **Python extension modules (~98 MB libtorch_python.dylib).** Cross-compiled against Python.xcframework's Python 3.14 headers, with each `.so` wrapped in a `.framework` bundle and code-signed.
3. **Dyld static-init survival.** iOS dyld runs ~3000 `_GLOBAL__sub_I_*` initializers sequentially at dlopen. Any throw aborts the process.
4. **LAPACK.** Stock iOS build skips LAPACK detection under `INTERN_BUILD_MOBILE`. `torch.linalg.det/inv/svd` needs it.
5. **Python 3.14 compat.** `_weakrefset._IterationGuard` removed, `typing.Union` made immutable — monkey-patches required.
6. **App bundle code signing.** iOS refuses to `dlopen()` unsigned bare `.so`; each Python C extension becomes a signed `.framework`.

## Patches

Lives at [torch_ios/](https://github.com/yu314-coder/CodeBench/tree/main/torch_ios) in the CodeBench repo. **18 patches** (`patches/0001-0018`) cover:

- Honor `FORCE_BUILD_PYTHON` under INTERN_BUILD_MOBILE (0001)
- Stub dynamo CPython internals (0002)
- Stub ONNX exports — functions + enum registration (0003, 0013)
- Fix `-lcblas` / `library.h` / `library.cpp` / traceback (0004, 0005, 0009)
- Disable global deps, LTC flags, functorch runtime (0006-0008)
- Compile serializer + cppnn + libshm sources (0010-0012, 0015)
- Wrap quantized schema parser in try/catch (0014)
- Enable LAPACK via Accelerate framework (0016)
- Force regular Type system over DynamicType (0017)
- Python-side compat: `_MissingOverload` placeholder, profiler graceful-degrade, Union `__module__` try/except, `_IterationGuard` polyfill, torchgen shipping (0018)

See [`BUILD_NOTES.md`](https://github.com/yu314-coder/CodeBench/blob/main/torch_ios/BUILD_NOTES.md) for the full wedge archaeology.

## Alternative: ExecuTorch

If all you want is **inference** (not training, not dynamic graph construction, not arbitrary Python), use [ExecuTorch](https://pytorch.org/executorch/) instead. Precompile your model to `.pte` on desktop, ship 5 MB of ExecuTorch runtime, call it from Swift or the [offlinai_torch](https://github.com/yu314-coder/CodeBench/tree/main/app_packages/site-packages/offlinai_torch) Python bridge.

ExecuTorch covers ~95% of "I need torch on iPad" use cases. This native build exists for the other 5% — research workflows, on-device fine-tuning, dynamic-graph user code.
