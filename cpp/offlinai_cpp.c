/*
 * OfflinAi C++ Interpreter — single-file implementation.
 * Lexer -> Parser -> Tree-walking interpreter.
 *
 * Supports: classes, single inheritance, virtual dispatch, templates,
 *           lambdas, references, namespaces, try/catch/throw,
 *           new/delete, operator overloading, range-for,
 *           std::string, std::vector, std::map, std::pair,
 *           cout/cin, auto type deduction, and most C features.
 */

#include "offlinai_cpp.h"
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
 *  Internal types
 * ══════════════════════════════════════════════ */

typedef struct {
    char name[256];
    OcppValue val;
    int is_const;
    int is_reference;
    OcppValue *ref_target;    /* if is_reference, points to original */
    int vmem_addr;
} OcppVar;

typedef struct OcppScope {
    OcppVar vars[OCPP_MAX_VARS];
    int n_vars;
    struct OcppScope *parent;
} OcppScope;

typedef struct {
    char name[256];
    OcppNode *node;
    char class_name[64];     /* "" for free functions */
} OcppFunc;

/* Class method info */
typedef struct {
    char name[64];
    OcppNode *node;
    int is_virtual;
    int access;  /* 0=public,1=private,2=protected */
} OcppMethod;

/* Class definition */
typedef struct {
    char name[64];
    char base_class[64];
    /* fields */
    char field_names[OCPP_MAX_FIELDS][64];
    OcppValType field_types[OCPP_MAX_FIELDS];
    int field_access[OCPP_MAX_FIELDS];
    OcppNode *field_inits[OCPP_MAX_FIELDS];
    int n_fields;
    /* methods */
    OcppMethod methods[OCPP_MAX_METHODS];
    int n_methods;
    /* constructor / destructor */
    OcppNode *constructor;
    OcppNode *destructor;
    /* operator overloads */
    struct { int op; OcppNode *node; } operators[16];
    int n_operators;
} OcppClassDef;

/* Template definition (stored as AST) */
typedef struct {
    char name[64];
    char type_param[64];
    OcppNode *node;
} OcppTemplateDef;

/* Thrown exception value */
typedef struct {
    OcppValue value;
    char type_name[64];
    int active;
} OcppException;

/* ── Interpreter state ── */
struct OcppInterpreter {
    /* output */
    char output[OCPP_MAX_OUTPUT];
    int out_len;
    char error[4096];
    /* tokens */
    OcppToken tokens[OCPP_MAX_TOKENS];
    int n_tokens;
    int tok_pos;
    /* AST */
    OcppNode *ast;
    /* runtime */
    OcppScope *global_scope;
    OcppScope *current_scope;
    OcppFunc funcs[OCPP_MAX_FUNCS];
    int n_funcs;
    /* classes */
    OcppClassDef classes[OCPP_MAX_CLASSES];
    int n_classes;
    /* templates */
    OcppTemplateDef templates[OCPP_MAX_TEMPLATES];
    int n_templates;
    /* control flow */
    int returning;
    OcppValue return_val;
    int breaking;
    int continuing;
    /* error recovery */
    jmp_buf err_jmp;
    int has_error;
    /* exception handling */
    OcppException cur_exception;
    jmp_buf catch_jmp[OCPP_MAX_STACK];
    int catch_depth;
    /* source for error reporting */
    const char *source;
    /* preprocessor defines */
    struct { char name[128]; char value[256]; } defines[256];
    int n_defines;
    /* enum tracking */
    struct { char name[128]; long long value; } enum_vals[256];
    int n_enum_vals;
    /* include flags */
    int has_iostream;
    int has_string;
    int has_vector;
    int has_map;
    int has_algorithm;
    int has_utility;
    int using_namespace_std;
    /* struct type definitions (C-style) */
    struct {
        char name[128];
        char field_names[32][64];
        OcppValType field_types[32];
        int n_fields;
    } struct_types[64];
    int n_struct_types;
    /* typedef aliases */
    struct { char alias[128]; char original[128]; } typedefs[64];
    int n_typedefs;
    /* virtual memory */
    OcppValue *vmem;
    int vmem_size;
    int vmem_used;
    /* this pointer stack */
    OcppValue *this_stack[OCPP_MAX_STACK];
    int this_depth;
    /* current class context for method calls */
    char current_class[64];
    /* namespace tracking */
    char namespaces[OCPP_MAX_NS][64];
    int n_namespaces;
    /* node pool */
    OcppNode **node_pool;
    int node_pool_count;
    int node_pool_cap;
};

/* ── Forward declarations ────────────────────── */
static void ocpp_error(OcppInterpreter *I, const char *fmt, ...);
static OcppValue eval_node(OcppInterpreter *I, OcppNode *n);
static void exec_node(OcppInterpreter *I, OcppNode *n);
static OcppValue call_function(OcppInterpreter *I, const char *name, OcppValue *args, int nargs);
static OcppValue call_method(OcppInterpreter *I, OcppValue *obj, const char *method, OcppValue *args, int nargs);
static OcppValue call_stl_func(OcppInterpreter *I, const char *name, OcppValue *args, int nargs);
static OcppClassDef *find_class(OcppInterpreter *I, const char *name);
static OcppValue create_object(OcppInterpreter *I, const char *class_name, OcppValue *args, int nargs);
static OcppValue string_method(OcppInterpreter *I, OcppValue *str, const char *method, OcppValue *args, int nargs);
static OcppValue vector_method(OcppInterpreter *I, OcppValue *vec, const char *method, OcppValue *args, int nargs);
static OcppValue map_method(OcppInterpreter *I, OcppValue *mp, const char *method, OcppValue *args, int nargs);

/* ── Helpers ─────────────────────────────────── */

static void out_append(OcppInterpreter *I, const char *s) {
    int len = (int)strlen(s);
    if (I->out_len + len >= OCPP_MAX_OUTPUT - 1) len = OCPP_MAX_OUTPUT - 1 - I->out_len;
    if (len > 0) { memcpy(I->output + I->out_len, s, len); I->out_len += len; }
    I->output[I->out_len] = '\0';
}

static void out_appendf(OcppInterpreter *I, const char *fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    out_append(I, buf);
}

static void ocpp_error(OcppInterpreter *I, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(I->error, sizeof(I->error), fmt, ap);
    va_end(ap);
    I->has_error = 1;
    longjmp(I->err_jmp, 1);
}

/* ── Value constructors ── */

static OcppValue make_int(long long v) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_INT; r.v.i = v; return r; }
static OcppValue make_float(double v) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_DOUBLE; r.v.f = v; return r; }
static OcppValue make_char(char c) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_CHAR; r.v.c = c; return r; }
static OcppValue make_bool(int b) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_BOOL; r.v.b = b ? 1 : 0; return r; }
static OcppValue make_void(void) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_VOID; return r; }
static OcppValue make_nullptr_val(void) { OcppValue r; memset(&r,0,sizeof(r)); r.type = CVAL_NULLPTR; return r; }

static OcppValue make_string(const char *s) {
    OcppValue r; memset(&r,0,sizeof(r));
    r.type = CVAL_STRING;
    r.v.s = strdup(s ? s : "");
    return r;
}

static OcppValue make_ptr(int addr, OcppValType pointee, int stride) {
    OcppValue r; memset(&r,0,sizeof(r));
    r.type = CVAL_PTR;
    r.v.ptr.addr = addr;
    r.v.ptr.pointee_type = pointee;
    r.v.ptr.stride = stride > 0 ? stride : 1;
    return r;
}

static OcppValue make_vector(OcppValType elem_type) {
    OcppValue r; memset(&r,0,sizeof(r));
    r.type = CVAL_VECTOR;
    r.v.vec.elem_type = elem_type;
    r.v.vec.cap = 8;
    r.v.vec.len = 0;
    r.v.vec.data = (OcppValue *)calloc(8, sizeof(OcppValue));
    return r;
}

static OcppValue make_map(OcppValType kt, OcppValType vt) {
    OcppValue r; memset(&r,0,sizeof(r));
    r.type = CVAL_MAP;
    r.v.map.key_type = kt;
    r.v.map.val_type = vt;
    r.v.map.cap = 8;
    r.v.map.len = 0;
    r.v.map.keys = (OcppValue *)calloc(8, sizeof(OcppValue));
    r.v.map.vals = (OcppValue *)calloc(8, sizeof(OcppValue));
    return r;
}

static OcppValue make_pair(OcppValue a, OcppValue b) {
    OcppValue r; memset(&r,0,sizeof(r));
    r.type = CVAL_PAIR;
    r.v.pair.first = (OcppValue *)malloc(sizeof(OcppValue));
    r.v.pair.second = (OcppValue *)malloc(sizeof(OcppValue));
    *r.v.pair.first = a;
    *r.v.pair.second = b;
    return r;
}

/* ── Type conversion helpers ── */

static double val_to_double(OcppValue v) {
    switch (v.type) {
        case CVAL_INT: return (double)v.v.i;
        case CVAL_FLOAT: case CVAL_DOUBLE: return v.v.f;
        case CVAL_CHAR: return (double)v.v.c;
        case CVAL_BOOL: return (double)v.v.b;
        case CVAL_PTR: return (double)v.v.ptr.addr;
        default: return 0.0;
    }
}

static long long val_to_int(OcppValue v) {
    switch (v.type) {
        case CVAL_INT: return v.v.i;
        case CVAL_FLOAT: case CVAL_DOUBLE: return (long long)v.v.f;
        case CVAL_CHAR: return (long long)v.v.c;
        case CVAL_BOOL: return (long long)v.v.b;
        case CVAL_PTR: return (long long)v.v.ptr.addr;
        default: return 0;
    }
}

static int val_to_bool(OcppValue v) {
    switch (v.type) {
        case CVAL_INT: return v.v.i != 0;
        case CVAL_FLOAT: case CVAL_DOUBLE: return v.v.f != 0.0;
        case CVAL_CHAR: return v.v.c != 0;
        case CVAL_BOOL: return v.v.b;
        case CVAL_STRING: return v.v.s && v.v.s[0];
        case CVAL_PTR: return v.v.ptr.addr != 0;
        case CVAL_NULLPTR: return 0;
        case CVAL_VECTOR: return v.v.vec.len > 0;
        default: return 0;
    }
}

static const char *val_to_str(OcppValue v, char *buf, int bufsz) {
    switch (v.type) {
        case CVAL_INT: snprintf(buf, bufsz, "%lld", v.v.i); break;
        case CVAL_FLOAT: case CVAL_DOUBLE: snprintf(buf, bufsz, "%g", v.v.f); break;
        case CVAL_CHAR: snprintf(buf, bufsz, "%c", v.v.c); break;
        case CVAL_BOOL: snprintf(buf, bufsz, "%s", v.v.b ? "true" : "false"); break;  /* changed: was 1/0, now true/false */
        case CVAL_STRING: return v.v.s ? v.v.s : "";
        case CVAL_NULLPTR: snprintf(buf, bufsz, "nullptr"); break;
        default: buf[0] = '\0'; break;
    }
    return buf;
}

static int is_numeric(OcppValue v) {
    return v.type == CVAL_INT || v.type == CVAL_FLOAT || v.type == CVAL_DOUBLE ||
           v.type == CVAL_CHAR || v.type == CVAL_BOOL;
}

static OcppValue value_deep_copy(OcppValue v) {
    OcppValue r = v;
    if (v.type == CVAL_STRING && v.v.s) {
        r.v.s = strdup(v.v.s);
    } else if (v.type == CVAL_VECTOR && v.v.vec.data) {
        r.v.vec.data = (OcppValue *)calloc(v.v.vec.cap, sizeof(OcppValue));
        for (int i = 0; i < v.v.vec.len; i++)
            r.v.vec.data[i] = value_deep_copy(v.v.vec.data[i]);
    } else if (v.type == CVAL_MAP && v.v.map.keys) {
        r.v.map.keys = (OcppValue *)calloc(v.v.map.cap, sizeof(OcppValue));
        r.v.map.vals = (OcppValue *)calloc(v.v.map.cap, sizeof(OcppValue));
        for (int i = 0; i < v.v.map.len; i++) {
            r.v.map.keys[i] = value_deep_copy(v.v.map.keys[i]);
            r.v.map.vals[i] = value_deep_copy(v.v.map.vals[i]);
        }
    } else if (v.type == CVAL_PAIR) {
        r.v.pair.first = (OcppValue *)malloc(sizeof(OcppValue));
        r.v.pair.second = (OcppValue *)malloc(sizeof(OcppValue));
        *r.v.pair.first = value_deep_copy(*v.v.pair.first);
        *r.v.pair.second = value_deep_copy(*v.v.pair.second);
    } else if (v.type == CVAL_OBJECT && v.v.obj.fields) {
        int nf = v.v.obj.n_fields;
        r.v.obj.fields = (OcppValue *)calloc(nf, sizeof(OcppValue));
        r.v.obj.field_names = (char (*)[64])calloc(nf, 64);
        for (int i = 0; i < nf; i++) {
            r.v.obj.fields[i] = value_deep_copy(v.v.obj.fields[i]);
            memcpy(r.v.obj.field_names[i], v.v.obj.field_names[i], 64);
        }
    }
    return r;
}

/* ══════════════════════════════════════════════
 *  Virtual Memory System
 * ══════════════════════════════════════════════ */

static void vmem_init(OcppInterpreter *I) {
    I->vmem = (OcppValue *)calloc(OCPP_VMEM_SIZE, sizeof(OcppValue));
    I->vmem_size = OCPP_VMEM_SIZE;
    I->vmem_used = 1; /* 0 = NULL */
}

static int vmem_alloc(OcppInterpreter *I, int n) {
    if (n <= 0) n = 1;
    if (I->vmem_used + n > I->vmem_size) return 0;
    int addr = I->vmem_used;
    I->vmem_used += n;
    return addr;
}

static OcppValue *vmem_get(OcppInterpreter *I, int addr) {
    if (addr <= 0 || addr >= I->vmem_size) return NULL;
    return &I->vmem[addr];
}

/* ══════════════════════════════════════════════
 *  Scope / Variable Management
 * ══════════════════════════════════════════════ */

static OcppScope *scope_create(OcppScope *parent) {
    OcppScope *s = (OcppScope *)calloc(1, sizeof(OcppScope));
    s->parent = parent;
    return s;
}

static void scope_destroy(OcppScope *s) {
    if (!s) return;
    for (int i = 0; i < s->n_vars; i++) {
        if (s->vars[i].val.type == CVAL_STRING && s->vars[i].val.v.s)
            free(s->vars[i].val.v.s);
    }
    free(s);
}

static OcppVar *scope_find(OcppScope *s, const char *name) {
    while (s) {
        for (int i = 0; i < s->n_vars; i++)
            if (strcmp(s->vars[i].name, name) == 0) return &s->vars[i];
        s = s->parent;
    }
    return NULL;
}

static OcppVar *scope_set(OcppInterpreter *I, OcppScope *s, const char *name, OcppValue val) {
    for (int i = 0; i < s->n_vars; i++) {
        if (strcmp(s->vars[i].name, name) == 0) {
            if (s->vars[i].is_reference && s->vars[i].ref_target) {
                *s->vars[i].ref_target = val;
            } else {
                s->vars[i].val = val;
            }
            return &s->vars[i];
        }
    }
    if (s->n_vars >= OCPP_MAX_VARS) ocpp_error(I, "Too many variables");
    OcppVar *v = &s->vars[s->n_vars++];
    strncpy(v->name, name, 255);
    v->val = val;
    v->is_const = 0;
    v->is_reference = 0;
    v->ref_target = NULL;
    v->vmem_addr = 0;
    return v;
}

static OcppVar *scope_get_var(OcppInterpreter *I, const char *name) {
    OcppVar *v = scope_find(I->current_scope, name);
    if (!v) ocpp_error(I, "Undefined variable '%s'", name);
    return v;
}

/* ══════════════════════════════════════════════
 *  Node pool
 * ══════════════════════════════════════════════ */

static OcppNode *alloc_node(OcppInterpreter *I, OcppNodeType type) {
    OcppNode *n = (OcppNode *)calloc(1, sizeof(OcppNode));
    n->type = type;
    /* track for cleanup */
    if (I->node_pool_count >= I->node_pool_cap) {
        I->node_pool_cap = I->node_pool_cap ? I->node_pool_cap * 2 : 256;
        I->node_pool = (OcppNode **)realloc(I->node_pool, I->node_pool_cap * sizeof(OcppNode *));
    }
    I->node_pool[I->node_pool_count++] = n;
    return n;
}

/* ══════════════════════════════════════════════
 *  Lexer
 * ══════════════════════════════════════════════ */

static int is_ident_char(char c) { return isalnum((unsigned char)c) || c == '_'; }

static void skip_whitespace_and_comments(const char **p, int *line) {
    while (**p) {
        if (**p == '\n') { (*line)++; (*p)++; }
        else if (isspace((unsigned char)**p)) { (*p)++; }
        else if ((*p)[0] == '/' && (*p)[1] == '/') {
            (*p) += 2;
            while (**p && **p != '\n') (*p)++;
        } else if ((*p)[0] == '/' && (*p)[1] == '*') {
            (*p) += 2;
            while (**p && !((*p)[0] == '*' && (*p)[1] == '/')) {
                if (**p == '\n') (*line)++;
                (*p)++;
            }
            if (**p) (*p) += 2;
        } else break;
    }
}

typedef struct { const char *word; OcppTokenType tok; } KeywordEntry;

static const KeywordEntry cpp_keywords[] = {
    /* C type keywords */
    {"int", CTOK_INT}, {"float", CTOK_FLOAT}, {"double", CTOK_DOUBLE},
    {"char", CTOK_CHAR}, {"void", CTOK_VOID},
    {"long", CTOK_LONG}, {"short", CTOK_SHORT},
    {"unsigned", CTOK_UNSIGNED}, {"signed", CTOK_SIGNED}, {"const", CTOK_CONST},
    /* C control */
    {"if", CTOK_IF}, {"else", CTOK_ELSE}, {"for", CTOK_FOR},
    {"while", CTOK_WHILE}, {"do", CTOK_DO},
    {"return", CTOK_RETURN}, {"break", CTOK_BREAK}, {"continue", CTOK_CONTINUE},
    {"switch", CTOK_SWITCH}, {"case", CTOK_CASE}, {"default", CTOK_DEFAULT},
    /* C misc */
    {"struct", CTOK_STRUCT}, {"typedef", CTOK_TYPEDEF}, {"sizeof", CTOK_SIZEOF},
    {"enum", CTOK_ENUM}, {"static", CTOK_STATIC}, {"union", CTOK_UNION},
    {"goto", CTOK_GOTO},
    /* C++ keywords */
    {"class", CTOK_CLASS}, {"public", CTOK_PUBLIC}, {"private", CTOK_PRIVATE},
    {"protected", CTOK_PROTECTED}, {"new", CTOK_NEW}, {"delete", CTOK_DELETE},
    {"this", CTOK_THIS}, {"virtual", CTOK_VIRTUAL}, {"override", CTOK_OVERRIDE},
    {"namespace", CTOK_NAMESPACE}, {"using", CTOK_USING},
    {"template", CTOK_TEMPLATE}, {"typename", CTOK_TYPENAME},
    {"auto", CTOK_AUTO}, {"try", CTOK_TRY}, {"catch", CTOK_CATCH},
    {"throw", CTOK_THROW}, {"nullptr", CTOK_NULLPTR}, {"bool", CTOK_BOOL},
    {"operator", CTOK_OPERATOR},
    /* bool literals */
    {"true", CTOK_BOOL_LIT}, {"false", CTOK_BOOL_LIT},
    /* STL identifiers recognized as tokens after using namespace std */
    {"endl", CTOK_ENDL}, {"cout", CTOK_COUT}, {"cin", CTOK_CIN},
    {"string", CTOK_STRING_TYPE},
    {NULL, CTOK_EOF}
};

