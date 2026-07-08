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
| `.parquet` read/write | **Not supported** — bundled pyarrow 15 was built without the Parquet C++ component (no `_parquet` extension, no libparquet) | Convert to JSON / CSV / Arrow; a `pyarrow.parquet` import shim lets `datasets` import and raises a clear error only on actual parquet I/O. Real parquet needs pyarrow rebuilt with `-DARROW_PARQUET=ON` |
| `pyarrow.dataset` (partitioned/folder builders) | Shimmed (`pyarrow._dataset` absent in the minimal build) | Non-parquet builders work; folder-of-parquet does not |
| `load_dataset("<hub-id>")` | Needs network to fetch the Hub dataset | Download on a desktop, ship the files, `load_dataset("json", data_files=...)` |
| Multiprocessed `.map(num_proc>1)` | iOS forbids `fork()` | Default single-process `.map()` |

## iOS-specific fix

`datasets` 4.0.0's `utils/_dill.py` overrides `Pickler._batch_setitems(self, items)`,
but Python 3.14 (3.13+) added a third `obj` parameter to that pickle hook — the
bundled copy is backported to forward it, so `.map()` doesn't die with
`_batch_setitems() takes 2 positional arguments but 3 were given`.

## See also
- [transformers.md](transformers.md) — the training loop that consumes datasets
- [evaluate.md](evaluate.md) — metrics
