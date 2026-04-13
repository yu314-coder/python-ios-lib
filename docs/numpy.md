# NumPy

> **Version:** 2.3.5.post1 | **Type:** Stock (pre-built iOS arm64 wheel) | **Status:** Fully working

Standard NumPy compiled for iOS arm64 via cibuildwheel. All features work including linear algebra (via Accelerate), FFT, random, and broadcasting.

---

## iOS-Specific Notes

- `.so` files are converted to signed `.framework` bundles by the Install Python build phase
- `SafeArray` subclass patches numpy array creation to fix `__bool__` for iOS (ndarray is a C type and can't be monkey-patched)
- Code signing requires `alwaysOutOfDate = 1` on the Install Python build phase

---

## Quick Start

```python
import numpy as np

A = np.array([[3, 2, -1], [2, -2, 4], [-1, 0.5, -1]])
b = np.array([1, -2, 0])
x = np.linalg.solve(A, b)
print("Solution:", x)
```

---

## Array Creation

| Function | Description |
|----------|-------------|
| `np.array(object, dtype)` | Create array from list/tuple |
| `np.zeros(shape, dtype)` | Array of zeros |
| `np.ones(shape, dtype)` | Array of ones |
| `np.empty(shape, dtype)` | Uninitialized array |
| `np.full(shape, fill_value, dtype)` | Array filled with value |
| `np.zeros_like(a)` | Zeros with same shape/dtype |
| `np.ones_like(a)` | Ones with same shape/dtype |
| `np.empty_like(a)` | Empty with same shape/dtype |
| `np.full_like(a, fill_value)` | Fill with same shape/dtype |
| `np.arange(start, stop, step, dtype)` | Evenly spaced values (like range) |
| `np.linspace(start, stop, num)` | Evenly spaced values (specify count) |
| `np.logspace(start, stop, num, base)` | Log-spaced values |
| `np.geomspace(start, stop, num)` | Geometric-spaced values |
| `np.eye(N, M, k, dtype)` | Identity matrix (or diagonal offset k) |
| `np.identity(n, dtype)` | Square identity matrix |
| `np.diag(v, k)` | Diagonal matrix from vector (or extract diagonal) |
| `np.meshgrid(*xi, indexing)` | Coordinate matrices from vectors |
| `np.mgrid[slices]` | Dense meshgrid via indexing |
| `np.ogrid[slices]` | Open meshgrid |
| `np.fromfunction(function, shape)` | Array from function of indices |
| `np.fromiter(iterable, dtype, count)` | Array from iterator |
| `np.frombuffer(buffer, dtype)` | Array from buffer |
| `np.tile(A, reps)` | Repeat array along axes |
| `np.repeat(a, repeats, axis)` | Repeat elements |
| `np.tri(N, M, k, dtype)` | Lower triangular array |
| `np.tril(m, k)` | Lower triangle of array |
| `np.triu(m, k)` | Upper triangle of array |
| `np.vander(x, N, increasing)` | Vandermonde matrix |

---

## Array Manipulation

| Function | Description |
|----------|-------------|
| `np.reshape(a, newshape)` | Reshape array |
| `np.ravel(a)` | Flatten to 1D |
| `np.flatten()` | Flatten (returns copy) |
| `np.transpose(a, axes)` / `a.T` | Transpose |
| `np.swapaxes(a, axis1, axis2)` | Swap two axes |
| `np.moveaxis(a, source, destination)` | Move axis position |
| `np.expand_dims(a, axis)` | Add dimension |
| `np.squeeze(a, axis)` | Remove length-1 dimensions |
| `np.concatenate(arrays, axis)` | Join arrays along axis |
| `np.stack(arrays, axis)` | Stack arrays along new axis |
| `np.vstack(tup)` | Stack vertically (row-wise) |
| `np.hstack(tup)` | Stack horizontally (column-wise) |
| `np.dstack(tup)` | Stack depth-wise (3rd axis) |
| `np.column_stack(tup)` | Stack as columns |
| `np.split(ary, indices_or_sections, axis)` | Split into sub-arrays |
| `np.hsplit(ary, indices)` | Horizontal split |
| `np.vsplit(ary, indices)` | Vertical split |
| `np.dsplit(ary, indices)` | Depth split |
| `np.flip(m, axis)` | Reverse elements |
| `np.fliplr(m)` | Flip left-right |
| `np.flipud(m)` | Flip up-down |
| `np.rot90(m, k)` | Rotate 90 degrees k times |
| `np.roll(a, shift, axis)` | Roll elements |
| `np.pad(array, pad_width, mode)` | Pad array |
| `np.insert(arr, obj, values, axis)` | Insert values |
| `np.append(arr, values, axis)` | Append values |
| `np.delete(arr, obj, axis)` | Delete elements |
| `np.unique(ar, return_index, return_counts)` | Unique elements |

---

## Mathematical Functions

### Element-wise

| Function | Description |
|----------|-------------|
| `np.add(x1, x2)` / `+` | Addition |
| `np.subtract(x1, x2)` / `-` | Subtraction |
| `np.multiply(x1, x2)` / `*` | Multiplication |
| `np.divide(x1, x2)` / `/` | Division |
| `np.floor_divide(x1, x2)` / `//` | Floor division |
| `np.power(x1, x2)` / `**` | Power |
| `np.mod(x1, x2)` / `%` | Modulo |
| `np.remainder(x1, x2)` | Remainder |
| `np.abs(x)` / `np.absolute(x)` | Absolute value |
| `np.negative(x)` | Numeric negation |
| `np.sign(x)` | Sign function |
| `np.sqrt(x)` | Square root |
| `np.cbrt(x)` | Cube root |
| `np.square(x)` | Square |
| `np.reciprocal(x)` | 1/x |
| `np.exp(x)` | Exponential |
| `np.exp2(x)` | 2^x |
| `np.expm1(x)` | exp(x) - 1 (precise near 0) |
| `np.log(x)` | Natural logarithm |
| `np.log2(x)` | Base-2 logarithm |
| `np.log10(x)` | Base-10 logarithm |
| `np.log1p(x)` | log(1 + x) (precise near 0) |
| `np.maximum(x1, x2)` | Element-wise maximum |
| `np.minimum(x1, x2)` | Element-wise minimum |
| `np.clip(a, a_min, a_max)` | Clip values to range |
| `np.round(a, decimals)` | Round |
| `np.floor(x)` | Floor |
| `np.ceil(x)` | Ceiling |
| `np.trunc(x)` | Truncate to integer |
| `np.rint(x)` | Round to nearest integer |

### Trigonometric

| Function | Description |
|----------|-------------|
| `np.sin(x)` / `np.cos(x)` / `np.tan(x)` | Trigonometric |
| `np.arcsin(x)` / `np.arccos(x)` / `np.arctan(x)` | Inverse trig |
| `np.arctan2(y, x)` | Two-argument arctangent |
| `np.sinh(x)` / `np.cosh(x)` / `np.tanh(x)` | Hyperbolic |
| `np.arcsinh(x)` / `np.arccosh(x)` / `np.arctanh(x)` | Inverse hyperbolic |
| `np.degrees(x)` / `np.rad2deg(x)` | Radians to degrees |
| `np.radians(x)` / `np.deg2rad(x)` | Degrees to radians |
| `np.hypot(x1, x2)` | Hypotenuse |
| `np.unwrap(p)` | Unwrap phase angles |

### Aggregation / Reduction

| Function | Description |
|----------|-------------|
| `np.sum(a, axis)` | Sum |
| `np.prod(a, axis)` | Product |
| `np.cumsum(a, axis)` | Cumulative sum |
| `np.cumprod(a, axis)` | Cumulative product |
| `np.diff(a, n, axis)` | N-th discrete difference |
| `np.gradient(f, *varargs)` | Numerical gradient |
| `np.mean(a, axis)` | Mean |
| `np.median(a, axis)` | Median |
| `np.average(a, weights, axis)` | Weighted average |
| `np.std(a, axis, ddof)` | Standard deviation |
| `np.var(a, axis, ddof)` | Variance |
| `np.min(a, axis)` / `np.max(a, axis)` | Min/max |
| `np.argmin(a, axis)` / `np.argmax(a, axis)` | Index of min/max |
| `np.ptp(a, axis)` | Peak-to-peak (max - min) |
| `np.percentile(a, q, axis)` | Q-th percentile |
| `np.quantile(a, q, axis)` | Q-th quantile |
| `np.nanmean(a)` / `np.nanstd(a)` / `np.nansum(a)` | NaN-ignoring versions |
| `np.histogram(a, bins)` | Compute histogram |
| `np.histogram2d(x, y, bins)` | 2D histogram |
| `np.histogramdd(sample, bins)` | N-D histogram |
| `np.bincount(x, weights)` | Count occurrences |
| `np.digitize(x, bins)` | Bin indices |
| `np.corrcoef(x, y)` | Correlation coefficients |
| `np.cov(m, y, rowvar)` | Covariance matrix |

---

## Linear Algebra -- `np.linalg`

| Function | Description |
|----------|-------------|
| `np.dot(a, b)` | Dot product / matrix multiply |
| `np.matmul(a, b)` / `a @ b` | Matrix multiplication |
| `np.inner(a, b)` | Inner product |
| `np.outer(a, b)` | Outer product |
| `np.cross(a, b)` | Cross product |
| `np.tensordot(a, b, axes)` | Tensor dot product |
| `np.einsum(subscripts, *operands)` | Einstein summation |
| `np.linalg.solve(a, b)` | Solve linear system Ax = b |
| `np.linalg.inv(a)` | Matrix inverse |
| `np.linalg.det(a)` | Determinant |
| `np.linalg.eig(a)` | Eigenvalues and eigenvectors |
| `np.linalg.eigvals(a)` | Eigenvalues only |
| `np.linalg.eigh(a)` | Eigenvalues/vectors (symmetric) |
| `np.linalg.eigvalsh(a)` | Eigenvalues (symmetric) |
| `np.linalg.svd(a, full_matrices)` | Singular value decomposition |
| `np.linalg.norm(x, ord, axis)` | Matrix/vector norm |
| `np.linalg.qr(a, mode)` | QR decomposition |
| `np.linalg.cholesky(a)` | Cholesky decomposition |
| `np.linalg.lstsq(a, b, rcond)` | Least-squares solution |
| `np.linalg.matrix_rank(M, tol)` | Matrix rank |
| `np.linalg.matrix_power(a, n)` | Matrix power |
| `np.linalg.pinv(a)` | Pseudoinverse |
| `np.linalg.cond(x, p)` | Condition number |
| `np.linalg.slogdet(a)` | Sign and log of determinant |
| `np.linalg.multi_dot(arrays)` | Efficient multi-matrix dot |
| `np.trace(a)` | Trace (sum of diagonal) |

---

## FFT -- `np.fft`

| Function | Description |
|----------|-------------|
| `np.fft.fft(a, n, axis)` | 1D discrete Fourier transform |
| `np.fft.ifft(a, n, axis)` | Inverse 1D FFT |
| `np.fft.rfft(a, n, axis)` | FFT of real input |
| `np.fft.irfft(a, n, axis)` | Inverse real FFT |
| `np.fft.fft2(a, s, axes)` | 2D FFT |
| `np.fft.ifft2(a, s, axes)` | Inverse 2D FFT |
| `np.fft.fftn(a, s, axes)` | N-dimensional FFT |
| `np.fft.ifftn(a, s, axes)` | Inverse N-D FFT |
| `np.fft.fftfreq(n, d)` | DFT sample frequencies |
| `np.fft.rfftfreq(n, d)` | Real FFT frequencies |
| `np.fft.fftshift(x, axes)` | Shift zero-frequency to center |
| `np.fft.ifftshift(x, axes)` | Inverse shift |

---

## Random -- `np.random`

### Legacy API

| Function | Description |
|----------|-------------|
| `np.random.rand(d0, d1, ...)` | Uniform [0, 1) |
| `np.random.randn(d0, d1, ...)` | Standard normal |
| `np.random.randint(low, high, size)` | Random integers |
| `np.random.choice(a, size, replace, p)` | Random selection |
| `np.random.shuffle(x)` | In-place shuffle |
| `np.random.permutation(x)` | Random permutation |
| `np.random.seed(seed)` | Set random seed |
| `np.random.normal(loc, scale, size)` | Normal distribution |
| `np.random.uniform(low, high, size)` | Uniform distribution |
| `np.random.binomial(n, p, size)` | Binomial distribution |
| `np.random.poisson(lam, size)` | Poisson distribution |
| `np.random.exponential(scale, size)` | Exponential distribution |
| `np.random.beta(a, b, size)` | Beta distribution |
| `np.random.gamma(shape, scale, size)` | Gamma distribution |
| `np.random.multivariate_normal(mean, cov, size)` | Multivariate normal |

### Generator API (recommended)

```python
rng = np.random.default_rng(42)
rng.random(size=10)            # Uniform [0, 1)
rng.standard_normal(size=10)   # Standard normal
rng.integers(0, 100, size=10)  # Random integers
rng.choice([1,2,3], size=5)    # Random choice
rng.shuffle(array)             # In-place shuffle
rng.normal(0, 1, size=100)     # Normal
rng.uniform(0, 1, size=100)    # Uniform
```

---

## Polynomials -- `np.polynomial`

| Function | Description |
|----------|-------------|
| `np.polyfit(x, y, deg)` | Polynomial fit (returns coefficients) |
| `np.polyval(p, x)` | Evaluate polynomial |
| `np.poly1d(c)` | 1D polynomial class |
| `np.roots(p)` | Polynomial roots |
| `np.polyadd(a1, a2)` | Add polynomials |
| `np.polymul(a1, a2)` | Multiply polynomials |
| `np.polyder(p, m)` | Derivative of polynomial |
| `np.polyint(p, m)` | Integral of polynomial |
| `np.polynomial.polynomial.Polynomial(coef)` | Modern polynomial class |
| `np.polynomial.chebyshev.Chebyshev(coef)` | Chebyshev polynomial |
| `np.polynomial.legendre.Legendre(coef)` | Legendre polynomial |
| `np.polynomial.hermite.Hermite(coef)` | Hermite polynomial |
| `np.polynomial.laguerre.Laguerre(coef)` | Laguerre polynomial |

---

## Sorting & Searching

| Function | Description |
|----------|-------------|
| `np.sort(a, axis, kind)` | Sort array (kinds: `quicksort`, `mergesort`, `heapsort`, `stable`) |
| `np.argsort(a, axis, kind)` | Indices that would sort array |
| `np.lexsort(keys)` | Indirect sort by multiple keys |
| `np.partition(a, kth)` | Partial sort (k-th smallest) |
| `np.argpartition(a, kth)` | Indices of partial sort |
| `np.searchsorted(a, v, side)` | Find insertion point |
| `np.where(condition, x, y)` | Conditional selection |
| `np.nonzero(a)` | Indices of non-zero elements |
| `np.argwhere(a)` | Indices where condition is True |
| `np.extract(condition, arr)` | Extract elements by condition |
| `np.count_nonzero(a, axis)` | Count non-zeros |

---

## Logic & Comparison

| Function | Description |
|----------|-------------|
| `np.all(a, axis)` | Test if all True |
| `np.any(a, axis)` | Test if any True |
| `np.isnan(x)` | Test for NaN |
| `np.isinf(x)` | Test for infinity |
| `np.isfinite(x)` | Test for finite |
| `np.isclose(a, b, rtol, atol)` | Element-wise close comparison |
| `np.allclose(a, b, rtol, atol)` | All elements close |
| `np.array_equal(a1, a2)` | Arrays are equal |
| `np.logical_and(x1, x2)` | Element-wise AND |
| `np.logical_or(x1, x2)` | Element-wise OR |
| `np.logical_not(x)` | Element-wise NOT |
| `np.logical_xor(x1, x2)` | Element-wise XOR |

---

## Set Operations

| Function | Description |
|----------|-------------|
| `np.intersect1d(ar1, ar2)` | Intersection |
| `np.union1d(ar1, ar2)` | Union |
| `np.setdiff1d(ar1, ar2)` | Set difference |
| `np.setxor1d(ar1, ar2)` | Symmetric difference |
| `np.in1d(ar1, ar2)` | Test membership |
| `np.isin(element, test_elements)` | Test membership (N-D) |

---

## Constants

| Constant | Value |
|----------|-------|
| `np.pi` | 3.141592653589793 |
| `np.e` | 2.718281828459045 |
| `np.inf` | Positive infinity |
| `np.nan` | Not a number |
| `np.newaxis` | None (adds axis) |
| `np.PZERO` / `np.NZERO` | Positive/negative zero |

---

## Data Types

| Type | Description |
|------|-------------|
| `np.int8/16/32/64` | Signed integers |
| `np.uint8/16/32/64` | Unsigned integers |
| `np.float16/32/64` | Floating point |
| `np.complex64/128` | Complex |
| `np.bool_` | Boolean |
| `np.str_` | String |
| `np.object_` | Python object |

## Not Available

None -- this is a full NumPy build. All features work.
