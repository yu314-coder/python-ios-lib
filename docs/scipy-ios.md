# scipy - iOS Compatibility Patches

> **Version:** 1.15.2 (stock scipy + iOS patches) | **Submodules:** 18+ | **Location:** `scipy/`

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

## Submodule Reference (18+ modules)

### `scipy.optimize` -- Optimization & Root Finding

| Function | Description |
|----------|-------------|
| `minimize(fun, x0, method, bounds, constraints, tol, options)` | General-purpose minimization. Methods: `Nelder-Mead`, `Powell`, `CG`, `BFGS`, `L-BFGS-B`, `TNC`, `COBYLA`, `SLSQP`, `trust-constr` |
| `minimize_scalar(fun, bracket, bounds, method)` | 1D scalar minimization. Methods: `brent`, `bounded`, `golden` |
| `curve_fit(f, xdata, ydata, p0, sigma, absolute_sigma)` | Non-linear least squares curve fitting. Returns `(popt, pcov)` |
| `root(fun, x0, method, jac, tol)` | Find roots of vector functions. Methods: `hybr`, `lm`, `broyden1`, `anderson`, `krylov` |
| `root_scalar(f, bracket, x0, method)` | Scalar root finding. Methods: `brentq`, `bisect`, `newton`, `secant`, `toms748` |
| `brentq(f, a, b, xtol)` | Brent's method for scalar root in bracket [a, b] |
| `bisect(f, a, b, xtol)` | Bisection method for root finding |
| `newton(func, x0, fprime, tol)` | Newton-Raphson root finding |
| `fsolve(func, x0, fprime)` | Find roots of a function (Fortran HYBRD) |
| `linprog(c, A_ub, b_ub, A_eq, b_eq, bounds, method)` | Linear programming. Methods: `highs`, `simplex`, `interior-point` |
| `milp(c, constraints, integrality, bounds)` | Mixed-integer linear programming |
| `least_squares(fun, x0, bounds, method)` | Bounded non-linear least squares. Methods: `trf`, `dogbox`, `lm` |
| `differential_evolution(func, bounds, maxiter, seed)` | Global optimization via differential evolution |
| `dual_annealing(func, bounds, maxiter, seed)` | Dual annealing global optimization |
| `shgo(func, bounds, constraints)` | Simplicial homology global optimization |
| `basinhopping(func, x0, niter, T)` | Basin-hopping global optimization |
| `OptimizeResult` | Result object with `x`, `fun`, `success`, `message`, `nit`, `jac`, `hess` |
| `LinearConstraint(A, lb, ub)` | Linear constraint for optimization |
| `NonlinearConstraint(fun, lb, ub)` | Nonlinear constraint |
| `Bounds(lb, ub)` | Variable bounds |

---

### `scipy.integrate` -- Integration & ODE Solvers

| Function | Description |
|----------|-------------|
| `quad(func, a, b, args, limit)` | Adaptive quadrature (definite integral). Returns `(result, error)` |
| `dblquad(func, a, b, gfun, hfun)` | Double integral |
| `tplquad(func, a, b, gfun, hfun, qfun, rfun)` | Triple integral |
| `nquad(func, ranges)` | N-dimensional integration |
| `fixed_quad(func, a, b, n)` | Fixed-order Gaussian quadrature |
| `quadrature(func, a, b, tol)` | Adaptive Gaussian quadrature |
| `trapezoid(y, x, dx)` | Trapezoidal rule (was `trapz`) |
| `simpson(y, x, dx)` | Simpson's rule (was `simps`) |
| `cumulative_trapezoid(y, x, dx, initial)` | Cumulative trapezoidal integration |
| `solve_ivp(fun, t_span, y0, method, t_eval, events)` | Solve initial value problems. Methods: `RK45`, `RK23`, `DOP853`, `Radau`, `BDF`, `LSODA` |
| `odeint(func, y0, t, args, Dfun)` | Integrate ODEs (LSODA wrapper). May require Fortran runtime |
| `OdeSolver` | Base class for ODE solvers |
| `OdeResult` | Result with `t`, `y`, `t_events` |

---

### `scipy.stats` -- Statistical Functions

#### Continuous Distributions

