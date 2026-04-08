# Fortran Runtime Stub

> **Type:** Compiled C stub providing Fortran runtime symbols | **Location:** `fortran/`

Provides minimal Fortran runtime I/O and math intrinsic stubs so that scipy's Fortran-compiled modules can load on iOS. All I/O operations become silent no-ops.

---

## Why This Exists

scipy includes many modules written in Fortran (COBYLA, LSODA, ARPACK, FITPACK, ODR, etc.). These were compiled with `flang-new` (LLVM 22) for iOS arm64. The compiled modules reference Fortran runtime symbols for `WRITE`/`PRINT` statements, but iOS doesn't ship flang's runtime library (`libflang_rt.runtime.dylib`).

This stub provides all 22 required symbols as safe no-ops. Fortran diagnostic output is silently suppressed; numerical computation is unaffected.

---

## Build

```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
clang -target arm64-apple-ios17.0 -isysroot "$SDK" \
  -shared -o _fortran_stub.cpython-314-iphoneos.so \
  _fortran_stub.c \
  -install_name @rpath/site-packages.scipy._fortran_stub.cpython-314-iphoneos.framework/site-packages.scipy._fortran_stub.cpython-314-iphoneos
```

---

## Implemented Symbols (22)

### I/O Begin Functions

| Symbol | Fortran Statement | Stub Behavior |
|--------|-------------------|---------------|
| `_FortranAioBeginExternalFormattedOutput` | `WRITE(unit, fmt)` | Returns dummy cookie |
| `_FortranAioBeginExternalListOutput` | `WRITE(unit, *)` | Returns dummy cookie |
| `_FortranAioBeginInternalFormattedOutput` | `WRITE(buf, fmt)` | Returns dummy cookie |
| `_FortranAioBeginExternalFormattedInput` | `READ(unit, fmt)` | Returns dummy cookie |
| `_FortranAioBeginUnformattedInput` | `READ(unit)` binary | Returns dummy cookie |
| `_FortranAioBeginOpenUnit` | `OPEN(unit=...)` | Returns dummy cookie |
| `_FortranAioBeginClose` | `CLOSE(unit)` | Returns dummy cookie |

### I/O Output Functions

| Symbol | Purpose | Stub Behavior |
|--------|---------|---------------|
| `_FortranAioOutputAscii` | Write string | No-op, returns 1 (success) |
| `_FortranAioOutputInteger32` | Write int32 | No-op, returns 1 |
| `_FortranAioOutputReal32` | Write float | No-op, returns 1 |
| `_FortranAioOutputReal64` | Write double | No-op, returns 1 |
| `_FortranAioOutputComplex32` | Write complex float | No-op, returns 1 |
| `_FortranAioOutputComplex64` | Write complex double | No-op, returns 1 |
| `_FortranAioOutputDescriptor` | Write descriptor | No-op, returns 1 |

### I/O Control Functions

| Symbol | Purpose | Stub Behavior |
|--------|---------|---------------|
| `_FortranAioEndIoStatement` | End I/O block | Returns 0 (success) |
| `_FortranAioInputDescriptor` | Read descriptor | No-op, returns 1 |
| `_FortranAioSetFile` | Set filename | No-op, returns 1 |
| `_FortranAioSetForm` | Set form (formatted/unformatted) | No-op, returns 1 |
| `_FortranAioSetStatus` | Set status (old/new) | No-op, returns 1 |

### Stop Statements

| Symbol | Purpose | Stub Behavior |
|--------|---------|---------------|
| `_FortranAStopStatement` | `STOP` | Silent return (does NOT abort) |
| `_FortranAStopStatementText` | `STOP "message"` | Silent return |

### Math Intrinsics

| Symbol | Purpose | Stub Behavior |
|--------|---------|---------------|
| `_FortranATrim` | `TRIM(string)` | Copies string, removes trailing spaces |
| `_FortranAModReal8` | `MOD(a, p)` for real*8 | Returns `fmod(a, p)` |

---

## scipy Modules Using This Stub

| Module | Symbols Needed |
|--------|----------------|
| `scipy.optimize._cobyla` | 6 symbols |
| `scipy.integrate._lsoda` | 7 symbols |
| `scipy.integrate._odepack` | 7 symbols |
| `scipy.integrate._vode` | 6 symbols |
| `scipy.integrate._dop` | 6 symbols |
| `scipy.odr.__odrpack` | 10 symbols |
| `scipy.interpolate._fitpack` | 6 symbols |
| `scipy.interpolate._dfitpack` | 6 symbols |
| `scipy.sparse.linalg._eigen.arpack._arpack` | 9 symbols |
| `scipy.sparse.linalg._propack._dpropack` | 5 symbols |
| `scipy.sparse.linalg._propack._spropack` | 5 symbols |
| `scipy.sparse.linalg._propack._cpropack` | 5 symbols |
| `scipy.sparse.linalg._propack._zpropack` | 5 symbols |
| `scipy.io._test_fortran` | 8 symbols |
| `scipy.integrate._test_odeint_banded` | 7 symbols |
| `scipy.stats._mvn` | 1 symbol |

---

## Not Implemented

| Feature | Reason |
|---------|--------|
| Actual Fortran I/O (file read/write) | iOS sandbox restrictions; diagnostic only |
| Fortran runtime error handling | Would require full runtime |
| Fortran format descriptors | Complex parsing not needed for stubs |
| NAMELIST I/O | Not used by scipy |
| Asynchronous I/O | Not used by scipy |
