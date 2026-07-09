# pyarrow — Apache Arrow 15.0.2 (iOS, with Parquet)

Real Arrow C++ 15.0.2 cross-compiled static for iOS arm64 with the Python
bindings (`lib`, `_compute`, `_csv`, `_json`, `_fs`, `_feather`, `_hdfsio`,
**`_parquet`, `_dataset`, `_dataset_parquet`** + `libarrow_python.so`).
Build tree: `/Volumes/D/python-ios-lib/pyarrow_ios/` (Arrow checkout +
`cpp/build-ios-pq` + `python/build-ios-pq`, BUNDLED deps, static).

> **2026-07:** originally shipped as a minimal build without the Parquet C++
> component (`pyarrow.parquet` was an error-raising import shim). Rebuilt with
> `-DARROW_PARQUET=ON -DARROW_DATASET=ON` + snappy/zstd/lz4, closing the last
> `datasets` gap — `.parquet` read/write and partitioned `pyarrow.dataset`
> now work on-device.

## What works

- Core `pyarrow` — `pa.array`, `pa.Table`, `pa.RecordBatch`, schemas, chunked
  arrays, slicing/casts
- `pyarrow.compute` — kernels (aggregations, arithmetic, string ops)
- `pyarrow.csv` / `pyarrow.json` — fast readers
- **Arrow IPC / Feather** — `pa.ipc`, `feather.read_table` / `write_feather`;
  this is the on-disk format `datasets` uses for its cache
- **`pyarrow.parquet`** — `write_table` / `read_table` / `read_metadata`,
  compression: snappy, zstd, lz4, none
- **`pyarrow.dataset`** — partitioned datasets, `write_dataset` / `dataset()`
  (parquet + IPC formats)
- `pandas` interop — `pa.Table.from_pandas()` / `.to_pandas()`,
  `pd.read_parquet` / `to_parquet`
- `pyarrow.fs` — local filesystem

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `flight` / `orc` / `cuda` / `gandiva` | Not built (server/GPU features) | N/A on device |
| Brotli parquet compression | Codec not built | snappy / zstd / lz4 / none |
| `pa.json_()`-era APIs (pyarrow ≥ 21) | This is 15.0.2 | Pin consumers accordingly (datasets 4.0.0, not 5.x) |

## iOS build gotchas (for rebuilds)

- Pass `-DCMAKE_SYSTEM_PROCESSOR=arm64` — Arrow's SetupCxxFlags errors
  "Unknown system processor" under `CMAKE_SYSTEM_NAME=iOS` without it.
- Thrift (parquet dep): `BOOST_ROOT` is ignored by `find_path` in an iOS
  cross-compile (sysroot-only search) — with `-DBOOST_SOURCE=BUNDLED`, also
  append `-DBoost_INCLUDE_DIR=${BOOST_ROOT}` to `THRIFT_CMAKE_ARGS` in
  `cmake_modules/ThirdpartyToolchain.cmake`.
- Static builds: `python/CMakeLists.txt` hardcodes
  `arrow_{acero,dataset}_shared` for `ACERO_LINK_LIBS` / `DATASET_LINK_LIBS`
  (upstream bug — parquet handles static correctly); patch to select
  `_static` when `NOT ARROW_BUILD_SHARED`.
- Python-side configure additionally needs `-DPython3_NumPy_INCLUDE_DIR=<venv
  numpy>` and, for `find_dependency(ArrowAcero)`, `-DCMAKE_FIND_ROOT_PATH=
  <install>` (same sysroot-only-search issue as thrift).
- The Cython exts come out suffixed `.cpython-314-darwin.so` (host venv
  naming) — genuinely iOS binaries (`LC_VERSION_MIN_IPHONEOS`); rename to
  `-iphoneos.so` when copying into the bundle. All exts + `libarrow_python`
  must swap together (same-build ABI).
- The wheel is assembled by `pyarrow-ios-build` (see dist-info WHEEL Generator).

## See also
- [datasets.md](datasets.md) — the main consumer + the shim behavior
- [pandas.md](pandas.md)
