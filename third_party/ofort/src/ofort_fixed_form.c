#include "ofort_fixed_form.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int append_n(char **buf, size_t *len, size_t *cap, const char *text, size_t n) {
    if (*len + n + 1 > *cap) {
        size_t new_cap = *cap ? *cap : 8192;
        char *p;
        while (*len + n + 1 > new_cap) new_cap *= 2;
        p = (char *)realloc(*buf, new_cap);
        if (!p) return 0;
        *buf = p;
        *cap = new_cap;
    }
    if (n > 0) memcpy(*buf + *len, text, n);
    *len += n;
    (*buf)[*len] = '\0';
    return 1;
}

static int append_s(char **buf, size_t *len, size_t *cap, const char *text) {
    return append_n(buf, len, cap, text, strlen(text));
}

static void trim_right(char *s) {
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t' || s[n - 1] == '\r' || s[n - 1] == '\n')) {
        s[--n] = '\0';
    }
}

static int blank_text(const char *s) {
    while (*s) {
        if (!isspace((unsigned char)*s)) return 0;
        s++;
    }
    return 1;
}

static char *dup_range(const char *a, const char *b) {
    size_t n = (size_t)(b - a);
    char *s = (char *)malloc(n + 1);
    if (!s) return NULL;
    memcpy(s, a, n);
    s[n] = '\0';
    return s;
}

char *ofort_fixed_to_free(const char *source,
                          const char *filename,
                          const OfortFixedFormOptions *options,
                          char **error_message) {
    int line_limit = options && options->fixed_line_length ? options->fixed_line_length : 72;
    int preserve_comments = options ? options->preserve_comments : 1;
    const char *p = source ? source : "";
    char *out = NULL;
    size_t out_len = 0, out_cap = 0;
    int pending = 0;
    (void)filename;
    if (error_message) *error_message = NULL;

    while (*p) {
        const char *line_start = p;
        const char *line_end;
        char *line;
        char *body;
        int raw_len;
        int is_comment = 0;
        int is_cont = 0;
        int body_start = 6;
        int body_end;
        char label[16];
        int label_len = 0;

        while (*p && *p != '\n') p++;
        line_end = p;
        if (*p == '\n') p++;
        line = dup_range(line_start, line_end);
        if (!line) goto oom;
        raw_len = (int)strlen(line);
        while (raw_len > 0 && line[raw_len - 1] == '\r') line[--raw_len] = '\0';

        if (raw_len == 0 || blank_text(line)) {
            if (!pending) {
                if (!append_s(&out, &out_len, &out_cap, "\n")) { free(line); goto oom; }
            }
            free(line);
            continue;
        }

        if (line[0] == 'c' || line[0] == 'C' || line[0] == '*' || line[0] == '!') {
            is_comment = 1;
        }

        if (is_comment) {
            if (preserve_comments) {
                if (pending && !append_s(&out, &out_len, &out_cap, "\n")) { free(line); goto oom; }
                pending = 0;
                if (!append_s(&out, &out_len, &out_cap, "!")) { free(line); goto oom; }
                if (raw_len > 1 && !append_n(&out, &out_len, &out_cap, line + 1, (size_t)(raw_len - 1))) {
                    free(line); goto oom;
                }
                if (!append_s(&out, &out_len, &out_cap, "\n")) { free(line); goto oom; }
            }
            free(line);
            continue;
        }

        if (raw_len > 5 && line[5] != ' ' && line[5] != '0') is_cont = 1;
        label[0] = '\0';
        if (!is_cont) {
            int i;
            for (i = 0; i < raw_len && i < 5 && label_len < (int)sizeof(label) - 1; i++) {
                if (isdigit((unsigned char)line[i])) {
                    label[label_len++] = line[i];
                }
            }
            label[label_len] = '\0';
        }
        body_start = raw_len > 6 ? 6 : raw_len;
        body_end = raw_len;
        if (line_limit > 0 && body_end > line_limit) body_end = line_limit;
        body = dup_range(line + body_start, line + body_end);
        free(line);
        if (!body) goto oom;
        trim_right(body);

        if (blank_text(body)) {
            free(body);
            continue;
        }

        if (is_cont) {
            if (!pending) {
                if (!append_s(&out, &out_len, &out_cap, "&\n")) { free(body); goto oom; }
            } else {
                if (!append_s(&out, &out_len, &out_cap, " &\n")) { free(body); goto oom; }
            }
            if (!append_s(&out, &out_len, &out_cap, body)) { free(body); goto oom; }
            pending = 1;
        } else {
            if (pending) {
                if (!append_s(&out, &out_len, &out_cap, "\n")) { free(body); goto oom; }
            }
            if (label[0]) {
                if (!append_s(&out, &out_len, &out_cap, label)) { free(body); goto oom; }
                if (!append_s(&out, &out_len, &out_cap, " ")) { free(body); goto oom; }
            }
            if (!append_s(&out, &out_len, &out_cap, body)) { free(body); goto oom; }
            pending = 1;
        }
        free(body);
    }

    if (pending) {
        if (!append_s(&out, &out_len, &out_cap, "\n")) goto oom;
    }
    if (!out && !append_s(&out, &out_len, &out_cap, "")) goto oom;
    return out;

oom:
    free(out);
    if (error_message) {
        *error_message = (char *)malloc(14);
        if (*error_message) strcpy(*error_message, "out of memory");
    }
    return NULL;
}
