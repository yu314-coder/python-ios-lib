// blas_compat_stubs.c — reference-BLAS helper functions that Apple's
// Accelerate framework does NOT export on iOS.
//
// scipy.linalg.cython_blas (and a few LAPACK paths) reference the small
// reference-BLAS helpers `dcabs1`, `scabs1`, and `lsame`. Apple's
// Accelerate provides the heavy BLAS/LAPACK kernels (dgemm, dgesv, …) but
// NOT these tiny helpers, so on a real iOS device dyld aborts with:
//
//     symbol not found in flat namespace '_dcabs1_'
//
// (see python-ios-lib issue #2). These are not real BLAS kernels — they're
// trivial scalar helpers — so providing them here and loading this dylib
// (via an LC_LOAD_DYLIB added to cython_blas.so) lets flat-namespace
// resolution succeed. Built for arm64 iOS, install_name
// @rpath/libscipy_blas_stubs.dylib.
//
// Fortran name-mangling appends a trailing underscore, so the exported
// Mach-O symbols are _dcabs1_, _scabs1_, _lsame_.

#include <math.h>

// DCABS1(Z) = |Re(Z)| + |Im(Z)|  — Z is COMPLEX*16, passed by reference
// (a pointer to two contiguous doubles: [real, imag]).
double dcabs1_(const double *z) {
    return fabs(z[0]) + fabs(z[1]);
}

// SCABS1(C) = |Re(C)| + |Im(C)|  — C is COMPLEX (single), by reference
// (a pointer to two contiguous floats: [real, imag]).
float scabs1_(const float *c) {
    return fabsf(c[0]) + fabsf(c[1]);
}

// LSAME(CA, CB) — case-insensitive comparison of two single characters,
// returns a Fortran LOGICAL (non-zero = .TRUE.). Fortran appends hidden
// character-length arguments after the value arguments; we ignore them
// and compare only the first character of each.
int lsame_(const char *ca, const char *cb, long ca_len, long cb_len) {
    (void)ca_len; (void)cb_len;
    int a = (unsigned char)ca[0];
    int b = (unsigned char)cb[0];
    if (a >= 'a' && a <= 'z') a -= 32;   // to upper
    if (b >= 'a' && b <= 'z') b -= 32;
    return a == b;
}
