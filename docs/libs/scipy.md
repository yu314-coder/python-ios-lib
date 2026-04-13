# SciPy

**Pure Python shim** | v1.15.0-offlinai

> Core scientific computing routines reimplemented in pure NumPy. Covers optimization, interpolation, integration, signal processing, and statistics.

---

## Modules

| Module | Key Functions |
|--------|--------------|
| `scipy.optimize` | `minimize`, `minimize_scalar`, `root`, `root_scalar`, `curve_fit`, `least_squares`, `linprog`, `linear_sum_assignment`, `fsolve`, `brentq`, `newton` |
| `scipy.interpolate` | `interp1d`, `CubicSpline`, `UnivariateSpline`, `BSpline`, `PchipInterpolator`, `Akima1DInterpolator`, `RegularGridInterpolator`, `griddata`, `splrep`, `splev` |
| `scipy.integrate` | `quad`, `dblquad`, `tplquad`, `trapezoid`, `simpson`, `cumulative_trapezoid`, `solve_ivp`, `odeint`, `RK45`, `Radau` |
| `scipy.linalg` | `solve`, `inv`, `det`, `eig`, `eigvals`, `svd`, `lu`, `qr`, `cholesky`, `schur`, `hessenberg`, `expm`, `logm`, `sqrtm`, `null_space`, `orth`, `block_diag` |
| `scipy.signal` | `convolve`, `correlate`, `fftconvolve`, `butter`, `cheby1`, `bessel`, `sosfilt`, `lfilter`, `freqz`, `spectrogram`, `stft`, `find_peaks`, `welch`, `periodogram`, `resample` |
| `scipy.stats` | `norm`, `t`, `chi2`, `f`, `uniform`, `expon`, `gamma`, `beta`, `poisson`, `binomial`, `pearsonr`, `spearmanr`, `ttest_1samp`, `ttest_ind`, `kstest`, `shapiro`, `mannwhitneyu`, `describe`, `zscore` |
| `scipy.spatial` | `distance.cdist`, `distance.pdist`, `distance.squareform`, `KDTree`, `cKDTree`, `ConvexHull`, `Delaunay`, `Voronoi` |
| `scipy.sparse` | `csr_matrix`, `csc_matrix`, `coo_matrix`, `lil_matrix`, `eye`, `diags`, `random`, `linalg.spsolve` |
| `scipy.special` | `gamma`, `gammaln`, `beta`, `betainc`, `erf`, `erfc`, `factorial`, `comb`, `perm`, `jv`, `yv`, `iv`, `kv` (Bessel), `legendre`, `hermite` |
| `scipy.fft` | `fft`, `ifft`, `rfft`, `fft2`, `fftn`, `fftfreq`, `fftshift`, `dct`, `idct`, `dst` |
| `scipy.ndimage` | `gaussian_filter`, `uniform_filter`, `median_filter`, `sobel`, `laplace`, `rotate`, `zoom`, `shift`, `binary_erosion`, `binary_dilation`, `label` |
| `scipy.io` | `loadmat`, `savemat`, `wavfile.read`, `wavfile.write` |
| `scipy.cluster` | `hierarchy.linkage`, `hierarchy.dendrogram`, `hierarchy.fcluster`, `vq.kmeans`, `vq.whiten` |