static void tokenize(OcppInterpreter *I, const char *src) {
    const char *p = src;
    int line = 1;
    I->n_tokens = 0;

    while (1) {
        skip_whitespace_and_comments(&p, &line);
        if (!*p) break;
        if (I->n_tokens >= OCPP_MAX_TOKENS - 1) ocpp_error(I, "Too many tokens");

        OcppToken *t = &I->tokens[I->n_tokens];
        t->start = p;
        t->line = line;
        t->num_val = 0;
        t->bool_val = 0;

        /* Preprocessor: #include, #define */
        if (*p == '#') {
            p++;
            while (*p == ' ' || *p == '\t') p++;
            const char *dir_start = p;
            while (isalpha((unsigned char)*p)) p++;
            int dir_len = (int)(p - dir_start);

            if (dir_len == 7 && strncmp(dir_start, "include", 7) == 0) {
                while (*p == ' ' || *p == '\t') p++;
                char delim = *p;
                if (delim == '<' || delim == '"') {
                    char end_delim = (delim == '<') ? '>' : '"';
                    p++;
                    const char *inc_start = p;
                    while (*p && *p != end_delim && *p != '\n') p++;
                    int inc_len = (int)(p - inc_start);
                    if (*p == end_delim) p++;

                    /* Set include flags */
                    if (inc_len >= 8 && strncmp(inc_start, "iostream", 8) == 0)
                        I->has_iostream = 1;
                    else if (inc_len >= 6 && strncmp(inc_start, "string", 6) == 0)
                        I->has_string = 1;
                    else if (inc_len >= 6 && strncmp(inc_start, "vector", 6) == 0)
                        I->has_vector = 1;
                    else if (inc_len >= 3 && strncmp(inc_start, "map", 3) == 0)
                        I->has_map = 1;
                    else if (inc_len >= 9 && strncmp(inc_start, "algorithm", 9) == 0)
                        I->has_algorithm = 1;
                    else if (inc_len >= 7 && strncmp(inc_start, "utility", 7) == 0)
                        I->has_utility = 1;
                    /* Also handle stdio.h, math.h, etc. for C compat */
                }
                t->type = CTOK_INCLUDE;
                t->length = (int)(p - t->start);
                I->n_tokens++;
                continue;
            } else if (dir_len == 6 && strncmp(dir_start, "define", 6) == 0) {
                while (*p == ' ' || *p == '\t') p++;
                const char *name_start = p;
                while (is_ident_char(*p)) p++;
                int name_len = (int)(p - name_start);
                while (*p == ' ' || *p == '\t') p++;
                const char *val_start = p;
                while (*p && *p != '\n') p++;
                int val_len = (int)(p - val_start);
                /* Store define */
                if (I->n_defines < 256 && name_len < 128 && val_len < 256) {
                    strncpy(I->defines[I->n_defines].name, name_start, name_len);
                    I->defines[I->n_defines].name[name_len] = '\0';
                    strncpy(I->defines[I->n_defines].value, val_start, val_len);
                    I->defines[I->n_defines].value[val_len] = '\0';
                    I->n_defines++;
                }
                t->type = CTOK_DEFINE;
                t->length = (int)(p - t->start);
                I->n_tokens++;
                continue;
            }
            t->type = CTOK_HASH;
            t->length = 1;
            I->n_tokens++;
            continue;
        }

        /* Number literal */
        if (isdigit((unsigned char)*p) || (*p == '.' && isdigit((unsigned char)p[1]))) {
            const char *start = p;
            int is_float_num = 0;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
                p += 2;
                while (isxdigit((unsigned char)*p)) p++;
                t->num_val = (double)strtoll(start, NULL, 16);
            } else {
                while (isdigit((unsigned char)*p)) p++;
                if (*p == '.') { is_float_num = 1; p++; while (isdigit((unsigned char)*p)) p++; }
                if (*p == 'e' || *p == 'E') {
                    is_float_num = 1; p++;
                    if (*p == '+' || *p == '-') p++;
                    while (isdigit((unsigned char)*p)) p++;
                }
                t->num_val = strtod(start, NULL);
            }
            if (*p == 'f' || *p == 'F') { is_float_num = 1; p++; }
            else if (*p == 'l' || *p == 'L') p++;
            else if (*p == 'u' || *p == 'U') p++;

            t->type = is_float_num ? CTOK_FLOAT_LIT : CTOK_INT_LIT;
            t->length = (int)(p - start);
            I->n_tokens++;
            continue;
        }

        /* String literal */
        if (*p == '"') {
            const char *start = p;
            p++;
            while (*p && *p != '"') {
                if (*p == '\\') p++;
                if (*p) p++;
            }
            if (*p == '"') p++;
            t->type = CTOK_STRING_LIT;
            t->length = (int)(p - start);
            I->n_tokens++;
            continue;
        }

        /* Char literal */
        if (*p == '\'') {
            const char *start = p;
            p++;
            if (*p == '\\') { p++; if (*p) p++; }
            else if (*p) p++;
            if (*p == '\'') p++;
            t->type = CTOK_CHAR_LIT;
            t->length = (int)(p - start);
            I->n_tokens++;
            continue;
        }

        /* Identifier or keyword */
        if (isalpha((unsigned char)*p) || *p == '_') {
            const char *start = p;
            while (is_ident_char(*p)) p++;
            int len = (int)(p - start);
            t->length = len;

            /* Check for std:: prefix — resolve to STL token */
            if (len == 3 && strncmp(start, "std", 3) == 0 && p[0] == ':' && p[1] == ':') {
                /* peek at what follows std:: */
                const char *after = p + 2;
                const char *id_start = after;
                while (is_ident_char(*after)) after++;
                int id_len = (int)(after - id_start);
                if (id_len == 4 && strncmp(id_start, "cout", 4) == 0) {
                    t->type = CTOK_COUT; t->length = (int)(after - start); p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 3 && strncmp(id_start, "cin", 3) == 0) {
                    t->type = CTOK_CIN; t->length = (int)(after - start); p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 4 && strncmp(id_start, "endl", 4) == 0) {
                    t->type = CTOK_ENDL; t->length = (int)(after - start); p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 6 && strncmp(id_start, "string", 6) == 0) {
                    t->type = CTOK_STRING_TYPE; t->length = (int)(after - start); p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 6 && strncmp(id_start, "vector", 6) == 0) {
                    /* leave as ident — parser handles std::vector<T> */
                    t->type = CTOK_IDENT;
                    t->start = id_start; t->length = id_len; p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 3 && strncmp(id_start, "map", 3) == 0) {
                    t->type = CTOK_IDENT;
                    t->start = id_start; t->length = id_len; p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 4 && strncmp(id_start, "pair", 4) == 0) {
                    t->type = CTOK_IDENT;
                    t->start = id_start; t->length = id_len; p = after;
                    I->n_tokens++; continue;
                } else if (id_len == 4 && strncmp(id_start, "sort", 4) == 0 ||
                           id_len == 4 && strncmp(id_start, "find", 4) == 0 ||
                           id_len == 5 && strncmp(id_start, "count", 5) == 0 ||
                           id_len == 7 && strncmp(id_start, "reverse", 7) == 0 ||
                           id_len == 3 && strncmp(id_start, "min", 3) == 0 ||
                           id_len == 3 && strncmp(id_start, "max", 3) == 0 ||
                           id_len == 9 && strncmp(id_start, "make_pair", 9) == 0 ||
                           id_len == 4 && strncmp(id_start, "swap", 4) == 0) {
                    t->type = CTOK_IDENT;
                    t->start = id_start; t->length = id_len; p = after;
                    I->n_tokens++; continue;
                }
                /* Unknown std:: identifier — just make it an ident with the name after :: */
                t->type = CTOK_IDENT;
                t->start = id_start; t->length = id_len; p = after;
                I->n_tokens++; continue;
            }

            /* Check keywords */
            int found = 0;
            for (int k = 0; cpp_keywords[k].word; k++) {
                int klen = (int)strlen(cpp_keywords[k].word);
                if (klen == len && strncmp(start, cpp_keywords[k].word, len) == 0) {
                    t->type = cpp_keywords[k].tok;
                    if (t->type == CTOK_BOOL_LIT) {
                        t->bool_val = (start[0] == 't') ? 1 : 0;
                    }
                    /* STL names only as keywords if using_namespace_std */
                    if ((t->type == CTOK_COUT || t->type == CTOK_CIN ||
                         t->type == CTOK_ENDL || t->type == CTOK_STRING_TYPE) &&
                        !I->using_namespace_std) {
                        t->type = CTOK_IDENT;
                    }
                    found = 1;
                    break;
                }
            }
            if (!found) {
                /* Check defines */
                for (int d = 0; d < I->n_defines; d++) {
                    if ((int)strlen(I->defines[d].name) == len &&
                        strncmp(start, I->defines[d].name, len) == 0) {
                        /* Substitute: re-tokenize the define value inline is complex,
                           so just treat as int literal if numeric, else ident */
                        const char *dv = I->defines[d].value;
                        while (*dv == ' ') dv++;
                        if (isdigit((unsigned char)*dv) || (*dv == '-' && isdigit((unsigned char)dv[1]))) {
                            t->type = CTOK_INT_LIT;
                            t->num_val = strtod(dv, NULL);
                        } else {
                            t->type = CTOK_IDENT;
                        }
                        found = 1;
                        break;
                    }
                }
                if (!found) t->type = CTOK_IDENT;
            }
            I->n_tokens++;
            continue;
        }

        /* Operators and punctuation */
        const char *start = p;
        switch (*p) {
            case '+':
                p++;
                if (*p == '+') { t->type = CTOK_INC; p++; }
                else if (*p == '=') { t->type = CTOK_PLUS_ASSIGN; p++; }
                else t->type = CTOK_PLUS;
                break;
            case '-':
                p++;
                if (*p == '-') { t->type = CTOK_DEC; p++; }
                else if (*p == '=') { t->type = CTOK_MINUS_ASSIGN; p++; }
                else if (*p == '>') { t->type = CTOK_ARROW; p++; }
                else t->type = CTOK_MINUS;
                break;
            case '*':
                p++;
                if (*p == '=') { t->type = CTOK_STAR_ASSIGN; p++; }
                else t->type = CTOK_STAR;
                break;
            case '/':
                p++;
                if (*p == '=') { t->type = CTOK_SLASH_ASSIGN; p++; }
                else t->type = CTOK_SLASH;
                break;
            case '%':
                p++;
                if (*p == '=') { t->type = CTOK_PERCENT_ASSIGN; p++; }
                else t->type = CTOK_PERCENT;
                break;
            case '&':
                p++;
                if (*p == '&') { t->type = CTOK_AND; p++; }
                else if (*p == '=') { t->type = CTOK_AMP_ASSIGN; p++; }
                else t->type = CTOK_AMP;
                break;
            case '|':
                p++;
                if (*p == '|') { t->type = CTOK_OR; p++; }
                else if (*p == '=') { t->type = CTOK_PIPE_ASSIGN; p++; }
                else t->type = CTOK_PIPE;
                break;
            case '^':
                p++;
                if (*p == '=') { t->type = CTOK_CARET_ASSIGN; p++; }
                else t->type = CTOK_CARET;
                break;
            case '~': t->type = CTOK_TILDE; p++; break;
            case '!':
                p++;
                if (*p == '=') { t->type = CTOK_NEQ; p++; }
                else t->type = CTOK_BANG;
                break;
            case '=':
                p++;
                if (*p == '=') { t->type = CTOK_EQ; p++; }
                else t->type = CTOK_ASSIGN;
                break;
            case '<':
                p++;
                if (*p == '<') { p++;
                    if (*p == '=') { t->type = CTOK_LSHIFT_ASSIGN; p++; }
                    else t->type = CTOK_LSHIFT;
                } else if (*p == '=') { t->type = CTOK_LE; p++; }
                else t->type = CTOK_LT;
                break;
            case '>':
                p++;
                if (*p == '>') { p++;
                    if (*p == '=') { t->type = CTOK_RSHIFT_ASSIGN; p++; }
                    else t->type = CTOK_RSHIFT;
                } else if (*p == '=') { t->type = CTOK_GE; p++; }
                else t->type = CTOK_GT;
                break;
            case ':':
                p++;
                if (*p == ':') { t->type = CTOK_SCOPE; p++; }
                else t->type = CTOK_COLON;
                break;
            case '.':
                p++;
                if (*p == '.' && p[1] == '.') { t->type = CTOK_ELLIPSIS; p += 2; }
                else t->type = CTOK_DOT;
                break;
            case '(': t->type = CTOK_LPAREN; p++; break;
            case ')': t->type = CTOK_RPAREN; p++; break;
            case '{': t->type = CTOK_LBRACE; p++; break;
            case '}': t->type = CTOK_RBRACE; p++; break;
            case '[': t->type = CTOK_LBRACKET; p++; break;
            case ']': t->type = CTOK_RBRACKET; p++; break;
            case ';': t->type = CTOK_SEMICOLON; p++; break;
            case ',': t->type = CTOK_COMMA; p++; break;
            case '?': t->type = CTOK_QUESTION; p++; break;
            default:
                p++;
                continue; /* skip unknown */
        }
        t->length = (int)(p - start);
        I->n_tokens++;
    }

    /* EOF token */
    OcppToken *eof = &I->tokens[I->n_tokens];
    eof->type = CTOK_EOF;
    eof->start = p;
    eof->length = 0;
    eof->line = line;
    I->n_tokens++;
}

/* ══════════════════════════════════════════════
 *  Parser helpers
 * ══════════════════════════════════════════════ */

static OcppToken *peek(OcppInterpreter *I) {
    return &I->tokens[I->tok_pos];
}

static OcppToken *peek_at(OcppInterpreter *I, int offset) {
    int idx = I->tok_pos + offset;
    if (idx >= I->n_tokens) return &I->tokens[I->n_tokens - 1];
    return &I->tokens[idx];
}

static OcppToken *advance(OcppInterpreter *I) {
    OcppToken *t = &I->tokens[I->tok_pos];
    if (t->type != CTOK_EOF) I->tok_pos++;
    return t;
}

static OcppToken *expect(OcppInterpreter *I, OcppTokenType type) {
    OcppToken *t = peek(I);
    if (t->type != type) {
        ocpp_error(I, "Line %d: expected token %d, got %d", t->line, type, t->type);
    }
    return advance(I);
}

static int match(OcppInterpreter *I, OcppTokenType type) {
    if (peek(I)->type == type) { advance(I); return 1; }
    return 0;
}

static int check(OcppInterpreter *I, OcppTokenType type) {
    return peek(I)->type == type;
}

static void tok_str(OcppToken *t, char *buf, int bufsz) {
    int len = t->length < bufsz - 1 ? t->length : bufsz - 1;
    memcpy(buf, t->start, len);
    buf[len] = '\0';
}

static char unescape_char(char c) {
    switch (c) {
        case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r';
        case '\\': return '\\'; case '\'': return '\''; case '"': return '"';
        case '0': return '\0'; case 'a': return '\a'; case 'b': return '\b';
        default: return c;
    }
}

/* Check if token is a type keyword */
static int is_type_token(OcppTokenType t) {
    return t == CTOK_INT || t == CTOK_FLOAT || t == CTOK_DOUBLE || t == CTOK_CHAR ||
           t == CTOK_VOID || t == CTOK_LONG || t == CTOK_SHORT || t == CTOK_UNSIGNED ||
           t == CTOK_SIGNED || t == CTOK_BOOL || t == CTOK_AUTO || t == CTOK_STRING_TYPE ||
           t == CTOK_CONST || t == CTOK_STRUCT || t == CTOK_CLASS;
}

static OcppValType token_to_valtype(OcppInterpreter *I, OcppTokenType t) {
    switch (t) {
        case CTOK_INT: case CTOK_LONG: case CTOK_SHORT:
        case CTOK_UNSIGNED: case CTOK_SIGNED: return CVAL_INT;
        case CTOK_FLOAT: return CVAL_FLOAT;
        case CTOK_DOUBLE: return CVAL_DOUBLE;
        case CTOK_CHAR: return CVAL_CHAR;
        case CTOK_BOOL: return CVAL_BOOL;
        case CTOK_VOID: return CVAL_VOID;
        case CTOK_STRING_TYPE: return CVAL_STRING;
        case CTOK_AUTO: return CVAL_VOID; /* resolved at eval */
        default: return CVAL_INT;
    }
}

/* ══════════════════════════════════════════════
 *  Parser — declarations
 * ══════════════════════════════════════════════ */

static OcppNode *parse_expr(OcppInterpreter *I);
static OcppNode *parse_assign_expr(OcppInterpreter *I);
static OcppNode *parse_stmt(OcppInterpreter *I);
static OcppNode *parse_block(OcppInterpreter *I);
static OcppNode *parse_declaration(OcppInterpreter *I);
static OcppNode *parse_class_decl(OcppInterpreter *I);

/* ── Expression parsing (precedence climbing) ── */

