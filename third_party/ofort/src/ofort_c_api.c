#include "ofort.h"
#include "ofort_c_api.h"

#include <string.h>

static int copy_text(const char *text, char *buf, int buf_size) {
    int len;

    if (!text) text = "";
    len = (int)strlen(text);
    if (buf && buf_size > 0) {
        int n = len;
        if (n > buf_size - 1) n = buf_size - 1;
        if (n > 0) memcpy(buf, text, (size_t)n);
        buf[n] = '\0';
    }
    return len;
}

void *ofort_c_create(void) {
    return ofort_create();
}

void ofort_c_destroy(void *interp) {
    ofort_destroy((OfortInterpreter *)interp);
}

void ofort_c_reset(void *interp) {
    ofort_reset((OfortInterpreter *)interp);
}

int ofort_c_execute(void *interp, const char *source) {
    if (!interp || !source) return -1;
    return ofort_execute((OfortInterpreter *)interp, source);
}

int ofort_c_check(void *interp, const char *source) {
    if (!interp || !source) return -1;
    return ofort_check((OfortInterpreter *)interp, source);
}

int ofort_c_call_real1(void *interp, const char *name, double x, double *result) {
    if (!interp || !name || !result) return -1;
    return ofort_call_real1((OfortInterpreter *)interp, name, x, result);
}

void ofort_c_set_implicit_typing(void *interp, int enabled) {
    ofort_set_implicit_typing((OfortInterpreter *)interp, enabled);
}

void ofort_c_set_warnings_enabled(void *interp, int enabled) {
    ofort_set_warnings_enabled((OfortInterpreter *)interp, enabled);
}

void ofort_c_set_fast_mode(void *interp, int enabled) {
    ofort_set_fast_mode((OfortInterpreter *)interp, enabled);
}

void ofort_c_set_trace_assign(void *interp, int enabled) {
    ofort_set_trace_assign((OfortInterpreter *)interp, enabled);
}

int ofort_c_copy_output(void *interp, char *buf, int buf_size) {
    return copy_text(interp ? ofort_get_output((OfortInterpreter *)interp) : "", buf, buf_size);
}

int ofort_c_copy_error(void *interp, char *buf, int buf_size) {
    return copy_text(interp ? ofort_get_error((OfortInterpreter *)interp) : "", buf, buf_size);
}

int ofort_c_copy_warnings(void *interp, char *buf, int buf_size) {
    return copy_text(interp ? ofort_get_warnings((OfortInterpreter *)interp) : "", buf, buf_size);
}
