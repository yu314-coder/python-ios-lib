# narwhals — Backend-agnostic dataframe API

**Version:** 1.16.0
**Type:** Pure Python
**SPM target:** Bundled in `Matplotlib` (no standalone target)
**Auto-included by:** Plotly, Altair
**Total Python modules:** 162

A compatibility layer that lets a single dataframe-shaped piece of code
run unchanged against pandas, polars, pyarrow, modin, cudf, dask,
duckdb, ibis, and pyspark. Plotly and Altair use it so they can accept
ANY dataframe type as input — narwhals normalizes calls like
`df.select(...)` / `df.filter(...)` into the right backend dialect.

You rarely import it directly. It's invoked when you pass a non-pandas
dataframe to a plotting library that supports multiple backends.

## Modules

### Top-level (32 files)

| Module | What it does |
|---|---|
| `narwhals.__init__` | Public API: `DataFrame`, `LazyFrame`, `Series`, `col`, `lit`, `when`, `from_native`, `to_native`, `narwhalify`, dtypes (`Int64`, `Float64`, `String`, `Datetime`, `Duration`, `Array`, `List`, `Struct`, …) |
| `narwhals.dataframe` | `DataFrame` / `LazyFrame` user-facing classes |
| `narwhals.series` | `Series` + per-namespace accessors (`series_cat`, `series_dt`, `series_list`, `series_str`, `series_struct`) |
| `narwhals.expr` | `Expr` + accessors (`expr_cat`, `expr_dt`, `expr_list`, `expr_name`, `expr_str`, `expr_struct`) |
| `narwhals.functions` | `col`, `lit`, `when`, `sum_horizontal`, `min_horizontal`, `max_horizontal`, `mean_horizontal`, `concat`, `concat_str`, `len_` |
| `narwhals.dtypes` | Backend-neutral dtype hierarchy |
| `narwhals.schema` | `Schema` — ordered name-to-dtype map |
| `narwhals.group_by` | `GroupBy`, `LazyGroupBy` |
| `narwhals.selectors` | Column selectors: `by_dtype`, `numeric`, `string`, `datetime`, `boolean`, `categorical`, `matches`, `all`, `last`, `first` |
| `narwhals.translate` | `from_native`, `to_native`, `from_dict`, `from_dicts`, `narwhalify` |
| `narwhals.dependencies` | Lazy-import probes (`get_polars`, `get_pandas`, `get_pyarrow`, …) — used to detect which backends are installed without importing them |
| `narwhals.exceptions` | `ColumnNotFoundError`, `ShapeError`, `InvalidOperationError`, `LengthChangingExprError`, `NarwhalsUnstableWarning`, etc. |
| `narwhals.typing` | Type aliases: `IntoFrame`, `IntoSeries`, `IntoExpr`, `IntoDType`, `DTypes` |
| `narwhals.plugins` | Third-party backend registration |
| `narwhals._utils` | `Implementation` enum + helpers (`generate_temporary_column_name`, `maybe_align_index`, `is_ordered_categorical`, …) |
| `narwhals.this` | The Zen of Narwhals (`import narwhals.this`) |

### Backend adapters

Each backend lives in its own `_<name>/` subpackage with a fairly
uniform layout (`dataframe.py`, `expr.py`, `series.py`, `namespace.py`,
`selectors.py`, `group_by.py`, `utils.py`, sometimes accessor modules
like `expr_dt.py`, `series_str.py`).

| Subpackage | Backend |
|---|---|
| `narwhals._pandas_like` | pandas, modin, cudf (shared implementation) |
| `narwhals._arrow` | PyArrow Tables |
| `narwhals._polars` | Polars (DataFrame + LazyFrame) |
| `narwhals._dask` | Dask DataFrames (lazy) |
| `narwhals._duckdb` | DuckDB relations (lazy) |
| `narwhals._ibis` | Ibis tables (lazy) |
| `narwhals._spark_like` | PySpark / sqlframe / pyspark-connect |
| `narwhals._sql` | Shared SQL-backend mixins |
| `narwhals._interchange` | Dataframe Interchange Protocol (DLPack) |
| `narwhals._compliant` | Abstract base classes every backend implements |

### Stable API surfaces

`narwhals.stable.v1` and `narwhals.stable.v2` — frozen public APIs for
downstream libraries that need version stability across narwhals
releases. Each pins a snapshot of `__init__`, `dependencies`, `dtypes`,
`selectors`, `typing`.

### Testing helpers

`narwhals.testing.asserts` — `assert_frame_equal`, `assert_series_equal`
for use in user test suites.

## iOS-specific patches

None. The bundled iOS app only ships pandas + pyarrow as backends
(`narwhals._pandas_like`, `narwhals._arrow`), so `_dask`, `_duckdb`,
`_ibis`, `_polars`, `_spark_like` exist as code paths but are only
loaded if you `pip install` those libraries on top — none ship with
the iOS bundle.

## Standalone example

```python
import narwhals as nw
import pandas as pd
import pyarrow as pa

# Same code works with pandas OR pyarrow input
def add_doubled(df_native):
    df = nw.from_native(df_native, eager_only=True)
    result = df.with_columns(doubled=nw.col("x") * 2)
    return nw.to_native(result)

print(add_doubled(pd.DataFrame({"x": [1, 2, 3]})))
#    x  doubled
# 0  1        2
# 1  2        4
# 2  3        6

print(add_doubled(pa.table({"x": [1, 2, 3]})))
# pyarrow.Table with x, doubled columns
```

## See also

- [docs/plotly.md](plotly.md) — primary consumer (figure-construction layer is narwhals-driven)
- [docs/matplotlib.md](matplotlib.md) — bundled into the Matplotlib SPM target
