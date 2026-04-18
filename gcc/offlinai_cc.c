/*
 * OfflinAi C Interpreter — single-file implementation.
 * Lexer → Parser → Tree-walking interpreter.
 *
 * Supports: full C89 with extensions — pointers (vmem-backed), structs, unions,
 * function pointers, static variables, goto/labels, compound literals,
 * multi-dimensional arrays, function-like macros, qsort, sprintf to buffer, etc.
 */

#include "offlinai_cc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <stdarg.h>
#include <setjmp.h>
#include <time.h>
#include <float.h>
#include <limits.h>

/* ══════════════════════════════════════════════
 *  Interpreter state
 * ══════════════════════════════════════════════ */

typedef struct {
    char name[256];
    OccValue val;
    int is_const;
    int vmem_addr; /* vmem address for addressable vars, 0 = not allocated */
} OccVar;

typedef struct OccScope {
    OccVar vars[OCC_MAX_VARS];
    int n_vars;
    struct OccScope *parent;
} OccScope;

typedef struct {
    char name[256];
    OccNode *node;
} OccFunc;

struct OccInterpreter {
    /* output */
    char output[OCC_MAX_OUTPUT];
    int out_len;
    char error[4096];
    /* tokens */
    OccToken tokens[OCC_MAX_TOKENS];
    int n_tokens;
    int tok_pos;
    /* AST */
    OccNode *ast;
    /* runtime */
    OccScope *global_scope;
    OccScope *current_scope;
    OccFunc funcs[OCC_MAX_FUNCS];
    int n_funcs;
    /* control flow */
    int returning;
    OccValue return_val;
    int breaking;
    int continuing;
    /* error recovery */
    jmp_buf err_jmp;
    int has_error;
    /* source for error reporting */
    const char *source;
    /* preprocessor defines */
    struct { char name[128]; char value[256]; } defines[256];
    int n_defines;
    /* enum tracking */
    struct { char name[128]; long long value; } enum_vals[256];
    int n_enum_vals;
    /* malloc'd blocks (simplified heap - legacy, kept for compat) */
    struct { OccValue *data; int size; long long id; } heap_blocks[256];
    int n_heap_blocks;
    long long next_heap_id;
    /* struct type definitions */
    struct {
        char name[128];
        char field_names[32][64];
        OccValType field_types[32];
        int field_array_sizes[32];
        int n_fields;
        int is_union;
    } struct_types[64];
    int n_struct_types;
    /* typedef aliases */
    struct { char alias[128]; char original[128]; } typedefs[64];
    int n_typedefs;
    /* ── New: virtual memory system ── */
    OccValue *vmem;
    int vmem_size;
    int vmem_used;
    /* ── New: static variables ── */
    struct { char func[128]; char var[128]; OccValue val; int init; } statics[256];
    int n_statics;
    /* ── New: current function name ── */
    char current_func[128];
    /* ── New: goto support ── */
    char goto_target[64];
    int goto_active;
    /* ── New: function-like macros ── */
    struct { char name[128]; char params[8][64]; int n_params; char body[512]; } func_macros[64];
    int n_func_macros;
};

/* ── Forward declarations ────────────────────── */
static void occ_error(OccInterpreter *I, const char *fmt, ...);
static OccValue eval_node(OccInterpreter *I, OccNode *n);
static void exec_node(OccInterpreter *I, OccNode *n);
static int occ_format(OccInterpreter *I, char *buf, int bufsize, const char *fmt, OccValue *args, int nargs);
static OccValue call_user_func(OccInterpreter *I, const char *fname, OccValue *args, int nargs);

/* ── Helpers ─────────────────────────────────── */

static void out_append(OccInterpreter *I, const char *s) {
    int len = (int)strlen(s);
    if (I->out_len + len >= OCC_MAX_OUTPUT - 1) len = OCC_MAX_OUTPUT - 1 - I->out_len;
    if (len > 0) { memcpy(I->output + I->out_len, s, len); I->out_len += len; }
    I->output[I->out_len] = '\0';
}

static void out_appendf(OccInterpreter *I, const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    out_append(I, buf);
}

static void occ_error(OccInterpreter *I, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(I->error, sizeof(I->error), fmt, ap);
    va_end(ap);
    I->has_error = 1;
    longjmp(I->err_jmp, 1);
}

static OccValue make_int(long long v) { OccValue r = {VAL_INT}; r.v.i = v; return r; }
static OccValue make_float(double v) { OccValue r = {VAL_DOUBLE}; r.v.f = v; return r; }
static OccValue make_char(char c) { OccValue r = {VAL_CHAR}; r.v.c = c; return r; }
static OccValue make_void(void) { OccValue r = {VAL_VOID}; r.v.i = 0; return r; }
static OccValue make_string(const char *s) {
    OccValue r = {VAL_STRING};
    r.v.s = strdup(s ? s : "");
    return r;
}

/* ── New: Pointer and function pointer helpers ── */

static OccValue make_ptr(int addr, OccValType pointee, int stride) {
    OccValue r = {VAL_PTR};
    r.v.ptr.addr = addr;
    r.v.ptr.pointee_type = pointee;
    r.v.ptr.stride = stride > 0 ? stride : 1;
    return r;
}

static OccValue make_funcptr(const char *name) {
    OccValue r = {VAL_FUNCPTR};
    r.v.s = strdup(name ? name : "");
    return r;
}

static double val_to_double(OccValue v) {
    switch (v.type) {
        case VAL_INT: return (double)v.v.i;
        case VAL_FLOAT: case VAL_DOUBLE: return v.v.f;
        case VAL_CHAR: return (double)v.v.c;
        case VAL_PTR: return (double)v.v.ptr.addr;
        default: return 0.0;
    }
}
static long long val_to_int(OccValue v) {
    switch (v.type) {
        case VAL_INT: return v.v.i;
        case VAL_FLOAT: case VAL_DOUBLE: return (long long)v.v.f;
        case VAL_CHAR: return (long long)v.v.c;
        case VAL_PTR: return (long long)v.v.ptr.addr;
        default: return 0;
    }
}
static int val_to_bool(OccValue v) {
    switch (v.type) {
        case VAL_INT: return v.v.i != 0;
        case VAL_FLOAT: case VAL_DOUBLE: return v.v.f != 0.0;
        case VAL_CHAR: return v.v.c != 0;
        case VAL_STRING: return v.v.s && v.v.s[0];
        case VAL_PTR: return v.v.ptr.addr != 0;
        case VAL_FUNCPTR: return v.v.s && v.v.s[0];
        default: return 0;
    }
}
static int is_float_type(OccValue v) {
    return v.type == VAL_FLOAT || v.type == VAL_DOUBLE;
}

/* ── New: array_to_cstring helper (for char arrays used as strings) ── */
static void array_to_cstring(OccValue arr, char *buf, int bufsize) {
    buf[0] = '\0';
    if (arr.type == VAL_ARRAY) {
        int len = arr.v.arr.len < bufsize - 1 ? arr.v.arr.len : bufsize - 1;
        for (int i = 0; i < len; i++) {
            char ch = 0;
            if (arr.v.arr.data[i].type == VAL_CHAR) ch = arr.v.arr.data[i].v.c;
            else if (arr.v.arr.data[i].type == VAL_INT) ch = (char)arr.v.arr.data[i].v.i;
            if (ch == '\0') { buf[i] = '\0'; return; }
            buf[i] = ch;
        }
        buf[len] = '\0';
    } else if (arr.type == VAL_STRING && arr.v.s) {
        strncpy(buf, arr.v.s, bufsize - 1);
        buf[bufsize - 1] = '\0';
    }
}

/* ══════════════════════════════════════════════
 *  Virtual Memory System
 * ══════════════════════════════════════════════ */

static void vmem_init(OccInterpreter *I) {
    I->vmem = (OccValue *)calloc(OCC_VMEM_SIZE, sizeof(OccValue));
    I->vmem_size = OCC_VMEM_SIZE;
    I->vmem_used = 1; /* 0 = NULL */
}

static int vmem_alloc(OccInterpreter *I, int n) {
    if (n <= 0) n = 1;
    if (I->vmem_used + n > I->vmem_size) return 0;
    int addr = I->vmem_used;
    I->vmem_used += n;
    return addr;
}

static OccValue *vmem_get(OccInterpreter *I, int addr) {
    if (addr <= 0 || addr >= I->vmem_size) return NULL;
    return &I->vmem[addr];
}

/* ══════════════════════════════════════════════
 *  Scope / Variable Management
 * ══════════════════════════════════════════════ */

static OccScope *scope_create(OccScope *parent) {
    OccScope *s = (OccScope *)calloc(1, sizeof(OccScope));
    s->parent = parent;
    return s;
}
static void scope_destroy(OccScope *s) {
    if (!s) return;
    for (int i = 0; i < s->n_vars; i++) {
        if (s->vars[i].val.type == VAL_STRING && s->vars[i].val.v.s)
            free(s->vars[i].val.v.s);
        if (s->vars[i].val.type == VAL_FUNCPTR && s->vars[i].val.v.s)
            free(s->vars[i].val.v.s);
        if (s->vars[i].val.type == VAL_ARRAY && s->vars[i].val.v.arr.data)
            free(s->vars[i].val.v.arr.data);
    }
    free(s);
}

/* Sync static variables from scope back to statics table before scope destruction */
static void sync_statics(OccInterpreter *I, OccScope *s) {
    for (int si = 0; si < I->n_statics; si++) {
        if (strcmp(I->statics[si].func, I->current_func) == 0) {
            for (int vi = 0; vi < s->n_vars; vi++) {
                if (strcmp(s->vars[vi].name, I->statics[si].var) == 0) {
                    I->statics[si].val = s->vars[vi].val;
                    break;
                }
            }
        }
    }
}

static OccVar *scope_find(OccScope *s, const char *name) {
    while (s) {
        for (int i = 0; i < s->n_vars; i++)
            if (strcmp(s->vars[i].name, name) == 0) return &s->vars[i];
        s = s->parent;
    }
    return NULL;
}

static OccVar *scope_set(OccInterpreter *I, OccScope *s, const char *name, OccValue val) {
    /* search current scope only */
    for (int i = 0; i < s->n_vars; i++) {
        if (strcmp(s->vars[i].name, name) == 0) {
            s->vars[i].val = val;
            return &s->vars[i];
        }
    }
    if (s->n_vars >= OCC_MAX_VARS) occ_error(I, "Too many variables");
    OccVar *v = &s->vars[s->n_vars++];
    strncpy(v->name, name, 255);
    v->val = val;
    v->vmem_addr = 0;
    return v;
}

/* ══════════════════════════════════════════════
 *  Lexer
 * ══════════════════════════════════════════════ */

static int is_ident_start(char c) { return isalpha(c) || c == '_'; }
static int is_ident_char(char c) { return isalnum(c) || c == '_'; }

typedef struct { const char *kw; OccTokenType type; } Keyword;
static const Keyword keywords[] = {
    {"int", TOK_INT}, {"float", TOK_FLOAT}, {"double", TOK_DOUBLE},
    {"char", TOK_CHAR}, {"void", TOK_VOID}, {"long", TOK_LONG},
    {"short", TOK_SHORT}, {"unsigned", TOK_UNSIGNED}, {"signed", TOK_SIGNED},
    {"const", TOK_CONST},
    {"if", TOK_IF}, {"else", TOK_ELSE}, {"for", TOK_FOR},
    {"while", TOK_WHILE}, {"do", TOK_DO},
    {"return", TOK_RETURN}, {"break", TOK_BREAK}, {"continue", TOK_CONTINUE},
    {"switch", TOK_SWITCH}, {"case", TOK_CASE}, {"default", TOK_DEFAULT},
    {"struct", TOK_STRUCT}, {"typedef", TOK_TYPEDEF}, {"sizeof", TOK_SIZEOF}, {"enum", TOK_ENUM},
    {"include", TOK_INCLUDE}, {"define", TOK_DEFINE},
    {"static", TOK_STATIC}, {"union", TOK_UNION}, {"goto", TOK_GOTO},
    /* C11/C23 keywords */
    {"_Static_assert", TOK_STATIC_ASSERT}, {"static_assert", TOK_STATIC_ASSERT},
    {"_Generic", TOK_GENERIC},
    {"_Alignof", TOK_ALIGNOF}, {"alignof", TOK_ALIGNOF},
    {"typeof", TOK_TYPEOF}, {"typeof_unqual", TOK_TYPEOF},
    {"constexpr", TOK_CONSTEXPR},
    {"_Noreturn", TOK_CONST}, /* treat as const */
    {"auto", TOK_AUTO_TYPE},
    {NULL, TOK_EOF}
};

