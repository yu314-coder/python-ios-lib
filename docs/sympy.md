# SymPy

> **Version:** 1.14.0 | **Type:** Stock (pure Python) | **Status:** Fully working

SymPy is a pure Python symbolic math library — no compiled extensions, runs natively on iOS without patches.

---

## Quick Start

```python
from sympy import symbols, solve, diff, integrate, sin, cos, exp, pi, oo, series, limit, simplify, factor, expand, Eq, sqrt, Rational, Matrix

x, y, z = symbols('x y z')
```

## Core Functions

### Equation Solving

```python
# Polynomial roots
roots = solve(x**3 - 6*x**2 + 11*x - 6, x)
print(f"Roots: {roots}")  # [1, 2, 3]

# System of equations
sol = solve([2*x + y - 5, x - y - 1], [x, y])
print(f"Solution: {sol}")  # {x: 2, y: 1}

# Symbolic equation
sol = solve(Eq(x**2 + 2*x, 3), x)
print(f"x^2 + 2x = 3: {sol}")
```

### Calculus

```python
# Derivatives
f = sin(x**2) * exp(x)
print(f"d/dx[sin(x^2)*e^x] = {diff(f, x)}")
print(f"d^2/dx^2 = {diff(f, x, 2)}")

# Integration
print(f"int(1/(1+x^2), 0..inf) = {integrate(1/(1+x**2), (x, 0, oo))}")  # pi/2
print(f"int(x*exp(-x^2)) = {integrate(x * exp(-x**2), x)}")

# Limits
print(f"lim(sin(x)/x, x->0) = {limit(sin(x)/x, x, 0)}")

# Taylor series
print(f"cos(x) = {series(cos(x), x, 0, n=8)}")
```

### Simplification

```python
expr = (x**2 - 1) / (x - 1)
print(f"Simplified: {simplify(expr)}")  # x + 1

print(f"Factor: {factor(x**3 - x)}")  # x*(x-1)*(x+1)
print(f"Expand: {expand((x+1)**3)}")  # x^3 + 3x^2 + 3x + 1
```

### Linear Algebra

```python
M = Matrix([[1, 2], [3, 4]])
print(f"Det: {M.det()}")
print(f"Inverse: {M.inv()}")
print(f"Eigenvalues: {M.eigenvals()}")
print(f"Rref: {M.rref()}")
```

### Number Theory

```python
from sympy import isprime, factorint, gcd, lcm, nextprime
print(f"Is 97 prime? {isprime(97)}")
print(f"Factor 360: {factorint(360)}")
print(f"GCD(48, 18): {gcd(48, 18)}")
```

## Available Modules

| Module | Key Functions |
|--------|--------------|
| `sympy.core` | `symbols`, `Rational`, `pi`, `E`, `I`, `oo`, `zoo`, `nan` |
| `sympy.solvers` | `solve`, `solveset`, `linsolve`, `nsolve` |
| `sympy.calculus` | `diff`, `integrate`, `limit`, `series`, `summation` |
| `sympy.simplify` | `simplify`, `factor`, `expand`, `trigsimp`, `radsimp`, `collect` |
| `sympy.matrices` | `Matrix`, `eye`, `zeros`, `ones`, `det`, `inv`, `eigenvals` |
| `sympy.functions` | `sin`, `cos`, `tan`, `exp`, `log`, `sqrt`, `Abs`, `sign`, `floor`, `ceiling` |
| `sympy.integrals` | `integrate`, `Integral` |
| `sympy.series` | `series`, `fourier_series`, `O` |
| `sympy.ntheory` | `isprime`, `factorint`, `nextprime`, `totient`, `divisors` |
| `sympy.combinatorics` | `Permutation`, `PermutationGroup` |
| `sympy.geometry` | `Point`, `Line`, `Circle`, `Triangle`, `Polygon` |
| `sympy.plotting` | Not functional on iOS (no display backend) |
| `sympy.stats` | `Normal`, `Uniform`, `Exponential`, `P`, `E` (expected value) |
| `sympy.physics` | `units`, `mechanics`, `quantum` |

## Not Available

- `sympy.plotting` (no display backend on iOS — use matplotlib instead)
- Interactive features (`init_printing`, `pprint` renders in terminal only)
