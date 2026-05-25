# PyTorch — tensors, autograd, neural nets

**Version:** 2.1.0 (patched for iOS arm64)
**Type:** Native iOS — `libtorch_python.dylib` ships at 99 MB via Git LFS
**SPM target:** `Torch`
**Auto-includes:** (none — `torch` is the base)
**Total Python modules:** 200+ (top-level + 40+ subpackages)

First public native PyTorch build for iOS. Tensors, autograd, `nn`, `optim`, JIT scripting, FFT, LAPACK via Apple's Accelerate framework, plus a Metal-Performance-Shaders bridge for GPU-accelerated matmul. Train and fine-tune transformer models on an iPad with zero network. A more category-organised reference is at [docs/libs/pytorch.md](libs/pytorch.md).

## Modules

### Core tensor + autograd (top-level)

| Module | What it does |
|---|---|
| `torch.__init__` | Re-exports `Tensor`, `tensor`, `zeros`/`ones`/`empty`/`arange`/`linspace`, `matmul`, `cat`, `stack`, `save`/`load`, dtype constants, `no_grad`/`enable_grad`/`set_grad_enabled`. **iOS-patched:** force-rebinds `torch._C` after partial-init; `manager_path` tolerates non-executable `torch_shm_manager` placeholder |
| `torch._C` | C-extension backing for tensors + ops (loaded from `_C.so`) |
| `torch._tensor` | Python-side `Tensor` class methods (`backward`, `to`, `view`, `reshape`, `expand`, indexing) |
| `torch.functional` | Functional analogues of `Tensor` methods (`broadcast_tensors`, `einsum`, `meshgrid`, `stft`, `istft`) |
| `torch.serialization` | `torch.save` / `torch.load` (pickle-based, `weights_only=True` for safety) |
| `torch.storage` | `UntypedStorage`, `TypedStorage` — raw byte backing for tensors |
| `torch.overrides` | `__torch_function__` dispatch (used by subclasses to override op behaviour) |
| `torch.types` | Type aliases (`Number`, `Device`, `_dtype`, `_size`) |
| `torch.random` / `torch.quasirandom` | Seeding + Sobol sequences |
| `torch.hub` | `torch.hub.load(...)` — fetch model defs from GitHub repos (needs network) |
| `torch.version` / `torch.torch_version` | Version constants |
| `torch.amp` | Mixed-precision autocast (`torch.amp.autocast`); CPU bf16/fp16 paths work |

### `torch.nn` — neural network building blocks

| Submodule | Provides |
|---|---|
| `nn.modules.module` | `nn.Module` base class (parameter registration, `.to()`, `.state_dict()`) |
| `nn.modules.linear` | `Linear`, `Bilinear`, `Identity`, `LazyLinear` |
| `nn.modules.conv` | `Conv1d`/`2d`/`3d`, `ConvTranspose1d`/`2d`/`3d`, `LazyConv*` |
| `nn.modules.rnn` | `RNN`, `LSTM`, `GRU`, `RNNCell`, `LSTMCell`, `GRUCell` |
| `nn.modules.transformer` | `Transformer`, `TransformerEncoder`/`Decoder`, `MultiheadAttention` |
| `nn.modules.activation` | `ReLU`, `GELU`, `SiLU`, `Sigmoid`, `Tanh`, `Softmax`, `Softplus`, … |
| `nn.modules.batchnorm` / `instancenorm` / `normalization` | `BatchNorm*d`, `InstanceNorm*d`, `LayerNorm`, `GroupNorm`, `RMSNorm` |
| `nn.modules.dropout` | `Dropout`, `Dropout2d`/`3d`, `AlphaDropout` |
| `nn.modules.pooling` | `MaxPool*d`, `AvgPool*d`, `AdaptiveMaxPool*d`, `AdaptiveAvgPool*d` |
| `nn.modules.loss` | `CrossEntropyLoss`, `MSELoss`, `BCELoss`/`BCEWithLogitsLoss`, `NLLLoss`, `KLDivLoss`, … |
| `nn.modules.sparse` | `Embedding`, `EmbeddingBag` |
| `nn.modules.container` | `Sequential`, `ModuleList`, `ModuleDict`, `ParameterList` |
| `nn.modules.padding`/`flatten`/`fold`/`upsampling`/`distance`/`pixelshuffle` | Misc layers |
| `nn.functional` | Stateless versions of every layer (`F.relu`, `F.linear`, `F.scaled_dot_product_attention`, `F.cross_entropy`, …). **Metal-bridge-patched:** `F.linear` routes via GPU for large matmuls |
| `nn.init` | Weight-init schemes (`xavier_uniform_`, `kaiming_normal_`, `orthogonal_`) |
| `nn.parameter` | `Parameter`, `UninitializedParameter` |
| `nn.utils` | `clip_grad_norm_`, `weight_norm`, `spectral_norm`, `prune.*`, `parametrize.*`, `rnn.pack_padded_sequence` |
| `nn.parallel` | `DataParallel`, `DistributedDataParallel` — **not useful on iOS** (single device) |
| `nn.intrinsic` / `nn.qat` / `nn.quantizable` / `nn.quantized` | Quantization-aware-training building blocks |