static void tokenize(OccInterpreter *I, const char *src) {
    const char *p = src;
    int line = 1;
    I->n_tokens = 0;

    while (*p && I->n_tokens < OCC_MAX_TOKENS - 1) {
        /* skip whitespace */
        while (*p && (*p == ' ' || *p == '\t' || *p == '\r')) p++;
        if (*p == '\n') { line++; p++; continue; }
        if (!*p) break;

        OccToken *t = &I->tokens[I->n_tokens];
        t->start = p;
        t->line = line;
        t->num_val = 0;

        /* single-line comment */
        if (p[0] == '/' && p[1] == '/') {
            while (*p && *p != '\n') p++;
            continue;
        }
        /* multi-line comment */
        if (p[0] == '/' && p[1] == '*') {
            p += 2;
            while (*p && !(p[0] == '*' && p[1] == '/')) { if (*p == '\n') line++; p++; }
            if (*p) p += 2;
            continue;
        }
        /* preprocessor directives */
        if (*p == '#') {
            p++;
            while (*p == ' ' || *p == '\t') p++;

            /* helper: extract directive name */
            const char *dir_start = p;
            while (isalpha(*p)) p++;
            int dir_len = (int)(p - dir_start);
            while (*p == ' ' || *p == '\t') p++;

            /* #define NAME VALUE or #define NAME(params) body */
            if (dir_len == 6 && strncmp(dir_start, "define", 6) == 0) {
                const char *name_start = p;
                while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '(') p++;
                int name_len = (int)(p - name_start);
                if (*p == '(') {
                    /* Function-like macro */
                    if (I->n_func_macros < 64 && name_len > 0 && name_len < 127) {
                        int fm_idx = I->n_func_macros;
                        memcpy(I->func_macros[fm_idx].name, name_start, name_len);
                        I->func_macros[fm_idx].name[name_len] = '\0';
                        I->func_macros[fm_idx].n_params = 0;
                        p++; /* skip ( */
                        /* parse param names */
                        while (*p && *p != ')' && I->func_macros[fm_idx].n_params < 8) {
                            while (*p == ' ' || *p == '\t') p++;
                            const char *ps = p;
                            while (*p && *p != ',' && *p != ')' && *p != ' ' && *p != '\t') p++;
                            int plen = (int)(p - ps);
                            if (plen > 0 && plen < 63) {
                                memcpy(I->func_macros[fm_idx].params[I->func_macros[fm_idx].n_params], ps, plen);
                                I->func_macros[fm_idx].params[I->func_macros[fm_idx].n_params][plen] = '\0';
                                I->func_macros[fm_idx].n_params++;
                            }
                            while (*p == ' ' || *p == '\t') p++;
                            if (*p == ',') p++;
                        }
                        if (*p == ')') p++;
                        while (*p == ' ' || *p == '\t') p++;
                        /* capture body (rest of line) */
                        const char *bstart = p;
                        while (*p && *p != '\n') p++;
                        int blen = (int)(p - bstart);
                        while (blen > 0 && (bstart[blen-1] == ' ' || bstart[blen-1] == '\t')) blen--;
                        if (blen > 0 && blen < 511) {
                            memcpy(I->func_macros[fm_idx].body, bstart, blen);
                            I->func_macros[fm_idx].body[blen] = '\0';
                        } else {
                            I->func_macros[fm_idx].body[0] = '\0';
                        }
                        I->n_func_macros++;
                    } else {
                        while (*p && *p != '\n') p++;
                    }
                } else {
                    /* Simple object-like macro */
                    while (*p == ' ' || *p == '\t') p++;
                    const char *val_start = p;
                    while (*p && *p != '\n') p++;
                    int val_len = (int)(p - val_start);
                    while (val_len > 0 && (val_start[val_len-1] == ' ' || val_start[val_len-1] == '\t')) val_len--;
                    if (I->n_defines < 256 && name_len > 0 && name_len < 127) {
                        memcpy(I->defines[I->n_defines].name, name_start, name_len);
                        I->defines[I->n_defines].name[name_len] = '\0';
                        if (val_len > 0 && val_len < 255) {
                            memcpy(I->defines[I->n_defines].value, val_start, val_len);
                            I->defines[I->n_defines].value[val_len] = '\0';
                        } else {
                            I->defines[I->n_defines].value[0] = '\0';
                        }
                        I->n_defines++;
                    }
                }
            }
            /* #undef NAME */
            else if (dir_len == 5 && strncmp(dir_start, "undef", 5) == 0) {
                const char *name_start = p;
                while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
                int name_len = (int)(p - name_start);
                char uname[128] = {0};
                if (name_len > 0 && name_len < 127) {
                    memcpy(uname, name_start, name_len);
                    for (int di = 0; di < I->n_defines; di++) {
                        if (strcmp(I->defines[di].name, uname) == 0) {
                            I->defines[di] = I->defines[--I->n_defines];
                            break;
                        }
                    }
                }
            }
            /* #warning MESSAGE — append warning to output */
            else if (dir_len == 7 && strncmp(dir_start, "warning", 7) == 0) {
                const char *msg_start = p;
                while (*p && *p != '\n') p++;
                int msg_len = (int)(p - msg_start);
                /* trim trailing whitespace */
                while (msg_len > 0 && (msg_start[msg_len-1] == ' ' || msg_start[msg_len-1] == '\t')) msg_len--;
                char wbuf[512];
                int wl = msg_len < 500 ? msg_len : 500;
                snprintf(wbuf, sizeof(wbuf), "warning: %.*s\n", wl, msg_start);
                out_append(I, wbuf);
                continue;
            }
            /* #ifdef / #ifndef / #if / #else / #elif / #endif */
            else if ((dir_len == 5 && strncmp(dir_start, "ifdef", 5) == 0) ||
                     (dir_len == 6 && strncmp(dir_start, "ifndef", 6) == 0) ||
                     (dir_len == 2 && strncmp(dir_start, "if", 2) == 0)) {
                int is_ifndef = (dir_len == 6);
                int is_ifdef = (dir_len == 5) || is_ifndef;
                int cond = 0;
                if (is_ifdef) {
                    const char *name_start2 = p;
                    while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
                    int nl = (int)(p - name_start2);
                    char cname[128] = {0};
                    if (nl > 0 && nl < 127) memcpy(cname, name_start2, nl);
                    int defined = 0;
                    for (int di = 0; di < I->n_defines; di++)
                        if (strcmp(I->defines[di].name, cname) == 0) { defined = 1; break; }
                    cond = is_ifndef ? !defined : defined;
                } else {
                    /* #if EXPR — simple: check if first token is nonzero */
                    char *endp;
                    long val = strtol(p, &endp, 0);
                    cond = (endp != p && val != 0);
                }
                while (*p && *p != '\n') p++;
                if (!cond) {
                    /* skip until matching #else/#elif/#endif */
                    int depth = 1;
                    while (*p && depth > 0) {
                        if (*p == '\n') { line++; p++; continue; }
                        if (*p == '#') {
                            const char *dp = p + 1;
                            while (*dp == ' ' || *dp == '\t') dp++;
                            if (strncmp(dp, "ifdef", 5) == 0 || strncmp(dp, "ifndef", 6) == 0
                                || (strncmp(dp, "if", 2) == 0 && !isalpha(dp[2]))) depth++;
                            else if (strncmp(dp, "endif", 5) == 0) { depth--; if (depth == 0) { p = dp + 5; while (*p && *p != '\n') p++; break; } }
                            else if (depth == 1 && strncmp(dp, "else", 4) == 0 && !isalpha(dp[4])) { p = dp + 4; while (*p && *p != '\n') p++; break; }
                            else if (depth == 1 && strncmp(dp, "elif", 4) == 0) { p = dp + 4; while (*p && *p != '\n') p++; break; }
                        }
                        p++;
                    }
                }
                continue;
            }
            else if ((dir_len == 4 && strncmp(dir_start, "else", 4) == 0) ||
                     (dir_len == 4 && strncmp(dir_start, "elif", 4) == 0)) {
                /* We're in the true branch — skip until #endif */
                int depth = 1;
                while (*p && *p != '\n') p++; /* skip rest of this line */
                while (*p && depth > 0) {
                    if (*p == '\n') { line++; p++; continue; }
                    if (*p == '#') {
                        const char *dp = p + 1;
                        while (*dp == ' ' || *dp == '\t') dp++;
                        if (strncmp(dp, "ifdef", 5) == 0 || strncmp(dp, "ifndef", 6) == 0
                            || (strncmp(dp, "if", 2) == 0 && !isalpha(dp[2]))) depth++;
                        else if (strncmp(dp, "endif", 5) == 0) { depth--; if (depth == 0) { p = dp + 5; while (*p && *p != '\n') p++; break; } }
                    }
                    p++;
                }
                continue;
            }
            else if (dir_len == 5 && strncmp(dir_start, "endif", 5) == 0) {
                /* just consume — matching #ifdef was true */
            }
            /* #include, #pragma — skip */
            while (*p && *p != '\n') p++;
            continue;
        }
        /* string literal (with adjacent string concatenation) */
        if (*p == '"') {
            p++;
            t->start = p;
            while (*p && *p != '"') { if (*p == '\\' && p[1]) p++; p++; }
            t->length = (int)(p - t->start);
            t->type = TOK_STRING_LIT;
            if (*p == '"') p++;
            I->n_tokens++;
            continue;
        }
        /* char literal */
        if (*p == '\'') {
            p++;
            t->start = p;
            if (*p == '\\') { p++; }
            p++;
            t->length = (int)(p - t->start);
            t->type = TOK_CHAR_LIT;
            if (*p == '\'') p++;
            I->n_tokens++;
            continue;
        }
        /* number */
        if (isdigit(*p) || (*p == '.' && isdigit(p[1]))) {
            const char *start = p;
            int is_flt = 0;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
                p += 2;
                while (isxdigit(*p) || *p == '\'') p++; /* C23 digit separator */
                /* Parse hex value, skipping digit separators */
                long long hval = 0;
                for (const char *hp = start + 2; hp < p; hp++) {
                    if (*hp == '\'') continue;
                    hval *= 16;
                    if (*hp >= '0' && *hp <= '9') hval += *hp - '0';
                    else if (*hp >= 'a' && *hp <= 'f') hval += *hp - 'a' + 10;
                    else if (*hp >= 'A' && *hp <= 'F') hval += *hp - 'A' + 10;
                }
                t->num_val = (double)hval;
            } else if (p[0] == '0' && (p[1] == 'b' || p[1] == 'B')) {
                /* C23 binary literals: 0b1010 */
                p += 2;
                long long bval = 0;
                while (*p == '0' || *p == '1' || *p == '\'') {
                    if (*p != '\'') { bval = (bval << 1) | (*p - '0'); }
                    p++;
                }
                t->num_val = (double)bval;
            } else {
                while (isdigit(*p) || *p == '\'') p++; /* C23 digit separator */
                if (*p == '.') { is_flt = 1; p++; while (isdigit(*p) || *p == '\'') p++; }
                if (*p == 'e' || *p == 'E') {
                    is_flt = 1; p++;
                    if (*p == '+' || *p == '-') p++;
                    while (isdigit(*p)) p++;
                }
                /* Parse decimal value, skipping digit separators */
                if (!is_flt) {
                    long long dval = 0;
                    for (const char *dp2 = start; dp2 < p; dp2++) {
                        if (*dp2 == '\'') continue;
                        dval = dval * 10 + (*dp2 - '0');
                    }
                    t->num_val = (double)dval;
                } else {
                    t->num_val = strtod(start, NULL);
                }
            }
            /* skip suffixes like L, LL, f, U etc */
            while (*p == 'l' || *p == 'L' || *p == 'f' || *p == 'F' || *p == 'u' || *p == 'U') p++;
            t->length = (int)(p - start);
            t->type = is_flt ? TOK_FLOAT_LIT : TOK_INT_LIT;
            I->n_tokens++;
            continue;
        }
        /* identifier / keyword / function-like macro expansion */
        if (is_ident_start(*p)) {
            const char *start = p;
            while (is_ident_char(*p)) p++;
            int ilen = (int)(p - start);
            t->length = ilen;
            t->type = TOK_IDENT;
            /* Check keywords */
            for (const Keyword *kw = keywords; kw->kw; kw++) {
                if ((int)strlen(kw->kw) == ilen && strncmp(start, kw->kw, ilen) == 0) {
                    t->type = kw->type;
                    break;
                }
            }
            /* Check function-like macro expansion */
            if (t->type == TOK_IDENT) {
                char id_name[128] = {0};
                int nlen = ilen < 127 ? ilen : 127;
                memcpy(id_name, start, nlen);
                /* Check for function-like macro */
                const char *after_ident = p;
                while (*after_ident == ' ' || *after_ident == '\t') after_ident++;
                if (*after_ident == '(') {
                    int fm_idx = -1;
                    for (int mi = 0; mi < I->n_func_macros; mi++) {
                        if (strcmp(I->func_macros[mi].name, id_name) == 0) { fm_idx = mi; break; }
                    }
                    if (fm_idx >= 0) {
                        /* Extract arguments */
                        p = after_ident + 1; /* skip ( */
                        char macro_args[8][256];
                        int n_margs = 0;
                        int depth = 1;
                        const char *arg_start = p;
                        while (*p && depth > 0 && n_margs < 8) {
                            if (*p == '(') depth++;
                            else if (*p == ')') { depth--; if (depth == 0) break; }
                            else if (*p == ',' && depth == 1) {
                                int alen = (int)(p - arg_start);
                                if (alen > 255) alen = 255;
                                while (alen > 0 && (arg_start[0] == ' ' || arg_start[0] == '\t')) { arg_start++; alen--; }
                                while (alen > 0 && (arg_start[alen-1] == ' ' || arg_start[alen-1] == '\t')) alen--;
                                memcpy(macro_args[n_margs], arg_start, alen);
                                macro_args[n_margs][alen] = '\0';
                                n_margs++;
                                arg_start = p + 1;
                            }
                            p++;
                        }
                        /* last arg */
                        if (depth == 0 && n_margs < 8) {
                            int alen = (int)(p - arg_start);
                            if (alen > 255) alen = 255;
                            while (alen > 0 && (arg_start[0] == ' ' || arg_start[0] == '\t')) { arg_start++; alen--; }
                            while (alen > 0 && (arg_start[alen-1] == ' ' || arg_start[alen-1] == '\t')) alen--;
                            if (alen > 0) {
                                memcpy(macro_args[n_margs], arg_start, alen);
                                macro_args[n_margs][alen] = '\0';
                                n_margs++;
                            }
                        }
                        if (*p == ')') p++;
                        /* Substitute params in body */
                        /* Heap-allocate so token pointers remain valid after tokenize returns */
                        char *expanded = (char *)calloc(1, 1024);
                        const char *bp = I->func_macros[fm_idx].body;
                        int ei = 0;
                        while (*bp && ei < 1020) {
                            if (is_ident_start(*bp)) {
                                const char *ws = bp;
                                while (is_ident_char(*bp)) bp++;
                                int wlen = (int)(bp - ws);
                                int replaced = 0;
                                for (int pi = 0; pi < I->func_macros[fm_idx].n_params && pi < n_margs; pi++) {
                                    if ((int)strlen(I->func_macros[fm_idx].params[pi]) == wlen &&
                                        strncmp(ws, I->func_macros[fm_idx].params[pi], wlen) == 0) {
                                        int al = (int)strlen(macro_args[pi]);
                                        if (ei + al < 1020) {
                                            memcpy(expanded + ei, macro_args[pi], al);
                                            ei += al;
                                        }
                                        replaced = 1;
                                        break;
                                    }
                                }
                                if (!replaced) {
                                    if (ei + wlen < 1020) { memcpy(expanded + ei, ws, wlen); ei += wlen; }
                                }
                            } else {
                                expanded[ei++] = *bp++;
                            }
                        }
                        expanded[ei] = '\0';
                        /* Now tokenize the expanded text and splice tokens into stream */
                        /* We'll store the expanded text in a static buffer and point tokens at it */
                        /* Simple approach: use the defines system to register as a simple define
                           and re-tokenize as inline text. For now, just tokenize into remaining space. */
                        /* Tokenize expanded text directly into token stream */
                        const char *ep = expanded;
                        /* Remove the ident token we started (don't increment n_tokens) */
                        while (*ep) {
                            while (*ep == ' ' || *ep == '\t') ep++;
                            if (!*ep) break;
                            OccToken *et = &I->tokens[I->n_tokens];
                            et->line = line;
                            et->num_val = 0;
                            et->start = ep;
                            if (isdigit(*ep) || (*ep == '.' && isdigit(ep[1]))) {
                                const char *ns = ep;
                                int is_ef = 0;
                                if (ep[0] == '0' && (ep[1] == 'x' || ep[1] == 'X')) {
                                    ep += 2; while (isxdigit(*ep)) ep++;
                                    et->num_val = (double)strtoll(ns, NULL, 16);
                                } else {
                                    while (isdigit(*ep)) ep++;
                                    if (*ep == '.') { is_ef = 1; ep++; while (isdigit(*ep)) ep++; }
                                    if (*ep == 'e' || *ep == 'E') { is_ef = 1; ep++; if (*ep == '+' || *ep == '-') ep++; while (isdigit(*ep)) ep++; }
                                    et->num_val = strtod(ns, NULL);
                                }
                                while (*ep == 'l' || *ep == 'L' || *ep == 'f' || *ep == 'F') ep++;
                                et->length = (int)(ep - ns);
                                et->type = is_ef ? TOK_FLOAT_LIT : TOK_INT_LIT;
                                if (I->n_tokens < OCC_MAX_TOKENS - 1) I->n_tokens++;
                            } else if (is_ident_start(*ep)) {
                                const char *ids = ep;
                                while (is_ident_char(*ep)) ep++;
                                et->length = (int)(ep - ids);
                                et->type = TOK_IDENT;
                                for (const Keyword *kw2 = keywords; kw2->kw; kw2++) {
                                    if ((int)strlen(kw2->kw) == et->length && strncmp(ids, kw2->kw, et->length) == 0) {
                                        et->type = kw2->type; break;
                                    }
                                }
                                if (I->n_tokens < OCC_MAX_TOKENS - 1) I->n_tokens++;
                            } else {
                                /* operator/punct — single char for simplicity */
                                et->length = 1;
                                switch (*ep) {
                                    case '+': et->type = TOK_PLUS; break;
                                    case '-': et->type = TOK_MINUS; break;
                                    case '*': et->type = TOK_STAR; break;
                                    case '/': et->type = TOK_SLASH; break;
                                    case '%': et->type = TOK_PERCENT; break;
                                    case '(': et->type = TOK_LPAREN; break;
                                    case ')': et->type = TOK_RPAREN; break;
                                    case ',': et->type = TOK_COMMA; break;
                                    case '<': et->type = TOK_LT; break;
                                    case '>': et->type = TOK_GT; break;
                                    case '=': et->type = TOK_ASSIGN; break;
                                    case '!': et->type = TOK_BANG; break;
                                    case '&': et->type = TOK_AMP; break;
                                    case '|': et->type = TOK_PIPE; break;
                                    case '^': et->type = TOK_CARET; break;
                                    case '~': et->type = TOK_TILDE; break;
                                    case '?': et->type = TOK_QUESTION; break;
                                    case ':': et->type = TOK_COLON; break;
                                    case ';': et->type = TOK_SEMICOLON; break;
                                    case '.': et->type = TOK_DOT; break;
                                    case '[': et->type = TOK_LBRACKET; break;
                                    case ']': et->type = TOK_RBRACKET; break;
                                    case '{': et->type = TOK_LBRACE; break;
                                    case '}': et->type = TOK_RBRACE; break;
                                    default: ep++; continue; /* skip unknown */
                                }
                                ep++;
                                if (I->n_tokens < OCC_MAX_TOKENS - 1) I->n_tokens++;
                            }
                        }
                        continue; /* skip normal ident addition */
                    }
                }
            }
            I->n_tokens++;
            continue;
        }
        /* C23 attribute syntax: [[...]] — skip entirely */
        if (p[0] == '[' && p[1] == '[') {
            p += 2;
            int attr_depth = 1;
            while (*p && attr_depth > 0) {
                if (p[0] == '[' && p[1] == '[') { attr_depth++; p += 2; continue; }
                if (p[0] == ']' && p[1] == ']') { attr_depth--; p += 2; continue; }
                if (*p == '\n') line++;
                p++;
            }
            continue;
        }

        /* operators and punctuation */
        #define TOK2(c1,c2,tok) if(p[0]==c1&&p[1]==c2){t->type=tok;t->length=2;p+=2;I->n_tokens++;continue;}
        #define TOK1(c,tok) if(p[0]==c){t->type=tok;t->length=1;p++;I->n_tokens++;continue;}

        /* 3-char tokens first */
        if (p[0]=='<'&&p[1]=='<'&&p[2]=='='){t->type=TOK_LSHIFT_ASSIGN;t->length=3;p+=3;I->n_tokens++;continue;}
        if (p[0]=='>'&&p[1]=='>'&&p[2]=='='){t->type=TOK_RSHIFT_ASSIGN;t->length=3;p+=3;I->n_tokens++;continue;}

        TOK2('+','+',TOK_INC) TOK2('-','-',TOK_DEC)
        TOK2('+','=',TOK_PLUS_ASSIGN) TOK2('-','=',TOK_MINUS_ASSIGN)
        TOK2('*','=',TOK_STAR_ASSIGN) TOK2('/','=',TOK_SLASH_ASSIGN)
        TOK2('%','=',TOK_PERCENT_ASSIGN)
        TOK2('&','=',TOK_AMP_ASSIGN) TOK2('|','=',TOK_PIPE_ASSIGN)
        TOK2('^','=',TOK_CARET_ASSIGN)
        TOK2('=','=',TOK_EQ) TOK2('!','=',TOK_NEQ)
        TOK2('<','=',TOK_LE) TOK2('>','=',TOK_GE)
        TOK2('<','<',TOK_LSHIFT) TOK2('>','>',TOK_RSHIFT)
        TOK2('&','&',TOK_AND) TOK2('|','|',TOK_OR)
        TOK2('-','>',TOK_ARROW)

        TOK1('+',TOK_PLUS) TOK1('-',TOK_MINUS) TOK1('*',TOK_STAR)
        TOK1('/',TOK_SLASH) TOK1('%',TOK_PERCENT)
        TOK1('&',TOK_AMP) TOK1('|',TOK_PIPE) TOK1('^',TOK_CARET)
        TOK1('~',TOK_TILDE) TOK1('!',TOK_BANG)
        TOK1('=',TOK_ASSIGN)
        TOK1('<',TOK_LT) TOK1('>',TOK_GT)
        TOK1('(',TOK_LPAREN) TOK1(')',TOK_RPAREN)
        TOK1('{',TOK_LBRACE) TOK1('}',TOK_RBRACE)
        TOK1('[',TOK_LBRACKET) TOK1(']',TOK_RBRACKET)
        TOK1(';',TOK_SEMICOLON) TOK1(',',TOK_COMMA)
        TOK1('.',TOK_DOT) TOK1(':',TOK_COLON) TOK1('?',TOK_QUESTION)
        TOK1('#',TOK_HASH)

        #undef TOK1
        #undef TOK2

        /* unknown char — skip */
        p++;
    }
    /* add EOF */
    I->tokens[I->n_tokens].type = TOK_EOF;
    I->tokens[I->n_tokens].line = line;
    I->tokens[I->n_tokens].start = p;
    I->tokens[I->n_tokens].length = 0;
}

/* ── Parser helpers ───────────────────────────── */

static OccToken *peek(OccInterpreter *I) { return &I->tokens[I->tok_pos]; }
static OccToken *advance(OccInterpreter *I) { return &I->tokens[I->tok_pos++]; }
static int check(OccInterpreter *I, OccTokenType t) { return peek(I)->type == t; }
static int match(OccInterpreter *I, OccTokenType t) {
    if (peek(I)->type == t) { I->tok_pos++; return 1; }
    return 0;
}
static void expect(OccInterpreter *I, OccTokenType t, const char *msg) {
    if (!match(I, t)) occ_error(I, "Line %d: Expected %s", peek(I)->line, msg);
}

static char *tok_str(OccToken *t) {
    static char buf[512];
    int len = t->length < 511 ? t->length : 511;
    memcpy(buf, t->start, len);
    buf[len] = '\0';
    return buf;
}

/* ══════════════════════════════════════════════
 *  AST Node allocation
 * ══════════════════════════════════════════════ */

static OccNode *new_node(OccNodeType type, int line) {
    OccNode *n = (OccNode *)calloc(1, sizeof(OccNode));
    n->type = type;
    n->line = line;
    return n;
}
static void add_stmt(OccNode *block, OccNode *stmt) {
    block->stmts = (OccNode **)realloc(block->stmts, sizeof(OccNode *) * (block->n_stmts + 1));
    block->stmts[block->n_stmts++] = stmt;
}
static void add_child(OccNode *parent, OccNode *child) {
    if (parent->n_children < 8) parent->children[parent->n_children++] = child;
}

/* ══════════════════════════════════════════════
 *  Parser (recursive descent)
 * ══════════════════════════════════════════════ */

static OccNode *parse_expr(OccInterpreter *I);
static OccNode *parse_assign(OccInterpreter *I);
static OccNode *parse_postfix(OccInterpreter *I);
static OccNode *parse_stmt(OccInterpreter *I);
static OccNode *parse_block(OccInterpreter *I);

static int is_type_token(OccTokenType t) {
    return t == TOK_INT || t == TOK_FLOAT || t == TOK_DOUBLE || t == TOK_CHAR
        || t == TOK_VOID || t == TOK_LONG || t == TOK_SHORT
        || t == TOK_UNSIGNED || t == TOK_SIGNED || t == TOK_CONST
        || t == TOK_STRUCT || t == TOK_ENUM || t == TOK_UNION
        || t == TOK_STATIC || t == TOK_AUTO_TYPE || t == TOK_TYPEOF
        || t == TOK_CONSTEXPR;
}

/* Special marker for C23 auto type deduction */
#define VAL_AUTO_MARKER ((OccValType)99)

