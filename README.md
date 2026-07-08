# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with **30+ offline libraries including real PyTorch + HuggingFace transformers + Rust tokenizers + Blender `bpy`**. No JIT, App Store safe.

> **New:** Full `import bpy` — the **complete Blender module** cross-compiled for iOS arm64. Render with **both Cycles and Eevee on the Apple GPU (Metal)** + OpenImageDenoise, with a working **`gpu` module** (`gpu.init()` / `GPUOffScreen`), plus OpenSubdiv / OpenVDB / Alembic / Bullet / Mantaflow and the full modifier stack. First public iOS build — including the first iOS Eevee / Metal-GPU backend. In CodeBench, saving a `.blend` auto-opens an interactive WebGL 3D preview. [doc](docs/blender-bpy.md)

> **New:** Full `import torch` (v2.1), `import transformers` (v4.41), and `import tokenizers` (v0.19, real Rust cross-compile) all work on-device. Train and fine-tune transformer models on an iPad with zero network. [Full integration test: 24/24 passing.](docs/transformers.md#test-coverage)

> **GPU (Metal):** Two of the Metal-accelerated pieces are also published as standalone repos — **[cairometal](https://github.com/yu314-coder/cairometal)** (a pycairo-compatible GPU cairo on Metal) and **[torchmetal](https://github.com/yu314-coder/torchmetal)** (routes PyTorch's hot inference ops to Metal/MPS, designed for iOS). Both are wired into this package's `Package.swift` as the **`CairoMetal`** and **`TorchMetal`** products. The full `cairo(metal)` engine used by manim's GPU path stays bundled in this repo (`app_packages`), unchanged.

## All Libraries

The `app_packages/site-packages/` bundle ships **~180 Python packages** — every entry below is importable on-device with **no `pip install` needed**. Anything you'd typically `pip install` for an HF training script is already here, except for a short list at the end that depends on un-cross-compileable C/Rust extensions.

### Machine Learning stack (bundled)

| Library | Version | Notes |
|---|---|---|
| **torch** | 2.1.0 (patched iOS) | Native arm64 + Metal GPU bridge. See [What works / what doesn't](#what-works--doesnt--ios-torch) below. |
| **transformers** | 4.41.2 | HF — train + generate + save. See [What works / what doesn't](#what-works--doesnt--transformers) below. |
| **accelerate** | 0.30.1 | Required by HF `Trainer` (hard import at module load). Pure Python. |
| **peft** | 0.12.0 | LoRA / IA3 / prefix tuning. `get_peft_model()` + `LoraConfig` work as-is. |
| **tokenizers** | 0.19.1 | Real Rust BPE/WordPiece/Unigram cross-compiled for iOS arm64 via PyO3. First public iOS build. |
| **safetensors** | 0.4.5 (pure-Python shim) | Bidirectional (read + write). `model.save_pretrained()` writes valid files. |
| **onnxruntime** | 1.26.0 | Native arm64 + **CoreML execution provider** (Neural Engine) — 12–14× over CPU on conv nets, device-verified. Export ONNX on host (iOS torch 2.1 lacks the export JIT passes), run on device. |
| **huggingface_hub** | 0.24.7 | HF Hub client — `from_pretrained` works over network. |
| **scikit-learn** | 1.9.0 | **Real native Cython** cross-compile — 69 `.so`, full API (all 39 submodules). First public iOS build, replaces the old pure-NumPy reimpl. [doc](docs/sklearn.md) |
| **faiss** | 1.9.0 (CPU) | Vector similarity search — native cross-compile (serial). On-device RAG retrieval. |
| **sentencepiece** | 0.2.0 | Google BPE / unigram tokenizer — native cross-compile (behind Llama / T5 / Gemma). |

#### What works / doesn't — iOS torch

✅ **Works on iPad:**
- `torch.Tensor`, `nn.Module`, `nn.Linear/Conv/...`, full `autograd`
- `torch.optim` (SGD, AdamW, Adam, RMSprop, Adagrad, …)
- `torch.jit.script` + `trace` (eager-mode tracing, no JIT codegen)
- LAPACK via Apple's Accelerate framework: `solve` / `eigh` / `svd` / `qr` / `lu` / `cholesky`
- FFT via Accelerate: `torch.fft.*`
- **GPU-accelerated** via the Metal bridge: `torch.matmul`, `torch.mm`, `torch.bmm`, `torch.addmm`, `F.linear`, `F.scaled_dot_product_attention` (fp32 / fp16 / bf16)
- Mixed precision: `bf16` and `fp16` dtypes (cast paths through the GPU bridge)
- `torch.save` / `torch.load` (pickle-based)
- **TensorBoard** `SummaryWriter` (2.19.0) — `add_scalar/histogram/…` write real event files offline (the *viewer* server needs grpcio → not bundled; copy the logs off-device to view)
- `torch.frombuffer` for byte-buffer→tensor (used by the safetensors / numpy shims)
- **`flash_attn` + `xformers` API shims** — `flash_attn_func` / `flash_attn_varlen_func` / `bert_padding` and `xformers.ops.memory_efficient_attention` are implemented on `F.scaled_dot_product_attention` (GPU via the Metal bridge), so code that hard-imports either package runs unchanged. Matches flash-attn ≥2.1 semantics (bottom-right causal alignment, GQA/MQA kv-head repeat, varlen). Not implemented: `window_size` sliding attention, ALiBi slopes, `return_attn_probs`.

❌ **Doesn't work — the only remaining gaps, all genuine iOS hardware/OS limits (workarounds where they exist):**

| Op / feature | Why broken | Workaround |
|---|---|---|
| `torch.cuda.*` | No CUDA on iOS | None — use the Metal bridge for matmul-heavy ops |
| `torch.backends.mps` | MPS backend not in this build | Metal bridge replaces it |
| `torch.distributed`, `torch.multiprocessing` | iOS forbids `fork()` | Single-process training only |
| `torch.compile` | Needs Triton JIT, iOS forbids JIT | Eager mode + GPU bridge |
| `torch.from_numpy()`, `tensor.numpy()` | Built with `USE_NUMPY=0` | **Auto-patched** in sitecustomize — drop-in pure-Python equivalents using `torch.frombuffer` |
| `DataLoader(num_workers > 0)` | Worker processes use `fork()` | Set `num_workers=0` (only iPad limitation that needs code awareness) |
| `flash-attn`, `xformers` (real kernels) | CUDA / Triton-only | **API shims bundled** — both packages import and their attention functions run on GPU via SDPA + the Metal bridge (see ✅ above) |
| `bitsandbytes` | CUDA-only 8/4-bit kernels; no Metal equivalent — a shim would dequantize and lose the memory saving | Use llama.cpp GGUF Q4/Q8 for quantized inference |

#### What works / doesn't — transformers

✅ **Works on iPad:**
- `AutoModel`, `AutoTokenizer`, `AutoModelForCausalLM`, `AutoModelForSeq2SeqLM`, etc.
- `from_pretrained(...)` — local files or HF Hub URLs (latter needs network access)
- `model.generate()` — full autoregressive generation, beam search, sampling
- `Trainer.train()` — auto-checkpoint + auto-resume via sitecustomize patches
- `model.save_pretrained(...)` — writes `pytorch_model.bin` + `.safetensors` (both work)
- `peft.get_peft_model()` + LoRA / IA3 training
- Mixed precision: `bf16=True` or `fp16=True` in `TrainingArguments`
- **Model families verified:** BERT, GPT-2, T5, BART, Llama, Qwen, Mistral, Phi
- **SentencePiece tokenizers** (`sentencepiece` C++ **is** cross-compiled + bundled) — Llama / T5 / BART / Gemma / DeBERTa slow tokenizers work, not just BPE ones
- **`datasets`** (4.0.0) — `load_dataset("json"/"csv", data_files=…)` from local files, `Dataset.from_dict/from_pandas`, `.map` / `.filter` / `.train_test_split`, `.arrow` cache (device-verified). **`.parquet` files are NOT supported** — the bundled pyarrow was built without the Parquet C++ component; a `pyarrow.parquet` shim lets datasets import + all non-parquet paths work, and raises a clear error on parquet I/O. (Real parquet needs pyarrow rebuilt with `ARROW_PARQUET=ON`.)
- **`evaluate`** (0.4.6) — imports + local metric compute; `evaluate.load("…")` downloads the metric script (needs network)
- **TensorBoard logging** — `Trainer(..., report_to="tensorboard")` / `SummaryWriter` write real event files offline (see the torch grid above)
- **`attn_implementation="flash_attention_2"` doesn't crash** — sitecustomize remaps it to `"sdpa"` where transformers allows it, else `"eager"` (transformers gates its sdpa path on torch ≥ 2.1.1 — pytorch#112577 — and the bundled torch is 2.1.0, so on-device FA2 requests land on eager: the same implementation every verified model already uses, matmuls GPU-bridged). A one-line notice is printed. Code that imports `flash_attn` / `xformers` directly gets the bundled SDPA-backed shims, which are NOT gated — they call `F.scaled_dot_product_attention` directly and are device-verified numerically correct.

The former software gaps — `sentencepiece`, `datasets`, `evaluate`, TensorBoard, `protobuf` — are all **closed** (bundled + device-verified, listed above). What's left is only what iOS physically can't do:

❌ **Doesn't work — all CUDA / JIT / multi-device limits with no iOS equivalent:**

| Op / feature | Why | Workaround |
|---|---|---|
| `FlashAttention2` (real CUDA kernels) | No CUDA; no Triton | **Auto-remapped** — requesting it no longer crashes (→ sdpa on torch ≥ 2.1.1, → eager on the bundled 2.1.0); `flash_attn` import shim bundled and runs SDPA on GPU directly |
| `DeepSpeed`, `FSDP` | Multi-device / multi-process | Single-device; not applicable to iPad |
| `BitsAndBytes` quantization | CUDA-only | Use llama.cpp's GGUF quantization for inference instead |
| Multi-GPU training | iOS = one device | N/A |

### Scientific Computing

| Library | Version | Type |
|---|---|---|
| **numpy** | 2.3.5 | Native arm64 — **Accelerate** BLAS/LAPACK on the AMX coprocessor |
| **scipy** | 1.15.0 | Native arm64 (flang Fortran + Accelerate BLAS/LAPACK) |
| **pandas** | 2.2.3 | Native arm64 (cross-compiled) — DataFrames |
| **statsmodels** | 0.14.4 | Native arm64 — statistical models / tests |
| **sympy** | 1.14.0 | Pure Python |
| **mpmath** | 1.4.1 | Pure Python |
| **networkx** | 3.6.1 | Pure Python |
| **pint** | 0.25.3 | Pure Python — physical units & dimensional analysis |
| **uncertainties** | 3.2.3 | Pure Python — error propagation (numpy-aware) |
| **periodictable** | 2.1.0 | Pure Python — chemistry element / isotope data (masses, densities) |

### Visualization

| Library | Version | Notes |
|---|---|---|
| **matplotlib** | **3.11.0 (REAL C build)** | ft2font/FreeType, Agg + SVG + PDF, mathtext, styles, animation. In CodeBench, `plt.show()` showcases through plotly: hover values, zoom/pan, legend toggle, orbitable 3-D (3-D axis text moved to the SVG layer — iOS WebKit can't raster WebGL glyphs). Legacy plotly shim preserved: `CODEBENCH_MPL_BACKEND=plotly`; static-only: `CODEBENCH_MPL_INTERACTIVE=0` |
| **plotly** | 6.6.0 | Renders in WKWebView preview pane |
| **seaborn** | bundled | Statistical plotting on matplotlib |
| **fonttools** | bundled | Font subsetting + metadata |
| **mpl_toolkits** | bundled (real) | real mplot3d / axes_grid1 / axisartist |
| **kiwisolver** | 1.5.0 | Native arm64 — mpl's constraint solver (Cassowary) |
| **contourpy** | 1.3.3 | Native arm64 — mpl's contouring engine |
| **narwhals** | 1.16.0 | DataFrame-agnostic helpers (matplotlib internal) |

### Animation / Math Visualization

| Library | Version |
|---|---|
| **manim** | 0.19.0 |
| **manimpango** | 0.6.1 (iOS shim) |
| **mapbox_earcut** | 1.0.3 |
| **isosurfaces** | 0.1.2 |
| **moderngl** | 5.12.0 |
| **moderngl_window** | 2.4.6 |
| **screeninfo** | 0.8.1 |
| **svgelements** | 1.9.6 |
| **pathops** | bundled |

### 3D content creation — Blender

The complete Blender Python module (`bpy` 5.3.0) runs on-device — **the first public iOS build**, and the **first with a working Metal GPU backend**. Beyond Cycles-on-Metal, an offscreen `GHOST_ContextMTL` powers the `gpu` module *and* the **Eevee** render engine, so `gpu.init()` / `GPUOffScreen` and `BLENDER_EEVEE` renders all run on the Apple GPU. It's at **feature parity with the PyPI `bpy` wheel** except Cycles-OSL (which needs a runtime JIT that iOS forbids), and the module-coverage suite — modeling, geometry nodes, animation, all exporters, Eevee/Freestyle/compositor/sequencer/**Cycles-Metal** renders — passes **on a real iPad Air (M3)**.

```python
import bpy, gpu
gpu.init()                                  # offscreen Metal context; gpu.platform.backend_type_get() == 'METAL'
gpu.types.GPUOffScreen(256, 256)            # render targets on the iPad GPU

bpy.data.scenes[0].render.engine = 'BLENDER_EEVEE'
bpy.data.scenes[0].render.filepath = '/…/out.png'
bpy.ops.render.render(write_still=True)     # Eevee still — ~9 s for a lit scene on an M-series iPad
```

| Library | Version | Notes |
|---|---|---|
| **bpy** (Blender) | 5.3.0 | Full `import bpy` — **Cycles *and* Eevee on the Apple GPU (Metal)** + OpenImageDenoise + a working **`gpu` module** (`gpu.init()` / `GPUOffScreen`, offscreen Metal backend), plus OpenSubdiv / OpenVDB / Alembic / **USD + MaterialX** / Bullet / **Mantaflow fluid sim** / **motion tracking (libmv)** / **audio (`aud` + libsndfile)** / i18n API / FFTW ocean / Freestyle, the full modifier stack, and **10/10 image formats** (JPEG/TIFF/WebP included). **At feature parity with the PyPI `bpy` wheel** (only Cycles-OSL remains — it needs a runtime JIT, forbidden on iOS). First public iOS build — including the first iOS Eevee / Metal-GPU backend. In CodeBench, saving a `.blend` auto-opens an interactive WebGL 3D preview. [doc](docs/blender-bpy.md) |

### Media — image / video / audio / documents

| Library | Notes |
|---|---|
| **PIL** (Pillow) | Image processing — native iOS build |
| **cv2** (OpenCV) | 4.10.0 — computer vision, curated native build (core / imgproc / photo / features2d / calib3d / objdetect / ml / flann) |
| **av** (PyAV) | FFmpeg bindings; 7 native dylibs (libav*) |
| **cairo** + **cairocffi** + **cairosvg** | 2D vector graphics + SVG |
| **pydub** | Audio manipulation (uses audioop) |
| **audioop** | LTS backport — removed from Python 3.13 stdlib |
| **pypdf** | PDF read |
| **fpdf** | PDF write |
| **reportlab** | PDF generation (full vector + text) |
| **openpyxl** + **xlsxwriter** + **et_xmlfile** | Excel `.xlsx` read / write |
| **qrcode** | QR-code generation (PNG via the bundled PIL, or pure-Python SVG) |

### LaTeX

| Library | Notes |
|---|---|
| **offlinai_latex** | Math-mode renderer (SwiftMath) + 33 MB bundled texmf tree |

### Web / Network / HTTP

| Library | Notes |
|---|---|
| **requests** | 2.33.1 — HTTP client |
| **urllib3** | 2.6.3 — HTTP transport |
| **httpx** | Async HTTP |
| **anyio** + **sniffio** | Async runtime backends |
| **charset_normalizer** | 3.4.7 — encoding detection |
| **certifi** | 2026.2.25 — CA bundle |
| **idna** | 3.11 — IDN |
| **bs4** (BeautifulSoup4) + **soupsieve** | HTML / XML parsing |
| **defusedxml** | Safe XML parsing |
| **jwt** (PyJWT) | JSON Web Tokens |
| **webview** (PyWebView shim) | Embed HTML in host preview pane |

### Web frameworks — host real dashboards on-device

All five are iOS-patched (`multiprocessing.Value` fallback, signal-handler
skip on worker thread, preview-panel auto-load, clean Ctrl+C shutdown).
Tick any of these in Xcode → SPM pulls every transitive dependency.

| Library | Version | Use case |
|---|---|---|
| **Werkzeug** | 3.1.x | WSGI utilities + dev server. Standalone, or the foundation Flask is built on |
| **Flask** | 3.x | Classic web framework — routes, sessions, templates, blueprints |
| **Dash** | 3.x | Plotly-based reactive dashboards — `dcc`, `html`, `dash_table`, pattern-matching callbacks |
| **Streamlit** | 1.50.x | Script-style dashboards — declarative widgets, `@st.cache_data`, fragments |
| **Tornado** | 6.5.x | Async HTTP/WebSocket framework. Streamlit's transport, usable standalone |

Per-lib docs: [werkzeug.md](docs/werkzeug.md) · [flask.md](docs/flask.md) · [dash.md](docs/dash.md) · [streamlit.md](docs/streamlit.md) · [tornado.md](docs/tornado.md). Cross-stack iOS-patch story: [web-stack.md](docs/web-stack.md).

### Data Formats

| Library | Notes |
|---|---|
| **yaml** (PyYAML) | YAML — native build |
| **jsonschema** 4.26.0 + **jsonschema_specifications** + **referencing** + **rpds** | JSON Schema validation |
| **fsspec** | Filesystem abstraction (HF transformers / hub dep) |
| **filelock** 3.28.0 | Cross-process file locking |
| **tinydb** 4.8.2 | Zero-dependency JSON document database (offline) |

### CLI / Terminal UI

| Library | Notes |
|---|---|
| **rich** 13.7.0 | Tables / progress / coloured output |
| **click** 8.1.7 + **typer** + **cloup** 3.0.5 + **shellingham** | CLI frameworks |
| **textual** | TUI framework |
| **tqdm** 4.67.3 | Progress bars |
| **colorama** | ANSI on every platform |
| **markdown_it** + **mdurl** | Markdown parser |
| **pygments** 2.18.0 | Syntax highlighting (500+ languages) |
| **plotext** 5.3.2 | Plot charts directly in the terminal (no matplotlib) |
| **ftfy** 6.3.1 | Fix mojibake / broken unicode text |

### Testing / Linting / Dev Tools

| Library | Notes |
|---|---|
| **pytest** + **_pytest** + **pluggy** + **iniconfig** | Test framework |
| **hypothesis** + **sortedcontainers** | Property-based testing |
| **black** + **blib2to3** + **isort** + **mypy** + **pyflakes** | Formatters / linters / type checker |
| **tomli** + **tomli_w** + **pytokens** + **pathspec** + **annotated_doc** | Common dev-tool deps |

### Templating / Utility

| Library | Notes |
|---|---|
| **jinja2** 3.1.6 + **markupsafe** 3.0.3 | Templating (HF Trainer chat templates use this) |
| **regex** 2024.11.6 | Extended regex (tokenizers use this) |
| **packaging** 26.0 | Version / requirement parsing |
| **more_itertools** + **lark** | Iteration + grammar parsing |
| **dill** 0.4.1 | Extended pickling — closures, lambdas, whole sessions |
| **pyparsing** 3.3.2 | PEG-style grammar parsing |
| **wcwidth** 0.7.0 | Terminal display width of unicode characters |
| **dateutil** + **pytz** + **pendulum** | Date / time |
| **attr** / **attrs** 24.2.0 + **cattrs** | Attribute classes / converters |
| **platformdirs** | OS-specific paths |
| **humanize** + **tabulate** | Output formatting |
| **watchdog** 4.0.0 | File system watcher |
| **psutil** 5.9.8 (iOS shim) | Process / system info |
| **pycparser** 2.22 | C parser (cffi dep) |
| **pip** 26.0.1 + **wheel** + **setuptools** + **pkg_resources** + **_distutils_hack** | Package management — `pip` patched to install pure-Python pkgs on-device |

### CodeBench-specific runtime helpers

| Module | Purpose |
|---|---|
| **offlinai_ai** | RAG + embedding utilities |
| **_torch_metal_bridge** | PyTorch → Metal GPU dispatch (auto-installed) |
| **_cb_training** | OOMGuard, MemoryProfiler, KVCache, TrainingMonitor, AutoCheckpointer (opt-in, for manual loops) |
| **_cb_background** | iOS background-time extension (auto-enabled) |
| **_cb_gguf_export** | PyTorch LoRA → GGUF converter for llama.cpp inference |

### Interpreters (no Python runtime — pure-Swift)

| Language | Lines | Description |
|---|---|---|
| **C** | ~3,450 | C89/C99/C23, 48 operators, structs, pointers, preprocessor |
| **C++** | ~4,200 | Classes, STL, templates, inheritance |
| **Fortran** | ~4,100 | Modules, allocatable arrays, 45+ intrinsics |

---

### Recent app-side changes

- **Monaco code editor with IntelliSense** running in a WKWebView — Python keyword snippets, signature help (~70-entry SIG_DB), hover docs, and resolve-from-Python for numpy / scipy / sklearn / matplotlib / sympy completions. See `CodeBench/MonacoEditorView.swift`.
- **Auto-save**: edits persist to disk on every keystroke (debounced ~600 ms) plus on run, tab-switch, view-disappear, and app-backgrounding. Fixes the "edit `a.tex`, reopen, 0 B" bug.
- **Tombstone system** — files deleted via the file browser trash icon, `rm` / `rmdir` in the shell, or ncdu's `d` key are recorded in `<Workspace>/.offlinai_deleted` so the starter-script seeder (`pip_demo.py`, `torch_test_all.py`, etc.) no longer re-creates them on next launch.
- **LaTeX bundle expanded** — 33 MB texmf tree now ships with full Latin Modern Type 1 fonts, expl3 code (1.3 MB), firstaid, graphics-def, hyphenation, stringenc, unicode-data, and pdftex.map. Math-mode rendering via SwiftMath is unlimited and reliable; the native `pdflatex` builtin is gated off pending replacement of the 2019-era `pdftex.xcframework` (see [LaTeX docs](docs/offlinai-latex.md)).
- **Shell builtins**: `pdflatex` / `latex` / `tex` / `pdftex` / `xelatex` / `latex-diagnose`, `ncdu` with raw arrow-key navigation and real-ncdu styling, `top` with Apple-chip detection, `git clone` via zipball fetch, and universal `--help` / `-h` interception.
- **matplotlib shim hardening** — user scripts no longer crash on chained attribute access like `ax.xaxis.line.set_color(...)` or `ax.title.set_text(...)`. The plotly-backed matplotlib compatibility shim now uses a chainable `_NoopChainable` singleton for unshimmed attributes (across both `pyplot.py` and the five module stubs in `mpl_toolkits/mplot3d/__init__.py` — `_Art3DModule`, `_Proj3DModule`, `_Axis3DModule`, `_ProjectionModule`, plus the `_art3d_getattr_fallback`), so any chain into a missing attribute degrades silently to `None` instead of raising `'function' object has no attribute X` mid-chain. Plus a swathe of type-mismatch fixes: `get_xticks` / `get_yticks` newly added (were missing on `_Axes` and crashing via the fallback), `get_legend_handles_labels` actually discovers labelled artists from `lines` / `patches` / `collections` / `containers`, `get_array` returns `np.array([])` not `None`, an `_AxisLine` stub for the axis-baseline styling pattern, `set_title(loc=, pad=, y=)` and `set_xticks(minor=)` no longer silently swallow upstream kwargs, and the `__figure__` sentinel that was leaking into `fig.update_layout` (raising `Invalid property '__figure__'` and aborting the whole layout) is now unpacked into the top level. Result: full styling — titles, axis ranges, background colors — actually applies to plotly-rendered charts.
- **Manim 4K/8K rendering is now memory-safe** — the animated-GIF assembly buffer is bounded (capped + downsampled at capture) and full-resolution frames stream to the mp4 instead of being accumulated, so memory no longer scales with `resolution × frame_count`. With a resolution-tiered RAM pre-flight and `malloc` pressure relief on top, manim renders up to **8K** (7680×4320) without tripping iOS's jetsam limit; quality is selectable 480p→8K. Encode uses `h264_videotoolbox`; manim's rasterization stays on cairo's CPU backend — a GPU cairo ([CairoMetal](https://github.com/yu314-coder/cairometal)) exists but doesn't accelerate manim (its bottleneck is Python interpolation, not cairo). See [docs/manim.md](docs/manim.md#high-resolution-4k--8k-rendering) and python-ios-lib issue #1.
- **UTF-8 is the on-device default for `open()`** — iOS's C locale is ASCII and a bare `Py_Initialize()` doesn't honor `PYTHONUTF8`, so `sys.flags.utf8_mode` stays `0` and `open(path)` would otherwise default to ASCII — making `open(p).read()` on a UTF-8 file, or `open(p, "w").write("café")`, crash with a `Unicode{Decode,Encode}Error` (stdout dodged this only because CodeBench wraps it in a custom UTF-8 writer; plain file I/O had no such guard). `sitecustomize.py` now wraps `builtins.open` / `io.open` so any text-mode open with no explicit encoding — or the `"locale"` sentinel that `pathlib.read_text` / `write_text` pass — defaults to UTF-8, matching desktop `PYTHONUTF8` / Python 3.15 behavior. Guarded on `sys.flags.utf8_mode` (steps aside if a future build gets real UTF-8 mode) and idempotent.
- **HuggingFace training-data stack completed** — `datasets` 4.0.0 (local `from_dict` / `map` / `filter` / `train_test_split` / `load_dataset("json")`), `evaluate` 0.4.6, and `torch.utils.tensorboard.SummaryWriter` are bundled and device-verified. `datasets` rides the minimal on-device `pyarrow` via `pyarrow.parquet` / `pyarrow.dataset` import shims (Arrow IPC cache works; real `.parquet` needs pyarrow rebuilt with `ARROW_PARQUET=ON`) plus a Python-3.14 pickle `_batch_setitems` backport. `sentencepiece` (Llama/T5/BART tokenizers) ships too.
- **Files-app sync no longer "Paused"** — the File Provider extension uses the legacy iSH-style `NSFileProviderExtension` enumeration path; `WorkspaceEnumerator` streams items from the shared App-Group container so the CodeBench workspace mounts reliably in the Files app.

## Setup — wiring this package into a fresh iOS app

This SPM package only ships the Python *libraries* (numpy, manim, scipy,
sklearn, matplotlib, …). The CPython 3.14 C runtime itself comes from
BeeWare's [Python-Apple-support](https://github.com/beeware/Python-Apple-support).
Below is the full one-time recipe.

### 1. Get BeeWare's `Python.xcframework`

```bash
mkdir -p _vendor/beeware && cd _vendor/beeware
gh release download 3.14-b9 -R beeware/Python-Apple-support \
  -p "Python-3.14-iOS-support.b9.tar.gz"
tar -xzf Python-3.14-iOS-support.b9.tar.gz
# You now have: Python.xcframework  (~124 MB, slices: ios-arm64,
# ios-arm64_x86_64-simulator, plus a shared lib/ tree)
```

### 2. Add `Python.xcframework` to your Xcode project

- Drag `_vendor/beeware/Python.xcframework` into the Xcode sidebar
  (uncheck "Copy items if needed" — leave it where it is)
- Target → **General → Frameworks, Libraries, and Embedded Content** →
  set its **Embed** column to **Embed & Sign**

### 3. Add this SPM package + tick `Manim`

- File → Add Package Dependencies → `https://github.com/yu314-coder/python-ios-lib`
- Tick **Manim** — every transitive dep (NumPy, SciPy, Sklearn, Matplotlib,
  Pillow, Cairo, FFmpegPyAV, SymPy, NetworkX, Pygments, Click, Cloup,
  Decorator, Tqdm, Rich, Mapbox_earcut, Isosurfaces, Jinja2, Markupsafe,
  Pydub, Psutil, Watchdog, Screeninfo, Moderngl, Moderngl_window,
  Typing_extensions, BeautifulSoup, LaTeXEngine, Plotly) gets pulled in
  automatically — ~30 bundles in total
- After Xcode resolves, each product lands at
  `<App>.app/python-ios-lib_<Product>.bundle/<package_name>/`

### 4. Install BeeWare's stdlib + re-sign every native lib

BeeWare keeps the stdlib **outside** the xcframework slices (at
`Python.xcframework/lib/python3.14/`). Xcode does NOT auto-bundle it.
Also, SwiftPM strips Mach-O code signatures when copying `.so`/`.dylib`
resources, and iOS dlopen rejects unsigned dylibs — so a re-sign loop
is mandatory.

In Build Settings, set **`ENABLE_USER_SCRIPT_SANDBOXING = NO`** (the
script writes into the .app bundle).

Add a **Run Script build phase** (Build Phases → +) with shell `/bin/bash`:

```sh
#!/bin/bash
set -e
BEEWARE="${SRCROOT}/_vendor/beeware/Python.xcframework"
PYIOSLIB_FW="${SRCROOT}/_vendor/python-ios-lib/Frameworks"   # adjust if needed
APP="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
DST="$APP/python-stdlib"
FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:--}"

case "$PLATFORM_NAME" in
  iphoneos)        SLICE="ios-arm64" ;;
  iphonesimulator) SLICE="ios-arm64_x86_64-simulator" ;;
esac
ARCH="${CURRENT_ARCH:-arm64}"; [ "$ARCH" = "undefined_arch" ] && ARCH="arm64"

# 1. Copy stdlib + per-arch lib-dynload + sysconfigdata.
mkdir -p "$DST"
rsync -a --delete --exclude '__pycache__' --exclude 'lib-dynload' \
  "$BEEWARE/lib/python3.14/" "$DST/"
rsync -a --delete \
  "$BEEWARE/$SLICE/lib-$ARCH/python3.14/lib-dynload/" "$DST/lib-dynload/"
find "$BEEWARE/$SLICE/lib-$ARCH/python3.14" -maxdepth 1 \
  -name "_sysconfigdata__*.py" -exec cp -f {} "$DST/" \;

# 2. Copy standalone dylibs from python-ios-lib/Frameworks/ into app
# Frameworks/ (libfortran_io_stubs.dylib for scipy.special, ffmpeg dylibs
# for PyAV, etc.).
mkdir -p "$FRAMEWORKS"
if [ -d "$PYIOSLIB_FW" ]; then
  while IFS= read -r -d '' src; do
    base=$(basename "$src")
    cp -f "$src" "$FRAMEWORKS/$base"
    codesign --force --sign "$IDENT" --timestamp=none "$FRAMEWORKS/$base" 2>/dev/null || true
  done < <(find "$PYIOSLIB_FW" -maxdepth 2 -name "*.dylib" -print0)
fi

# 3. Re-sign every .so/.dylib in stdlib + python-ios-lib_*.bundle.
sign_lib() {
  codesign --force --sign "$IDENT" --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags "$1" 2>/dev/null \
    || codesign --force --sign "$IDENT" --timestamp=none "$1"
}
find "$DST/lib-dynload" -name "*.so" -print0 | while IFS= read -r -d '' so; do sign_lib "$so"; done
for b in "$APP"/python-ios-lib_*.bundle; do
  [ -d "$b" ] || continue
  while IFS= read -r -d '' lib; do sign_lib "$lib"; done \
    < <(find "$b" \( -name "*.so" -o -name "*.dylib" \) -print0)
done

# 4. Rewrite PyAV's hardcoded /tmp/ffmpeg-ios/ install_names → @rpath.
AV="$APP/python-ios-lib_FFmpegPyAV.bundle"
fix_names() {
  for old in $(otool -L "$1" 2>/dev/null | awk '/\/tmp\/ffmpeg-ios/{print $1}'); do
    install_name_tool -change "$old" "@rpath/$(basename "$old")" "$1" 2>/dev/null || true
  done
  for old in $(otool -D "$1" 2>/dev/null | awk 'NR==2 && /\/tmp\/ffmpeg-ios/{print $1}'); do
    install_name_tool -id "@rpath/$(basename "$old")" "$1" 2>/dev/null || true
  done
}
for lib in "$FRAMEWORKS"/libav*.dylib "$FRAMEWORKS"/libsw*.dylib; do
  [ -f "$lib" ] && { fix_names "$lib"; sign_lib "$lib"; }
done
if [ -d "$AV/av" ]; then
  while IFS= read -r -d '' so; do fix_names "$so"; sign_lib "$so"; done \
    < <(find "$AV/av" -name "*.so" -print0)
fi

# 5. (Optional) Bundle Monaco editor with directory structure preserved.
# Synchronized-folder mode flattens subdirs and Monaco has duplicate file
# names across language subfolders — so rsync into the .app at build time
# instead of adding it as a normal resource.
MONACO_SRC="${SRCROOT}/_vendor/python-ios-lib/Monaco"
if [ -d "$MONACO_SRC" ]; then
  rsync -a --delete "$MONACO_SRC/" "$APP/Monaco/"
fi
```

### 5. Boot Python and add the bundles to `sys.path`

Set these env vars **before** `Py_Initialize()` — note the `_PYTHON_SYSCONFIGDATA_NAME`
choice has to match the slice/arch you built for, otherwise `pydoc`
(transitively imported by scipy) crashes with `AttributeError 'installed_base'`:

```swift
let bundleURL = Bundle.main.bundleURL
let stdlib    = bundleURL.appendingPathComponent("python-stdlib")
let dynload   = stdlib.appendingPathComponent("lib-dynload")

// Auto-discover every python-ios-lib_*.bundle sibling.
var libBundles: [String] = []
if let entries = try? FileManager.default.contentsOfDirectory(atPath: bundleURL.path) {
    for n in entries where n.hasPrefix("python-ios-lib_") && n.hasSuffix(".bundle") {
        libBundles.append(bundleURL.appendingPathComponent(n).path)
    }
}

let pythonPath = ([stdlib.path, dynload.path] + libBundles).joined(separator: ":")
setenv("PYTHONHOME",            stdlib.path,  1)
setenv("PYTHONPATH",            pythonPath,   1)
setenv("PYTHONNOUSERSITE",      "1",          1)
setenv("PYTHONDONTWRITEBYTECODE","1",         1)
setenv("PYTHONMALLOC",          "malloc",     1)   // CRITICAL — must be before Py_Initialize
setenv("TMPDIR",                NSTemporaryDirectory(), 1)

// BeeWare per-arch sysconfigdata — pick the matching name for your build:
//   sim arm64:  "_sysconfigdata__ios_arm64-iphonesimulator"
//   sim x86_64: "_sysconfigdata__ios_x86_64-iphonesimulator"
//   device:     "_sysconfigdata__ios_arm64-iphoneos"
setenv("_PYTHON_SYSCONFIGDATA_NAME", "_sysconfigdata__ios_arm64-iphoneos", 1)

Py_Initialize()
PyEval_SaveThread()   // release GIL so manim's worker threads can run
```

### 6. (For LaTeX / Manim's MathTex) — point `offlinai_latex` at busytex

```swift
setenv("OFFLINAI_LATEX_BACKEND",       "busytex", 1)
setenv("OFFLINAI_LATEX_FORCE_BUSYTEX", "1",       1)
setenv("OFFLINAI_LATEX_USE_PDFTEX",    "0",       1)
```

(Bundle CodeBench's `Resources/Busytex/` and `BusytexEngine.swift` +
`LaTeXEngine.swift` per the LaTeX section earlier in this README.)

### 7. Verify

```python
import importlib.metadata
for d in importlib.metadata.distributions():
    print(d.metadata["Name"], d.version)
```

You should see ~30 distributions listed. If empty, your `PYTHONPATH`
isn't including the `python-ios-lib_*.bundle` paths — re-check step 5's
auto-discovery loop.

```python
import manim, numpy, scipy, sklearn, sympy, networkx, av, cairo
print("all imports ok")
```

If any line fails with `Trying to load an unsigned library` or
`Library not loaded: /tmp/ffmpeg-ios/...`, the Run Script in step 4
didn't run. Check Build Settings → `ENABLE_USER_SCRIPT_SANDBOXING = NO`
and that the script is in the build phases list.

---

## Bundle layout reference

After build, the .app contains:

```
YourApp.app/
├── YourApp                                     ← executable
├── Frameworks/
│   ├── Python.framework/Python                 ← BeeWare CPython dylib
│   ├── libfortran_io_stubs.dylib               ← from step 4.2
│   ├── libsf_error_state.dylib                 ← from step 4.2
│   ├── libscipy_blas_stubs.dylib               ← dcabs1 helper (scipy.linalg)
│   └── libav*.dylib, libsw*.dylib              ← FFmpeg, install_name fixed
├── python-stdlib/                              ← step 4.1 (BeeWare stdlib)
│   ├── os.py, json/, encodings/, …
│   ├── _sysconfigdata__ios_*.py
│   └── lib-dynload/*.so                        ← signed
├── python-ios-lib_NumPy.bundle/numpy/
├── python-ios-lib_Manim.bundle/{manim, manimpango, offlinai_latex,
│                                  svgelements, pathops, *-dist-info}
├── python-ios-lib_SciPy.bundle/scipy/
├── python-ios-lib_Sklearn.bundle/sklearn/
├── python-ios-lib_Matplotlib.bundle/matplotlib/
├── python-ios-lib_FFmpegPyAV.bundle/{av, ffmpeg/*.dylib}
├── python-ios-lib_CairoGraphics.bundle/{cairo, pango, harfbuzz}
├── python-ios-lib_Pillow.bundle/PIL/
└── python-ios-lib_*.bundle/                    ← 24+ more, one per ticked product
```

`PYTHONPATH` should include `python-stdlib/`, `python-stdlib/lib-dynload/`,
and every `python-ios-lib_*.bundle/` directory. Step 5's auto-discovery
loop handles that automatically.

---

## App Store distribution

Submitting an app with this package to App Store Connect surfaces
**~15 distinct categories** of `ITMS-9xxxx` validation errors,
because Apple's bundle rules don't accept the typical Python-iOS
layout that BeeWare's `install_python` produces.

This section documents every category we hit and how they're fixed.
There are **two classes** of rejection, and which fix you need depends on
**how you consume this package**:

- **(A) Loose Mach-O → `ITMS-90171` "binary file is not permitted".** Apple
  forbids any `.so`/`.dylib` that isn't inside a `.framework`. Every app hits
  this; the fix depends on your layout:
  - **Swift Package Manager** (you get `python-ios-lib_*.bundle/` +
    `python-stdlib/lib-dynload/`): use
    [`scripts/appstore/wrap-binaries-as-frameworks.sh`](scripts/appstore/wrap-binaries-as-frameworks.sh)
    + [`python_ios_lib_import_hook.py`](scripts/appstore/python_ios_lib_import_hook.py).
    It wraps every `.so` in `lib-dynload/` **and** the SPM bundles into
    `Frameworks/*.framework`, rewrites the cross-`LC_LOAD_DYLIB` references, and
    the import hook re-routes `import numpy._core…` to the framework at runtime.
  - **Manual `app_packages/` layout** (the CodeBench reference app, where
    BeeWare's binary-module signing already emits `.framework` + `.fwork`
    placeholders): use
    [`scripts/appstore/wrap-loose-dylibs.sh`](scripts/appstore/wrap-loose-dylibs.sh),
    which fixes up the `.fwork` paths and wraps the remaining loose dylibs.
- **(B) Content rejections** (private API, static `.a`, `MinimumOSVersion`,
  bitcode, `MH_BUNDLE`, macOS-only dylibs, standalone executables) depend on
  *which* libraries you bundle. `wrap-loose-dylibs.sh` carries a fix for each
  (table below); the same cleanups apply to either layout.

> **Note:** earlier revisions marked `wrap-binaries-as-frameworks.sh` as "no
> longer recommended" — that was wrong for SwiftPM consumers and is the root
> cause of the `ITMS-90171` reports. It is the **supported** path for the
> resource-bundle layout. Step-by-step in
> [App Store Connect submission](#app-store-connect-submission) below.

> TestFlight + dev (`Run`) builds work WITHOUT any of this. App Store
> submission is the only path that triggers Apple's strict validator.

### App Store Connect submission

For a **Swift Package Manager** app (the common case), these are the steps that
take an archive from `ITMS-90171`-rejected to accepted:

**1. Framework-wrap the loose `.so` (build phase).** Build Phases → + → New Run
Script Phase, shell `/bin/bash`, placed AFTER "Copy Bundle Resources" / your
stdlib-copy phase and BEFORE Xcode's implicit code-sign:

```sh
WRAP="${BUILD_ROOT}/../../SourcePackages/checkouts/python-ios-lib/scripts/appstore/wrap-binaries-as-frameworks.sh"
[ -f "$WRAP" ] && bash "$WRAP"
```

It wraps `python-stdlib/lib-dynload/*.so` and every
`python-ios-lib_*.bundle/**/*.so` into `Frameworks/<name>.framework/`, rewrites
cross-references, **flips each binary from `MH_BUNDLE` to `MH_DYLIB` and inserts
`LC_ID_DYLIB`**, **drops a `PrivacyInfo.xcprivacy` into the OpenSSL-linked
frameworks**, re-signs, and writes `python-ios-lib_extension_manifest.txt`
for the runtime hook.

> **The `MH_BUNDLE → MH_DYLIB` flip is mandatory.** Python `.so` extensions are
> Mach-O type `MH_BUNDLE`, and Apple's validator rejects a `.framework` whose
> executable is `MH_BUNDLE` — *"has type 'BUNDLE'… Only 'EXECUTE' is permitted"*
> (`90124`), *"missing load commands"* (`90210`), *"standalone library… not
> permitted"* (`90171`). The wrap script calls `scripts/appstore/fix-macho-type.py`
> automatically to do it, so **keep that file alongside `wrap-binaries-as-frameworks.sh`**
> (both ship in `scripts/appstore/`) and ensure `python3` is on the build machine.
> Wrapping the `.so` into a framework **without** this flip is the #1 cause of a
> still-rejected archive.

> **Privacy manifest (`ITMS-91061`).** Python's `_ssl` / `_hashlib` statically
> link **OpenSSL/BoringSSL**, a "commonly used third-party SDK" — so the wrapped
> `stdlib_ssl.framework` / `stdlib_hashlib.framework` must each carry a
> `PrivacyInfo.xcprivacy` or App Store Connect rejects with *"Missing privacy
> manifest"* (`ITMS-91061`). The wrap script copies the minimal manifest at
> [`scripts/appstore/PrivacyInfo.xcprivacy`](scripts/appstore/PrivacyInfo.xcprivacy)
> (no tracking, no data collection) into every OpenSSL-linked framework before
> re-signing — keep that file beside the script. If a later upload returns
> `ITMS-91053` ("missing required-reason API"), add the named reason code to the
> manifest's `NSPrivacyAccessedAPITypes` array.

**2. Install the runtime import hook.** Copy `python_ios_lib_import_hook.py`
into your bundled `python-stdlib/`, then in your embedding bootstrap —
immediately after `Py_Initialize()` and BEFORE any user import:

```c
setenv("PYTHON_IOS_LIB_HOOK_DIR",
       [[[NSBundle.mainBundle.bundleURL
          URLByAppendingPathComponent:@"python-stdlib"] path] UTF8String], 1);
PyRun_SimpleString(
    "import sys, os\n"
    "sys.path.insert(0, os.environ['PYTHON_IOS_LIB_HOOK_DIR'])\n"
    "import python_ios_lib_import_hook\n"
    "python_ios_lib_import_hook.install()\n");
```

The hook is **fail-safe**: if the manifest is absent (a dev `Run` build that
skipped step 1), `install()` is a no-op — so the same code path works for both
dev and release.

**3. C BLAS stub (only if you used the in-app stub route).** Adding
`blas_compat_stubs.c` to *Compile Sources* can fail with *"Module
'ObjectiveC.NSObject' requires feature 'objc'"* / *"Could not build module
'Foundation'"* — the `.c` file is inheriting the app's Objective-C prefix
header. Rename it to **`blas_compat_stubs.m`** (Objective-C is a superset of C),
or exclude it from the prefix header.

**4. Build Settings & Info.plist** (full list in the next table):
`ENABLE_USER_SCRIPT_SANDBOXING = NO`, `ENABLE_BITCODE = NO`,
`IPHONEOS_DEPLOYMENT_TARGET ≥ 17.0`, ExecuTorch xcframeworks set to **"Do Not
Embed"**, `ITSAppUsesNonExemptEncryption = false`, and — if `UIBackgroundModes`
contains `processing` — a `BGTaskSchedulerPermittedIdentifiers` array.

**5. Content rejections (category B).** Depending on the libraries you bundle
you may still trip the issues in the table below (private API, static `.a`,
`MinimumOSVersion`, `MH_BUNDLE`, …); apply the matching fix for each.

**6. dSYM warning.** *"Upload Symbols Failed: archive did not include a dSYM for
Python.framework"* is a **non-blocking warning**, not a rejection — the prebuilt
`Python.framework` ships without a dSYM. Untick **"Upload your app's symbols"**
in the Distribute flow, or ignore it.

Only an actual archive → App Store Connect (or TestFlight) upload runs Apple's
full validator, so verify there.

### Old vs new — what changed in the App Store path

| Issue | Old script | New `wrap-loose-dylibs.sh` |
|---|---|---|
| Loose `.so` in `app_packages/` | wrapped via `Frameworks/<name>.framework/` + import hook | same wrapping; **also** rewrites BeeWare's `.fwork` files to `@executable_path/Frameworks/...` (absolute paths) so iOS hardened-mode dyld accepts them |
| Loose `.dylib` in `Frameworks/` (FFmpeg, libtorch_python, libshm) | wrapped, refs rewritten | same |
| Static `.a` archives in `Frameworks/` (PyTorch ExecuTorch) | not handled | hard-deleted; ExecuTorch's xcframeworks must be set to "Do Not Embed" in Xcode (linker pulls symbols at compile time, not runtime) |
| `MinimumOSVersion` mismatch (BeeWare writes 13.0, binary is 17.0) | not handled | rewrites every wrapped framework's Info.plist `MinimumOSVersion` to match `IPHONEOS_DEPLOYMENT_TARGET` |
| `armv7` slice in fat binaries (e.g. `ios_system`) | not handled | strips armv7 via `lipo -remove` |
| `MH_BUNDLE` filetype on Cython `.so` | not handled | flips byte 12 of Mach-O header to `MH_DYLIB` (0x6); inserts `LC_ID_DYLIB` load command into padding |
| Bitcode segments left in vendored xcframeworks | not handled | `xcrun bitcode_strip -r` on every binary |
| `_CTFontCopyDefaultCascadeList` private API in `manimpango._register_font` | not handled | deletes the C extension; **fontTools-backed pure-Python `manimpango/__init__.py` shim** replaces all functionality (bundled in this package) |
| `_IOPSCopyPowerSourcesInfo` private API in `psutil._psutil_osx` | not handled | deletes the macOS-only C extension |
| `_xerbla_array__` flagged as private API in `scipy.linalg.cython_lapack` | not handled | renames symbol to `_xerbla_arr_io_` via Mach-O byte patching, adds an `LC_LOAD_DYLIB` to a runtime-built stub `.framework`, AND patches the bind opcodes + symbol-table `n_desc` to use flat-namespace lookup |
| macOS-arm64 dylibs in `scipy/.dylibs/` (libgfortran, libgcc_s, libquadmath) | not handled | hard-deleted (scipy never actually loads them on iOS — verified via `nm -u` symbol audit; Apple Accelerate provides the real BLAS/LAPACK) |
| `torch_shm_manager` standalone Mach-O executable | not handled | replaced with non-executable text placeholder (PyTorch's path-existence check passes; iOS forbids `fork()` so the real binary couldn't function anyway) |
| `LC_ENCRYPTION_INFO` missing on macOS dylibs | not handled | resolved indirectly by deleting the macOS dylibs |
| Native manimpango Cython `.so` files use Cairo's toy API which can't extract CJK glyph paths on iOS | not handled (CJK fell back to PIL rasterizer = opacity fade only, no stroke trace) | **fontTools shim reads OTF outlines directly** — produces real bezier `<path>` data per glyph; manim's `Write` traces strokes natively for CJK exactly like Latin |
| `torch._C` not injected into `torch` module namespace at import time | not handled | one-line patch in `torch/__init__.py` (`import torch._C as _C`) makes `torch._C` a regular module attribute regardless of what PyInit__C did |
| `manim.animation.animation.Animation.interpolate_mobject` ignored `lag_ratio` for ImageMobject children | not handled (CJK Text faded as a single block) | manim's iOS image-fallback patch now uses `get_sub_alpha(...)` per-child, producing proper typewriter-style staggered reveal |

### Setup — drop-in build phase

After the existing stdlib-copy Run Script (step 4 of the Setup), add
a NEW Run Script Phase. **Build Phases → + → New Run Script Phase**,
shell `/bin/bash`:

```sh
WRAP="${BUILD_ROOT}/../../SourcePackages/checkouts/python-ios-lib/scripts/appstore/wrap-loose-dylibs.sh"
[ -f "$WRAP" ] && bash "$WRAP"
```

Place AFTER "Copy Bundle Resources" + the stdlib-copy phase, BEFORE
Xcode's final implicit code-sign step.

The script also needs two helpers in the same dir, which the wrap
script auto-locates via `${PROJECT_DIR}/scripts/`:
- [`fix-macho-type.py`](scripts/appstore/fix-macho-type.py) — flips
  MH_BUNDLE → MH_DYLIB and inserts LC_ID_DYLIB
- [`patch-cython-lapack.py`](scripts/appstore/patch-cython-lapack.py)
  — renames `_xerbla_array__` symbol + adds LC_LOAD_DYLIB + patches
  bind opcodes for flat-namespace lookup

For convenience, copy them next to the wrap script in your project's
`scripts/` directory.

### Setup — required Xcode build settings

| Setting | Value | Why |
|---|---|---|
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` | wrap script needs to write outside its own Build dir |
| `ENABLE_BITCODE` | `NO` (or unset; default in Xcode 14+) | bitcode is deprecated and our strip step assumes it's gone |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.0` (or higher) | wrap script harmonizes framework `MinimumOSVersion` to this value |
| ExecuTorch xcframeworks (`executorch`, `backend_xnnpack`, `backend_coreml`, `kernels_optimized`, `threadpool`) | **"Do Not Embed"** in Frameworks, Libraries, and Embedded Content | static `.a` archives — link at compile time, never embed |
| `Info.plist` → `ITSAppUsesNonExemptEncryption` | `<false/>` | skips the encryption-questionnaire prompt every upload (only standard TLS via OpenSSL) |

### What the wrap script outputs in the build log

```
=== wrap-loose-dylibs.sh starting ===
  BUILT_PRODUCTS_DIR=...
  CODESIGNING_FOLDER_PATH=...

wrap-loose-dylibs: Step 0 — hard cleanup of App Store-rejected files
  removed .../numpy/_core/lib/libnpymath.a
  removed .../torch/bin/torch_shm_manager (then re-created as text placeholder below)
  ... (10-15 files)

wrap-loose-dylibs: Step 0b — harmonizing MinimumOSVersion to 17.0
  fixed MinimumOSVersion in 262 framework Info.plists

wrap-loose-dylibs: Step 0b2 — stripping armv7 from fat framework binaries
  stripped armv7 from ios_system.framework
  1 framework(s) thinned to arm64-only

wrap-loose-dylibs: Step 0b3 — rewriting .fwork files to absolute paths
  rewrote 264 .fwork files (skipped 0 already-absolute)

wrap-loose-dylibs: Step 0c — patching scipy cython_lapack for App Store
  built libscipy_lapack_stubs.dylib
  renamed 2 occurrence(s) of _xerbla_array__ → _xerbla_arr_io_
  added LC_LOAD_DYLIB → @rpath/libscipy_lapack_stubs.framework/...
  rewrote 2 bind entry(s) to flat-namespace lookup

wrap-loose-dylibs: 11 loose dylibs to wrap
wrap-loose-dylibs: stripping bitcode from binaries
  stripped bitcode from 275 binaries
wrap-loose-dylibs: flipping MH_BUNDLE → MH_DYLIB
  fix-macho-type summary:  140 already_dylib, 133 patched, 1 patched_fat
  LC_ID_DYLIB: 133 added, 140 already present, 1 failed

=== wrap-loose-dylibs: final App Store readiness check ===
  ✓ static .a archives clean
  ✓ loose .dylib in Frameworks/ clean
  ✓ loose .dylib in app_packages/ clean
  ✓ torch_shm_manager is text placeholder (App Store-safe)
  ✓ manimpango native .so (CTFontCopyDefaultCascadeList) clean
  ✓ psutil._psutil_osx (IOPSCopyPowerSources*) clean
✓ App Store readiness OK
```

If any check fails, the script exits non-zero and Xcode flags the
build phase as failed — preventing you from accidentally archiving
a known-bad bundle.

### Python-side patches that ship with this package

The repo bundles **already-patched copies** of three site-packages
files — these replace the upstream versions and ship inside the
package's `app_packages/site-packages/` tree:

| Patched file | What it fixes |
|---|---|
| [`manimpango/__init__.py`](app_packages/site-packages/manimpango/__init__.py) | Native `_register_font.so` and `cmanimpango.so` (deleted by wrap script for ITMS-90338) — replaced with **fontTools-based pure-Python text2svg** that reads OTF/TTF glyph outlines directly via `SVGPathPen`. CJK Text in manim now produces real `<path d="...">` per glyph (typewriter-style `Write` animation works). Bundled `fontTools/` (~5 MB pure Python) provides the implementation. |
| [`manim/animation/animation.py`](app_packages/site-packages/manim/animation/animation.py) | The iOS image-fallback in `interpolate_mobject` now staggers `ImageMobject` opacity by `lag_ratio` (matching what `Write`'s smart `lag_ratio = min(4.0/N, 0.2)` expects) — produces proper typewriter reveal across per-character ImageMobject children. Was previously fading all chars at the same alpha. |
| [`torch/__init__.py`](app_packages/site-packages/torch/__init__.py) | Two iOS-specific patches: (1) `import torch._C as _C` after `from torch._C import *` so `torch._C` is in module namespace even when PyInit__C's re-entrant `setattr` silently fails on iOS. (2) `manager_path()` returns the `torch_shm_manager` text-placeholder path instead of raising `RuntimeError("Unable to find...")` when the binary was replaced. Lets full PyTorch import succeed; only `torch.multiprocessing`'s fork-based APIs are unavailable (iOS platform limit). |

The `fontTools/` directory is bundled at [`app_packages/site-packages/fontTools/`](app_packages/site-packages/fontTools/) — required by the patched manimpango shim. It's ~4.8 MB pure Python (no C extensions needed; the SVGPathPen + ttLib paths we use don't require the optional Cython accelerators).

### Verify locally before archiving

```sh
bash scripts/appstore/wrap-loose-dylibs.sh   # dry run requires Xcode env vars
# Better: actually archive and inspect the build log for "✓ App Store readiness OK"
```

The script's final assertion fails the build if any rejected file
remains, so you can never accidentally upload a broken bundle.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `Trying to load an unsigned library` on first numpy/scipy import | SwiftPM strips signatures from `.so` resources | Run Script in step 4 must re-sign all `.so` |
| `symbol not found in flat namespace '_dcabs1_'` importing `scipy.signal` / `scipy.linalg` on a real device | Apple's Accelerate doesn't export the reference-BLAS helper `dcabs1` (only `cython_blas` needs it — `lsame` IS in Accelerate) | ships `Frameworks/scipy_aux/libscipy_blas_stubs.dylib` providing it + an `LC_LOAD_DYLIB` on `cython_blas.so` so the flat lookup resolves. Already baked into the bundled `.so`; re-run `scripts/appstore/build-blas-stubs.sh` after rebuilding scipy. |
| `Library not loaded: /tmp/ffmpeg-ios/install/lib/libavcodec.62.dylib` | PyAV `.so` has hardcoded build-time install_names | `install_name_tool -change` step in step 4.4 |
| `AttributeError: 'installed_base'` from inside `pydoc` | BeeWare per-arch `_sysconfigdata` not on `sys.path` | Step 4.1 copies it; step 5 sets `_PYTHON_SYSCONFIGDATA_NAME` |
| `ModuleNotFoundError: No module named 'cloup'` (or click, tqdm, rich, …) | Transitive dep wasn't auto-linked from `Manim` | Verify with the bundle layout — every product in step 3 should have a corresponding `python-ios-lib_*.bundle` dir; if missing, tick it explicitly in Xcode |
| `Error importing numpy: you should not try to import numpy from its source directory` | numpy's `_multiarray_umath.so` failed to load (usually unsigned) | Re-check the codesign loop output in build log |
| Empty `importlib.metadata.distributions()` | Your earlier Package.swift didn't ship `*.dist-info` dirs as resources | Fixed in current Package.swift |
| Render appears to hang | iOS jetsam killing for memory pressure | `PYTHONMALLOC=malloc` is set in step 5; lower preview quality, avoid long `MathTex` chains |
| App Store: `Invalid bundle structure. The 'X.so' binary file is not permitted.` (`ITMS-90171`) | Apple rejects loose Mach-O outside `.framework/`; SwiftPM ships `.so` loose in `python-ios-lib_*.bundle/` + `python-stdlib/lib-dynload/` | Run `wrap-binaries-as-frameworks.sh` + load `python_ios_lib_import_hook.py` — see [App Store Connect submission](#app-store-connect-submission) |
| `Library not loaded: @rpath/<lib>.dylib` (e.g. `libfortran_io_stubs.dylib`) crashing on a **real device** after wrapping (field report [#2](https://github.com/yu314-coder/python-ios-lib/issues/2)) | A bare `@rpath/<basename>.dylib` cross-dep wasn't rewritten to its wrapped `loose_<name>.framework`, so dyld can't find it | `rewrite_cross_refs` now also probes `Frameworks/` on disk for the wrapped `loose_<stem>` framework as a fallback — pull the latest `scripts/appstore/wrap-binaries-as-frameworks.sh`. Also confirm the loose dylib lands in `<App>.app/Frameworks/` **before** the wrap phase runs, and that the referencing binary carries `@executable_path/Frameworks` + `@loader_path/..` rpaths (the script adds both). |
| `IndentationError: unexpected indent` at ~line 27 of `python_ios_lib_import_hook.py` (field report [#2](https://github.com/yu314-coder/python-ios-lib/issues/2)) | The file's leading `"""docstring"""` got mangled during copy (delimiters lost), so its indented usage example parses as code | Copy `scripts/appstore/python_ios_lib_import_hook.py` **verbatim** (don't hand-retype or reflow it), or delete the leading docstring block (it's purely documentation). Install it with the `\n`-joined `PyRun_SimpleString("import sys, os\n" …)` form in [step 2](#app-store-connect-submission) — **not** an indented `"""…"""` heredoc, which itself triggers this error. |
| App Store: `Missing Info.plist value. The Info.plist key 'BGTaskSchedulerPermittedIdentifiers' must contain a list of identifiers when 'UIBackgroundModes' has a value of 'processing'.` | Required when `UIBackgroundModes` includes `processing` | Add `BGTaskSchedulerPermittedIdentifiers` array to your Info.plist |
| `Upload Symbols Failed: archive did not include a dSYM for X.dylib` | Release archive is missing debug symbols | Build Settings → Debug Information Format = `DWARF with dSYM File` for Release; not a rejection — just no crash symbolication |
| `Unicode{Encode,Decode}Error: 'ascii' codec …` reading/writing a non-ASCII file with a plain `open(p)` / `open(p,'w')` | iOS C locale is ASCII and bare `Py_Initialize()` ignores `PYTHONUTF8` → `sys.flags.utf8_mode == 0` → `open()` defaults to ASCII (stdout is fine — it's a custom UTF-8 writer) | Bundled `sitecustomize.py` (`_install_utf8_open_default`) wraps `open` / `io.open` to default text mode to UTF-8, covering `pathlib.read_text` / `write_text`. Embedding the runtime yourself? Pass `encoding="utf-8"` explicitly, or set `PyConfig.utf8_mode = 1` before `Py_InitializeFromConfig`. |

---

## Available products (29 in Xcode's checklist)

Pick whichever combination you need. Dependencies auto-resolve.

### Standalone packages (no dependencies)

| Package | What you get | Doc |
|---|---|---|
| **CInterpreter** | C89/C99/C23 tree-walking interpreter (~3,661 lines) | [doc](docs/c-interpreter.md) |
| **CppInterpreter** | C++ interpreter — classes, STL, templates, inheritance (~4,287 lines) | [doc](docs/cpp-interpreter.md) |
| **FortranInterpreter** | Fortran via [ofort](https://github.com/Beliavsky/ofort) (Beliavsky, MIT) — modules, allocatable arrays, 45+ intrinsics | [doc](docs/fortran-interpreter.md) |
| **NumPy** | NumPy 2.3.5 — arrays, linalg, FFT, random (native iOS) | [doc](docs/numpy.md) |
| **SymPy** | SymPy 1.14 — symbolic math, calculus, solving | [doc](docs/sympy.md) |
| **Plotly** | Plotly 6.6 — interactive charts, 3D plots | [doc](docs/plotly.md) |
| **NetworkX** | NetworkX 3.6 — graph theory, algorithms | [doc](docs/networkx.md) |
| **Pillow** | Pillow 12.2 — image processing (native iOS) | [doc](docs/pillow.md) |
| **BeautifulSoup** | BeautifulSoup4 — HTML/XML parsing | [doc](docs/beautifulsoup.md) |
| **Requests** | HTTP client (GET, POST, sessions, JSON) | [doc](docs/requests.md) |
| **PyYAML** | YAML parser (native iOS) | [doc](docs/pyyaml.md) |
| **Rich** | Rich text, tables, progress bars | [doc](docs/rich.md) |
| **Tqdm** | Progress bars for loops | [doc](docs/tqdm.md) |
| **Click** | CLI framework | [doc](docs/click.md) |
| **Pygments** | Syntax highlighting (500+ languages) | [doc](docs/pygments.md) |
| **Mpmath** | Arbitrary-precision arithmetic | [doc](docs/mpmath.md) |
| **Pydub** | Audio manipulation | [doc](docs/pydub.md) |
| **JsonSchema** | JSON Schema validation | [doc](docs/jsonschema.md) |
| **CairoGraphics** | Cairo + Pango + HarfBuzz (2D graphics, native iOS) | [doc](docs/cairographics.md) |
| **FFmpegPyAV** | FFmpeg (7 dylibs) + PyAV video encoding (native iOS) | [doc](docs/ffmpeg-pyav.md) |
| **Decorator** | Michele Simionato's full `decorator` package (5.3.1, pure Python) — `decorator` / `contextmanager` / `dispatch_on` | [doc](docs/decorator.md) |
| **PyWebView** | pywebview shim — embed HTML/CSS/JS UI in your iOS app from Python via the host's preview pane (full cookie API + file IPC) | [doc](docs/pywebview.md) |
| **Werkzeug** | WSGI utilities + dev server (3.1.x, 52 modules). iOS-patched: `multiprocessing.Value` fallback, reloader auto-disable, preview-signal hook, clean-shutdown hook | [doc](docs/werkzeug.md) · [stack](docs/web-stack.md) |
| **Tornado** | Async HTTP/WebSocket framework (6.5.x, 73 modules). Pure-Python; macOS `speedups.abi3.so` stripped, transparent Python fallback. Streamlit's transport, usable standalone | [doc](docs/tornado.md) · [stack](docs/web-stack.md) |

### Packages with dependencies (auto-included when you select)

| Package | What you get | Auto-includes | Doc |
|---|---|---|---|
| **Sklearn** | scikit-learn (40 modules, 12K+ lines) | + NumPy | [doc](docs/sklearn.md) |
| **SciPy** | SciPy (optimize, integrate, signal, stats) | + NumPy | [doc](docs/scipy-ios.md) |
| **Matplotlib** | REAL matplotlib 3.11 (C extensions: ft2font, Agg, contourpy, kiwisolver) + plotly interactive showcase | + Plotly | [doc](docs/matplotlib.md) |
| **Manim** | manim (145+ mobjects, 73 animations) | + NumPy, Matplotlib, FFmpegPyAV, CairoGraphics | [doc](docs/manim.md) |
| **LaTeXEngine** | pdftex.xcframework + 33 MB bundled texmf tree (Latin Modern, amsmath, hyperref, expl3, …). `\documentclass{article}` end-to-end. | + CairoGraphics | [doc](docs/latex-engine.md) |
| **Flask** | Web framework (3.x, 24 modules) on Werkzeug — routes, sessions, templates, blueprints | + Werkzeug, Jinja2, Markupsafe, Click | [doc](docs/flask.md) · [stack](docs/web-stack.md) |
| **Dash** | Plotly-based reactive dashboards (3.x, 211 modules) — callbacks, charts, tables, dcc + html components | + Flask, Werkzeug, Jinja2, Markupsafe, Click, Plotly | [doc](docs/dash.md) · [stack](docs/web-stack.md) |
| **Streamlit** | Script-style dashboards (1.50.x, 213 modules) — declarative widgets, `@st.cache_data`. iOS-patched: signal-handler skip, preview hook, clean shutdown | + Tornado, Click, Watchdog, Typing_extensions, PyArrow | [doc](docs/streamlit.md) · [stack](docs/web-stack.md) |

### Machine Learning stack (PyTorch + HuggingFace)

First public iOS builds of each. Once added, `import torch`, `import transformers`, `import tokenizers` all work on-device with no extra setup.

| Package | What you get | Auto-includes | Doc |
|---|---|---|---|
| **PyTorch** | PyTorch 2.1.0 native iOS — tensors, autograd, nn, optim, JIT, FFT, LAPACK via Accelerate, plus a transparent Metal/MPS bridge for large matmul / attention. **95/95 correctness asserts.** Ships `libtorch_python.dylib` as a ~14 MB LZMA blob (`Sources/PyTorch/torch_dylib/libtorch_python.dylib.applzma`); the `PyTorch` Swift package decompresses it to ~99 MB at first launch via `Compression.framework`. No Git LFS needed. | regex shim | [doc](docs/torch.md) |
| **Tokenizers** | HuggingFace tokenizers 0.19.1 — real Rust BPE/WordPiece/Unigram trainers cross-compiled for iOS arm64 (PyO3). First public iOS build. | (none) | [doc](docs/tokenizers.md) |
| **Transformers** | HuggingFace transformers 4.41.2 — BERT, GPT-2, T5, BART, Llama, Qwen. Construct + train + `.generate()` + save/load on-device. | + PyTorch, Tokenizers, `huggingface_hub`, `filelock`, `safetensors`, `accelerate`, `peft` | [doc](docs/transformers.md) |
| **Accelerate** | HuggingFace Accelerate 0.30.1 — `Trainer` hard-imports it for device placement, gradient accumulation, mixed precision. Pure Python. | (none extra) | upstream [docs](https://huggingface.co/docs/accelerate) |
| **PEFT** | HuggingFace PEFT 0.12.0 — `LoraConfig` + `get_peft_model` for LoRA / IA3 / prefix tuning. Pure Python. | + Transformers | upstream [docs](https://huggingface.co/docs/peft) |

The `safetensors` shim is bidirectional: both `load_file` and `save_file` work, so `model.save_pretrained()` and `peft.save_pretrained()` write valid `.safetensors` files that load back bit-identical (verified via roundtrip test with fp16/bf16/fp32/int64/bool tensors).

**Now bundled** (added since the first release, all device-verified): `datasets` 4.0.0, `evaluate` 0.4.6, `sentencepiece` (the Llama/T5/BART tokenizers), `protobuf` 5.29.6, `pyarrow` 15.0.2 (minimal build — Arrow IPC works, no `.parquet`), and `torch.utils.tensorboard.SummaryWriter`. See the [Machine Learning stack](#machine-learning-stack-bundled) list above for per-library caveats. What's still out is only what iOS physically can't do: CUDA kernels (`bitsandbytes`; `flash-attn`/`xformers` get SDPA-backed API shims so they import + run on GPU), JIT (`triton`, `torch.compile`), and fork-based multiprocessing (`DataLoader(num_workers>0)`, `deepspeed`, `fairscale`).

### GPU acceleration for PyTorch (Metal bridge)

`app_packages/site-packages/_torch_metal_bridge.py` patches `torch.matmul`, `torch.mm`, `torch.bmm`, `torch.addmm`, `F.linear`, and `F.scaled_dot_product_attention` to route matmul-heavy ops onto the iPad GPU via `MPSMatrixMultiplication`. Auto-installed at Python startup by `sitecustomize.py` — no code changes required. Supports float32 and float16 natively; bfloat16 is cast to fp32 internally. Typical speedup at transformer training sizes: **2–10× on iPad** (CPU on iPad has no AMX, unlike Mac Apple Silicon). The Swift bridge (`CodeBench/MetalMatmulBridge.swift`) exposes one C entry point via `@_cdecl` and ctypes reaches it through `dlopen(NULL)` — `OTHER_LDFLAGS` exports the symbol explicitly so it survives TestFlight / App Store stripping.

### NumPy / safetensors shims

iOS PyTorch was compiled with `USE_NUMPY=0` to keep the binary self-contained, so `torch.from_numpy()` and `tensor.numpy()` raise. `sitecustomize.py` installs pure-Python replacements using `torch.frombuffer` — drop-in equivalents with correct dtype mapping for fp16/bf16/uint16-64. `safetensors` (normally Rust + PyO3, not cross-compiled for iOS) is also re-implemented in pure Python over `mmap` for read paths, which is what `transformers.from_pretrained` actually uses.

### Standard HuggingFace scripts work unchanged on iPad

The whole point of this stack is that a training script written for Mac/Windows runs on iPad without modification. Two automatic patches in [`sitecustomize.py`](app_packages/site-packages/sitecustomize.py) make this work:

**1. iOS background-time extension** — applied at every Python startup. `UIApplication.beginBackgroundTask` is requested via the Swift `@_cdecl` bridge in [`CodeBench/BackgroundTimeManager.swift`](https://github.com/yu314-coder/CodeBench/blob/main/CodeBench/BackgroundTimeManager.swift), so when the user backgrounds the app mid-training, iOS grants extra time instead of suspending immediately. No-op on macOS/Linux (no UIKit), so the same Python script behaves correctly cross-platform. Disable with `CODEBENCH_AUTO_BACKGROUND=0`.

**2. `transformers.TrainingArguments` defaults** — patched via a `sys.meta_path` import hook (zero startup cost; only fires when the user imports `transformers`). Injects iPad-friendly defaults:

| Field | HF default | iPad default | Why |
|---|---|---|---|
| `save_steps` | 500 | **100** | Checkpoint more often so iOS suspension loses less progress |
| `save_total_limit` | None (unlimited) | **3** | Cap disk use |
| `Trainer.train(resume_from_checkpoint=)` | None | **auto-detect** | If `output_dir` has `checkpoint-*/` subdirs, resume from the latest one without requiring an explicit argument |

User-specified values always win (setdefault semantics; explicit `resume_from_checkpoint=False` is also respected). Disable with `CODEBENCH_AUTO_CHECKPOINT=0`.

The net effect: a vanilla HF training script —

```python
from transformers import TrainingArguments, Trainer
args = TrainingArguments(output_dir="./run-1")
trainer = Trainer(model=model, args=args, train_dataset=ds)
trainer.train()           # on iPad: auto-checkpoint every 100 steps,
                          # auto-resume on crash/relaunch
```

— runs unchanged on Mac/Windows (with whatever HF defaults that platform implies) and on iPad (with the patched defaults plus auto-resume on relaunch).

### Manual-loop helpers — `_cb_training.py` (opt-in)

For training loops that don't use HF `Trainer`, five extra utilities are available via explicit import:

- **`OOMGuard`** — auto-halves batch size and retries on out-of-memory.
- **`MemoryProfiler`** — RSS snapshots between named checkpoints.
- **`KVCache`** — per-layer key/value cache for autoregressive inference.
- **`TrainingMonitor`** — terminal dashboard: loss/it-s/ETA/RAM/GPU dispatches.
- **`AutoCheckpointer`** — periodic save + auto-resume for hand-rolled loops.

These are NOT auto-installed — vanilla HF scripts don't need them. Import them only if you're writing a training loop without `Trainer`.

### LoRA → GGUF export — standalone CLI

Closes the train→deploy loop. After training a LoRA via PyTorch + HF Trainer (with the Metal bridge for speed), convert the resulting `.pt` to a GGUF adapter for fast Metal-accelerated inference in llama.cpp. Pure-Python writer, no external deps:

```bash
python -m _cb_gguf_export --pt ./run-1/checkpoint-500/adapter_model.pt \
                          --gguf ./qwen-lora.gguf --arch qwen2 --alpha 16
```

Supports Qwen / Llama / Mistral / Phi-family modules (`attn_q/k/v/output`, `ffn_gate/up/down`). For other architectures, extend `_MODULE_MAP`.

### After adding the package

The Python files are bundled as resources. Copy them to your app's `site-packages/` at runtime:

```swift
import PythonSklearn  // or whichever package

// Get the bundled resource path
if let path = PythonIOSLib.resourcePath {
    // Copy to your Python site-packages directory
    let sitePackages = documentsURL.appendingPathComponent("site-packages")
    try? FileManager.default.copyItem(atPath: path + "/sklearn", 
                                       toPath: sitePackages.path + "/sklearn")
}
```

### LaTeX engine — for FULL LaTeX, use busytex (this package's default is incomplete)

> **TL;DR — if you actually want LaTeX to work, swap in busytex.** The
> bundled `LaTeXEngine` (offlinai_latex + native pdftex.xcframework) is
> not a complete LaTeX implementation and will fail on most real-world
> documents. CodeBench itself does NOT rely on it — it ships busytex
> for exactly this reason. Section below tells you how to do the same.

What ships in this package's `LaTeXEngine` product:
- `pdftex.xcframework` — a stale-ish (2019-era) native pdftex binary
- `kpathsea.xcframework` + `ios_system.xcframework` — POSIX shim layer
- a minimal 48 MB texmf tree (Latin Modern, amsmath, hyperref,
  graphics-def, hyphenation, expl3, …)
- `offlinai_latex` Python bridge — what manim's `MathTex` / `Tex` calls

**Why it's not "full":**
- `pdflatex foo.tex` for a `\documentclass{article}` document is
  gated off (the bundled pdftex.xcframework crashes on modern
  `latex.ltx`)
- `MathTex` works for simple math (`\sin x`, `\frac{a}{b}`, AMS
  symbols, matrices) but breaks on tikz, chemistry, fancy font
  substitutions, anything needing texlive packages outside the
  ~48 MB tree
- The `ios_system` PTY emulator that pdftex shells through breaks
  outright on Mac "Designed for iPad" / Mac Catalyst (macOS sandbox
  blocks the fork-like syscalls)

What CodeBench uses instead — and what you should use for full LaTeX:
**busytex**, a WebAssembly build of pdflatex that runs inside a hidden
WKWebView with the full texlive tree (basic + latex-base + latex-extra
+ latex-recommended + fonts-recommended + science). Compiles real
`\documentclass{...}` documents end-to-end, handles tikz, chem,
biblatex, the works.

|                | Bundled offlinai_latex / native pdftex | Busytex (recommended) |
|---|---|---|
| `MathTex(r"\sin x")` | works | works |
| `MathTex(r"\begin{tikzpicture}…")` | fails | works |
| `pdflatex foo.tex` (full document) | gated off (pdftex crashes) | works |
| Texlive package coverage | ~48 MB minimal | full distribution |
| Mac "Designed for iPad" / Catalyst | broken (sandbox kills ios_system) | works |
| Real iOS device | partial | works |
| Cold start | ~50 ms | ~1 s |
| Per-render speed | ~80 ms (when it works) | ~500 ms |
| Bundle cost | ~48 MB | ~58 MB minimum / ~237 MB full texlive |

#### Adding busytex to your app

1. Grab the busytex assets from CodeBench's repo:
   ```sh
   git clone --depth 1 https://github.com/yu314-coder/CodeBench /tmp/cb
   ```
2. Copy `/tmp/cb/CodeBench/Resources/Busytex/` into your iOS app
   target's resources. Two sizing options:

   **Full (~237 MB)** — handles every texlive package CodeBench ships
   (basic + latex-base + latex-extra + latex-recommended + fonts +
   science). Recommended if you want the same "full LaTeX works" UX
   as CodeBench:
   ```
   cp -R /tmp/cb/CodeBench/Resources/Busytex YourApp/Resources/
   ```

   **Minimum viable (~58 MB)** — covers MathTex + simple `\documentclass{article}`
   docs. Drop tikz/chem/fancy fonts. Copy only:
   ```
   busytex.html / busytex.js / busytex.wasm
   busytex_pipeline.js / busytex_worker.js
   dvipdfmx.cfg / texmf.cnf / updmap.cfg / versions.txt
   offlinai-texmf.{data,js}                  ← Computer Modern + AMS
   ubuntu-texlive-latex-base.{data,js}       ← article/standalone classes
   ```
3. Copy `/tmp/cb/CodeBench/BusytexEngine.swift` and the relevant pieces of
   `LaTeXEngine.swift` (the `checkForMathCompileRequest` poller — see
   line 686+) into your app's Swift source. These wire Python's compile
   signals to the WKWebView running busytex.
4. At app launch, call `BusytexEngine.shared.preload()` so the WASM
   engine boots before the first MathTex.
5. Tell `offlinai_latex` to route to busytex:
   ```python
   import os
   os.environ["OFFLINAI_LATEX_BACKEND"] = "busytex"
   ```

#### Why we don't bundle busytex into this SPM package

The full texlive bundle is 237 MB; even the minimum viable subset is
~58 MB. Forcing every SPM consumer to download that — including
people who just want NumPy or Sklearn — would bloat the package
unreasonably. Keeping busytex as a manual copy step lets you opt in
only when you actually need real LaTeX.

If you only care about programmatic Math display (no `MathTex`,
no full documents), `LaTeXEngine` doesn't have to be linked at all
— just don't tick it in Xcode's product picker.

---

### C Interpreters (no Python needed)

```swift
import CInterpreter

let interp = occ_create()
defer { occ_destroy(interp) }

occ_execute(interp, """
#include <stdio.h>
int main() {
    printf("Hello from C on iOS!\\n");
    return 0;
}
""")
print(String(cString: occ_get_output(interp)))
```

---

## Dependency Graph

```
PythonManim
  ├── FFmpegPyAV (video encoding)
  ├── CairoGraphics (2D rendering)
  ├── LaTeXEngine (math typesetting)
  └── PythonMatplotlib (plotting)
        └── plotly (pure Python, install separately)

PythonSklearn → numpy (iOS wheel)
PythonScipy → numpy (iOS wheel)
PythonMatplotlib → plotly (pure Python)
CInterpreter → (standalone)
PythonRequests → (standalone)

Transformers
  ├── PyTorch (14 MB LZMA blob → 99 MB dylib at runtime)
  │     └── regex (shim)
  └── Tokenizers (5 MB Rust .so)
Transformers also bundles huggingface_hub, filelock, safetensors
```

---

## Not bundled — install via `pip` if you need them

CodeBench ships a patched `pip` that installs pure-Python wheels on-device into the per-workspace site-packages. **Two categories**:

✅ **Pure-Python — typically installs fine via `pip install <name>`:**
- `diffusers` — Stable Diffusion / etc. (note: inference may be slow; better via ExecuTorch)
- `trl` — RLHF / DPO trainers built on transformers + accelerate (both bundled)
- `wandb-core` Python parts — but no network sync without internet
- `bertopic`, `umap-learn`, `gensim` — most NLP utility libs
- Generally: anything whose wheel contains only `.py` files

❌ **Has C / Rust / CUDA extensions not cross-compiled for iOS arm64 — pip install will FAIL or import will crash:**

| Package | Reason | Workaround |
|---|---|---|
| **`bitsandbytes`** | CUDA-only quantization kernels | Use llama.cpp GGUF Q4/Q8 quantization for inference |
| **`flash-attn`**, **`xformers`** | CUDA-only attention kernels — don't pip-install them | Already bundled as SDPA-backed API shims (`flash_attn_func`, `memory_efficient_attention` run on GPU via the bridge) |
| **`triton`** | LLVM JIT codegen | iOS forbids JIT; no equivalent |
| **`deepspeed`**, **`fairscale`** | Multi-GPU training infrastructure | Single-device on iPad; not applicable |
| **`polars`** | Rust DataFrame core | Use the bundled `pandas` instead |

---

## Documentation index — every bundled package

Every Python library + native engine + interpreter shipped here has a
documentation file in `docs/`. Each file covers usage examples, iOS-specific
notes, limitations, troubleshooting, and build provenance.

### Interpreters (no Python runtime needed)

| Lang | Doc |
|---|---|
| **C** | [docs/c-interpreter.md](docs/c-interpreter.md) |
| **C++** | [docs/cpp-interpreter.md](docs/cpp-interpreter.md) |
| **Fortran** | [docs/fortran-interpreter.md](docs/fortran-interpreter.md) + [docs/fortran-runtime.md](docs/fortran-runtime.md) |

### Native engines (C/C++ libs)

| Engine | Doc |
|---|---|
| **CairoGraphics** (Cairo + Pango + HarfBuzz + FreeType + GLib + libffi) | [docs/cairographics.md](docs/cairographics.md) |
| **FFmpeg + PyAV** (video encode/decode, VideoToolbox H.264) | [docs/ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| **LaTeXEngine** (pdftex.xcframework + 33 MB texmf) | [docs/latex-engine.md](docs/latex-engine.md) |

### Scientific computing

| Library | Doc |
|---|---|
| **NumPy** | [docs/numpy.md](docs/numpy.md) |
| **SciPy** | [docs/scipy-ios.md](docs/scipy-ios.md) |
| **SymPy** | [docs/sympy.md](docs/sympy.md) |
| **mpmath** | [docs/mpmath.md](docs/mpmath.md) |
| **NetworkX** | [docs/networkx.md](docs/networkx.md) |
| **scikit-learn** | [docs/sklearn.md](docs/sklearn.md) |

### Machine learning

| Library | Doc |
|---|---|
| **PyTorch** (14 MB LZMA blob → 99 MB dylib at runtime) | [docs/torch.md](docs/torch.md) |
| **transformers** | [docs/transformers.md](docs/transformers.md) |
| **tokenizers** (Rust via PyO3) | [docs/tokenizers.md](docs/tokenizers.md) |
| **safetensors** | [docs/safetensors.md](docs/safetensors.md) |
| **huggingface_hub** | [docs/huggingface-hub.md](docs/huggingface-hub.md) |

### Visualization

| Library | Doc |
|---|---|
| **matplotlib** (REAL 3.11 + plotly showcase) | [docs/matplotlib.md](docs/matplotlib.md) |
| **onnxruntime** (CoreML EP) | [docs/onnxruntime.md](docs/onnxruntime.md) |
| **Plotly** | [docs/plotly.md](docs/plotly.md) |
| **manim** | [docs/manim.md](docs/manim.md) |
| **manim deps** (pathops + mapbox_earcut + isosurfaces) | [docs/manim-deps.md](docs/manim-deps.md) |
| **manimpango** | [docs/manimpango.md](docs/manimpango.md) |

### 3D content creation

| Library | Doc |
|---|---|
| **bpy** (Blender — Cycles **and Eevee** on Metal GPU + a working `gpu` module + OpenImageDenoise) | [docs/blender-bpy.md](docs/blender-bpy.md) |

### Media (image / audio / video)

| Library | Doc |
|---|---|
| **Pillow / PIL** | [docs/pillow.md](docs/pillow.md) |
| **PyAV** | [docs/av-pyav.md](docs/av-pyav.md) — also [docs/ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| **pydub** (audio, uses audioop) | [docs/pydub.md](docs/pydub.md) |
| **audioop** (LTS backport — removed from Python 3.13 stdlib) | [docs/audioop.md](docs/audioop.md) |
| **svgelements** | [docs/svgelements.md](docs/svgelements.md) |

### Web & network

| Library | Doc |
|---|---|
| **requests** | [docs/requests.md](docs/requests.md) |
| **urllib3** | [docs/urllib3.md](docs/urllib3.md) |
| **BeautifulSoup4** | [docs/beautifulsoup.md](docs/beautifulsoup.md) |
| **certifi** (CA bundle for HTTPS) | [docs/certifi.md](docs/certifi.md) |
| **charset_normalizer** | [docs/charset-normalizer.md](docs/charset-normalizer.md) |
| **idna** | [docs/idna.md](docs/idna.md) |
| **PyWebView (CodeBench shim)** — full cookie API + verbose logging | [docs/pywebview.md](docs/pywebview.md) |

### Web frameworks (run dashboards on-device)

| Library | Doc |
|---|---|
| **Werkzeug** (WSGI utilities + dev server) | [docs/werkzeug.md](docs/werkzeug.md) |
| **Flask** (web framework on Werkzeug) | [docs/flask.md](docs/flask.md) |
| **Dash** (Plotly-based reactive dashboards) | [docs/dash.md](docs/dash.md) |
| **Streamlit** (script-style dashboards) | [docs/streamlit.md](docs/streamlit.md) |
| **Tornado** (async HTTP/WebSocket — Streamlit's transport) | [docs/tornado.md](docs/tornado.md) |
| **Cross-stack iOS patches + Ctrl+C behavior** | [docs/web-stack.md](docs/web-stack.md) |

### Data / config

| Library | Doc |
|---|---|
| **PyYAML** | [docs/pyyaml.md](docs/pyyaml.md) |
| **jsonschema** | [docs/jsonschema.md](docs/jsonschema.md) |

### Terminal / CLI

| Library | Doc |
|---|---|
| **rich** (colors, tables, markdown rendering) | [docs/rich.md](docs/rich.md) |
| **click** | [docs/click.md](docs/click.md) |
| **tqdm** (progress bars) | [docs/tqdm.md](docs/tqdm.md) |
| **pygments** (syntax highlighting) | [docs/pygments.md](docs/pygments.md) |
| **markdown_it + mdurl** | [docs/markdown-it.md](docs/markdown-it.md) |

### System / process

| Library | Doc |
|---|---|
| **psutil + filelock + watchdog** (combined) | [docs/process-and-io.md](docs/process-and-io.md) |
| **moderngl + moderngl_window + screeninfo** (all stubbed on iOS) | [docs/moderngl.md](docs/moderngl.md) |

### C interop / language utilities

| Library | Doc |
|---|---|
| **cffi + pycparser** | [docs/cffi.md](docs/cffi.md) |
| **regex + typing_extensions** | [docs/regex-and-typing.md](docs/regex-and-typing.md) |
| **decorator** (full upstream package, pure Python) | [docs/decorator.md](docs/decorator.md) |

### Build / packaging

| Library | Doc |
|---|---|
| **pip** (with the in-shell wrapper) | [docs/pip.md](docs/pip.md) |

### Smaller utilities (transitive deps)

| Lib | Doc |
|---|---|
| **attrs** | [docs/attrs.md](docs/attrs.md) |
| **packaging** | [docs/packaging.md](docs/packaging.md) |
| **narwhals** | [docs/narwhals.md](docs/narwhals.md) |
| **referencing** | [docs/referencing.md](docs/referencing.md) |
| **cloup** | [docs/cloup.md](docs/cloup.md) |
| **srt** | [docs/srt.md](docs/srt.md) |
| **mdurl** | [docs/mdurl.md](docs/mdurl.md) |
| **typing_extensions** | [docs/typing-extensions.md](docs/typing-extensions.md) |
| **isosurfaces** | [docs/isosurfaces.md](docs/isosurfaces.md) |
| **mapbox_earcut** | [docs/mapbox-earcut.md](docs/mapbox-earcut.md) |
| **pathops** (skia-pathops) | [docs/pathops.md](docs/pathops.md) |
| **pycairo** | [docs/pycairo.md](docs/pycairo.md) |
| **rpds** (iOS stub) | [docs/rpds.md](docs/rpds.md) |
| **pylab** | [docs/pylab.md](docs/pylab.md) |
| **torchgen** | [docs/torchgen.md](docs/torchgen.md) |
| **setuptools** | [docs/setuptools.md](docs/setuptools.md) |
| **wheel** | [docs/wheel.md](docs/wheel.md) |
| **pkg_resources** | [docs/pkg-resources.md](docs/pkg-resources.md) |
| **_distutils_hack** | [docs/distutils-hack.md](docs/distutils-hack.md) |
| **psutil** | [docs/psutil.md](docs/psutil.md) |
| **filelock** | [docs/filelock.md](docs/filelock.md) |
| **watchdog** | [docs/watchdog.md](docs/watchdog.md) |

### CodeBench glue layer (host-app integration)

| Module | Doc |
|---|---|
| **offlinai_shell** (108 builtins, Ctrl+C watchdog, convenience-imports, HF git clone, AI mode) | [docs/offlinai-shell.md](docs/offlinai-shell.md) |
| **offlinai_ai** (chat REPL backed by bundled llama.cpp) | [docs/offlinai-ai.md](docs/offlinai-ai.md) |
| **offlinai_latex** (math/doc bridge to SwiftMath + busytex) | [docs/offlinai-latex.md](docs/offlinai-latex.md) |

---

## Quick lib lookup

If you're looking for a specific package and forgot which doc it's in:

| `import X` | Doc |
|---|---|
| `attrs` | [attrs.md](docs/attrs.md) |
| `audioop` | [audioop.md](docs/audioop.md) |
| `av` | [av-pyav.md](docs/av-pyav.md) · [ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| `bs4` | [beautifulsoup.md](docs/beautifulsoup.md) |
| `cairo` (pycairo) | [pycairo.md](docs/pycairo.md) · [cairographics.md](docs/cairographics.md) |
| `certifi` | [certifi.md](docs/certifi.md) |
| `cffi` / `pycparser` | [cffi.md](docs/cffi.md) |
| `charset_normalizer` | [charset-normalizer.md](docs/charset-normalizer.md) |
| `click` | [click.md](docs/click.md) |
| `cloup` | [cloup.md](docs/cloup.md) |
| `dash` | [dash.md](docs/dash.md) · [web-stack.md](docs/web-stack.md) |
| `decorator` | [decorator.md](docs/decorator.md) |
| `_distutils_hack` | [distutils-hack.md](docs/distutils-hack.md) |
| `filelock` | [filelock.md](docs/filelock.md) |
| `flask` | [flask.md](docs/flask.md) · [web-stack.md](docs/web-stack.md) |
| `huggingface_hub` | [huggingface-hub.md](docs/huggingface-hub.md) |
| `idna` | [idna.md](docs/idna.md) |
| `isosurfaces` | [isosurfaces.md](docs/isosurfaces.md) |
| `jsonschema` / `jsonschema_specifications` | [jsonschema.md](docs/jsonschema.md) |
| `manim` | [manim.md](docs/manim.md) |
| `manimpango` | [manimpango.md](docs/manimpango.md) |
| `mapbox_earcut` | [mapbox-earcut.md](docs/mapbox-earcut.md) |
| `markdown_it` | [markdown-it.md](docs/markdown-it.md) |
| `matplotlib` / `mpl_toolkits` (real 3.11) | [matplotlib.md](docs/matplotlib.md) |
| `onnxruntime` | [onnxruntime.md](docs/onnxruntime.md) |
| `mdurl` | [mdurl.md](docs/mdurl.md) |
| `moderngl` / `moderngl_window` / `screeninfo` | [moderngl.md](docs/moderngl.md) |
| `mpmath` | [mpmath.md](docs/mpmath.md) |
| `narwhals` | [narwhals.md](docs/narwhals.md) |
| `networkx` | [networkx.md](docs/networkx.md) |
| `numpy` | [numpy.md](docs/numpy.md) |
| `offlinai_ai` | [offlinai-ai.md](docs/offlinai-ai.md) |
| `offlinai_latex` | [offlinai-latex.md](docs/offlinai-latex.md) |
| `offlinai_shell` | [offlinai-shell.md](docs/offlinai-shell.md) |
| `packaging` | [packaging.md](docs/packaging.md) |
| `pathops` (skia-pathops) | [pathops.md](docs/pathops.md) |
| `PIL` (Pillow) | [pillow.md](docs/pillow.md) |
| `pip` (and the shell wrapper) | [pip.md](docs/pip.md) |
| `pkg_resources` | [pkg-resources.md](docs/pkg-resources.md) |
| `plotly` / `_plotly_utils` | [plotly.md](docs/plotly.md) |
| `psutil` | [psutil.md](docs/psutil.md) |
| `pydub` | [pydub.md](docs/pydub.md) |
| `pygments` | [pygments.md](docs/pygments.md) |
| `pylab` | [pylab.md](docs/pylab.md) |
| `referencing` | [referencing.md](docs/referencing.md) |
| `regex` | [regex.md](docs/regex.md) |
| `requests` | [requests.md](docs/requests.md) |
| `rich` | [rich.md](docs/rich.md) |
| `rpds` | [rpds.md](docs/rpds.md) |
| `safetensors` | [safetensors.md](docs/safetensors.md) |
| `scipy` | [scipy-ios.md](docs/scipy-ios.md) |
| `setuptools` | [setuptools.md](docs/setuptools.md) |
| `sklearn` | [sklearn.md](docs/sklearn.md) |
| `soupsieve` | (ships with bs4 — see [beautifulsoup.md](docs/beautifulsoup.md)) |
| `srt` | [srt.md](docs/srt.md) |
| `streamlit` | [streamlit.md](docs/streamlit.md) · [web-stack.md](docs/web-stack.md) |
| `svgelements` | [svgelements.md](docs/svgelements.md) |
| `sympy` | [sympy.md](docs/sympy.md) |
| `tokenizers` | [tokenizers.md](docs/tokenizers.md) |
| `torch` | [torch.md](docs/torch.md) |
| `torchgen` | [torchgen.md](docs/torchgen.md) |
| `tornado` | [tornado.md](docs/tornado.md) · [web-stack.md](docs/web-stack.md) |
| `tqdm` | [tqdm.md](docs/tqdm.md) |
| `transformers` | [transformers.md](docs/transformers.md) |
| `typing_extensions` | [typing-extensions.md](docs/typing-extensions.md) |
| `urllib3` | [urllib3.md](docs/urllib3.md) |
| `watchdog` | [watchdog.md](docs/watchdog.md) |
| `webview` (PyWebView shim) | [pywebview.md](docs/pywebview.md) |
| `werkzeug` | [werkzeug.md](docs/werkzeug.md) · [web-stack.md](docs/web-stack.md) |
| `wheel` | [wheel.md](docs/wheel.md) |
| `yaml` (PyYAML) | [pyyaml.md](docs/pyyaml.md) |

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 ([BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- Xcode 15+

## License

MIT