### `torch.optim` — optimizers + LR schedulers

| Submodule | Provides |
|---|---|
| `optim.sgd` / `adam` / `adamw` / `adamax` / `adadelta` / `adagrad` / `asgd` / `nadam` / `radam` / `rmsprop` / `rprop` / `sparse_adam` / `lbfgs` | One optimizer per file; all importable from `torch.optim.*` |
| `optim.lr_scheduler` | `StepLR`, `MultiStepLR`, `ExponentialLR`, `CosineAnnealingLR`, `OneCycleLR`, `ReduceLROnPlateau`, `ChainedScheduler`, `SequentialLR` |
| `optim.swa_utils` | Stochastic Weight Averaging (`AveragedModel`, `SWALR`, `update_bn`) |
| `optim.optimizer` | `Optimizer` base class |

### `torch.autograd` — automatic differentiation

| Submodule | Provides |
|---|---|
| `autograd.function` | `Function` — base for custom `forward`/`backward` |
| `autograd.functional` | `jacobian`, `hessian`, `vjp`, `jvp`, `hvp`, `vhp` |
| `autograd.grad_mode` | `no_grad`, `enable_grad`, `set_grad_enabled`, `inference_mode` |
| `autograd.gradcheck` | `gradcheck`, `gradgradcheck` (numerical verification) |
| `autograd.profiler` | `profiler.profile()` context manager |
| `autograd.anomaly_mode` | `detect_anomaly` (debug NaN gradients) |
| `autograd.forward_ad` | Forward-mode autodiff (`dual_level`, `make_dual`, `unpack_dual`) |

### `torch.distributions` — probability distributions

`Bernoulli`, `Beta`, `Binomial`, `Categorical`, `Cauchy`, `Chi2`, `Dirichlet`, `Exponential`, `FisherSnedecor`, `Gamma`, `Geometric`, `Gumbel`, `HalfCauchy`, `HalfNormal`, `Independent`, `Kumaraswamy`, `Laplace`, `LKJCholesky`, `LogNormal`, `LogisticNormal`, `LowRankMultivariateNormal`, `MixtureSameFamily`, `Multinomial`, `MultivariateNormal`, `NegativeBinomial`, `Normal`, `OneHotCategorical`, `Pareto`, `Poisson`, `RelaxedBernoulli`, `RelaxedCategorical`, `StudentT`, `TransformedDistribution`, `Uniform`, `VonMises`, `Weibull`, `Wishart`. Plus `transforms.*` (bijectors) and `kl.kl_divergence`.

### `torch.fft` — Fast Fourier Transforms

Single-file module: `fft`, `ifft`, `fft2`, `ifft2`, `fftn`, `ifftn`, `rfft`, `irfft`, `rfft2`, `irfft2`, `rfftn`, `irfftn`, `hfft`, `ihfft`, `fftshift`, `ifftshift`, `fftfreq`, `rfftfreq`. **Accelerate-backed** on iOS.

### `torch.linalg` — linear algebra

Single-file module: `solve`, `inv`, `pinv`, `qr`, `svd`, `svdvals`, `eig`, `eigh`, `eigvals`, `eigvalsh`, `cholesky`, `cholesky_ex`, `lu`, `lu_factor`, `lu_solve`, `det`, `slogdet`, `matrix_rank`, `matrix_norm`, `vector_norm`, `norm`, `cross`, `matrix_power`, `matrix_exp`, `tensorsolve`, `tensorinv`. **Accelerate-LAPACK-backed**.

### `torch.special` — special math functions

`erf`, `erfc`, `erfinv`, `expm1`, `gammaln`, `digamma`, `polygamma`, `i0`, `i0e`, `i1`, `i1e`, `xlogy`, `entr`, `logit`, `expit`, `multigammaln`, `zeta`, `bessel_*`.

### `torch.jit` — TorchScript

| Submodule | Provides |
|---|---|
| `jit._script` | `script`, `ScriptModule`, `ScriptFunction` |
| `jit._trace` | `trace`, `trace_module`, `TracerWarning` |
| `jit._freeze` | `freeze`, `optimize_for_inference` |
| `jit._serialization` | `save`, `load` for `.pt` script archives |
| `jit.mobile` | Mobile-optimized bytecode export |
| `jit._async` / `_await` | `fork`/`wait`/`async` primitives |
| `jit.frontend` | Python-to-IR translator |
| `jit._fuser` | Op fusion passes |