static OccValType parse_type(OccInterpreter *I) {
    OccValType vt = VAL_INT;
    int had_modifier = 0;
    /* skip const, constexpr, unsigned, signed, long, short, struct, static, union */
    while (check(I, TOK_CONST) || check(I, TOK_CONSTEXPR) || check(I, TOK_UNSIGNED) || check(I, TOK_SIGNED)
           || check(I, TOK_LONG) || check(I, TOK_SHORT) || check(I, TOK_STRUCT)
           || check(I, TOK_STATIC) || check(I, TOK_UNION)) {
        if (check(I, TOK_LONG) || check(I, TOK_SHORT) || check(I, TOK_UNSIGNED) || check(I, TOK_SIGNED))
            had_modifier = 1;
        if (check(I, TOK_STATIC)) { advance(I); continue; } /* consume static but don't set modifier */
        if (check(I, TOK_CONSTEXPR)) { advance(I); continue; } /* C23 constexpr — treat like const */
        advance(I);
    }
    /* C23 auto type deduction */
    if (match(I, TOK_AUTO_TYPE)) {
        return VAL_AUTO_MARKER;
    }
    /* C11/C23 typeof(expr) */
    if (match(I, TOK_TYPEOF)) {
        expect(I, TOK_LPAREN, "(");
        OccNode *texpr = parse_expr(I);
        expect(I, TOK_RPAREN, ")");
        /* Evaluate expression to determine type */
        OccValue tv = eval_node(I, texpr);
        return tv.type;
    }
    if (match(I, TOK_INT)) vt = VAL_INT;
    else if (match(I, TOK_FLOAT)) vt = VAL_FLOAT;
    else if (match(I, TOK_DOUBLE)) vt = VAL_DOUBLE;
    else if (match(I, TOK_CHAR)) vt = VAL_CHAR;
    else if (match(I, TOK_VOID)) vt = VAL_VOID;
    else if (!had_modifier && check(I, TOK_IDENT)) {
        advance(I);
        vt = VAL_INT;
    }
    /* skip trailing long/short/etc */
    while (check(I, TOK_LONG) || check(I, TOK_SHORT)) advance(I);
    return vt;
}

/* ── Expression parsing (precedence climbing) ── */

static OccNode *parse_primary(OccInterpreter *I) {
    int line = peek(I)->line;

    if (check(I, TOK_INT_LIT) || check(I, TOK_FLOAT_LIT)) {
        OccToken *t = advance(I);
        OccNode *n = new_node(t->type == TOK_INT_LIT ? ND_INT_LIT : ND_FLOAT_LIT, line);
        n->num_val = t->num_val;
        return n;
    }
    if (check(I, TOK_STRING_LIT)) {
        OccToken *t = advance(I);
        OccNode *n = new_node(ND_STRING_LIT, line);
        /* unescape */
        int j = 0;
        for (int i = 0; i < t->length && j < OCC_MAX_STRLEN - 1; i++) {
            if (t->start[i] == '\\' && i + 1 < t->length) {
                i++;
                switch (t->start[i]) {
                    case 'n': n->str_val[j++] = '\n'; break;
                    case 't': n->str_val[j++] = '\t'; break;
                    case '\\': n->str_val[j++] = '\\'; break;
                    case '"': n->str_val[j++] = '"'; break;
                    case '0': n->str_val[j++] = '\0'; break;
                    default: n->str_val[j++] = t->start[i]; break;
                }
            } else {
                n->str_val[j++] = t->start[i];
            }
        }
        n->str_val[j] = '\0';
        return n;
    }
    if (check(I, TOK_CHAR_LIT)) {
        OccToken *t = advance(I);
        OccNode *n = new_node(ND_CHAR_LIT, line);
        if (t->start[0] == '\\') {
            switch (t->start[1]) {
                case 'n': n->num_val = '\n'; break;
                case 't': n->num_val = '\t'; break;
                case '0': n->num_val = '\0'; break;
                case '\\': n->num_val = '\\'; break;
                case '\'': n->num_val = '\''; break;
                default: n->num_val = t->start[1]; break;
            }
        } else {
            n->num_val = t->start[0];
        }
        return n;
    }
    if (check(I, TOK_SIZEOF)) {
        advance(I);
        OccNode *n = new_node(ND_SIZEOF, line);
        expect(I, TOK_LPAREN, "(");
        if (is_type_token(peek(I)->type)) {
            OccValType vt = parse_type(I);
            while (match(I, TOK_STAR)) {} /* skip pointer stars */
            n->val_type = vt;
        } else {
            add_child(n, parse_expr(I));
        }
        expect(I, TOK_RPAREN, ")");
        return n;
    }
    /* C11 _Alignof(type) / C23 alignof(type) */
    if (check(I, TOK_ALIGNOF)) {
        advance(I);
        expect(I, TOK_LPAREN, "(");
        OccValType avt = VAL_INT;
        if (is_type_token(peek(I)->type)) {
            avt = parse_type(I);
            while (match(I, TOK_STAR)) { avt = VAL_PTR; }
        }
        expect(I, TOK_RPAREN, ")");
        /* Return alignment based on type */
        OccNode *n = new_node(ND_INT_LIT, line);
        switch (avt) {
            case VAL_CHAR: n->num_val = 1; break;
            case VAL_INT: n->num_val = 4; break;
            case VAL_FLOAT: n->num_val = 4; break;
            case VAL_DOUBLE: n->num_val = 8; break;
            case VAL_PTR: n->num_val = 8; break;
            default: n->num_val = 8; break;
        }
        return n;
    }
    /* C11 _Generic(expr, type: expr, ..., default: expr) */
    if (check(I, TOK_GENERIC)) {
        advance(I);
        OccNode *n = new_node(ND_GENERIC, line);
        expect(I, TOK_LPAREN, "(");
        /* controlling expression */
        add_child(n, parse_assign(I));
        /* parse type: expr associations */
        while (match(I, TOK_COMMA)) {
            if (check(I, TOK_DEFAULT)) {
                /* default: expr */
                advance(I); /* consume 'default' */
                expect(I, TOK_COLON, ":");
                OccNode *assoc = new_node(ND_DEFAULT, line);
                add_child(assoc, parse_assign(I));
                add_stmt(n, assoc);
            } else {
                /* type: expr */
                OccNode *assoc = new_node(ND_CASE, line);
                OccValType avt2 = parse_type(I);
                while (match(I, TOK_STAR)) { avt2 = VAL_PTR; }
                assoc->val_type = avt2;
                expect(I, TOK_COLON, ":");
                add_child(assoc, parse_assign(I));
                add_stmt(n, assoc);
            }
        }
        expect(I, TOK_RPAREN, ")");
        return n;
    }
    if (check(I, TOK_IDENT)) {
        OccToken *t = advance(I);
        OccNode *n = new_node(ND_IDENT, line);
        strncpy(n->name, t->start, t->length < 255 ? t->length : 255);
        n->name[t->length < 255 ? t->length : 255] = '\0';
        return n;
    }
    if (match(I, TOK_LPAREN)) {
        /* check for cast: (int)expr, (double)expr, etc */
        if (is_type_token(peek(I)->type)) {
            int saved = I->tok_pos;
            OccValType vt = parse_type(I);
            while (match(I, TOK_STAR)) {}
            if (check(I, TOK_RPAREN)) {
                advance(I); /* consume ) */
                /* Compound literal: (type){...} */
                if (check(I, TOK_LBRACE)) {
                    OccNode *cl = new_node(ND_COMPOUND_LITERAL, line);
                    cl->val_type = vt;
                    /* For struct compound literals, we need the struct name.
                       parse_type consumed 'struct' + 'Name' — find the name we consumed */
                    {
                        int tp = saved;
                        while (tp < I->tok_pos) {
                            if (I->tokens[tp].type == TOK_STRUCT && tp + 1 < I->tok_pos && I->tokens[tp+1].type == TOK_IDENT) {
                                OccToken *snt = &I->tokens[tp+1];
                                int snl = snt->length < (OCC_MAX_STRLEN-1) ? snt->length : (OCC_MAX_STRLEN-1);
                                memcpy(cl->str_val, snt->start, snl);
                                cl->str_val[snl] = '\0';
                                cl->val_type = VAL_STRUCT;
                                break;
                            }
                            tp++;
                        }
                    }
                    advance(I); /* { */
                    OccNode *init = new_node(ND_ARRAY_INIT, line);
                    if (!check(I, TOK_RBRACE)) {
                        add_stmt(init, parse_assign(I));
                        while (match(I, TOK_COMMA)) {
                            if (check(I, TOK_RBRACE)) break;
                            add_stmt(init, parse_assign(I));
                        }
                    }
                    expect(I, TOK_RBRACE, "}");
                    add_child(cl, init);
                    return cl;
                }
                /* Normal cast */
                OccNode *n = new_node(ND_CAST, line);
                n->val_type = vt;
                add_child(n, parse_postfix(I));
                return n;
            } else {
                /* Not a cast — backtrack */
                I->tok_pos = saved;
            }
        }
        OccNode *n = parse_expr(I);
        expect(I, TOK_RPAREN, ")");
        return n;
    }

    occ_error(I, "Line %d: Unexpected token '%s'", line, tok_str(peek(I)));
    return new_node(ND_INT_LIT, line); /* unreachable */
}

static OccNode *parse_postfix(OccInterpreter *I) {
    OccNode *n = parse_primary(I);
    int line = peek(I)->line;

    for (;;) {
        if (match(I, TOK_LPAREN)) {
            /* function call */
            OccNode *call = new_node(ND_CALL, line);
            add_child(call, n);
            OccNode *args = new_node(ND_BLOCK, line);
            if (!check(I, TOK_RPAREN)) {
                add_stmt(args, parse_assign(I));
                while (match(I, TOK_COMMA))
                    add_stmt(args, parse_assign(I));
            }
            expect(I, TOK_RPAREN, ")");
            add_child(call, args);
            n = call;
        } else if (match(I, TOK_LBRACKET)) {
            OccNode *idx = new_node(ND_INDEX, line);
            add_child(idx, n);
            add_child(idx, parse_expr(I));
            expect(I, TOK_RBRACKET, "]");
            n = idx;
        } else if (match(I, TOK_DOT)) {
            OccNode *mem = new_node(ND_MEMBER, line);
            add_child(mem, n);
            OccToken *t = advance(I);
            strncpy(mem->name, t->start, t->length < 255 ? t->length : 255);
            n = mem;
        } else if (match(I, TOK_ARROW)) {
            OccNode *mem = new_node(ND_ARROW, line);
            add_child(mem, n);
            OccToken *t = advance(I);
            strncpy(mem->name, t->start, t->length < 255 ? t->length : 255);
            n = mem;
        } else if (match(I, TOK_INC)) {
            OccNode *inc = new_node(ND_POST_INC, line);
            add_child(inc, n);
            n = inc;
        } else if (match(I, TOK_DEC)) {
            OccNode *dec = new_node(ND_POST_DEC, line);
            add_child(dec, n);
            n = dec;
        } else break;
    }
    return n;
}

static OccNode *parse_unary(OccInterpreter *I) {
    int line = peek(I)->line;
    if (match(I, TOK_MINUS)) {
        OccNode *n = new_node(ND_NEG, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_BANG)) {
        OccNode *n = new_node(ND_NOT, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_TILDE)) {
        OccNode *n = new_node(ND_BIT_NOT, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_INC)) {
        OccNode *n = new_node(ND_PRE_INC, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_DEC)) {
        OccNode *n = new_node(ND_PRE_DEC, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_STAR)) {
        OccNode *n = new_node(ND_DEREF, line);
        add_child(n, parse_unary(I));
        return n;
    }
    if (match(I, TOK_AMP)) {
        OccNode *n = new_node(ND_ADDR, line);
        add_child(n, parse_unary(I));
        return n;
    }
    /* cast: handled in parse_primary */
    return parse_postfix(I);
}

/* Binary expression parsing with precedence */
#define PARSE_BINARY(fname, next, ...) \
static OccNode *fname(OccInterpreter *I) { \
    OccNode *left = next(I); \
    for (;;) { \
        int line = peek(I)->line; \
        OccNodeType nt = 0; \
        __VA_ARGS__ \
        if (!nt) break; \
        advance(I); \
        OccNode *n = new_node(nt, line); \
        add_child(n, left); \
        add_child(n, next(I)); \
        left = n; \
    } \
    return left; \
}

PARSE_BINARY(parse_mul, parse_unary,
    if (check(I,TOK_STAR)) nt=ND_MUL;
    else if (check(I,TOK_SLASH)) nt=ND_DIV;
    else if (check(I,TOK_PERCENT)) nt=ND_MOD;
)
PARSE_BINARY(parse_add, parse_mul,
    if (check(I,TOK_PLUS)) nt=ND_ADD;
    else if (check(I,TOK_MINUS)) nt=ND_SUB;
)
PARSE_BINARY(parse_shift, parse_add,
    if (check(I,TOK_LSHIFT)) nt=ND_LSHIFT;
    else if (check(I,TOK_RSHIFT)) nt=ND_RSHIFT;
)
PARSE_BINARY(parse_rel, parse_shift,
    if (check(I,TOK_LT)) nt=ND_LT;
    else if (check(I,TOK_GT)) nt=ND_GT;
    else if (check(I,TOK_LE)) nt=ND_LE;
    else if (check(I,TOK_GE)) nt=ND_GE;
)
PARSE_BINARY(parse_eq, parse_rel,
    if (check(I,TOK_EQ)) nt=ND_EQ;
    else if (check(I,TOK_NEQ)) nt=ND_NEQ;
)
PARSE_BINARY(parse_bit_and, parse_eq, if (check(I,TOK_AMP) && !check(I,TOK_AND)) nt=ND_BIT_AND;)
PARSE_BINARY(parse_bit_xor, parse_bit_and, if (check(I,TOK_CARET)) nt=ND_BIT_XOR;)
PARSE_BINARY(parse_bit_or, parse_bit_xor, if (check(I,TOK_PIPE) && !check(I,TOK_OR)) nt=ND_BIT_OR;)
PARSE_BINARY(parse_log_and, parse_bit_or, if (check(I,TOK_AND)) nt=ND_AND;)
PARSE_BINARY(parse_log_or, parse_log_and, if (check(I,TOK_OR)) nt=ND_OR;)

static OccNode *parse_ternary(OccInterpreter *I) {
    OccNode *cond = parse_log_or(I);
    if (match(I, TOK_QUESTION)) {
        int line = peek(I)->line;
        OccNode *n = new_node(ND_TERNARY, line);
        add_child(n, cond);
        add_child(n, parse_expr(I));
        expect(I, TOK_COLON, ":");
        add_child(n, parse_ternary(I));
        return n;
    }
    return cond;
}

static OccNode *parse_assign(OccInterpreter *I) {
    OccNode *left = parse_ternary(I);
    int line = peek(I)->line;
    if (match(I, TOK_ASSIGN)) {
        OccNode *n = new_node(ND_ASSIGN, line);
        add_child(n, left);
        add_child(n, parse_assign(I));
        return n;
    }
    OccTokenType compound[] = {TOK_PLUS_ASSIGN, TOK_MINUS_ASSIGN, TOK_STAR_ASSIGN, TOK_SLASH_ASSIGN, TOK_PERCENT_ASSIGN,
                               TOK_AMP_ASSIGN, TOK_PIPE_ASSIGN, TOK_CARET_ASSIGN, TOK_LSHIFT_ASSIGN, TOK_RSHIFT_ASSIGN};
    OccNodeType ops[] = {ND_ADD, ND_SUB, ND_MUL, ND_DIV, ND_MOD,
                         ND_BIT_AND, ND_BIT_OR, ND_BIT_XOR, ND_LSHIFT, ND_RSHIFT};
    for (int i = 0; i < 10; i++) {
        if (match(I, compound[i])) {
            OccNode *n = new_node(ND_COMPOUND_ASSIGN, line);
            n->op = ops[i];
            add_child(n, left);
            add_child(n, parse_assign(I));
            return n;
        }
    }
    return left;
}

static OccNode *parse_expr(OccInterpreter *I) {
    OccNode *n = parse_assign(I);
    while (match(I, TOK_COMMA)) {
        OccNode *comma = new_node(ND_COMMA, peek(I)->line);
        add_child(comma, n);
        add_child(comma, parse_assign(I));
        n = comma;
    }
    return n;
}

/* ── Statement parsing ────────────────────────── */

static OccNode *parse_vardecl(OccInterpreter *I, OccValType vt) {
    int line = peek(I)->line;
    int is_ptr = 0;
    while (match(I, TOK_STAR)) is_ptr++;

    OccToken *name = advance(I);
    OccNode *decl = new_node(ND_VARDECL, line);
    strncpy(decl->name, name->start, name->length < 255 ? name->length : 255);
    decl->name[name->length < 255 ? name->length : 255] = '\0';
    decl->val_type = is_ptr ? VAL_PTR : vt;

    /* array declaration: int x[10]; or int x[3][4]; or int x[] = {1,2,3}; */
    if (match(I, TOK_LBRACKET)) {
        decl->is_array = 1;
        int total_size = 1;
        int dim_count = 0;
        int dim_sizes[4] = {0, 0, 0, 0};
        if (!check(I, TOK_RBRACKET)) {
            OccNode *sz = parse_expr(I);
            int dim = (int)sz->num_val;
            if (dim > 0) { total_size *= dim; if (dim_count < 4) dim_sizes[dim_count] = dim; }
            dim_count++;
        }
        expect(I, TOK_RBRACKET, "]");
        /* Multi-dimensional arrays */
        while (match(I, TOK_LBRACKET)) {
            if (!check(I, TOK_RBRACKET)) {
                OccNode *sz = parse_expr(I);
                int dim = (int)sz->num_val;
                if (dim > 0) { total_size *= dim; if (dim_count < 4) dim_sizes[dim_count] = dim; }
                dim_count++;
            }
            expect(I, TOK_RBRACKET, "]");
        }
        decl->array_size = total_size > 0 ? total_size : 0;
        /* Store dimension info for multi-dim indexing */
        decl->num_val = dim_count; /* repurpose num_val for n_dims */
        for (int d = 0; d < 4; d++) decl->str_val[d] = (char)dim_sizes[d]; /* hack: store dims in str_val bytes */
    }
    /* initializer */
    if (match(I, TOK_ASSIGN)) {
        if (match(I, TOK_LBRACE)) {
            /* array/struct init: {1,2,3} or nested {{1,2},{3,4}} */
            OccNode *init = new_node(ND_ARRAY_INIT, line);
            if (!check(I, TOK_RBRACE)) {
                if (check(I, TOK_LBRACE)) {
                    /* nested brace init: {{1,2}, {3,4}} */
                    while (check(I, TOK_LBRACE)) {
                        advance(I); /* { */
                        while (!check(I, TOK_RBRACE) && !check(I, TOK_EOF)) {
                            add_stmt(init, parse_assign(I));
                            if (!match(I, TOK_COMMA)) break;
                        }
                        expect(I, TOK_RBRACE, "}");
                        if (!match(I, TOK_COMMA)) break;
                    }
                } else {
                    add_stmt(init, parse_assign(I));
                    while (match(I, TOK_COMMA)) {
                        if (check(I, TOK_RBRACE)) break;
                        add_stmt(init, parse_assign(I));
                    }
                }
            }
            expect(I, TOK_RBRACE, "}");
            add_child(decl, init);
        } else {
            add_child(decl, parse_assign(I));
        }
    }
    return decl;
}

