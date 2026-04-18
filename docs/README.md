# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with 30+ offline libraries. Everything runs locally on-device — no internet, no server, no JIT. App Store safe.

---

## Languages

| Language | Runtime | Notes |
|----------|---------|-------|
| **Python 3.14** | BeeWare embedded CPython | Native C extensions (.so → .fwork) |
| **C** | Tree-walking interpreter (3,450 lines) | 48 operators, structs, pointers, preprocessor |
| **C++** | Tree-walking interpreter (4,200 lines) | Classes, STL, templates, inheritance |
| **Fortran** | Tree-walking interpreter (4,100 lines) | Modules, allocatable arrays, intrinsics |

---

## Python Libraries

### Scientific Computing

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **NumPy** | 2.3.5 | Native iOS | N-dimensional arrays, linear algebra, FFT, random |
| **SciPy** | 1.15.0 | Pure Python shim | Optimization, interpolation, integration, signal, stats, spatial |
| **SymPy** | 1.14.0 | Pure Python | Symbolic math: algebra, calculus, solving, matrices |
| **mpmath** | 1.4.1 | Pure Python | Arbitrary-precision arithmetic, special functions |

### Machine Learning

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **PyTorch** | 2.1.0 (patched) | Native iOS (arm64) | Full `import torch` — tensors, autograd, nn, optim, JIT, FFT, distributions. 95/95 correctness asserts. Apple Accelerate for linalg |
| **transformers** | 4.41.2 | Pure Python | HuggingFace models: BERT, GPT-2, T5, BART, etc. Construct from config, train, generate, save/load — all on-device |
| **tokenizers** | 0.19.1 | Native iOS (Rust) | **First public iOS build.** Real Rust BPE/WordPiece/Unigram trainers. PyO3 bindings, full speed |
| **scikit-learn** | — | Pure NumPy (12K+ lines, 40 modules) | Classification, regression, clustering, preprocessing, model selection, 38 metrics |

### Visualization

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **matplotlib** | 3.9.0 | Plotly shim (64 modules) | Drop-in pyplot → interactive Plotly HTML |
| **Plotly** | 6.6.0 | Pure Python | Interactive charts, 3D plots, maps |
| **manim** | 0.20.1 | Modified for iOS | 145+ mobjects, 73 animations, 40+ rate functions, H.264 video |

### Media & Rendering

| Library | Type | Description |
|---------|------|-------------|
| **PyAV** | Native iOS (17 C extensions) | FFmpeg bindings: encode/decode video and audio |
| **FFmpeg** | Native iOS (7 dylibs, 21 MB) | H.264/HEVC hardware encoding, 50+ codecs, 30+ formats |
| **Cairo** (pycairo) | Native iOS (2.8 MB) | 2D vector graphics: SVG, PDF, PNG, patterns, text paths |
| **Pillow** | 12.2.0, Native iOS | Image processing: resize, crop, filter, draw, 15 formats |
| **ManimPango** | Cairo-based fallback | Text → SVG vector outlines (11 font weights) |
| **offlinai_latex** | pdftex C library | Local LaTeX typesetting: pdftex → PDF → SVG |

### Data & Web

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| **requests** | — | Pure Python | HTTP client: GET, POST, sessions, auth, JSON |
| **BeautifulSoup4** | 4.14.3 | Pure Python | HTML/XML parsing and scraping |
| **NetworkX** | 3.6.1 | Pure Python | Graph theory: 200+ algorithms, generators |
| **jsonschema** | 4.26.0 | Pure Python | JSON Schema validation (Draft 7) |
| **PyYAML** | 6.0.3 | Native | YAML parsing and serialization |

### Utilities

| Library | Description |
|---------|-------------|
| **rich** | Rich text, tables, progress bars, syntax highlighting |
| **tqdm** | Progress bars for loops and iterables |
| **Pygments** | Source code syntax highlighting (500+ languages) |
| **click** | CLI framework with decorators |
| **pydub** | Audio manipulation (slice, concatenate, effects) |
| **packaging** | Version parsing and comparison (PEP 440) |
| **srt** | Subtitle file parsing and generation |
| **watchdog** | Filesystem event monitoring |
| **svgelements** | SVG parsing and manipulation |
| **cffi** | C Foreign Function Interface |

---

## Detailed Documentation

### Machine Learning
- [**PyTorch**](libs/pytorch.md) — Full `import torch` on iPad. 95/95 numerical + training asserts
- [**transformers**](libs/transformers.md) — HuggingFace models: BERT, GPT-2, train + generate on-device
- [**tokenizers**](libs/tokenizers.md) — First public iOS build of HuggingFace's Rust tokenizers
- [scikit-learn](libs/sklearn.md) — 40 modules, 85%+ of common ML workflows

### Scientific
- [NumPy](libs/numpy.md) — Arrays, linear algebra, FFT, random
- [SciPy](libs/scipy.md) — 13 submodules: optimize, integrate, signal, stats, ...
- [SymPy](libs/sympy.md) — Computer algebra system

### Visualization & Media
- [matplotlib](libs/matplotlib.md) — 64 modules, Plotly backend
- [**manim**](libs/manim.md) — 145+ mobjects, 73 animations, full rendering pipeline
- [**Media & Rendering**](libs/media.md) — PyAV, FFmpeg (7 libs), Cairo, Pillow, ManimPango, LaTeX

### Interpreters
- [C/C++/Fortran Interpreters](libs/interpreters.md) — 11,800 lines, full language support

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   iPad App                       │
├──────────┬──────────┬──────────┬────────────────┤
│  Editor  │  Files   │   Docs   │   AI Chat      │
│  (code)  │ (browse) │  (ref)   │  (LLM assist)  │
├──────────┴──────────┴──────────┴────────────────┤
│              Python 3.14 Runtime                 │
│  ┌─────────┬───────────┬─────────────┐          │
│  │ PyTorch │transformers│ tokenizers  │  ← ML    │
│  │ 2.1 iOS │   4.41     │ 0.19 (Rust) │          │
│  └─────────┴───────────┴─────────────┘          │
│  ┌────────┬────────┬────────┬────────┐          │
│  │ NumPy  │ SciPy  │ manim  │sklearn │   ...    │
│  └────────┴────────┴────────┴────────┘          │
├─────────────────────────────────────────────────┤
│  Native Frameworks (arm64)                       │
│  ┌──────────┬────────┬────────┬────────┐        │
│  │ libtorch │ FFmpeg │ Cairo  │pdftex  │        │
│  │ (185 MB) │(7 libs)│        │        │        │
│  └──────────┴────────┴────────┴────────┘        │
│  ┌─────────────────────┬──────────────┐         │
│  │ Apple Accelerate    │ Pillow       │         │
│  │ (BLAS/LAPACK/FFT)   │              │         │
│  └─────────────────────┴──────────────┘         │
├──────────┬──────────┬───────────────────────────┤
│ C interp │ C++ int  │ Fortran interpreter       │
│ (Swift)  │ (Swift)  │ (Swift)                   │
├──────────┴──────────┴───────────────────────────┤
│           llama.cpp (local LLM inference)        │
│           Qwen3.5 / Gemma 4 (GGUF)             │
└─────────────────────────────────────────────────┘
```
