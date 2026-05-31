# Fixing scipy on iOS — `symbol not found in flat namespace '_dcabs1_'`

Tracking: [issue #2](https://github.com/yu314-coder/python-ios-lib/issues/2)

## Symptom

On a **real iOS device** (the Simulator and "My Mac (Designed for iPad)"
can differ), importing anything that pulls in `scipy.linalg.cython_blas`
— e.g. `scipy.signal`, `scipy.linalg` — aborts at load time:

```
dyld: symbol not found in flat namespace '_dcabs1_'
```

## Cause

`scipy.linalg.cython_blas` references three small **reference-BLAS helper**
routines: `dcabs1`, `scabs1`, and `lsame`. Apple's **Accelerate** framework
provides the heavy BLAS/LAPACK kernels (`dgemm`, `zgesv`, …) but does **not**
export `dcabs1` / `scabs1`. Because `cython_blas` resolves those symbols in
the **flat** namespace, `dyld` aborts the moment it can't find `dcabs1`.

(`lsame` *is* present in Accelerate — it's two-level-bound and resolves
fine; only `dcabs1` / `scabs1` are genuinely missing.)

## The easy fix (recommended for apps embedding python-ios-lib)

Add **one tiny C file** to your **app target** so the missing symbols live
in your main executable. The flat-namespace lookup then resolves against it
— no need to patch scipy or ship any extra dylib:

```c
// blas_compat_stubs.c — reference-BLAS helpers Accelerate omits on iOS.
// Fortran name-mangling adds a trailing underscore, so the exported
// symbols are _dcabs1_, _scabs1_, _lsame_.
#include <math.h>

double dcabs1_(const double *z) { return fabs(z[0]) + fabs(z[1]); }
float  scabs1_(const float  *c) { return fabsf(c[0]) + fabsf(c[1]); }

int lsame_(const char *ca, const char *cb, long ca_len, long cb_len) {
    (void)ca_len; (void)cb_len;
    int a = (unsigned char)ca[0], b = (unsigned char)cb[0];
    if (a >= 'a' && a <= 'z') a -= 32;
    if (b >= 'a' && b <= 'z') b -= 32;
    return a == b;
}
```

1. Add `blas_compat_stubs.c` to your Xcode target (**Build Phases → Compile
   Sources**).
2. Rebuild and run on device.

`import scipy.signal` / `scipy.linalg` now load. (The source above is
`fortran/blas_compat_stubs.c` in this repo.)

## What python-ios-lib bundles

So the package "just works" without app changes, we also ship a prebuilt
helper dylib and wire it into scipy:

- `Frameworks/scipy_aux/libscipy_blas_stubs.dylib` — the three helpers,
  built for `arm64-apple-ios`, ad-hoc signed, `install_name`
  `@rpath/libscipy_blas_stubs.dylib`.
- An `LC_LOAD_DYLIB` is added to every `scipy/linalg/cython_blas*.so` so the
  flat-namespace `_dcabs1_` resolves against the dylib at runtime.
- `scripts/appstore/build-blas-stubs.sh` rebuilds + re-signs both, and is
  idempotent — re-run it after any scipy rebuild.

If you embed the package, make sure `libscipy_blas_stubs.dylib` is copied
into your app's `Frameworks/` and is reachable via an `@rpath` entry (or
just use the easy fix above and skip the dylib entirely).

## Verifying

Run [`test_scipy_blas_fix.py`](../test_scipy_blas_fix.py) **on device**. It
imports the routines that used to crash and exercises the `dcabs1` code path
via complex `linalg.solve` / `eigvals` and a
`butter → sosfiltfilt → savgol_filter → find_peaks → gaussian` pipeline.
All lines should print `[PASS]`.
