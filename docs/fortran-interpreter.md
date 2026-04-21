# Fortran Interpreter (offlinai_fortran)

> **Type:** Tree-walking Fortran 90/95/2003 interpreter | **Location:** `gcc/offlinai_fortran.c`, `gcc/offlinai_fortran.h` | **Language:** Fortran 90/95/2003 subset | **App Store safe**

A self-contained Fortran interpreter that lexes, parses, and executes Fortran code at runtime. Supports free-form source, modules, allocatable arrays up to 7 dimensions, 45+ intrinsic functions, and formatted I/O. Case-insensitive as per the Fortran standard. No JIT, no compilation, no external tools needed.

Edits `.f90` / `.f95` / `.f03` / `.f` / `.for` files in the shared Monaco-powered editor with Fortran syntax highlighting and auto-save (debounced ~600 ms; also flushed on run, tab switch, view disappear, and app backgrounding).

---

## Quick Start

```fortran
PROGRAM hello
    IMPLICIT NONE
    INTEGER :: i, n
    REAL :: sum, average
    REAL, DIMENSION(10) :: data

    n = 10
    sum = 0.0
    DO i = 1, n
        data(i) = REAL(i) * 1.5
        sum = sum + data(i)
    END DO

    average = sum / REAL(n)
    WRITE(*, '(A, F8.2)') 'Average: ', average
    WRITE(*, '(A, I0)') 'Count:   ', n
END PROGRAM hello
```

---

## Program Structure

### Basic Program Units

```fortran
PROGRAM main_program
    IMPLICIT NONE
    ! declarations
    ! executable statements
END PROGRAM main_program

SUBROUTINE my_sub(arg1, arg2)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: arg1
    REAL, INTENT(OUT) :: arg2
    arg2 = REAL(arg1) * 2.0
END SUBROUTINE my_sub

FUNCTION my_func(x) RESULT(y)
    IMPLICIT NONE
    REAL, INTENT(IN) :: x
    REAL :: y
    y = x * x + 1.0
END FUNCTION my_func
```

### Modules

```fortran
MODULE constants
    IMPLICIT NONE
    REAL, PARAMETER :: PI = 3.14159265358979
    REAL, PARAMETER :: E = 2.71828182845905
    REAL, PARAMETER :: G = 9.80665
END MODULE constants

MODULE geometry
    USE constants
    IMPLICIT NONE
CONTAINS
    FUNCTION circle_area(r) RESULT(area)
        REAL, INTENT(IN) :: r
        REAL :: area
        area = PI * r * r
    END FUNCTION circle_area

    FUNCTION sphere_volume(r) RESULT(vol)
        REAL, INTENT(IN) :: r
        REAL :: vol
        vol = (4.0 / 3.0) * PI * r * r * r
    END FUNCTION sphere_volume
END MODULE geometry

PROGRAM main
    USE geometry
    IMPLICIT NONE
    WRITE(*, *) 'Circle area (r=5): ', circle_area(5.0)
    WRITE(*, *) 'Sphere volume (r=3): ', sphere_volume(3.0)
END PROGRAM main
```

---

## Data Types

| Type | Declaration | Description |
|------|-------------|-------------|
| `INTEGER` | `INTEGER :: n = 42` | Integer (64-bit) |
| `REAL` | `REAL :: x = 3.14` | Single-precision float (stored as double internally) |
| `DOUBLE PRECISION` | `DOUBLE PRECISION :: d = 3.14D0` | Double-precision float |
| `COMPLEX` | `COMPLEX :: z = (1.0, 2.0)` | Complex number |
| `LOGICAL` | `LOGICAL :: flag = .TRUE.` | Boolean |
| `CHARACTER` | `CHARACTER(LEN=20) :: name = 'hello'` | Fixed-length string |
| `CHARACTER(*)` | `CHARACTER(*), INTENT(IN) :: s` | Assumed-length string |

### Type Qualifiers

| Qualifier | Description |
|-----------|-------------|
| `PARAMETER` | Named constant (`REAL, PARAMETER :: PI = 3.14159`) |
| `INTENT(IN)` | Read-only argument |
| `INTENT(OUT)` | Write-only argument |
| `INTENT(INOUT)` | Read-write argument |
| `ALLOCATABLE` | Dynamically allocatable |
| `DIMENSION(...)` | Array dimensions |
| `SAVE` | Preserve value between calls (like C `static`) |
| `IMPLICIT NONE` | Require explicit type declarations |