| Distribution | Description |
|-------------|-------------|
| `norm(loc, scale)` | Normal (Gaussian) distribution |
| `t(df, loc, scale)` | Student's t-distribution |
| `chi2(df, loc, scale)` | Chi-squared distribution |
| `f(dfn, dfd, loc, scale)` | F-distribution |
| `uniform(loc, scale)` | Uniform distribution |
| `expon(loc, scale)` | Exponential distribution |
| `gamma(a, loc, scale)` | Gamma distribution |
| `beta(a, b, loc, scale)` | Beta distribution |
| `lognorm(s, loc, scale)` | Log-normal distribution |
| `weibull_min(c, loc, scale)` | Weibull minimum distribution |
| `pareto(b, loc, scale)` | Pareto distribution |
| `cauchy(loc, scale)` | Cauchy distribution |
| `laplace(loc, scale)` | Laplace distribution |
| `rayleigh(loc, scale)` | Rayleigh distribution |

All distributions support: `.pdf(x)`, `.cdf(x)`, `.ppf(q)`, `.rvs(size)`, `.mean()`, `.var()`, `.std()`, `.interval(confidence)`, `.fit(data)`

#### Discrete Distributions

| Distribution | Description |
|-------------|-------------|
| `binom(n, p)` | Binomial distribution |
| `poisson(mu)` | Poisson distribution |
| `geom(p)` | Geometric distribution |
| `nbinom(n, p)` | Negative binomial |
| `hypergeom(M, n, N)` | Hypergeometric distribution |
| `bernoulli(p)` | Bernoulli distribution |
| `randint(low, high)` | Discrete uniform |
| `zipf(a)` | Zipf distribution |

Discrete distributions support: `.pmf(k)`, `.cdf(k)`, `.ppf(q)`, `.rvs(size)`, `.mean()`, `.var()`

#### Statistical Tests

| Function | Description |
|----------|-------------|
| `ttest_ind(a, b, equal_var)` | Independent two-sample t-test |
| `ttest_1samp(a, popmean)` | One-sample t-test |
| `ttest_rel(a, b)` | Paired t-test |
| `pearsonr(x, y)` | Pearson correlation coefficient and p-value |
| `spearmanr(a, b)` | Spearman rank correlation |
| `kendalltau(x, y)` | Kendall's tau |
| `kstest(rvs, cdf)` | Kolmogorov-Smirnov test |
| `ks_2samp(data1, data2)` | Two-sample KS test |
| `mannwhitneyu(x, y)` | Mann-Whitney U test |
| `wilcoxon(x, y)` | Wilcoxon signed-rank test |
| `kruskal(*args)` | Kruskal-Wallis H-test |
| `friedmanchisquare(*args)` | Friedman test |
| `chi2_contingency(observed)` | Chi-squared test of independence |
| `fisher_exact(table)` | Fisher's exact test |
| `shapiro(x)` | Shapiro-Wilk normality test |
| `normaltest(a)` | D'Agostino / Pearson normality test |
| `anderson(x, dist)` | Anderson-Darling test |
| `levene(*args)` | Levene's test for equal variances |
| `bartlett(*args)` | Bartlett's test for equal variances |
| `f_oneway(*args)` | One-way ANOVA |

#### Descriptive Statistics

| Function | Description |
|----------|-------------|
| `describe(a)` | Descriptive statistics summary |
| `mode(a)` | Mode of data |
| `zscore(a)` | Z-score normalization |
| `iqr(x)` | Interquartile range |
| `sem(a)` | Standard error of the mean |
| `trim_mean(a, proportiontocut)` | Trimmed mean |
| `entropy(pk, qk)` | Shannon entropy (or KL divergence) |
| `differential_entropy(values)` | Differential entropy estimate |
| `linregress(x, y)` | Simple linear regression (slope, intercept, r, p, stderr) |

---

### `scipy.interpolate` -- Interpolation