iOS: script + trace **work**; on-device JIT codegen does **not** (no Triton, no runtime C compiler).

### `torch.utils` — runtime utilities

| Submodule | Provides |
|---|---|
| `utils.data` | `Dataset`, `IterableDataset`, `DataLoader`, `Sampler`, `RandomSampler`, `SequentialSampler`, `BatchSampler`, `WeightedRandomSampler`, `random_split`, `Subset`, `ConcatDataset`. **iOS:** `DataLoader(num_workers>0)` doesn't work (no `fork()`); use `num_workers=0` |
| `utils.checkpoint` | `checkpoint`, `checkpoint_sequential` (activation checkpointing for memory savings) |
| `utils.cpp_extension` | `load`, `load_inline` — **iOS-broken** (no on-device compiler) |
| `utils.dlpack` | `to_dlpack`, `from_dlpack` (zero-copy tensor exchange with NumPy / JAX / CuPy) |
| `utils.tensorboard` | `SummaryWriter` — file output works; no UI |
| `utils.bottleneck` | `python -m torch.utils.bottleneck` profiler entry |
| `utils.flop_counter` | `FlopCounterMode` context manager |
| `utils.mkldnn` | MKL-DNN conversion (no-op on iOS) |
| `utils.mobile_optimizer` | `optimize_for_mobile` |
| `utils.collect_env` | `python -m torch.utils.collect_env` env dump |
| `utils.hooks` | `RemovableHandle` for forward/backward hooks |
| `utils.weak` | `WeakIdKeyDictionary`, `WeakIdRef` |
| `utils.benchmark` | `Timer`, `Compare` — microbenchmarking helpers |

### `torch.backends` — device backends

| Submodule | iOS status |
|---|---|
| `backends.cpu` | Active backend on iOS |
| `backends.mps` | **Not bundled.** Metal compute is wired via the `_torch_metal_bridge` shim instead |
| `backends.cuda` / `cudnn` | Not applicable (no GPU on this build) |
| `backends.mkl` / `mkldnn` / `openmp` / `opt_einsum` / `quantized` / `xeon` / `xnnpack` | Present; mostly no-ops or fall back to Accelerate |
| `backends._coreml` / `_nnapi` | iOS export targets (CoreML works for inference) |

### Compiler + lazy stack — **iOS no-op territory**

| Submodule | What it would do | iOS reality |
|---|---|---|
| `torch.compile` (in `_dynamo` + `_inductor`) | TorchDynamo + Triton JIT compilation | Falls back to eager (no Triton, no JIT) |
| `torch._dynamo` | Graph capture | Imports OK, but `compile` is a no-op |
| `torch._inductor` | TorchInductor codegen | Imports OK; runtime usage errors |
| `torch._functorch` / `torch.func` | `vmap`, `grad`, `jacrev`, `jacfwd`, `hessian`, `functional_call` | Most work in eager |
| `torch._lazy` | Lazy tensor backend | Not used on iOS |
| `torch._export` / `torch.export` | Graph export for AOT | Works for inspection |

### Distributed / multi-process — **iOS-blocked**

`torch.distributed` (all-reduce, broadcasts, FSDP, RPC), `torch.multiprocessing`, `torch.distributed.checkpoint`, `torch.distributed.elastic`, `torch.distributed.fsdp`, `torch.distributed.pipeline`, `torch.distributed.tensor` — present in the tree for import compatibility but **none work** (iOS forbids `fork()`).

### Sparse + quantization

| Submodule | What it does |
|---|---|
| `torch.sparse` | `sparse_coo_tensor`, `sparse_csr_tensor`, sparse mat ops |
| `torch.quantization` / `torch.ao` | Post-training + QAT quantization (`quantize_dynamic`, `prepare_qat`, `convert`) |
| `torch.nested` | Nested (ragged) tensors |
| `torch.masked` | MaskedTensor (NaN-safe ops) |

### Graph + IR + export

| Submodule | What it does |
|---|---|
| `torch.fx` | Symbolic tracing + graph rewriting (`symbolic_trace`, `GraphModule`, `Transformer`) |
| `torch.onnx` | ONNX export (`torch.onnx.export`) — works on iOS |
| `torch.package` | Self-contained model archives (`PackageExporter`, `PackageImporter`) |
| `torch.profiler` | `torch.profiler.profile()` context manager — Chrome-trace export works |

### Misc / specialty

