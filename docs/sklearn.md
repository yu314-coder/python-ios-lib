# scikit-learn (sklearn) — real native Cython build

> **Version:** 1.9.0 | **Type:** Native iOS arm64 (real upstream Cython cross-compile) | **Extensions:** 69 `.cpython-314-iphoneos.so` | **Submodules:** 39 (full API) | **Location:** `sklearn/`

This is the **real, full scikit-learn 1.9.0** — the upstream Cython/C++ package cross-compiled for iOS arm64 — not a reimplementation. It replaces the previous pure-NumPy reimpl (`1.8.0-offlinai`, ~40 modules / "85% of workflows") with the complete upstream library: every estimator, every submodule, the genuine Cython kernels, and the libsvm/liblinear C++. As far as we can tell, the **first public iOS build of scikit-learn**.

It sits on the bundled native **numpy** (Accelerate/AMX) and **scipy**, plus pure-Python **joblib**, **threadpoolctl**, and **narwhals**.

---

## Quick Start

```python
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

X, y = make_classification(n_samples=200, n_features=4, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3)

clf = RandomForestClassifier(n_estimators=10, max_depth=5)
clf.fit(X_train, y_train)
print(f"Accuracy: {accuracy_score(y_test, clf.predict(X_test)):.3f}")
```

Because it's the real library, the **full upstream API** is available and behaves exactly as documented at [scikit-learn.org](https://scikit-learn.org) — `fit` / `predict` / `transform` / `score` / `predict_proba` / `decision_function` / `get_params` / `set_params`, pipelines, grid search, the lot.

---

## What's included — all 39 submodules

Every public submodule imports and runs (verified on-device, see below):

`calibration · cluster · covariance · cross_decomposition · datasets · decomposition · discriminant_analysis · dummy · ensemble · exceptions · experimental · feature_extraction · feature_selection · gaussian_process · impute · inspection · isotonic · kernel_approximation · kernel_ridge · linear_model · manifold · metrics · mixture · model_selection · multiclass · multioutput · naive_bayes · neighbors · neural_network · pipeline · preprocessing · random_projection · semi_supervised · svm · tree · utils` (+ `base`, `pipeline`, `compose`, top-level `clone`/`get_config`/`set_config`/`config_context`/`show_versions`).

The heavy compiled kernels are all present and numerically correct: `tree`/`ensemble` (decision trees, gradient boosting, **HistGradientBoosting**), `svm` (**libsvm + liblinear** C++), `neighbors` (KD-/Ball-tree), `cluster` (`_kmeans`), `linear_model` (`_cd_fast`, `_sgd_fast`, `_sag`), `metrics` (`_pairwise`, `_dist_metrics`), `manifold` (Barnes-Hut TSNE), `decomposition`, `_loss`, and the shared `_cyutility` module.

---

## iOS-specific notes & caveats

- **Serial (no OpenMP).** iOS has no `libomp`, so the OpenMP-parallel kernels are built serial (`SKLEARN_OPENMP_PARALLELISM_ENABLED=0`, gated on `_OPENMP`). Results are identical; only intra-estimator multi-core is unavailable. (A cross-compiled `libomp` could enable it later.)
- **`n_jobs > 1`** uses joblib's default **loky** backend, which needs `fork()` — unavailable on iOS. Use `n_jobs=1` (default) or `joblib.parallel_backend("threading")`.
- **Built against** numpy 2.4.x / scipy 1.17.x headers; the device runs numpy 2.3.5 / scipy 1.15.0. The numpy/scipy C-API is capsule-based and ABI-stable across 2.x (`NPY_NO_DEPRECATED_API`), so this is compatible — and confirmed on-device.
- Extensions resolve Python / numpy / scipy at runtime (`-undefined dynamic_lookup` + capsules); they link only `libSystem` + `libc++`.

## How it's built

Cross-compiled with a BeeWare **cross-venv** (host venv patched to report iOS sysconfig) + a meson cross-file pointing at the `arm64-apple-ios-clang` wrappers, via `pip wheel --no-build-isolation --config-settings=setup-args=--cross-file=…`. Harness + recipe: `sklearn_ios/` (`ios-cross.ini`, `build` notes). Two gotchas worth knowing: meson must use **Cython 3.1.x** (the host's 3.0.12 rejects sklearn's `cdef const`), and the OpenMP dependency must be forced not-found (else meson links the macOS Homebrew `libomp`). The previous pure-NumPy reimpl is kept at `sklearn_ios/sklearn_reimpl_backup/`.

## Verification

Validated on-device (CodeBench, "Designed for iPad" / real device) with `sklearn_ios/test_sklearn_on_device.py`: it imports every submodule and runs real-value correctness checks — recovered linear coefficients exactly, `MSE=1/3`, `ROC-AUC=0.75`, PCA explained-variance `0.9777` + lossless reconstruction, KMeans/GMM `ARI=1.000`, the libsvm/liblinear C++, KD-trees, and Barnes-Hut TSNE all correct. **66/66 checks pass.**

## See also

- [docs/numpy.md](numpy.md) — the Accelerate-backed numpy underneath
- [docs/scipy-ios.md](scipy-ios.md) — the native scipy underneath
- [docs/torch.md](torch.md) — PyTorch (separate ML stack)