| Class / Function | Description |
|-----------------|-------------|
| `interp1d(x, y, kind, fill_value)` | 1D interpolation. Kinds: `linear`, `nearest`, `zero`, `slinear`, `quadratic`, `cubic` |
| `CubicSpline(x, y, bc_type)` | Cubic spline interpolation. BC types: `not-a-knot`, `clamped`, `natural`, `periodic` |
| `UnivariateSpline(x, y, k, s)` | Smoothing univariate spline of degree k |
| `InterpolatedUnivariateSpline(x, y, k)` | Interpolating spline (passes through all points) |
| `PchipInterpolator(x, y)` | PCHIP monotone interpolation |
| `Akima1DInterpolator(x, y)` | Akima interpolation |
| `BarycentricInterpolator(xi, yi)` | Barycentric polynomial interpolation |
| `KroghInterpolator(xi, yi)` | Krogh interpolation |
| `make_interp_spline(x, y, k)` | Build B-spline interpolation |
| `griddata(points, values, xi, method)` | Interpolate unstructured data. Methods: `linear`, `nearest`, `cubic` |
| `RectBivariateSpline(x, y, z, kx, ky)` | 2D bivariate spline on rectangular grid |
| `bisplrep(x, y, z, kx, ky)` | Bivariate spline representation |
| `bisplev(x, y, tck)` | Evaluate bivariate spline |
| `BSpline(t, c, k)` | B-spline basis class |
| `PPoly(c, x)` | Piecewise polynomial |
| `RegularGridInterpolator(points, values, method)` | N-D regular grid interpolation |
| `LinearNDInterpolator(points, values)` | Piecewise linear interpolation in N-D |
| `NearestNDInterpolator(points, values)` | Nearest-neighbor in N-D |
| `CloughTocher2DInterpolator(points, values)` | Clough-Tocher 2D interpolation |
| `RBFInterpolator(y, d, kernel)` | Radial basis function interpolation |

---

### `scipy.linalg` -- Linear Algebra

| Function | Description |
|----------|-------------|
| `solve(a, b, assume_a)` | Solve linear system Ax = b. `assume_a`: `gen`, `sym`, `pos` |
| `solve_triangular(a, b, lower)` | Solve triangular system |
| `solve_banded(l_and_u, ab, b)` | Solve banded system |
| `inv(a)` | Matrix inverse |
| `det(a)` | Matrix determinant |
| `norm(a, ord)` | Matrix or vector norm |
| `eig(a)` | Eigenvalues and right eigenvectors |
| `eigvals(a)` | Eigenvalues only |
| `eigh(a)` | Eigenvalues/vectors for symmetric/Hermitian |
| `eigvalsh(a)` | Eigenvalues for symmetric/Hermitian |
| `svd(a, full_matrices)` | Singular value decomposition |
| `svdvals(a)` | Singular values only |
| `lu(a, permute_l)` | LU decomposition with pivoting |
| `lu_factor(a)` | LU factorization for repeated solves |
| `lu_solve(lu_and_piv, b)` | Solve using LU factorization |
| `cholesky(a, lower)` | Cholesky decomposition |
| `cho_factor(a)` | Cholesky factorization |
| `cho_solve(c_and_lower, b)` | Solve using Cholesky factorization |
| `qr(a, mode)` | QR decomposition |
| `schur(a, output)` | Schur decomposition |
| `hessenberg(a)` | Hessenberg form |
| `expm(A)` | Matrix exponential |
| `logm(A)` | Matrix logarithm |
| `sqrtm(A)` | Matrix square root |
| `funm(A, func)` | General matrix function |
| `pinv(a)` | Moore-Penrose pseudoinverse |
| `lstsq(a, b)` | Least-squares solution |
| `null_space(A)` | Null space of a matrix |
| `orth(A)` | Orthogonal basis for range |
| `block_diag(*arrs)` | Block diagonal matrix |
| `toeplitz(c, r)` | Toeplitz matrix |
| `hankel(c, r)` | Hankel matrix |
| `hadamard(n)` | Hadamard matrix |
| `hilbert(n)` | Hilbert matrix |
| `invhilbert(n)` | Inverse Hilbert matrix |
| `pascal(n)` | Pascal matrix |
| `kron(a, b)` | Kronecker product |

All backed by Apple's Accelerate framework (BLAS/LAPACK) for optimal iOS performance.

---

### `scipy.fft` -- Fast Fourier Transform

