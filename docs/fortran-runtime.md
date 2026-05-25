# Fortran Runtime Stubs

**Type:** LLVM Flang runtime stubs + BLAS auxiliary shims + Fortran interpreter
**Location:** `/Volumes/D/OfflinAi/fortran/`
**Status:** All flang-required symbols implemented as no-ops; numerical paths unaffected

Provides minimal Flang runtime I/O + math intrinsic stubs so that
scipy's Fortran-compiled modules can load on iOS. All Fortran I/O
operations become silent no-ops; STOP statements abort with a clear
message. A separate single-file Fortran interpreter is also bundled
for executing user-supplied Fortran source at runtime.

NOTE: This is NOT a port of `libgfortran` — scipy on iOS is built
with **LLVM Flang** (`flang-new`), so the stubs cover Flang's
`_FortranA*` runtime ABI, not GFortran's `_gfortran_*` ABI. (The two
runtimes are incompatible.)

---

## Why This Exists

scipy includes many modules written in Fortran (COBYLA, LSODA,
ARPACK, FITPACK, ODR, etc.). These were compiled with `flang-new`
(LLVM 22) for iOS arm64. The compiled modules reference Fortran
runtime symbols for `WRITE`/`PRINT` statements; iOS doesn't ship
flang's runtime library (`libflang_rt.runtime.dylib`).

This stub provides all 22 required Flang symbols as safe no-ops.
Fortran diagnostic output is silently suppressed; numerical
computation is unaffected. Plus 3 BLAS auxiliary helpers
(`dcabs1_`, `lsame_`, `dlartg_`) that Apple Accelerate's BLAS
doesn't expose.

---

## Files

| File | Purpose |
|---|---|
| `fortran_io_stubs.c` | 22 Flang `_Fortran*` runtime symbols + 3 BLAS auxiliary helpers |
| `libfortran_io_stubs.dylib` | Pre-built dylib (cross-compiled for `arm64-apple-ios17.0`) |
| `offlinai_fortran.c` | **Standalone Fortran 90/95/2003 interpreter** (4096 LOC, single file, no JIT) |
| `offlinai_fortran.h` | Public C API for the interpreter (`ofort_create`, `ofort_execute`, `ofort_get_output`, `ofort_get_error`, `ofort_reset`, `ofort_destroy`) |
| `npy_math_ios.c` | numpy-math fallback shims (`npy_clear_floatstatus`, `npy_spacing`, complex math) — bundled with `_fortran_io_stubs` |
| `ios-arm64-cross.ini` | Meson cross-file for building scipy modules with flang |
| `ios-flang-wrapper.py` | Wrapper around `flang-new` that injects iOS sysroot + linker flags |
| `README.md` | Build/install instructions |

---

## Build

```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
clang -target arm64-apple-ios17.0 -isysroot "$SDK" \
  -shared -o libfortran_io_stubs.dylib \
  fortran_io_stubs.c npy_math_ios.c \
  -install_name @rpath/libfortran_io_stubs.dylib
```

---

## Symbols (Flang runtime — 22 total)

### I/O Begin functions (return a dummy cookie)

| Symbol | Fortran statement |
|---|---|
| `_FortranAioBeginExternalFormattedOutput` | `WRITE(unit, fmt)` |
| `_FortranAioBeginExternalListOutput` | `WRITE(unit, *)` |
| `_FortranAioBeginInternalFormattedOutput` | `WRITE(buf, fmt)` |
| `_FortranAioBeginExternalFormattedInput` | `READ(unit, fmt)` |
| `_FortranAioBeginUnformattedInput` | `READ(unit)` binary |
| `_FortranAioBeginOpenUnit` | `OPEN(unit=...)` |
| `_FortranAioBeginClose` | `CLOSE(unit)` |

### I/O Output functions (no-op, return 1)

| Symbol | Type |
|---|---|
| `_FortranAioOutputAscii` | string |
| `_FortranAioOutputInteger32` | int32 |
| `_FortranAioOutputReal32` | float |
| `_FortranAioOutputReal64` | double |
| `_FortranAioOutputComplex32` | complex float |
| `_FortranAioOutputComplex64` | complex double |
| `_FortranAioOutputDescriptor` | descriptor |

### I/O Control + setters (no-op, return 1 / 0)

| Symbol | Purpose |
|---|---|
| `_FortranAioEndIoStatement` | End I/O block (returns 0 = success) |
| `_FortranAioInputDescriptor` | Read descriptor |
| `_FortranAioSetFile` | Set filename for OPEN |
| `_FortranAioSetForm` | Set FORM= (formatted/unformatted) |
| `_FortranAioSetStatus` | Set STATUS= (old/new/replace) |

### Stop statements (abort with message)

| Symbol | Purpose |
|---|---|
| `_FortranAStopStatement` | `STOP code` — prints `[fortran] STOP <n>` to stderr, calls `exit(code)` |
| `_FortranAStopStatementText` | `STOP "message"` — prints `[fortran] STOP "<msg>"`, calls `exit(1)` |

Unlike most other stubs, STOP **does** terminate the process — Fortran
code that hits STOP is signaling a fatal numerical condition.

### Math intrinsics

| Symbol | Purpose | Implementation |
|---|---|---|
| `_FortranATrim` | `TRIM(string)` | No-op (scipy's hot paths don't observe result byte-for-byte) |
| `_FortranAModReal8` | `MOD(a, p)` for `real*8` | `x - trunc(x/y) * y` (Fortran MOD semantics, not `fmod`) |

---

## BLAS auxiliary symbols (also bundled — 3 total)

Apple Accelerate provides the core BLAS via the `$NEWLAPACK` suffix
suite, but these tiny helpers are missing.

