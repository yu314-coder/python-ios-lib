# offlinai-libs

Pure-Python and native C libraries for running ML, math, plotting, and C code on **iOS/iPadOS** — no JIT, no compilation, App Store safe.

Built for [OfflinAi](https://github.com/user/OfflinAi), an iPad app that runs local LLMs with a full Python/C runtime.

## Libraries

### `sklearn/` — scikit-learn (pure numpy)

Drop-in replacement for scikit-learn's most-used algorithms, implemented entirely in numpy. No scipy dependency, no C extensions needed.

**Algorithms:**

| Module | Classes |
|---|---|
| `linear_model` | `LinearRegression`, `Ridge`, `Lasso`, `LogisticRegression` |
| `tree` | `DecisionTreeClassifier`, `DecisionTreeRegressor` |
| `neighbors` | `KNeighborsClassifier`, `KNeighborsRegressor` |
| `cluster` | `KMeans` |
| `svm` | `SVC`, `SVR` (linear kernel) |
| `preprocessing` | `StandardScaler`, `MinMaxScaler`, `LabelEncoder`, `PolynomialFeatures` |
| `metrics` | `accuracy_score`, `r2_score`, `mean_squared_error`, `confusion_matrix`, `classification_report`, `silhouette_score` |
| `model_selection` | `train_test_split`, `cross_val_score` |

**Usage:**
```python
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)
model = LinearRegression().fit(X_train, y_train)
print(f"R² = {model.score(X_test, y_test):.4f}")
```

**Installation:** Copy the `sklearn/` folder into your app's `site-packages/` directory.

---

### `matplotlib/` — matplotlib → plotly wrapper

Translates standard `matplotlib.pyplot` API calls into interactive Plotly charts. Any code that uses `plt.plot()`, `plt.scatter()`, `plt.contour()`, etc. works unchanged.

**Supported:**
- `plot`, `scatter`, `bar`, `barh`, `hist`, `pie`, `fill_between`, `stem`, `step`
- `errorbar`, `boxplot`, `violinplot`, `imshow`, `contour`, `contourf`, `polar`
- `hlines`, `vlines`, `axhline`, `axvline`, `axhspan`, `axvspan`
- `title`, `xlabel`, `ylabel`, `xlim`, `ylim`, `grid`, `legend`, `annotate`, `text`
- `figure`, `subplots`, `subplot`, `savefig`, `show`, `close`
- Full OO interface: `fig, ax = plt.subplots()`
- Matplotlib default color cycle and styling

**Requirements:** `numpy`, `plotly` (both available as iOS wheels)

**Installation:** Copy the `matplotlib/` folder into your app's `site-packages/` directory.

---

### `gcc/` — C interpreter

A lightweight C89/C90 interpreter written in pure C (~1600 lines). Executes C code on-device via tree-walking interpretation — no JIT, no code generation.

**Supported:**
- Types: `int`, `long long`, `float`, `double`, `char`, `void`, arrays, pointers
- Control flow: `if`/`else`, `for`, `while`, `do-while`, `switch`/`case`, `break`, `continue`, `return`
- Functions: user-defined with parameters, recursion
- Operators: all arithmetic, comparison, logical, bitwise, ternary, compound assignment, pre/post increment
- Builtins: `printf` (full format strings), `puts`, `putchar`, `strlen`, `strcmp`, `atoi`, `atof`
- Math: `sin`, `cos`, `tan`, `sqrt`, `pow`, `exp`, `log`, `fabs`, `ceil`, `floor`, `round`, `atan2`, `fmod`, etc.
- Constants: `M_PI`, `M_E`, `INT_MAX`, `LLONG_MAX`, `NULL`, `true`/`false`, `RAND_MAX`
- Other: `sizeof`, casts, `rand`/`srand`, `time`, `clock`, `exit`
- Preprocessor: `#include` and `#define` lines are skipped (no linker needed)
- Both `main()` mode and script mode

**Integration (Swift):**
```swift
// Add offlinai_cc.c and offlinai_cc.h to your Xcode project
// Add to your bridging header: #include "offlinai_cc.h"

let interp = occ_create()
defer { occ_destroy(interp) }

occ_execute(interp, """
#include <stdio.h>
#include <math.h>

int main() {
    for (int i = 1; i <= 10; i++) {
        printf("%d! = %lld\\n", i, factorial(i));
    }
    printf("pi = %.10f\\n", M_PI);
    return 0;
}

long long factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}
""")

let output = String(cString: occ_get_output(interp))
print(output)
```

**C API:**
```c
OccInterpreter *occ_create(void);
void occ_destroy(OccInterpreter *interp);
int occ_execute(OccInterpreter *interp, const char *source); // 0=success, -1=error
const char *occ_get_output(OccInterpreter *interp);
const char *occ_get_error(OccInterpreter *interp);
void occ_reset(OccInterpreter *interp);
```

---

### `scipy/` — scipy for iOS (WIP)

Status: **Blocked** — scipy requires a Fortran compiler for LAPACK/BLAS. No Fortran cross-compiler for iOS arm64 exists. Investigating:
- Building with Apple Accelerate framework (provides LAPACK/BLAS natively)
- Using `f2c` to transpile Fortran → C
- scipy's experimental no-Fortran build mode

---

## Requirements

- iOS 17.0+
- Python 3.14 (via [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
- numpy 2.x (iOS arm64 wheel)
- plotly (pure Python, for matplotlib wrapper)

## License

MIT