static OcppNode *parse_primary(OcppInterpreter *I) {
    OcppToken *t = peek(I);

    if (t->type == CTOK_INT_LIT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_INT_LIT);
        n->num_val = t->num_val;
        n->line = t->line;
        return n;
    }
    if (t->type == CTOK_FLOAT_LIT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_FLOAT_LIT);
        n->num_val = t->num_val;
        n->line = t->line;
        return n;
    }
    if (t->type == CTOK_BOOL_LIT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_BOOL_LIT);
        n->num_val = t->bool_val;
        n->line = t->line;
        return n;
    }
    if (t->type == CTOK_NULLPTR) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_NULLPTR_LIT);
        n->line = t->line;
        return n;
    }
    if (t->type == CTOK_STRING_LIT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_STRING_LIT);
        n->line = t->line;
        /* Decode string content */
        const char *s = t->start + 1; /* skip opening quote */
        int slen = t->length - 2; /* exclude quotes */
        int j = 0;
        for (int i = 0; i < slen && j < OCPP_MAX_STRLEN - 1; i++) {
            if (s[i] == '\\' && i + 1 < slen) {
                n->str_val[j++] = unescape_char(s[++i]);
            } else {
                n->str_val[j++] = s[i];
            }
        }
        n->str_val[j] = '\0';
        return n;
    }
    if (t->type == CTOK_CHAR_LIT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_CHAR_LIT);
        n->line = t->line;
        if (t->start[1] == '\\') {
            n->num_val = unescape_char(t->start[2]);
        } else {
            n->num_val = t->start[1];
        }
        return n;
    }
    if (t->type == CTOK_THIS) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_THIS_EXPR);
        n->line = t->line;
        return n;
    }
    if (t->type == CTOK_COUT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_COUT_EXPR);
        n->line = t->line;
        /* Parse << chain */
        n->stmts = NULL;
        n->n_stmts = 0;
        int cap = 8;
        n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
        while (check(I, CTOK_LSHIFT)) {
            advance(I);
            if (check(I, CTOK_ENDL)) {
                advance(I);
                OcppNode *endl_n = alloc_node(I, NP_STRING_LIT);
                strcpy(endl_n->str_val, "\n");
                if (n->n_stmts >= cap) {
                    cap *= 2;
                    n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *));
                }
                n->stmts[n->n_stmts++] = endl_n;
            } else {
                OcppNode *expr = parse_assign_expr(I);
                if (n->n_stmts >= cap) {
                    cap *= 2;
                    n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *));
                }
                n->stmts[n->n_stmts++] = expr;
            }
        }
        return n;
    }
    if (t->type == CTOK_CIN) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_CIN_EXPR);
        n->line = t->line;
        n->stmts = NULL;
        n->n_stmts = 0;
        int cap = 8;
        n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
        while (check(I, CTOK_RSHIFT)) {
            advance(I);
            OcppNode *var = parse_primary(I);
            if (n->n_stmts >= cap) {
                cap *= 2;
                n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *));
            }
            n->stmts[n->n_stmts++] = var;
        }
        return n;
    }
    if (t->type == CTOK_SIZEOF) {
        advance(I);
        expect(I, CTOK_LPAREN);
        OcppNode *n = alloc_node(I, NP_SIZEOF);
        n->line = t->line;
        if (is_type_token(peek(I)->type)) {
            n->val_type = token_to_valtype(I, advance(I)->type);
        } else {
            n->children[0] = parse_expr(I);
            n->n_children = 1;
        }
        expect(I, CTOK_RPAREN);
        return n;
    }
    if (t->type == CTOK_NEW) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_NEW_EXPR);
        n->line = t->line;
        /* class/type name */
        OcppToken *name_tok = expect(I, CTOK_IDENT);
        tok_str(name_tok, n->class_name, sizeof(n->class_name));
        /* Optional constructor args */
        if (match(I, CTOK_LPAREN)) {
            int cap = 8;
            n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
            while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                if (n->n_stmts > 0) expect(I, CTOK_COMMA);
                if (n->n_stmts >= cap) {
                    cap *= 2;
                    n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *));
                }
                n->stmts[n->n_stmts++] = parse_assign_expr(I);
            }
            expect(I, CTOK_RPAREN);
        }
        return n;
    }
    if (t->type == CTOK_DELETE) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_DELETE_EXPR);
        n->line = t->line;
        n->children[0] = parse_expr(I);
        n->n_children = 1;
        return n;
    }
    /* Lambda: [captures](params){ body } */
    if (t->type == CTOK_LBRACKET) {
        /* Check if this is a lambda (next token after [...] is '(') */
        int saved = I->tok_pos;
        advance(I); /* skip [ */
        int depth = 1;
        while (depth > 0 && !check(I, CTOK_EOF)) {
            if (check(I, CTOK_LBRACKET)) depth++;
            else if (check(I, CTOK_RBRACKET)) depth--;
            if (depth > 0) advance(I);
        }
        if (check(I, CTOK_RBRACKET)) advance(I);
        int is_lambda = check(I, CTOK_LPAREN);
        I->tok_pos = saved; /* restore */

        if (is_lambda) {
            OcppNode *n = alloc_node(I, NP_LAMBDA_EXPR);
            n->line = t->line;
            /* Parse captures */
            expect(I, CTOK_LBRACKET);
            n->n_stmts = 0;
            n->stmts = (OcppNode **)calloc(8, sizeof(OcppNode *));
            int cap_idx = 0;
            while (!check(I, CTOK_RBRACKET) && !check(I, CTOK_EOF)) {
                if (cap_idx > 0) expect(I, CTOK_COMMA);
                int by_ref = 0;
                if (check(I, CTOK_AMP)) { advance(I); by_ref = 1; }
                if (check(I, CTOK_IDENT)) {
                    OcppToken *cap_tok = advance(I);
                    tok_str(cap_tok, n->param_names[cap_idx], sizeof(n->param_names[0]));
                    n->param_is_ref[cap_idx] = by_ref;
                    cap_idx++;
                } else if (check(I, CTOK_ASSIGN)) {
                    /* [=] capture all by value */
                    advance(I);
                    strcpy(n->param_names[cap_idx], "=");
                    cap_idx++;
                }
            }
            expect(I, CTOK_RBRACKET);
            n->op = cap_idx; /* store capture count in op field */

            /* Parse parameters */
            expect(I, CTOK_LPAREN);
            n->n_params = 0;
            while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                if (n->n_params > 0) expect(I, CTOK_COMMA);
                /* type */
                if (is_type_token(peek(I)->type)) {
                    n->param_types[n->n_params] = token_to_valtype(I, advance(I)->type);
                } else {
                    advance(I);
                    n->param_types[n->n_params] = CVAL_INT;
                }
                /* optional & */
                if (check(I, CTOK_AMP)) advance(I);
                /* name */
                OcppToken *pname = expect(I, CTOK_IDENT);
                tok_str(pname, n->param_names[cap_idx + n->n_params], sizeof(n->param_names[0]));
                n->n_params++;
            }
            expect(I, CTOK_RPAREN);

            /* Optional -> return type (skip) */
            if (check(I, CTOK_ARROW)) {
                advance(I);
                if (is_type_token(peek(I)->type)) advance(I);
            }

            /* Body */
            n->children[0] = parse_block(I);
            n->n_children = 1;
            return n;
        }
    }
    /* Cast: (type)expr */
    if (t->type == CTOK_LPAREN && is_type_token(peek_at(I, 1)->type)) {
        /* Check if this is actually a cast */
        int saved = I->tok_pos;
        advance(I);
        OcppTokenType tt = peek(I)->type;
        if (is_type_token(tt)) {
            OcppValType cast_type = token_to_valtype(I, tt);
            advance(I);
            /* skip pointers */
            while (check(I, CTOK_STAR)) advance(I);
            if (check(I, CTOK_RPAREN)) {
                advance(I);
                OcppNode *n = alloc_node(I, NP_CAST);
                n->val_type = cast_type;
                n->line = t->line;
                n->children[0] = parse_primary(I);
                n->n_children = 1;
                return n;
            }
        }
        I->tok_pos = saved;
    }
    /* Parenthesized expression */
    if (t->type == CTOK_LPAREN) {
        advance(I);
        OcppNode *n = parse_expr(I);
        expect(I, CTOK_RPAREN);
        return n;
    }
    /* Unary operators */
    if (t->type == CTOK_MINUS) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_NEG);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_BANG) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_NOT);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_TILDE) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_BIT_NOT);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_INC) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_PRE_INC);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_DEC) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_PRE_DEC);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_STAR) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_DEREF);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_AMP) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_ADDR);
        n->line = t->line;
        n->children[0] = parse_primary(I);
        n->n_children = 1;
        return n;
    }
    if (t->type == CTOK_THROW) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_THROW_EXPR);
        n->line = t->line;
        if (!check(I, CTOK_SEMICOLON)) {
            n->children[0] = parse_assign_expr(I);
            n->n_children = 1;
        }
        return n;
    }
    /* Identifier */
    if (t->type == CTOK_IDENT) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_IDENT);
        n->line = t->line;
        tok_str(t, n->name, sizeof(n->name));
        return n;
    }
    if (t->type == CTOK_STRING_TYPE) {
        /* string used as type or constructor: string("hello") */
        advance(I);
        if (check(I, CTOK_LPAREN)) {
            /* string("...") constructor call */
            advance(I);
            OcppNode *n = alloc_node(I, NP_CALL);
            n->line = t->line;
            strcpy(n->name, "string");
            n->stmts = (OcppNode **)calloc(4, sizeof(OcppNode *));
            n->n_stmts = 0;
            while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                if (n->n_stmts > 0) expect(I, CTOK_COMMA);
                n->stmts[n->n_stmts++] = parse_assign_expr(I);
            }
            expect(I, CTOK_RPAREN);
            return n;
        }
        /* Just the identifier "string" */
        OcppNode *n = alloc_node(I, NP_IDENT);
        n->line = t->line;
        strcpy(n->name, "string");
        return n;
    }
    if (t->type == CTOK_ENDL) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_STRING_LIT);
        strcpy(n->str_val, "\n");
        n->line = t->line;
        return n;
    }

    ocpp_error(I, "Line %d: unexpected token '%.*s'", t->line, t->length, t->start);
    return NULL; /* unreachable */
}

/* Postfix: calls, indexing, member access, post-inc/dec */
static OcppNode *parse_postfix(OcppInterpreter *I) {
    OcppNode *left = parse_primary(I);

    while (1) {
        if (check(I, CTOK_LPAREN)) {
            /* Function call */
            advance(I);
            OcppNode *call = alloc_node(I, NP_CALL);
            call->line = left->line;
            if (left->type == NP_IDENT) {
                strcpy(call->name, left->name);
            } else if (left->type == NP_MEMBER || left->type == NP_ARROW) {
                strcpy(call->name, left->name);
                call->children[0] = left->children[0];
                call->n_children = 1;
                call->op = (left->type == NP_ARROW) ? 1 : 2; /* 1=arrow, 2=dot method */
            } else {
                strcpy(call->name, "__indirect");
                call->children[0] = left;
                call->n_children = 1;
            }
            /* Parse args */
            int cap = 8;
            call->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
            call->n_stmts = 0;
            while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                if (call->n_stmts > 0) expect(I, CTOK_COMMA);
                if (call->n_stmts >= cap) {
                    cap *= 2;
                    call->stmts = (OcppNode **)realloc(call->stmts, cap * sizeof(OcppNode *));
                }
                call->stmts[call->n_stmts++] = parse_assign_expr(I);
            }
            expect(I, CTOK_RPAREN);
            left = call;
        } else if (check(I, CTOK_LBRACKET)) {
            advance(I);
            OcppNode *idx = alloc_node(I, NP_INDEX);
            idx->line = left->line;
            idx->children[0] = left;
            idx->children[1] = parse_expr(I);
            idx->n_children = 2;
            expect(I, CTOK_RBRACKET);
            left = idx;
        } else if (check(I, CTOK_DOT)) {
            advance(I);
            OcppNode *mem = alloc_node(I, NP_MEMBER);
            mem->line = left->line;
            mem->children[0] = left;
            mem->n_children = 1;
            OcppToken *name_tok = advance(I);
            tok_str(name_tok, mem->name, sizeof(mem->name));
            left = mem;
        } else if (check(I, CTOK_ARROW)) {
            advance(I);
            OcppNode *arr = alloc_node(I, NP_ARROW);
            arr->line = left->line;
            arr->children[0] = left;
            arr->n_children = 1;
            OcppToken *name_tok = advance(I);
            tok_str(name_tok, arr->name, sizeof(arr->name));
            left = arr;
        } else if (check(I, CTOK_INC)) {
            advance(I);
            OcppNode *n = alloc_node(I, NP_POST_INC);
            n->line = left->line;
            n->children[0] = left;
            n->n_children = 1;
            left = n;
        } else if (check(I, CTOK_DEC)) {
            advance(I);
            OcppNode *n = alloc_node(I, NP_POST_DEC);
            n->line = left->line;
            n->children[0] = left;
            n->n_children = 1;
            left = n;
        } else {
            break;
        }
    }
    return left;
}

