# tqdm — progress bars

**Version:** 4.67.3  
**Type:** Pure Python  
**SPM target:** `Tqdm`  
**Auto-included by:** huggingface_hub, transformers, datasets, manim, pip  
**Total Python modules:** 31

Wrap any iterable with `tqdm(...)` to get a live progress bar with ETA, rate, postfix stats. Multiple flavors (stdout, GUI, Jupyter, rich, async). On iOS the stdout flavor renders as in-place updates in the in-app shell.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `tqdm.__init__` | Re-exports `tqdm`, `trange`, `tqdm_pandas`, `tqdm_gui`, `tgrange`, `TMonitor`, `TqdmSynchronisationWarning`, `__version__`, `main` |
| `tqdm.std` | The reference `tqdm` class (used by `from tqdm import tqdm`). Also `Bar`, `EMA`, `TqdmDefaultWriteLock`, `TRLock`, all warning types (`TqdmTypeError`, `TqdmKeyError`, `TqdmWarning`, `TqdmDeprecationWarning`, `TqdmMonitorWarning`, `TqdmExperimentalWarning`) |
| `tqdm.auto` | Auto-detect best flavor — uses `tqdm.notebook` in Jupyter, `tqdm.std` elsewhere. The recommended import: `from tqdm.auto import tqdm` |
| `tqdm.autonotebook` | Same as `auto` but errors-loud if not in a notebook |
| `tqdm.asyncio` | `tqdm.asyncio.tqdm` — async iterator support: `async for x in tqdm(async_iter)` |
| `tqdm.gui` | Tkinter / matplotlib GUI bars — no GUI on iOS, falls back to stdout |
| `tqdm.notebook` | Jupyter widget bars (`IProgress` HTML widget) |
| `tqdm.tk` | Tk-based bar window |
| `tqdm.rich` | Rich-rendered bar — uses `rich.progress.Progress` |
| `tqdm.dask` | `tqdm.dask.TqdmCallback` — Dask scheduler progress |
| `tqdm.keras` | `tqdm.keras.TqdmCallback` — Keras training callback |
| `tqdm.cli` | `tqdm` command-line entry — pipe stdin through a progress bar |
| `tqdm.version` | `__version__` lookup (via `importlib.metadata`) |
| `tqdm.utils` | `disp_len`, `disp_trim`, `IS_WIN`, `IS_NIX`, color helpers |
| `tqdm._utils` | Deprecated alias for `tqdm.utils` (re-exported for back-compat) |
| `tqdm._monitor` | `TMonitor` thread that warns about hung iteration |
| `tqdm._main` | Deprecated alias for `tqdm.cli` |
| `tqdm._tqdm` / `_tqdm_gui` / `_tqdm_notebook` / `_tqdm_pandas` | Deprecated aliases for `tqdm.std` / `gui` / `notebook` / pandas integration |

### `tqdm.contrib` — extras

| Submodule | What it does |
|---|---|
| `contrib.__init__` | `tenumerate`, `tzip`, `tmap` — wrapped `enumerate`/`zip`/`map` |
| `contrib.bells` | `tqdm` with all extras enabled (rich + auto + colour) |
| `contrib.concurrent` | `process_map`, `thread_map` — concurrent.futures + progress bar |
| `contrib.discord` | Report progress to a Discord channel via webhook |
| `contrib.slack` | Report progress to Slack via webhook |
| `contrib.telegram` | Report progress to a Telegram chat |
| `contrib.logging` | `tqdm_logging_redirect` ctx manager — route `logging` writes through `tqdm.write` so log lines don't break the bar |
| `contrib.itertools` | `product` — `itertools.product` with progress |
| `contrib.utils_worker` | `MonoWorker` — worker that prints each result on its own line |

## iOS notes

- **stdout bar works.** Carriage-return based redraw renders cleanly in the in-app shell.
- **No Jupyter widgets.** `tqdm.notebook` imports `ipywidgets` which isn't shipped. Use `tqdm.auto` — it falls back to `tqdm.std`.
- **No GUI.** `tqdm.gui` / `tqdm.tk` need Tk/matplotlib displays — non-functional on iOS.
- **`huggingface_hub` and `transformers` log via tqdm.** Model download bars work out of the box.
- **TMonitor thread:** disable via `tqdm.set_lock(None)` or `TQDM_DISABLE_MONITOR=1` if you see "iteration stuck" false positives on iOS (slow filesystem operations can trip the 60-second default).

## Example

```python
from tqdm.auto import tqdm, trange
from tqdm.contrib.concurrent import thread_map
import time

# Wrap any iterable
for path in tqdm(file_list, desc="Hashing", unit="file"):
    hash_file(path)

# Manual / unknown total
pbar = tqdm(total=None, desc="Streaming", unit="B", unit_scale=True)
while chunk := stream.read(8192):
    pbar.update(len(chunk))
pbar.close()

# Parallel + progress in one line
results = thread_map(download, urls, max_workers=4, desc="Downloading")

# Postfix stats
pbar = trange(100, desc="Training")
for i in pbar:
    loss = train_step()
    pbar.set_postfix(loss=f"{loss:.4f}", lr=1e-3)
```
