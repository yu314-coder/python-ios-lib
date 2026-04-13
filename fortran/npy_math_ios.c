/* Minimal npymath for iOS — provides float status and complex math wrappers */
#include <math.h>
#include <complex.h>
#include <fenv.h>

/* Float status */
int npy_clear_floatstatus(void) { int r = fetestexcept(FE_ALL_EXCEPT); feclearexcept(FE_ALL_EXCEPT); return r; }
int npy_clear_floatstatus_barrier(char *p) { (void)p; return npy_clear_floatstatus(); }
int npy_get_floatstatus(void) { return fetestexcept(FE_ALL_EXCEPT); }
int npy_get_floatstatus_barrier(char *p) { (void)p; return npy_get_floatstatus(); }
void npy_set_floatstatus_divbyzero(void) { feraiseexcept(FE_DIVBYZERO); }
void npy_set_floatstatus_overflow(void) { feraiseexcept(FE_OVERFLOW); }
void npy_set_floatstatus_underflow(void) { feraiseexcept(FE_UNDERFLOW); }
void npy_set_floatstatus_invalid(void) { feraiseexcept(FE_INVALID); }

/* Spacing (ULP) */
float npy_spacingf(float x) { return nextafterf(x, INFINITY) - x; }
double npy_spacing(double x) { return nextafter(x, INFINITY) - x; }
long double npy_spacingl(long double x) { return nextafterl(x, INFINITY) - x; }

/* Complex math wrappers */
double npy_cabs(double complex z) { return cabs(z); }
float npy_cabsf(float complex z) { return cabsf(z); }
long double npy_cabsl(long double complex z) { return cabsl(z); }

double complex npy_cacos(double complex z) { return cacos(z); }
float complex npy_cacosf(float complex z) { return cacosf(z); }
double complex npy_cacosh(double complex z) { return cacosh(z); }
float complex npy_cacoshf(float complex z) { return cacoshf(z); }
long double complex npy_cacoshl(long double complex z) { return cacoshl(z); }
long double complex npy_cacosl(long double complex z) { return cacosl(z); }

double complex npy_casin(double complex z) { return casin(z); }
float complex npy_casinf(float complex z) { return casinf(z); }
double complex npy_casinh(double complex z) { return casinh(z); }
float complex npy_casinhf(float complex z) { return casinhf(z); }

double complex npy_catan(double complex z) { return catan(z); }
float complex npy_catanf(float complex z) { return catanf(z); }
double complex npy_catanh(double complex z) { return catanh(z); }
float complex npy_catanhf(float complex z) { return catanhf(z); }

double complex npy_ccos(double complex z) { return ccos(z); }
float complex npy_ccosf(float complex z) { return ccosf(z); }
double complex npy_ccosh(double complex z) { return ccosh(z); }
float complex npy_ccoshf(float complex z) { return ccoshf(z); }

double complex npy_cexp(double complex z) { return cexp(z); }
float complex npy_cexpf(float complex z) { return cexpf(z); }

double complex npy_clog(double complex z) { return clog(z); }
float complex npy_clogf(float complex z) { return clogf(z); }

double complex npy_cpow(double complex a, double complex b) { return cpow(a, b); }
float complex npy_cpowf(float complex a, float complex b) { return cpowf(a, b); }

double complex npy_csin(double complex z) { return csin(z); }
float complex npy_csinf(float complex z) { return csinf(z); }
double complex npy_csinh(double complex z) { return csinh(z); }
float complex npy_csinhf(float complex z) { return csinhf(z); }

double complex npy_csqrt(double complex z) { return csqrt(z); }
float complex npy_csqrtf(float complex z) { return csqrtf(z); }

double complex npy_ctan(double complex z) { return ctan(z); }
float complex npy_ctanf(float complex z) { return ctanf(z); }
double complex npy_ctanh(double complex z) { return ctanh(z); }
float complex npy_ctanhf(float complex z) { return ctanhf(z); }
