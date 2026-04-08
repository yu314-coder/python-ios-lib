# python-ios-lib

Pure-Python and native C/Fortran libraries for running **ML, math, plotting, and C code on iOS/iPadOS** — no JIT, no compilation, App Store safe.

Provides drop-in replacements and iOS compatibility patches for popular Python libraries that can't run natively on iOS due to missing compilers, code-signing restrictions, or platform limitations.

## All Libraries

### Custom / Reimplemented

| Library | Type | Coverage | Docs |
|---------|------|----------|------|
| [**sklearn**](docs/sklearn.md) | Pure NumPy reimplementation | ~85% of common APIs | 13 modules, 40+ classes |
| [**matplotlib**](docs/matplotlib.md) | matplotlib API -> Plotly backend | ~75% of pyplot | 25+ plot types, 3D, subplots |
| [**scipy (iOS patches)**](docs/scipy-ios.md) | Cross-compiled + runtime fixes | ~60% of submodules | Fortran stub, dcabs1 fix, import guards |
| [**C interpreter**](docs/c-interpreter.md) | Tree-walking C89/C99 interpreter | ~70% of C language | 60+ built-in functions, structs, preprocessor |
| [**Fortran runtime stub**](docs/fortran-runtime.md) | No-op I/O stubs for flang | 22 symbols | Enables scipy Fortran modules on iOS |

### Stock Python Libraries (fully working)

| Library | Version | Docs |
|---------|---------|------|
| [**numpy**](docs/numpy.md) | 2.3.5 | Arrays, linalg, FFT, random |
| [**sympy**](docs/sympy.md) | 1.14.0 | Symbolic math, calculus, solving |
| [**plotly**](docs/plotly.md) | 6.6.0 | Interactive charts (rendering engine) |
| [**networkx**](docs/networkx.md) | 3.6.1 | Graph theory, network analysis |
| [**Pillow (PIL)**](docs/pillow.md) | 12.2.0 | Image processing |
| [**BeautifulSoup (bs4)**](docs/beautifulsoup.md) | 4.14.3 | HTML/XML parsing |
| [**PyYAML**](docs/pyyaml.md) | 6.0.3 | YAML parser/emitter |
| [**mpmath**](docs/mpmath.md) | 1.4.1 | Arbitrary-precision math |
| [**rich**](docs/rich.md) | 14.3.3 | Rich text formatting |
| [**tqdm**](docs/tqdm.md) | 4.67.3 | Progress bars |
| [**Pygments**](docs/pygments.md) | 2.20.0 | Syntax highlighting |
| [**jsonschema**](docs/jsonschema.md) | 4.26.0 | JSON Schema validation |
| [**click**](docs/click.md) | 8.3.2 | CLI framework |
| [**svgelements**](docs/svgelements.md) | 1.9.6 | SVG path manipulation |
| [**pydub**](docs/pydub.md) | 0.25.1 | Audio manipulation |
| [**PyAV (av)**](docs/av-pyav.md) | 17.0.1 | FFmpeg Python bindings |
| [**manim**](docs/manim.md) | 0.20.1 | Math animations (experimental) |
| [**Minor libs**](docs/minor-libs.md) | various | attrs, packaging, srt, cffi, pycairo, rpds, etc. |

---

## Quick Start

### Python Libraries

Copy the library folder into your app's `site-packages/` directory:

```
YourApp.app/
  app_packages/
    site-packages/
      sklearn/          <- drop in
      matplotlib/       <- drop in (requires plotly)
      scipy/            <- cross-compiled + patches
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
    printf("e  = %.10f\\n", M_E);
    return 0;
}
""")

print(String(cString: occ_get_output(interp)))
```

---

## sklearn - Pure NumPy ML

[Full documentation](docs/sklearn.md)

A complete reimplementation of scikit-learn's most-used classes using only NumPy. No compiled extensions needed.

```python
from sklearn.ensemble import RandomForestClassifier
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

X, y = make_classification(n_samples=500, n_features=10, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3)
clf = RandomForestClassifier(n_estimators=20, max_depth=5).fit(X_train, y_train)
print(f"Accuracy: {accuracy_score(y_test, clf.predict(X_test)):.3f}")
```