---

## Arrays

### Declaration & Initialization

```fortran
! Static arrays
INTEGER, DIMENSION(10) :: arr1
REAL :: matrix(3, 3)
INTEGER :: cube(4, 4, 4)

! Up to 7 dimensions
REAL :: tensor(2, 3, 4, 5, 6, 7, 8)

! Initializer
INTEGER :: v(5) = (/1, 2, 3, 4, 5/)
INTEGER :: w(5) = [1, 2, 3, 4, 5]  ! F2003 syntax

! Implied DO
INTEGER :: seq(10) = [(i, i = 1, 10)]
REAL :: squares(5) = [(REAL(i)**2, i = 1, 5)]
```

### Allocatable Arrays

```fortran
REAL, ALLOCATABLE :: data(:)
REAL, ALLOCATABLE :: grid(:,:)
INTEGER :: n

n = 100
ALLOCATE(data(n))
ALLOCATE(grid(n, n))

DO i = 1, n
    data(i) = REAL(i)
END DO

! Check allocation status
IF (ALLOCATED(data)) THEN
    WRITE(*, *) 'data is allocated, size =', SIZE(data)
END IF

DEALLOCATE(data)
DEALLOCATE(grid)
```

### Array Operations (Whole-Array)

```fortran
REAL :: a(5) = [1.0, 2.0, 3.0, 4.0, 5.0]
REAL :: b(5) = [5.0, 4.0, 3.0, 2.0, 1.0]
REAL :: c(5)

! Element-wise operations
c = a + b          ! [6, 6, 6, 6, 6]
c = a * b          ! [5, 8, 9, 8, 5]
c = a ** 2         ! [1, 4, 9, 16, 25]

! Array sections
c(1:3) = a(3:5)    ! Slice assignment
c(::2) = 0.0       ! Stride: every other element

! WHERE construct
WHERE (a > 3.0)
    c = a
ELSEWHERE
    c = 0.0
END WHERE
```

### Array Intrinsics

| Function | Description |
|----------|-------------|
| `SIZE(array, dim)` | Total number of elements (or along dimension) |
| `SHAPE(array)` | Array of dimension extents |
| `LBOUND(array, dim)` | Lower bound |
| `UBOUND(array, dim)` | Upper bound |
| `SUM(array, dim, mask)` | Sum of elements |
| `PRODUCT(array, dim, mask)` | Product of elements |
| `MAXVAL(array, dim, mask)` | Maximum value |
| `MINVAL(array, dim, mask)` | Minimum value |
| `MAXLOC(array, dim, mask)` | Location of maximum |
| `MINLOC(array, dim, mask)` | Location of minimum |
| `COUNT(mask, dim)` | Count of .TRUE. elements |
| `ANY(mask, dim)` | .TRUE. if any element is .TRUE. |
| `ALL(mask, dim)` | .TRUE. if all elements are .TRUE. |
| `MATMUL(A, B)` | Matrix multiplication |
| `DOT_PRODUCT(A, B)` | Dot product |
| `TRANSPOSE(A)` | Matrix transpose |
| `RESHAPE(source, shape)` | Reshape array |
| `MERGE(tsource, fsource, mask)` | Conditional merge |
| `PACK(array, mask)` | Pack elements where mask is .TRUE. |
| `UNPACK(vector, mask, field)` | Unpack vector into array |
| `SPREAD(source, dim, ncopies)` | Replicate array along dimension |
| `CSHIFT(array, shift, dim)` | Circular shift |
| `EOSHIFT(array, shift, boundary, dim)` | End-off shift |

---

## Control Flow

### IF / THEN / ELSE

```fortran
IF (x > 0) THEN
    WRITE(*, *) 'Positive'
ELSE IF (x < 0) THEN
    WRITE(*, *) 'Negative'
ELSE
    WRITE(*, *) 'Zero'
END IF

! One-line IF
IF (x > 0) WRITE(*, *) 'Positive'
```

### DO Loop

```fortran
! Counted DO
DO i = 1, 10
    WRITE(*, *) i
END DO

! DO with step
DO i = 10, 1, -1
    WRITE(*, *) i
END DO

! DO with step of 2
DO i = 0, 20, 2
    WRITE(*, *) i
END DO

! DO WHILE
n = 1
DO WHILE (n <= 100)
    n = n * 2
END DO

! Infinite DO with EXIT
DO
    READ(*, *) x
    IF (x < 0) EXIT
    WRITE(*, *) SQRT(x)
END DO

! Named DO with CYCLE
outer: DO i = 1, 10
    inner: DO j = 1, 10
        IF (MOD(j, 3) == 0) CYCLE inner
        IF (i * j > 50) EXIT outer
        WRITE(*, *) i, j
    END DO inner
END DO outer
```

