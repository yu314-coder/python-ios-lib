#ifndef OFORT_C_API_H
#define OFORT_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

void *ofort_c_create(void);
void ofort_c_destroy(void *interp);
void ofort_c_reset(void *interp);

int ofort_c_execute(void *interp, const char *source);
int ofort_c_check(void *interp, const char *source);
int ofort_c_call_real1(void *interp, const char *name, double x, double *result);

void ofort_c_set_implicit_typing(void *interp, int enabled);
void ofort_c_set_warnings_enabled(void *interp, int enabled);
void ofort_c_set_fast_mode(void *interp, int enabled);
void ofort_c_set_trace_assign(void *interp, int enabled);

int ofort_c_copy_output(void *interp, char *buf, int buf_size);
int ofort_c_copy_error(void *interp, char *buf, int buf_size);
int ofort_c_copy_warnings(void *interp, char *buf, int buf_size);

#ifdef __cplusplus
}
#endif

#endif
