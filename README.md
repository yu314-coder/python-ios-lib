# offlinai-libs

Pure-Python and native C/Fortran libraries for running **ML, math, plotting, and compiled code on iOS/iPadOS** -- no JIT, no compilation at runtime, App Store safe.

Provides drop-in replacements and iOS compatibility patches for popular Python libraries that can't run natively on iOS due to missing compilers, code-signing restrictions, or platform limitations.

## All Libraries

### Custom / Reimplemented

| Library | Type | Version | Coverage | Docs |
|---------|------|---------|----------|------|
| [**sklearn**](docs/sklearn.md) | Pure NumPy reimplementation | 1.8.0-offlinai | 12,077 lines, 40 modules | 100+ classes, full estimator API |
| [**matplotlib**](docs/matplotlib.md) | matplotlib API -> Plotly backend | 3.9.0-offlinai | 64 modules | 30+ plot types, 3D, subplots, colormaps |
| [**scipy (iOS patches)**](docs/scipy-ios.md) | Cross-compiled + runtime fixes | 1.15.2 | 18+ submodules | Fortran stub, dcabs1 fix, import guards |
| [**C interpreter**](docs/c-interpreter.md) | Tree-walking C89/C99/C23 interpreter | -- | ~3,450 lines | 70+ builtins, vmem pointers, C23 features |
| [**C++ interpreter**](docs/cpp-interpreter.md) | Tree-walking C++17 interpreter | -- | -- | Classes, templates, STL, lambdas |
| [**Fortran interpreter**](docs/fortran-interpreter.md) | Tree-walking Fortran 90/95/2003 interpreter | -- | -- | Modules, 7D arrays, 45+ intrinsics |
| [**Fortran runtime stub**](docs/fortran-runtime.md) | No-op I/O stubs for flang | -- | 22 symbols | Enables scipy Fortran modules on iOS |

### Stock Python Libraries (fully working)

| Library | Version | Docs |
|---------|---------|------|
| [**numpy**](docs/numpy.md) | 2.3.5 | Arrays, linalg (Accelerate), FFT, random, polynomials |
| [**sympy**](docs/sympy.md) | 1.14.0 | Symbolic math, calculus, solving, matrices, number theory |
| [**plotly**](docs/plotly.md) | 6.6.0 | 30+ interactive chart types, 3D, subplots |
| [**networkx**](docs/networkx.md) | 3.6.1 | Graph theory, centrality, community detection, shortest paths |
| [**Pillow (PIL)**](docs/pillow.md) | 12.2.0 | Image processing, drawing, filters, enhancement |
| [**BeautifulSoup (bs4)**](docs/beautifulsoup.md) | 4.14.3 | HTML/XML parsing, CSS selectors |
| [**PyYAML**](docs/pyyaml.md) | 6.0.3 | YAML parser/emitter |
| [**mpmath**](docs/mpmath.md) | 1.4.1 | Arbitrary-precision math, special functions |
| [**rich**](docs/rich.md) | 14.3.3 | Rich text formatting, tables, trees |
| [**tqdm**](docs/tqdm.md) | 4.67.3 | Progress bars |
| [**Pygments**](docs/pygments.md) | 2.20.0 | Syntax highlighting (300+ languages) |
| [**jsonschema**](docs/jsonschema.md) | 4.26.0 | JSON Schema validation |
| [**click**](docs/click.md) | 8.3.2 | CLI framework |
| [**svgelements**](docs/svgelements.md) | 1.9.6 | SVG path manipulation |
| [**pydub**](docs/pydub.md) | 0.25.1 | Audio manipulation & generation |
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

### C++ Interpreter

Add `offlinai_cpp.c` and `offlinai_cpp.h` to your Xcode project:

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
    cout << endl;
    return 0;
}
""")

print(String(cString: ocpp_get_output(interp)))
```

### Fortran Interpreter

Add `offlinai_fortran.c` and `offlinai_fortran.h` to your Xcode project:

```swift
let interp = ofortran_create()
defer { ofortran_destroy(interp) }

ofortran_execute(interp, """
PROGRAM hello
    IMPLICIT NONE
    REAL :: x, result
    x = 2.0
    result = SQRT(x)
    WRITE(*, '(A, F10.6)') 'sqrt(2) = ', result
