# python-ios-lib

Full Python 3.14 runtime for iOS/iPadOS with **30+ offline libraries** — NumPy, SciPy, sklearn, manim, PyAV/FFmpeg, Cairo, Pillow, SymPy, matplotlib. Includes C/C++/Fortran interpreters. No JIT, App Store safe.

---

## All Libraries

### Scientific Computing

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| [**NumPy**](docs/libs/numpy.md) | 2.3.5 | Native iOS | N-dimensional arrays, linear algebra, FFT, random |
| [**SciPy**](docs/libs/scipy.md) | 1.15.0 | Pure Python shim | Optimization, interpolation, integration, signal, stats, spatial |
| [**SymPy**](docs/libs/sympy.md) | 1.14.0 | Pure Python | Symbolic math: algebra, calculus, solving, matrices |
| **mpmath** | 1.4.1 | Pure Python | Arbitrary-precision arithmetic, special functions |

### Machine Learning

| Library | Type | Description |
|---------|------|-------------|
| [**scikit-learn**](docs/libs/sklearn.md) | Pure NumPy (12K+ lines, 40 modules) | Classification, regression, clustering, preprocessing, model selection, 38 metrics |

### Visualization

| Library | Version | Type | Description |
|---------|---------|------|-------------|
| [**matplotlib**](docs/libs/matplotlib.md) | 3.9.0 | Plotly shim (64 modules) | Drop-in pyplot → interactive Plotly HTML |
| **Plotly** | 6.6.0 | Pure Python | Interactive charts, 3D plots, maps |
| [**manim**](docs/libs/manim.md) | 0.20.1 | Modified for iOS | 145+ mobjects, 73 animations, 40+ rate functions, H.264 video |

### Media & Rendering

| Library | Type | Description |
|---------|------|-------------|
| [**PyAV**](docs/libs/media.md) | Native iOS (17 C extensions) | FFmpeg bindings: encode/decode video and audio |
| **FFmpeg** | Native iOS (7 dylibs, 21 MB) | H.264/HEVC hardware encoding, 50+ codecs, 30+ formats |
| **Cairo** (pycairo) | Native iOS (2.8 MB) | 2D vector graphics: SVG, PDF, PNG, patterns, text paths |
| **Pillow** | 12.2.0, Native iOS | Image processing: resize, crop, filter, draw, 15 formats |
| **ManimPango** | Cairo-based fallback | Text → SVG vector outlines (11 font weights) |
| **offlinai_latex** | pdftex C library | Local LaTeX typesetting: pdftex → PDF → SVG |

### Data & Web

| Library | Version | Description |
|---------|---------|-------------|
| **requests** | — | HTTP client: GET, POST, sessions, auth, JSON |
| **BeautifulSoup4** | 4.14.3 | HTML/XML parsing and scraping |
| **NetworkX** | 3.6.1 | Graph theory: 200+ algorithms |
| **jsonschema** | 4.26.0 | JSON Schema validation (Draft 7) |
| **PyYAML** | 6.0.3 | YAML parsing and serialization |

### Utilities

| Library | Description |
|---------|-------------|
| **rich** | Rich text, tables, progress bars |
| **tqdm** | Progress bars for loops |
| **Pygments** | Syntax highlighting (500+ languages) |
| **click** | CLI framework with decorators |
| **pydub** | Audio manipulation |
| **packaging** | Version parsing (PEP 440) |
| **srt** | Subtitle file parsing |
| **svgelements** | SVG path manipulation |
| **cffi** | C Foreign Function Interface |

### Interpreters

| Language | Type | Description |
|----------|------|-------------|
| [**C**](docs/libs/interpreters.md) | Tree-walking (~3,450 lines) | 48 operators, structs, pointers, preprocessor, malloc/free |
| [**C++**](docs/libs/interpreters.md) | Tree-walking (~4,200 lines) | Classes, STL, templates, inheritance, lambdas |
| [**Fortran**](docs/libs/interpreters.md) | Tree-walking (~4,100 lines) | Modules, allocatable arrays, 45+ intrinsics |

---

## Quick Start

### Python Libraries

Copy library folders into your app's `site-packages/` directory:

```
YourApp.app/
  app_packages/
    site-packages/
      sklearn/          <- drop in
      matplotlib/       <- drop in (requires plotly)
      scipy/            <- cross-compiled + patches
      manim/            <- with PyAV + Cairo
```

### C Interpreter

Add `offlinai_cc.c` and `offlinai_cc.h` to your Xcode project:

```swift
let interp = occ_create()
defer { occ_destroy(interp) }

occ_execute(interp, """
#include <stdio.h>
#include <math.h>

int main() {
    printf("pi = %.10f\\n", M_PI);
    return 0;
}
""")

print(String(cString: occ_get_output(interp)))
```

### C++ Interpreter

```swift
let interp = ocpp_create()
defer { ocpp_destroy(interp) }

ocpp_execute(interp, """
#include <iostream>
#include <vector>
#include <algorithm>
using namespace std;

int main() {
    vector<int> v = {5, 2, 8, 1, 9, 3};
    sort(v.begin(), v.end());
    for (auto x : v) cout << x << " ";
    return 0;
}
""")
```

### Fortran Interpreter

```swift
let interp = ofortran_create()
defer { ofortran_destroy(interp) }

ofortran_execute(interp, """
PROGRAM hello
    IMPLICIT NONE
    REAL :: x
    x = 2.0
    WRITE(*, '(A, F10.6)') 'sqrt(2) = ', SQRT(x)
END PROGRAM hello
""")
```

---

## Architecture

```
python-ios-lib/
├── sklearn/              # Pure NumPy sklearn (40 modules, 12K+ lines)
├── matplotlib/           # Plotly-backed matplotlib shim (64 modules)
├── scipy/                # Cross-compiled scipy + iOS patches
├── manim/                # Math animation engine (iOS-adapted)
├── av/                   # PyAV — FFmpeg Python bindings (17 C modules)
├── cairo/                # pycairo — 2D vector graphics
├── PIL/                  # Pillow — image processing
├── offlinai_latex/       # Local LaTeX engine (pdftex C library)
├── gcc/                  # C/C++/Fortran interpreters
│   ├── offlinai_cc.c     #   C89/C99/C23 interpreter
│   ├── offlinai_cpp.c    #   C++17 interpreter
│   └── offlinai_fortran.c #  Fortran 90/95/2003 interpreter
├── docs/
│   └── libs/             # Detailed documentation
│       ├── numpy.md
│       ├── scipy.md
│       ├── sklearn.md    #   40 modules, 100+ classes
│       ├── matplotlib.md #   64 modules, 30+ plot types
│       ├── sympy.md
│       ├── manim.md      #   145+ mobjects, 73 animations
│       ├── media.md      #   PyAV, FFmpeg, Cairo, Pillow, LaTeX
│       └── interpreters.md
└── README.md
```

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 (via [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- NumPy 2.x (iOS arm64 wheel)
- Plotly (pure Python, for matplotlib backend)

## License

MIT
