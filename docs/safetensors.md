# safetensors

> **Version:** 0.4.5  | **Type:** Pure-Python frontend + native Rust backend (NumPy / TF / Flax I/O works; **PyTorch I/O is shimmed to NotImplementedError on iOS** — see iOS Notes)  | **Status:** Partial

Hugging Face's safe alternative to `torch.save` / `pickle.load` for
storing tensors. The format is a small JSON header (file offsets +
shapes + dtypes) followed by raw binary tensor data — fast to load,
and SAFE because reading a `.safetensors` file can never execute
arbitrary Python (unlike pickle).

---

## Quick start (NumPy)

```python
import numpy as np
from safetensors.numpy import save_file, load_file

# Save
arrays = {
    "weights": np.random.randn(1024, 1024).astype(np.float32),
    "bias":    np.zeros(1024, dtype=np.float32),
}
save_file(arrays, "/path/Documents/model.safetensors")

# Load
loaded = load_file("/path/Documents/model.safetensors")
print(loaded["weights"].shape)   # (1024, 1024)
print(loaded["bias"].dtype)      # float32
```

```python
# Inspect without loading data — peek at metadata + tensor headers
from safetensors import safe_open

with safe_open("/path/model.safetensors", framework="np") as f:
    print(f.metadata())               # {'format': 'pt', 'date': '2024-...'}
    for key in f.keys():
        t = f.get_tensor(key)
        print(f"  {key}: {t.shape} {t.dtype}")
```

---

## PyTorch I/O — IMPORTANT iOS NOTE

The `safetensors.torch` module's `save_file` / `load_file` are
**shimmed to raise `NotImplementedError`** on iOS:

```python
from safetensors.torch import save_file
save_file({"x": torch.zeros(3)}, "/path/x.safetensors")
# → NotImplementedError: safetensors.torch: torch_ios shim does not
#   implement .safetensors I/O. Construct models from config, or
#   save/load via torch.save/torch.load instead.
```

**Why**: the `torch_ios` shim in this distribution doesn't implement
the dlpack / `__cuda_array_interface__` paths that
`safetensors.torch._safe_open` uses to wrap raw bytes as torch
tensors without copying. We could implement them, but the iOS torch
build is already memory-tight and the workaround is simple:

### Workaround 1 — go through NumPy

```python
import numpy as np, torch
from safetensors.numpy import save_file, load_file

# Save
state = {k: v.detach().cpu().numpy() for k, v in model.state_dict().items()}
save_file(state, "/path/model.safetensors")

# Load
np_state = load_file("/path/model.safetensors")
model.load_state_dict({k: torch.from_numpy(v) for k, v in np_state.items()})
```

### Workaround 2 — use torch.save / torch.load

```python
torch.save(model.state_dict(), "/path/model.pt")          # pickle-based
state = torch.load("/path/model.pt", weights_only=True)   # 2.x has weights_only=True for safety
model.load_state_dict(state)
```

The NumPy roundtrip is the SAFER option (no pickle, smaller iOS attack
surface). Use it when you want safetensors-on-disk benefits with
torch-in-memory operation.

---

## What works on iOS (regardless of backend)

- **Format inspection** — `safe_open(...).metadata()`, `.keys()`,
  `.get_tensor()` all work for any framework's safetensors files
- **NumPy I/O** — full roundtrip
- **Tensorflow / Flax I/O** — would work if TF/Flax were bundled
  (they're not in this build)
- **Reading HF model files** — `transformers` reads safetensors-format
  weights via the NumPy path internally on iOS, so loading
  pre-trained models works fine

What doesn't work:

- **Direct `safetensors.torch.save_file` / `load_file`** — workaround
  above

---

## API surface

### Module entrypoints

| Module | Purpose |
|---|---|
| `safetensors.numpy` | save_file / load_file with `np.ndarray` values |
| `safetensors.torch` | save_file / load_file with `torch.Tensor` values — **iOS shim raises NotImplementedError** |
| `safetensors.flax` | Flax (JAX-based) — not used on iOS |
| `safetensors.tensorflow` | TF — not used on iOS |
| `safetensors` (top-level) | low-level `safe_open`, `serialize`, `deserialize` |

### `safe_open(path, framework, device=None)` returns a context manager:

| Method | Returns |
|---|---|
| `f.keys()` | list of tensor names |
| `f.metadata()` | dict of file-level metadata (typically format + date) |
| `f.get_tensor(name)` | the tensor as a `np.ndarray` / `torch.Tensor` / etc. |
| `f.get_slice(name)` | lazy slice handle — `s = f.get_slice("w"); s[:, :100]` |

`framework=` accepts `"pt"` (torch), `"tf"`, `"flax"`, `"numpy"`,
`"mlx"`. `"numpy"` is always available; others depend on what's
installed.

---

## Why use safetensors over `torch.save` / `pickle`

| Concern | safetensors | torch.save (pickle) |
|---|---|---|
| Arbitrary code exec on load | impossible | possible (requires careful `weights_only=True` + trust check) |
| Format readable by other frameworks | yes (TF, JAX, NumPy can all read .pt-tagged files) | no (pickle is Python-specific) |
| Memory-mapped lazy loading | yes (slice access) | no (loads everything) |
| File size | identical (raw float bytes) | slightly larger (pickle overhead per tensor) |
| Speed (load) | ~30% faster (no unpickling) | slower |
| Compatibility | new (introduced 2023) | universal in PyTorch ecosystem |

For new code: use safetensors via the NumPy roundtrip.
For loading existing `.pt` files: use `torch.load(... weights_only=True)`.

---

## Limitations

- **`safetensors.torch` write/read** — see iOS Notes above
- **No bf16 / fp8 zero-copy** — even with the NumPy backend, casting
  through NumPy upcasts these to fp32; for inference-time fp8 weights
  you'd lose half the storage savings
- **Memory-mapped lazy loading** — works for NumPy backend but
  iOS may cap mmap size on big files (~2 GB is fine; multi-GB
  mmaps occasionally fail with `ENOMEM` on memory-pressured devices)
- **No streaming write** — must hold the full state dict in memory at
  save time. For models > a few GB, save in chunks via multiple files

---

## See also

- [pytorch.md](libs/pytorch.md) — torch + the iOS shim's surface
- [transformers.md](libs/transformers.md) — model loading uses
  safetensors transparently when available