static OccNode *parse_block(OccInterpreter *I) {
    OccNode *block = new_node(ND_BLOCK, peek(I)->line);
    expect(I, TOK_LBRACE, "{");
    while (!check(I, TOK_RBRACE) && !check(I, TOK_EOF)) {
        add_stmt(block, parse_stmt(I));
    }
    expect(I, TOK_RBRACE, "}");
    return block;
}

/* Helper to parse struct/union body definition */
static void parse_struct_union_body(OccInterpreter *I, int st_idx) {
    advance(I); /* { */
    I->struct_types[st_idx].n_fields = 0;
    while (!check(I, TOK_RBRACE) && !check(I, TOK_EOF)) {
        if (is_type_token(peek(I)->type) || check(I, TOK_STRUCT) || check(I, TOK_UNION)) {
            OccValType ft;
            if (check(I, TOK_STRUCT) || check(I, TOK_UNION)) {
                advance(I);
                if (check(I, TOK_IDENT)) advance(I);
                ft = VAL_STRUCT;
            } else {
                ft = parse_type(I);
            }
            while (match(I, TOK_STAR)) ft = VAL_PTR;
            if (check(I, TOK_IDENT)) {
                OccToken *fn_tok = advance(I);
                int fi = I->struct_types[st_idx].n_fields;
                if (fi < 32) {
                    int fl = fn_tok->length < 63 ? fn_tok->length : 63;
                    memcpy(I->struct_types[st_idx].field_names[fi], fn_tok->start, fl);
                    I->struct_types[st_idx].field_names[fi][fl] = '\0';
                    I->struct_types[st_idx].field_types[fi] = ft;
                    I->struct_types[st_idx].field_array_sizes[fi] = 0;
                    /* arrays in structs */
                    if (match(I, TOK_LBRACKET)) {
                        if (!check(I, TOK_RBRACKET)) {
                            OccNode *sz = parse_expr(I);
                            I->struct_types[st_idx].field_array_sizes[fi] = (int)sz->num_val;
                        }
                        expect(I, TOK_RBRACKET, "]");
                    }
                    I->struct_types[st_idx].n_fields++;
                }
            }
            expect(I, TOK_SEMICOLON, ";");
        } else {
            advance(I); /* skip unknown */
        }
    }
    expect(I, TOK_RBRACE, "}");
}

static OccNode *parse_stmt(OccInterpreter *I) {
    int line = peek(I)->line;

    /* block */
    if (check(I, TOK_LBRACE)) return parse_block(I);

    /* if */
    if (match(I, TOK_IF)) {
        OccNode *n = new_node(ND_IF, line);
        expect(I, TOK_LPAREN, "(");
        add_child(n, parse_expr(I));
        expect(I, TOK_RPAREN, ")");
        add_child(n, parse_stmt(I));
        if (match(I, TOK_ELSE)) add_child(n, parse_stmt(I));
        return n;
    }
    /* while */
    if (match(I, TOK_WHILE)) {
        OccNode *n = new_node(ND_WHILE, line);
        expect(I, TOK_LPAREN, "(");
        add_child(n, parse_expr(I));
        expect(I, TOK_RPAREN, ")");
        add_child(n, parse_stmt(I));
        return n;
    }
    /* do-while */
    if (match(I, TOK_DO)) {
        OccNode *n = new_node(ND_DOWHILE, line);
        add_child(n, parse_stmt(I));
        expect(I, TOK_WHILE, "while");
        expect(I, TOK_LPAREN, "(");
        add_child(n, parse_expr(I));
        expect(I, TOK_RPAREN, ")");
        expect(I, TOK_SEMICOLON, ";");
        return n;
    }
    /* for */
    if (match(I, TOK_FOR)) {
        OccNode *n = new_node(ND_FOR, line);
        expect(I, TOK_LPAREN, "(");
        /* init */
        if (is_type_token(peek(I)->type)) {
            OccValType vt = parse_type(I);
            add_child(n, parse_vardecl(I, vt));
        } else if (!check(I, TOK_SEMICOLON)) {
            add_child(n, parse_expr(I));
        } else {
            add_child(n, NULL);
        }
        expect(I, TOK_SEMICOLON, ";");
        /* condition */
        add_child(n, check(I, TOK_SEMICOLON) ? NULL : parse_expr(I));
        expect(I, TOK_SEMICOLON, ";");
        /* increment */
        add_child(n, check(I, TOK_RPAREN) ? NULL : parse_expr(I));
        expect(I, TOK_RPAREN, ")");
        add_child(n, parse_stmt(I));
        return n;
    }
    /* switch */
    if (match(I, TOK_SWITCH)) {
        OccNode *n = new_node(ND_SWITCH, line);
        expect(I, TOK_LPAREN, "(");
        add_child(n, parse_expr(I));
        expect(I, TOK_RPAREN, ")");
        expect(I, TOK_LBRACE, "{");
        while (!check(I, TOK_RBRACE) && !check(I, TOK_EOF)) {
            if (match(I, TOK_CASE)) {
                OccNode *c = new_node(ND_CASE, peek(I)->line);
                add_child(c, parse_expr(I));
                expect(I, TOK_COLON, ":");
                while (!check(I, TOK_CASE) && !check(I, TOK_DEFAULT)
                       && !check(I, TOK_RBRACE) && !check(I, TOK_EOF))
                    add_stmt(c, parse_stmt(I));
                add_stmt(n, c);
            } else if (match(I, TOK_DEFAULT)) {
                OccNode *c = new_node(ND_DEFAULT, peek(I)->line);
                expect(I, TOK_COLON, ":");
                while (!check(I, TOK_CASE) && !check(I, TOK_DEFAULT)
                       && !check(I, TOK_RBRACE) && !check(I, TOK_EOF))
                    add_stmt(c, parse_stmt(I));
                add_stmt(n, c);
            } else {
                advance(I); /* skip unexpected */
            }
        }
        expect(I, TOK_RBRACE, "}");
        return n;
    }
    /* return */
    if (match(I, TOK_RETURN)) {
        OccNode *n = new_node(ND_RETURN, line);
        if (!check(I, TOK_SEMICOLON)) add_child(n, parse_expr(I));
        expect(I, TOK_SEMICOLON, ";");
        return n;
    }
    if (match(I, TOK_BREAK)) { expect(I, TOK_SEMICOLON, ";"); return new_node(ND_BREAK, line); }
    if (match(I, TOK_CONTINUE)) { expect(I, TOK_SEMICOLON, ";"); return new_node(ND_CONTINUE, line); }

    /* C11/C23 _Static_assert(expr, "msg") or _Static_assert(expr) */
    if (match(I, TOK_STATIC_ASSERT)) {
        OccNode *n = new_node(ND_STATIC_ASSERT, line);
        expect(I, TOK_LPAREN, "(");
        add_child(n, parse_expr(I)); /* condition */
        if (match(I, TOK_COMMA)) {
            /* optional message string */
            if (check(I, TOK_STRING_LIT)) {
                OccToken *msg_tok = advance(I);
                int ml = msg_tok->length < (OCC_MAX_STRLEN - 1) ? msg_tok->length : (OCC_MAX_STRLEN - 1);
                memcpy(n->str_val, msg_tok->start, ml);
                n->str_val[ml] = '\0';
            }
        }
        expect(I, TOK_RPAREN, ")");
        expect(I, TOK_SEMICOLON, ";");
        return n;
    }

    /* goto label; */
    if (match(I, TOK_GOTO)) {
        OccNode *n = new_node(ND_GOTO, line);
        if (check(I, TOK_IDENT)) {
            OccToken *t = advance(I);
            int ll = t->length < 63 ? t->length : 63;
            memcpy(n->label, t->start, ll);
            n->label[ll] = '\0';
        }
        expect(I, TOK_SEMICOLON, ";");
        return n;
    }

    /* struct/union declaration or variable */
    if (check(I, TOK_STRUCT) || check(I, TOK_UNION)) {
        int is_union = check(I, TOK_UNION);
        advance(I); /* consume 'struct' or 'union' */
        char sname[128] = {0};
        if (check(I, TOK_IDENT)) {
            OccToken *nt = advance(I);
            int nl = nt->length < 127 ? nt->length : 127;
            memcpy(sname, nt->start, nl);
        }
        /* struct/union definition: struct Name { ... }; */
        if (check(I, TOK_LBRACE)) {
            int st_idx = I->n_struct_types;
            if (st_idx < 64) {
                strncpy(I->struct_types[st_idx].name, sname, 127);
                I->struct_types[st_idx].is_union = is_union;
                parse_struct_union_body(I, st_idx);
                I->n_struct_types++;
            }
            /* check for variable declaration after struct def */
            if (check(I, TOK_IDENT)) {
                OccToken *var_tok = advance(I);
                OccNode *decl = new_node(ND_VARDECL, line);
                int vl = var_tok->length < 255 ? var_tok->length : 255;
                memcpy(decl->name, var_tok->start, vl); decl->name[vl] = '\0';
                decl->val_type = is_union ? VAL_UNION : VAL_STRUCT;
                strncpy(decl->str_val, sname, OCC_MAX_STRLEN - 1);
                if (match(I, TOK_ASSIGN)) add_child(decl, parse_assign(I));
                expect(I, TOK_SEMICOLON, ";");
                return decl;
            }
            expect(I, TOK_SEMICOLON, ";");
            return new_node(ND_BLOCK, line);
        }
        /* struct/union variable declaration */
        if (check(I, TOK_STAR) || check(I, TOK_IDENT)) {
            while (match(I, TOK_STAR)) {}
            if (check(I, TOK_IDENT)) {
                OccToken *var_tok = advance(I);
                OccNode *decl = new_node(ND_VARDECL, line);
                int vl = var_tok->length < 255 ? var_tok->length : 255;
                memcpy(decl->name, var_tok->start, vl); decl->name[vl] = '\0';
                decl->val_type = is_union ? VAL_UNION : VAL_STRUCT;
                strncpy(decl->str_val, sname, OCC_MAX_STRLEN - 1);
                /* Check for array of structs */
                if (match(I, TOK_LBRACKET)) {
                    decl->is_array = 1;
                    if (!check(I, TOK_RBRACKET)) {
                        OccNode *sz = parse_expr(I);
                        decl->array_size = (int)sz->num_val;
                    }
                    expect(I, TOK_RBRACKET, "]");
                }
                if (match(I, TOK_ASSIGN)) {
                    if (check(I, TOK_LBRACE)) {
                        advance(I);
                        OccNode *init = new_node(ND_STRUCT_INIT, line);
                        strncpy(init->str_val, sname, OCC_MAX_STRLEN - 1);
                        if (!check(I, TOK_RBRACE)) {
                            add_stmt(init, parse_assign(I));
                            while (match(I, TOK_COMMA)) {
                                if (check(I, TOK_RBRACE)) break;
                                add_stmt(init, parse_assign(I));
                            }
                        }
                        expect(I, TOK_RBRACE, "}");
                        add_child(decl, init);
                    } else {
                        add_child(decl, parse_assign(I));
                    }
                }
                expect(I, TOK_SEMICOLON, ";");
                return decl;
            }
        }
        expect(I, TOK_SEMICOLON, ";");
        return new_node(ND_BLOCK, line);
    }

    /* typedef */
    if (check(I, TOK_TYPEDEF)) {
        advance(I);
        if (check(I, TOK_STRUCT) || check(I, TOK_UNION)) {
            int is_union_td = check(I, TOK_UNION);
            advance(I);
            char orig[128] = {0};
            if (check(I, TOK_IDENT)) {
                OccToken *nt = peek(I);
                int nl = nt->length < 127 ? nt->length : 127;
                memcpy(orig, nt->start, nl);
                advance(I);
            }
            if (check(I, TOK_LBRACE)) {
                /* inline struct/union def */
                int st_idx = I->n_struct_types;
                if (st_idx < 64 && orig[0]) {
                    strncpy(I->struct_types[st_idx].name, orig, 127);
                    I->struct_types[st_idx].is_union = is_union_td;
                    parse_struct_union_body(I, st_idx);
                    I->n_struct_types++;
                } else {
                    /* anonymous — skip */
                    advance(I);
                    int depth = 1;
                    while (depth > 0 && !check(I, TOK_EOF)) {
                        if (check(I, TOK_LBRACE)) depth++;
                        if (check(I, TOK_RBRACE)) depth--;
                        if (depth > 0) advance(I);
                    }
                    expect(I, TOK_RBRACE, "}");
                }
            }
            if (check(I, TOK_IDENT)) {
                OccToken *alias = advance(I);
                if (I->n_typedefs < 64) {
                    int al = alias->length < 127 ? alias->length : 127;
                    memcpy(I->typedefs[I->n_typedefs].alias, alias->start, al);
                    strncpy(I->typedefs[I->n_typedefs].original, orig, 127);
                    I->n_typedefs++;
                }
            }
        } else {
            /* typedef int Alias; — skip type, grab alias */
            while (!check(I, TOK_SEMICOLON) && !check(I, TOK_EOF)) advance(I);
        }
        expect(I, TOK_SEMICOLON, ";");
        return new_node(ND_BLOCK, line);
    }

    /* enum declaration */
    if (check(I, TOK_ENUM)) {
        advance(I);
        if (check(I, TOK_IDENT)) advance(I);
        if (match(I, TOK_LBRACE)) {
            long long enum_counter = 0;
            while (!check(I, TOK_RBRACE) && !check(I, TOK_EOF)) {
                if (check(I, TOK_IDENT)) {
                    OccToken *name_tok = advance(I);
                    char ename[128] = {0};
                    int elen = name_tok->length < 127 ? name_tok->length : 127;
                    memcpy(ename, name_tok->start, elen);
                    if (match(I, TOK_ASSIGN)) {
                        int neg = 0;
                        if (match(I, TOK_MINUS)) neg = 1;
                        if (check(I, TOK_INT_LIT) || check(I, TOK_FLOAT_LIT)) {
                            OccToken *vt = advance(I);
                            enum_counter = (long long)vt->num_val;
                            if (neg) enum_counter = -enum_counter;
                        }
                    }
                    if (I->n_enum_vals < 256) {
                        strncpy(I->enum_vals[I->n_enum_vals].name, ename, 127);
                        I->enum_vals[I->n_enum_vals].value = enum_counter;
                        I->n_enum_vals++;
                    }
                    enum_counter++;
                    match(I, TOK_COMMA);
                } else {
                    advance(I);
                }
            }
            expect(I, TOK_RBRACE, "}");
        }
        expect(I, TOK_SEMICOLON, ";");
        return new_node(ND_BLOCK, line);
    }

    /* Labels: ident followed by colon (not inside switch) */
    if (check(I, TOK_IDENT) && I->tok_pos + 1 < I->n_tokens &&
        I->tokens[I->tok_pos + 1].type == TOK_COLON) {
        /* Check it's not a ternary or case — just a simple label */
        OccToken *lt = advance(I);
        advance(I); /* consume : */
        OccNode *label = new_node(ND_LABEL, line);
        int ll = lt->length < 63 ? lt->length : 63;
        memcpy(label->label, lt->start, ll);
        label->label[ll] = '\0';
        /* parse the statement after the label */
        if (!check(I, TOK_RBRACE) && !check(I, TOK_EOF))
            add_child(label, parse_stmt(I));
        return label;
    }

    /* variable declaration (including static) */
    if (is_type_token(peek(I)->type)) {
        int is_static = 0;
        if (check(I, TOK_STATIC)) {
            is_static = 1;
            /* Don't consume yet — parse_type handles it */
        }
        OccValType vt = parse_type(I);

        /* Check if this is a function pointer declaration: type (*name)(...) */
        if (check(I, TOK_LPAREN)) {
            int saved_fp = I->tok_pos;
            advance(I); /* ( */
            if (match(I, TOK_STAR)) {
                if (check(I, TOK_IDENT)) {
                    OccToken *fp_name = advance(I);
                    expect(I, TOK_RPAREN, ")");
                    /* Skip the parameter list */
                    if (match(I, TOK_LPAREN)) {
                        int depth = 1;
                        while (depth > 0 && !check(I, TOK_EOF)) {
                            if (check(I, TOK_LPAREN)) depth++;
                            if (check(I, TOK_RPAREN)) depth--;
                            if (depth > 0) advance(I);
                        }
                        match(I, TOK_RPAREN);
                    }
                    OccNode *decl = new_node(ND_VARDECL, line);
                    int nl2 = fp_name->length < 255 ? fp_name->length : 255;
                    memcpy(decl->name, fp_name->start, nl2);
                    decl->name[nl2] = '\0';
                    decl->val_type = VAL_FUNCPTR;
                    if (match(I, TOK_ASSIGN)) {
                        add_child(decl, parse_assign(I));
                    }
                    expect(I, TOK_SEMICOLON, ";");
                    return decl;
                }
            }
            I->tok_pos = saved_fp; /* backtrack */
        }

        /* Check if this is a function declaration: type name(...) { */
        int saved = I->tok_pos;
        while (match(I, TOK_STAR)) {} /* skip pointer stars */
        if (check(I, TOK_IDENT)) {
            int nameidx = I->tok_pos;
            advance(I);
            if (check(I, TOK_LPAREN)) {
                /* function declaration */
                I->tok_pos = nameidx;
                OccToken *fname_tok = advance(I);
                OccNode *fn = new_node(ND_FUNCDECL, line);
                strncpy(fn->name, fname_tok->start,
                        fname_tok->length < 255 ? fname_tok->length : 255);
                fn->name[fname_tok->length < 255 ? fname_tok->length : 255] = '\0';
                fn->val_type = vt;
                fn->is_static = is_static;
                expect(I, TOK_LPAREN, "(");
                while (!check(I, TOK_RPAREN) && !check(I, TOK_EOF)) {
                    /* function pointer params: void (*fp)(int, int) */
                    if (is_type_token(peek(I)->type)) {
                        OccValType pt = parse_type(I);
                        /* Check for function pointer param */
                        if (check(I, TOK_LPAREN)) {
                            int saved_pp = I->tok_pos;
                            advance(I);
                            if (match(I, TOK_STAR)) {
                                if (check(I, TOK_IDENT)) {
                                    OccToken *pname = advance(I);
                                    fn->param_types[fn->n_params] = VAL_FUNCPTR;
                                    strncpy(fn->param_names[fn->n_params], pname->start,
                                            pname->length < 255 ? pname->length : 255);
                                    fn->param_names[fn->n_params][pname->length < 255 ? pname->length : 255] = '\0';
                                    fn->n_params++;
                                    expect(I, TOK_RPAREN, ")");
                                    /* skip param list */
                                    if (match(I, TOK_LPAREN)) {
                                        int dp = 1;
                                        while (dp > 0 && !check(I, TOK_EOF)) {
                                            if (check(I, TOK_LPAREN)) dp++;
                                            if (check(I, TOK_RPAREN)) dp--;
                                            if (dp > 0) advance(I);
                                        }
                                        match(I, TOK_RPAREN);
                                    }
                                    if (!match(I, TOK_COMMA)) break;
                                    continue;
                                }
                            }
                            I->tok_pos = saved_pp;
                        }
                        while (match(I, TOK_STAR)) pt = VAL_PTR;
                        if (check(I, TOK_IDENT)) {
                            OccToken *pname = advance(I);
                            fn->param_types[fn->n_params] = pt;
                            strncpy(fn->param_names[fn->n_params], pname->start,
                                    pname->length < 255 ? pname->length : 255);
                            fn->param_names[fn->n_params][pname->length < 255 ? pname->length : 255] = '\0';
                            fn->n_params++;
                        }
                        if (match(I, TOK_LBRACKET)) {
                            while (!check(I, TOK_RBRACKET) && !check(I, TOK_EOF)) advance(I);
                            match(I, TOK_RBRACKET);
                        }
                    } else {
                        advance(I); /* skip ... or unknown */
                    }
                    if (!match(I, TOK_COMMA)) break;
                }
                expect(I, TOK_RPAREN, ")");
                if (check(I, TOK_LBRACE)) {
                    add_child(fn, parse_block(I));
                } else {
                    expect(I, TOK_SEMICOLON, ";"); /* forward declaration */
                }
                return fn;
            }
        }
        I->tok_pos = saved;

        /* regular variable declaration, possibly multiple: int a, b, c; */
        OccNode *block = new_node(ND_BLOCK, line);
        OccNode *vd = parse_vardecl(I, vt);
        vd->is_static = is_static;
        add_stmt(block, vd);
        while (match(I, TOK_COMMA)) {
            OccNode *vd2 = parse_vardecl(I, vt);
            vd2->is_static = is_static;
            add_stmt(block, vd2);
        }
        expect(I, TOK_SEMICOLON, ";");
        return block;
    }

    /* expression statement */
    if (match(I, TOK_SEMICOLON)) return new_node(ND_BLOCK, line); /* empty */
    OccNode *n = new_node(ND_EXPR_STMT, line);
    add_child(n, parse_expr(I));
    expect(I, TOK_SEMICOLON, ";");
    return n;
}

