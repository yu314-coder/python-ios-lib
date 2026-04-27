# PyTorch

> **Version:** 2.1.2 (patched for iOS arm64) | **Type:** Native iOS — `libtorch_python.dylib` ships at 99 MB via Git LFS  | **Status:** Working — full `import torch` (95/95 correctness asserts on real device)

First public native PyTorch build for iOS. Tensors, autograd, `nn`,
`optim`, JIT scripting, FFT, LAPACK via Apple's Accelerate framework.
Train and fine-tune transformer models on an iPad with zero network.

A more category-organised reference is at [docs/libs/pytorch.md](libs/pytorch.md).
This page is the standalone API+iOS-notes summary.

---

## Quick start

```python
import torch

# Basic tensor ops
x = torch.tensor([[1.0, 2.0], [3.0, 4.0]])
y = torch.eye(2)
print(x @ y)              # tensor([[1., 2.], [3., 4.]])

# Autograd
w = torch.randn(3, requires_grad=True)
x = torch.randn(3)
loss = (w * x).sum() ** 2
loss.backward()
print(w.grad)              # 2 * x * (w*x).sum()

# nn module
import torch.nn as nn
import torch.nn.functional as F

class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(10, 32)
        self.fc2 = nn.Linear(32, 1)
    def forward(self, x):
        return self.fc2(F.relu(self.fc1(x)))

model = MLP()
opt = torch.optim.Adam(model.parameters(), lr=1e-3)

# Training loop
for step in range(100):
    x = torch.randn(64, 10)
    y = (x.sum(1, keepdim=True) > 0).float()
    pred = model(x)
    loss = F.binary_cross_entropy_with_logits(pred, y)
    opt.zero_grad()
    loss.backward()
    opt.step()
```

---

## What works

- **Tensor algebra** — full upstream API; on Float64/Float32/Float16 with
  Accelerate-backed BLAS for matmul (significantly faster than reference)
- **Autograd** — `requires_grad`, `backward()`, `torch.no_grad()`,
  custom autograd Functions, double backward
- **`torch.nn`** — `Linear`, `Conv1d/2d/3d`, `LSTM`/`GRU`/`Transformer`,
  `Embedding`, `LayerNorm`, `BatchNorm*d`, all activation funcs,
  loss functions
- **`torch.optim`** — SGD, Adam, AdamW, RMSprop, Adagrad, etc.
- **`torch.fft`** — 1D / 2D / 3D real + complex FFT (Accelerate-backed)
- **`torch.linalg`** — `solve`, `inv`, `qr`, `svd`, `eigh`, `cholesky`,
  `pinv`, `det`, `slogdet`
- **`torch.jit.script` / `torch.jit.trace`** — script and trace
  transformations both work; the saved `.pt` files load cross-platform
- **`torch.save` / `torch.load`** — pickle-based; pass `weights_only=True`
  for safety
- **`torch.compile`** — DOES NOT work on iOS (no Triton / no on-device
  C compiler) — falls back to eager; documented in
  [docs/libs/pytorch.md#torchcompile](libs/pytorch.md#torchcompile)

---

## iOS-specific notes

- **`libtorch_python.dylib` is 99 MB** — ships via Git LFS. If you
  clone the repo without git-lfs installed, the dylib arrives as a
  134-byte pointer file and `import torch` crashes at load.
  ```bash
  brew install git-lfs && git lfs install
  git clone https://github.com/yu314-coder/python-ios-lib   # then
  ```
- **CUDA / ROCm / XLA: not available.** All compute on CPU + Apple's
  Accelerate (vectorized SIMD).
- **MPS (Metal Performance Shaders) backend: not bundled** — would
  need separate work to wire up `torch.backends.mps`. CPU is the
  default and only device.
- **`subprocess`-based dataloaders (`num_workers > 0`)**: don't work
  (no fork on iOS). Use `num_workers=0` (single-process data loading);
  iterate datasets in the main thread.
- **`torch.distributed`**: not available — multi-process training
  needs fork.
- **No CUDA-only ops** (e.g. `torch.cuda.amp.autocast`) — but their CPU
  equivalents (`torch.amp.autocast(device_type="cpu", dtype=torch.bfloat16)`)
  do work for inference acceleration.

---

## Pairing with safetensors / transformers

```python
# Load a HuggingFace model bundled in the app
from transformers import AutoTokenizer, AutoModelForCausalLM

tok = AutoTokenizer.from_pretrained("path/to/Qwen2.5-1.5B")
model = AutoModelForCausalLM.from_pretrained(
    "path/to/Qwen2.5-1.5B",
    torch_dtype=torch.float16,    # half-precision saves memory
)

ids = tok("Once upon a time,", return_tensors="pt").input_ids
out = model.generate(ids, max_new_tokens=50)
print(tok.decode(out[0]))
```

For weight I/O, prefer `safetensors` via the NumPy roundtrip (see
[safetensors.md](safetensors.md)) — `safetensors.torch.load_file` is
shimmed off on iOS.

---

## Performance tips

- **`torch.set_num_threads(N)`** — defaults to # of cores. Lower if
  your app's UI is sharing the CPU.
- **`torch.set_default_dtype(torch.float16)`** — halves memory for
  inference on big models. Combined with `model.half()`, recovers a
  lot of headroom on memory-tight devices.
- **`torch.no_grad()`** for inference — saves memory + a small
  amount of compute by not building the autograd graph.
- **Pre-allocate big buffers** — avoid `torch.cat` in tight loops;
  it allocates a new tensor each call.
- **Watch RSS** — iOS jetsam kills the app at ~60% of physical RAM.
  Print `psutil.Process().memory_info().rss / 1024**2` regularly
  during heavy training.

---

## Test coverage

**95/95 correctness asserts** pass on real iOS devices, covering:

- Tensor creation + dtype conversion (15 asserts)
- Arithmetic + broadcasting (12 asserts)
- LinAlg via Accelerate (10 asserts)
- Autograd correctness (10 asserts)
- `nn` modules forward/backward (15 asserts)
- Optimizer step deltas (8 asserts)
- JIT script / trace round-trip (10 asserts)
- Save / load pickle (5 asserts)
- FFT real + complex 1D/2D (10 asserts)

See `app_packages/site-packages/test_torch.py` (or run
`python torch_test_all.py` from the in-app shell).

---

## Limitations

- No CUDA / ROCm / XLA / MPS backend
- No multi-process distributed training
- `torch.compile` falls back to eager (no on-device JIT compiler)
- `torch.utils.data.DataLoader(num_workers=>0)` doesn't work
- Model size soft cap: ~3 GB working set is comfortable; 6+ GB risks
  jetsam on memory-tight devices
- No CUDA-streaming — all `.to(device)` is a no-op (already on CPU)

## See also

- [docs/libs/pytorch.md](libs/pytorch.md) — category-organised reference
- [docs/transformers.md](transformers.md) / [docs/tokenizers.md](tokenizers.md)
- [docs/safetensors.md](safetensors.md) — safe weight I/O
- [docs/huggingface-hub.md](huggingface-hub.md) — model download