| Function | Description |
|----------|-------------|
| `fft(x, n, axis, norm)` | 1D discrete Fourier transform |
| `ifft(x, n, axis, norm)` | Inverse 1D FFT |
| `rfft(x, n, axis, norm)` | FFT of real-valued input (positive frequencies only) |
| `irfft(x, n, axis, norm)` | Inverse of rfft |
| `fft2(x, s, axes, norm)` | 2D FFT |
| `ifft2(x, s, axes, norm)` | Inverse 2D FFT |
| `fftn(x, s, axes, norm)` | N-dimensional FFT |
| `ifftn(x, s, axes, norm)` | Inverse N-dimensional FFT |
| `rfft2(x, s, axes, norm)` | 2D FFT of real input |
| `rfftn(x, s, axes, norm)` | N-D FFT of real input |
| `dct(x, type, n, axis, norm)` | Discrete cosine transform (types I-IV) |
| `idct(x, type, n, axis, norm)` | Inverse DCT |
| `dst(x, type, n, axis, norm)` | Discrete sine transform |
| `idst(x, type, n, axis, norm)` | Inverse DST |
| `fftfreq(n, d)` | DFT sample frequencies |
| `rfftfreq(n, d)` | Real-input DFT frequencies |
| `fftshift(x, axes)` | Shift zero-frequency to center |
| `ifftshift(x, axes)` | Inverse of fftshift |
| `next_fast_len(target)` | Optimal FFT length |

---

### `scipy.signal` -- Signal Processing

| Function | Description |
|----------|-------------|
| `butter(N, Wn, btype, analog, output)` | Butterworth filter design |
| `cheby1(N, rp, Wn, btype)` | Chebyshev type I filter |
| `cheby2(N, rs, Wn, btype)` | Chebyshev type II filter |
| `ellip(N, rp, rs, Wn, btype)` | Elliptic (Cauer) filter |
| `bessel(N, Wn, btype)` | Bessel/Thomson filter |
| `iirfilter(N, Wn, btype, ftype)` | General IIR filter design |
| `firwin(numtaps, cutoff, window, pass_zero)` | FIR filter using window method |
| `firwin2(numtaps, freq, gain)` | FIR filter with arbitrary response |
| `filtfilt(b, a, x, axis)` | Zero-phase forward-backward filtering |
| `sosfilt(sos, x, axis)` | Filter using second-order sections |
| `lfilter(b, a, x, axis)` | IIR/FIR filter |
| `convolve(in1, in2, mode)` | N-D convolution |
| `correlate(in1, in2, mode)` | N-D correlation |
| `fftconvolve(in1, in2, mode)` | FFT-based convolution |
| `find_peaks(x, height, threshold, distance, prominence, width)` | Find peaks in 1D signal |
| `peak_widths(x, peaks, rel_height)` | Width of peaks |
| `peak_prominences(x, peaks)` | Peak prominences |
| `welch(x, fs, nperseg, noverlap)` | Power spectral density via Welch's method |
| `periodogram(x, fs, window)` | Periodogram PSD estimate |
| `spectrogram(x, fs, nperseg, noverlap)` | Spectrogram (time-frequency) |
| `stft(x, fs, nperseg, noverlap)` | Short-time Fourier transform |
| `istft(Zxx, fs, nperseg, noverlap)` | Inverse STFT |
| `hilbert(x, N)` | Analytic signal via Hilbert transform |
| `detrend(data, axis, type)` | Remove linear or constant trend |
| `resample(x, num)` | Resample signal using Fourier method |
| `decimate(x, q, n)` | Downsample with anti-aliasing filter |
| `savgol_filter(x, window_length, polyorder)` | Savitzky-Golay filter |
| `medfilt(volume, kernel_size)` | Median filter |
| `wiener(im, mysize, noise)` | Wiener filter |
| `cwt(data, wavelet, widths)` | Continuous wavelet transform |
| `chirp(t, f0, t1, f1, method)` | Frequency-swept cosine |
| `gausspulse(t, fc, bw)` | Gaussian-modulated sinusoidal pulse |
| `square(t, duty)` | Square wave |
| `sawtooth(t, width)` | Sawtooth wave |
| `freqz(b, a, worN)` | Frequency response of digital filter |
| `sosfreqz(sos, worN)` | Frequency response from SOS |
| `zpk2sos(z, p, k)` | Convert zero-pole-gain to SOS |
| `tf2zpk(b, a)` | Transfer function to zero-pole-gain |