END PROGRAM hello
""")

print(String(cString: ofortran_get_output(interp)))
```

---

## sklearn -- Pure NumPy ML

[Full documentation](docs/sklearn.md)

A complete reimplementation of scikit-learn's most-used classes using only NumPy. No compiled extensions needed.

**40 modules, 100+ classes** including:
- **Linear models:** LinearRegression, Ridge, Lasso, ElasticNet, LogisticRegression, SGDClassifier/Regressor, and 11 more
- **Trees:** DecisionTreeClassifier/Regressor, ExtraTreeClassifier/Regressor
- **Ensembles:** RandomForest, GradientBoosting, AdaBoost, Bagging, ExtraTrees, HistGradientBoosting, IsolationForest, Voting, Stacking
- **Clustering:** KMeans, DBSCAN, AgglomerativeClustering, SpectralClustering, MeanShift, OPTICS, Birch, HDBSCAN, and 4 more
- **Preprocessing:** 17 transformers (StandardScaler, OneHotEncoder, PolynomialFeatures, etc.)
- **Decomposition:** PCA, NMF, FastICA, TruncatedSVD, LDA, and 6 more
- **Metrics:** 38 functions (classification, regression, clustering)
- **Model selection:** train_test_split, cross_val_score, GridSearchCV, KFold, and 11 more
- **Plus:** SVM, Naive Bayes, Neural Networks, Gaussian Processes, Manifold Learning, Pipelines, Imputation, Feature Selection, and more

---

## matplotlib -- Plotly Backend

[Full documentation](docs/matplotlib.md)

Drop-in replacement for `matplotlib.pyplot` that renders interactive HTML charts via Plotly.js.

**64 modules** including:
- **30+ 2D plot types:** line, scatter, bar, histogram, pie, contour, heatmap, polar, errorbar, violin, boxplot, hexbin, quiver, streamplot
- **8 3D plot types:** surface, wireframe, scatter3D, bar3d, trisurf, contour3D
- **Colormaps:** 50+ colormaps with callable `cm.viridis()`, `cm.plasma()`, `cm.jet()`
- **Colors:** `to_rgba()` with full CSS4 support (148 named colors), custom colormaps
- **Ticker:** 10 locators, 10 formatters
- **Patches:** 14 shape classes (Rectangle, Circle, Polygon, FancyArrow, etc.)
- **Animation:** FuncAnimation, ArtistAnimation
- **GridSpec:** Flexible subplot grid layout
- **mpl_toolkits:** mplot3d, axes_grid1, axisartist

---

## scipy -- iOS Patches

[Full documentation](docs/scipy-ios.md)

Cross-compiled scipy 1.15.2 for iOS arm64 with runtime patches:

**18+ submodules** including:
- **optimize:** minimize (9 methods), curve_fit, root, linprog, differential_evolution, least_squares
- **integrate:** quad, solve_ivp (6 methods), trapezoid, simpson
- **stats:** 14+ continuous distributions, 8 discrete distributions, 20+ statistical tests
- **interpolate:** interp1d, CubicSpline, griddata, RBFInterpolator, and 15 more
- **linalg:** solve, inv, det, eig, svd, lu, cholesky, qr, expm, and 30 more (via Accelerate)
- **fft:** fft, rfft, dct, dst, fftfreq, and 15 more
- **signal:** butter, filtfilt, find_peaks, welch, spectrogram, cwt, and 30 more
- **spatial:** ConvexHull, Voronoi, Delaunay, cKDTree, 15 distance functions
- **sparse:** csr/csc/coo matrices, sparse solvers, eigensolvers
- **special:** gamma, erf, beta, bessel, elliptic, hypergeometric functions
- **ndimage:** gaussian_filter, label, morphology, distance transforms
- **cluster.hierarchy:** linkage, fcluster, dendrogram
- **constants:** Physical and mathematical constants

---

## C Interpreter

[Full documentation](docs/c-interpreter.md)

A ~3,450-line C89/C99/C23 interpreter with virtual memory, real pointers, and 48/49 tests passing.

**Supports:** Real pointer arithmetic (`&`, `*`, `ptr+i`), 2D arrays, structs, unions, enums, function pointers, `static` variables, `goto`/labels, function-like macros, compound literals, sprintf to buffer, 70+ built-in functions, `malloc`/`calloc`/`realloc`/`free` via virtual memory.

**C23 features:** `_Static_assert`, `_Generic`, `typeof`, `auto` type inference, `constexpr`, binary literals (`0b1010`), digit separators (`1'000'000`), `[[attributes]]`, `#warning`, `bool`/`true`/`false` keywords, `nullptr`.

---

## C++ Interpreter

[Full documentation](docs/cpp-interpreter.md)

A C++17 interpreter extending the C interpreter with object-oriented and modern C++ features.

**Supports:** Classes (public/private/protected), single inheritance, virtual functions, constructors/destructors with initializer lists, `new`/`delete`, references, `this` pointer, operator overloading, namespaces, `std::cout`/`cin`, `std::string`/`vector`/`map`/`pair`/`set`, `std::sort`/`find`/`count`, `auto` type deduction, range-based for loops, lambda expressions (captures by value/reference), function and class templates, `try`/`catch`/`throw`.

---

## Fortran Interpreter

[Full documentation](docs/fortran-interpreter.md)

A Fortran 90/95/2003 interpreter for numerical computing.

**Supports:** `PROGRAM`/`END PROGRAM`, `DO`/`DO WHILE` loops, `IF`/`THEN`/`ELSE`, `SELECT CASE` (with ranges), `SUBROUTINE`/`FUNCTION`/`MODULE` with `CONTAINS`, arrays up to 7 dimensions, `ALLOCATABLE` arrays, whole-array operations (`MATMUL`, `SUM`, `MAXVAL`), `WRITE`/`PRINT` with format descriptors (I, F, E, ES, A, L, X, /), 45+ intrinsic functions, case-insensitive parsing, dot-operators (`.EQ.`, `.AND.`, `.NOT.`), derived types, `IMPLICIT NONE`, `INTENT` attributes, recursive functions.

---

## Fortran Runtime Stub

[Full documentation](docs/fortran-runtime.md)

Provides 22 Fortran runtime symbols as no-ops so scipy's Fortran-compiled modules load on iOS. All I/O becomes silent; numerical computation is unaffected.

---

## Architecture

```
offlinai-libs/
├── sklearn/              # Pure NumPy sklearn (40 modules, 12K+ lines)
├── matplotlib/           # Plotly-backed matplotlib shim (64 modules)
│   ├── pyplot.py         #   72 functions, 4 classes
│   ├── cm.py             #   50+ colormaps (callable)
│   └── colors.py         #   to_rgba, CSS4, normalizations
├── scipy/                # Cross-compiled scipy + iOS patches
│   ├── _fortran_stub.c   #   Fortran runtime stub source
│   ├── _scipy_ios_fix.c  #   dcabs1 fix source
│   └── _ios_preload.py   #   Framework preloader
├── gcc/                  # Interpreters
│   ├── offlinai_cc.c     #   C89/C99/C23 interpreter
│   ├── offlinai_cc.h     #   C interpreter API
│   ├── offlinai_cpp.c    #   C++17 interpreter
│   ├── offlinai_cpp.h    #   C++ interpreter API
│   ├── offlinai_fortran.c #  Fortran 90/95/2003 interpreter
│   └── offlinai_fortran.h #  Fortran interpreter API
├── fortran/              # Fortran cross-compilation tools
│   └── ios-flang-wrapper.py
├── docs/                 # Detailed documentation
│   ├── sklearn.md        #   100+ classes across 40 modules
│   ├── matplotlib.md     #   64 modules, all plot types
│   ├── scipy-ios.md      #   18+ submodules with key functions
│   ├── c-interpreter.md  #   C89/C99/C23 features, 70+ builtins
│   ├── cpp-interpreter.md #  C++17: classes, STL, templates, lambdas
│   ├── fortran-interpreter.md # F90/95/2003: modules, arrays, intrinsics
│   ├── fortran-runtime.md #  22 Fortran runtime symbols
│   ├── numpy.md          #   Full NumPy reference
│   ├── sympy.md          #   Symbolic math reference
│   ├── plotly.md         #   30+ trace types
│   ├── networkx.md       #   Graph theory algorithms
│   ├── pillow.md         #   Image processing reference
│   ├── beautifulsoup.md  #   HTML parsing reference
│   ├── mpmath.md         #   Arbitrary-precision math
│   └── ...               #   14 more library docs
└── README.md
```

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Python 3.14 (via [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- numpy 2.x (iOS arm64 wheel)
- plotly (pure Python, for matplotlib backend)

## License

MIT
