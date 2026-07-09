# datasets — HuggingFace Datasets 4.0.0 (iOS)

Bundled and device-verified for local dataset work. Version **4.0.0** specifically:
5.0.0 hard-fails on the bundled pyarrow 15 (it calls `pa.json_()`, a pyarrow-21
API, at import). 4.0.0 needs only `pyarrow>=15` and runs fine on the bundled
`dill 0.4.1`.

## What works

- `Dataset.from_dict(...)`, `Dataset.from_pandas(...)`, `Dataset.from_list(...)`
- `.map()`, `.filter()`, `.select()`, `.shuffle()`, `.sort()`, `.train_test_split()`
- `load_dataset("json", data_files=...)` and `load_dataset("csv", ...)` from local files
- `.save_to_disk()` / `load_from_disk()` — Arrow IPC (`.arrow`) cache
- Streaming transforms, `set_format("torch")`, column ops

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `.parquet` read/write | ✅ **Works** (since 2026-07) — pyarrow was rebuilt with the Parquet C++ component (`_parquet` / `_dataset` exts + snappy/zstd/lz4); `load_dataset("parquet", data_files=...)` and the folder builders run for real. See [pyarrow.md](pyarrow.md) | — |
| `load_dataset("<hub-id>")` | Needs network to fetch the Hub dataset | Download on a desktop, ship the files, `load_dataset("json"/"parquet", data_files=...)` |
| Multiprocessed `.map(num_proc>1)` | iOS forbids `fork()` | Default single-process `.map()` |

## iOS-specific fix

`datasets` 4.0.0's `utils/_dill.py` overrides `Pickler._batch_setitems(self, items)`,
but Python 3.14 (3.13+) added a third `obj` parameter to that pickle hook — the
bundled copy is backported to forward it, so `.map()` doesn't die with
`_batch_setitems() takes 2 positional arguments but 3 were given`.

## See also
- [transformers.md](transformers.md) — the training loop that consumes datasets
- [evaluate.md](evaluate.md) — metrics