---

### `scipy.spatial` -- Spatial Algorithms

| Class / Function | Description |
|-----------------|-------------|
| `ConvexHull(points)` | Convex hull computation. Attributes: `vertices`, `simplices`, `volume`, `area` |
| `Voronoi(points)` | Voronoi tessellation. Attributes: `vertices`, `regions`, `ridge_vertices` |
| `Delaunay(points)` | Delaunay triangulation. Attributes: `simplices`, `neighbors`, `find_simplex()` |
| `cKDTree(data, leafsize)` | KD-tree for fast nearest-neighbor queries |
| `KDTree(data, leafsize)` | Pure Python KD-tree |
| `distance.euclidean(u, v)` | Euclidean distance |
| `distance.cosine(u, v)` | Cosine distance |
| `distance.cityblock(u, v)` | Manhattan distance |
| `distance.minkowski(u, v, p)` | Minkowski distance |
| `distance.cdist(XA, XB, metric)` | Pairwise distances between two sets |
| `distance.pdist(X, metric)` | Pairwise distances within one set |
| `distance.squareform(X)` | Convert condensed to square distance matrix |
| `distance.hamming(u, v)` | Hamming distance |
| `distance.jaccard(u, v)` | Jaccard distance |
| `distance.chebyshev(u, v)` | Chebyshev distance |
| `distance.mahalanobis(u, v, VI)` | Mahalanobis distance |
| `distance.correlation(u, v)` | Correlation distance |
| `tsearch(tri, xi)` | Find enclosing simplex |
| `procrustes(data1, data2)` | Procrustes analysis |
| `geometric_slerp(start, end, t)` | Spherical linear interpolation |

---

### `scipy.sparse` -- Sparse Matrices

| Class / Function | Description |
|-----------------|-------------|
| `csr_matrix(data, shape)` | Compressed Sparse Row matrix |
| `csc_matrix(data, shape)` | Compressed Sparse Column matrix |
| `coo_matrix(data, shape)` | COOrdinate format |
| `lil_matrix(shape)` | List of Lists (efficient construction) |
| `dia_matrix(data, shape)` | DIAgonal format |
| `bsr_matrix(data, shape)` | Block Sparse Row |
| `dok_matrix(shape)` | Dictionary of Keys |
| `eye(n, format)` | Sparse identity matrix |
| `diags(diagonals, offsets, shape)` | Construct sparse diagonal matrix |
| `block_diag(mats, format)` | Sparse block diagonal |
| `hstack(blocks)` | Horizontal stack |
| `vstack(blocks)` | Vertical stack |
| `kron(A, B, format)` | Sparse Kronecker product |
| `issparse(x)` | Check if sparse |
| `random(m, n, density, format)` | Random sparse matrix |
| `linalg.spsolve(A, b)` | Solve sparse linear system |
| `linalg.eigs(A, k)` | Largest eigenvalues of sparse matrix |
| `linalg.eigsh(A, k)` | Eigenvalues for sparse symmetric |
| `linalg.svds(A, k)` | Partial SVD of sparse matrix |
| `linalg.norm(x)` | Sparse matrix norm |
| `linalg.inv(A)` | Sparse matrix inverse |
| `linalg.expm(A)` | Sparse matrix exponential |
| `linalg.cg(A, b)` | Conjugate gradient solver |
| `linalg.gmres(A, b)` | GMRES iterative solver |
| `linalg.lgmres(A, b)` | LGMRES solver |
| `linalg.bicg(A, b)` | BiConjugate gradient |
| `linalg.bicgstab(A, b)` | BiCG-STAB solver |
| `linalg.splu(A)` | Sparse LU factorization |
| `linalg.spilu(A)` | Incomplete LU factorization |
| `linalg.LinearOperator(shape, matvec)` | Abstract linear operator |

---

### `scipy.special` -- Special Functions

