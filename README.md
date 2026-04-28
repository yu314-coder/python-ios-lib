# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with **30+ offline libraries including real PyTorch + HuggingFace transformers + Rust tokenizers**. No JIT, App Store safe.

> **New:** Full `import torch` (v2.1), `import transformers` (v4.41), and `import tokenizers` (v0.19, real Rust cross-compile) all work on-device. Train and fine-tune transformer models on an iPad with zero network. [Full integration test: 24/24 passing.](docs/libs/transformers.md#test-coverage)

### Recent app-side changes

- **Monaco code editor with IntelliSense** running in a WKWebView — Python keyword snippets, signature help (~70-entry SIG_DB), hover docs, and resolve-from-Python for numpy / scipy / sklearn / matplotlib / sympy completions. See `CodeBench/MonacoEditorView.swift`.
- **Auto-save**: edits persist to disk on every keystroke (debounced ~600 ms) plus on run, tab-switch, view-disappear, and app-backgrounding. Fixes the "edit `a.tex`, reopen, 0 B" bug.
- **Tombstone system** — files deleted via the file browser trash icon, `rm` / `rmdir` in the shell, or ncdu's `d` key are recorded in `<Workspace>/.offlinai_deleted` so the starter-script seeder (`pip_demo.py`, `torch_test_all.py`, etc.) no longer re-creates them on next launch.
- **LaTeX bundle expanded** — 33 MB texmf tree now ships with full Latin Modern Type 1 fonts, expl3 code (1.3 MB), firstaid, graphics-def, hyphenation, stringenc, unicode-data, and pdftex.map. Math-mode rendering via SwiftMath is unlimited and reliable; the native `pdflatex` builtin is gated off pending replacement of the 2019-era `pdftex.xcframework` (see [Media docs](docs/libs/media.md#local-latex-engine-offlinai_latex)).
- **Shell builtins**: `pdflatex` / `latex` / `tex` / `pdftex` / `xelatex` / `latex-diagnose`, `ncdu` with raw arrow-key navigation and real-ncdu styling, `top` with Apple-chip detection, `git clone` via zipball fetch, and universal `--help` / `-h` interception.

## Quick Start — adding python-ios-lib to your iOS app

This is a Swift Package — works with Xcode and SwiftPM. Steps:

### 1. Install Git LFS (only once per machine)

The PyTorch dylib is 99 MB and lives in Git LFS. Without LFS, the
file arrives as a 134-byte pointer stub and `import torch` will
crash at load. Skip this step ONLY if you don't use the PyTorch
target.

```bash
brew install git-lfs && git lfs install
```

### 2. Add the package in Xcode

In Xcode: **File → Add Package Dependencies…** → paste this URL:

```
https://github.com/yu314-coder/python-ios-lib
```

Pick a version (use the latest tag, or "Branch: main" for the bleeding edge).

### 3. Pick the products you actually need

Xcode shows a checklist of every library product. Tick only what your
app imports — each product copies its Python files into the app
bundle, so adding everything bloats the binary unnecessarily.

For example, just want to use `import webview` (the pywebview shim)?
Check **PyWebView** and nothing else.

Need PyTorch + transformers + numpy? Check **Transformers** —
`PyTorch`, `Tokenizers`, `huggingface_hub`, `safetensors`, and
`filelock` get auto-included as dependencies.

### 4. Wire up Python at app launch

You need a Python runtime to actually `import` these. The simplest
path is [BeeWare's Python-Apple-support](https://github.com/beeware/Python-Apple-support)
binary — set up a `Py_Initialize()` once at startup, then run
arbitrary Python code via `PyRun_SimpleString`. CodeBench's
`PythonRuntime.swift` is a working reference.

### 5. (Optional) Use the SwiftPM CLI instead

If you prefer `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "PyWebView", package: "python-ios-lib"),
        .product(name: "NumPy",     package: "python-ios-lib"),
        // … add as many products as you want
    ]),
],
```

### 6. (For Mac "Designed for iPad" only) Add the network entitlement

Designed-for-iPad runs your iOS app under the macOS sandbox, which
blocks outbound network by default. If `pip install` or
`requests.get` returns `PermissionError(1, 'Operation not
permitted')`, create a `MyApp.entitlements` file with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

…and set Project → Build Settings → **Code Signing Entitlements** to
this file. Real iOS devices and the iOS Simulator don't need this.

---

## Available products (29 in Xcode's checklist)

Pick whichever combination you need. Dependencies auto-resolve.

### Standalone packages (no dependencies)

| Package | What you get | Doc |
|---|---|---|
| **CInterpreter** | C89/C99/C23 tree-walking interpreter (~3,661 lines) | [doc](docs/c-interpreter.md) |
| **CppInterpreter** | C++ interpreter — classes, STL, templates, inheritance (~4,287 lines) | [doc](docs/cpp-interpreter.md) |
| **FortranInterpreter** | Fortran — modules, allocatable arrays, 45+ intrinsics (~3,876 lines) | [doc](docs/fortran-interpreter.md) |
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
| **Decorator** | Single-file shim of Michele Simionato's `decorator` package — covers manim's needs | [doc](docs/decorator.md) |
| **PyWebView** | pywebview shim — embed HTML/CSS/JS UI in your iOS app from Python via the host's preview pane (full cookie API + file IPC) | [doc](docs/pywebview.md) |

### Packages with dependencies (auto-included when you select)

| Package | What you get | Auto-includes | Doc |
|---|---|---|---|
| **Sklearn** | scikit-learn (40 modules, 12K+ lines) | + NumPy | [doc](docs/sklearn.md) |
| **SciPy** | SciPy (optimize, integrate, signal, stats) | + NumPy | [doc](docs/scipy-ios.md) |
| **Matplotlib** | matplotlib (64 modules, Plotly backend) | + Plotly | [doc](docs/matplotlib.md) |
| **Manim** | manim (145+ mobjects, 73 animations) | + NumPy, Matplotlib, FFmpegPyAV, CairoGraphics | [doc](docs/manim.md) |
| **LaTeXEngine** | pdftex.xcframework + 33 MB bundled texmf tree (Latin Modern, amsmath, hyperref, expl3, …). `\documentclass{article}` end-to-end. | + CairoGraphics | [doc](docs/latex-engine.md) |

### Machine Learning stack (PyTorch + HuggingFace)

First public iOS builds of each. Once added, `import torch`, `import transformers`, `import tokenizers` all work on-device with no extra setup.

| Package | What you get | Auto-includes | Doc |
|---|---|---|---|
| **PyTorch** | PyTorch 2.1.2 native iOS — tensors, autograd, nn, optim, JIT, FFT, LAPACK via Accelerate. **95/95 correctness asserts.** Ships `libtorch_python.dylib` (99 MB) via Git LFS. | regex shim | [doc](docs/torch.md) |
| **Tokenizers** | HuggingFace tokenizers 0.19.1 — real Rust BPE/WordPiece/Unigram trainers cross-compiled for iOS arm64 (PyO3). First public iOS build. | (none) | [doc](docs/tokenizers.md) |
| **Transformers** | HuggingFace transformers 4.41.2 — BERT, GPT-2, T5, BART, Llama, Qwen. Construct + train + `.generate()` + save/load on-device. | + PyTorch, Tokenizers, `huggingface_hub`, `filelock`, `safetensors` | [doc](docs/transformers.md) |

> **Git LFS required for PyTorch / Transformers** — see [step 1 of Quick Start](#1-install-git-lfs-only-once-per-machine). Other targets work without LFS.

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
  ├── PyTorch (99 MB dylib via Git LFS)
  │     └── regex (shim)
  └── Tokenizers (5 MB Rust .so)
Transformers also bundles huggingface_hub, filelock, safetensors
```

---

## All Libraries

### Scientific Computing

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **NumPy** | 2.3.5 | Native iOS | Arrays, linear algebra, FFT, random |
| **SciPy** | 1.15.0 | Compiled + shim | Optimization, interpolation, signal, stats |
| **SymPy** | 1.14.0 | Pure Python | Symbolic math, calculus, solving |
| **mpmath** | 1.4.1 | Pure Python | Arbitrary-precision arithmetic |

### Machine Learning

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **PyTorch** | 2.1.2 (patched) | Native iOS (arm64) | Full `import torch`: tensors, autograd, nn, optim, JIT, LAPACK via Accelerate. **95/95 correctness asserts.** First public native PyTorch on iOS. [Details →](docs/libs/pytorch.md) |
| **transformers** | 4.41.2 | Pure Python | HuggingFace: BERT, GPT-2, T5, BART — train + `generate()` on-device. [Details →](docs/libs/transformers.md) |
| **tokenizers** | 0.19.1 | Native iOS (Rust) | **First public iOS build.** Real BPE/WordPiece/Unigram trainers via PyO3. [Details →](docs/libs/tokenizers.md) |
| **scikit-learn** | — | Pure NumPy (40 modules) | Classification, regression, clustering, preprocessing, metrics |

### Visualization

| Library | Version | Description |
|---------|---------|-------------|
| **matplotlib** | 3.9.0 | Plotly backend (64 modules) |
| **Plotly** | 6.6.0 | Interactive charts |
| **manim** | 0.20.1 | Math animations (145+ mobjects, 73 animations) |

### Media & Rendering

| Library | Description |
|---------|-------------|
| **PyAV + FFmpeg** | Video encoding (H.264 hardware), 7 native dylibs |
| **Cairo + Pango** | 2D vector graphics, text rendering |
| **Pillow** | Image processing |
| **Local LaTeX** (`offlinai_latex` module) | Math-mode LaTeX via SwiftMath (unlimited calls). Full-document `pdflatex` gated off — the bundled `pdftex.xcframework` v1.40.20 crashes on modern latex.ltx; see [Media docs](docs/libs/media.md#local-latex-engine-offlinai_latex) for the SwiftLaTeX-WASM migration path |

### Data & Web

| Library | Description |
|---------|-------------|
| **requests** | HTTP client |
| **urllib3** | HTTP transport (under requests) |
| **BeautifulSoup4** | HTML parsing |
| **NetworkX** | Graph algorithms |
| **jsonschema** | JSON validation |
| **PyWebView** | Render HTML/CSS/JS in the host app's preview pane (CodeBench shim) |

### Interpreters

| Language | Lines | Description |
|----------|-------|-------------|
| **C** | ~3,450 | C89/C99/C23, 48 operators, structs, pointers, preprocessor |
| **C++** | ~4,200 | Classes, STL, templates, inheritance |
| **Fortran** | ~4,100 | Modules, allocatable arrays, 45+ intrinsics |

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
| All three (overview) | [docs/libs/interpreters.md](docs/libs/interpreters.md) |

### Native engines (C/C++ libs)

| Engine | Doc |
|---|---|
| **CairoGraphics** (Cairo + Pango + HarfBuzz + FreeType + GLib + libffi) | [docs/cairographics.md](docs/cairographics.md) |
| **FFmpeg + PyAV** (video encode/decode, VideoToolbox H.264) | [docs/ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| **LaTeXEngine** (pdftex.xcframework + 33 MB texmf) | [docs/latex-engine.md](docs/latex-engine.md) |

### Scientific computing

| Library | Doc |
|---|---|
| **NumPy** | [docs/numpy.md](docs/numpy.md) — also [docs/libs/numpy.md](docs/libs/numpy.md) |
| **SciPy** | [docs/scipy-ios.md](docs/scipy-ios.md) — also [docs/libs/scipy.md](docs/libs/scipy.md) |
| **SymPy** | [docs/sympy.md](docs/sympy.md) — also [docs/libs/sympy.md](docs/libs/sympy.md) |
| **mpmath** | [docs/mpmath.md](docs/mpmath.md) |
| **NetworkX** | [docs/networkx.md](docs/networkx.md) |
| **scikit-learn** | [docs/sklearn.md](docs/sklearn.md) — also [docs/libs/sklearn.md](docs/libs/sklearn.md) |

### Machine learning

| Library | Doc |
|---|---|
| **PyTorch** (99 MB dylib via Git LFS) | [docs/torch.md](docs/torch.md) — also [docs/libs/pytorch.md](docs/libs/pytorch.md) |
| **transformers** | [docs/transformers.md](docs/transformers.md) — also [docs/libs/transformers.md](docs/libs/transformers.md) |
| **tokenizers** (Rust via PyO3) | [docs/tokenizers.md](docs/tokenizers.md) — also [docs/libs/tokenizers.md](docs/libs/tokenizers.md) |
| **safetensors** | [docs/safetensors.md](docs/safetensors.md) |
| **huggingface_hub** | [docs/huggingface-hub.md](docs/huggingface-hub.md) |

### Visualization

| Library | Doc |
|---|---|
| **matplotlib** (Plotly-backend shim) | [docs/matplotlib.md](docs/matplotlib.md) — also [docs/libs/matplotlib.md](docs/libs/matplotlib.md) |
| **Plotly** | [docs/plotly.md](docs/plotly.md) |
| **manim** | [docs/manim.md](docs/manim.md) — also [docs/libs/manim.md](docs/libs/manim.md) |
| **manim deps** (pathops + mapbox_earcut + isosurfaces) | [docs/manim-deps.md](docs/manim-deps.md) |
| **manimpango** | [docs/manimpango.md](docs/manimpango.md) |

### Media (image / audio / video)

| Library | Doc |
|---|---|
| **Pillow / PIL** | [docs/pillow.md](docs/pillow.md) |
| **PyAV** | [docs/av-pyav.md](docs/av-pyav.md) — also [docs/ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| **pydub** (audio, uses audioop) | [docs/pydub.md](docs/pydub.md) |
| **audioop** (LTS backport — removed from Python 3.13 stdlib) | [docs/audioop.md](docs/audioop.md) |
| **svgelements** | [docs/svgelements.md](docs/svgelements.md) |
| **Media overview** | [docs/libs/media.md](docs/libs/media.md) |

### Web & network

| Library | Doc |
|---|---|
| **requests** | [docs/requests.md](docs/requests.md) |
| **urllib3** | [docs/urllib3.md](docs/urllib3.md) |
| **BeautifulSoup4** | [docs/beautifulsoup.md](docs/beautifulsoup.md) |
| **certifi** (CA bundle for HTTPS) | [docs/certifi.md](docs/certifi.md) |
| **charset_normalizer + idna** | [docs/encoding.md](docs/encoding.md) |
| **PyWebView (CodeBench shim)** — full cookie API + verbose logging | [docs/pywebview.md](docs/pywebview.md) |

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
| **decorator** (CodeBench shim — manim's only deps) | [docs/decorator.md](docs/decorator.md) |

### Build / packaging

| Library | Doc |
|---|---|
| **pip** (with the in-shell wrapper) | [docs/pip.md](docs/pip.md) |

### Smaller utilities (transitive deps)

| Lib | Doc |
|---|---|
| **attrs / packaging / narwhals / referencing** | [docs/minor-libs.md](docs/minor-libs.md) |
| **cloup / soupsieve / rpds / srt / pylab / torchgen / setuptools / wheel / pkg_resources / _distutils_hack** | [docs/small-utils.md](docs/small-utils.md) |

### CodeBench glue layer (host-app integration)

| Module | Doc |
|---|---|
| **offlinai_shell** (108 builtins) + **offlinai_ai** (chat REPL) + **offlinai_latex** (math/doc bridge) | [docs/codebench-extras.md](docs/codebench-extras.md) |

---

## Quick lib lookup

If you're looking for a specific package and forgot which doc it's in:

| `import X` | Doc |
|---|---|
| `attr` / `attrs` | [minor-libs.md](docs/minor-libs.md) |
| `audioop` | [audioop.md](docs/audioop.md) |
| `av` | [av-pyav.md](docs/av-pyav.md) / [ffmpeg-pyav.md](docs/ffmpeg-pyav.md) |
| `bs4` | [beautifulsoup.md](docs/beautifulsoup.md) |
| `cairo` | [cairographics.md](docs/cairographics.md) |
| `certifi` | [certifi.md](docs/certifi.md) |
| `cffi` / `pycparser` | [cffi.md](docs/cffi.md) |
| `charset_normalizer` / `idna` | [encoding.md](docs/encoding.md) |
| `click` / `cloup` | [click.md](docs/click.md) / [small-utils.md](docs/small-utils.md) |
| `decorator` | [decorator.md](docs/decorator.md) |
| `filelock` / `psutil` / `watchdog` | [process-and-io.md](docs/process-and-io.md) |
| `huggingface_hub` | [huggingface-hub.md](docs/huggingface-hub.md) |
| `isosurfaces` / `mapbox_earcut` / `pathops` | [manim-deps.md](docs/manim-deps.md) |
| `jsonschema` / `jsonschema_specifications` / `referencing` / `rpds` | [jsonschema.md](docs/jsonschema.md) / [small-utils.md](docs/small-utils.md) |
| `manim` | [manim.md](docs/manim.md) |
| `manimpango` | [manimpango.md](docs/manimpango.md) |
| `markdown_it` / `mdurl` | [markdown-it.md](docs/markdown-it.md) |
| `matplotlib` / `mpl_toolkits` / `pylab` | [matplotlib.md](docs/matplotlib.md) / [small-utils.md](docs/small-utils.md) |
| `moderngl` / `moderngl_window` / `screeninfo` | [moderngl.md](docs/moderngl.md) |
| `mpmath` | [mpmath.md](docs/mpmath.md) |
| `narwhals` / `packaging` | [minor-libs.md](docs/minor-libs.md) |
| `networkx` | [networkx.md](docs/networkx.md) |
| `numpy` | [numpy.md](docs/numpy.md) |
| `offlinai_ai` / `offlinai_latex` / `offlinai_shell` | [codebench-extras.md](docs/codebench-extras.md) |
| `PIL` (Pillow) | [pillow.md](docs/pillow.md) |
| `pip` (and the shell wrapper) | [pip.md](docs/pip.md) |
| `plotly` / `_plotly_utils` | [plotly.md](docs/plotly.md) |
| `pydub` | [pydub.md](docs/pydub.md) |
| `pygments` | [pygments.md](docs/pygments.md) |
| `regex` / `typing_extensions` | [regex-and-typing.md](docs/regex-and-typing.md) |
| `requests` / `urllib3` | [requests.md](docs/requests.md) / [urllib3.md](docs/urllib3.md) |
| `rich` | [rich.md](docs/rich.md) |
| `safetensors` | [safetensors.md](docs/safetensors.md) |
| `scipy` | [scipy-ios.md](docs/scipy-ios.md) |
| `setuptools` / `wheel` / `pkg_resources` / `_distutils_hack` | [small-utils.md](docs/small-utils.md) |
| `sklearn` | [sklearn.md](docs/sklearn.md) |
| `soupsieve` | [small-utils.md](docs/small-utils.md) |
| `srt` | [small-utils.md](docs/small-utils.md) |
| `svgelements` | [svgelements.md](docs/svgelements.md) |
| `sympy` | [sympy.md](docs/sympy.md) |
| `tokenizers` | [tokenizers.md](docs/tokenizers.md) |
| `torch` / `torchgen` | [torch.md](docs/torch.md) / [small-utils.md](docs/small-utils.md) |
| `tqdm` | [tqdm.md](docs/tqdm.md) |
| `transformers` | [transformers.md](docs/transformers.md) |
| `webview` (PyWebView shim) | [pywebview.md](docs/pywebview.md) |
| `yaml` (PyYAML) | [pyyaml.md](docs/pyyaml.md) |

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 ([BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- Xcode 15+

## License

MIT