/* Binary expression parsing with precedence */
static OcppNode *parse_mul(OcppInterpreter *I) {
    OcppNode *left = parse_postfix(I);
    while (check(I, CTOK_STAR) || check(I, CTOK_SLASH) || check(I, CTOK_PERCENT)) {
        OcppTokenType op = advance(I)->type;
        OcppNode *n = alloc_node(I, op == CTOK_STAR ? NP_MUL : op == CTOK_SLASH ? NP_DIV : NP_MOD);
        n->children[0] = left; n->children[1] = parse_postfix(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_add(OcppInterpreter *I) {
    OcppNode *left = parse_mul(I);
    while (check(I, CTOK_PLUS) || check(I, CTOK_MINUS)) {
        OcppTokenType op = advance(I)->type;
        OcppNode *n = alloc_node(I, op == CTOK_PLUS ? NP_ADD : NP_SUB);
        n->children[0] = left; n->children[1] = parse_mul(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_shift(OcppInterpreter *I) {
    OcppNode *left = parse_add(I);
    while (check(I, CTOK_LSHIFT) || check(I, CTOK_RSHIFT)) {
        OcppTokenType op = advance(I)->type;
        OcppNode *n = alloc_node(I, op == CTOK_LSHIFT ? NP_LSHIFT : NP_RSHIFT);
        n->children[0] = left; n->children[1] = parse_add(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_relational(OcppInterpreter *I) {
    OcppNode *left = parse_shift(I);
    while (check(I, CTOK_LT) || check(I, CTOK_GT) || check(I, CTOK_LE) || check(I, CTOK_GE)) {
        OcppTokenType op = advance(I)->type;
        OcppNodeType nt = op == CTOK_LT ? NP_LT : op == CTOK_GT ? NP_GT :
                          op == CTOK_LE ? NP_LE : NP_GE;
        OcppNode *n = alloc_node(I, nt);
        n->children[0] = left; n->children[1] = parse_shift(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_equality(OcppInterpreter *I) {
    OcppNode *left = parse_relational(I);
    while (check(I, CTOK_EQ) || check(I, CTOK_NEQ)) {
        OcppTokenType op = advance(I)->type;
        OcppNode *n = alloc_node(I, op == CTOK_EQ ? NP_EQ : NP_NEQ);
        n->children[0] = left; n->children[1] = parse_relational(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_bit_and(OcppInterpreter *I) {
    OcppNode *left = parse_equality(I);
    while (check(I, CTOK_AMP) && !check(I, CTOK_AND)) {
        /* Ensure it's & not && */
        if (peek_at(I, 1)->type == CTOK_AMP) break; /* would be parsed as && */
        advance(I);
        OcppNode *n = alloc_node(I, NP_BIT_AND);
        n->children[0] = left; n->children[1] = parse_equality(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_bit_xor(OcppInterpreter *I) {
    OcppNode *left = parse_bit_and(I);
    while (check(I, CTOK_CARET)) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_BIT_XOR);
        n->children[0] = left; n->children[1] = parse_bit_and(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_bit_or(OcppInterpreter *I) {
    OcppNode *left = parse_bit_xor(I);
    while (check(I, CTOK_PIPE) && peek_at(I, 1)->type != CTOK_PIPE) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_BIT_OR);
        n->children[0] = left; n->children[1] = parse_bit_xor(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_logical_and(OcppInterpreter *I) {
    OcppNode *left = parse_bit_or(I);
    while (check(I, CTOK_AND)) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_AND);
        n->children[0] = left; n->children[1] = parse_bit_or(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_logical_or(OcppInterpreter *I) {
    OcppNode *left = parse_logical_and(I);
    while (check(I, CTOK_OR)) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_OR);
        n->children[0] = left; n->children[1] = parse_logical_and(I); n->n_children = 2;
        left = n;
    }
    return left;
}

static OcppNode *parse_ternary(OcppInterpreter *I) {
    OcppNode *cond = parse_logical_or(I);
    if (check(I, CTOK_QUESTION)) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_TERNARY);
        n->children[0] = cond;
        n->children[1] = parse_expr(I);
        expect(I, CTOK_COLON);
        n->children[2] = parse_ternary(I);
        n->n_children = 3;
        return n;
    }
    return cond;
}

static OcppNode *parse_assign_expr(OcppInterpreter *I) {
    OcppNode *left = parse_ternary(I);
    OcppTokenType t = peek(I)->type;
    if (t == CTOK_ASSIGN) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_ASSIGN);
        n->children[0] = left;
        n->children[1] = parse_assign_expr(I);
        n->n_children = 2;
        return n;
    }
    if (t >= CTOK_PLUS_ASSIGN && t <= CTOK_RSHIFT_ASSIGN) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_COMPOUND_ASSIGN);
        n->op = t;
        n->children[0] = left;
        n->children[1] = parse_assign_expr(I);
        n->n_children = 2;
        return n;
    }
    return left;
}

static OcppNode *parse_expr(OcppInterpreter *I) {
    OcppNode *left = parse_assign_expr(I);
    while (check(I, CTOK_COMMA) && !check(I, CTOK_RPAREN)) {
        /* Only comma as operator, not separator */
        /* Heuristic: only treat as comma op if not in arg list context */
        break; /* For simplicity, don't support comma operator */
    }
    return left;
}

/* ══════════════════════════════════════════════
 *  Parser — statements and declarations
 * ══════════════════════════════════════════════ */

static OcppNode *parse_block(OcppInterpreter *I) {
    expect(I, CTOK_LBRACE);
    OcppNode *block = alloc_node(I, NP_BLOCK);
    block->line = peek(I)->line;
    int cap = 16;
    block->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
    block->n_stmts = 0;
    while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
        OcppNode *s = parse_stmt(I);
        if (s) {
            if (block->n_stmts >= cap) {
                cap *= 2;
                block->stmts = (OcppNode **)realloc(block->stmts, cap * sizeof(OcppNode *));
            }
            block->stmts[block->n_stmts++] = s;
        }
    }
    expect(I, CTOK_RBRACE);
    return block;
}

/* Detect if current position is a variable/function declaration */
static int is_declaration(OcppInterpreter *I) {
    OcppTokenType t = peek(I)->type;
    if (is_type_token(t)) return 1;
    /* Check for class-type declarations: ClassName varName */
    if (t == CTOK_IDENT) {
        /* Could be ClassName var; or ClassName var = ...; */
        OcppTokenType t2 = peek_at(I, 1)->type;
        if (t2 == CTOK_IDENT || t2 == CTOK_STAR || t2 == CTOK_AMP ||
            t2 == CTOK_LT) {
            /* Check if first ident is a known class */
            char name[256];
            tok_str(peek(I), name, sizeof(name));
            if (find_class(I, name)) return 1;
            /* Check if it's vector, map, pair */
            if (strcmp(name, "vector") == 0 || strcmp(name, "map") == 0 ||
                strcmp(name, "pair") == 0) return 1;
        }
    }
    if (t == CTOK_TEMPLATE || t == CTOK_VIRTUAL) return 1;
    return 0;
}

/* Parse variable or function declaration */
static OcppNode *parse_declaration(OcppInterpreter *I) {
    int is_virt = 0;
    int is_static_decl = 0;
    int is_const_decl = 0;

    /* template<typename T> */
    if (check(I, CTOK_TEMPLATE)) {
        advance(I);
        expect(I, CTOK_LT);
        OcppNode *tmpl = alloc_node(I, NP_TEMPLATE_DECL);
        tmpl->line = peek(I)->line;
        /* typename T or class T */
        if (check(I, CTOK_TYPENAME) || check(I, CTOK_CLASS)) advance(I);
        OcppToken *tp = expect(I, CTOK_IDENT);
        tok_str(tp, tmpl->type_param, sizeof(tmpl->type_param));
        expect(I, CTOK_GT);
        /* Parse the actual function/class declaration */
        tmpl->children[0] = parse_declaration(I);
        tmpl->n_children = 1;
        return tmpl;
    }

    if (check(I, CTOK_VIRTUAL)) { advance(I); is_virt = 1; }
    if (check(I, CTOK_STATIC)) { advance(I); is_static_decl = 1; }
    if (check(I, CTOK_CONST)) { advance(I); is_const_decl = 1; }

    OcppValType base_type = CVAL_INT;
    char type_class_name[64] = "";
    int is_class_type = 0;

    OcppTokenType tt = peek(I)->type;

    /* auto keyword */
    if (tt == CTOK_AUTO) {
        advance(I);
        base_type = CVAL_VOID; /* will be deduced */
        int is_ref = 0;
        if (check(I, CTOK_AMP)) { advance(I); is_ref = 1; }
        OcppToken *name_tok = expect(I, CTOK_IDENT);

        OcppNode *n = alloc_node(I, NP_VARDECL);
        n->line = name_tok->line;
        tok_str(name_tok, n->name, sizeof(n->name));
        n->val_type = base_type;
        n->is_reference = is_ref;
        n->is_const = is_const_decl;
        strcpy(n->label, "auto");

        if (match(I, CTOK_ASSIGN)) {
            n->children[0] = parse_assign_expr(I);
            n->n_children = 1;
        }
        expect(I, CTOK_SEMICOLON);
        return n;
    }

    /* vector<T>, map<K,V>, pair<A,B> */
    if (tt == CTOK_IDENT) {
        char tname[256];
        tok_str(peek(I), tname, sizeof(tname));
        if (strcmp(tname, "vector") == 0 || strcmp(tname, "map") == 0 ||
            strcmp(tname, "pair") == 0) {
            advance(I);
            /* skip <...> template args */
            if (check(I, CTOK_LT)) {
                advance(I);
                int depth = 1;
                while (depth > 0 && !check(I, CTOK_EOF)) {
                    if (check(I, CTOK_LT)) depth++;
                    else if (check(I, CTOK_GT)) depth--;
                    if (depth > 0) advance(I);
                }
                if (check(I, CTOK_GT)) advance(I);
            }
            /* Now parse variable name */
            int is_ref = 0;
            if (check(I, CTOK_AMP)) { advance(I); is_ref = 1; }
            OcppToken *name_tok = expect(I, CTOK_IDENT);

            OcppNode *n = alloc_node(I, NP_VARDECL);
            n->line = name_tok->line;
            tok_str(name_tok, n->name, sizeof(n->name));
            strcpy(n->class_name, tname);
            n->is_reference = is_ref;

            if (strcmp(tname, "vector") == 0) n->val_type = CVAL_VECTOR;
            else if (strcmp(tname, "map") == 0) n->val_type = CVAL_MAP;
            else n->val_type = CVAL_PAIR;

            if (match(I, CTOK_ASSIGN)) {
                n->children[0] = parse_assign_expr(I);
                n->n_children = 1;
            } else if (check(I, CTOK_LPAREN)) {
                /* Constructor syntax: vector<int> v(5, 0) */
                advance(I);
                int cap = 4;
                n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
                while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                    if (n->n_stmts > 0) expect(I, CTOK_COMMA);
                    n->stmts[n->n_stmts++] = parse_assign_expr(I);
                }
                expect(I, CTOK_RPAREN);
            } else if (check(I, CTOK_LBRACE)) {
                /* Initializer list: vector<int> v = {1,2,3} or vector<int> v{1,2,3} */
                advance(I);
                int cap = 8;
                n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
                while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
                    if (n->n_stmts > 0) expect(I, CTOK_COMMA);
                    if (n->n_stmts >= cap) {
                        cap *= 2;
                        n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *));
                    }
                    n->stmts[n->n_stmts++] = parse_assign_expr(I);
                }
                expect(I, CTOK_RBRACE);
            }
            expect(I, CTOK_SEMICOLON);
            return n;
        }
        /* Check if it's a known class name */
        if (find_class(I, tname)) {
            advance(I);
            is_class_type = 1;
            strncpy(type_class_name, tname, 63);
            base_type = CVAL_OBJECT;
        }
    }

    if (!is_class_type && is_type_token(tt)) {
        base_type = token_to_valtype(I, tt);
        advance(I);
        /* Handle "long long", "unsigned int", etc. */
        while (is_type_token(peek(I)->type) && peek(I)->type != CTOK_CONST) {
            tt = peek(I)->type;
            if (tt == CTOK_LONG || tt == CTOK_INT || tt == CTOK_SHORT ||
                tt == CTOK_UNSIGNED || tt == CTOK_SIGNED || tt == CTOK_DOUBLE) {
                if (tt == CTOK_DOUBLE) base_type = CVAL_DOUBLE;
                advance(I);
            } else break;
        }
    }

    if (check(I, CTOK_CONST)) { advance(I); is_const_decl = 1; }

    /* Pointer? */
    int ptr_depth = 0;
    while (check(I, CTOK_STAR)) { advance(I); ptr_depth++; }

    /* Reference? */
    int is_ref = 0;
    if (check(I, CTOK_AMP)) { advance(I); is_ref = 1; }

    /* Name */
    if (!check(I, CTOK_IDENT)) {
        ocpp_error(I, "Line %d: expected identifier in declaration", peek(I)->line);
    }
    OcppToken *name_tok = advance(I);
    char name[256];
    tok_str(name_tok, name, sizeof(name));

    /* Function declaration? */
    if (check(I, CTOK_LPAREN)) {
        advance(I);
        OcppNode *fn = alloc_node(I, NP_FUNCDECL);
        fn->line = name_tok->line;
        strcpy(fn->name, name);
        fn->val_type = ptr_depth > 0 ? CVAL_PTR : base_type;
        fn->is_virtual = is_virt;
        fn->is_static = is_static_decl;
        if (is_class_type) strcpy(fn->class_name, type_class_name);

        /* Parse parameters */
        fn->n_params = 0;
        while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
            if (fn->n_params > 0) expect(I, CTOK_COMMA);
            if (check(I, CTOK_ELLIPSIS)) { advance(I); break; }
            /* Skip const */
            if (check(I, CTOK_CONST)) advance(I);
            OcppValType ptype = CVAL_INT;
            if (is_type_token(peek(I)->type)) {
                ptype = token_to_valtype(I, advance(I)->type);
                while (is_type_token(peek(I)->type)) advance(I);
            } else if (check(I, CTOK_IDENT)) {
                /* Could be a class type parameter */
                char pclass[256];
                tok_str(peek(I), pclass, sizeof(pclass));
                if (find_class(I, pclass) || strcmp(pclass, "vector") == 0 ||
                    strcmp(pclass, "map") == 0 || strcmp(pclass, "string") == 0) {
                    ptype = CVAL_OBJECT;
                    advance(I);
                    if (check(I, CTOK_LT)) {
                        advance(I);
                        int d = 1;
                        while (d > 0 && !check(I, CTOK_EOF)) {
                            if (check(I, CTOK_LT)) d++;
                            if (check(I, CTOK_GT)) d--;
                            if (d > 0) advance(I);
                        }
                        if (check(I, CTOK_GT)) advance(I);
                    }
                } else {
                    advance(I);
                }
            }
            /* pointer/ref */
            int pref = 0;
            while (check(I, CTOK_STAR)) { advance(I); ptype = CVAL_PTR; }
            if (check(I, CTOK_AMP)) { advance(I); pref = 1; }
            if (check(I, CTOK_CONST)) advance(I);
            fn->param_types[fn->n_params] = ptype;
            fn->param_is_ref[fn->n_params] = pref;
            if (check(I, CTOK_IDENT)) {
                OcppToken *pt = advance(I);
                tok_str(pt, fn->param_names[fn->n_params], sizeof(fn->param_names[0]));
            }
            /* Default value */
            if (check(I, CTOK_ASSIGN)) {
                advance(I);
                parse_assign_expr(I); /* skip default value for now */
            }
            fn->n_params++;
        }
        expect(I, CTOK_RPAREN);

        /* Optional const, override */
        if (check(I, CTOK_CONST)) advance(I);
        if (check(I, CTOK_OVERRIDE)) advance(I);

        /* Body */
        if (check(I, CTOK_LBRACE)) {
            fn->children[0] = parse_block(I);
            fn->n_children = 1;
        } else {
            expect(I, CTOK_SEMICOLON);
        }
        return fn;
    }

    /* Variable declaration */
    OcppNode *n = alloc_node(I, NP_VARDECL);
    n->line = name_tok->line;
    strcpy(n->name, name);
    n->val_type = ptr_depth > 0 ? CVAL_PTR : base_type;
    n->is_reference = is_ref;
    n->is_const = is_const_decl;
    n->is_static = is_static_decl;
    if (is_class_type) strcpy(n->class_name, type_class_name);

    /* Array? */
    if (check(I, CTOK_LBRACKET)) {
        advance(I);
        n->is_array = 1;
        if (!check(I, CTOK_RBRACKET)) {
            n->array_size = (int)peek(I)->num_val;
            advance(I);
        }
        expect(I, CTOK_RBRACKET);
    }

    /* Initializer */
    if (match(I, CTOK_ASSIGN)) {
        if (check(I, CTOK_LBRACE)) {
            /* Initializer list */
            advance(I);
            OcppNode *init = alloc_node(I, NP_ARRAY_INIT);
            int cap = 16;
            init->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
            while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
                if (init->n_stmts > 0) expect(I, CTOK_COMMA);
                if (init->n_stmts >= cap) {
                    cap *= 2;
                    init->stmts = (OcppNode **)realloc(init->stmts, cap * sizeof(OcppNode *));
                }
                init->stmts[init->n_stmts++] = parse_assign_expr(I);
            }
            expect(I, CTOK_RBRACE);
            n->children[0] = init;
            n->n_children = 1;
        } else {
            n->children[0] = parse_assign_expr(I);
            n->n_children = 1;
        }
    } else if (check(I, CTOK_LPAREN) && is_class_type) {
        /* Constructor call: ClassName obj(args) */
        advance(I);
        OcppNode *init = alloc_node(I, NP_CALL);
        strcpy(init->name, type_class_name);
        int cap = 4;
        init->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
        while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
            if (init->n_stmts > 0) expect(I, CTOK_COMMA);
            init->stmts[init->n_stmts++] = parse_assign_expr(I);
        }
        expect(I, CTOK_RPAREN);
        n->children[0] = init;
        n->n_children = 1;
    }

    expect(I, CTOK_SEMICOLON);
    return n;
}

/* Parse class declaration */
static OcppNode *parse_class_decl(OcppInterpreter *I) {
    expect(I, CTOK_CLASS);
    OcppNode *cls = alloc_node(I, NP_CLASS_DECL);
    cls->line = peek(I)->line;
    OcppToken *name_tok = expect(I, CTOK_IDENT);
    tok_str(name_tok, cls->name, sizeof(cls->name));

    /* Inheritance */
    if (match(I, CTOK_COLON)) {
        if (check(I, CTOK_PUBLIC) || check(I, CTOK_PRIVATE) || check(I, CTOK_PROTECTED))
            advance(I);
        OcppToken *base = expect(I, CTOK_IDENT);
        tok_str(base, cls->base_class, sizeof(cls->base_class));
    }

    expect(I, CTOK_LBRACE);

    /* Parse class body */
    int cap = 16;
    cls->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
    cls->n_stmts = 0;
    int current_access = 1; /* private by default */

    while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
        /* Access specifiers */
        if (check(I, CTOK_PUBLIC)) { advance(I); expect(I, CTOK_COLON); current_access = 0; continue; }
        if (check(I, CTOK_PRIVATE)) { advance(I); expect(I, CTOK_COLON); current_access = 1; continue; }
        if (check(I, CTOK_PROTECTED)) { advance(I); expect(I, CTOK_COLON); current_access = 2; continue; }

        /* Constructor: ClassName(...) */
        if (check(I, CTOK_IDENT)) {
            char pname[256];
            tok_str(peek(I), pname, sizeof(pname));
            if (strcmp(pname, cls->name) == 0 && peek_at(I, 1)->type == CTOK_LPAREN) {
                /* Constructor */
                advance(I); advance(I);
                OcppNode *ctor = alloc_node(I, NP_FUNCDECL);
                ctor->line = peek(I)->line;
                strcpy(ctor->name, "__ctor");
                strcpy(ctor->class_name, cls->name);
                ctor->access = current_access;
                ctor->n_params = 0;
                while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                    if (ctor->n_params > 0) expect(I, CTOK_COMMA);
                    if (check(I, CTOK_CONST)) advance(I);
                    if (is_type_token(peek(I)->type) || check(I, CTOK_IDENT)) {
                        ctor->param_types[ctor->n_params] = token_to_valtype(I, peek(I)->type);
                        advance(I);
                        if (check(I, CTOK_LT)) {
                            advance(I);
                            int d=1; while(d>0 && !check(I,CTOK_EOF)){if(check(I,CTOK_LT))d++;if(check(I,CTOK_GT))d--;if(d>0)advance(I);}
                            if(check(I,CTOK_GT))advance(I);
                        }
                    }
                    while (check(I, CTOK_STAR)) advance(I);
                    if (check(I, CTOK_AMP)) { advance(I); ctor->param_is_ref[ctor->n_params] = 1; }
                    if (check(I, CTOK_CONST)) advance(I);
                    if (check(I, CTOK_IDENT)) {
                        OcppToken *pt = advance(I);
                        tok_str(pt, ctor->param_names[ctor->n_params], sizeof(ctor->param_names[0]));
                    }
                    if (check(I, CTOK_ASSIGN)) { advance(I); parse_assign_expr(I); }
                    ctor->n_params++;
                }
                expect(I, CTOK_RPAREN);
                /* Initializer list: : field(val), ... */
                if (check(I, CTOK_COLON)) {
                    advance(I);
                    while (!check(I, CTOK_LBRACE) && !check(I, CTOK_EOF)) {
                        if (check(I, CTOK_IDENT)) advance(I);
                        if (check(I, CTOK_LPAREN)) {
                            advance(I);
                            int d = 1;
                            while (d > 0 && !check(I, CTOK_EOF)) {
                                if (check(I, CTOK_LPAREN)) d++;
                                if (check(I, CTOK_RPAREN)) d--;
                                if (d > 0) advance(I);
                            }
                            if (check(I, CTOK_RPAREN)) advance(I);
                        }
                        if (check(I, CTOK_COMMA)) advance(I);
                    }
                }
                ctor->children[0] = parse_block(I);
                ctor->n_children = 1;
                if (cls->n_stmts >= cap) { cap *= 2; cls->stmts = (OcppNode **)realloc(cls->stmts, cap * sizeof(OcppNode *)); }
                cls->stmts[cls->n_stmts++] = ctor;
                continue;
            }
        }

        /* Destructor: ~ClassName() */
        if (check(I, CTOK_TILDE)) {
            advance(I);
            if (check(I, CTOK_IDENT)) advance(I);
            expect(I, CTOK_LPAREN);
            expect(I, CTOK_RPAREN);
            OcppNode *dtor = alloc_node(I, NP_FUNCDECL);
            dtor->line = peek(I)->line;
            strcpy(dtor->name, "__dtor");
            strcpy(dtor->class_name, cls->name);
            dtor->children[0] = parse_block(I);
            dtor->n_children = 1;
            if (cls->n_stmts >= cap) { cap *= 2; cls->stmts = (OcppNode **)realloc(cls->stmts, cap * sizeof(OcppNode *)); }
            cls->stmts[cls->n_stmts++] = dtor;
            continue;
        }

        /* Operator overload: ReturnType operator+(Params) { ... } */
        if (check(I, CTOK_VIRTUAL)) advance(I);
        if (is_type_token(peek(I)->type) || check(I, CTOK_IDENT)) {
            int saved = I->tok_pos;
            /* Try to see if this is an operator overload */
            while (is_type_token(peek(I)->type) || check(I, CTOK_STAR) || check(I, CTOK_AMP)) advance(I);
            if (check(I, CTOK_OPERATOR)) {
                advance(I);
                OcppNode *op_decl = alloc_node(I, NP_OPERATOR_DECL);
                op_decl->line = peek(I)->line;
                strcpy(op_decl->class_name, cls->name);
                op_decl->access = current_access;
                /* Get operator */
                OcppToken *optok = advance(I);
                op_decl->op = optok->type;
                /* If == or other two-char operator */
                if (check(I, CTOK_LPAREN) && optok->type == CTOK_LPAREN) {
                    expect(I, CTOK_RPAREN); /* operator() */
                    op_decl->op = CTOK_LPAREN;
                }
                expect(I, CTOK_LPAREN);
                op_decl->n_params = 0;
                while (!check(I, CTOK_RPAREN) && !check(I, CTOK_EOF)) {
                    if (op_decl->n_params > 0) expect(I, CTOK_COMMA);
                    if (check(I, CTOK_CONST)) advance(I);
                    if (is_type_token(peek(I)->type) || check(I, CTOK_IDENT)) {
                        op_decl->param_types[op_decl->n_params] = token_to_valtype(I, peek(I)->type);
                        advance(I);
                    }
                    while (check(I, CTOK_STAR) || check(I, CTOK_AMP)) advance(I);
                    if (check(I, CTOK_CONST)) advance(I);
                    if (check(I, CTOK_IDENT)) {
                        OcppToken *pt = advance(I);
                        tok_str(pt, op_decl->param_names[op_decl->n_params], sizeof(op_decl->param_names[0]));
                    }
                    op_decl->n_params++;
                }
                expect(I, CTOK_RPAREN);
                if (check(I, CTOK_CONST)) advance(I);
                op_decl->children[0] = parse_block(I);
                op_decl->n_children = 1;
                if (cls->n_stmts >= cap) { cap *= 2; cls->stmts = (OcppNode **)realloc(cls->stmts, cap * sizeof(OcppNode *)); }
                cls->stmts[cls->n_stmts++] = op_decl;
                continue;
            }
            I->tok_pos = saved;
        }

        /* Member field or method */
        OcppNode *member = parse_declaration(I);
        if (member) {
            member->access = current_access;
            strcpy(member->class_name, cls->name);
            if (cls->n_stmts >= cap) { cap *= 2; cls->stmts = (OcppNode **)realloc(cls->stmts, cap * sizeof(OcppNode *)); }
            cls->stmts[cls->n_stmts++] = member;
        }
    }
    expect(I, CTOK_RBRACE);
    expect(I, CTOK_SEMICOLON);
    return cls;
}

static OcppNode *parse_stmt(OcppInterpreter *I) {
    OcppToken *t = peek(I);

    /* Skip preprocessor tokens */
    if (t->type == CTOK_INCLUDE || t->type == CTOK_DEFINE) {
        advance(I);
        return NULL;
    }

    /* using namespace std; */
    if (t->type == CTOK_USING) {
        advance(I);
        if (check(I, CTOK_NAMESPACE)) {
            advance(I);
            OcppNode *n = alloc_node(I, NP_USING_DECL);
            n->line = t->line;
            OcppToken *ns_tok = advance(I);
            tok_str(ns_tok, n->name, sizeof(n->name));
            expect(I, CTOK_SEMICOLON);
            return n;
        }
        /* using declaration — skip */
        while (!check(I, CTOK_SEMICOLON) && !check(I, CTOK_EOF)) advance(I);
        if (check(I, CTOK_SEMICOLON)) advance(I);
        return NULL;
    }

    /* namespace Name { ... } */
    if (t->type == CTOK_NAMESPACE) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_NAMESPACE_DECL);
        n->line = t->line;
        if (check(I, CTOK_IDENT)) {
            OcppToken *ns = advance(I);
            tok_str(ns, n->name, sizeof(n->name));
        }
        n->children[0] = parse_block(I);
        n->n_children = 1;
        return n;
    }

    /* class */
    if (t->type == CTOK_CLASS) {
        return parse_class_decl(I);
    }

    /* struct (C-style) */
    if (t->type == CTOK_STRUCT) {
        advance(I);
        OcppNode *sd = alloc_node(I, NP_STRUCT_DECL);
        sd->line = t->line;
        if (check(I, CTOK_IDENT)) {
            OcppToken *sn = advance(I);
            tok_str(sn, sd->name, sizeof(sd->name));
        }
        if (check(I, CTOK_LBRACE)) {
            sd->children[0] = parse_block(I);
            sd->n_children = 1;
        }
        expect(I, CTOK_SEMICOLON);
        return sd;
    }

    /* enum */
    if (t->type == CTOK_ENUM) {
        advance(I);
        if (check(I, CTOK_CLASS)) advance(I); /* enum class */
        OcppNode *en = alloc_node(I, NP_STRUCT_DECL);
        en->line = t->line;
        if (check(I, CTOK_IDENT)) {
            OcppToken *ename = advance(I);
            tok_str(ename, en->name, sizeof(en->name));
        }
        strcpy(en->label, "enum");
        if (check(I, CTOK_LBRACE)) {
            advance(I);
            int cap = 16;
            en->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
            int eval = 0;
            while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
                if (en->n_stmts > 0) expect(I, CTOK_COMMA);
                if (check(I, CTOK_RBRACE)) break;
                OcppNode *ev = alloc_node(I, NP_VARDECL);
                OcppToken *ename = expect(I, CTOK_IDENT);
                tok_str(ename, ev->name, sizeof(ev->name));
                if (match(I, CTOK_ASSIGN)) {
                    eval = (int)peek(I)->num_val;
                    advance(I);
                }
                ev->num_val = eval++;
                if (en->n_stmts >= cap) { cap *= 2; en->stmts = (OcppNode **)realloc(en->stmts, cap * sizeof(OcppNode *)); }
                en->stmts[en->n_stmts++] = ev;
            }
            expect(I, CTOK_RBRACE);
        }
        expect(I, CTOK_SEMICOLON);
        return en;
    }

    /* Block */
    if (t->type == CTOK_LBRACE) return parse_block(I);

    /* if */
    if (t->type == CTOK_IF) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_IF);
        n->line = t->line;
        expect(I, CTOK_LPAREN);
        n->children[0] = parse_expr(I);
        expect(I, CTOK_RPAREN);
        n->children[1] = parse_stmt(I);
        n->n_children = 2;
        if (match(I, CTOK_ELSE)) {
            n->children[2] = parse_stmt(I);
            n->n_children = 3;
        }
        return n;
    }

    /* while */
    if (t->type == CTOK_WHILE) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_WHILE);
        n->line = t->line;
        expect(I, CTOK_LPAREN);
        n->children[0] = parse_expr(I);
        expect(I, CTOK_RPAREN);
        n->children[1] = parse_stmt(I);
        n->n_children = 2;
        return n;
    }

    /* do-while */
    if (t->type == CTOK_DO) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_DOWHILE);
        n->line = t->line;
        n->children[0] = parse_stmt(I);
        expect(I, CTOK_WHILE);
        expect(I, CTOK_LPAREN);
        n->children[1] = parse_expr(I);
        expect(I, CTOK_RPAREN);
        n->n_children = 2;
        expect(I, CTOK_SEMICOLON);
        return n;
    }

    /* for — regular or range-based */
    if (t->type == CTOK_FOR) {
        advance(I);
        expect(I, CTOK_LPAREN);

        /* Check for range-based for: for (type var : container) */
        int saved = I->tok_pos;
        int is_range = 0;
        /* Try scanning for : before ; */
        int depth = 0;
        int pos = I->tok_pos;
        while (pos < I->n_tokens) {
            OcppTokenType tt2 = I->tokens[pos].type;
            if (tt2 == CTOK_LPAREN) depth++;
            else if (tt2 == CTOK_RPAREN) { if (depth == 0) break; depth--; }
            else if (tt2 == CTOK_SEMICOLON && depth == 0) break;
            else if (tt2 == CTOK_COLON && depth == 0) { is_range = 1; break; }
            pos++;
        }

        if (is_range) {
            OcppNode *n = alloc_node(I, NP_RANGE_FOR);
            n->line = t->line;
            /* Parse type */
            if (check(I, CTOK_AUTO) || check(I, CTOK_CONST) || is_type_token(peek(I)->type)) {
                if (check(I, CTOK_CONST)) advance(I);
                if (is_type_token(peek(I)->type)) {
                    n->val_type = token_to_valtype(I, advance(I)->type);
                }
            }
            if (check(I, CTOK_AMP)) { advance(I); n->is_reference = 1; }
            OcppToken *var = expect(I, CTOK_IDENT);
            tok_str(var, n->name, sizeof(n->name));
            expect(I, CTOK_COLON);
            n->children[0] = parse_expr(I);
            expect(I, CTOK_RPAREN);
            n->children[1] = parse_stmt(I);
            n->n_children = 2;
            return n;
        }

        I->tok_pos = saved;

        /* Regular for */
        OcppNode *n = alloc_node(I, NP_FOR);
        n->line = t->line;
        /* Init */
        if (check(I, CTOK_SEMICOLON)) {
            advance(I);
            n->children[0] = NULL;
        } else if (is_declaration(I)) {
            n->children[0] = parse_declaration(I); /* includes ; */
        } else {
            n->children[0] = alloc_node(I, NP_EXPR_STMT);
            n->children[0]->children[0] = parse_expr(I);
            n->children[0]->n_children = 1;
            expect(I, CTOK_SEMICOLON);
        }
        /* Condition */
        if (check(I, CTOK_SEMICOLON)) {
            n->children[1] = NULL;
        } else {
            n->children[1] = parse_expr(I);
        }
        expect(I, CTOK_SEMICOLON);
        /* Update */
        if (check(I, CTOK_RPAREN)) {
            n->children[2] = NULL;
        } else {
            n->children[2] = parse_expr(I);
        }
        expect(I, CTOK_RPAREN);
        n->children[3] = parse_stmt(I);
        n->n_children = 4;
        return n;
    }

    /* switch */
    if (t->type == CTOK_SWITCH) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_SWITCH);
        n->line = t->line;
        expect(I, CTOK_LPAREN);
        n->children[0] = parse_expr(I);
        expect(I, CTOK_RPAREN);
        n->n_children = 1;
        expect(I, CTOK_LBRACE);
        int cap = 16;
        n->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
        while (!check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
            if (check(I, CTOK_CASE)) {
                advance(I);
                OcppNode *cs = alloc_node(I, NP_CASE);
                cs->children[0] = parse_expr(I);
                cs->n_children = 1;
                expect(I, CTOK_COLON);
                int bcap = 8;
                cs->stmts = (OcppNode **)calloc(bcap, sizeof(OcppNode *));
                while (!check(I, CTOK_CASE) && !check(I, CTOK_DEFAULT) &&
                       !check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
                    OcppNode *s = parse_stmt(I);
                    if (s) {
                        if (cs->n_stmts >= bcap) { bcap *= 2; cs->stmts = (OcppNode **)realloc(cs->stmts, bcap * sizeof(OcppNode *)); }
                        cs->stmts[cs->n_stmts++] = s;
                    }
                }
                if (n->n_stmts >= cap) { cap *= 2; n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *)); }
                n->stmts[n->n_stmts++] = cs;
            } else if (check(I, CTOK_DEFAULT)) {
                advance(I); expect(I, CTOK_COLON);
                OcppNode *df = alloc_node(I, NP_DEFAULT);
                int bcap = 8;
                df->stmts = (OcppNode **)calloc(bcap, sizeof(OcppNode *));
                while (!check(I, CTOK_CASE) && !check(I, CTOK_RBRACE) && !check(I, CTOK_EOF)) {
                    OcppNode *s = parse_stmt(I);
                    if (s) {
                        if (df->n_stmts >= bcap) { bcap *= 2; df->stmts = (OcppNode **)realloc(df->stmts, bcap * sizeof(OcppNode *)); }
                        df->stmts[df->n_stmts++] = s;
                    }
                }
                if (n->n_stmts >= cap) { cap *= 2; n->stmts = (OcppNode **)realloc(n->stmts, cap * sizeof(OcppNode *)); }
                n->stmts[n->n_stmts++] = df;
            } else {
                advance(I); /* skip stray tokens */
            }
        }
        expect(I, CTOK_RBRACE);
        return n;
    }

    /* return */
    if (t->type == CTOK_RETURN) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_RETURN);
        n->line = t->line;
        if (!check(I, CTOK_SEMICOLON)) {
            n->children[0] = parse_expr(I);
            n->n_children = 1;
        }
        expect(I, CTOK_SEMICOLON);
        return n;
    }

    /* break / continue */
    if (t->type == CTOK_BREAK) { advance(I); expect(I, CTOK_SEMICOLON); OcppNode *n = alloc_node(I, NP_BREAK); n->line = t->line; return n; }
    if (t->type == CTOK_CONTINUE) { advance(I); expect(I, CTOK_SEMICOLON); OcppNode *n = alloc_node(I, NP_CONTINUE); n->line = t->line; return n; }

    /* try/catch */
    if (t->type == CTOK_TRY) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_TRY_CATCH);
        n->line = t->line;
        n->children[0] = parse_block(I);
        n->n_children = 1;
        n->n_catches = 0;
        while (check(I, CTOK_CATCH)) {
            advance(I);
            OcppNode *cc = alloc_node(I, NP_BLOCK);
            cc->line = peek(I)->line;
            expect(I, CTOK_LPAREN);
            if (check(I, CTOK_ELLIPSIS)) {
                advance(I);
                strcpy(cc->name, "...");
            } else {
                /* catch (Type& name) */
                if (is_type_token(peek(I)->type) || check(I, CTOK_IDENT)) {
                    OcppToken *ct = advance(I);
                    tok_str(ct, cc->class_name, sizeof(cc->class_name));
                }
                if (check(I, CTOK_AMP)) advance(I);
                if (check(I, CTOK_IDENT)) {
                    OcppToken *cn = advance(I);
                    tok_str(cn, cc->name, sizeof(cc->name));
                }
            }
            expect(I, CTOK_RPAREN);
            cc->children[0] = parse_block(I);
            cc->n_children = 1;
            if (n->n_catches < OCPP_MAX_CATCH) {
                n->catch_clauses[n->n_catches++] = cc;
            }
        }
        return n;
    }

    /* goto */
    if (t->type == CTOK_GOTO) {
        advance(I);
        OcppNode *n = alloc_node(I, NP_GOTO);
        n->line = t->line;
        OcppToken *lab = expect(I, CTOK_IDENT);
        tok_str(lab, n->label, sizeof(n->label));
        expect(I, CTOK_SEMICOLON);
        return n;
    }

    /* Label: ident followed by : */
    if (t->type == CTOK_IDENT && peek_at(I, 1)->type == CTOK_COLON) {
        OcppToken *lab = advance(I);
        advance(I); /* skip : */
        OcppNode *n = alloc_node(I, NP_LABEL);
        tok_str(lab, n->label, sizeof(n->label));
        n->line = lab->line;
        return n;
    }

    /* Declaration or expression statement */
    if (is_declaration(I)) {
        return parse_declaration(I);
    }

    /* Expression statement */
    OcppNode *n = alloc_node(I, NP_EXPR_STMT);
    n->line = t->line;
    n->children[0] = parse_expr(I);
    n->n_children = 1;
    expect(I, CTOK_SEMICOLON);
    return n;
}

