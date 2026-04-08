# scipy - iOS Compatibility Patches

> **Version:** 1.15.2 (stock scipy + iOS patches) | **Location:** `scipy/`

scipy is cross-compiled for iOS arm64 using flang (Fortran) + Accelerate (BLAS/LAPACK). These patches make it load and run on iOS where some native modules fail.

---

## Quick Start

```python
import numpy as np
from scipy.optimize import minimize
from scipy.stats import ttest_1samp
from scipy.interpolate import interp1d
from scipy.linalg import solve

# Optimization
result = minimize(lambda x: (x[0]-1)**2 + (x[1]-2)**2, [0, 0], method='Nelder-Mead')
print(f"Minimum at: {result.x}")

# Statistics
data = np.random.randn(100) + 0.5
t_stat, p_val = ttest_1samp(data, 0)
print(f"t={t_stat:.3f}, p={p_val:.4f}")
```

---

## Patches Applied

### 1. Fortran Runtime Stub - `_fortran_stub.cpython-314-iphoneos.so`

16 scipy modules (COBYLA, LSODA, ARPACK, etc.) are compiled with flang and need Fortran I/O runtime symbols. iOS doesn't ship flang's runtime, so we provide no-op stubs.

**Symbols provided (22):**

| Symbol | Purpose |
|--------|---------|
| `_FortranAioBeginExternalFormattedOutput` | Start formatted WRITE |
| `_FortranAioBeginExternalListOutput` | Start list-directed WRITE |
| `_FortranAioEndIoStatement` | End I/O statement |
| `_FortranAioOutputAscii` | Output string |
| `_FortranAioOutputInteger32` | Output int |
| `_FortranAioOutputReal64` | Output double |
| `_FortranAioOutputReal32` | Output float |
| `_FortranAioOutputComplex32/64` | Output complex |
| `_FortranAioOutputDescriptor` | Output descriptor |
| `_FortranAioBeginOpenUnit` | Open file unit |
| `_FortranAioBeginClose` | Close file unit |
| `_FortranAioSetFile/Form/Status` | Set I/O properties |
| `_FortranAStopStatement` | Fortran STOP (no-op) |
| `_FortranAStopStatementText` | Fortran STOP with message |
| `_FortranATrim` | String TRIM intrinsic |
| `_FortranAModReal8` | Real*8 MOD intrinsic |

**Effect:** Fortran WRITE/PRINT become silent. Diagnostic output from legacy Fortran code is suppressed, but computation is unaffected.

### 2. dcabs1 Fix - `_scipy_ios_fix.cpython-314-iphoneos.so`

Apple's Accelerate framework doesn't include the `dcabs1` BLAS function.

```c
double dcabs1_(const double *z) {
    return fabs(z[0]) + fabs(z[1]);  // |Re(z)| + |Im(z)|
}
```

### 3. libsf_error_state - Install Name Fix

scipy.special's `_ufuncs`, `_special_ufuncs`, `_ufuncs_cxx`, `_gufuncs`, `cython_special`, `_ellip_harm_2` all reference `libsf_error_state.dylib`. After iOS framework conversion, the path breaks.

**Fix:** `install_name_tool -change` on all 6 `.so` files to point to the correct framework path.

### 4. iOS Preload Mechanism - `_ios_preload.py`

```python
# Loaded at scipy import time, before any submodule
def _load_framework(so_name, base_dir):
    # Reads .fwork file -> resolves framework binary path -> ctypes.CDLL(RTLD_GLOBAL)
```

Load order:
1. `_fortran_stub` (Fortran runtime)
2. `_scipy_ios_fix` (dcabs1)
3. `libsf_error_state` (special function error state)

### 5. Import Cascade Protection

All scipy submodule `__init__.py` files wrapped with `try/except`:

| Module | Wrapping |
|--------|----------|
| `scipy.optimize` | All 30+ imports via `_try_import()` helper |
| `scipy.stats` | `_binomtest`, `_kde`, `mstats`, `qmc`, etc. |
| `scipy.fft` | `_basic`, `_realtransforms`, `_fftlog`, `_helper`, etc. |
| `scipy.special` | `_ufuncs`, `_basic`, `_multiufuncs` |
| `scipy.sparse.linalg` | `_eigen`, `_propack` |
| `scipy.io.matlab` | MATLAB I/O |

---

## Working Submodules

| Module | Status | Notes |
|--------|--------|-------|
| `scipy.optimize` | Partial | `minimize` (Nelder-Mead, BFGS, Powell), `brentq`, `differential_evolution` work. COBYLA/SLSQP may fail. |
| `scipy.linalg` | Works | `solve`, `inv`, `det`, `eig`, `svd`, `lu`, `cholesky` via Accelerate |
| `scipy.stats` | Partial | `ttest_1samp`, `norm`, `pearsonr`, `spearmanr` work. Some tests need optimize. |
| `scipy.interpolate` | Works | `interp1d`, `CubicSpline`, `UnivariateSpline` |
| `scipy.integrate` | Partial | `quad`, `trapezoid` work. `odeint` needs Fortran (may fail). |
| `scipy.fft` | Partial | Basic FFT works. `fht`/`ifht` need special functions. |
| `scipy.signal` | Partial | `butter`, `filtfilt`, `convolve` work. |
| `scipy.sparse` | Partial | Basic sparse matrices. ARPACK eigensolver may fail. |
| `scipy.special` | Partial | Depends on `_ufuncs` loading. |

---

## Not Working

- Modules requiring full Fortran I/O (COBYLA with verbose output)
- Some sparse eigensolvers (ARPACK)
- `scipy.io.matlab` (may have import issues)
- Full `scipy.special` function set (depends on `_ufuncs` platform load)
