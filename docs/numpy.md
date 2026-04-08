# NumPy

> **Version:** 2.3.5.post1 | **Type:** Stock (pre-built iOS arm64 wheel) | **Status:** Fully working

Standard NumPy compiled for iOS arm64 via cibuildwheel. All features work including linear algebra (via Accelerate), FFT, random, and broadcasting.

---

## iOS-Specific Notes

- `.so` files are converted to signed `.framework` bundles by the Install Python build phase
- `SafeArray` subclass patches numpy array creation to fix `__bool__` for iOS (ndarray is a C type and can't be monkey-patched)
- Code signing requires `alwaysOutOfDate = 1` on the Install Python build phase

## Key Modules

```python
import numpy as np

# Arrays & Linear Algebra
A = np.array([[3, 2, -1], [2, -2, 4], [-1, 0.5, -1]])
b = np.array([1, -2, 0])
x = np.linalg.solve(A, b)
print("Solution:", x)

# Eigenvalues
evals, evecs = np.linalg.eig(A)
print("Eigenvalues:", evals)

# FFT
t = np.linspace(0, 1, 1000)
signal = np.sin(2*np.pi*5*t) + 0.5*np.sin(2*np.pi*12*t)
freqs = np.fft.rfftfreq(len(t), 1/1000)
spectrum = np.abs(np.fft.rfft(signal))

# Random
rng = np.random.default_rng(42)
samples = rng.normal(0, 1, size=1000)
print(f"Mean: {samples.mean():.4f}, Std: {samples.std():.4f}")

# Statistics
data = np.random.randn(1000)
print(f"Median: {np.median(data):.4f}")
print(f"Percentile 95: {np.percentile(data, 95):.4f}")
```

## Available Submodules

| Module | Functions |
|--------|-----------|
| `np.linalg` | `solve`, `inv`, `det`, `eig`, `eigvals`, `svd`, `norm`, `qr`, `cholesky`, `lstsq`, `matrix_rank` |
| `np.fft` | `fft`, `ifft`, `rfft`, `irfft`, `fft2`, `fftfreq`, `rfftfreq` |
| `np.random` | `rand`, `randn`, `randint`, `choice`, `shuffle`, `normal`, `uniform`, `default_rng` |
| `np.polynomial` | `polyfit`, `polyval`, `roots`, `poly1d` |
| Core | `array`, `zeros`, `ones`, `linspace`, `arange`, `meshgrid`, `outer`, `dot`, `cross`, `where`, `clip`, `sort`, `argsort`, `unique`, `concatenate`, `stack`, `reshape`, `transpose` |

## Not Available

None — this is a full NumPy build. All features work.