static OccNode *parse_program(OccInterpreter *I) {
    OccNode *prog = new_node(ND_PROGRAM, 1);
    while (!check(I, TOK_EOF)) {
        add_stmt(prog, parse_stmt(I));
    }
    return prog;
}

/* ══════════════════════════════════════════════
 *  Printf / Format engine (shared by printf, sprintf, snprintf)
 * ══════════════════════════════════════════════ */

/* Returns number of chars written. If buf is NULL, writes to I->output. */
static int occ_format(OccInterpreter *I, char *buf, int bufsize, const char *fmt, OccValue *args, int nargs) {
    int ai = 0;
    int written = 0;
    char tmp[1024];

    for (const char *p = fmt; *p; p++) {
        if (*p == '%' && p[1]) {
            p++;
            int width = 0, prec = -1, left = 0, zero = 0;
            char len_mod = 0;
            if (*p == '-') { left = 1; p++; }
            if (*p == '0') { zero = 1; p++; }
            while (isdigit(*p)) { width = width * 10 + (*p - '0'); p++; }
            if (*p == '.') { p++; prec = 0; while (isdigit(*p)) { prec = prec * 10 + (*p - '0'); p++; } }
            if (*p == 'l') { len_mod = 'l'; p++; if (*p == 'l') p++; }
            else if (*p == 'h') { p++; }
            (void)len_mod;

            char fmtbuf[256], subfmt[32];
            int n = 0;
            switch (*p) {
                case 'd': case 'i':
                    if (ai < nargs) {
                        snprintf(subfmt, sizeof(subfmt), "%%%s%s%dlld", left?"-":"", zero?"0":"", width);
                        if (width == 0 && !left && !zero) strcpy(subfmt, "%lld");
                        n = snprintf(fmtbuf, sizeof(fmtbuf), subfmt, val_to_int(args[ai++]));
                    }
                    break;
                case 'u':
                    if (ai < nargs) {
                        snprintf(subfmt, sizeof(subfmt), "%%%s%dllu", left?"-":"", width);
                        if (width == 0 && !left) strcpy(subfmt, "%llu");
                        n = snprintf(fmtbuf, sizeof(fmtbuf), subfmt, (unsigned long long)val_to_int(args[ai++]));
                    }
                    break;
                case 'f': case 'F':
                    if (ai < nargs) {
                        if (prec >= 0) n = snprintf(fmtbuf, sizeof(fmtbuf), "%*.*f", width, prec, val_to_double(args[ai++]));
                        else if (width > 0) n = snprintf(fmtbuf, sizeof(fmtbuf), "%*f", width, val_to_double(args[ai++]));
                        else n = snprintf(fmtbuf, sizeof(fmtbuf), "%f", val_to_double(args[ai++]));
                    }
                    break;
                case 'e': case 'E':
                    if (ai < nargs) {
                        if (prec >= 0) n = snprintf(fmtbuf, sizeof(fmtbuf), "%.*e", prec, val_to_double(args[ai++]));
                        else n = snprintf(fmtbuf, sizeof(fmtbuf), "%e", val_to_double(args[ai++]));
                    }
                    break;
                case 'g': case 'G':
                    if (ai < nargs) {
                        if (prec >= 0) n = snprintf(fmtbuf, sizeof(fmtbuf), "%.*g", prec, val_to_double(args[ai++]));
                        else n = snprintf(fmtbuf, sizeof(fmtbuf), "%g", val_to_double(args[ai++]));
                    }
                    break;
                case 'x': case 'X':
                    if (ai < nargs) {
                        snprintf(subfmt, sizeof(subfmt), "%%%s%s%dll%c", left?"-":"", zero?"0":"", width, *p);
                        if (width == 0 && !left && !zero) snprintf(subfmt, sizeof(subfmt), "%%ll%c", *p);
                        n = snprintf(fmtbuf, sizeof(fmtbuf), subfmt, val_to_int(args[ai++]));
                    }
                    break;
                case 'o':
                    if (ai < nargs) { n = snprintf(fmtbuf, sizeof(fmtbuf), "%llo", val_to_int(args[ai++])); }
                    break;
                case 'c':
                    if (ai < nargs) { fmtbuf[0] = (char)val_to_int(args[ai++]); fmtbuf[1] = 0; n = 1; }
                    break;
                case 's':
                    if (ai < nargs) {
                        /* Handle both VAL_STRING and VAL_ARRAY (char[]) */
                        if (args[ai].type == VAL_STRING && args[ai].v.s) {
                            if (width > 0) n = snprintf(fmtbuf, sizeof(fmtbuf), left ? "%-*s" : "%*s", width, args[ai].v.s);
                            else { strncpy(fmtbuf, args[ai].v.s, sizeof(fmtbuf)-1); fmtbuf[sizeof(fmtbuf)-1]=0; n = (int)strlen(fmtbuf); }
                            ai++;
                        } else if (args[ai].type == VAL_ARRAY) {
                            array_to_cstring(args[ai], tmp, sizeof(tmp));
                            if (width > 0) n = snprintf(fmtbuf, sizeof(fmtbuf), left ? "%-*s" : "%*s", width, tmp);
                            else { strncpy(fmtbuf, tmp, sizeof(fmtbuf)-1); fmtbuf[sizeof(fmtbuf)-1]=0; n = (int)strlen(fmtbuf); }
                            ai++;
                        } else {
                            ai++;
                            strcpy(fmtbuf, "(null)"); n = 6;
                        }
                    }
                    break;
                case 'p':
                    if (ai < nargs) { n = snprintf(fmtbuf, sizeof(fmtbuf), "0x%llx", val_to_int(args[ai++])); }
                    break;
                case '%': fmtbuf[0] = '%'; fmtbuf[1] = 0; n = 1; break;
                default: fmtbuf[0] = '%'; fmtbuf[1] = *p; fmtbuf[2] = 0; n = 2; break;
            }
            if (n > 0) {
                if (buf) {
                    int copylen = n;
                    if (written + copylen >= bufsize) copylen = bufsize - 1 - written;
                    if (copylen > 0) { memcpy(buf + written, fmtbuf, copylen); written += copylen; }
                } else {
                    out_append(I, fmtbuf);
                    written += n;
                }
            }
        } else {
            if (buf) {
                if (written < bufsize - 1) { buf[written++] = *p; }
            } else {
                char tc[2] = {*p, 0};
                out_append(I, tc);
                written++;
            }
        }
    }
    if (buf && written < bufsize) buf[written] = '\0';
    return written;
}

/* Legacy wrapper */
static void occ_printf(OccInterpreter *I, const char *fmt, OccValue *args, int nargs) {
    occ_format(I, NULL, 0, fmt, args, nargs);
}

/* ══════════════════════════════════════════════
 *  Built-in functions
 * ══════════════════════════════════════════════ */

static OccValue call_builtin(OccInterpreter *I, const char *name, OccValue *args, int nargs);

/* Call a user-defined function by name with given args */
static OccValue call_user_func(OccInterpreter *I, const char *fname, OccValue *args, int nargs) {
    for (int i = 0; i < I->n_funcs; i++) {
        if (strcmp(I->funcs[i].name, fname) == 0) {
            OccNode *fn = I->funcs[i].node;
            OccScope *fn_scope = scope_create(I->global_scope);
            for (int p = 0; p < fn->n_params && p < nargs; p++)
                scope_set(I, fn_scope, fn->param_names[p], args[p]);
            OccScope *saved = I->current_scope;
            char saved_func[128];
            strncpy(saved_func, I->current_func, 127);
            strncpy(I->current_func, fname, 127);
            I->current_scope = fn_scope;
            I->returning = 0;
            if (fn->children[0]) exec_node(I, fn->children[0]);
            OccValue ret = I->return_val;
            I->returning = 0;
            I->current_scope = saved;
            sync_statics(I, fn_scope); /* sync BEFORE restoring current_func */
            strncpy(I->current_func, saved_func, 127);
            scope_destroy(fn_scope);
            return ret;
        }
    }
    /* Not a user function — try builtin */
    return call_builtin(I, fname, args, nargs);
}

static OccValue call_builtin(OccInterpreter *I, const char *name, OccValue *args, int nargs) {
    /* printf family */
    if (strcmp(name, "printf") == 0 || strcmp(name, "fprintf") == 0) {
        int start = 0;
        if (strcmp(name, "fprintf") == 0) start = 1;
        if (start < nargs && args[start].type == VAL_STRING)
            occ_printf(I, args[start].v.s, args + start + 1, nargs - start - 1);
        else if (start < nargs && args[start].type == VAL_ARRAY) {
            char fmtbuf[OCC_MAX_STRLEN];
            array_to_cstring(args[start], fmtbuf, sizeof(fmtbuf));
            occ_printf(I, fmtbuf, args + start + 1, nargs - start - 1);
        }
        return make_int(0);
    }
    if (strcmp(name, "sprintf") == 0) {
        /* sprintf(buf, fmt, ...) — format into buf variable */
        if (nargs >= 2) {
            const char *fmt_str = NULL;
            char fmt_tmp[OCC_MAX_STRLEN];
            if (args[1].type == VAL_STRING) fmt_str = args[1].v.s;
            else if (args[1].type == VAL_ARRAY) { array_to_cstring(args[1], fmt_tmp, sizeof(fmt_tmp)); fmt_str = fmt_tmp; }
            if (fmt_str) {
                char result[OCC_MAX_STRLEN];
                int len = occ_format(I, result, sizeof(result), fmt_str, args + 2, nargs - 2);
                /* Try to write back to the first arg's variable if it's a char array */
                /* The caller (eval ND_CALL) will handle writeback for sprintf */
                (void)len;
                return make_string(result);
            }
        }
        return make_int(0);
    }
    if (strcmp(name, "snprintf") == 0) {
        if (nargs >= 3) {
            const char *fmt_str = NULL;
            char fmt_tmp[OCC_MAX_STRLEN];
            if (args[2].type == VAL_STRING) fmt_str = args[2].v.s;
            else if (args[2].type == VAL_ARRAY) { array_to_cstring(args[2], fmt_tmp, sizeof(fmt_tmp)); fmt_str = fmt_tmp; }
            if (fmt_str) {
                int maxlen = (int)val_to_int(args[1]);
                if (maxlen > OCC_MAX_STRLEN) maxlen = OCC_MAX_STRLEN;
                char result[OCC_MAX_STRLEN];
                int len = occ_format(I, result, maxlen > 0 ? maxlen : sizeof(result), fmt_str, args + 3, nargs - 3);
                (void)len;
                return make_string(result);
            }
        }
        return make_int(0);
    }
    if (strcmp(name, "puts") == 0) {
        if (nargs > 0) {
            if (args[0].type == VAL_STRING) { out_append(I, args[0].v.s); }
            else if (args[0].type == VAL_ARRAY) {
                char tmp[OCC_MAX_STRLEN];
                array_to_cstring(args[0], tmp, sizeof(tmp));
                out_append(I, tmp);
            }
            out_append(I, "\n");
        }
        return make_int(0);
    }
    if (strcmp(name, "putchar") == 0) {
        char c[2] = {(char)val_to_int(args[0]), 0}; out_append(I, c);
        return make_int(0);
    }

    /* math functions */
    #define MATH1(fn) if(strcmp(name,#fn)==0){return make_float(fn(val_to_double(args[0])));}
    #define MATH2(fn) if(strcmp(name,#fn)==0){return make_float(fn(val_to_double(args[0]),val_to_double(args[1])));}

    MATH1(sin) MATH1(cos) MATH1(tan) MATH1(asin) MATH1(acos) MATH1(atan)
    MATH1(sinh) MATH1(cosh) MATH1(tanh)
    MATH1(exp) MATH1(log) MATH1(log2) MATH1(log10)
    MATH1(sqrt) MATH1(cbrt) MATH1(fabs) MATH1(ceil) MATH1(floor) MATH1(round)
    MATH2(pow) MATH2(fmod) MATH2(atan2) MATH2(fmax) MATH2(fmin)
    #undef MATH1
    #undef MATH2

    if (strcmp(name, "abs") == 0) return make_int(llabs(val_to_int(args[0])));
    if (strcmp(name, "labs") == 0) return make_int(llabs(val_to_int(args[0])));

    /* string functions */
    if (strcmp(name, "strlen") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_int((long long)strlen(args[0].v.s));
        if (nargs > 0 && args[0].type == VAL_ARRAY) {
            char tmp[OCC_MAX_STRLEN];
            array_to_cstring(args[0], tmp, sizeof(tmp));
            return make_int((long long)strlen(tmp));
        }
        return make_int(0);
    }
    if (strcmp(name, "strcmp") == 0) {
        if (nargs >= 2) {
            char a[OCC_MAX_STRLEN], b[OCC_MAX_STRLEN];
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else { array_to_cstring(args[0], a, sizeof(a)); }
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else { array_to_cstring(args[1], b, sizeof(b)); }
            return make_int(strcmp(a, b));
        }
        return make_int(0);
    }
    if (strcmp(name, "atoi") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_int(atoi(args[0].v.s));
        if (nargs > 0 && args[0].type == VAL_ARRAY) {
            char tmp[OCC_MAX_STRLEN]; array_to_cstring(args[0], tmp, sizeof(tmp));
            return make_int(atoi(tmp));
        }
        return make_int(0);
    }
    if (strcmp(name, "atof") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_float(atof(args[0].v.s));
        if (nargs > 0 && args[0].type == VAL_ARRAY) {
            char tmp[OCC_MAX_STRLEN]; array_to_cstring(args[0], tmp, sizeof(tmp));
            return make_float(atof(tmp));
        }
        return make_float(0);
    }

    /* time */
    if (strcmp(name, "time") == 0) return make_int((long long)time(NULL));
    if (strcmp(name, "clock") == 0) return make_int((long long)clock());

    /* rand */
    if (strcmp(name, "rand") == 0) return make_int(rand());
    if (strcmp(name, "srand") == 0) { srand((unsigned)val_to_int(args[0])); return make_void(); }

    /* ── Memory allocation via vmem ── */
    if (strcmp(name, "malloc") == 0) {
        int sz = (int)val_to_int(args[0]);
        if (sz <= 0) return make_ptr(0, VAL_CHAR, 1);
        int addr = vmem_alloc(I, sz);
        if (!addr) return make_ptr(0, VAL_CHAR, 1);
        return make_ptr(addr, VAL_CHAR, 1);
    }
    if (strcmp(name, "calloc") == 0) {
        int n_items = (int)val_to_int(args[0]);
        int sz = nargs > 1 ? (int)val_to_int(args[1]) : 1;
        int total = n_items * sz;
        if (total <= 0) return make_ptr(0, VAL_CHAR, 1);
        int addr = vmem_alloc(I, total);
        if (!addr) return make_ptr(0, VAL_CHAR, 1);
        /* zero-fill (already zero from calloc in vmem_init) */
        for (int i = 0; i < total; i++) {
            OccValue *slot = vmem_get(I, addr + i);
            if (slot) *slot = make_int(0);
        }
        return make_ptr(addr, VAL_CHAR, 1);
    }
    if (strcmp(name, "realloc") == 0) {
        int old_addr = 0;
        if (nargs > 0 && args[0].type == VAL_PTR) old_addr = args[0].v.ptr.addr;
        int new_sz = nargs > 1 ? (int)val_to_int(args[1]) : 0;
        if (new_sz <= 0) return make_ptr(0, VAL_CHAR, 1);
        int new_addr = vmem_alloc(I, new_sz);
        if (!new_addr) return make_ptr(0, VAL_CHAR, 1);
        /* copy old data if possible */
        if (old_addr > 0) {
            for (int i = 0; i < new_sz; i++) {
                OccValue *src = vmem_get(I, old_addr + i);
                OccValue *dst = vmem_get(I, new_addr + i);
                if (src && dst) *dst = *src;
                else break;
            }
        }
        return make_ptr(new_addr, VAL_CHAR, 1);
    }
    if (strcmp(name, "free") == 0) {
        /* no-op — vmem is arena-based */
        return make_void();
    }

    /* memset/memcpy/memmove/memcmp */
    if (strcmp(name, "memset") == 0) return nargs > 0 ? args[0] : make_int(0);
    if (strcmp(name, "memcpy") == 0) return nargs > 0 ? args[0] : make_int(0);
    if (strcmp(name, "memmove") == 0) return nargs > 0 ? args[0] : make_int(0);
    if (strcmp(name, "memcmp") == 0) {
        /* simplified: compare as strings if both are strings/arrays */
        if (nargs >= 3) {
            char a[OCC_MAX_STRLEN] = {0}, b[OCC_MAX_STRLEN] = {0};
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
            int n = (int)val_to_int(args[2]);
            return make_int(memcmp(a, b, n < OCC_MAX_STRLEN ? n : OCC_MAX_STRLEN));
        }
        return make_int(0);
    }

    /* scanf — no stdin on iOS */
    if (strcmp(name, "scanf") == 0 || strcmp(name, "sscanf") == 0) {
        return make_int(0);
    }

    /* qsort — implemented with function pointers */
    if (strcmp(name, "qsort") == 0) {
        /* qsort(array_var, count, elem_size, comparator_func) */
        /* We need the array variable, which is args[0], and comparator name from args[3] */
        if (nargs >= 4) {
            int count = (int)val_to_int(args[1]);
            /* Get comparator function name */
            const char *cmp_name = NULL;
            if (args[3].type == VAL_FUNCPTR && args[3].v.s) cmp_name = args[3].v.s;
            else if (args[3].type == VAL_STRING && args[3].v.s) cmp_name = args[3].v.s;
            if (cmp_name && args[0].type == VAL_ARRAY && count > 1) {
                OccValue *data = args[0].v.arr.data;
                int len = args[0].v.arr.len;
                if (count > len) count = len;
                /* Insertion sort using comparator */
                for (int i = 1; i < count; i++) {
                    OccValue key = data[i];
                    int j = i - 1;
                    while (j >= 0) {
                        OccValue cmp_args[2] = {data[j], key};
                        OccValue cmp_result = call_user_func(I, cmp_name, cmp_args, 2);
                        if (val_to_int(cmp_result) <= 0) break;
                        data[j + 1] = data[j];
                        j--;
                    }
                    data[j + 1] = key;
                }
            }
        }
        return make_void();
    }

    /* string functions */
    if (strcmp(name, "strcpy") == 0 || strcmp(name, "strncpy") == 0) {
        if (nargs >= 2 && args[1].type == VAL_STRING) return make_string(args[1].v.s);
        if (nargs >= 2 && args[1].type == VAL_ARRAY) {
            char tmp[OCC_MAX_STRLEN]; array_to_cstring(args[1], tmp, sizeof(tmp));
            return make_string(tmp);
        }
        return args[0];
    }
    if (strcmp(name, "strcat") == 0) {
        char a[OCC_MAX_STRLEN] = {0}, b[OCC_MAX_STRLEN] = {0};
        if (nargs >= 1) {
            if (args[0].type == VAL_STRING && args[0].v.s) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
        }
        if (nargs >= 2) {
            if (args[1].type == VAL_STRING && args[1].v.s) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
        }
        char result[OCC_MAX_STRLEN];
        snprintf(result, sizeof(result), "%s%s", a, b);
        return make_string(result);
    }
    if (strcmp(name, "strstr") == 0) {
        if (nargs >= 2) {
            char a[OCC_MAX_STRLEN], b[OCC_MAX_STRLEN];
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
            return make_int(strstr(a, b) != NULL);
        }
        return make_int(0);
    }
    if (strcmp(name, "strncmp") == 0) {
        if (nargs >= 3) {
            char a[OCC_MAX_STRLEN], b[OCC_MAX_STRLEN];
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
            return make_int(strncmp(a, b, (int)val_to_int(args[2])));
        }
        return make_int(0);
    }
    if (strcmp(name, "strspn") == 0) {
        if (nargs >= 2) {
            char a[OCC_MAX_STRLEN], b[OCC_MAX_STRLEN];
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
            return make_int((long long)strspn(a, b));
        }
        return make_int(0);
    }
    if (strcmp(name, "strcspn") == 0) {
        if (nargs >= 2) {
            char a[OCC_MAX_STRLEN], b[OCC_MAX_STRLEN];
            if (args[0].type == VAL_STRING) strncpy(a, args[0].v.s, sizeof(a)-1);
            else array_to_cstring(args[0], a, sizeof(a));
            if (args[1].type == VAL_STRING) strncpy(b, args[1].v.s, sizeof(b)-1);
            else array_to_cstring(args[1], b, sizeof(b));
            return make_int((long long)strcspn(a, b));
        }
        return make_int(0);
    }
    if (strcmp(name, "toupper") == 0) return make_int(toupper((int)val_to_int(args[0])));
    if (strcmp(name, "tolower") == 0) return make_int(tolower((int)val_to_int(args[0])));
    if (strcmp(name, "isdigit") == 0) return make_int(isdigit((int)val_to_int(args[0])));
    if (strcmp(name, "isalpha") == 0) return make_int(isalpha((int)val_to_int(args[0])));
    if (strcmp(name, "isalnum") == 0) return make_int(isalnum((int)val_to_int(args[0])));
    if (strcmp(name, "isspace") == 0) return make_int(isspace((int)val_to_int(args[0])));
    if (strcmp(name, "isupper") == 0) return make_int(isupper((int)val_to_int(args[0])));
    if (strcmp(name, "islower") == 0) return make_int(islower((int)val_to_int(args[0])));
    if (strcmp(name, "ispunct") == 0) return make_int(ispunct((int)val_to_int(args[0])));
    if (strcmp(name, "isxdigit") == 0) return make_int(isxdigit((int)val_to_int(args[0])));
    if (strcmp(name, "isprint") == 0) return make_int(isprint((int)val_to_int(args[0])));

    /* string conversion */
    if (strcmp(name, "strtol") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) {
            int base = nargs > 2 ? (int)val_to_int(args[2]) : 10;
            return make_int(strtol(args[0].v.s, NULL, base));
        }
        return make_int(0);
    }
    if (strcmp(name, "strtod") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING)
            return make_float(strtod(args[0].v.s, NULL));
        return make_float(0);
    }
    if (strcmp(name, "strtof") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING)
            return make_float(strtof(args[0].v.s, NULL));
        return make_float(0);
    }

    /* more string functions */
    if (strcmp(name, "strchr") == 0) {
        if (nargs >= 2 && args[0].type == VAL_STRING) {
            char *p = strchr(args[0].v.s, (char)val_to_int(args[1]));
            return p ? make_string(p) : make_int(0);
        }
        return make_int(0);
    }
    if (strcmp(name, "strrchr") == 0) {
        if (nargs >= 2 && args[0].type == VAL_STRING) {
            char *p = strrchr(args[0].v.s, (char)val_to_int(args[1]));
            return p ? make_string(p) : make_int(0);
        }
        return make_int(0);
    }
    if (strcmp(name, "strncat") == 0) {
        if (nargs >= 3 && args[0].type == VAL_STRING && args[1].type == VAL_STRING) {
            char buf[OCC_MAX_STRLEN];
            snprintf(buf, sizeof(buf), "%s%.*s", args[0].v.s, (int)val_to_int(args[2]), args[1].v.s);
            return make_string(buf);
        }
        return args[0];
    }
    if (strcmp(name, "strdup") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_string(args[0].v.s);
        return make_string("");
    }
    if (strcmp(name, "strtok") == 0) {
        if (nargs >= 2 && args[0].type == VAL_STRING && args[1].type == VAL_STRING) {
            char buf[OCC_MAX_STRLEN];
            strncpy(buf, args[0].v.s, sizeof(buf)-1);
            char *tok = strtok(buf, args[1].v.s);
            return tok ? make_string(tok) : make_int(0);
        }
        return make_int(0);
    }

    /* getchar / fgets — no stdin on iOS */
    if (strcmp(name, "getchar") == 0) return make_int(-1);
    if (strcmp(name, "fgets") == 0) return make_int(0);

    /* assert */
    if (strcmp(name, "assert") == 0) {
        if (nargs > 0 && !val_to_bool(args[0])) {
            occ_error(I, "Assertion failed");
        }
        return make_void();
    }

    if (strcmp(name, "itoa") == 0) {
        char buf[64];
        snprintf(buf, sizeof(buf), "%lld", val_to_int(args[0]));
        return make_string(buf);
    }

    /* exit */
    if (strcmp(name, "exit") == 0) {
        I->returning = 1;
        I->return_val = make_int(nargs > 0 ? val_to_int(args[0]) : 0);
        return make_void();
    }

    occ_error(I, "Undefined function: %s", name);
    return make_void();
}