### SELECT CASE

```fortran
SELECT CASE (grade)
    CASE ('A')
        WRITE(*, *) 'Excellent'
    CASE ('B', 'C')
        WRITE(*, *) 'Good'
    CASE ('D')
        WRITE(*, *) 'Below average'
    CASE ('F')
        WRITE(*, *) 'Fail'
    CASE DEFAULT
        WRITE(*, *) 'Invalid grade'
END SELECT

! Integer ranges
SELECT CASE (score)
    CASE (90:100)
        grade = 'A'
    CASE (80:89)
        grade = 'B'
    CASE (70:79)
        grade = 'C'
    CASE (:69)
        grade = 'F'
END SELECT
```

---

## Subroutines & Functions

### Subroutines

```fortran
SUBROUTINE swap(a, b)
    IMPLICIT NONE
    INTEGER, INTENT(INOUT) :: a, b
    INTEGER :: temp
    temp = a
    a = b
    b = temp
END SUBROUTINE swap

! Call with CALL keyword
CALL swap(x, y)
```

### Functions

```fortran
! With RESULT clause
FUNCTION factorial(n) RESULT(fact)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    INTEGER :: fact
    INTEGER :: i
    fact = 1
    DO i = 2, n
        fact = fact * i
    END DO
END FUNCTION factorial

! Recursive functions
RECURSIVE FUNCTION fib(n) RESULT(f)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    INTEGER :: f
    IF (n <= 1) THEN
        f = n
    ELSE
        f = fib(n - 1) + fib(n - 2)
    END IF
END FUNCTION fib
```

### Internal Subprograms (CONTAINS)

```fortran
PROGRAM main
    IMPLICIT NONE
    WRITE(*, *) double(21)
CONTAINS
    FUNCTION double(x) RESULT(y)
        INTEGER, INTENT(IN) :: x
        INTEGER :: y
        y = x * 2
    END FUNCTION double
END PROGRAM main
```

---

## I/O -- WRITE, PRINT, and Format Descriptors

### Free-Format Output

```fortran
WRITE(*, *) 'Hello, World!'
WRITE(*, *) 'x =', x, 'y =', y
PRINT *, 'Sum =', a + b
```

### Formatted Output

```fortran
! Format descriptors
WRITE(*, '(A)')         'Hello'          ! String
WRITE(*, '(I5)')        42               ! Integer, width 5
WRITE(*, '(I0)')        42               ! Integer, minimum width
WRITE(*, '(I8.5)')      42               ! Integer, width 8, min 5 digits (00042)
WRITE(*, '(F10.3)')     3.14159          ! Float, width 10, 3 decimals
WRITE(*, '(E12.4)')     12345.6          ! Scientific: 0.1235E+05
WRITE(*, '(ES12.4)')    12345.6          ! Engineering: 1.2346E+04
WRITE(*, '(G12.4)')     12345.6          ! General (auto format)
WRITE(*, '(L5)')        .TRUE.           ! Logical, width 5
WRITE(*, '(A10)')       'hello'          ! String, width 10
WRITE(*, '(3I5)')       1, 2, 3          ! Repeat count
WRITE(*, '(2(I3,1X))')  1, 2             ! Grouped format
WRITE(*, '(A, I0, A, F6.2)') 'n=', n, ' x=', x  ! Mixed
```

### Format Descriptor Reference

| Descriptor | Description |
|------------|-------------|
| `In` / `In.m` | Integer, width n, min m digits |
| `Fn.d` | Fixed-point real, width n, d decimals |
| `En.d` | Scientific notation |
| `ESn.d` | Engineering notation |
| `Gn.d` | General (auto-selects F or E) |
| `Dn.d` | Double precision (same as E with D exponent) |
| `An` | Character, width n |
| `Ln` | Logical, width n |
| `nX` | n spaces (horizontal skip) |
| `/` | New line |
| `Tn` | Tab to column n |
| `TLn` / `TRn` | Tab left/right n positions |
| `nP` | Scale factor for E/F format |
| `'text'` | Literal string in format |
| `r(...)` | Repeat group r times |

---

## Operators

### Arithmetic