/* Parse program: top-level declarations/statements */
static OcppNode *parse_program(OcppInterpreter *I) {
    OcppNode *prog = alloc_node(I, NP_PROGRAM);
    int cap = 32;
    prog->stmts = (OcppNode **)calloc(cap, sizeof(OcppNode *));
    prog->n_stmts = 0;

    while (!check(I, CTOK_EOF)) {
        OcppNode *s = parse_stmt(I);
        if (s) {
            if (prog->n_stmts >= cap) {
                cap *= 2;
                prog->stmts = (OcppNode **)realloc(prog->stmts, cap * sizeof(OcppNode *));
            }
            prog->stmts[prog->n_stmts++] = s;
        }
    }
    return prog;
}

/* ══════════════════════════════════════════════
 *  Class management
 * ══════════════════════════════════════════════ */

static OcppClassDef *find_class(OcppInterpreter *I, const char *name) {
    for (int i = 0; i < I->n_classes; i++)
        if (strcmp(I->classes[i].name, name) == 0) return &I->classes[i];
    return NULL;
}

static void register_class(OcppInterpreter *I, OcppNode *cls_node) {
    if (I->n_classes >= OCPP_MAX_CLASSES)
        ocpp_error(I, "Too many classes");
    OcppClassDef *cd = &I->classes[I->n_classes++];
    memset(cd, 0, sizeof(*cd));
    strncpy(cd->name, cls_node->name, 63);
    if (cls_node->base_class[0])
        strncpy(cd->base_class, cls_node->base_class, 63);

    /* Copy base class fields if inheriting */
    OcppClassDef *base = find_class(I, cd->base_class);
    if (base) {
        for (int i = 0; i < base->n_fields; i++) {
            strcpy(cd->field_names[cd->n_fields], base->field_names[i]);
            cd->field_types[cd->n_fields] = base->field_types[i];
            cd->field_access[cd->n_fields] = base->field_access[i];
            cd->n_fields++;
        }
        /* Copy base methods */
        for (int i = 0; i < base->n_methods; i++) {
            cd->methods[cd->n_methods] = base->methods[i];
            cd->n_methods++;
        }
    }

    /* Process class body */
    for (int i = 0; i < cls_node->n_stmts; i++) {
        OcppNode *mem = cls_node->stmts[i];
        if (!mem) continue;
        if (mem->type == NP_VARDECL) {
            /* Field */
            if (cd->n_fields < OCPP_MAX_FIELDS) {
                strncpy(cd->field_names[cd->n_fields], mem->name, 63);
                cd->field_types[cd->n_fields] = mem->val_type;
                cd->field_access[cd->n_fields] = mem->access;
                cd->field_inits[cd->n_fields] = (mem->n_children > 0) ? mem->children[0] : NULL;
                cd->n_fields++;
            }
        } else if (mem->type == NP_FUNCDECL) {
            if (strcmp(mem->name, "__ctor") == 0) {
                cd->constructor = mem;
            } else if (strcmp(mem->name, "__dtor") == 0) {
                cd->destructor = mem;
            } else {
                /* Method — check for override */
                int replaced = 0;
                if (mem->is_virtual || base) {
                    for (int m = 0; m < cd->n_methods; m++) {
                        if (strcmp(cd->methods[m].name, mem->name) == 0) {
                            cd->methods[m].node = mem;
                            cd->methods[m].is_virtual = mem->is_virtual;
                            replaced = 1;
                            break;
                        }
                    }
                }
                if (!replaced && cd->n_methods < OCPP_MAX_METHODS) {
                    strncpy(cd->methods[cd->n_methods].name, mem->name, 63);
                    cd->methods[cd->n_methods].node = mem;
                    cd->methods[cd->n_methods].is_virtual = mem->is_virtual;
                    cd->methods[cd->n_methods].access = mem->access;
                    cd->n_methods++;
                }
            }
        } else if (mem->type == NP_OPERATOR_DECL) {
            if (cd->n_operators < 16) {
                cd->operators[cd->n_operators].op = mem->op;
                cd->operators[cd->n_operators].node = mem;
                cd->n_operators++;
            }
        }
    }
}

static OcppValue create_default_val(OcppValType t) {
    switch (t) {
        case CVAL_INT: return make_int(0);
        case CVAL_FLOAT: case CVAL_DOUBLE: return make_float(0.0);
        case CVAL_CHAR: return make_char('\0');
        case CVAL_BOOL: return make_bool(0);
        case CVAL_STRING: return make_string("");
        case CVAL_VECTOR: return make_vector(CVAL_INT);
        case CVAL_MAP: return make_map(CVAL_STRING, CVAL_INT);
        default: return make_int(0);
    }
}

static OcppValue create_object(OcppInterpreter *I, const char *class_name, OcppValue *args, int nargs) {
    OcppClassDef *cd = find_class(I, class_name);
    if (!cd) ocpp_error(I, "Unknown class '%s'", class_name);

    OcppValue obj;
    memset(&obj, 0, sizeof(obj));
    obj.type = CVAL_OBJECT;
    int nf = cd->n_fields;
    obj.v.obj.fields = (OcppValue *)calloc(nf > 0 ? nf : 1, sizeof(OcppValue));
    obj.v.obj.field_names = (char (*)[64])calloc(nf > 0 ? nf : 1, 64);
    obj.v.obj.n_fields = nf;
    strncpy(obj.v.obj.class_name, class_name, 63);

    /* Init fields */
    for (int i = 0; i < nf; i++) {
        strcpy(obj.v.obj.field_names[i], cd->field_names[i]);
        if (cd->field_inits[i]) {
            obj.v.obj.fields[i] = eval_node(I, cd->field_inits[i]);
        } else {
            obj.v.obj.fields[i] = create_default_val(cd->field_types[i]);
        }
    }

    /* Allocate vmem for this pointer */
    int addr = vmem_alloc(I, 1);
    if (addr) {
        *vmem_get(I, addr) = obj;
        obj.v.obj.vmem_addr = addr;
    }

    /* Run constructor */
    if (cd->constructor && cd->constructor->n_children > 0) {
        /* Push this */
        if (I->this_depth >= OCPP_MAX_STACK) ocpp_error(I, "this stack overflow");
        I->this_stack[I->this_depth++] = &obj;
        char prev_class[64];
        strcpy(prev_class, I->current_class);
        strcpy(I->current_class, class_name);

        OcppScope *prev = I->current_scope;
        OcppScope *ctor_scope = scope_create(I->global_scope);
        I->current_scope = ctor_scope;

        /* Bind params */
        OcppNode *ctor = cd->constructor;
        for (int i = 0; i < ctor->n_params && i < nargs; i++) {
            scope_set(I, ctor_scope, ctor->param_names[i], args[i]);
        }

        exec_node(I, ctor->children[0]);
        I->returning = 0;

        /* Copy fields back from this pointer */
        OcppValue *this_ptr = I->this_stack[I->this_depth - 1];
        for (int i = 0; i < this_ptr->v.obj.n_fields; i++) {
            obj.v.obj.fields[i] = this_ptr->v.obj.fields[i];
        }

        I->current_scope = prev;
        scope_destroy(ctor_scope);
        I->this_depth--;
        strcpy(I->current_class, prev_class);
    }

    return obj;
}

/* ══════════════════════════════════════════════
 *  STL Built-in implementations
 * ══════════════════════════════════════════════ */

/* ── string methods ── */
static OcppValue string_method(OcppInterpreter *I, OcppValue *str, const char *method, OcppValue *args, int nargs) {
    if (str->type != CVAL_STRING) ocpp_error(I, "String method on non-string");
    const char *s = str->v.s ? str->v.s : "";

    if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) {
        return make_int((long long)strlen(s));
    }
    if (strcmp(method, "empty") == 0) {
        return make_bool(s[0] == '\0');
    }
    if (strcmp(method, "clear") == 0) {
        if (str->v.s) { free(str->v.s); str->v.s = strdup(""); }
        return make_void();
    }
    if (strcmp(method, "c_str") == 0) {
        return make_string(s);
    }
    if (strcmp(method, "substr") == 0) {
        int pos = nargs > 0 ? (int)val_to_int(args[0]) : 0;
        int len2 = nargs > 1 ? (int)val_to_int(args[1]) : (int)strlen(s) - pos;
        int slen = (int)strlen(s);
        if (pos < 0 || pos > slen) pos = slen;
        if (len2 < 0 || pos + len2 > slen) len2 = slen - pos;
        char buf[OCPP_MAX_STRLEN];
        strncpy(buf, s + pos, len2);
        buf[len2] = '\0';
        return make_string(buf);
    }
    if (strcmp(method, "find") == 0) {
        if (nargs < 1) return make_int(-1);
        const char *needle = "";
        char nbuf[OCPP_MAX_STRLEN];
        if (args[0].type == CVAL_STRING) needle = args[0].v.s ? args[0].v.s : "";
        else if (args[0].type == CVAL_CHAR) { nbuf[0] = args[0].v.c; nbuf[1] = '\0'; needle = nbuf; }
        else { val_to_str(args[0], nbuf, sizeof(nbuf)); needle = nbuf; }
        int start_pos = nargs > 1 ? (int)val_to_int(args[1]) : 0;
        const char *result = strstr(s + start_pos, needle);
        return make_int(result ? (long long)(result - s) : -1LL);
    }
    if (strcmp(method, "append") == 0) {
        if (nargs < 1) return make_void();
        char buf[OCPP_MAX_STRLEN];
        const char *app = val_to_str(args[0], buf, sizeof(buf));
        int old_len = (int)strlen(s);
        int app_len = (int)strlen(app);
        char *new_s = (char *)malloc(old_len + app_len + 1);
        memcpy(new_s, s, old_len);
        memcpy(new_s + old_len, app, app_len + 1);
        if (str->v.s) free(str->v.s);
        str->v.s = new_s;
        return *str;
    }
    if (strcmp(method, "at") == 0) {
        if (nargs < 1) ocpp_error(I, "string::at requires index");
        int idx = (int)val_to_int(args[0]);
        int slen = (int)strlen(s);
        if (idx < 0 || idx >= slen) ocpp_error(I, "string::at index out of range");
        return make_char(s[idx]);
    }
    if (strcmp(method, "push_back") == 0) {
        if (nargs < 1) return make_void();
        char ch = (char)val_to_int(args[0]);
        int old_len = (int)strlen(s);
        char *new_s = (char *)malloc(old_len + 2);
        memcpy(new_s, s, old_len);
        new_s[old_len] = ch;
        new_s[old_len + 1] = '\0';
        if (str->v.s) free(str->v.s);
        str->v.s = new_s;
        return make_void();
    }
    if (strcmp(method, "erase") == 0) {
        int pos = nargs > 0 ? (int)val_to_int(args[0]) : 0;
        int count = nargs > 1 ? (int)val_to_int(args[1]) : 1;
        int slen = (int)strlen(s);
        if (pos >= slen) return *str;
        if (pos + count > slen) count = slen - pos;
        char *new_s = (char *)malloc(slen - count + 1);
        memcpy(new_s, s, pos);
        memcpy(new_s + pos, s + pos + count, slen - pos - count + 1);
        if (str->v.s) free(str->v.s);
        str->v.s = new_s;
        return *str;
    }
    ocpp_error(I, "Unknown string method '%s'", method);
    return make_void();
}

/* ── vector methods ── */
static void vec_ensure_cap(OcppValue *vec, int needed) {
    if (needed <= vec->v.vec.cap) return;
    int new_cap = vec->v.vec.cap * 2;
    if (new_cap < needed) new_cap = needed;
    vec->v.vec.data = (OcppValue *)realloc(vec->v.vec.data, new_cap * sizeof(OcppValue));
    memset(vec->v.vec.data + vec->v.vec.cap, 0, (new_cap - vec->v.vec.cap) * sizeof(OcppValue));
    vec->v.vec.cap = new_cap;
}