/* ══════════════════════════════════════════════
 *  Evaluator (tree-walking interpreter)
 * ══════════════════════════════════════════════ */

static OccVar *resolve_lvalue(OccInterpreter *I, OccNode *n) {
    if (n->type == ND_IDENT) {
        OccVar *v = scope_find(I->current_scope, n->name);
        if (!v) occ_error(I, "Line %d: Undefined variable '%s'", n->line, n->name);
        return v;
    }
    if (n->type == ND_INDEX) {
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (v && v->val.type == VAL_ARRAY) {
            int idx = (int)val_to_int(eval_node(I, n->children[1]));
            if (idx < 0 || idx >= v->val.v.arr.len)
                occ_error(I, "Line %d: Array index %d out of bounds (size %d)", n->line, idx, v->val.v.arr.len);
            return NULL; /* handled specially in eval */
        }
    }
    return NULL;
}

static OccValue eval_node(OccInterpreter *I, OccNode *n) {
    if (!n) return make_int(0);

    switch (n->type) {
    case ND_INT_LIT: return make_int((long long)n->num_val);
    case ND_FLOAT_LIT: return make_float(n->num_val);
    case ND_CHAR_LIT: return make_char((char)(int)n->num_val);
    case ND_STRING_LIT: return make_string(n->str_val);

    case ND_IDENT: {
        OccVar *v = scope_find(I->current_scope, n->name);
        if (!v) {
            /* check built-in constants */
            if (strcmp(n->name, "NULL") == 0) return make_ptr(0, VAL_VOID, 1);
            if (strcmp(n->name, "nullptr") == 0) return make_ptr(0, VAL_VOID, 1);
            if (strcmp(n->name, "true") == 0 || strcmp(n->name, "TRUE") == 0) return make_int(1);
            if (strcmp(n->name, "false") == 0 || strcmp(n->name, "FALSE") == 0) return make_int(0);
            if (strcmp(n->name, "M_PI") == 0) return make_float(M_PI);
            if (strcmp(n->name, "M_E") == 0) return make_float(M_E);
            if (strcmp(n->name, "INT_MAX") == 0) return make_int(INT_MAX);
            if (strcmp(n->name, "INT_MIN") == 0) return make_int(INT_MIN);
            if (strcmp(n->name, "LLONG_MAX") == 0) return make_int(LLONG_MAX);
            if (strcmp(n->name, "DBL_MAX") == 0) return make_float(DBL_MAX);
            if (strcmp(n->name, "RAND_MAX") == 0) return make_int(RAND_MAX);
            if (strcmp(n->name, "CLOCKS_PER_SEC") == 0) return make_int(CLOCKS_PER_SEC);
            if (strcmp(n->name, "EOF") == 0) return make_int(-1);
            /* check #define'd values */
            for (int di = 0; di < I->n_defines; di++) {
                if (strcmp(I->defines[di].name, n->name) == 0) {
                    const char *val = I->defines[di].value;
                    if (val[0] == '\0') return make_int(1);
                    char *endp;
                    double dv = strtod(val, &endp);
                    if (endp != val && *endp == '\0') {
                        if (strchr(val, '.') || strchr(val, 'e') || strchr(val, 'E'))
                            return make_float(dv);
                        return make_int((long long)dv);
                    }
                    return make_string(val);
                }
            }
            /* check enum values */
            for (int ei = 0; ei < I->n_enum_vals; ei++) {
                if (strcmp(I->enum_vals[ei].name, n->name) == 0)
                    return make_int(I->enum_vals[ei].value);
            }
            /* Check if it's a function name — return as function pointer */
            for (int fi = 0; fi < I->n_funcs; fi++) {
                if (strcmp(I->funcs[fi].name, n->name) == 0)
                    return make_funcptr(n->name);
            }
            occ_error(I, "Line %d: Undefined variable '%s'", n->line, n->name);
        }
        /* If variable has vmem backing (pointer was taken), read from vmem to see write-through changes */
        if (v->vmem_addr > 0 && v->val.type != VAL_ARRAY && v->val.type != VAL_PTR
            && v->val.type != VAL_STRUCT && v->val.type != VAL_UNION && v->val.type != VAL_FUNCPTR) {
            OccValue *slot = vmem_get(I, v->vmem_addr);
            if (slot && slot->type != VAL_VOID) {
                v->val = *slot; /* sync back from vmem */
            }
        }
        return v->val;
    }

    case ND_CAST: {
        OccValue v = eval_node(I, n->children[0]);
        switch (n->val_type) {
            case VAL_INT: return make_int(val_to_int(v));
            case VAL_FLOAT: case VAL_DOUBLE: return make_float(val_to_double(v));
            case VAL_CHAR: return make_char((char)val_to_int(v));
            default: return v;
        }
    }

    case ND_SIZEOF: {
        if (n->children[0]) {
            OccValue v = eval_node(I, n->children[0]);
            switch (v.type) {
                case VAL_CHAR: return make_int(1);
                case VAL_INT: return make_int(4);
                case VAL_FLOAT: return make_int(4);
                case VAL_DOUBLE: return make_int(8);
                case VAL_STRING: return make_int(v.v.s ? (long long)strlen(v.v.s) + 1 : 0);
                case VAL_ARRAY: return make_int(v.v.arr.len * 8);
                case VAL_PTR: return make_int(8);
                default: return make_int(8);
            }
        }
        switch (n->val_type) {
            case VAL_CHAR: return make_int(1);
            case VAL_INT: return make_int(4);
            case VAL_FLOAT: return make_int(4);
            case VAL_DOUBLE: return make_int(8);
            default: return make_int(8);
        }
    }

    /* C11 _Generic: evaluate controlling expr, match type against associations */
    case ND_GENERIC: {
        OccValue ctrl = eval_node(I, n->children[0]);
        OccValType ctrl_type = ctrl.type;
        /* Map FLOAT to DOUBLE for matching (both are stored as VAL_DOUBLE often) */
        OccNode *default_assoc = NULL;
        for (int gi = 0; gi < n->n_stmts; gi++) {
            OccNode *assoc = n->stmts[gi];
            if (assoc->type == ND_DEFAULT) {
                default_assoc = assoc;
            } else if (assoc->type == ND_CASE && assoc->val_type == ctrl_type) {
                return eval_node(I, assoc->children[0]);
            }
        }
        /* Also try matching VAL_FLOAT to VAL_DOUBLE and vice versa */
        if (ctrl_type == VAL_FLOAT || ctrl_type == VAL_DOUBLE) {
            OccValType alt = (ctrl_type == VAL_FLOAT) ? VAL_DOUBLE : VAL_FLOAT;
            for (int gi = 0; gi < n->n_stmts; gi++) {
                OccNode *assoc = n->stmts[gi];
                if (assoc->type == ND_CASE && assoc->val_type == alt) {
                    return eval_node(I, assoc->children[0]);
                }
            }
        }
        if (default_assoc) return eval_node(I, default_assoc->children[0]);
        occ_error(I, "Line %d: _Generic: no matching type association", n->line);
        return make_int(0);
    }

    /* arithmetic with pointer support */
    case ND_ADD: case ND_SUB: case ND_MUL: case ND_DIV: case ND_MOD: {
        OccValue l = eval_node(I, n->children[0]);
        OccValue r = eval_node(I, n->children[1]);
        /* Pointer arithmetic */
        if (n->type == ND_ADD && l.type == VAL_PTR) {
            return make_ptr(l.v.ptr.addr + (int)val_to_int(r) * l.v.ptr.stride, l.v.ptr.pointee_type, l.v.ptr.stride);
        }
        if (n->type == ND_ADD && r.type == VAL_PTR) {
            return make_ptr(r.v.ptr.addr + (int)val_to_int(l) * r.v.ptr.stride, r.v.ptr.pointee_type, r.v.ptr.stride);
        }
        if (n->type == ND_SUB && l.type == VAL_PTR && r.type == VAL_PTR) {
            int stride = l.v.ptr.stride > 0 ? l.v.ptr.stride : 1;
            return make_int((l.v.ptr.addr - r.v.ptr.addr) / stride);
        }
        if (n->type == ND_SUB && l.type == VAL_PTR) {
            return make_ptr(l.v.ptr.addr - (int)val_to_int(r) * l.v.ptr.stride, l.v.ptr.pointee_type, l.v.ptr.stride);
        }
        if (is_float_type(l) || is_float_type(r)) {
            double a = val_to_double(l), b = val_to_double(r);
            switch (n->type) {
                case ND_ADD: return make_float(a + b);
                case ND_SUB: return make_float(a - b);
                case ND_MUL: return make_float(a * b);
                case ND_DIV: return b != 0 ? make_float(a / b) : make_float(0);
                case ND_MOD: return make_float(fmod(a, b));
                default: break;
            }
        }
        long long a = val_to_int(l), b = val_to_int(r);
        switch (n->type) {
            case ND_ADD: return make_int(a + b);
            case ND_SUB: return make_int(a - b);
            case ND_MUL: return make_int(a * b);
            case ND_DIV: return b != 0 ? make_int(a / b) : make_int(0);
            case ND_MOD: return b != 0 ? make_int(a % b) : make_int(0);
            default: break;
        }
        break;
    }

    /* comparison */
    case ND_EQ: case ND_NEQ: case ND_LT: case ND_GT: case ND_LE: case ND_GE: {
        OccValue l = eval_node(I, n->children[0]);
        OccValue r = eval_node(I, n->children[1]);
        /* Pointer comparison */
        if (l.type == VAL_PTR && r.type == VAL_PTR) {
            int la = l.v.ptr.addr, ra = r.v.ptr.addr;
            switch (n->type) {
                case ND_EQ: return make_int(la == ra);
                case ND_NEQ: return make_int(la != ra);
                case ND_LT: return make_int(la < ra);
                case ND_GT: return make_int(la > ra);
                case ND_LE: return make_int(la <= ra);
                case ND_GE: return make_int(la >= ra);
                default: break;
            }
        }
        /* Pointer vs NULL (int 0) */
        if (l.type == VAL_PTR || r.type == VAL_PTR) {
            long long la = val_to_int(l), ra = val_to_int(r);
            switch (n->type) {
                case ND_EQ: return make_int(la == ra);
                case ND_NEQ: return make_int(la != ra);
                default: break;
            }
        }
        double a = val_to_double(l), b = val_to_double(r);
        switch (n->type) {
            case ND_EQ: return make_int(a == b);
            case ND_NEQ: return make_int(a != b);
            case ND_LT: return make_int(a < b);
            case ND_GT: return make_int(a > b);
            case ND_LE: return make_int(a <= b);
            case ND_GE: return make_int(a >= b);
            default: break;
        }
        break;
    }

    /* logical */
    case ND_AND: return make_int(val_to_bool(eval_node(I, n->children[0])) && val_to_bool(eval_node(I, n->children[1])));
    case ND_OR: return make_int(val_to_bool(eval_node(I, n->children[0])) || val_to_bool(eval_node(I, n->children[1])));
    case ND_NOT: return make_int(!val_to_bool(eval_node(I, n->children[0])));

    /* bitwise */
    case ND_BIT_AND: return make_int(val_to_int(eval_node(I, n->children[0])) & val_to_int(eval_node(I, n->children[1])));
    case ND_BIT_OR: return make_int(val_to_int(eval_node(I, n->children[0])) | val_to_int(eval_node(I, n->children[1])));
    case ND_BIT_XOR: return make_int(val_to_int(eval_node(I, n->children[0])) ^ val_to_int(eval_node(I, n->children[1])));
    case ND_BIT_NOT: return make_int(~val_to_int(eval_node(I, n->children[0])));
    case ND_LSHIFT: return make_int(val_to_int(eval_node(I, n->children[0])) << val_to_int(eval_node(I, n->children[1])));
    case ND_RSHIFT: return make_int(val_to_int(eval_node(I, n->children[0])) >> val_to_int(eval_node(I, n->children[1])));

    /* unary */
    case ND_NEG: {
        OccValue v = eval_node(I, n->children[0]);
        return is_float_type(v) ? make_float(-val_to_double(v)) : make_int(-val_to_int(v));
    }

    /* pre/post inc/dec */
    case ND_PRE_INC: case ND_PRE_DEC: {
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (v) {
            if (v->val.type == VAL_PTR) {
                v->val.v.ptr.addr += (n->type == ND_PRE_INC ? v->val.v.ptr.stride : -v->val.v.ptr.stride);
            } else if (is_float_type(v->val)) {
                v->val.v.f += (n->type == ND_PRE_INC ? 1.0 : -1.0);
            } else {
                v->val.v.i += (n->type == ND_PRE_INC ? 1 : -1);
            }
            return v->val;
        }
        break;
    }
    case ND_POST_INC: case ND_POST_DEC: {
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (v) {
            OccValue old = v->val;
            if (v->val.type == VAL_PTR) {
                v->val.v.ptr.addr += (n->type == ND_POST_INC ? v->val.v.ptr.stride : -v->val.v.ptr.stride);
            } else if (is_float_type(v->val)) {
                v->val.v.f += (n->type == ND_POST_INC ? 1.0 : -1.0);
            } else {
                v->val.v.i += (n->type == ND_POST_INC ? 1 : -1);
            }
            return old;
        }
        break;
    }

    /* ternary */
    case ND_TERNARY:
        return val_to_bool(eval_node(I, n->children[0]))
            ? eval_node(I, n->children[1]) : eval_node(I, n->children[2]);

    /* assignment */
    case ND_ASSIGN: {
        OccValue rhs = eval_node(I, n->children[1]);
        if (n->children[0]->type == ND_IDENT) {
            OccVar *v = scope_find(I->current_scope, n->children[0]->name);
            if (!v) occ_error(I, "Line %d: Undefined variable '%s'", n->line, n->children[0]->name);
            /* If assigning string to char array, convert */
            if (v->val.type == VAL_ARRAY && v->val.v.arr.elem_type == VAL_CHAR && rhs.type == VAL_STRING && rhs.v.s) {
                int slen = (int)strlen(rhs.v.s);
                for (int i = 0; i < v->val.v.arr.len && i <= slen; i++) {
                    v->val.v.arr.data[i] = make_char(i < slen ? rhs.v.s[i] : '\0');
                }
                return rhs;
            }
            v->val = rhs;
            return rhs;
        }
        if (n->children[0]->type == ND_INDEX) {
            /* Check for nested index: arr[i][j] */
            OccNode *idx_node = n->children[0];
            if (idx_node->children[0]->type == ND_INDEX) {
                /* 2D: outer[inner[base][i]][j] */
                OccVar *v = resolve_lvalue(I, idx_node->children[0]->children[0]);
                if (v && v->val.type == VAL_ARRAY) {
                    int outer_idx = (int)val_to_int(eval_node(I, idx_node->children[0]->children[1]));
                    int inner_idx = (int)val_to_int(eval_node(I, idx_node->children[1]));
                    if (outer_idx >= 0 && outer_idx < v->val.v.arr.len &&
                        v->val.v.arr.data[outer_idx].type == VAL_ARRAY) {
                        OccValue *inner = &v->val.v.arr.data[outer_idx];
                        if (inner_idx >= 0 && inner_idx < inner->v.arr.len) {
                            inner->v.arr.data[inner_idx] = rhs;
                        }
                    }
                    return rhs;
                }
            }
            OccVar *v = resolve_lvalue(I, idx_node->children[0]);
            if (v && v->val.type == VAL_ARRAY) {
                int idx = (int)val_to_int(eval_node(I, idx_node->children[1]));
                if (idx >= 0 && idx < v->val.v.arr.len)
                    v->val.v.arr.data[idx] = rhs;
                return rhs;
            }
            /* Pointer index assignment */
            if (v && v->val.type == VAL_PTR) {
                int idx = (int)val_to_int(eval_node(I, idx_node->children[1]));
                int addr = v->val.v.ptr.addr + idx * v->val.v.ptr.stride;
                OccValue *slot = vmem_get(I, addr);
                if (slot) *slot = rhs;
                return rhs;
            }
        }
        if (n->children[0]->type == ND_DEREF) {
            OccValue ptr = eval_node(I, n->children[0]->children[0]);
            if (ptr.type == VAL_PTR) {
                OccValue *slot = vmem_get(I, ptr.v.ptr.addr);
                if (slot) *slot = rhs;
            }
            return rhs;
        }
        /* struct.field = value or ptr->field = value */
        if (n->children[0]->type == ND_MEMBER || n->children[0]->type == ND_ARROW) {
            OccNode *mem = n->children[0];
            if (mem->children[0]->type == ND_IDENT) {
                OccVar *sv = scope_find(I->current_scope, mem->children[0]->name);
                if (sv && (sv->val.type == VAL_STRUCT || sv->val.type == VAL_UNION)) {
                    if (sv->val.type == VAL_UNION) {
                        /* Union: writing any field writes the single storage */
                        if (sv->val.v.st.n_fields > 0) {
                            sv->val.v.st.fields[0] = rhs;
                            return rhs;
                        }
                    }
                    for (int fi = 0; fi < sv->val.v.st.n_fields; fi++) {
                        if (strcmp(sv->val.v.st.field_names[fi], mem->name) == 0) {
                            sv->val.v.st.fields[fi] = rhs;
                            return rhs;
                        }
                    }
                }
            }
            /* Nested: struct.arr[i].field */
            if (mem->children[0]->type == ND_INDEX) {
                OccNode *idx_n = mem->children[0];
                OccVar *sv = resolve_lvalue(I, idx_n->children[0]);
                if (sv && sv->val.type == VAL_ARRAY) {
                    int idx = (int)val_to_int(eval_node(I, idx_n->children[1]));
                    if (idx >= 0 && idx < sv->val.v.arr.len && sv->val.v.arr.data[idx].type == VAL_STRUCT) {
                        OccValue *elem = &sv->val.v.arr.data[idx];
                        for (int fi = 0; fi < elem->v.st.n_fields; fi++) {
                            if (strcmp(elem->v.st.field_names[fi], mem->name) == 0) {
                                elem->v.st.fields[fi] = rhs;
                                return rhs;
                            }
                        }
                    }
                }
            }
        }
        return rhs;
    }
    case ND_COMPOUND_ASSIGN: {
        /* Handle compound assign on indexed elements (arr[i] += val, arr[i][j] += val) */
        if (n->children[0]->type == ND_INDEX) {
            OccValue cur = eval_node(I, n->children[0]);
            OccValue rhs = eval_node(I, n->children[1]);
            OccValue result;
            if (is_float_type(cur) || is_float_type(rhs)) {
                double a = val_to_double(cur), b = val_to_double(rhs);
                switch (n->op) {
                    case ND_ADD: result = make_float(a + b); break;
                    case ND_SUB: result = make_float(a - b); break;
                    case ND_MUL: result = make_float(a * b); break;
                    case ND_DIV: result = make_float(b != 0 ? a / b : 0); break;
                    default: result = make_float(a); break;
                }
            } else {
                long long a = val_to_int(cur), b = val_to_int(rhs);
                switch (n->op) {
                    case ND_ADD: result = make_int(a + b); break;
                    case ND_SUB: result = make_int(a - b); break;
                    case ND_MUL: result = make_int(a * b); break;
                    case ND_DIV: result = make_int(b != 0 ? a / b : 0); break;
                    case ND_MOD: result = make_int(b != 0 ? a % b : 0); break;
                    case ND_BIT_AND: result = make_int(a & b); break;
                    case ND_BIT_OR: result = make_int(a | b); break;
                    case ND_BIT_XOR: result = make_int(a ^ b); break;
                    case ND_LSHIFT: result = make_int(a << b); break;
                    case ND_RSHIFT: result = make_int(a >> b); break;
                    default: result = make_int(a); break;
                }
            }
            /* Write back: resolve the array slot and overwrite */
            OccNode *idx = n->children[0];
            if (idx->children[0]->type == ND_INDEX) {
                /* 2D: arr[i][j] += val */
                OccValue base = eval_node(I, idx->children[0]->children[0]);
                if (base.type == VAL_ARRAY && base.v.arr.n_dims >= 2) {
                    int row = (int)val_to_int(eval_node(I, idx->children[0]->children[1]));
                    int col = (int)val_to_int(eval_node(I, idx->children[1]));
                    int cols = base.v.arr.dims[1];
                    int flat = row * cols + col;
                    /* Find the variable owning this array */
                    if (idx->children[0]->children[0]->type == ND_IDENT) {
                        OccVar *av = scope_find(I->current_scope, idx->children[0]->children[0]->name);
                        if (av && av->val.type == VAL_ARRAY && flat >= 0 && flat < av->val.v.arr.len) {
                            av->val.v.arr.data[flat] = result;
                        }
                    }
                } else {
                    /* Nested arrays */
                    OccNode *outer = idx->children[0];
                    if (outer->children[0]->type == ND_IDENT) {
                        OccVar *av = scope_find(I->current_scope, outer->children[0]->name);
                        if (av && av->val.type == VAL_ARRAY) {
                            int i1 = (int)val_to_int(eval_node(I, outer->children[1]));
                            int i2 = (int)val_to_int(eval_node(I, idx->children[1]));
                            if (i1 >= 0 && i1 < av->val.v.arr.len && av->val.v.arr.data[i1].type == VAL_ARRAY) {
                                OccValue *inner = &av->val.v.arr.data[i1];
                                if (i2 >= 0 && i2 < inner->v.arr.len)
                                    inner->v.arr.data[i2] = result;
                            }
                        }
                    }
                }
            } else {
                /* 1D: arr[i] += val */
                if (idx->children[0]->type == ND_IDENT) {
                    OccVar *av = scope_find(I->current_scope, idx->children[0]->name);
                    if (av && av->val.type == VAL_ARRAY) {
                        int i1 = (int)val_to_int(eval_node(I, idx->children[1]));
                        if (i1 >= 0 && i1 < av->val.v.arr.len)
                            av->val.v.arr.data[i1] = result;
                    } else if (av && av->val.type == VAL_PTR) {
                        int i1 = (int)val_to_int(eval_node(I, idx->children[1]));
                        int addr = av->val.v.ptr.addr + i1 * av->val.v.ptr.stride;
                        OccValue *slot = vmem_get(I, addr);
                        if (slot) *slot = result;
                    }
                }
            }
            return result;
        }
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (!v) occ_error(I, "Line %d: Invalid assignment target", n->line);
        OccValue rhs = eval_node(I, n->children[1]);
        /* Pointer compound assign */
        if (v->val.type == VAL_PTR && (n->op == ND_ADD || n->op == ND_SUB)) {
            int delta = (int)val_to_int(rhs) * v->val.v.ptr.stride;
            v->val.v.ptr.addr += (n->op == ND_ADD ? delta : -delta);
            return v->val;
        }
        if (is_float_type(v->val) || is_float_type(rhs)) {
            double a = val_to_double(v->val), b = val_to_double(rhs);
            switch (n->op) {
                case ND_ADD: v->val = make_float(a + b); break;
                case ND_SUB: v->val = make_float(a - b); break;
                case ND_MUL: v->val = make_float(a * b); break;
                case ND_DIV: v->val = make_float(b != 0 ? a / b : 0); break;
                case ND_MOD: v->val = make_float(fmod(a, b)); break;
                default: break;
            }
        } else {
            long long a = val_to_int(v->val), b = val_to_int(rhs);
            switch (n->op) {
                case ND_ADD: v->val = make_int(a + b); break;
                case ND_SUB: v->val = make_int(a - b); break;
                case ND_MUL: v->val = make_int(a * b); break;
                case ND_DIV: v->val = make_int(b != 0 ? a / b : 0); break;
                case ND_MOD: v->val = make_int(b != 0 ? a % b : 0); break;
                case ND_BIT_AND: v->val = make_int(a & b); break;
                case ND_BIT_OR: v->val = make_int(a | b); break;
                case ND_BIT_XOR: v->val = make_int(a ^ b); break;
                case ND_LSHIFT: v->val = make_int(a << b); break;
                case ND_RSHIFT: v->val = make_int(a >> b); break;
                default: break;
            }
        }
        return v->val;
    }

    /* array index */
    case ND_INDEX: {
        /* Detect chained 2D index: arr[i][j] → INDEX(INDEX(IDENT,i), j) */
        if (n->children[0]->type == ND_INDEX) {
            OccNode *outer = n->children[0];
            /* Get the base array from the inner INDEX */
            OccValue base_arr = eval_node(I, outer->children[0]);
            if (base_arr.type == VAL_ARRAY && base_arr.v.arr.n_dims >= 2) {
                int row = (int)val_to_int(eval_node(I, outer->children[1]));
                int col = (int)val_to_int(eval_node(I, n->children[1]));
                int cols = base_arr.v.arr.dims[1];
                int flat = row * cols + col;
                if (flat >= 0 && flat < base_arr.v.arr.len)
                    return base_arr.v.arr.data[flat];
                return make_int(0);
            }
            /* Fallback: nested array of arrays */
            if (base_arr.type == VAL_ARRAY) {
                int i1 = (int)val_to_int(eval_node(I, outer->children[1]));
                if (i1 >= 0 && i1 < base_arr.v.arr.len && base_arr.v.arr.data[i1].type == VAL_ARRAY) {
                    int i2 = (int)val_to_int(eval_node(I, n->children[1]));
                    OccValue *inner = &base_arr.v.arr.data[i1];
                    if (i2 >= 0 && i2 < inner->v.arr.len)
                        return inner->v.arr.data[i2];
                }
                return make_int(0);
            }
        }
        OccValue arr = eval_node(I, n->children[0]);
        int idx = (int)val_to_int(eval_node(I, n->children[1]));
        if (arr.type == VAL_ARRAY) {
            if (idx < 0 || idx >= arr.v.arr.len) return make_int(0);
            return arr.v.arr.data[idx];
        }
        if (arr.type == VAL_STRING && arr.v.s) {
            int len = (int)strlen(arr.v.s);
            if (idx < 0 || idx >= len) return make_char(0);
            return make_char(arr.v.s[idx]);
        }
        /* Pointer indexing via vmem */
        if (arr.type == VAL_PTR) {
            int addr = arr.v.ptr.addr + idx * arr.v.ptr.stride;
            OccValue *slot = vmem_get(I, addr);
            if (slot) return *slot;
            return make_int(0);
        }
        return make_int(0);
    }

    /* function call */
    case ND_CALL: {
        char fname[256] = {0};
        if (n->children[0]->type == ND_IDENT) strncpy(fname, n->children[0]->name, 255);

        /* evaluate arguments */
        OccNode *arg_list = n->children[1];
        int nargs = arg_list ? arg_list->n_stmts : 0;
        OccValue args[32];
        for (int i = 0; i < nargs && i < 32; i++)
            args[i] = eval_node(I, arg_list->stmts[i]);

        /* If callee is a function pointer variable */
        if (fname[0]) {
            OccVar *fvar = scope_find(I->current_scope, fname);
            if (fvar && fvar->val.type == VAL_FUNCPTR && fvar->val.v.s) {
                OccValue result = call_user_func(I, fvar->val.v.s, args, nargs);
                return result;
            }
        }

        /* Special handling for sprintf/snprintf: write result back to first arg variable */
        if ((strcmp(fname, "sprintf") == 0 || strcmp(fname, "snprintf") == 0) && nargs >= 2) {
            OccValue result = call_builtin(I, fname, args, nargs);
            /* Write formatted string back to the char array variable */
            if (arg_list->stmts[0]->type == ND_IDENT) {
                OccVar *dest = scope_find(I->current_scope, arg_list->stmts[0]->name);
                if (dest && dest->val.type == VAL_ARRAY && result.type == VAL_STRING && result.v.s) {
                    int slen = (int)strlen(result.v.s);
                    for (int i = 0; i < dest->val.v.arr.len && i <= slen; i++) {
                        dest->val.v.arr.data[i] = make_char(i < slen ? result.v.s[i] : '\0');
                    }
                    if (result.v.s) free(result.v.s);
                    return make_int(slen);
                }
            }
            return result;
        }

        /* qsort special: pass the actual array variable */
        if (strcmp(fname, "qsort") == 0 && nargs >= 4 && arg_list->stmts[0]->type == ND_IDENT) {
            OccVar *arr_var = scope_find(I->current_scope, arg_list->stmts[0]->name);
            if (arr_var && arr_var->val.type == VAL_ARRAY) {
                args[0] = arr_var->val; /* pass the actual array (by ref basically) */
                OccValue result = call_builtin(I, fname, args, nargs);
                /* The sort modified data in-place */
                return result;
            }
        }

        /* Call user-defined function */
        OccValue result = call_user_func(I, fname, args, nargs);
        return result;
    }

    case ND_COMMA:
        eval_node(I, n->children[0]);
        return eval_node(I, n->children[1]);

    case ND_MEMBER: case ND_ARROW: {
        OccValue obj = eval_node(I, n->children[0]);
        if (obj.type == VAL_STRUCT || obj.type == VAL_UNION) {
            if (obj.type == VAL_UNION) {
                /* Union: reading any field returns the single stored value */
                if (obj.v.st.n_fields > 0) return obj.v.st.fields[0];
                return make_int(0);
            }
            for (int fi = 0; fi < obj.v.st.n_fields; fi++) {
                if (strcmp(obj.v.st.field_names[fi], n->name) == 0)
                    return obj.v.st.fields[fi];
            }
            occ_error(I, "Line %d: Struct '%s' has no field '%s'", n->line, obj.v.st.type_name, n->name);
        }
        /* Array element struct access: handled via ND_INDEX already returning the struct */
        return make_int(0);
    }

    /* Address-of: allocate vmem slot and return pointer */
    case ND_ADDR: {
        if (n->children[0]->type == ND_IDENT) {
            OccVar *v = scope_find(I->current_scope, n->children[0]->name);
            if (!v) occ_error(I, "Line %d: Undefined variable '%s'", n->line, n->children[0]->name);
            /* Allocate vmem if not already done */
            if (v->vmem_addr == 0) {
                if (v->val.type == VAL_ARRAY) {
                    /* For arrays, allocate slots for each element */
                    int sz = v->val.v.arr.len > 0 ? v->val.v.arr.len : 1;
                    v->vmem_addr = vmem_alloc(I, sz);
                    for (int i = 0; i < sz && i < v->val.v.arr.len; i++) {
                        OccValue *slot = vmem_get(I, v->vmem_addr + i);
                        if (slot) *slot = v->val.v.arr.data[i];
                    }
                    return make_ptr(v->vmem_addr, v->val.v.arr.elem_type, 1);
                } else {
                    v->vmem_addr = vmem_alloc(I, 1);
                    OccValue *slot = vmem_get(I, v->vmem_addr);
                    if (slot) *slot = v->val;
                }
            } else {
                /* Update vmem from current value */
                if (v->val.type != VAL_ARRAY) {
                    OccValue *slot = vmem_get(I, v->vmem_addr);
                    if (slot) *slot = v->val;
                }
            }
            OccValType pt = v->val.type;
            int stride = 1;
            if (pt == VAL_ARRAY) { pt = v->val.v.arr.elem_type; }
            return make_ptr(v->vmem_addr, pt, stride);
        }
        if (n->children[0]->type == ND_INDEX) {
            /* &arr[i] */
            OccNode *idx_node = n->children[0];
            if (idx_node->children[0]->type == ND_IDENT) {
                OccVar *v = scope_find(I->current_scope, idx_node->children[0]->name);
                if (v && v->val.type == VAL_ARRAY) {
                    int idx = (int)val_to_int(eval_node(I, idx_node->children[1]));
                    if (v->vmem_addr == 0) {
                        int sz = v->val.v.arr.len > 0 ? v->val.v.arr.len : 1;
                        v->vmem_addr = vmem_alloc(I, sz);
                        for (int i = 0; i < sz && i < v->val.v.arr.len; i++) {
                            OccValue *slot = vmem_get(I, v->vmem_addr + i);
                            if (slot) *slot = v->val.v.arr.data[i];
                        }
                    }
                    return make_ptr(v->vmem_addr + idx, v->val.v.arr.elem_type, 1);
                }
            }
        }
        return make_ptr(0, VAL_VOID, 1);
    }

    /* Dereference: read from vmem */
    case ND_DEREF: {
        OccValue ptr = eval_node(I, n->children[0]);
        if (ptr.type == VAL_PTR) {
            OccValue *slot = vmem_get(I, ptr.v.ptr.addr);
            if (slot) return *slot;
            return make_int(0);
        }
        /* Legacy: if not a real pointer, just return the value */
        return ptr;
    }

    /* Compound literal */
    case ND_COMPOUND_LITERAL: {
        if (n->children[0] && n->children[0]->type == ND_ARRAY_INIT) {
            int count = n->children[0]->n_stmts;
            /* Check if this is a struct compound literal */
            if (n->val_type == VAL_STRUCT && n->str_val[0]) {
                int st_idx = -1;
                for (int si = 0; si < I->n_struct_types; si++) {
                    if (strcmp(I->struct_types[si].name, n->str_val) == 0) { st_idx = si; break; }
                }
                if (st_idx >= 0) {
                    int nf = I->struct_types[st_idx].n_fields;
                    OccValue sv;
                    sv.type = VAL_STRUCT;
                    sv.v.st.n_fields = nf;
                    sv.v.st.fields = (OccValue *)calloc(nf, sizeof(OccValue));
                    sv.v.st.field_names = (char (*)[64])calloc(nf, 64);
                    strncpy(sv.v.st.type_name, I->struct_types[st_idx].name, 63);
                    for (int fi = 0; fi < nf; fi++) {
                        strncpy(sv.v.st.field_names[fi], I->struct_types[st_idx].field_names[fi], 63);
                        sv.v.st.fields[fi] = (fi < count) ? eval_node(I, n->children[0]->stmts[fi]) : make_int(0);
                    }
                    return sv;
                }
            }
            /* Array compound literal */
            OccValue arr;
            arr.type = VAL_ARRAY;
            arr.v.arr.len = count;
            arr.v.arr.cap = count;
            arr.v.arr.elem_type = n->val_type;
            arr.v.arr.data = (OccValue *)calloc(count, sizeof(OccValue));
            arr.v.arr.n_dims = 0;
            for (int i = 0; i < count; i++)
                arr.v.arr.data[i] = eval_node(I, n->children[0]->stmts[i]);
            return arr;
        }
        return make_int(0);
    }

    default: break;
    }
    return make_int(0);
}