`+`, `-`, `*`, `/`, `**` (power)

### Comparison (Dot-Operators)

| Operator | Alternative | Description |
|----------|------------|-------------|
| `.EQ.` | `==` | Equal |
| `.NE.` | `/=` | Not equal |
| `.LT.` | `<` | Less than |
| `.GT.` | `>` | Greater than |
| `.LE.` | `<=` | Less than or equal |
| `.GE.` | `>=` | Greater than or equal |

### Logical

| Operator | Description |
|----------|-------------|
| `.AND.` | Logical AND |
| `.OR.` | Logical OR |
| `.NOT.` | Logical NOT |
| `.EQV.` | Logical equivalence |
| `.NEQV.` | Logical non-equivalence (XOR) |

### String

| Operator | Description |
|----------|-------------|
| `//` | String concatenation |

---

## Intrinsic Functions (45+)

### Mathematical

| Function | Description |
|----------|-------------|
| `ABS(x)` | Absolute value |
| `SQRT(x)` | Square root |
| `EXP(x)` | Exponential (e^x) |
| `LOG(x)` | Natural logarithm |
| `LOG10(x)` | Base-10 logarithm |
| `SIN(x)` / `COS(x)` / `TAN(x)` | Trigonometric |
| `ASIN(x)` / `ACOS(x)` / `ATAN(x)` | Inverse trig |
| `ATAN2(y, x)` | Two-argument arctangent |
| `SINH(x)` / `COSH(x)` / `TANH(x)` | Hyperbolic |
| `MOD(a, p)` | Modulo (a - INT(a/p)*p) |
| `MODULO(a, p)` | Fortran modulo (differs from MOD for negative) |
| `SIGN(a, b)` | ABS(a) with sign of b |
| `MAX(a, b, ...)` | Maximum of arguments |
| `MIN(a, b, ...)` | Minimum of arguments |
| `DIM(x, y)` | Positive difference: MAX(x-y, 0) |
| `CEILING(x)` | Smallest integer >= x |
| `FLOOR(x)` | Largest integer <= x |
| `NINT(x)` | Nearest integer |
| `INT(x)` | Truncation to integer |
| `REAL(x)` / `FLOAT(x)` | Convert to real |
| `DBLE(x)` | Convert to double precision |
| `CMPLX(x, y)` | Create complex number |
| `CONJG(z)` | Complex conjugate |
| `AIMAG(z)` | Imaginary part |

### Character

| Function | Description |
|----------|-------------|
| `LEN(string)` | String length |
| `LEN_TRIM(string)` | Length without trailing spaces |
| `TRIM(string)` | Remove trailing spaces |
| `ADJUSTL(string)` | Left-justify |
| `ADJUSTR(string)` | Right-justify |
| `INDEX(string, substring)` | Position of substring |
| `SCAN(string, set)` | Position of first char in set |
| `VERIFY(string, set)` | Position of first char not in set |
| `REPEAT(string, ncopies)` | Repeat string n times |
| `CHAR(i)` | Character from ASCII code |
| `ICHAR(c)` | ASCII code from character |
| `ACHAR(i)` | Character from ASCII (same as CHAR) |
| `IACHAR(c)` | ASCII code (same as ICHAR) |
| `LGE(a, b)` / `LGT(a, b)` | Lexical comparison (>=, >) |
| `LLE(a, b)` / `LLT(a, b)` | Lexical comparison (<=, <) |

### Type Inquiry

| Function | Description |
|----------|-------------|
| `KIND(x)` | Kind type parameter |
| `SELECTED_INT_KIND(r)` | Integer kind for range r |
| `SELECTED_REAL_KIND(p, r)` | Real kind for precision p, range r |
| `HUGE(x)` | Largest representable number |
| `TINY(x)` | Smallest positive number |
| `EPSILON(x)` | Machine epsilon |
| `PRECISION(x)` | Decimal precision |
| `RANGE(x)` | Decimal exponent range |
| `BIT_SIZE(i)` | Number of bits in integer |

### Bit Manipulation

| Function | Description |
|----------|-------------|
| `IAND(i, j)` | Bitwise AND |
| `IOR(i, j)` | Bitwise OR |
| `IEOR(i, j)` | Bitwise XOR |
| `NOT(i)` | Bitwise NOT |
| `ISHFT(i, shift)` | Logical shift |
| `ISHFTC(i, shift, size)` | Circular shift |
| `BTEST(i, pos)` | Test bit |
| `IBSET(i, pos)` | Set bit |
| `IBCLR(i, pos)` | Clear bit |