static OcppValue vector_method(OcppInterpreter *I, OcppValue *vec, const char *method, OcppValue *args, int nargs) {
    if (vec->type != CVAL_VECTOR) ocpp_error(I, "Vector method on non-vector");

    if (strcmp(method, "push_back") == 0 || strcmp(method, "emplace_back") == 0) {
        if (nargs < 1) ocpp_error(I, "push_back requires argument");
        vec_ensure_cap(vec, vec->v.vec.len + 1);
        vec->v.vec.data[vec->v.vec.len++] = value_deep_copy(args[0]);
        return make_void();
    }
    if (strcmp(method, "pop_back") == 0) {
        if (vec->v.vec.len > 0) vec->v.vec.len--;
        return make_void();
    }
    if (strcmp(method, "size") == 0) {
        return make_int(vec->v.vec.len);
    }
    if (strcmp(method, "empty") == 0) {
        return make_bool(vec->v.vec.len == 0);
    }
    if (strcmp(method, "clear") == 0) {
        vec->v.vec.len = 0;
        return make_void();
    }
    if (strcmp(method, "at") == 0) {
        if (nargs < 1) ocpp_error(I, "at requires index");
        int idx = (int)val_to_int(args[0]);
        if (idx < 0 || idx >= vec->v.vec.len) ocpp_error(I, "vector::at out of range");
        return vec->v.vec.data[idx];
    }
    if (strcmp(method, "front") == 0) {
        if (vec->v.vec.len == 0) ocpp_error(I, "vector::front on empty vector");
        return vec->v.vec.data[0];
    }
    if (strcmp(method, "back") == 0) {
        if (vec->v.vec.len == 0) ocpp_error(I, "vector::back on empty vector");
        return vec->v.vec.data[vec->v.vec.len - 1];
    }
    if (strcmp(method, "erase") == 0) {
        if (nargs < 1) return make_void();
        int idx = (int)val_to_int(args[0]);
        if (idx >= 0 && idx < vec->v.vec.len) {
            for (int i = idx; i < vec->v.vec.len - 1; i++)
                vec->v.vec.data[i] = vec->v.vec.data[i + 1];
            vec->v.vec.len--;
        }
        return make_void();
    }
    if (strcmp(method, "insert") == 0) {
        if (nargs < 2) return make_void();
        int idx = (int)val_to_int(args[0]);
        if (idx < 0) idx = 0;
        if (idx > vec->v.vec.len) idx = vec->v.vec.len;
        vec_ensure_cap(vec, vec->v.vec.len + 1);
        for (int i = vec->v.vec.len; i > idx; i--)
            vec->v.vec.data[i] = vec->v.vec.data[i - 1];
        vec->v.vec.data[idx] = value_deep_copy(args[1]);
        vec->v.vec.len++;
        return make_void();
    }
    if (strcmp(method, "begin") == 0) return make_int(0);
    if (strcmp(method, "end") == 0) return make_int(vec->v.vec.len);
    if (strcmp(method, "resize") == 0) {
        if (nargs < 1) return make_void();
        int new_size = (int)val_to_int(args[0]);
        if (new_size < 0) new_size = 0;
        vec_ensure_cap(vec, new_size);
        for (int i = vec->v.vec.len; i < new_size; i++)
            vec->v.vec.data[i] = nargs > 1 ? value_deep_copy(args[1]) : make_int(0);
        vec->v.vec.len = new_size;
        return make_void();
    }
    ocpp_error(I, "Unknown vector method '%s'", method);
    return make_void();
}

/* ── map methods ── */
static int map_find_key(OcppValue *mp, OcppValue key) {
    for (int i = 0; i < mp->v.map.len; i++) {
        OcppValue k = mp->v.map.keys[i];
        if (key.type == CVAL_STRING && k.type == CVAL_STRING) {
            if (strcmp(key.v.s ? key.v.s : "", k.v.s ? k.v.s : "") == 0) return i;
        } else if (key.type == CVAL_INT && k.type == CVAL_INT) {
            if (key.v.i == k.v.i) return i;
        } else {
            if (val_to_int(key) == val_to_int(k)) return i;
        }
    }
    return -1;
}

static void map_ensure_cap(OcppValue *mp, int needed) {
    if (needed <= mp->v.map.cap) return;
    int new_cap = mp->v.map.cap * 2;
    if (new_cap < needed) new_cap = needed;
    mp->v.map.keys = (OcppValue *)realloc(mp->v.map.keys, new_cap * sizeof(OcppValue));
    mp->v.map.vals = (OcppValue *)realloc(mp->v.map.vals, new_cap * sizeof(OcppValue));
    mp->v.map.cap = new_cap;
}

static OcppValue *map_get_or_insert(OcppValue *mp, OcppValue key) {
    int idx = map_find_key(mp, key);
    if (idx >= 0) return &mp->v.map.vals[idx];
    map_ensure_cap(mp, mp->v.map.len + 1);
    idx = mp->v.map.len++;
    mp->v.map.keys[idx] = value_deep_copy(key);
    mp->v.map.vals[idx] = make_int(0);
    return &mp->v.map.vals[idx];
}

static OcppValue map_method(OcppInterpreter *I, OcppValue *mp, const char *method, OcppValue *args, int nargs) {
    if (mp->type != CVAL_MAP) ocpp_error(I, "Map method on non-map");

    if (strcmp(method, "size") == 0) return make_int(mp->v.map.len);
    if (strcmp(method, "empty") == 0) return make_bool(mp->v.map.len == 0);
    if (strcmp(method, "clear") == 0) { mp->v.map.len = 0; return make_void(); }
    if (strcmp(method, "count") == 0) {
        if (nargs < 1) return make_int(0);
        return make_int(map_find_key(mp, args[0]) >= 0 ? 1 : 0);
    }
    if (strcmp(method, "find") == 0) {
        if (nargs < 1) return make_int(-1);
        int idx = map_find_key(mp, args[0]);
        return make_int(idx >= 0 ? idx : mp->v.map.len);
    }
    if (strcmp(method, "erase") == 0) {
        if (nargs < 1) return make_void();
        int idx = map_find_key(mp, args[0]);
        if (idx >= 0) {
            for (int i = idx; i < mp->v.map.len - 1; i++) {
                mp->v.map.keys[i] = mp->v.map.keys[i + 1];
                mp->v.map.vals[i] = mp->v.map.vals[i + 1];
            }
            mp->v.map.len--;
        }
        return make_void();
    }
    if (strcmp(method, "insert") == 0) {
        if (nargs < 1) return make_void();
        /* insert(pair) or insert({key, val}) */
        if (args[0].type == CVAL_PAIR) {
            OcppValue key = *args[0].v.pair.first;
            OcppValue val = *args[0].v.pair.second;
            if (map_find_key(mp, key) < 0) {
                map_ensure_cap(mp, mp->v.map.len + 1);
                int idx = mp->v.map.len++;
                mp->v.map.keys[idx] = value_deep_copy(key);
                mp->v.map.vals[idx] = value_deep_copy(val);
            }
        }
        return make_void();
    }
    ocpp_error(I, "Unknown map method '%s'", method);
    return make_void();
}