**40+ classes** across 13 modules: linear models, trees, ensembles, clustering, SVM, naive bayes, preprocessing, decomposition, metrics, model selection, pipeline, datasets.

---

## matplotlib - Plotly Backend

[Full documentation](docs/matplotlib.md)

Drop-in replacement for `matplotlib.pyplot` that renders interactive HTML charts via Plotly.js.

```python
import numpy as np
import matplotlib.pyplot as plt

# 2D - works exactly like real matplotlib
x = np.linspace(0, 2*np.pi, 200)
plt.plot(x, np.sin(x), label='sin(x)')
plt.plot(x, np.cos(x), label='cos(x)')
plt.title('Trig Functions')
plt.legend()
plt.grid(True)
plt.show()

# 3D - also works
fig = plt.figure()
ax = fig.add_subplot(111, projection='3d')
u, v = np.linspace(0, 2*np.pi, 50), np.linspace(0, np.pi, 50)
X = np.outer(np.cos(u), np.sin(v))
Y = np.outer(np.sin(u), np.sin(v))
Z = np.outer(np.ones_like(u), np.cos(v))
ax.plot_surface(X, Y, Z, cmap='viridis')
plt.show()
```

**25+ plot types** including line, scatter, bar, histogram, pie, contour, heatmap, 3D surface, wireframe, polar, subplots, dual axes.

---

## scipy - iOS Patches

[Full documentation](docs/scipy-ios.md)

Cross-compiled scipy 1.15.2 for iOS arm64 with runtime patches:

- **Fortran runtime stub** — 22 no-op symbols for Fortran I/O
- **dcabs1 fix** — Missing BLAS function stub
- **libsf_error_state** — Install name rewriting for framework conversion
- **Import cascade guards** — try/except wrappers on all submodule imports

```python
from scipy.optimize import minimize
from scipy.stats import ttest_1samp, norm
from scipy.linalg import solve
from scipy.interpolate import interp1d

result = minimize(lambda x: (x[0]-1)**2 + (x[1]-2.5)**2, [0, 0], method='Nelder-Mead')
print(f"Minimum at: {result.x.round(4)}")
```

---

## C Interpreter

[Full documentation](docs/c-interpreter.md)

A ~2200-line C89/C99 interpreter. Lexer -> recursive descent parser -> tree-walking execution.

```c
#include <stdio.h>
#include <math.h>

struct Point { double x; double y; };

double distance(struct Point a, struct Point b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
}

int main() {
    struct Point p1 = {3.0, 4.0};
    struct Point p2 = {7.0, 1.0};
    printf("Distance: %.4f\n", distance(p1, p2));
    return 0;
}
```

**Supports:** 6 data types, 48 operators, structs, enums, `#ifdef`/`#ifndef`/`#endif`, 60+ built-in functions (printf, math, string, char classification, memory).

---

## Fortran Runtime Stub

[Full documentation](docs/fortran-runtime.md)

Provides 22 Fortran runtime symbols as no-ops so scipy's Fortran-compiled modules load on iOS. All I/O becomes silent; numerical computation is unaffected.

---

## Architecture

```
python-ios-lib/
├── sklearn/              # Pure NumPy sklearn (13 .py files)
├── matplotlib/           # Plotly-backed matplotlib shim
│   ├── pyplot.py         #   72 functions, 4 classes
│   └── cm.py             #   50 colormaps
├── scipy/                # Cross-compiled scipy + iOS patches
│   ├── _fortran_stub.c   #   Fortran runtime stub source
│   ├── _scipy_ios_fix.c  #   dcabs1 fix source
│   └── _ios_preload.py   #   Framework preloader
├── gcc/                  # C interpreter
│   ├── offlinai_cc.c     #   ~2200 lines, full interpreter
│   └── offlinai_cc.h     #   Public API header
├── fortran/              # Fortran cross-compilation tools
│   └── ios-flang-wrapper.py
├── docs/                 # Detailed documentation
│   ├── sklearn.md
│   ├── matplotlib.md
│   ├── scipy-ios.md
│   ├── c-interpreter.md
│   └── fortran-runtime.md
└── README.md
```

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 (via [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- numpy 2.x (iOS arm64 wheel)
- plotly (pure Python, for matplotlib backend)

## License

MIT