### System

| Function | Description |
|----------|-------------|
| `RANDOM_NUMBER(x)` | Fill with uniform random [0, 1) |
| `RANDOM_SEED(size, put, get)` | Random seed control |
| `SYSTEM_CLOCK(count, count_rate, count_max)` | System clock |
| `CPU_TIME(time)` | CPU time in seconds |
| `DATE_AND_TIME(date, time, zone, values)` | Current date and time |

---

## Case Insensitivity

Fortran is fully case-insensitive. All of these are equivalent:

```fortran
PROGRAM example      ! uppercase
program example      ! lowercase
Program Example      ! mixed case
pRoGrAm eXaMpLe     ! any combination
```

Keywords, variable names, function names, and intrinsic functions are all case-insensitive.

---

## Derived Types (Structs)

```fortran
TYPE :: Person
    CHARACTER(LEN=50) :: name
    INTEGER :: age
    REAL :: height
END TYPE Person

TYPE(Person) :: p1, p2

p1%name = 'Alice'
p1%age = 30
p1%height = 1.65

! Constructor syntax
p2 = Person('Bob', 25, 1.80)

WRITE(*, '(A, A, A, I0)') 'Name: ', TRIM(p1%name), ', Age: ', p1%age
```

### Nested Types

```fortran
TYPE :: Vector2D
    REAL :: x, y
END TYPE Vector2D

TYPE :: Particle
    TYPE(Vector2D) :: position
    TYPE(Vector2D) :: velocity
    REAL :: mass
END TYPE Particle

TYPE(Particle) :: p
p%position%x = 1.0
p%position%y = 2.0
p%velocity = Vector2D(3.0, 4.0)
p%mass = 1.5
```

---

## Example: Matrix Operations

```fortran
PROGRAM matrix_ops
    IMPLICIT NONE
    INTEGER, PARAMETER :: N = 3
    REAL :: A(N, N), B(N, N), C(N, N)
    INTEGER :: i, j

    ! Initialize
    DO i = 1, N
        DO j = 1, N
            A(i, j) = REAL(i + j)
            B(i, j) = REAL(i * j)
        END DO
    END DO

    ! Matrix multiply using intrinsic
    C = MATMUL(A, B)

    ! Print result
    DO i = 1, N
        WRITE(*, '(3F8.2)') (C(i, j), j = 1, N)
    END DO

    ! Other operations
    WRITE(*, '(A, F8.2)') 'Trace: ', SUM([(A(i,i), i=1,N)])
    WRITE(*, '(A, F8.2)') 'Frobenius norm: ', SQRT(SUM(A**2))
    WRITE(*, '(A, F8.2)') 'Max element: ', MAXVAL(A)
    WRITE(*, '(A, 2I3)')  'Max location: ', MAXLOC(A)
END PROGRAM matrix_ops
```

---

## Limits

| Limit | Value |
|-------|-------|
| Max variables per scope | 512 |
| Max functions/subroutines | 128 |
| Max output buffer | 64 KB |
| Max string length | 4,096 chars |
| Max array dimensions | 7 |
| Max array elements | 10,000 |
| Max tokens | 32,768 |
| Max loop iterations | 1,000,000 |
| Max derived types | 64 |
| Max type fields | 32 |
| Max modules | 32 |
| Max module members | 128 |

---

## Not Supported

| Feature | Notes |
|---------|-------|
| Pointers (`POINTER`, `TARGET`) | Not implemented |
| Abstract interfaces | Not implemented |
| Type-bound procedures | F2003 OOP not fully supported |
| Operator overloading (`INTERFACE OPERATOR`) | Not implemented |
| Generic interfaces (`INTERFACE`) | Not implemented |
| `FORALL` construct | Use DO loops instead |
| Coarrays (F2008) | Parallel features not applicable |
| `BLOCK` construct (F2008) | Not implemented |
| `DO CONCURRENT` (F2008) | Use regular DO loops |
| File I/O (`OPEN`, `READ` from file) | No filesystem access from interpreter |
| `NAMELIST` I/O | Not implemented |
| `EQUIVALENCE` | Not implemented |
| `COMMON` blocks | Use modules instead |
| `DATA` statements | Use initializers instead |
| `ASSOCIATE` construct (F2003) | Not implemented |
| Binary/octal/hex BOZ literals in I/O | Not implemented |