/* ── STL free functions ── */
static int value_compare(const void *a, const void *b) {
    const OcppValue *va = (const OcppValue *)a;
    const OcppValue *vb = (const OcppValue *)b;
    if (va->type == CVAL_STRING && vb->type == CVAL_STRING) {
        return strcmp(va->v.s ? va->v.s : "", vb->v.s ? vb->v.s : "");
    }
    double da = val_to_double(*va);
    double db = val_to_double(*vb);
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

static OcppValue call_stl_func(OcppInterpreter *I, const char *name, OcppValue *args, int nargs) {
    if (strcmp(name, "sort") == 0) {
        /* sort(vec.begin(), vec.end()) — we treat this as sort on the vector */
        /* With our simplified iterator model, find the vector var */
        /* For now: if called with a vector directly, sort it */
        if (nargs >= 1 && args[0].type == CVAL_VECTOR) {
            qsort(args[0].v.vec.data, args[0].v.vec.len, sizeof(OcppValue), value_compare);
            return make_void();
        }
        return make_void();
    }
    if (strcmp(name, "reverse") == 0) {
        if (nargs >= 1 && args[0].type == CVAL_VECTOR) {
            int len = args[0].v.vec.len;
            for (int i = 0; i < len / 2; i++) {
                OcppValue tmp = args[0].v.vec.data[i];
                args[0].v.vec.data[i] = args[0].v.vec.data[len - 1 - i];
                args[0].v.vec.data[len - 1 - i] = tmp;
            }
            return make_void();
        }
        return make_void();
    }
    if (strcmp(name, "min") == 0) {
        if (nargs < 2) return make_int(0);
        double a = val_to_double(args[0]);
        double b = val_to_double(args[1]);
        return a <= b ? args[0] : args[1];
    }
    if (strcmp(name, "max") == 0) {
        if (nargs < 2) return make_int(0);
        double a = val_to_double(args[0]);
        double b = val_to_double(args[1]);
        return a >= b ? args[0] : args[1];
    }
    if (strcmp(name, "abs") == 0) {
        if (nargs < 1) return make_int(0);
        if (args[0].type == CVAL_INT) return make_int(llabs(args[0].v.i));
        return make_float(fabs(val_to_double(args[0])));
    }
    if (strcmp(name, "swap") == 0) {
        /* swap modifies in place — best effort */
        if (nargs >= 2) {
            OcppValue tmp = args[0];
            args[0] = args[1];
            args[1] = tmp;
        }
        return make_void();
    }
    if (strcmp(name, "make_pair") == 0) {
        if (nargs < 2) ocpp_error(I, "make_pair requires 2 args");
        return make_pair(args[0], args[1]);
    }
    if (strcmp(name, "find") == 0) {
        /* find in vector: find(begin, end, value) — simplified */
        if (nargs >= 3 && args[0].type == CVAL_VECTOR) {
            /* Non-standard usage — just search the vector */
        }
        return make_int(-1);
    }
    if (strcmp(name, "count") == 0) {
        return make_int(0);
    }
    if (strcmp(name, "to_string") == 0) {
        if (nargs < 1) return make_string("");
        char buf[256];
        val_to_str(args[0], buf, sizeof(buf));
        return make_string(buf);
    }
    if (strcmp(name, "stoi") == 0) {
        if (nargs < 1 || args[0].type != CVAL_STRING) return make_int(0);
        return make_int(atoll(args[0].v.s ? args[0].v.s : "0"));
    }
    if (strcmp(name, "stod") == 0 || strcmp(name, "stof") == 0) {
        if (nargs < 1 || args[0].type != CVAL_STRING) return make_float(0);
        return make_float(atof(args[0].v.s ? args[0].v.s : "0"));
    }
    if (strcmp(name, "sqrt") == 0) {
        if (nargs < 1) return make_float(0);
        return make_float(sqrt(val_to_double(args[0])));
    }
    if (strcmp(name, "pow") == 0) {
        if (nargs < 2) return make_float(0);
        return make_float(pow(val_to_double(args[0]), val_to_double(args[1])));
    }
    if (strcmp(name, "getline") == 0) {
        /* stub — set string to empty */
        return make_int(0);
    }
    /* printf compat */
    if (strcmp(name, "printf") == 0) {
        if (nargs < 1 || args[0].type != CVAL_STRING) return make_int(0);
        const char *fmt = args[0].v.s;
        char buf[OCPP_MAX_STRLEN];
        int bi = 0, ai = 1;
        for (int i = 0; fmt[i] && bi < OCPP_MAX_STRLEN - 2; i++) {
            if (fmt[i] == '%' && fmt[i+1]) {
                i++;
                /* Skip flags, width, precision */
                while (fmt[i] == '-' || fmt[i] == '+' || fmt[i] == ' ' || fmt[i] == '0' || fmt[i] == '#') i++;
                while (isdigit((unsigned char)fmt[i])) i++;
                if (fmt[i] == '.') { i++; while (isdigit((unsigned char)fmt[i])) i++; }
                if (fmt[i] == 'l') i++;
                if (fmt[i] == 'l') i++;
                char spec = fmt[i];
                if (ai < nargs) {
                    char tmp[256];
                    switch (spec) {
                        case 'd': case 'i': snprintf(tmp, sizeof(tmp), "%lld", val_to_int(args[ai])); break;
                        case 'u': snprintf(tmp, sizeof(tmp), "%llu", (unsigned long long)val_to_int(args[ai])); break;
                        case 'f': snprintf(tmp, sizeof(tmp), "%f", val_to_double(args[ai])); break;
                        case 'g': snprintf(tmp, sizeof(tmp), "%g", val_to_double(args[ai])); break;
                        case 'c': snprintf(tmp, sizeof(tmp), "%c", (char)val_to_int(args[ai])); break;
                        case 's':
                            if (args[ai].type == CVAL_STRING)
                                snprintf(tmp, sizeof(tmp), "%s", args[ai].v.s ? args[ai].v.s : "(null)");
                            else
                                val_to_str(args[ai], tmp, sizeof(tmp));
                            break;
                        case 'x': snprintf(tmp, sizeof(tmp), "%llx", val_to_int(args[ai])); break;
                        case 'p': snprintf(tmp, sizeof(tmp), "%p", (void *)(intptr_t)val_to_int(args[ai])); break;
                        case '%': snprintf(tmp, sizeof(tmp), "%%"); ai--; break;
                        default: tmp[0] = spec; tmp[1] = '\0'; break;
                    }
                    int tl = (int)strlen(tmp);
                    if (bi + tl < OCPP_MAX_STRLEN - 1) { memcpy(buf + bi, tmp, tl); bi += tl; }
                    ai++;
                }
            } else if (fmt[i] == '\\' && fmt[i+1] == 'n') {
                buf[bi++] = '\n'; i++;
            } else {
                buf[bi++] = fmt[i];
            }
        }
        buf[bi] = '\0';
        out_append(I, buf);
        return make_int(bi);
    }
    /* C++ specific: endl (if called as function) */
    if (strcmp(name, "endl") == 0) {
        return make_string("\n");
    }

    ocpp_error(I, "Unknown function '%s'", name);
    return make_void();
}

/* ══════════════════════════════════════════════
 *  Evaluator
 * ══════════════════════════════════════════════ */

/* Get a mutable pointer to a variable's value from an ident/member/index node */
static OcppValue *eval_lvalue(OcppInterpreter *I, OcppNode *n) {
    if (n->type == NP_IDENT) {
        OcppVar *v = scope_get_var(I, n->name);
        if (v->is_reference && v->ref_target) return v->ref_target;
        return &v->val;
    }
    if (n->type == NP_MEMBER) {
        OcppValue *obj = eval_lvalue(I, n->children[0]);
        if (obj->type == CVAL_OBJECT) {
            for (int i = 0; i < obj->v.obj.n_fields; i++) {
                if (strcmp(obj->v.obj.field_names[i], n->name) == 0)
                    return &obj->v.obj.fields[i];
            }
            ocpp_error(I, "No field '%s'", n->name);
        }
        if (obj->type == CVAL_PAIR) {
            if (strcmp(n->name, "first") == 0) return obj->v.pair.first;
            if (strcmp(n->name, "second") == 0) return obj->v.pair.second;
        }
        ocpp_error(I, "Cannot access member '%s'", n->name);
    }
    if (n->type == NP_ARROW) {
        OcppValue ptr_val = eval_node(I, n->children[0]);
        OcppValue *obj = NULL;
        if (ptr_val.type == CVAL_PTR) {
            obj = vmem_get(I, ptr_val.v.ptr.addr);
        } else if (ptr_val.type == CVAL_OBJECT) {
            /* this->field style */
            obj = &ptr_val;
        }
        if (obj && obj->type == CVAL_OBJECT) {
            for (int i = 0; i < obj->v.obj.n_fields; i++) {
                if (strcmp(obj->v.obj.field_names[i], n->name) == 0)
                    return &obj->v.obj.fields[i];
            }
        }
        ocpp_error(I, "No field '%s' via ->", n->name);
    }
    if (n->type == NP_INDEX) {
        OcppValue *arr = eval_lvalue(I, n->children[0]);
        OcppValue idx_val = eval_node(I, n->children[1]);
        if (arr->type == CVAL_VECTOR) {
            int idx = (int)val_to_int(idx_val);
            if (idx < 0 || idx >= arr->v.vec.len) {
                /* Auto-grow for assignment */
                vec_ensure_cap(arr, idx + 1);
                while (arr->v.vec.len <= idx) arr->v.vec.data[arr->v.vec.len++] = make_int(0);
            }
            return &arr->v.vec.data[idx];
        }
        if (arr->type == CVAL_MAP) {
            return map_get_or_insert(arr, idx_val);
        }
        if (arr->type == CVAL_STRING) {
            /* Can't return pointer to char in string easily;
               handle in eval_node for read, and assignment separately */
        }
        ocpp_error(I, "Cannot index this type");
    }
    if (n->type == NP_DEREF) {
        OcppValue ptr_val = eval_node(I, n->children[0]);
        if (ptr_val.type == CVAL_PTR) {
            OcppValue *target = vmem_get(I, ptr_val.v.ptr.addr);
            if (!target) ocpp_error(I, "Null pointer dereference");
            return target;
        }
        ocpp_error(I, "Cannot dereference non-pointer");
    }
    if (n->type == NP_THIS_EXPR) {
        if (I->this_depth > 0) return I->this_stack[I->this_depth - 1];
        ocpp_error(I, "'this' used outside class");
    }
    ocpp_error(I, "Not an lvalue");
    return NULL;
}

static OcppValue eval_node(OcppInterpreter *I, OcppNode *n) {
    if (!n) return make_void();

    switch (n->type) {
    case NP_INT_LIT: return make_int((long long)n->num_val);
    case NP_FLOAT_LIT: return make_float(n->num_val);
    case NP_CHAR_LIT: return make_char((char)(int)n->num_val);
    case NP_BOOL_LIT: return make_bool((int)n->num_val);
    case NP_NULLPTR_LIT: return make_nullptr_val();
    case NP_STRING_LIT: return make_string(n->str_val);

    case NP_IDENT: {
        OcppVar *v = scope_find(I->current_scope, n->name);
        if (v) {
            if (v->is_reference && v->ref_target) return *v->ref_target;
            return v->val;
        }
        /* Check enum values */
        for (int i = 0; i < I->n_enum_vals; i++) {
            if (strcmp(I->enum_vals[i].name, n->name) == 0)
                return make_int(I->enum_vals[i].value);
        }
        /* Check if it's a function name */
        for (int i = 0; i < I->n_funcs; i++) {
            if (strcmp(I->funcs[i].name, n->name) == 0)
                return make_string(n->name); /* function as value */
        }
        /* Check class name (for constructor) */
        if (find_class(I, n->name)) {
            return make_string(n->name);
        }
        ocpp_error(I, "Line %d: undefined variable '%s'", n->line, n->name);
        break;
    }

    case NP_THIS_EXPR: {
        if (I->this_depth > 0) return *I->this_stack[I->this_depth - 1];
        ocpp_error(I, "'this' used outside class");
        break;
    }

    case NP_ASSIGN: {
        OcppValue val = eval_node(I, n->children[1]);
        OcppValue *lv = eval_lvalue(I, n->children[0]);
        *lv = val;
        return val;
    }

    case NP_COMPOUND_ASSIGN: {
        OcppValue *lv = eval_lvalue(I, n->children[0]);
        OcppValue rhs = eval_node(I, n->children[1]);
        OcppValue lhs = *lv;
        OcppValue result;
        /* String += */
        if (lhs.type == CVAL_STRING && n->op == CTOK_PLUS_ASSIGN) {
            char buf[OCPP_MAX_STRLEN];
            const char *rs = val_to_str(rhs, buf, sizeof(buf));
            const char *ls = lhs.v.s ? lhs.v.s : "";
            int ll = (int)strlen(ls), rl = (int)strlen(rs);
            char *ns = (char *)malloc(ll + rl + 1);
            memcpy(ns, ls, ll);
            memcpy(ns + ll, rs, rl + 1);
            result = make_string(ns);
            free(ns);
            if (lv->v.s) free(lv->v.s);
            *lv = result;
            return result;
        }
        /* Numeric */
        if (is_numeric(lhs) && is_numeric(rhs)) {
            int use_float = (lhs.type == CVAL_FLOAT || lhs.type == CVAL_DOUBLE ||
                             rhs.type == CVAL_FLOAT || rhs.type == CVAL_DOUBLE);
            double df = val_to_double(lhs);
            long long di = val_to_int(lhs);
            switch (n->op) {
                case CTOK_PLUS_ASSIGN:  if (use_float) result = make_float(df + val_to_double(rhs)); else result = make_int(di + val_to_int(rhs)); break;
                case CTOK_MINUS_ASSIGN: if (use_float) result = make_float(df - val_to_double(rhs)); else result = make_int(di - val_to_int(rhs)); break;
                case CTOK_STAR_ASSIGN:  if (use_float) result = make_float(df * val_to_double(rhs)); else result = make_int(di * val_to_int(rhs)); break;
                case CTOK_SLASH_ASSIGN: if (use_float) result = make_float(df / val_to_double(rhs)); else { long long rv = val_to_int(rhs); result = make_int(rv ? di / rv : 0); } break;
                case CTOK_PERCENT_ASSIGN: { long long rv = val_to_int(rhs); result = make_int(rv ? di % rv : 0); } break;
                case CTOK_AMP_ASSIGN: result = make_int(di & val_to_int(rhs)); break;
                case CTOK_PIPE_ASSIGN: result = make_int(di | val_to_int(rhs)); break;
                case CTOK_CARET_ASSIGN: result = make_int(di ^ val_to_int(rhs)); break;
                case CTOK_LSHIFT_ASSIGN: result = make_int(di << val_to_int(rhs)); break;
                case CTOK_RSHIFT_ASSIGN: result = make_int(di >> val_to_int(rhs)); break;
                default: result = lhs; break;
            }
        } else {
            result = lhs;
        }
        *lv = result;
        return result;
    }

    case NP_ADD: case NP_SUB: case NP_MUL: case NP_DIV: case NP_MOD:
    case NP_EQ: case NP_NEQ: case NP_LT: case NP_GT: case NP_LE: case NP_GE:
    case NP_LSHIFT: case NP_RSHIFT:
    case NP_BIT_AND: case NP_BIT_OR: case NP_BIT_XOR: {
        OcppValue lhs = eval_node(I, n->children[0]);
        OcppValue rhs = eval_node(I, n->children[1]);

        /* String + string */
        if (n->type == NP_ADD && (lhs.type == CVAL_STRING || rhs.type == CVAL_STRING)) {
            char lbuf[OCPP_MAX_STRLEN], rbuf[OCPP_MAX_STRLEN];
            const char *ls = val_to_str(lhs, lbuf, sizeof(lbuf));
            const char *rs = val_to_str(rhs, rbuf, sizeof(rbuf));
            int ll = (int)strlen(ls), rl = (int)strlen(rs);
            char *ns = (char *)malloc(ll + rl + 1);
            memcpy(ns, ls, ll);
            memcpy(ns + ll, rs, rl + 1);
            OcppValue result = make_string(ns);
            free(ns);
            return result;
        }

        /* String comparisons */
        if ((lhs.type == CVAL_STRING && rhs.type == CVAL_STRING) &&
            (n->type == NP_EQ || n->type == NP_NEQ || n->type == NP_LT ||
             n->type == NP_GT || n->type == NP_LE || n->type == NP_GE)) {
            int cmp = strcmp(lhs.v.s ? lhs.v.s : "", rhs.v.s ? rhs.v.s : "");
            switch (n->type) {
                case NP_EQ: return make_bool(cmp == 0);
                case NP_NEQ: return make_bool(cmp != 0);
                case NP_LT: return make_bool(cmp < 0);
                case NP_GT: return make_bool(cmp > 0);
                case NP_LE: return make_bool(cmp <= 0);
                case NP_GE: return make_bool(cmp >= 0);
                default: break;
            }
        }

        /* Operator overloading for objects */
        if (lhs.type == CVAL_OBJECT) {
            OcppClassDef *cd = find_class(I, lhs.v.obj.class_name);
            if (cd) {
                int op_tok = 0;
                switch (n->type) {
                    case NP_ADD: op_tok = CTOK_PLUS; break;
                    case NP_SUB: op_tok = CTOK_MINUS; break;
                    case NP_MUL: op_tok = CTOK_STAR; break;
                    case NP_EQ: op_tok = CTOK_EQ; break;
                    case NP_NEQ: op_tok = CTOK_NEQ; break;
                    case NP_LT: op_tok = CTOK_LT; break;
                    case NP_GT: op_tok = CTOK_GT; break;
                    default: break;
                }
                for (int i = 0; i < cd->n_operators; i++) {
                    if (cd->operators[i].op == op_tok) {
                        OcppNode *op_node = cd->operators[i].node;
                        if (I->this_depth >= OCPP_MAX_STACK) ocpp_error(I, "this stack overflow");
                        I->this_stack[I->this_depth++] = &lhs;
                        OcppScope *prev = I->current_scope;
                        OcppScope *op_scope = scope_create(I->global_scope);
                        I->current_scope = op_scope;
                        if (op_node->n_params > 0) {
                            scope_set(I, op_scope, op_node->param_names[0], rhs);
                        }
                        exec_node(I, op_node->children[0]);
                        OcppValue result = I->return_val;
                        I->returning = 0;
                        I->current_scope = prev;
                        scope_destroy(op_scope);
                        I->this_depth--;
                        return result;
                    }
                }
            }
        }

        /* Numeric operations */
        int use_float = (lhs.type == CVAL_FLOAT || lhs.type == CVAL_DOUBLE ||
                         rhs.type == CVAL_FLOAT || rhs.type == CVAL_DOUBLE);

        if (use_float) {
            double a = val_to_double(lhs), b = val_to_double(rhs);
            switch (n->type) {
                case NP_ADD: return make_float(a + b);
                case NP_SUB: return make_float(a - b);
                case NP_MUL: return make_float(a * b);
                case NP_DIV: return make_float(b != 0 ? a / b : 0);
                case NP_MOD: return make_float(b != 0 ? fmod(a, b) : 0);
                case NP_EQ: return make_bool(a == b);
                case NP_NEQ: return make_bool(a != b);
                case NP_LT: return make_bool(a < b);
                case NP_GT: return make_bool(a > b);
                case NP_LE: return make_bool(a <= b);
                case NP_GE: return make_bool(a >= b);
                default: break;
            }
        }
        long long a = val_to_int(lhs), b = val_to_int(rhs);
        switch (n->type) {
            case NP_ADD: return make_int(a + b);
            case NP_SUB: return make_int(a - b);
            case NP_MUL: return make_int(a * b);
            case NP_DIV: return make_int(b ? a / b : 0);
            case NP_MOD: return make_int(b ? a % b : 0);
            case NP_EQ: return make_bool(a == b);
            case NP_NEQ: return make_bool(a != b);
            case NP_LT: return make_bool(a < b);
            case NP_GT: return make_bool(a > b);
            case NP_LE: return make_bool(a <= b);
            case NP_GE: return make_bool(a >= b);
            case NP_LSHIFT: return make_int(a << b);
            case NP_RSHIFT: return make_int(a >> b);
            case NP_BIT_AND: return make_int(a & b);
            case NP_BIT_OR: return make_int(a | b);
            case NP_BIT_XOR: return make_int(a ^ b);
            default: break;
        }
        break;
    }

    case NP_AND: {
        OcppValue lhs = eval_node(I, n->children[0]);
        if (!val_to_bool(lhs)) return make_bool(0);
        return make_bool(val_to_bool(eval_node(I, n->children[1])));
    }
    case NP_OR: {
        OcppValue lhs = eval_node(I, n->children[0]);
        if (val_to_bool(lhs)) return make_bool(1);
        return make_bool(val_to_bool(eval_node(I, n->children[1])));
    }

    case NP_NEG: return is_numeric(eval_node(I, n->children[0])) ?
        (eval_node(I, n->children[0]).type == CVAL_DOUBLE || eval_node(I, n->children[0]).type == CVAL_FLOAT ?
         make_float(-val_to_double(eval_node(I, n->children[0]))) :
         make_int(-val_to_int(eval_node(I, n->children[0])))) : make_int(0);
    case NP_NOT: return make_bool(!val_to_bool(eval_node(I, n->children[0])));
    case NP_BIT_NOT: return make_int(~val_to_int(eval_node(I, n->children[0])));

    case NP_PRE_INC: case NP_PRE_DEC: {
        OcppValue *lv = eval_lvalue(I, n->children[0]);
        if (lv->type == CVAL_INT) lv->v.i += (n->type == NP_PRE_INC) ? 1 : -1;
        else if (lv->type == CVAL_DOUBLE || lv->type == CVAL_FLOAT) lv->v.f += (n->type == NP_PRE_INC) ? 1.0 : -1.0;
        return *lv;
    }
    case NP_POST_INC: case NP_POST_DEC: {
        OcppValue *lv = eval_lvalue(I, n->children[0]);
        OcppValue old = *lv;
        if (lv->type == CVAL_INT) lv->v.i += (n->type == NP_POST_INC) ? 1 : -1;
        else if (lv->type == CVAL_DOUBLE || lv->type == CVAL_FLOAT) lv->v.f += (n->type == NP_POST_INC) ? 1.0 : -1.0;
        return old;
    }

    case NP_ADDR: {
        OcppValue *lv = eval_lvalue(I, n->children[0]);
        /* Allocate vmem if not already */
        OcppVar *v = (n->children[0]->type == NP_IDENT) ?
            scope_find(I->current_scope, n->children[0]->name) : NULL;
        if (v && v->vmem_addr == 0) {
            int addr = vmem_alloc(I, 1);
            if (addr) {
                *vmem_get(I, addr) = v->val;
                v->vmem_addr = addr;
            }
        }
        int addr = v ? v->vmem_addr : 0;
        return make_ptr(addr, lv->type, 1);
    }
    case NP_DEREF: {
        OcppValue val = eval_node(I, n->children[0]);
        if (val.type == CVAL_PTR) {
            OcppValue *target = vmem_get(I, val.v.ptr.addr);
            if (!target) ocpp_error(I, "Null pointer dereference");
            return *target;
        }
        ocpp_error(I, "Cannot dereference non-pointer");
        break;
    }

    case NP_SIZEOF: {
        if (n->n_children > 0) {
            OcppValue v = eval_node(I, n->children[0]);
            switch (v.type) {
                case CVAL_INT: return make_int(sizeof(long long));
                case CVAL_FLOAT: return make_int(sizeof(float));
                case CVAL_DOUBLE: return make_int(sizeof(double));
                case CVAL_CHAR: return make_int(1);
                case CVAL_BOOL: return make_int(1);
                default: return make_int(8);
            }
        }
        switch (n->val_type) {
            case CVAL_INT: return make_int(4);
            case CVAL_FLOAT: return make_int(4);
            case CVAL_DOUBLE: return make_int(8);
            case CVAL_CHAR: return make_int(1);
            case CVAL_BOOL: return make_int(1);
            default: return make_int(8);
        }
    }

    case NP_CAST: {
        OcppValue val = eval_node(I, n->children[0]);
        switch (n->val_type) {
            case CVAL_INT: return make_int(val_to_int(val));
            case CVAL_FLOAT: case CVAL_DOUBLE: return make_float(val_to_double(val));
            case CVAL_CHAR: return make_char((char)val_to_int(val));
            case CVAL_BOOL: return make_bool(val_to_bool(val));
            default: return val;
        }
    }

    case NP_TERNARY: {
        return val_to_bool(eval_node(I, n->children[0])) ?
            eval_node(I, n->children[1]) : eval_node(I, n->children[2]);
    }

    case NP_INDEX: {
        OcppValue arr = eval_node(I, n->children[0]);
        OcppValue idx = eval_node(I, n->children[1]);
        if (arr.type == CVAL_VECTOR) {
            int i = (int)val_to_int(idx);
            if (i >= 0 && i < arr.v.vec.len) return arr.v.vec.data[i];
            ocpp_error(I, "Vector index %d out of range [0, %d)", i, arr.v.vec.len);
        }
        if (arr.type == CVAL_STRING) {
            int i = (int)val_to_int(idx);
            const char *s = arr.v.s ? arr.v.s : "";
            if (i >= 0 && i < (int)strlen(s)) return make_char(s[i]);
            ocpp_error(I, "String index out of range");
        }
        if (arr.type == CVAL_MAP) {
            int i = map_find_key(&arr, idx);
            if (i >= 0) return arr.v.map.vals[i];
            return make_int(0); /* default */
        }
        ocpp_error(I, "Cannot index this type");
        break;
    }

    case NP_MEMBER: {
        OcppValue obj = eval_node(I, n->children[0]);
        /* Object field access */
        if (obj.type == CVAL_OBJECT) {
            for (int i = 0; i < obj.v.obj.n_fields; i++) {
                if (strcmp(obj.v.obj.field_names[i], n->name) == 0)
                    return obj.v.obj.fields[i];
            }
            ocpp_error(I, "No field '%s' in class '%s'", n->name, obj.v.obj.class_name);
        }
        if (obj.type == CVAL_PAIR) {
            if (strcmp(n->name, "first") == 0) return *obj.v.pair.first;
            if (strcmp(n->name, "second") == 0) return *obj.v.pair.second;
        }
        ocpp_error(I, "Cannot access member '%s'", n->name);
        break;
    }

    case NP_ARROW: {
        OcppValue ptr = eval_node(I, n->children[0]);
        OcppValue *obj = NULL;
        if (ptr.type == CVAL_PTR) obj = vmem_get(I, ptr.v.ptr.addr);
        if (obj && obj->type == CVAL_OBJECT) {
            for (int i = 0; i < obj->v.obj.n_fields; i++) {
                if (strcmp(obj->v.obj.field_names[i], n->name) == 0)
                    return obj->v.obj.fields[i];
            }
        }
        ocpp_error(I, "Cannot access '%s' via ->", n->name);
        break;
    }

    case NP_CALL: {
        /* Evaluate arguments */
        OcppValue args[16];
        int nargs = n->n_stmts;
        if (nargs > 16) nargs = 16;
        for (int i = 0; i < nargs; i++) {
            args[i] = eval_node(I, n->stmts[i]);
        }

        /* Method call: obj.method() or obj->method() */
        if (n->op == 1 || n->op == 2) {
            OcppValue *obj_ptr = NULL;
            OcppValue obj_val;
            if (n->op == 1 && n->n_children > 0) {
                /* arrow: evaluate pointer, get object */
                OcppValue ptr = eval_node(I, n->children[0]);
                if (ptr.type == CVAL_PTR) obj_ptr = vmem_get(I, ptr.v.ptr.addr);
                if (!obj_ptr) ocpp_error(I, "Null pointer in method call");
                obj_val = *obj_ptr;
            } else if (n->n_children > 0) {
                /* dot */
                obj_ptr = eval_lvalue(I, n->children[0]);
                obj_val = *obj_ptr;
            }

            /* STL type methods */
            if (obj_val.type == CVAL_STRING) {
                OcppValue result = string_method(I, obj_ptr ? obj_ptr : &obj_val, n->name, args, nargs);
                return result;
            }
            if (obj_val.type == CVAL_VECTOR) {
                OcppValue result = vector_method(I, obj_ptr ? obj_ptr : &obj_val, n->name, args, nargs);
                return result;
            }
            if (obj_val.type == CVAL_MAP) {
                OcppValue result = map_method(I, obj_ptr ? obj_ptr : &obj_val, n->name, args, nargs);
                return result;
            }

            /* Class method call */
            if (obj_val.type == CVAL_OBJECT) {
                return call_method(I, obj_ptr ? obj_ptr : &obj_val, n->name, args, nargs);
            }
            ocpp_error(I, "Cannot call method '%s' on this type", n->name);
        }

        /* string() constructor */
        if (strcmp(n->name, "string") == 0) {
            if (nargs > 0 && args[0].type == CVAL_STRING) return value_deep_copy(args[0]);
            if (nargs > 0) { char buf[256]; return make_string(val_to_str(args[0], buf, sizeof(buf))); }
            return make_string("");
        }

        /* Class constructor call: ClassName(args) */
        OcppClassDef *cd = find_class(I, n->name);
        if (cd) {
            return create_object(I, n->name, args, nargs);
        }

        /* User-defined function */
        for (int i = 0; i < I->n_funcs; i++) {
            if (strcmp(I->funcs[i].name, n->name) == 0) {
                return call_function(I, n->name, args, nargs);
            }
        }

        /* Lambda call */
        OcppVar *lv = scope_find(I->current_scope, n->name);
        if (lv && lv->val.type == CVAL_LAMBDA) {
            OcppValue *lambda = &lv->val;
            OcppScope *prev = I->current_scope;
            OcppScope *lscope = scope_create(I->global_scope);
            I->current_scope = lscope;
            /* Bind captures */
            for (int i = 0; i < lambda->v.lambda.n_captures; i++) {
                scope_set(I, lscope, lambda->v.lambda.capture_names[i],
                          value_deep_copy(lambda->v.lambda.captures[i]));
            }
            /* Bind params */
            for (int i = 0; i < lambda->v.lambda.n_params && i < nargs; i++) {
                scope_set(I, lscope, lambda->v.lambda.param_names[i], args[i]);
            }
            exec_node(I, lambda->v.lambda.body);
            OcppValue result = I->returning ? I->return_val : make_void();
            I->returning = 0;
            I->current_scope = prev;
            scope_destroy(lscope);
            return result;
        }

        /* STL / built-in functions */
        return call_stl_func(I, n->name, args, nargs);
    }

    case NP_COUT_EXPR: {
        for (int i = 0; i < n->n_stmts; i++) {
            OcppValue val = eval_node(I, n->stmts[i]);
            char buf[OCPP_MAX_STRLEN];
            const char *s = val_to_str(val, buf, sizeof(buf));
            out_append(I, s);
        }
        return make_void();
    }

    case NP_CIN_EXPR: {
        /* Stub: assign 0/empty to each variable */
        for (int i = 0; i < n->n_stmts; i++) {
            if (n->stmts[i]->type == NP_IDENT) {
                OcppVar *v = scope_find(I->current_scope, n->stmts[i]->name);
                if (v) {
                    if (v->val.type == CVAL_STRING) {
                        if (v->val.v.s) free(v->val.v.s);
                        v->val = make_string("");
                    } else if (v->val.type == CVAL_INT) {
                        v->val = make_int(0);
                    } else if (v->val.type == CVAL_DOUBLE || v->val.type == CVAL_FLOAT) {
                        v->val = make_float(0);
                    }
                }
            }
        }
        return make_void();
    }

    case NP_NEW_EXPR: {
        /* Allocate object on vmem heap */
        OcppClassDef *cdef = find_class(I, n->class_name);
        if (cdef) {
            OcppValue args[16];
            int nargs = n->n_stmts > 16 ? 16 : n->n_stmts;
            for (int i = 0; i < nargs; i++) args[i] = eval_node(I, n->stmts[i]);
            OcppValue obj = create_object(I, n->class_name, args, nargs);
            int addr = vmem_alloc(I, 1);
            if (!addr) ocpp_error(I, "Out of memory for new");
            *vmem_get(I, addr) = obj;
            return make_ptr(addr, CVAL_OBJECT, 1);
        }
        /* new for basic types */
        int addr = vmem_alloc(I, 1);
        if (!addr) ocpp_error(I, "Out of memory for new");
        OcppValue init_val = make_int(0);
        if (n->n_stmts > 0) init_val = eval_node(I, n->stmts[0]);
        *vmem_get(I, addr) = init_val;
        return make_ptr(addr, init_val.type, 1);
    }

    case NP_DELETE_EXPR: {
        OcppValue ptr = eval_node(I, n->children[0]);
        if (ptr.type == CVAL_PTR && ptr.v.ptr.addr > 0) {
            OcppValue *target = vmem_get(I, ptr.v.ptr.addr);
            if (target && target->type == CVAL_OBJECT) {
                /* Run destructor */
                OcppClassDef *cdef = find_class(I, target->v.obj.class_name);
                if (cdef && cdef->destructor && cdef->destructor->n_children > 0) {
                    if (I->this_depth < OCPP_MAX_STACK) {
                        I->this_stack[I->this_depth++] = target;
                        OcppScope *prev = I->current_scope;
                        OcppScope *ds = scope_create(I->global_scope);
                        I->current_scope = ds;
                        exec_node(I, cdef->destructor->children[0]);
                        I->returning = 0;
                        I->current_scope = prev;
                        scope_destroy(ds);
                        I->this_depth--;
                    }
                }
            }
            /* Zero out memory */
            if (target) memset(target, 0, sizeof(OcppValue));
        }
        return make_void();
    }

    case NP_THROW_EXPR: {
        OcppValue thrown = (n->n_children > 0) ? eval_node(I, n->children[0]) : make_int(0);
        I->cur_exception.value = thrown;
        I->cur_exception.active = 1;
        if (thrown.type == CVAL_STRING) {
            strncpy(I->cur_exception.type_name, "string", 63);
        } else if (thrown.type == CVAL_INT) {
            strncpy(I->cur_exception.type_name, "int", 63);
        } else if (thrown.type == CVAL_OBJECT) {
            strncpy(I->cur_exception.type_name, thrown.v.obj.class_name, 63);
        } else {
            strcpy(I->cur_exception.type_name, "unknown");
        }
        if (I->catch_depth > 0) {
            longjmp(I->catch_jmp[I->catch_depth - 1], 1);
        }
        ocpp_error(I, "Unhandled exception");
        break;
    }

    case NP_LAMBDA_EXPR: {
        OcppValue lval;
        memset(&lval, 0, sizeof(lval));
        lval.type = CVAL_LAMBDA;
        int n_captures = n->op; /* stored in op field */
        lval.v.lambda.n_captures = 0;
        lval.v.lambda.captures = (OcppValue *)calloc(n_captures > 0 ? n_captures : 1, sizeof(OcppValue));
        lval.v.lambda.capture_names = (char (*)[64])calloc(n_captures > 0 ? n_captures : 1, 64);
        for (int i = 0; i < n_captures; i++) {
            const char *cap_name = n->param_names[i];
            if (strcmp(cap_name, "=") == 0) continue; /* capture-all — simplified */
            OcppVar *cv = scope_find(I->current_scope, cap_name);
            if (cv) {
                strcpy(lval.v.lambda.capture_names[lval.v.lambda.n_captures], cap_name);
                lval.v.lambda.captures[lval.v.lambda.n_captures] = value_deep_copy(cv->val);
                lval.v.lambda.n_captures++;
            }
        }
        lval.v.lambda.n_params = n->n_params;
        lval.v.lambda.param_names = (char (*)[64])calloc(n->n_params > 0 ? n->n_params : 1, 64);
        lval.v.lambda.param_types = (OcppValType *)calloc(n->n_params > 0 ? n->n_params : 1, sizeof(OcppValType));
        for (int i = 0; i < n->n_params; i++) {
            strcpy(lval.v.lambda.param_names[i], n->param_names[n_captures + i]);
            lval.v.lambda.param_types[i] = n->param_types[i];
        }
        lval.v.lambda.body = n->children[0];
        return lval;
    }

    default:
        break;
    }

    return make_void();
}

/* ── Call user-defined function ── */
static OcppValue call_function(OcppInterpreter *I, const char *name, OcppValue *args, int nargs) {
    OcppFunc *fn = NULL;
    for (int i = 0; i < I->n_funcs; i++) {
        if (strcmp(I->funcs[i].name, name) == 0) { fn = &I->funcs[i]; break; }
    }
    if (!fn || !fn->node) ocpp_error(I, "Undefined function '%s'", name);

    OcppNode *fnode = fn->node;
    if (!fnode->n_children || !fnode->children[0]) ocpp_error(I, "Function '%s' has no body", name);

    OcppScope *prev = I->current_scope;
    OcppScope *fscope = scope_create(I->global_scope);
    I->current_scope = fscope;

    /* Bind parameters */
    for (int i = 0; i < fnode->n_params && i < nargs; i++) {
        OcppVar *pv = scope_set(I, fscope, fnode->param_names[i], args[i]);
        if (fnode->param_is_ref[i]) {
            /* For ref params, we'd need lvalue from the caller — simplified */
            pv->is_reference = 0;
        }
    }

    exec_node(I, fnode->children[0]);
    OcppValue result = I->returning ? I->return_val : make_void();
    I->returning = 0;

    I->current_scope = prev;
    scope_destroy(fscope);
    return result;
}

/* ── Call class method ── */
static OcppValue call_method(OcppInterpreter *I, OcppValue *obj, const char *method, OcppValue *args, int nargs) {
    if (obj->type != CVAL_OBJECT) ocpp_error(I, "Method call on non-object");

    /* Look up method in class (and base classes for virtual dispatch) */
    const char *class_name = obj->v.obj.class_name;
    OcppNode *method_node = NULL;

    while (class_name[0]) {
        OcppClassDef *cd = find_class(I, class_name);
        if (!cd) break;
        for (int i = 0; i < cd->n_methods; i++) {
            if (strcmp(cd->methods[i].name, method) == 0) {
                method_node = cd->methods[i].node;
                break;
            }
        }
        if (method_node) break;
        class_name = cd->base_class;
    }

    if (!method_node) ocpp_error(I, "Unknown method '%s' in class '%s'", method, obj->v.obj.class_name);
    if (!method_node->n_children || !method_node->children[0])
        ocpp_error(I, "Method '%s' has no body", method);

    /* Set up scope with this pointer */
    if (I->this_depth >= OCPP_MAX_STACK) ocpp_error(I, "this stack overflow");
    I->this_stack[I->this_depth++] = obj;
    char prev_class[64];
    strcpy(prev_class, I->current_class);
    strcpy(I->current_class, obj->v.obj.class_name);

    OcppScope *prev = I->current_scope;
    OcppScope *mscope = scope_create(I->global_scope);
    I->current_scope = mscope;

    /* Bind this fields as variables in scope */
    for (int i = 0; i < obj->v.obj.n_fields; i++) {
        OcppVar *fv = scope_set(I, mscope, obj->v.obj.field_names[i], obj->v.obj.fields[i]);
        fv->is_reference = 1;
        fv->ref_target = &obj->v.obj.fields[i];
    }

    /* Bind params */
    for (int i = 0; i < method_node->n_params && i < nargs; i++) {
        scope_set(I, mscope, method_node->param_names[i], args[i]);
    }

    exec_node(I, method_node->children[0]);
    OcppValue result = I->returning ? I->return_val : make_void();
    I->returning = 0;

    I->current_scope = prev;
    scope_destroy(mscope);
    I->this_depth--;
    strcpy(I->current_class, prev_class);
    return result;
}

/* ══════════════════════════════════════════════
 *  Statement execution
 * ══════════════════════════════════════════════ */

static void exec_node(OcppInterpreter *I, OcppNode *n) {
    if (!n || I->returning || I->breaking || I->continuing) return;

    switch (n->type) {
    case NP_PROGRAM:
    case NP_BLOCK:
    case NP_NAMESPACE_DECL: {
        OcppScope *prev = I->current_scope;
        if (n->type == NP_BLOCK || n->type == NP_NAMESPACE_DECL) {
            I->current_scope = scope_create(I->current_scope);
        }
        if (n->type == NP_NAMESPACE_DECL && n->n_children > 0) {
            OcppNode *body = n->children[0];
            for (int i = 0; i < body->n_stmts; i++) {
                exec_node(I, body->stmts[i]);
                if (I->returning || I->breaking) break;
            }
        } else {
            for (int i = 0; i < n->n_stmts; i++) {
                exec_node(I, n->stmts[i]);
                if (I->returning || I->breaking) break;
            }
        }
        if (n->type == NP_BLOCK || n->type == NP_NAMESPACE_DECL) {
            OcppScope *old = I->current_scope;
            I->current_scope = prev;
            scope_destroy(old);
        }
        break;
    }

    case NP_USING_DECL: {
        if (strcmp(n->name, "std") == 0) {
            I->using_namespace_std = 1;
        }
        break;
    }

    case NP_CLASS_DECL: {
        register_class(I, n);
        break;
    }

    case NP_TEMPLATE_DECL: {
        /* Store template for later instantiation */
        if (n->n_children > 0 && n->children[0]->type == NP_FUNCDECL) {
            OcppNode *fn = n->children[0];
            if (I->n_templates < OCPP_MAX_TEMPLATES) {
                OcppTemplateDef *td = &I->templates[I->n_templates++];
                strcpy(td->name, fn->name);
                strcpy(td->type_param, n->type_param);
                td->node = fn;
            }
            /* Also register as a regular function for direct use */
            if (I->n_funcs < OCPP_MAX_FUNCS) {
                OcppFunc *f = &I->funcs[I->n_funcs++];
                strcpy(f->name, fn->name);
                f->node = fn;
                f->class_name[0] = '\0';
            }
        }
        break;
    }

    case NP_FUNCDECL: {
        if (I->n_funcs >= OCPP_MAX_FUNCS) ocpp_error(I, "Too many functions");
        OcppFunc *f = &I->funcs[I->n_funcs++];
        strncpy(f->name, n->name, 255);
        f->node = n;
        f->class_name[0] = '\0';
        break;
    }

    case NP_VARDECL: {
        OcppValue init_val;
        int is_auto = (strcmp(n->label, "auto") == 0);

        if (n->val_type == CVAL_VECTOR) {
            init_val = make_vector(CVAL_INT);
            if (n->n_children > 0 && n->children[0]) {
                OcppValue rv = eval_node(I, n->children[0]);
                if (rv.type == CVAL_VECTOR) init_val = rv;
            }
            /* Init from initializer list in stmts */
            if (n->stmts && n->n_stmts > 0) {
                for (int i = 0; i < n->n_stmts; i++) {
                    OcppValue elem = eval_node(I, n->stmts[i]);
                    vec_ensure_cap(&init_val, init_val.v.vec.len + 1);
                    init_val.v.vec.data[init_val.v.vec.len++] = elem;
                }
            }
        } else if (n->val_type == CVAL_MAP) {
            init_val = make_map(CVAL_STRING, CVAL_INT);
        } else if (n->val_type == CVAL_PAIR) {
            if (n->n_children > 0) {
                init_val = eval_node(I, n->children[0]);
            } else {
                init_val = make_pair(make_int(0), make_int(0));
            }
        } else if (n->val_type == CVAL_OBJECT && n->class_name[0]) {
            /* Object construction */
            if (n->n_children > 0 && n->children[0]) {
                OcppValue cv = eval_node(I, n->children[0]);
                if (cv.type == CVAL_OBJECT) {
                    init_val = cv;
                } else {
                    OcppValue args[1] = {cv};
                    init_val = create_object(I, n->class_name, args, 1);
                }
            } else {
                init_val = create_object(I, n->class_name, NULL, 0);
            }
        } else if (n->n_children > 0 && n->children[0]) {
            if (n->children[0]->type == NP_ARRAY_INIT) {
                OcppNode *ai = n->children[0];
                init_val = make_vector(n->val_type);
                for (int i = 0; i < ai->n_stmts; i++) {
                    OcppValue elem = eval_node(I, ai->stmts[i]);
                    vec_ensure_cap(&init_val, init_val.v.vec.len + 1);
                    init_val.v.vec.data[init_val.v.vec.len++] = elem;
                }
                /* If declared as array, keep as vector for simplicity */
            } else {
                init_val = eval_node(I, n->children[0]);
                /* Auto type deduction */
                if (is_auto) {
                    n->val_type = init_val.type;
                }
            }
        } else {
            init_val = create_default_val(n->val_type);
        }

        OcppVar *v = scope_set(I, I->current_scope, n->name, init_val);
        v->is_const = n->is_const;
        if (n->is_reference) {
            /* Try to find the referenced variable's lvalue */
            if (n->n_children > 0 && n->children[0] && n->children[0]->type == NP_IDENT) {
                OcppVar *ref = scope_find(I->current_scope, n->children[0]->name);
                if (ref) {
                    v->is_reference = 1;
                    v->ref_target = &ref->val;
                }
            }
        }
        break;
    }

    case NP_STRUCT_DECL: {
        if (n->label[0] && strcmp(n->label, "enum") == 0) {
            /* Register enum values */
            for (int i = 0; i < n->n_stmts; i++) {
                if (n->stmts[i] && I->n_enum_vals < 256) {
                    strcpy(I->enum_vals[I->n_enum_vals].name, n->stmts[i]->name);
                    I->enum_vals[I->n_enum_vals].value = (long long)n->stmts[i]->num_val;
                    I->n_enum_vals++;
                    /* Also set as variable */
                    scope_set(I, I->current_scope, n->stmts[i]->name,
                             make_int((long long)n->stmts[i]->num_val));
                }
            }
        }
        break;
    }

    case NP_EXPR_STMT: {
        if (n->n_children > 0) eval_node(I, n->children[0]);
        break;
    }

    case NP_IF: {
        if (val_to_bool(eval_node(I, n->children[0]))) {
            exec_node(I, n->children[1]);
        } else if (n->n_children > 2) {
            exec_node(I, n->children[2]);
        }
        break;
    }

    case NP_WHILE: {
        while (!I->returning && !I->breaking && val_to_bool(eval_node(I, n->children[0]))) {
            exec_node(I, n->children[1]);
            I->continuing = 0;
        }
        I->breaking = 0;
        break;
    }

    case NP_DOWHILE: {
        do {
            exec_node(I, n->children[0]);
            I->continuing = 0;
            if (I->returning || I->breaking) break;
        } while (val_to_bool(eval_node(I, n->children[1])));
        I->breaking = 0;
        break;
    }

    case NP_FOR: {
        OcppScope *prev = I->current_scope;
        I->current_scope = scope_create(I->current_scope);

        if (n->children[0]) exec_node(I, n->children[0]);
        while (!I->returning && !I->breaking) {
            if (n->children[1]) {
                if (!val_to_bool(eval_node(I, n->children[1]))) break;
            }
            exec_node(I, n->children[3]);
            I->continuing = 0;
            if (n->children[2]) eval_node(I, n->children[2]);
        }
        I->breaking = 0;

        OcppScope *old = I->current_scope;
        I->current_scope = prev;
        scope_destroy(old);
        break;
    }

    case NP_RANGE_FOR: {
        OcppValue container = eval_node(I, n->children[0]);
        OcppScope *prev = I->current_scope;
        I->current_scope = scope_create(I->current_scope);

        if (container.type == CVAL_VECTOR) {
            for (int i = 0; i < container.v.vec.len && !I->returning && !I->breaking; i++) {
                scope_set(I, I->current_scope, n->name, container.v.vec.data[i]);
                exec_node(I, n->children[1]);
                I->continuing = 0;
            }
        } else if (container.type == CVAL_STRING) {
            const char *s = container.v.s ? container.v.s : "";
            for (int i = 0; s[i] && !I->returning && !I->breaking; i++) {
                scope_set(I, I->current_scope, n->name, make_char(s[i]));
                exec_node(I, n->children[1]);
                I->continuing = 0;
            }
        } else if (container.type == CVAL_MAP) {
            for (int i = 0; i < container.v.map.len && !I->returning && !I->breaking; i++) {
                OcppValue pair_val = make_pair(container.v.map.keys[i], container.v.map.vals[i]);
                scope_set(I, I->current_scope, n->name, pair_val);
                exec_node(I, n->children[1]);
                I->continuing = 0;
            }
        }
        I->breaking = 0;

        OcppScope *old = I->current_scope;
        I->current_scope = prev;
        scope_destroy(old);
        break;
    }

    case NP_SWITCH: {
        OcppValue sv = eval_node(I, n->children[0]);
        int matched = 0;
        for (int i = 0; i < n->n_stmts && !I->breaking; i++) {
            OcppNode *cs = n->stmts[i];
            if (cs->type == NP_CASE) {
                if (!matched) {
                    OcppValue cv = eval_node(I, cs->children[0]);
                    if (val_to_int(sv) == val_to_int(cv)) matched = 1;
                }
                if (matched) {
                    for (int j = 0; j < cs->n_stmts && !I->breaking; j++)
                        exec_node(I, cs->stmts[j]);
                }
            } else if (cs->type == NP_DEFAULT && !matched) {
                matched = 1;
                for (int j = 0; j < cs->n_stmts && !I->breaking; j++)
                    exec_node(I, cs->stmts[j]);
            }
        }
        I->breaking = 0;
        break;
    }

    case NP_RETURN: {
        I->return_val = (n->n_children > 0) ? eval_node(I, n->children[0]) : make_void();
        I->returning = 1;
        break;
    }

    case NP_BREAK: I->breaking = 1; break;
    case NP_CONTINUE: I->continuing = 1; break;

    case NP_TRY_CATCH: {
        if (I->catch_depth >= OCPP_MAX_STACK) ocpp_error(I, "Try nesting too deep");
        int caught = 0;
        if (setjmp(I->catch_jmp[I->catch_depth]) == 0) {
            I->catch_depth++;
            exec_node(I, n->children[0]); /* try block */
            I->catch_depth--;
        } else {
            I->catch_depth--;
            caught = 1;
        }

        if (caught && I->cur_exception.active) {
            I->cur_exception.active = 0;
            I->has_error = 0;
            I->error[0] = '\0';

            /* Find matching catch */
            int handled = 0;
            for (int i = 0; i < n->n_catches; i++) {
                OcppNode *cc = n->catch_clauses[i];
                if (strcmp(cc->name, "...") == 0) {
                    /* catch-all */
                    exec_node(I, cc->children[0]);
                    handled = 1;
                    break;
                }
                /* Check type match (simplified) */
                int type_match = 0;
                if (cc->class_name[0]) {
                    if (strcmp(cc->class_name, "int") == 0 && I->cur_exception.value.type == CVAL_INT)
                        type_match = 1;
                    else if ((strcmp(cc->class_name, "string") == 0 ||
                              strcmp(cc->class_name, "exception") == 0 ||
                              strcmp(cc->class_name, "runtime_error") == 0) &&
                             I->cur_exception.value.type == CVAL_STRING)
                        type_match = 1;
                    else if (strcmp(cc->class_name, I->cur_exception.type_name) == 0)
                        type_match = 1;
                }
                if (type_match) {
                    OcppScope *prev = I->current_scope;
                    I->current_scope = scope_create(I->current_scope);
                    if (cc->name[0]) {
                        scope_set(I, I->current_scope, cc->name, I->cur_exception.value);
                    }
                    exec_node(I, cc->children[0]);
                    OcppScope *old = I->current_scope;
                    I->current_scope = prev;
                    scope_destroy(old);
                    handled = 1;
                    break;
                }
            }
            if (!handled) {
                /* Re-throw */
                I->cur_exception.active = 1;
                if (I->catch_depth > 0) {
                    longjmp(I->catch_jmp[I->catch_depth - 1], 1);
                }
                ocpp_error(I, "Unhandled exception of type '%s'", I->cur_exception.type_name);
            }
        }
        break;
    }

    case NP_LABEL: break; /* Labels are no-ops at runtime */

    case NP_GOTO: {
        /* Simplified goto: not fully supported in tree-walker */
        /* Could be implemented with longjmp but omitted for safety */
        break;
    }

    default:
        /* For expression-type nodes at statement level */
        eval_node(I, n);
        break;
    }
}

/* ══════════════════════════════════════════════
 *  Public API
 * ══════════════════════════════════════════════ */

OcppInterpreter *ocpp_create(void) {
    OcppInterpreter *I = (OcppInterpreter *)calloc(1, sizeof(OcppInterpreter));
    if (!I) return NULL;
    vmem_init(I);
    I->global_scope = scope_create(NULL);
    I->current_scope = I->global_scope;
    I->node_pool = NULL;
    I->node_pool_count = 0;
    I->node_pool_cap = 0;
    return I;
}

void ocpp_destroy(OcppInterpreter *interp) {
    if (!interp) return;
    /* Free node pool */
    for (int i = 0; i < interp->node_pool_count; i++) {
        OcppNode *n = interp->node_pool[i];
        if (n->stmts) free(n->stmts);
        free(n);
    }
    if (interp->node_pool) free(interp->node_pool);
    /* Free scopes */
    if (interp->global_scope) scope_destroy(interp->global_scope);
    /* Free vmem */
    if (interp->vmem) free(interp->vmem);
    free(interp);
}

int ocpp_execute(OcppInterpreter *interp, const char *source) {
    if (!interp || !source) return -1;

    interp->source = source;
    interp->has_error = 0;
    interp->error[0] = '\0';
    interp->tok_pos = 0;
    interp->returning = 0;
    interp->breaking = 0;
    interp->continuing = 0;
    interp->cur_exception.active = 0;
    interp->catch_depth = 0;
    interp->this_depth = 0;
    interp->current_class[0] = '\0';

    if (setjmp(interp->err_jmp) != 0) {
        return -1;
    }

    /* Tokenize */
    tokenize(interp, source);

    /* Parse */
    interp->tok_pos = 0;
    interp->ast = parse_program(interp);

    /* Execute */
    exec_node(interp, interp->ast);

    /* If there's a main() function, call it */
    for (int i = 0; i < interp->n_funcs; i++) {
        if (strcmp(interp->funcs[i].name, "main") == 0) {
            call_function(interp, "main", NULL, 0);
            break;
        }
    }

    return interp->has_error ? -1 : 0;
}

const char *ocpp_get_output(OcppInterpreter *interp) {
    return interp ? interp->output : "";
}

const char *ocpp_get_error(OcppInterpreter *interp) {
    return interp ? interp->error : "";
}

void ocpp_reset(OcppInterpreter *interp) {
    if (!interp) return;
    interp->output[0] = '\0';
    interp->out_len = 0;
    interp->error[0] = '\0';
    interp->has_error = 0;
}