| Function | Description |
|----------|-------------|
| `gamma(z)` | Gamma function |
| `gammaln(x)` | Log of absolute gamma |
| `digamma(x)` | Digamma (psi) function |
| `polygamma(n, x)` | Polygamma function |
| `beta(a, b)` | Beta function |
| `betaln(a, b)` | Log of beta function |
| `erf(z)` | Error function |
| `erfc(z)` | Complementary error function |
| `erfinv(y)` | Inverse error function |
| `erfcinv(y)` | Inverse complementary error function |
| `factorial(n, exact)` | Factorial |
| `comb(N, k, exact)` | Combinations (binomial coefficient) |
| `perm(N, k, exact)` | Permutations |
| `binom(n, k)` | Binomial coefficient (real-valued) |
| `zeta(x, q)` | Riemann/Hurwitz zeta function |
| `jv(v, z)` | Bessel function of first kind |
| `yv(v, z)` | Bessel function of second kind |
| `iv(v, z)` | Modified Bessel, first kind |
| `kv(v, z)` | Modified Bessel, second kind |
| `hankel1(v, z)` / `hankel2(v, z)` | Hankel functions |
| `airy(z)` | Airy functions (Ai, Bi and derivatives) |
| `legendre(n)` | Legendre polynomial |
| `hermite(n)` | Hermite polynomial |
| `laguerre(n)` | Laguerre polynomial |
| `chebyc(n)` / `chebyt(n)` | Chebyshev polynomials |
| `ellipj(u, m)` | Jacobi elliptic functions |
| `ellipk(m)` / `ellipe(m)` | Complete elliptic integrals |
| `expn(n, x)` | Generalized exponential integral |
| `expi(x)` | Exponential integral Ei |
| `lambertw(z)` | Lambert W function |
| `softmax(x, axis)` | Softmax function |
| `log_softmax(x, axis)` | Log softmax |
| `expit(x)` | Logistic sigmoid |
| `logit(p)` | Logit (inverse sigmoid) |
| `logsumexp(a, axis)` | Log of sum of exponentials |
| `rel_entr(x, y)` | Relative entropy (KL divergence element) |
| `xlogy(x, y)` | x * log(y) with proper 0*log(0) handling |
| `hyp2f1(a, b, c, z)` | Gauss hypergeometric function |

Note: Availability depends on `_ufuncs` loading successfully on iOS.

---

### `scipy.ndimage` -- N-dimensional Image Processing

| Function | Description |
|----------|-------------|
| `gaussian_filter(input, sigma)` | Gaussian smoothing |
| `uniform_filter(input, size)` | Uniform (box) filter |
| `median_filter(input, size)` | Median filter |
| `maximum_filter(input, size)` | Maximum filter |
| `minimum_filter(input, size)` | Minimum filter |
| `convolve(input, weights)` | N-D convolution |
| `correlate(input, weights)` | N-D correlation |
| `sobel(input, axis)` | Sobel edge detection |
| `laplace(input)` | Laplacian filter |
| `gaussian_laplace(input, sigma)` | Gaussian Laplacian |
| `gaussian_gradient_magnitude(input, sigma)` | Gaussian gradient magnitude |
| `binary_erosion(input, structure)` | Binary erosion |
| `binary_dilation(input, structure)` | Binary dilation |
| `binary_opening(input, structure)` | Binary opening |
| `binary_closing(input, structure)` | Binary closing |
| `binary_fill_holes(input)` | Fill holes in binary image |
| `label(input, structure)` | Label connected components |
| `find_objects(labeled_array)` | Find bounding boxes of labeled objects |
| `center_of_mass(input, labels, index)` | Center of mass |
| `rotate(input, angle)` | Rotate image |
| `zoom(input, zoom)` | Resize by zoom factor |
| `shift(input, shift)` | Shift image |
| `affine_transform(input, matrix, offset)` | Affine transform |
| `map_coordinates(input, coordinates)` | Map coordinates interpolation |
| `distance_transform_edt(input)` | Euclidean distance transform |
| `generate_binary_structure(rank, connectivity)` | Generate structuring element |

---

### `scipy.cluster.hierarchy` -- Hierarchical Clustering

