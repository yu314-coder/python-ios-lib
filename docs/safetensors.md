# safetensors — safe tensor serialization

**Version:** 0.4.5
**Type:** Pure-Python shim (real package is Rust + PyO3 — not cross-compiled for iOS)
**SPM target:** `Safetensors`
**Auto-includes:** (none)
**Total Python modules:** 2 (`safetensors`, `safetensors.torch`)

HuggingFace's safe alternative to `torch.save` / `pickle.load` for storing tensors. The format is a small JSON header (file offsets + shapes + dtypes) followed by raw binary tensor data — fast to load, and SAFE because reading a `.safetensors` file can never execute arbitrary Python (unlike pickle).

The iOS build is a **fully working pure-Python re-implementation** of the on-disk format. Both read AND write work; `model.save_pretrained()` produces valid `.safetensors` files. The Rust-only `framework="tf"` / `"flax"` / `"mlx"` paths are absent because those backends aren't bundled.

## Modules

| Module | What it does |
|---|---|
| `safetensors.__init__` | The shim itself. Exports `safe_open` (`_SafeOpen` context manager wrapping `mmap`), `load_file(path)`, `save_file(tensors, path, metadata=None)`, `save(tensors, metadata=None) -> bytes`, `SafetensorError`. Dtype map covers F32/F16/BF16/F64, I8/I16/I32/I64, U8/U16/U32/U64, BOOL |
| `safetensors.torch` | `storage_ptr(tensor)` + `storage_size(tensor)` (lifted from upstream so `transformers.pytorch_utils` tied-weight detection works); re-exports `load_file` / `save_file` / `safe_open` / `save` from the parent module; adds `load(bytes) -> dict` (in-memory variant) |

Other Rust-only entrypoints (`safetensors.numpy`, `safetensors.flax`, `safetensors.tensorflow`, `safetensors.mlx`) are **not present** in this shim — but the pure-Python `safe_open(..., framework="numpy")` path works when NumPy is bundled.

## On-disk format (handled by the shim)

```
[8 bytes  : little-endian u64 — JSON header length N]
[N bytes  : UTF-8 JSON describing each tensor: dtype/shape/data_offsets]
[rest     : raw tensor bytes, sliced per JSON's data_offsets]
```

The shim `mmap`s the file so loading a multi-GB model doesn't double-copy into RAM. The writer pads the header to 8-byte alignment, matching the Rust upstream.

## What works on iOS

- **Reading** any `.safetensors` file (mmap-backed, zero-copy slice into bytes; one copy to detach from buffer lifetime)
- **Writing** any `{str: torch.Tensor}` dict via `save_file` or `save`
- **Format inspection** — `safe_open(...).metadata()`, `.keys()`, `.get_tensor()`, `.get_slice()`
- **Dtypes**: F32, F16, BF16 (via int16 view dance), F64, I8/I16/I32/I64, U8/U16/U32/U64 (signed-widening dance), BOOL
- **`framework="pt"`** (PyTorch) — primary path, uses `torch.frombuffer` (PyTorch was built with `USE_NUMPY=0`, so `torch.from_numpy` isn't an option)
- **`framework="numpy"`** — works when numpy is bundled (it is, in this distribution)
- **`HF transformers` model loading** — `from_pretrained(...)` reads `.safetensors` via this shim transparently
- **`HF transformers` model saving** — `model.save_pretrained(...)` writes `.safetensors` via this shim

## What's NOT in the shim

- `framework="tf"` / `"flax"` / `"mlx"` (those backends aren't bundled)
- The Rust `safetensors_rust` extension itself (would require an iOS Rust cross-compile)
- Lazy `get_slice(name)[...]` indexing — the shim materialises the full tensor and indexes Python-side (slower but correct)
- Zero-copy from-mmap `torch.Tensor` (the shim always copies once into a torch-managed buffer)

## Standalone example

```python
# READ — peek at metadata + tensor headers without loading data
from safetensors import safe_open

with safe_open("/path/Documents/model.safetensors", framework="pt") as f:
    print(f.metadata())                  # {'format': 'pt', ...}
    for key in f.keys():
        t = f.get_tensor(key)            # torch.Tensor
        print(f"  {key}: {tuple(t.shape)} {t.dtype}")
```

```python
# WRITE — save a torch state dict
import torch
from safetensors.torch import save_file, load_file

state = {
    "encoder.weight": torch.randn(512, 256, dtype=torch.float16),
    "encoder.bias":   torch.zeros(512,    dtype=torch.float16),
}
save_file(state, "/path/Documents/model.safetensors",
          metadata={"format": "pt", "version": "1"})

# READ — round trip
loaded = load_file("/path/Documents/model.safetensors")
print(loaded["encoder.weight"].shape, loaded["encoder.weight"].dtype)
```

```python
# In-memory variant — useful if you want to mmap or stream the bytes
from safetensors.torch import save, load

blob = save(state)                       # bytes
parsed = load(blob)                      # back to dict (writes a tmp file internally)
```

## Pairing with transformers

```python
from transformers import AutoModel
# from_pretrained reads .safetensors files via this shim transparently:
model = AutoModel.from_pretrained("/path/Documents/models/distilbert")

# save_pretrained writes .safetensors via this shim:
model.save_pretrained("/path/Documents/models/distilbert-finetuned")
# Produces config.json + model.safetensors (+ pytorch_model.bin if requested)
```

## Why safetensors over `torch.save` / `pickle`

| Concern | safetensors | torch.save (pickle) |
|---|---|---|
| Arbitrary code exec on load | impossible | possible (mitigate with `weights_only=True`) |
| Format readable by other frameworks | yes (TF, JAX, NumPy can all read .pt-tagged files) | no (pickle is Python-specific) |
| Memory-mapped lazy loading | yes (slice access) | no (loads everything) |
| File size | identical (raw float bytes) | slightly larger (pickle overhead per tensor) |
| Speed (load) | ~30% faster (no unpickling) | slower |
| Compatibility | new (introduced 2023) | universal in PyTorch ecosystem |

## iOS-specific notes

- **bf16 special case**: torch's `frombuffer` can't read directly into a bfloat16 view, so the shim reads as `int16` then `.view(torch.bfloat16)` then `.clone()`. Round-trip-equivalent, just a one-time copy.
- **Unsigned >8-bit dtypes**: torch lacks native `uint16`/`uint32`/`uint64`, so the shim widens to the same-byte-width signed type. Same bit pattern preserved on read; transformers doesn't use these dtypes.
- **No streaming write** — must hold the full state dict in memory at save time. For models > a few GB, save as multiple shards (`huggingface_hub.serialization.split_state_dict_into_shards_factory`).
- **mmap on memory-pressured devices** — multi-GB mmaps occasionally fail with `ENOMEM`. ~2 GB files are fine; if you hit issues, split into shards.
- **`safetensors.torch.load_file` / `save_file` work fine on iOS** — earlier docs noted these were shimmed off; that's no longer the case. The pure-Python writer was added.

## See also

- [docs/torch.md](torch.md) — PyTorch; `torch.frombuffer` is the load path
- [docs/transformers.md](transformers.md) — `from_pretrained` / `save_pretrained` route through here
- [docs/huggingface-hub.md](huggingface-hub.md) — downloads `.safetensors` files
