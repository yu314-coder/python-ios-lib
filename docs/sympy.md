# SymPy

> **Version:** 1.14.0 | **Type:** Stock (pure Python) | **Status:** Fully working

SymPy is a pure Python symbolic math library -- no compiled extensions, runs natively on iOS without patches.

---

## Quick Start

```python
from sympy import symbols, solve, diff, integrate, sin, cos, exp, pi, oo, series, limit, simplify, factor, expand, Eq, sqrt, Rational, Matrix

x, y, z = symbols('x y z')
```

---

## Core Module -- `sympy.core`

### Symbols & Constants

| Object | Description |
|--------|-------------|
| `symbols('x y z')` | Create symbolic variables |
| `Symbol('x', positive=True)` | Symbol with assumptions |
| `Rational(p, q)` | Exact rational number p/q |
| `Integer(n)` | Symbolic integer |
| `Float(x, dps)` | Symbolic float with precision |
| `pi` | 3.14159... |
| `E` | 2.71828... (Euler's number) |
| `I` | Imaginary unit |
| `oo` | Positive infinity |
| `zoo` | Complex infinity |
| `nan` | Not a number |
| `S.Half` / `S.One` / `S.Zero` | Singleton rationals |
| `S.NegativeOne` | -1 |
| `S.Infinity` | Same as `oo` |
| `GoldenRatio` | (1 + sqrt(5))/2 |
| `EulerGamma` | Euler-Mascheroni constant |
| `Catalan` | Catalan's constant |

### Expression Manipulation

| Function | Description |
|----------|-------------|
| `simplify(expr)` | General simplification |
| `expand(expr)` | Expand products and powers |
| `factor(expr)` | Factor polynomial |
| `collect(expr, x)` | Collect coefficients of x |
| `cancel(expr)` | Cancel common factors |
| `apart(expr, x)` | Partial fraction decomposition |
| `together(expr)` | Combine fractions |
| `radsimp(expr)` | Rationalize denominator |
| `powsimp(expr)` | Simplify powers |
| `trigsimp(expr)` | Simplify trig expressions |
| `logcombine(expr)` | Combine logarithms |
| `nsimplify(expr)` | Convert float to exact |
| `cse(exprs)` | Common subexpression elimination |
| `subs(old, new)` | Substitute values |
| `expr.evalf(n)` | Numerical evaluation to n digits |
| `N(expr, n)` | Same as evalf |
| `expr.rewrite(func)` | Rewrite in terms of func |
| `expr.as_numer_denom()` | Split to numerator/denominator |
| `expr.coeff(x, n)` | Coefficient of x^n |
| `degree(expr, x)` | Degree of polynomial |
| `Poly(expr, x)` | Convert to polynomial object |

---

## Solvers -- `sympy.solvers`

| Function | Description |
|----------|-------------|
| `solve(expr, x)` | Solve equation(s) symbolically |
| `solve([eq1, eq2], [x, y])` | Solve system of equations |
| `solve(Eq(lhs, rhs), x)` | Solve explicit equation |
| `solveset(expr, x, domain)` | Solve with domain specification (Reals, Complexes) |
| `linsolve([eq1, eq2], x, y)` | Solve linear system (returns set) |
| `nonlinsolve([eq1, eq2], [x, y])` | Solve nonlinear system |
| `nsolve(expr, x0)` | Numerical root finding |
| `roots(expr, x)` | Roots with multiplicity |
| `real_roots(expr, x)` | Real roots only |
| `dsolve(ode, f(x))` | Solve ordinary differential equation |
| `pdsolve(pde, f(x, y))` | Solve partial differential equation |
| `checkodesol(ode, sol)` | Verify ODE solution |
| `reduce_inequalities(ineqs, x)` | Solve inequalities |
| `diophantine(expr)` | Solve Diophantine equations |

---

## Calculus -- `sympy.calculus`

| Function | Description |
|----------|-------------|
| `diff(expr, x)` | First derivative d/dx |
| `diff(expr, x, n)` | N-th derivative |
| `diff(expr, x, y)` | Mixed partial derivative |
| `Derivative(expr, x)` | Unevaluated derivative |
| `integrate(expr, x)` | Indefinite integral |
| `integrate(expr, (x, a, b))` | Definite integral from a to b |
| `Integral(expr, x)` | Unevaluated integral |
| `limit(expr, x, x0)` | Limit as x -> x0 |
| `limit(expr, x, x0, '+')` | Right-hand limit |
| `limit(expr, x, x0, '-')` | Left-hand limit |
| `series(expr, x, x0, n)` | Taylor/Laurent series around x0 |
| `summation(expr, (i, a, b))` | Symbolic sum |
| `product(expr, (i, a, b))` | Symbolic product |
| `sequence(expr, (n, a, b))` | Define sequence |
| `fourier_series(f, (x, -pi, pi))` | Fourier series expansion |
| `singularities(expr, x)` | Find singularities |
| `is_increasing(expr, interval)` | Test if increasing |
| `is_decreasing(expr, interval)` | Test if decreasing |
| `minimum(expr, x, domain)` | Find minimum |
| `maximum(expr, x, domain)` | Find maximum |

---

## Matrices -- `sympy.matrices`

| Function / Class | Description |
|-----------------|-------------|
| `Matrix([[a, b], [c, d]])` | Create matrix |
| `eye(n)` | Identity matrix |
| `zeros(m, n)` | Zero matrix |
| `ones(m, n)` | Ones matrix |
| `diag(*args)` | Diagonal matrix |
| `M.det()` | Determinant |
| `M.inv()` | Inverse |
| `M.transpose()` / `M.T` | Transpose |
| `M.adjugate()` | Adjugate (classical adjoint) |
| `M.cofactor(i, j)` | Cofactor |
| `M.eigenvals()` | Eigenvalues with multiplicities |
| `M.eigenvects()` | Eigenvalues and eigenvectors |
| `M.diagonalize()` | Diagonalization (P, D) |
| `M.jordan_form()` | Jordan normal form |
| `M.rref()` | Reduced row echelon form |
| `M.rank()` | Matrix rank |
| `M.nullspace()` | Null space basis |
| `M.columnspace()` | Column space basis |
| `M.rowspace()` | Row space basis |
| `M.norm(ord)` | Matrix norm |
| `M.trace()` | Trace |
| `M.cholesky()` | Cholesky decomposition |
| `M.LUdecomposition()` | LU decomposition |
| `M.QRdecomposition()` | QR decomposition |
| `M.singular_values()` | Singular values |
| `M.condition_number()` | Condition number |
| `M.exp()` | Matrix exponential |
| `M.applyfunc(f)` | Apply function to each element |
| `M.row_del(i)` / `M.col_del(j)` | Delete row/column |
| `M.row_insert(i, row)` | Insert row |
| `M.col_insert(j, col)` | Insert column |
| `M * N` | Matrix multiplication |
| `M ** n` | Matrix power |
| `M.cross(N)` | Cross product (3D vectors) |
| `M.dot(N)` | Dot product |

---

## Functions -- `sympy.functions`

### Trigonometric
`sin`, `cos`, `tan`, `cot`, `sec`, `csc`, `asin`, `acos`, `atan`, `acot`, `asec`, `acsc`, `atan2`

### Hyperbolic
`sinh`, `cosh`, `tanh`, `coth`, `sech`, `csch`, `asinh`, `acosh`, `atanh`, `acoth`

### Exponential & Logarithmic
`exp`, `log`, `ln`, `LambertW`

### Power & Roots
`sqrt`, `cbrt`, `root(x, n)`, `Pow`, `Abs`, `sign`

### Combinatorial
`factorial`, `binomial`, `fibonacci`, `lucas`, `harmonic`, `bernoulli`, `euler`, `catalan`, `bell`, `stirling`, `subfactorial`, `RisingFactorial`, `FallingFactorial`

### Special Functions
`gamma`, `loggamma`, `digamma`, `polygamma`, `beta`, `zeta`, `dirichlet_eta`, `polylog`, `lerchphi`, `Ei`, `Si`, `Ci`, `li`, `erf`, `erfc`, `erfi`, `erfinv`, `erfcinv`, `besselj`, `bessely`, `besseli`, `besselk`, `hankel1`, `hankel2`, `jn`, `yn`, `airyai`, `airybi`, `legendreP`, `legendreQ`, `assoc_legendre`, `hermite`, `laguerre`, `assoc_laguerre`, `chebyshevt`, `chebyshevu`, `jacobi`, `gegenbauer`, `Ynm` (spherical harmonics), `hyper`, `meijerg`, `elliptic_k`, `elliptic_e`, `elliptic_pi`

### Piecewise & Other
`Piecewise((expr1, cond1), (expr2, cond2), ...)`, `Heaviside(x)`, `DiracDelta(x)`, `floor`, `ceiling`, `frac`, `Min`, `Max`, `re`, `im`, `conjugate`, `arg`

---

## Number Theory -- `sympy.ntheory`

| Function | Description |
|----------|-------------|
| `isprime(n)` | Primality test |
| `nextprime(n)` | Next prime after n |
| `prevprime(n)` | Previous prime before n |
| `prime(n)` | N-th prime |
| `primerange(a, b)` | Primes in range [a, b) |
| `primepi(n)` | Count of primes <= n |
| `factorint(n)` | Integer factorization (dict) |
| `divisors(n)` | All divisors |
| `divisor_count(n)` | Number of divisors |
| `divisor_sigma(n, k)` | Sum of k-th powers of divisors |
| `totient(n)` | Euler's totient function |
| `reduced_totient(n)` | Carmichael's lambda |
| `mobius(n)` | Mobius function |
| `gcd(a, b)` / `lcm(a, b)` | GCD / LCM |
| `igcd(a, b)` | Integer GCD |
| `mod_inverse(a, m)` | Modular inverse |
| `is_quad_residue(a, p)` | Quadratic residue test |
| `legendre_symbol(a, p)` | Legendre symbol |
| `jacobi_symbol(a, n)` | Jacobi symbol |
| `discrete_log(n, a, b)` | Discrete logarithm |
| `continued_fraction_periodic(p, q, d)` | Periodic continued fraction |
| `egyptian_fraction(r)` | Egyptian fraction representation |
| `binomial_coefficients(n)` | All binomial coefficients of n |
| `npartitions(n)` | Number of partitions |

---

## Geometry -- `sympy.geometry`

| Class | Description |
|-------|-------------|
| `Point(x, y)` / `Point3D(x, y, z)` | Point in 2D/3D |
| `Line(p1, p2)` | Line through two points |
| `Ray(p1, p2)` | Ray from p1 through p2 |
| `Segment(p1, p2)` | Line segment |
| `Circle(center, radius)` | Circle |
| `Ellipse(center, hradius, vradius)` | Ellipse |
| `Triangle(p1, p2, p3)` | Triangle |
| `Polygon(*points)` | N-sided polygon |
| `RegularPolygon(center, radius, n)` | Regular polygon |
| `Curve(expr_tuple, param_range)` | Parametric curve |
| `Plane(p1, p2, p3)` | 3D plane |

Methods: `.area`, `.perimeter`, `.circumcircle`, `.incircle`, `.centroid`, `.distance()`, `.intersection()`, `.is_tangent()`, `.is_similar()`, `.is_congruent()`

---

## Combinatorics -- `sympy.combinatorics`

| Class | Description |
|-------|-------------|
| `Permutation([1, 0, 3, 2])` | Permutation |
| `Permutation.cyclic_form` | Cycle notation |
| `PermutationGroup([perms])` | Permutation group |
| `SymmetricGroup(n)` | Symmetric group S_n |
| `CyclicGroup(n)` | Cyclic group Z_n |
| `DihedralGroup(n)` | Dihedral group D_n |
| `AlternatingGroup(n)` | Alternating group A_n |
| `Partition([parts])` | Integer partition |
| `IntegerPartition(n)` | All partitions of n |
| `Subset(subset, superset)` | Subset enumeration |
| `GrayCode(n)` | Gray code generation |

---

## Statistics -- `sympy.stats`

| Function / Class | Description |
|-----------------|-------------|
| `Normal('X', mu, sigma)` | Normal random variable |
| `Uniform('X', a, b)` | Uniform random variable |
| `Exponential('X', rate)` | Exponential |
| `Poisson('X', mu)` | Poisson |
| `Bernoulli('X', p)` | Bernoulli |
| `Binomial('X', n, p)` | Binomial |
| `Beta('X', a, b)` | Beta |
| `Gamma('X', k, theta)` | Gamma |
| `P(condition)` | Probability |
| `E(expr)` | Expected value |
| `variance(X)` | Variance |
| `std(X)` | Standard deviation |
| `covariance(X, Y)` | Covariance |
| `density(X)` | Probability density function |
| `cdf(X)` | Cumulative distribution function |
| `moment(X, n)` | N-th moment |
| `median(X)` | Median |
| `sample(X)` | Generate random sample |

---

## Logic -- `sympy.logic`

| Function / Class | Description |
|-----------------|-------------|
| `And(a, b)` / `a & b` | Logical AND |
| `Or(a, b)` / `a | b` | Logical OR |
| `Not(a)` / `~a` | Logical NOT |
| `Implies(a, b)` | Implication |
| `Equivalent(a, b)` | Biconditional |
| `Xor(a, b)` | Exclusive OR |
| `satisfiable(expr)` | Find satisfying assignment |
| `simplify_logic(expr)` | Simplify logical expression |
| `SOPform(variables, minterms)` | Sum of products |
| `POSform(variables, minterms)` | Product of sums |
| `truth_table(expr, variables)` | Generate truth table |

---

## Sets -- `sympy.sets`

| Class | Description |
|-------|-------------|
| `FiniteSet(1, 2, 3)` | Finite set |
| `Interval(a, b)` | Closed interval [a, b] |
| `Interval.open(a, b)` | Open interval (a, b) |
| `S.Reals` | Set of real numbers |
| `S.Integers` | Set of integers |
| `S.Naturals` | Set of natural numbers |
| `S.Naturals0` | Natural numbers including 0 |
| `S.Complexes` | Set of complex numbers |
| `S.EmptySet` | Empty set |
| `S.UniversalSet` | Universal set |
| `Union(A, B)` | Set union |
| `Intersection(A, B)` | Set intersection |
| `Complement(A, B)` | Set difference A \ B |
| `SymmetricDifference(A, B)` | Symmetric difference |
| `ProductSet(A, B)` | Cartesian product |
| `ImageSet(f, S)` | Image of set under function |
| `ConditionSet(x, condition, S)` | Conditional set |

---

## Printing & LaTeX

| Function | Description |
|----------|-------------|
| `latex(expr)` | LaTeX string |
| `pretty(expr)` | Unicode pretty-print string |
| `mathml(expr)` | MathML output |
| `str(expr)` | Python string |
| `srepr(expr)` | Internal representation |
| `ccode(expr)` | C code generation |
| `fcode(expr)` | Fortran code generation |
| `jscode(expr)` | JavaScript code generation |
| `python(expr)` | Python code string |

---

## Physics -- `sympy.physics`

| Module | Description |
|--------|-------------|
| `sympy.physics.units` | Physical units and dimensions |
| `sympy.physics.mechanics` | Classical mechanics (Lagrangian, Hamiltonian) |
| `sympy.physics.quantum` | Quantum mechanics (operators, states, brakets) |
| `sympy.physics.optics` | Optics |
| `sympy.physics.vector` | Vector algebra in 3D reference frames |
| `sympy.physics.hydrogen` | Hydrogen atom wavefunctions |
| `sympy.physics.paulialgebra` | Pauli matrices |
| `sympy.physics.wigner` | Wigner symbols |

---

## Not Available

- `sympy.plotting` (no display backend on iOS -- use matplotlib instead)
- Interactive features (`init_printing`, `pprint` renders in terminal only)