| Function | Description |
|----------|-------------|
| `linkage(y, method, metric)` | Hierarchical clustering. Methods: `single`, `complete`, `average`, `weighted`, `centroid`, `median`, `ward` |
| `fcluster(Z, t, criterion)` | Form flat clusters from linkage. Criteria: `distance`, `maxclust`, `inconsistent` |
| `dendrogram(Z, truncate_mode, color_threshold)` | Plot dendrogram |
| `cut_tree(Z, n_clusters, height)` | Cut tree at given height or cluster count |
| `cophenet(Z, Y)` | Cophenetic distances |
| `inconsistent(Z, d)` | Inconsistency statistics |
| `maxdists(Z)` | Maximum distances in linkage |
| `leaves_list(Z)` | Leaf ordering |
| `fclusterdata(X, t, method, metric)` | Cluster from raw data (one-step) |
| `is_valid_linkage(Z)` | Validate linkage matrix |
| `optimal_leaf_ordering(Z, y)` | Optimal leaf ordering |

---

### `scipy.constants` -- Physical & Mathematical Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `pi` | 3.14159... | Pi |
| `golden` | 1.61803... | Golden ratio |
| `c` | 299792458.0 | Speed of light (m/s) |
| `h` | 6.626e-34 | Planck constant (J*s) |
| `hbar` | 1.055e-34 | Reduced Planck constant |
| `G` | 6.674e-11 | Gravitational constant |
| `g` | 9.80665 | Standard gravity (m/s^2) |
| `e` | 1.602e-19 | Elementary charge (C) |
| `k` | 1.381e-23 | Boltzmann constant (J/K) |
| `N_A` | 6.022e23 | Avogadro's number |
| `R` | 8.314 | Gas constant (J/(mol*K)) |
| `sigma` | 5.670e-8 | Stefan-Boltzmann constant |
| `eV` | 1.602e-19 | Electron volt (J) |
| `m_e` | 9.109e-31 | Electron mass (kg) |
| `m_p` | 1.673e-27 | Proton mass (kg) |
| `epsilon_0` | 8.854e-12 | Vacuum permittivity |
| `mu_0` | 1.257e-6 | Vacuum permeability |

Also: `physical_constants` dict, `value(name)`, `unit(name)`, `precision(name)`, `find(sub)` for lookup.

Conversion functions: `convert_temperature(val, old, new)`, and unit prefixes (`kilo`, `mega`, `giga`, `tera`, `milli`, `micro`, `nano`, etc.)

---

### Additional Submodules

| Module | Status | Key Contents |
|--------|--------|-------------|
| `scipy.io` | Partial | `loadmat()`, `savemat()`, `whosmat()` -- MATLAB file I/O |
| `scipy.io.wavfile` | Works | `read()`, `write()` -- WAV audio files |
| `scipy.misc` | Works | `face()`, `electrocardiogram()`, `central_diff_weights()`, `derivative()` |
| `scipy.odr` | Partial | Orthogonal distance regression (Fortran-dependent) |
| `scipy.cluster.vq` | Works | `kmeans()`, `kmeans2()`, `vq()`, `whiten()` -- Vector quantization |

---

## iOS Patches Applied

### 1. Fortran Runtime Stub -- `_fortran_stub.cpython-314-iphoneos.so`

22 Fortran I/O symbols as no-ops. All Fortran `WRITE`/`PRINT` become silent. Computation unaffected.

### 2. dcabs1 Fix -- `_scipy_ios_fix.cpython-314-iphoneos.so`

Apple's Accelerate doesn't include `dcabs1`. Provides: `dcabs1_(z) = |Re(z)| + |Im(z)|`

### 3. libsf_error_state -- Install Name Fix

`install_name_tool -change` on 6 `.so` files for framework path resolution.

### 4. iOS Preload Mechanism -- `_ios_preload.py`

Load order: `_fortran_stub` -> `_scipy_ios_fix` -> `libsf_error_state`

### 5. Import Cascade Protection

All submodule `__init__.py` files wrapped with `try/except` for graceful degradation.

---

## Known Limitations

- Modules requiring full Fortran I/O (COBYLA with verbose output) may fail
- Some sparse eigensolvers (ARPACK) may not load
- `scipy.io.matlab` may have import issues
- `scipy.special` depends on `_ufuncs` platform load (partial)
- SLSQP optimizer may fail (Fortran-dependent)
- `odeint` may fail (requires Fortran LSODA; use `solve_ivp` instead)