`torch.contrib`, `torch.testing`, `torch.signal` (DSP), `torch.cpu`, `torch.cuda` (stubbed — present so dependent code that probes feature flags doesn't crash; nothing actually runs), `torch.mps` (placeholder, see Metal bridge), `torch.legacy`.

## iOS-specific patches

| Patch site | Why |
|---|---|
| `torch/__init__.py` lines ~237-246 | Force-rebind `torch._C` after `from torch._C import *` — iOS embedded Python's partial-init doesn't allow `PyInit__C` to set the attribute itself |
| `torch/__init__.py` lines ~1326-1347 | Tolerate non-executable `torch_shm_manager` placeholder (App Store rejects standalone Mach-O binaries in `app_packages/`); swallow `prepare_multiprocessing_environment` errors |
| `torch/serialization.py` | None — works as-is |
| `torch.from_numpy` / `Tensor.numpy()` | Built with `USE_NUMPY=0`. **Auto-patched in `sitecustomize.py`** with pure-Python `torch.frombuffer`-based equivalents (copy, not zero-copy) |
| `torch.matmul`, `F.linear`, `F.scaled_dot_product_attention` | **Wrapped by `_torch_metal_bridge.install()`** to route large 2-D and batched matmuls through MPS for fp32/fp16/bf16. Threshold gated by `CODEBENCH_GPU_MATMUL_MIN_FLOPS` |
| `torch/bin/torch_shm_manager` | Replaced with text placeholder (App Store ban on standalone executables) |

The Metal bridge implementation lives in `app_packages/site-packages/_torch_metal_bridge.py`.

## Standalone example

```python
import torch
import torch.nn as nn
import torch.nn.functional as F

# Basic tensor ops — matmul auto-routes through Metal for large shapes
x = torch.randn(1024, 1024)
y = torch.randn(1024, 1024)
z = x @ y                              # GPU-accelerated on iPad

# Autograd
w = torch.randn(3, requires_grad=True)
loss = (w * torch.randn(3)).sum() ** 2
loss.backward()

# nn module + optimizer
class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(10, 32)
        self.fc2 = nn.Linear(32, 1)
    def forward(self, x):
        return self.fc2(F.relu(self.fc1(x)))

model = MLP()
opt = torch.optim.AdamW(model.parameters(), lr=1e-3)

for _ in range(100):
    x = torch.randn(64, 10)
    y = (x.sum(1, keepdim=True) > 0).float()
    loss = F.binary_cross_entropy_with_logits(model(x), y)
    opt.zero_grad(); loss.backward(); opt.step()

# Save / load
torch.save(model.state_dict(), "/tmp/mlp.pt")
state = torch.load("/tmp/mlp.pt", weights_only=True)
model.load_state_dict(state)
```

## iOS notes

- **CUDA / ROCm / XLA / MPS-as-backend: not available.** Compute runs on CPU+Accelerate, with matmul fast-path through Metal via the bridge shim.
- **`torch.compile`** silently falls back to eager (no Triton, no on-device JIT).
- **`DataLoader(num_workers>0)`** doesn't work (no `fork`). Set `num_workers=0` and iterate in the main thread.
- **`torch.distributed`** and **`torch.multiprocessing`** import fine but fail at runtime.
- **`libtorch_python.dylib` is 99 MB** — ships via Git LFS. Without `git lfs install`, the dylib arrives as a 134-byte pointer file and `import torch` crashes at load.
- **`torch.from_numpy` / `tensor.numpy()`** are auto-patched in `sitecustomize.py`. Both copy (not zero-copy).
- **`bitsandbytes`, `flash-attn`, `xformers`**: CUDA-only — skip; the Metal bridge handles attention via SDPA.
- **Soft memory ceiling: ~3 GB working set**. iOS jetsam kills the app around ~60% of physical RAM. Print `psutil.Process().memory_info().rss / 1024**2` during heavy work.

## Pairing with the HF stack

```python
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

tok = AutoTokenizer.from_pretrained("path/to/Qwen2.5-1.5B")
model = AutoModelForCausalLM.from_pretrained(
    "path/to/Qwen2.5-1.5B",
    torch_dtype=torch.float16,
)
ids = tok("Once upon a time,", return_tensors="pt").input_ids
out = model.generate(ids, max_new_tokens=50)
print(tok.decode(out[0]))
```

For weight I/O the pure-Python `safetensors` shim handles both read and write — see [safetensors.md](safetensors.md).

## See also

- [docs/libs/pytorch.md](libs/pytorch.md) — category-organised reference
- [docs/transformers.md](transformers.md) / [docs/tokenizers.md](tokenizers.md)
- [docs/safetensors.md](safetensors.md) — weight I/O
- [docs/huggingface-hub.md](huggingface-hub.md) — model download