/* ── Statement execution ──────────────────────── */

static void exec_node(OccInterpreter *I, OccNode *n) {
    if (!n || I->returning || I->breaking || I->continuing) return;
    /* If goto is active, skip statements until we find the target label */
    if (I->goto_active && n->type != ND_LABEL && n->type != ND_BLOCK && n->type != ND_PROGRAM) return;

    switch (n->type) {
    case ND_PROGRAM:
    case ND_BLOCK:
        for (int i = 0; i < n->n_stmts; i++) {
            if (I->goto_active) {
                /* Only process labels and blocks when searching for goto target */
                if (n->stmts[i] && (n->stmts[i]->type == ND_LABEL || n->stmts[i]->type == ND_BLOCK)) {
                    exec_node(I, n->stmts[i]);
                    if (!I->goto_active) {
                        /* Found and cleared — continue executing from here */
                        for (int j = i + 1; j < n->n_stmts; j++) {
                            exec_node(I, n->stmts[j]);
                            if (I->returning || I->breaking || I->continuing || I->goto_active) break;
                        }
                        return;
                    }
                }
                continue;
            }
            exec_node(I, n->stmts[i]);
            if (I->returning || I->breaking || I->continuing) break;
            if (I->goto_active) continue; /* don't break — scan forward for the label */
        }
        break;

    case ND_FUNCDECL:
        if (I->n_funcs < OCC_MAX_FUNCS) {
            strncpy(I->funcs[I->n_funcs].name, n->name, 255);
            I->funcs[I->n_funcs].node = n;
            I->n_funcs++;
        }
        break;

    case ND_VARDECL: {
        OccValue init;
        /* C23 auto type deduction: evaluate initializer first to determine type */
        if (n->val_type == VAL_AUTO_MARKER) {
            if (n->children[0]) {
                init = eval_node(I, n->children[0]);
                /* Adopt the type from the initializer */
            } else {
                init = make_int(0); /* no initializer, default to int */
            }
            scope_set(I, I->current_scope, n->name, init);
            break;
        }
        /* Static variable handling */
        if (n->is_static) {
            /* Check if already exists in statics table */
            for (int si = 0; si < I->n_statics; si++) {
                if (strcmp(I->statics[si].func, I->current_func) == 0 &&
                    strcmp(I->statics[si].var, n->name) == 0) {
                    if (I->statics[si].init) {
                        scope_set(I, I->current_scope, n->name, I->statics[si].val);
                        return;
                    }
                }
            }
        }
        if (n->val_type == VAL_STRUCT || n->val_type == VAL_UNION) {
            /* Find struct/union type definition */
            int st_idx = -1;
            for (int si = 0; si < I->n_struct_types; si++) {
                if (strcmp(I->struct_types[si].name, n->str_val) == 0) { st_idx = si; break; }
            }
            if (st_idx < 0) {
                for (int ti = 0; ti < I->n_typedefs; ti++) {
                    if (strcmp(I->typedefs[ti].alias, n->str_val) == 0) {
                        for (int si = 0; si < I->n_struct_types; si++) {
                            if (strcmp(I->struct_types[si].name, I->typedefs[ti].original) == 0) { st_idx = si; break; }
                        }
                        break;
                    }
                }
            }
            if (st_idx >= 0) {
                int nf = I->struct_types[st_idx].n_fields;
                int is_union = I->struct_types[st_idx].is_union;
                init.type = is_union ? VAL_UNION : VAL_STRUCT;
                init.v.st.n_fields = nf;
                init.v.st.fields = (OccValue *)calloc(nf > 0 ? nf : 1, sizeof(OccValue));
                init.v.st.field_names = (char (*)[64])calloc(nf > 0 ? nf : 1, 64);
                strncpy(init.v.st.type_name, I->struct_types[st_idx].name, 63);
                for (int fi = 0; fi < nf; fi++) {
                    strncpy(init.v.st.field_names[fi], I->struct_types[st_idx].field_names[fi], 63);
                    int arr_sz = I->struct_types[st_idx].field_array_sizes[fi];
                    if (arr_sz > 0) {
                        /* Array field in struct */
                        OccValue arr_val;
                        arr_val.type = VAL_ARRAY;
                        arr_val.v.arr.len = arr_sz;
                        arr_val.v.arr.cap = arr_sz;
                        arr_val.v.arr.elem_type = I->struct_types[st_idx].field_types[fi];
                        arr_val.v.arr.data = (OccValue *)calloc(arr_sz, sizeof(OccValue));
                        arr_val.v.arr.n_dims = 0;
                        init.v.st.fields[fi] = arr_val;
                    } else {
                        switch (I->struct_types[st_idx].field_types[fi]) {
                            case VAL_FLOAT: case VAL_DOUBLE: init.v.st.fields[fi] = make_float(0); break;
                            case VAL_CHAR: init.v.st.fields[fi] = make_char(0); break;
                            case VAL_STRING: init.v.st.fields[fi] = make_string(""); break;
                            default: init.v.st.fields[fi] = make_int(0); break;
                        }
                    }
                }
                if (n->children[0]) {
                    if (n->children[0]->type == ND_STRUCT_INIT) {
                        for (int fi = 0; fi < n->children[0]->n_stmts && fi < nf; fi++)
                            init.v.st.fields[fi] = eval_node(I, n->children[0]->stmts[fi]);
                    } else {
                        OccValue rhs = eval_node(I, n->children[0]);
                        if (rhs.type == VAL_STRUCT || rhs.type == VAL_UNION) init = rhs;
                    }
                }
            } else {
                init = make_int(0);
            }
            scope_set(I, I->current_scope, n->name, init);
            if (n->is_static && I->n_statics < 256) {
                int si = I->n_statics++;
                strncpy(I->statics[si].func, I->current_func, 127);
                strncpy(I->statics[si].var, n->name, 127);
                I->statics[si].val = init;
                I->statics[si].init = 1;
            }
            break;
        }
        /* char array from string literal: char str[N] = "hello" */
        if (n->is_array && n->val_type == VAL_CHAR && n->children[0] &&
            n->children[0]->type == ND_STRING_LIT) {
            const char *s = n->children[0]->str_val;
            int slen = (int)strlen(s);
            int sz = n->array_size > 0 ? n->array_size : (slen + 1);
            if (sz < slen + 1) sz = slen + 1;
            init.type = VAL_ARRAY;
            init.v.arr.len = sz;
            init.v.arr.cap = sz;
            init.v.arr.elem_type = VAL_CHAR;
            init.v.arr.n_dims = 0;
            init.v.arr.data = (OccValue *)calloc(sz, sizeof(OccValue));
            for (int i = 0; i < sz; i++) {
                init.v.arr.data[i] = make_char(i < slen ? s[i] : '\0');
            }
            scope_set(I, I->current_scope, n->name, init);
            if (n->is_static && I->n_statics < 256) {
                int si = I->n_statics++;
                strncpy(I->statics[si].func, I->current_func, 127);
                strncpy(I->statics[si].var, n->name, 127);
                I->statics[si].val = init;
                I->statics[si].init = 1;
            }
            break;
        }
        if (n->is_array) {
            int sz = n->array_size > 0 ? n->array_size : 16;
            if (n->children[0] && n->children[0]->type == ND_ARRAY_INIT)
                sz = n->children[0]->n_stmts > sz ? n->children[0]->n_stmts : sz;
            init.type = VAL_ARRAY;
            init.v.arr.len = sz;
            init.v.arr.cap = sz;
            init.v.arr.elem_type = n->val_type;
            /* Store multi-dimensional info */
            int nd = (int)n->num_val;
            init.v.arr.n_dims = nd > 0 ? nd : 0;
            for (int d = 0; d < 4; d++) init.v.arr.dims[d] = (unsigned char)n->str_val[d];
            init.v.arr.data = (OccValue *)calloc(sz, sizeof(OccValue));
            if (n->children[0] && n->children[0]->type == ND_ARRAY_INIT) {
                for (int i = 0; i < n->children[0]->n_stmts && i < sz; i++)
                    init.v.arr.data[i] = eval_node(I, n->children[0]->stmts[i]);
            }
        } else if (n->val_type == VAL_FUNCPTR) {
            if (n->children[0]) {
                OccValue rhs = eval_node(I, n->children[0]);
                if (rhs.type == VAL_FUNCPTR) init = rhs;
                else if (rhs.type == VAL_STRING) init = make_funcptr(rhs.v.s);
                else init = make_funcptr("");
            } else {
                init = make_funcptr("");
            }
        } else if (n->children[0]) {
            init = eval_node(I, n->children[0]);
        } else {
            switch (n->val_type) {
                case VAL_FLOAT: case VAL_DOUBLE: init = make_float(0); break;
                case VAL_CHAR: init = make_char(0); break;
                case VAL_STRING: init = make_string(""); break;
                case VAL_PTR: init = make_ptr(0, VAL_VOID, 1); break;
                default: init = make_int(0); break;
            }
        }
        scope_set(I, I->current_scope, n->name, init);
        /* Record static if needed */
        if (n->is_static && I->n_statics < 256) {
            int si = I->n_statics++;
            strncpy(I->statics[si].func, I->current_func, 127);
            strncpy(I->statics[si].var, n->name, 127);
            I->statics[si].val = init;
            I->statics[si].init = 1;
        }
        break;
    }

    case ND_IF: {
        OccValue cond = eval_node(I, n->children[0]);
        if (val_to_bool(cond))
            exec_node(I, n->children[1]);
        else if (n->children[2])
            exec_node(I, n->children[2]);
        break;
    }

    case ND_WHILE: {
        int limit = 1000000;
        while (--limit > 0 && val_to_bool(eval_node(I, n->children[0]))) {
            exec_node(I, n->children[1]);
            if (I->breaking) { I->breaking = 0; break; }
            if (I->continuing) { I->continuing = 0; continue; }
            if (I->returning) break;
        }
        break;
    }

    case ND_DOWHILE: {
        int limit = 1000000;
        do {
            exec_node(I, n->children[0]);
            if (I->breaking) { I->breaking = 0; break; }
            if (I->continuing) { I->continuing = 0; continue; }
            if (I->returning) break;
        } while (--limit > 0 && val_to_bool(eval_node(I, n->children[1])));
        break;
    }

    case ND_FOR: {
        OccScope *for_scope = scope_create(I->current_scope);
        OccScope *saved = I->current_scope;
        I->current_scope = for_scope;
        if (n->children[0]) exec_node(I, n->children[0]);
        int limit = 1000000;
        while (--limit > 0) {
            if (n->children[1] && !val_to_bool(eval_node(I, n->children[1]))) break;
            exec_node(I, n->children[3]);
            if (I->breaking) { I->breaking = 0; break; }
            if (I->continuing) { I->continuing = 0; }
            if (I->returning) break;
            if (n->children[2]) eval_node(I, n->children[2]);
        }
        I->current_scope = saved;
        scope_destroy(for_scope);
        break;
    }

    case ND_SWITCH: {
        OccValue sw = eval_node(I, n->children[0]);
        long long sv = val_to_int(sw);
        int matched = 0, found_default = -1;
        for (int i = 0; i < n->n_stmts; i++) {
            OccNode *c = n->stmts[i];
            if (c->type == ND_DEFAULT) { found_default = i; continue; }
            if (c->type == ND_CASE) {
                long long cv = (long long)eval_node(I, c->children[0]).v.i;
                if (cv == sv || matched) {
                    matched = 1;
                    for (int j = 0; j < c->n_stmts; j++) {
                        exec_node(I, c->stmts[j]);
                        if (I->breaking) { I->breaking = 0; goto switch_done; }
                        if (I->returning) goto switch_done;
                    }
                }
            }
        }
        if (!matched && found_default >= 0) {
            OccNode *c = n->stmts[found_default];
            for (int j = 0; j < c->n_stmts; j++) {
                exec_node(I, c->stmts[j]);
                if (I->breaking) { I->breaking = 0; break; }
                if (I->returning) break;
            }
        }
        switch_done: break;
    }

    case ND_RETURN:
        I->return_val = n->children[0] ? eval_node(I, n->children[0]) : make_void();
        I->returning = 1;
        break;

    case ND_BREAK: I->breaking = 1; break;
    case ND_CONTINUE: I->continuing = 1; break;

    case ND_EXPR_STMT:
        if (n->children[0]) eval_node(I, n->children[0]);
        break;

    /* Goto: set target and flag */
    case ND_GOTO:
        strncpy(I->goto_target, n->label, 63);
        I->goto_active = 1;
        break;

    /* C11/C23 _Static_assert: evaluate condition, error if false */
    case ND_STATIC_ASSERT: {
        OccValue cond = eval_node(I, n->children[0]);
        if (!val_to_bool(cond)) {
            if (n->str_val[0])
                occ_error(I, "Static assertion failed: %s", n->str_val);
            else
                occ_error(I, "Static assertion failed");
        }
        break;
    }

    /* Label: check if this is the goto target */
    case ND_LABEL:
        if (I->goto_active && strcmp(I->goto_target, n->label) == 0) {
            I->goto_active = 0;
            I->goto_target[0] = '\0';
        }
        if (!I->goto_active && n->children[0]) {
            exec_node(I, n->children[0]);
        }
        break;

    default: break;
    }
}

