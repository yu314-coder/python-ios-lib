// torch_ios / offlinai_libs: Fortran runtime stubs for iOS.
//
// scipy's ARPACK / PROPACK / sparse / linalg extensions are compiled via
// flang-new and reference LLVM Flang's Fortran runtime. Rather than
// ship full libflang_rt.runtime (which isn't cross-compiled for iOS),
// we provide no-op stubs for the 22 `_Fortran*` symbols scipy actually
// calls. I/O paths silently discard output; STOP statements abort.

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef void* Cookie;

// ─── I/O begin calls — return a non-null cookie ───────────────────────
static Cookie _cookie(void) { return (Cookie)1; }

Cookie _FortranAioBeginExternalFormattedOutput(const char* fmt, size_t fl,
    void* scratch, size_t sl, int unit, const char* src, int line) {
    (void)fmt;(void)fl;(void)scratch;(void)sl;(void)unit;(void)src;(void)line;
    return _cookie();
}
Cookie _FortranAioBeginExternalListOutput(int unit, const char* src, int line) {
    (void)unit;(void)src;(void)line;
    return _cookie();
}
Cookie _FortranAioBeginInternalFormattedOutput(char* buf, size_t bl,
    const char* fmt, size_t fl, void* scratch, size_t sl,
    const char* src, int line) {
    (void)buf;(void)bl;(void)fmt;(void)fl;(void)scratch;(void)sl;(void)src;(void)line;
    return _cookie();
}
Cookie _FortranAioBeginUnformattedInput(int unit, const char* src, int line) {
    (void)unit;(void)src;(void)line;
    return _cookie();
}
Cookie _FortranAioBeginOpenUnit(int unit, const char* src, int line) {
    (void)unit;(void)src;(void)line;
    return _cookie();
}
Cookie _FortranAioBeginClose(int unit, const char* src, int line) {
    (void)unit;(void)src;(void)line;
    return _cookie();
}

// ─── I/O body calls — all no-op, return truthy ──────────────────────────
int _FortranAioEndIoStatement(Cookie c) { (void)c; return 0; }

int _FortranAioOutputAscii(Cookie c, const char* s, size_t l) {
    (void)c;(void)s;(void)l; return 1;
}
int _FortranAioOutputDescriptor(Cookie c, void* d)     { (void)c;(void)d; return 1; }
int _FortranAioInputDescriptor(Cookie c, void* d)      { (void)c;(void)d; return 1; }
int _FortranAioOutputInteger32(Cookie c, int32_t v)    { (void)c;(void)v; return 1; }
int _FortranAioOutputReal32(Cookie c, float v)         { (void)c;(void)v; return 1; }
int _FortranAioOutputReal64(Cookie c, double v)        { (void)c;(void)v; return 1; }
int _FortranAioOutputComplex32(Cookie c, float r, float i) {
    (void)c;(void)r;(void)i; return 1;
}
int _FortranAioOutputComplex64(Cookie c, double r, double i) {
    (void)c;(void)r;(void)i; return 1;
}

// I/O attribute setters (OPEN statement)
int _FortranAioSetFile(Cookie c, const char* path, size_t len) {
    (void)c;(void)path;(void)len; return 1;
}
int _FortranAioSetForm(Cookie c, const char* form, size_t len) {
    (void)c;(void)form;(void)len; return 1;
}
int _FortranAioSetStatus(Cookie c, const char* status, size_t len) {
    (void)c;(void)status;(void)len; return 1;
}

// ─── STOP statements ────────────────────────────────────────────────────
// Fortran STOP — abort via stdio so the error is visible.
_Noreturn void _FortranAStopStatement(int code, int quiet, int error_stop) {
    (void)quiet; (void)error_stop;
    fprintf(stderr, "[fortran] STOP %d\n", code);
    exit(code);
}
_Noreturn void _FortranAStopStatementText(const char* text, size_t len,
    int quiet, int error_stop) {
    (void)quiet; (void)error_stop;
    fprintf(stderr, "[fortran] STOP \"%.*s\"\n", (int)len, text ? text : "");
    exit(1);
}

// ─── String + math intrinsics ────────────────────────────────────────────
// TRIM intrinsic — trim trailing spaces. Returns a descriptor; here we just
// copy the input verbatim (scipy doesn't observe the result byte-for-byte
// in any path manim hits).
// Signature: void _FortranATrim(CFI_cdesc_t* result, const CFI_cdesc_t* in)
void _FortranATrim(void* result, const void* input) {
    (void)result; (void)input;
    // No-op. If scipy ever dereferences the result, we'd need a proper
    // CFI_cdesc_t here; for import-time constant folding this never runs.
}

// MOD(x, y) for REAL*8 — Fortran MOD intrinsic.
double _FortranAModReal8(double x, double y) {
    if (y == 0.0) return 0.0;
    double q = x / y;
    double qtrunc = (q >= 0) ? (double)(long long)q : -(double)(long long)(-q);
    return x - qtrunc * y;
}

// ─── BLAS / LAPACK auxiliary functions not in Apple Accelerate ─────────
// scipy's cython_blas and Fortran code path call these directly (Fortran
// calling convention: lowercase name + trailing underscore, args by ref).
// Accelerate provides the core BLAS symbols via the `$NEWLAPACK` suffix,
// but these tiny helpers are missing.

#include <math.h>
#include <ctype.h>

// dcabs1(z): sum of absolute values of real and imaginary parts of a
// complex double. Used in BLAS complex-norm calculations.
double dcabs1_(double *z) {
    return fabs(z[0]) + fabs(z[1]);
}

// lsame(ca, cb): case-insensitive single-character compare.
// Returns Fortran LOGICAL (0 or 1; platform int size).
int lsame_(const char *ca, const char *cb) {
    if (!ca || !cb) return 0;
    int a = toupper((unsigned char)ca[0]);
    int b = toupper((unsigned char)cb[0]);
    return a == b ? 1 : 0;
}

// dlartg(f, g, cs, sn, r): generate a plane (Givens) rotation such that
// [cs sn; -sn cs] * [f; g] = [r; 0]. Used by LAPACK in QR / SVD.
void dlartg_(double *f, double *g, double *cs, double *sn, double *r) {
    double F = *f, G = *g;
    if (G == 0.0) {
        *cs = 1.0; *sn = 0.0; *r = F;
    } else if (F == 0.0) {
        *cs = 0.0; *sn = 1.0; *r = G;
    } else {
        double d = sqrt(F * F + G * G);
        *cs = F / d;
        *sn = G / d;
        *r = d;
    }
}
