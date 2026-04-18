# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with **30+ offline libraries**. No JIT, App Store safe.

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
| **PyTorch** | [Native PyTorch 2.1.2](docs/libs/pytorch.md) — full `import torch` (JIT, LAPACK, autograd, nn, training). **57/57 tests pass on iPad.** 98 MB dylib. | + NumPy |
| **Sklearn** | scikit-learn (40 modules, 12K+ lines) | + NumPy |
| **SciPy** | SciPy (optimize, integrate, signal, stats) | + NumPy |
| **Matplotlib** | matplotlib (64 modules, Plotly backend) | + Plotly |
| **Manim** | manim (145+ mobjects, 73 animations) | + NumPy, Matplotlib, FFmpegPyAV, CairoGraphics |
| **LaTeXEngine** | pdftex + kpathsea + texmf fonts | + CairoGraphics |

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

| Library | Type | Description |
|---------|------|-------------|
| **PyTorch** | Native cross-compile (v2.1.2) | **Full `import torch`** — C++ JIT, autograd, nn, training, LAPACK via Accelerate. **57/57 acceptance tests pass.** First public native PyTorch on iOS. |
| **scikit-learn** | Pure NumPy (40 modules) | Classification, regression, clustering, preprocessing, metrics |

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

- [**PyTorch**](docs/libs/pytorch.md) — native iOS build with full `import torch`
- [NumPy](docs/libs/numpy.md) | [SciPy](docs/libs/scipy.md) | [scikit-learn](docs/libs/sklearn.md)
- [matplotlib](docs/libs/matplotlib.md) | [SymPy](docs/libs/sympy.md) | [manim](docs/libs/manim.md)
- [Media & Rendering](docs/libs/media.md) | [Interpreters](docs/libs/interpreters.md)

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 ([BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- Xcode 15+

## License

MIT
