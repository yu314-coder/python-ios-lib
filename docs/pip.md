# pip

> **Version:** 26.0.1 (in-process; not the `pip` shell binary)  | **Type:** Pure Python  | **Status:** Working — installs to `~/Documents/site-packages/` (writable in iOS sandbox)

The standard pip installer, runnable in-process from Python. iOS apps
can't `fork`/`exec` to spawn a `pip` binary, so the in-app shell wraps
`pip._internal.cli.main.main(argv)` and routes installs into the
user's writable Documents directory.

---

## Quick start

In CodeBench's in-app shell (or any Python session):

```
pip install rich tqdm requests
pip uninstall some-package
pip list
pip show numpy
pip freeze > requirements.txt
```

From Python directly:

```python
from pip._internal.cli.main import main as pip_main

pip_main(["install", "rich"])
pip_main(["list"])
```

The CodeBench shell wrapper does some additional polish:
- Auto-injects `--target ~/Documents/site-packages` (the only writable
  Python path in the iOS sandbox)
- Detects bundled packages via dist-info and prints
  `Requirement already satisfied: <pkg> — bundled with CodeBench`
- Doesn't auto-add `--upgrade` (so plain `pip install foo` doesn't
  re-download every time)
- Strips capture/forwarding so progress bars + colored output work in
  the in-app terminal

---

## What you can install

### ✓ Pure-Python wheels

Anything PyPI ships as `*-py3-none-any.whl`:

```
pip install python-dotenv
pip install python-dateutil
pip install pytz
pip install pyparsing
pip install loguru
pip install pendulum
pip install ftfy
pip install pytest               # tests run in-process
pip install hypothesis
pip install black
pip install ruff                 # has a Rust binary fallback to pure-Python
pip install httpx                # async HTTP — pure Python
pip install pydantic-core        # NB: this one IS native, see below
pip install python-magic         # NB: needs libmagic native — won't work
```

If the package's wheel name contains `py3-none-any.whl`, it'll work.

### ✓ Already-bundled libs (auto-detected as installed)

These are vendored into the app, so pip recognizes them via dist-info
stubs and reports "already satisfied":

```
numpy, scipy, sympy, mpmath, networkx, sklearn,
plotly, matplotlib, manim, manimpango, mapbox-earcut, isosurfaces,
PIL/Pillow, av (PyAV), pydub, cairo, pathops, svgelements,
torch, transformers, tokenizers, safetensors, huggingface-hub,
requests, urllib3, bs4, certifi, idna, charset-normalizer,
jsonschema, jsonschema-specifications, referencing, rpds-py,
rich, click, cloup, attrs, packaging, pygments, regex, tqdm, psutil,
filelock, pyyaml, watchdog, decorator, pywebview, …
```

(See [scripts/register_bundled_packages.py](../scripts/register_bundled_packages.py)
for the full list.)

### ✗ What you CANNOT install on iOS

Packages with native C / Rust extensions that don't have an iOS arm64
wheel on PyPI. Examples:

| Package | Why it fails |
|---|---|
| `numpy` (re-install) | PyPI ships macOS / Linux / Windows wheels; no iOS. Use the bundled one. |
| `scipy` (re-install) | Same — bundled is iOS-built. |
| `pandas` | macOS-only wheels on PyPI. **Workaround**: would need to be cross-compiled for iOS arm64 (not in this repo yet). |
| `lxml` | C wrapper around libxml2; no iOS wheel. Use `bs4` with the html.parser backend. |
| `Pillow` (re-install) | Bundled is iOS-built. |
| `numpy-quaternion` | C extension; no iOS wheel. |
| `pycryptodome` | Has a sdist that needs C compilation; no on-device compiler. |
| `matplotlib` (replace shim) | Bundled is the Plotly-backend shim — installing the real matplotlib would crash trying to load Tk/Cairo backends. |
| `bitsandbytes` | CUDA-only — not just iOS, requires NVIDIA GPU. |
| `flash-attn` / `xformers` | CUDA-only. |
| `vllm` / `mlc-llm` | CUDA / Metal compute — also need C++ compilation. |

**Rule of thumb**: if the PyPI page lists wheels for `manylinux` /
`macosx` / `win` only (no `iphoneos`), the package won't install. Pure
Python wheels (`*-py3-none-any.whl`) work fine.

### Sometimes-works: sdist packages

Some packages on PyPI ship only as source distributions (`*.tar.gz`).
pip will TRY to build them on-device, but iOS has no C compiler so:

- **Pure Python sdist** (e.g. `python-magic-bin`'s pure-Python part):
  works — pip just unpacks and installs the .py files.
- **C-extension sdist** (e.g. `psutil` from sdist): fails at the
  `setup.py build_ext` step. You'll see
  `error: command '/usr/bin/clang' not found`.

For C extensions: file an issue requesting an iOS arm64 build, or
cross-compile on macOS and add to this repo.

---

## Where pip installs to

By default the in-app `pip` injects `--target ~/Documents/site-packages/`
because that's the only writable Python path on iOS. Your `sys.path`
includes that directory ahead of the bundled site-packages, so:

- New installs win over bundled versions (useful for testing patches)
- Removing the file from `~/Documents/site-packages/` reverts to the
  bundled version (no full re-install needed)
- Files persist across app updates (Documents survives app upgrades)

You can also install elsewhere:

```
pip install -t /custom/path some-package
```

---

## What the wrapper does

Reading `app_packages/site-packages/offlinai_shell.py`'s `_pip` function:

1. Set env vars: `PIP_DISABLE_PIP_VERSION_CHECK=1`, `PIP_NO_CACHE_DIR=1`,
   `PIP_NO_COLOR=1`, `PYTHONUNBUFFERED=1`
2. Add `~/Documents/site-packages` to `sys.path` if not already
3. For `install` commands:
   - Detect already-bundled packages via `importlib.metadata.distribution(name)`
   - Print "Requirement already satisfied: X (Y) — bundled with CodeBench"
   - Strip already-bundled package names from the install args
   - If nothing remains to install, return early
   - Otherwise, inject `--target ~/Documents/site-packages
     --no-warn-script-location` (so pip writes to a writable location)
3. For `list` / `show` / `freeze` / `check`: capture stdout into our
   own pipe so the output reaches the in-app terminal even when pip
   would normally buffer
4. Reset cached pip loggers (otherwise repeated calls in the same
   interpreter print nothing)
5. Call `pip._internal.cli.main.main(args)` and surface the exit code

---

## Custom pip-friendly subcommands

The shell adds shortcuts:

```
pip-install <pkg>       # → pip install <pkg> --target user_site
pip-uninstall <pkg>     # → pip uninstall <pkg>
pip-list                # → pip list
pip-show <pkg>          # → pip show <pkg>  (richer output: file count, native .so list, deps)
pip-freeze              # → pip freeze
pip-check               # → pip check
```

`pip-show` is enhanced — for bundled packages it prints native-extension
info, file counts, and reverse-dependency markers in addition to the
standard pip output.

---

## Examples

### Install a new pure-Python package

```
pip install python-dateutil
```
Output:
```
Collecting python-dateutil
  Downloading python_dateutil-2.9.0.post0-py2.py3-none-any.whl (229 kB)
Collecting six>=1.5
  Downloading six-1.16.0-py2.py3-none-any.whl (11 kB)
Installing collected packages: six, python-dateutil
Successfully installed python-dateutil-2.9.0.post0 six-1.16.0
```

The `python-dateutil` and `six` files now live at
`~/Documents/site-packages/`. `import dateutil` from any Python session
finds them ahead of (any nonexistent) bundled version.

### Try to install something with native code

```
pip install lxml
```
```
Collecting lxml
  Downloading lxml-5.3.0.tar.gz (3.6 MB)
  Installing build dependencies ... done
  ...
  ERROR: Failed to build lxml
  Cannot find compatible C compiler in PATH
```

Workaround: `pip install beautifulsoup4` instead and use bs4's
html.parser backend (pure Python).

### Re-install a bundled package from PyPI (if you wanted to test a newer version)

```
pip install --force-reinstall numpy
```
This bypasses the "already satisfied" check, but pip will still fail
because the PyPI wheel for numpy is macOS / Linux / Windows only.
There's no iOS wheel to install over the bundled one.

---

## Limitations

- **No isolated venvs.** `python -m venv` works but the resulting
  venv shares the bundled site-packages — there's nothing to
  isolate from. If you really want a fresh tree, `pip install
  --target /custom/path/...`.
- **No `pip wheel` builds with C deps** — same no-compiler issue.
- **`pip install -e .`** (editable installs) works for pure-Python
  packages, has the usual setuptools-side caveats for compiled ones.
- **No `pip search`** — PyPI removed the search endpoint years ago;
  applies to all clients.

---

## See also

- [docs/codebench-extras.md](codebench-extras.md) — the wrapper around pip
  in offlinai_shell
- [scripts/register_bundled_packages.py](../scripts/register_bundled_packages.py)
  — generates the dist-info stubs that make pip detect bundled libs
