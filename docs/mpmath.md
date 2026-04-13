# mpmath

> **Version:** 1.4.1 | **Type:** Stock (pure Python) | **Status:** Fully working

Arbitrary-precision floating-point math. Used by SymPy internally.

---

## Quick Start

```python
from mpmath import mp, mpf, pi, e, sqrt, sin, cos, exp, log, gamma, zeta, quad, nstr

mp.dps = 50  # 50 decimal places
print(f"pi = {pi}")
print(f"e  = {e}")
```

---

## Precision Control

| Setting | Description |
|---------|-------------|
| `mp.dps = n` | Set decimal places (digits of precision) |
| `mp.prec = n` | Set binary precision (bits) |
| `mpf(x)` | Create multi-precision float |
| `mpc(re, im)` | Create multi-precision complex |
| `nstr(x, n)` | Format to n significant digits |
| `mpf('0.1')` | Exact decimal input (avoids float rounding) |

---

## Constants

| Constant | Description |
|----------|-------------|
| `pi` | 3.14159... |
| `e` | 2.71828... (Euler's number) |
| `euler` | 0.57721... (Euler-Mascheroni) |
| `catalan` | 0.91596... (Catalan's constant) |
| `phi` | 1.61803... (golden ratio) |
| `khinchin` | 2.68545... (Khinchin's constant) |
| `glaisher` | 1.28242... (Glaisher-Kinkelin) |
| `apery` | 1.20205... (Apery's constant = zeta(3)) |
| `degree` | pi/180 |
| `inf` | Positive infinity |
| `nan` | Not a number |
| `j` | Imaginary unit |

---

## Arithmetic & Power Functions

| Function | Description |
|----------|-------------|
| `sqrt(x)` | Square root |
| `cbrt(x)` | Cube root |
| `root(x, n)` | N-th root |
| `power(x, y)` | x^y |
| `exp(x)` | Exponential |
| `expm1(x)` | exp(x) - 1 (precise near 0) |
| `log(x)` / `ln(x)` | Natural logarithm |
| `log10(x)` | Base-10 logarithm |
| `log(x, b)` | Logarithm base b |
| `fabs(x)` | Absolute value |
| `sign(x)` | Sign function |
| `floor(x)` / `ceil(x)` | Floor / ceiling |
| `nint(x)` | Nearest integer |
| `frac(x)` | Fractional part |
| `fmod(x, y)` | Floating-point modulo |
| `ldexp(x, n)` | x * 2^n |
| `frexp(x)` | Decompose to (m, e) where x = m * 2^e |

---

## Trigonometric & Hyperbolic

| Function | Description |
|----------|-------------|
| `sin`, `cos`, `tan` | Trigonometric |
| `cot`, `sec`, `csc` | Reciprocal trig |
| `asin`, `acos`, `atan` | Inverse trig |
| `atan2(y, x)` | Two-argument arctangent |
| `sinh`, `cosh`, `tanh` | Hyperbolic |
| `coth`, `sech`, `csch` | Reciprocal hyperbolic |
| `asinh`, `acosh`, `atanh` | Inverse hyperbolic |
| `sinpi(x)` / `cospi(x)` | sin(pi*x), cos(pi*x) (exact at integers) |
| `sincpi(x)` | sin(pi*x)/(pi*x) |
| `degrees(x)` / `radians(x)` | Angle conversion |

---

## Special Functions

| Function | Description |
|----------|-------------|
| `gamma(z)` | Gamma function |
| `rgamma(z)` | 1/gamma(z) |
| `loggamma(z)` | Log-gamma |
| `factorial(n)` | n! |
| `fac2(n)` | Double factorial n!! |
| `rf(x, n)` | Rising factorial (Pochhammer) |
| `ff(x, n)` | Falling factorial |
| `binomial(n, k)` | Binomial coefficient |
| `beta(a, b)` | Beta function |
| `betainc(a, b, x1, x2)` | Incomplete beta |
| `psi(n, z)` | Polygamma (digamma when n=0) |
| `digamma(z)` | Digamma function |
| `harmonic(n)` | Harmonic number |
| `bernoulli(n)` | Bernoulli numbers |
| `euler(n)` | Euler numbers |

### Zeta & L-Functions

| Function | Description |
|----------|-------------|
| `zeta(s)` | Riemann zeta function |
| `altzeta(s)` | Dirichlet eta function |
| `polylog(s, z)` | Polylogarithm |
| `lerchphi(z, s, a)` | Lerch transcendent |
| `dirichlet(s, chi)` | Dirichlet L-function |
| `stieltjes(n)` | Stieltjes constants |

### Error & Exponential Integrals

| Function | Description |
|----------|-------------|
| `erf(z)` | Error function |
| `erfc(z)` | Complementary error function |
| `erfi(z)` | Imaginary error function |
| `erfinv(z)` | Inverse error function |
| `ei(x)` | Exponential integral Ei |
| `li(x)` | Logarithmic integral |
| `si(x)` / `ci(x)` | Sine/cosine integrals |
| `shi(x)` / `chi(x)` | Hyperbolic sine/cosine integrals |

### Bessel & Airy

| Function | Description |
|----------|-------------|
| `besselj(v, z)` | Bessel J (first kind) |
| `bessely(v, z)` | Bessel Y (second kind) |
| `besseli(v, z)` | Modified Bessel I |
| `besselk(v, z)` | Modified Bessel K |
| `hankel1(v, z)` / `hankel2(v, z)` | Hankel functions |
| `airyai(z)` / `airybi(z)` | Airy functions |
| `airyaizero(n)` / `airybizero(n)` | Zeros of Airy functions |

### Hypergeometric

| Function | Description |
|----------|-------------|
| `hyp0f1(b, z)` | Confluent hypergeometric limit |
| `hyp1f1(a, b, z)` | Kummer confluent hypergeometric |
| `hyp2f1(a, b, c, z)` | Gauss hypergeometric |
| `hyper(a_s, b_s, z)` | Generalized hypergeometric pFq |
| `meijerg(a, b, z)` | Meijer G-function |

### Elliptic Functions

| Function | Description |
|----------|-------------|
| `ellipk(m)` | Complete elliptic integral K |
| `ellipe(m)` | Complete elliptic integral E |
| `ellipf(phi, m)` | Incomplete elliptic F |
| `ellippi(n, m)` | Complete elliptic Pi |
| `jtheta(n, z, q)` | Jacobi theta functions (n=1,2,3,4) |
| `kleinj(tau)` | Klein j-invariant |

### Orthogonal Polynomials

`legendre(n, x)`, `chebyt(n, x)`, `chebyu(n, x)`, `hermite(n, x)`, `laguerre(n, x, m)`, `gegenbauer(n, a, x)`, `jacobi(n, a, b, x)`, `spherharm(l, m, theta, phi)`

---

## Numerical Calculus

| Function | Description |
|----------|-------------|
| `quad(f, [a, b])` | Numerical integration (adaptive quadrature) |
| `quadgl(f, [a, b])` | Gauss-Legendre quadrature |
| `quadts(f, [a, b])` | Tanh-sinh quadrature |
| `quadosc(f, [a, inf], omega)` | Oscillatory integral |
| `diff(f, x, n)` | N-th numerical derivative |
| `diffs(f, x, n)` | All derivatives up to order n |
| `taylor(f, x, n)` | Taylor coefficients |
| `pade(coeffs, L, M)` | Pade approximant |
| `nsum(f, [a, b])` | Numerical summation |
| `nprod(f, [a, b])` | Numerical product |
| `limit(f, x)` | Richardson extrapolation limit |
| `richardson(f, n, N)` | Richardson extrapolation |

---

## Linear Algebra

| Function | Description |
|----------|-------------|
| `matrix(rows)` | Create matrix |
| `eye(n)` | Identity matrix |
| `zeros(m, n)` | Zero matrix |
| `ones(m, n)` | Ones matrix |
| `diag(entries)` | Diagonal matrix |
| `lu_solve(A, b)` | Solve via LU |
| `qr_solve(A, b)` | Solve via QR |
| `cholesky_solve(A, b)` | Solve via Cholesky |
| `det(A)` | Determinant |
| `inverse(A)` / `A**-1` | Matrix inverse |
| `norm(A, p)` | Matrix/vector norm |
| `mnorm(A, p)` | Matrix norm |
| `eig(A)` | Eigenvalues |
| `eigsy(A)` | Eigenvalues (symmetric) |
| `svd(A)` | Singular value decomposition |
| `svd_r(A)` | Economy SVD |
| `qr(A)` | QR decomposition |
| `lu(A)` | LU decomposition |
| `cholesky(A)` | Cholesky decomposition |
| `hessenberg(A)` | Hessenberg reduction |
| `schur(A)` | Schur decomposition |
| `expm(A)` | Matrix exponential |
| `logm(A)` | Matrix logarithm |
| `sqrtm(A)` | Matrix square root |
| `powm(A, n)` | Matrix power |

---

## Root Finding & Optimization

| Function | Description |
|----------|-------------|
| `findroot(f, x0)` | Find root using Newton or secant method |
| `findroot(f, [a, b])` | Find root in interval |
| `polyroots(coeffs)` | Polynomial roots (arbitrary precision) |
| `polyval(coeffs, x)` | Evaluate polynomial |

---

## Number Theory

| Function | Description |
|----------|-------------|
| `isprime(n)` | Primality test |
| `primepi(n)` | Prime counting function |
| `primepi2(n)` | Prime counting with error bound |
| `bell(n)` | Bell numbers |
| `stirling1(n, k)` | Stirling numbers (first kind) |
| `stirling2(n, k)` | Stirling numbers (second kind) |
| `moebius(n)` | Mobius function |

---

## Series & Transforms

| Function | Description |
|----------|-------------|
| `taylor(f, x, n)` | Taylor coefficients |
| `chebyfit(f, [a, b], n)` | Chebyshev approximation |
| `fourier(f, [a, b], n)` | Fourier coefficients |
| `nsum(f, [a, inf])` | Numerical infinite sum |
| `nprod(f, [a, inf])` | Numerical infinite product |
