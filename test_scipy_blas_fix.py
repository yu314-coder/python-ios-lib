#!/usr/bin/env python3
"""
test_scipy_blas_fix.py — verify the scipy.linalg / cython_blas `dcabs1` fix
(python-ios-lib issue #2) works on a real iOS device.

Run this INSIDE the app (CodeBench Run button, or any python-ios-lib host —
NOT on macOS, where the iOS-built scipy can't load). Before the fix the very
first import crashed with:

    symbol not found in flat namespace '_dcabs1_'

After the fix every section below should print [PASS].
"""
import sys
import platform
import traceback

PASS, FAIL = "PASS", "FAIL"
_results = []


def check(name, fn):
    """Run fn(); record + print PASS/FAIL. Never raises."""
    try:
        detail = fn()
        _results.append((PASS, name))
        print("  [PASS] " + name + (("   " + detail) if detail else ""))
    except BaseException as e:  # BaseException → also catch the dyld abort surface
        last = traceback.format_exc().strip().splitlines()[-1]
        _results.append((FAIL, name))
        print("  [FAIL] " + name + "\n         " + last)


print("=" * 66)
print(" scipy BLAS-helper (dcabs1) fix test  —  python-ios-lib issue #2")
print("=" * 66)
print("python   : " + sys.version.split()[0])
print("platform : " + platform.platform())
try:
    import scipy
    print("scipy    : " + scipy.__version__)
except Exception as e:
    print("scipy    : IMPORT FAILED — " + repr(e))

# ── 1. The imports that crashed in issue #2 (the load-time symbol test) ──
print("\n-- 1. imports that triggered the crash --")


def _imp_signal():
    from scipy.signal import butter, sosfiltfilt, find_peaks, savgol_filter  # noqa: F401


def _imp_windows():
    from scipy.signal.windows import gaussian  # noqa: F401


def _imp_linalg():
    from scipy import linalg  # noqa: F401  (loads cython_blas + cython_lapack .so)


check("from scipy.signal import butter, sosfiltfilt, find_peaks, savgol_filter", _imp_signal)
check("from scipy.signal.windows import gaussian", _imp_windows)
check("from scipy import linalg", _imp_linalg)

# ── 2. Exercise the dcabs1 code path: complex BLAS / LAPACK ──────────────
# dcabs1 (|Re|+|Im|) is used by complex-BLAS routines like izamax, which
# drive pivoting in the complex LU (zgetrf) behind a complex linalg.solve.
print("\n-- 2. exercise dcabs1: complex BLAS / linalg --")


def _complex_solve():
    import numpy as np
    from scipy import linalg
    A = np.array([[2 + 1j, 1 - 1j], [0 + 1j, 3 + 2j]], dtype=complex)
    b = np.array([1 + 0j, 2 - 1j], dtype=complex)
    x = linalg.solve(A, b)
    assert np.allclose(A @ x, b), "complex solve gave a wrong answer"
    return "solve(2x2 complex) ok"


def _complex_eig():
    import numpy as np
    from scipy import linalg
    A = np.array([[0 + 0j, -1 + 0j], [1 + 0j, 0 + 0j]], dtype=complex)
    w = linalg.eigvals(A)            # complex eigenvalues → complex BLAS
    assert np.allclose(sorted(w, key=lambda z: z.imag), [-1j, 1j]), "eig wrong"
    return "eigvals(complex) ok"


check("scipy.linalg.solve on a complex matrix", _complex_solve)
check("scipy.linalg.eigvals on a complex matrix", _complex_eig)

# ── 3. The reporter's actual signal-processing pipeline ─────────────────
print("\n-- 3. the reporter's actual pipeline --")


def _pipeline():
    import numpy as np
    from scipy.signal import butter, sosfiltfilt, find_peaks, savgol_filter
    from scipy.signal.windows import gaussian
    fs = 200.0
    t = np.linspace(0, 5, int(fs * 5), endpoint=False)
    rng = np.random.default_rng(0)
    x = np.sin(2 * np.pi * 3 * t) + 0.5 * np.sin(2 * np.pi * 40 * t) + 0.2 * rng.standard_normal(t.size)
    sos = butter(4, 10, btype="low", fs=fs, output="sos")
    y = sosfiltfilt(sos, x)
    y = savgol_filter(y, 11, 3)
    peaks, _ = find_peaks(y, height=0)
    w = gaussian(51, std=7)
    assert y.shape == x.shape and w.shape == (51,)
    return "filtered %d samples, %d peaks, window_sum=%.2f" % (x.size, len(peaks), float(w.sum()))


check("butter + sosfiltfilt + savgol_filter + find_peaks + gaussian", _pipeline)

# ── Summary ─────────────────────────────────────────────────────────────
print("\n" + "=" * 66)
npass = sum(1 for r in _results if r[0] == PASS)
total = len(_results)
nfail = total - npass
if nfail == 0:
    print("RESULT: %d/%d passed  —  scipy BLAS (dcabs1) fix OK ✓" % (npass, total))
    print("=" * 66)
else:
    print("RESULT: %d/%d passed, %d FAILED" % (npass, total, nfail))
    print("\nIf a failure says \"symbol not found in flat namespace '_dcabs1_'\":")
    print("  * the patched cython_blas.so or libscipy_blas_stubs.dylib didn't reach the build.")
    print("  * confirm Frameworks/scipy_aux/libscipy_blas_stubs.dylib was copied into the")
    print("    app's Frameworks/ (step 4.2 of the README) and is code-signed.")
    print("  * after any scipy rebuild, re-run scripts/appstore/build-blas-stubs.sh.")
    print("=" * 66)
    sys.exit(1)