/* ══════════════════════════════════════════════
 *  Public API
 * ══════════════════════════════════════════════ */

OccInterpreter *occ_create(void) {
    OccInterpreter *I = (OccInterpreter *)calloc(1, sizeof(OccInterpreter));
    I->global_scope = scope_create(NULL);
    I->current_scope = I->global_scope;
    vmem_init(I);
    return I;
}

void occ_destroy(OccInterpreter *I) {
    if (!I) return;
    scope_destroy(I->global_scope);
    if (I->vmem) free(I->vmem);
    /* Note: AST nodes are leaked for simplicity. In production, walk and free. */
    free(I);
}

void occ_reset(OccInterpreter *I) {
    I->output[0] = '\0';
    I->out_len = 0;
    I->error[0] = '\0';
    I->has_error = 0;
    I->returning = 0;
    I->breaking = 0;
    I->continuing = 0;
    I->return_val = make_void();
    /* Clear global scope */
    scope_destroy(I->global_scope);
    I->global_scope = scope_create(NULL);
    I->current_scope = I->global_scope;
    /* Clear function table */
    I->n_funcs = 0;
    /* Clear tokens */
    I->n_tokens = 0;
    I->tok_pos = 0;
    I->ast = NULL;
    /* Clear defines, enums, heap */
    I->n_defines = 0;
    I->n_enum_vals = 0;
    for (int i = 0; i < I->n_heap_blocks; i++) {
        if (I->heap_blocks[i].data) free(I->heap_blocks[i].data);
    }
    I->n_heap_blocks = 0;
    I->next_heap_id = 0;
    I->n_struct_types = 0;
    I->n_typedefs = 0;
    /* Reset vmem */
    if (I->vmem) {
        memset(I->vmem, 0, I->vmem_size * sizeof(OccValue));
        I->vmem_used = 1; /* 0 = NULL */
    }
    /* Clear statics */
    I->n_statics = 0;
    /* Clear goto state */
    I->goto_target[0] = '\0';
    I->goto_active = 0;
    /* Clear current function */
    I->current_func[0] = '\0';
    /* Clear function-like macros */
    I->n_func_macros = 0;
}

int occ_execute(OccInterpreter *I, const char *source) {
    occ_reset(I);
    I->source = source;

    if (setjmp(I->err_jmp) != 0) {
        return -1;
    }

    /* Tokenize */
    tokenize(I, source);
    I->tok_pos = 0;

    /* Parse */
    I->ast = parse_program(I);

    /* First pass: register functions AND execute global declarations */
    for (int i = 0; i < I->ast->n_stmts; i++) {
        OccNodeType st = I->ast->stmts[i]->type;
        if (st == ND_FUNCDECL || st == ND_VARDECL || st == ND_BLOCK || st == ND_STATIC_ASSERT) {
            exec_node(I, I->ast->stmts[i]);
        }
    }

    /* Check for main() */
    int has_main = 0;
    for (int i = 0; i < I->n_funcs; i++) {
        if (strcmp(I->funcs[i].name, "main") == 0) { has_main = 1; break; }
    }

    if (has_main) {
        for (int i = 0; i < I->n_funcs; i++) {
            if (strcmp(I->funcs[i].name, "main") == 0) {
                OccNode *fn = I->funcs[i].node;
                OccScope *fn_scope = scope_create(I->global_scope);
                OccScope *saved = I->current_scope;
                strncpy(I->current_func, "main", 127);
                I->current_scope = fn_scope;
                I->returning = 0;
                if (fn->children[0]) exec_node(I, fn->children[0]);
                I->current_scope = saved;
                sync_statics(I, fn_scope);
                I->current_func[0] = '\0';
                scope_destroy(fn_scope);
                break;
            }
        }
    } else {
        for (int i = 0; i < I->ast->n_stmts; i++) {
            if (I->ast->stmts[i]->type != ND_FUNCDECL)
                exec_node(I, I->ast->stmts[i]);
            if (I->returning) break;
        }
    }

    return 0;
}

const char *occ_get_output(OccInterpreter *I) { return I->output; }
const char *occ_get_error(OccInterpreter *I) { return I->error; }
