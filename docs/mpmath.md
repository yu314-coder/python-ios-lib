# mpmath

> **Version:** 1.4.1 | **Type:** Stock (pure Python) | **Status:** Fully working

Arbitrary-precision floating-point math. Used by SymPy internally.

---

## Usage

```python
from mpmath import mp, mpf, pi, e, sqrt, sin, cos, exp, log, gamma, zeta, quad, nstr

# Set precision
mp.dps = 50  # 50 decimal places

# Constants
print(f"pi = {pi}")
print(f"e  = {e}")
print(f"sqrt(2) = {sqrt(2)}")

# Special functions
print(f"gamma(0.5) = {gamma(0.5)}")      # sqrt(pi)
print(f"zeta(2) = {zeta(2)}")            # pi^2/6

# Numerical integration
result = quad(lambda x: exp(-x**2), [0, mp.inf])
print(f"int(e^-x^2, 0..inf) = {result}")  # sqrt(pi)/2

# Arbitrary precision
mp.dps = 100
print(f"pi (100 digits) = {pi}")
```

## Key Functions

| Category | Functions |
|----------|-----------|
| Constants | `pi`, `e`, `euler`, `catalan`, `phi` (golden ratio), `inf`, `nan` |
| Arithmetic | `mpf()`, `mpc()`, `power()`, `sqrt()`, `cbrt()`, `root()` |
| Trig | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2` |
| Exponential | `exp`, `log`, `log10`, `power` |
| Special | `gamma`, `factorial`, `zeta`, `bernoulli`, `polylog`, `hyper` |
| Integration | `quad` (numerical quadrature) |
| Linear Algebra | `matrix`, `lu_solve`, `qr_solve`, `det`, `inverse` |
| Series | `taylor`, `nsum`, `nprod` |