| Symbol | Purpose |
|---|---|
| `dcabs1_` | Sum of absolute values of real + imaginary parts of a complex double. Used in BLAS complex-norm calculations |
| `lsame_` | Case-insensitive single-character compare (Fortran LOGICAL return) |
| `dlartg_` | Generate a plane (Givens) rotation: `[cs sn; -sn cs] * [f; g] = [r; 0]`. Used by LAPACK in QR / SVD |

Names use the Fortran calling convention (lowercase + trailing
underscore, args by reference).

---

## scipy modules linked against this stub

| Module | Flang symbols needed |
|---|---|
| `scipy.optimize._cobyla` | 6 |
| `scipy.integrate._lsoda` | 7 |
| `scipy.integrate._odepack` | 7 |
| `scipy.integrate._vode` | 6 |
| `scipy.integrate._dop` | 6 |
| `scipy.odr.__odrpack` | 10 |
| `scipy.interpolate._fitpack` | 6 |
| `scipy.interpolate._dfitpack` | 6 |
| `scipy.sparse.linalg._eigen.arpack._arpack` | 9 |
| `scipy.sparse.linalg._propack._dpropack` | 5 |
| `scipy.sparse.linalg._propack._spropack` | 5 |
| `scipy.sparse.linalg._propack._cpropack` | 5 |
| `scipy.sparse.linalg._propack._zpropack` | 5 |
| `scipy.io._test_fortran` | 8 |
| `scipy.integrate._test_odeint_banded` | 7 |
| `scipy.stats._mvn` | 1 |

---

## Bonus: standalone Fortran interpreter

`offlinai_fortran.c` is a **separate, self-contained
Fortran 90/95/2003 subset interpreter** that lets the host app run
arbitrary user-supplied Fortran code on-device. Tree-walking,
no JIT, no codegen — pure interpretation. ~4100 LOC, single file.

### Supported features

- **Types:** `INTEGER`, `REAL`, `DOUBLE PRECISION`, `CHARACTER`,
  `LOGICAL`, `COMPLEX`
- **Arrays:** 1-based indexing, up to 7 dimensions, `ALLOCATABLE`
- **Derived types** with field access (`%`)
- **Modules** with `USE` imports
- **Subroutines + functions** with `INTENT(IN|OUT|INOUT)`, `RESULT(name)`
- **Control flow:** `IF/ELSE IF/ELSE`, `DO`/`DO WHILE`, `SELECT CASE`,
  `EXIT`, `CYCLE`, `RETURN`, `STOP`, `CALL`
- **I/O:** `PRINT`, `WRITE`, `READ` (formatted, captured to in-memory output buffer)
- **String operators:** concatenation `//`, comparison
- **Logical operators:** `.AND.`, `.OR.`, `.NOT.`, `.EQV.`, `.NEQV.`
- **Numeric operators:** `+ - * / ** //`

### Intrinsic functions (58 total)

Math (25): `ABS, SQRT, SIN, COS, TAN, ASIN, ACOS, ATAN, ATAN2, EXP,
LOG, LOG10, MOD, MAX, MIN, FLOOR, CEILING, NINT, REAL, INT, DBLE,
CMPLX, AIMAG, CONJG, SIGN`

String (11): `LEN, LEN_TRIM, TRIM, ADJUSTL, ADJUSTR, INDEX, CHAR,
ICHAR, ACHAR, IACHAR, REPEAT`

Array (16): `SIZE, SHAPE, SUM, PRODUCT, MAXVAL, MINVAL, DOT_PRODUCT,
MATMUL, TRANSPOSE, RESHAPE, COUNT, ANY, ALL, ALLOCATED, LBOUND, UBOUND`

Type conversion (6): `FLOAT, DFLOAT, SNGL, LOGICAL, +DBLE, +INT (above)`

### C API

```c
#include "offlinai_fortran.h"

OfortInterpreter *interp = ofort_create();
int ret = ofort_execute(interp,
    "program hello\n"
    "  integer :: i\n"
    "  do i = 1, 5\n"
    "    print *, 'i =', i\n"
    "  end do\n"
    "end program\n");

if (ret == 0) {
    const char *out = ofort_get_output(interp);
    printf("%s", out);
} else {
    fprintf(stderr, "error: %s\n", ofort_get_error(interp));
}

ofort_destroy(interp);
```

### Limits

- `OFORT_MAX_VARS = 512` per scope
- `OFORT_MAX_FUNCS = 128`
- `OFORT_MAX_OUTPUT = 65536` bytes per `ofort_execute` call
- `OFORT_MAX_STRLEN = 4096` per string literal
- `OFORT_MAX_ARRAY = 10000` per array
- `OFORT_MAX_TOKENS = 32768` per source
- `OFORT_MAX_MODULES = 32`

---

## Not implemented

| Feature | Reason |
|---|---|
| Actual Fortran I/O (file read/write) from compiled scipy modules | iOS sandbox restrictions; diagnostic-only stubs are enough |
| Full Flang runtime error handling | Would require full libflang_rt |
| Fortran format descriptors in scipy stubs | Complex parsing not needed |
| NAMELIST I/O | Not used by scipy |
| Asynchronous I/O | Not used by scipy |
| `libgfortran`-style symbols (`_gfortran_*`) | scipy uses Flang, not GFortran |
| Coarrays / OpenMP (interpreter) | Not in F95 subset |
| JIT / code generation (interpreter) | Tree-walking only |

---

## See also

- `/Volumes/D/OfflinAi/fortran/README.md` — flang build instructions
- [scipy.md](scipy.md) — how scipy's Fortran modules are exposed in Python
