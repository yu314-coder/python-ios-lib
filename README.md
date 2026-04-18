# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with **30+ offline libraries including real PyTorch + HuggingFace transformers + Rust tokenizers**. No JIT, App Store safe.

> **New:** Full `import torch` (v2.1), `import transformers` (v4.41), and `import tokenizers` (v0.19, real Rust cross-compile) all work on-device. Train and fine-tune transformer models on an iPad with zero network. [Full integration test: 24/24 passing.](docs/libs/transformers.md#test-coverage)

## Quick Start — Add via Xcode

In Xcode: **File → Add Package Dependencies** → paste:

```
https://github.com/yu314-coder/python-ios-lib
```

Then select which packages you need:

### Standalone packages (no dependencies)

| Package | What you get |
|---------|-------------|
| **CInterpreter** | C/C++/Fortran interpreters (compiles from source) |
| **NumPy** | NumPy 2.3.5 — arrays, linalg, FFT, random (native iOS) |
| **SymPy** | SymPy 1.14 — symbolic math, calculus, solving |
| **Plotly** | Plotly 6.6 — interactive charts, 3D plots |
| **NetworkX** | NetworkX 3.6 — graph theory, algorithms |
| **Pillow** | Pillow 12.2 — image processing (native iOS) |
| **BeautifulSoup** | BeautifulSoup4 — HTML/XML parsing |
| **Requests** | HTTP client (GET, POST, sessions, JSON) |
| **PyYAML** | YAML parser (native iOS) |
| **Rich** | Rich text, tables, progress bars |
| **Tqdm** | Progress bars for loops |
| **Click** | CLI framework |
| **Pygments** | Syntax highlighting (500+ languages) |
| **Mpmath** | Arbitrary-precision arithmetic |
| **Pydub** | Audio manipulation |
| **JsonSchema** | JSON Schema validation |
| **CairoGraphics** | Cairo + Pango + HarfBuzz (2D graphics, native iOS) |
| **FFmpegPyAV** | FFmpeg (7 dylibs) + PyAV video encoding (native iOS) |

### Packages with dependencies (auto-included when you select)

| Package | What you get | Auto-includes |
|---------|-------------|---------------|
| **Sklearn** | scikit-learn (40 modules, 12K+ lines) | + NumPy |
| **SciPy** | SciPy (optimize, integrate, signal, stats) | + NumPy |
| **Matplotlib** | matplotlib (64 modules, Plotly backend) | + Plotly |
| **Manim** | manim (145+ mobjects, 73 animations) | + NumPy, Matplotlib, FFmpegPyAV, CairoGraphics |
| **LaTeXEngine** | pdftex + kpathsea + texmf fonts | + CairoGraphics |

### Machine Learning stack (PyTorch + HuggingFace)

First public iOS builds of each. Once added, `import torch`, `import transformers`, `import tokenizers` all work on-device with no extra setup.

| Package | What you get | Auto-includes |
|---------|-------------|---------------|
| **PyTorch** | [PyTorch 2.1.2](docs/libs/pytorch.md) native iOS — tensors, autograd, nn, optim, JIT, FFT, LAPACK via Accelerate. **95/95 correctness asserts.** Ships `libtorch_python.dylib` (99 MB) via Git LFS. | regex shim |
| **Tokenizers** | [HuggingFace tokenizers 0.19.1](docs/libs/tokenizers.md) — real Rust BPE/WordPiece/Unigram trainers cross-compiled for iOS arm64 (PyO3). First public iOS build. | (none) |
| **Transformers** | [HuggingFace transformers 4.41.2](docs/libs/transformers.md) — BERT, GPT-2, T5, BART. Construct + train + `.generate()` + save/load on-device. | + PyTorch, Tokenizers, `huggingface_hub`, `filelock`, `safetensors` |

> **Requires Git LFS** — install `brew install git-lfs && git lfs install` before cloning so the 99 MB PyTorch binary pulls correctly. Without it, `libtorch_python.dylib` arrives as a 134-byte LFS pointer stub and `import torch` crashes at load.

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
| **offlinai_latex** | Local LaTeX via pdftex |

### Data & Web

| Library | Description |
|---------|-------------|
| **requests** | HTTP client |
| **BeautifulSoup4** | HTML parsing |
| **NetworkX** | Graph algorithms |
| **jsonschema** | JSON validation |

### Interpreters

| Language | Lines | Description |
|----------|-------|-------------|
| **C** | ~3,450 | C89/C99/C23, 48 operators, structs, pointers, preprocessor |
| **C++** | ~4,200 | Classes, STL, templates, inheritance |
| **Fortran** | ~4,100 | Modules, allocatable arrays, 45+ intrinsics |

---

## Detailed Docs

### Machine Learning
- [**PyTorch**](docs/libs/pytorch.md) — native iOS build with full `import torch` (95/95 asserts)
- [**transformers**](docs/libs/transformers.md) — HuggingFace models, on-device train + generate
- [**tokenizers**](docs/libs/tokenizers.md) — Rust BPE/WordPiece/Unigram trainers
- [scikit-learn](docs/libs/sklearn.md) — 40 modules, common ML workflows

### Scientific + Viz + Media
- [NumPy](docs/libs/numpy.md) | [SciPy](docs/libs/scipy.md) | [SymPy](docs/libs/sympy.md)
- [matplotlib](docs/libs/matplotlib.md) | [manim](docs/libs/manim.md)
- [Media & Rendering](docs/libs/media.md) — PyAV, FFmpeg, Cairo, Pillow, LaTeX

### Interpreters
- [C / C++ / Fortran](docs/libs/interpreters.md) — 11,800 lines, full language support

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 ([BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- Xcode 15+

## License

MIT
