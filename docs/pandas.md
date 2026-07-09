# pandas — 2.2.3 native iOS build

Real pandas 2.2.3 cross-compiled for iOS arm64 (all Cython extensions native).
Bundled under `pandas_ios/pandas-2.2.3/` and put on `sys.path` by the runtime
(the wheel's hyphenated dir name isn't importable as-is, hence the path entry).

## What works

- DataFrames / Series end-to-end: construction, indexing (`loc`/`iloc`),
  groupby, merge/join, pivot, resample, rolling windows, categoricals
- I/O: CSV, JSON, Excel (via bundled `openpyxl`), Arrow interop
  (`pa.Table.from_pandas` / `.to_pandas` with the bundled pyarrow), pickle,
  HDF-free formats
- Datetime stack (bundled `dateutil` + `pytz` ship as sourceless `.pyc` —
  tracked exceptions in `.gitignore` so fresh clones work)
- Interop: numpy (Accelerate-backed), matplotlib plotting, `datasets.from_pandas`

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `pd.read_parquet` / `to_parquet` | ✅ Works — pyarrow rebuilt with Parquet (see [pyarrow.md](pyarrow.md)) | — |
| `pd.read_hdf` (PyTables) | `tables` not bundled (HDF5 C lib) | pickle or Arrow IPC |
| `pd.read_sql` against remote DBs | Driver packages (psycopg2 etc.) not bundled | sqlite3 (stdlib) works |
| `DataFrame.plot()` GUI popups | No desktop windows | Plots render into the CodeBench preview via matplotlib |
| Copy-on-write parallelism / threads | Fine — but no `multiprocessing` | Single-process ops (pandas is single-threaded anyway) |

## iOS-specific patches

- A `resize`-fallback hook in `sitecustomize.py` guards against the iOS numpy
  OWNDATA quirk in `np.ndarray.resize` paths pandas exercises
  (see [numpy.md](numpy.md)).

## See also
- [numpy.md](numpy.md) · [pyarrow.md](pyarrow.md) · [datasets.md](datasets.md)
