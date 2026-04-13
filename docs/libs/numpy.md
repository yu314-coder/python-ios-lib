# NumPy

**Native iOS build** | v2.3.5 | Full C extension

> Real NumPy compiled for iOS arm64. All ufuncs, BLAS/LAPACK, and FFT included.

---

## Modules

| Module | Key Functions |
|--------|--------------|
| **Array Creation** | `array`, `zeros`, `ones`, `empty`, `full`, `arange`, `linspace`, `logspace`, `eye`, `identity`, `diag`, `meshgrid`, `mgrid`, `ogrid`, `fromfunction`, `tile`, `repeat` |
| **Manipulation** | `reshape`, `ravel`, `flatten`, `transpose`, `swapaxes`, `expand_dims`, `squeeze`, `concatenate`, `stack`, `vstack`, `hstack`, `split`, `flip`, `rot90`, `roll`, `pad`, `unique` |
| **Math** | `add`, `subtract`, `multiply`, `divide`, `power`, `mod`, `abs`, `sqrt`, `exp`, `log`, `sin`, `cos`, `tan`, `arcsin`, `arccos`, `arctan`, `sinh`, `cosh`, `tanh`, `clip`, `round`, `floor`, `ceil` |
| **Aggregation** | `sum`, `prod`, `cumsum`, `cumprod`, `mean`, `median`, `std`, `var`, `min`, `max`, `argmin`, `argmax`, `percentile`, `histogram`, `corrcoef`, `cov` |
| **Linear Algebra** | `dot`, `matmul`, `inner`, `outer`, `cross`, `einsum`, `linalg.solve`, `linalg.inv`, `linalg.eig`, `linalg.svd`, `linalg.norm`, `linalg.qr`, `linalg.cholesky`, `linalg.lstsq`, `linalg.det` |
| **FFT** | `fft.fft`, `fft.ifft`, `fft.rfft`, `fft.fft2`, `fft.fftn`, `fft.fftfreq`, `fft.fftshift` |
| **Random** | `random.default_rng`, `random.rand`, `random.randn`, `random.randint`, `random.choice`, `random.shuffle`, `random.normal`, `random.uniform`, `random.poisson` |
| **Polynomial** | `polyfit`, `polyval`, `poly1d`, `roots`, `polynomial.Polynomial`, `polynomial.Chebyshev` |
| **Sorting** | `sort`, `argsort`, `lexsort`, `partition`, `searchsorted`, `where`, `nonzero`, `argwhere` |
| **Logic & Sets** | `all`, `any`, `isnan`, `isinf`, `isfinite`, `isclose`, `logical_and/or/not`, `intersect1d`, `union1d`, `isin` |
| **I/O** | `save`, `load`, `savez`, `savetxt`, `loadtxt`, `genfromtxt`, `fromfile`, `tofile` |
