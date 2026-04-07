/*
 * OfflinAi C Interpreter — single-file implementation.
 * Lexer → Parser → Tree-walking interpreter.
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
};

/* ── Forward declarations ────────────────────── */
static void occ_error(OccInterpreter *I, const char *fmt, ...);
static OccValue eval_node(OccInterpreter *I, OccNode *n);
static void exec_node(OccInterpreter *I, OccNode *n);
static void occ_printf(OccInterpreter *I, const char *fmt, OccValue *args, int nargs);

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

static double val_to_double(OccValue v) {
    switch (v.type) {
        case VAL_INT: return (double)v.v.i;
        case VAL_FLOAT: case VAL_DOUBLE: return v.v.f;
        case VAL_CHAR: return (double)v.v.c;
        default: return 0.0;
    }
}
static long long val_to_int(OccValue v) {
    switch (v.type) {
        case VAL_INT: return v.v.i;
        case VAL_FLOAT: case VAL_DOUBLE: return (long long)v.v.f;
        case VAL_CHAR: return (long long)v.v.c;
        default: return 0;
    }
}
static int val_to_bool(OccValue v) {
    switch (v.type) {
        case VAL_INT: return v.v.i != 0;
        case VAL_FLOAT: case VAL_DOUBLE: return v.v.f != 0.0;
        case VAL_CHAR: return v.v.c != 0;
        case VAL_STRING: return v.v.s && v.v.s[0];
        default: return 0;
    }
}
static int is_float_type(OccValue v) {
    return v.type == VAL_FLOAT || v.type == VAL_DOUBLE;
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
        if (s->vars[i].val.type == VAL_ARRAY && s->vars[i].val.v.arr.data)
            free(s->vars[i].val.v.arr.data);
    }
    free(s);
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
    {"struct", TOK_STRUCT}, {"typedef", TOK_TYPEDEF}, {"sizeof", TOK_SIZEOF},
    {"include", TOK_INCLUDE}, {"define", TOK_DEFINE},
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
        /* preprocessor: skip #include / #define lines */
        if (*p == '#') {
            p++;
            while (*p == ' ' || *p == '\t') p++;
            /* just skip the whole line */
            while (*p && *p != '\n') p++;
            continue;
        }
        /* string literal */
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
            int is_float = 0;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
                p += 2;
                while (isxdigit(*p)) p++;
                t->num_val = (double)strtoll(start, NULL, 16);
            } else {
                while (isdigit(*p)) p++;
                if (*p == '.') { is_float = 1; p++; while (isdigit(*p)) p++; }
                if (*p == 'e' || *p == 'E') {
                    is_float = 1; p++;
                    if (*p == '+' || *p == '-') p++;
                    while (isdigit(*p)) p++;
                }
                t->num_val = strtod(start, NULL);
            }
            /* skip suffixes like L, LL, f, U etc */
            while (*p == 'l' || *p == 'L' || *p == 'f' || *p == 'F' || *p == 'u' || *p == 'U') p++;
            t->length = (int)(p - start);
            t->type = is_float ? TOK_FLOAT_LIT : TOK_INT_LIT;
            I->n_tokens++;
            continue;
        }
        /* identifier / keyword */
        if (is_ident_start(*p)) {
            const char *start = p;
            while (is_ident_char(*p)) p++;
            t->length = (int)(p - start);
            t->type = TOK_IDENT;
            for (const Keyword *kw = keywords; kw->kw; kw++) {
                if ((int)strlen(kw->kw) == t->length && strncmp(start, kw->kw, t->length) == 0) {
                    t->type = kw->type;
                    break;
                }
            }
            I->n_tokens++;
            continue;
        }
        /* operators and punctuation */
        #define TOK2(c1,c2,tok) if(p[0]==c1&&p[1]==c2){t->type=tok;t->length=2;p+=2;I->n_tokens++;continue;}
        #define TOK1(c,tok) if(p[0]==c){t->type=tok;t->length=1;p++;I->n_tokens++;continue;}

        TOK2('+','+',TOK_INC) TOK2('-','-',TOK_DEC)
        TOK2('+','=',TOK_PLUS_ASSIGN) TOK2('-','=',TOK_MINUS_ASSIGN)
        TOK2('*','=',TOK_STAR_ASSIGN) TOK2('/','=',TOK_SLASH_ASSIGN)
        TOK2('%','=',TOK_PERCENT_ASSIGN)
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
static OccNode *parse_stmt(OccInterpreter *I);
static OccNode *parse_block(OccInterpreter *I);

static int is_type_token(OccTokenType t) {
    return t == TOK_INT || t == TOK_FLOAT || t == TOK_DOUBLE || t == TOK_CHAR
        || t == TOK_VOID || t == TOK_LONG || t == TOK_SHORT
        || t == TOK_UNSIGNED || t == TOK_SIGNED || t == TOK_CONST
        || t == TOK_STRUCT;
}

static OccValType parse_type(OccInterpreter *I) {
    OccValType vt = VAL_INT;
    /* skip const, unsigned, signed, etc */
    while (check(I, TOK_CONST) || check(I, TOK_UNSIGNED) || check(I, TOK_SIGNED)
           || check(I, TOK_LONG) || check(I, TOK_SHORT) || check(I, TOK_STRUCT)) {
        advance(I);
    }
    if (match(I, TOK_INT)) vt = VAL_INT;
    else if (match(I, TOK_FLOAT)) vt = VAL_FLOAT;
    else if (match(I, TOK_DOUBLE)) vt = VAL_DOUBLE;
    else if (match(I, TOK_CHAR)) vt = VAL_CHAR;
    else if (match(I, TOK_VOID)) vt = VAL_VOID;
    else if (check(I, TOK_IDENT)) { advance(I); vt = VAL_INT; } /* typedef'd type */
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
            OccValType vt = parse_type(I);
            while (match(I, TOK_STAR)) {}
            expect(I, TOK_RPAREN, ")");
            OccNode *n = new_node(ND_CAST, line);
            n->val_type = vt;
            add_child(n, parse_primary(I));  /* parse the casted expression */
            return n;
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
    OccTokenType compound[] = {TOK_PLUS_ASSIGN, TOK_MINUS_ASSIGN, TOK_STAR_ASSIGN, TOK_SLASH_ASSIGN, TOK_PERCENT_ASSIGN};
    OccNodeType ops[] = {ND_ADD, ND_SUB, ND_MUL, ND_DIV, ND_MOD};
    for (int i = 0; i < 5; i++) {
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

    /* array declaration: int x[10]; or int x[] = {1,2,3}; */
    if (match(I, TOK_LBRACKET)) {
        decl->is_array = 1;
        if (!check(I, TOK_RBRACKET)) {
            OccNode *sz = parse_expr(I);
            decl->array_size = (int)sz->num_val;
        }
        expect(I, TOK_RBRACKET, "]");
    }
    /* initializer */
    if (match(I, TOK_ASSIGN)) {
        if (match(I, TOK_LBRACE)) {
            /* array init: {1,2,3} */
            OccNode *init = new_node(ND_ARRAY_INIT, line);
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

    /* variable declaration */
    if (is_type_token(peek(I)->type)) {
        OccValType vt = parse_type(I);
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
                expect(I, TOK_LPAREN, "(");
                while (!check(I, TOK_RPAREN) && !check(I, TOK_EOF)) {
                    if (is_type_token(peek(I)->type)) {
                        OccValType pt = parse_type(I);
                        while (match(I, TOK_STAR)) {}
                        if (check(I, TOK_IDENT)) {
                            OccToken *pname = advance(I);
                            fn->param_types[fn->n_params] = pt;
                            strncpy(fn->param_names[fn->n_params], pname->start,
                                    pname->length < 255 ? pname->length : 255);
                            fn->param_names[fn->n_params][pname->length < 255 ? pname->length : 255] = '\0';
                            fn->n_params++;
                        }
                        /* skip array brackets in params */
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
        add_stmt(block, parse_vardecl(I, vt));
        while (match(I, TOK_COMMA))
            add_stmt(block, parse_vardecl(I, vt));
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
 *  Built-in functions
 * ══════════════════════════════════════════════ */

static void occ_printf(OccInterpreter *I, const char *fmt, OccValue *args, int nargs) {
    int ai = 0;
    for (const char *p = fmt; *p; p++) {
        if (*p == '%' && p[1]) {
            p++;
            /* flags */
            int width = 0, prec = -1, left = 0, zero = 0;
            char len_mod = 0;
            if (*p == '-') { left = 1; p++; }
            if (*p == '0') { zero = 1; p++; }
            while (isdigit(*p)) { width = width * 10 + (*p - '0'); p++; }
            if (*p == '.') { p++; prec = 0; while (isdigit(*p)) { prec = prec * 10 + (*p - '0'); p++; } }
            if (*p == 'l') { len_mod = 'l'; p++; if (*p == 'l') p++; }
            else if (*p == 'h') { p++; }

            char fmtbuf[64];
            (void)left; (void)zero; (void)len_mod;
            switch (*p) {
                case 'd': case 'i':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), "%lld", val_to_int(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case 'u':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), "%llu", (unsigned long long)val_to_int(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case 'f': case 'F':
                    if (ai < nargs) {
                        if (prec >= 0) snprintf(fmtbuf, sizeof(fmtbuf), "%.*f", prec, val_to_double(args[ai++]));
                        else snprintf(fmtbuf, sizeof(fmtbuf), "%f", val_to_double(args[ai++]));
                        out_append(I, fmtbuf);
                    }
                    break;
                case 'e': case 'E':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), "%e", val_to_double(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case 'g': case 'G':
                    if (ai < nargs) {
                        if (prec >= 0) snprintf(fmtbuf, sizeof(fmtbuf), "%.*g", prec, val_to_double(args[ai++]));
                        else snprintf(fmtbuf, sizeof(fmtbuf), "%g", val_to_double(args[ai++]));
                        out_append(I, fmtbuf);
                    }
                    break;
                case 'x': case 'X':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), *p == 'x' ? "%llx" : "%llX", val_to_int(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case 'o':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), "%llo", val_to_int(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case 'c':
                    if (ai < nargs) { char cc[2] = {(char)val_to_int(args[ai++]), 0}; out_append(I, cc); }
                    break;
                case 's':
                    if (ai < nargs && args[ai].type == VAL_STRING && args[ai].v.s) out_append(I, args[ai++].v.s);
                    else if (ai < nargs) { ai++; out_append(I, "(null)"); }
                    break;
                case 'p':
                    if (ai < nargs) { snprintf(fmtbuf, sizeof(fmtbuf), "0x%llx", val_to_int(args[ai++])); out_append(I, fmtbuf); }
                    break;
                case '%': out_append(I, "%"); break;
                default: { char tmp[3] = {'%', *p, 0}; out_append(I, tmp); } break;
            }
        } else {
            char tmp[2] = {*p, 0};
            out_append(I, tmp);
        }
    }
}

static OccValue call_builtin(OccInterpreter *I, const char *name, OccValue *args, int nargs) {
    /* printf family */
    if (strcmp(name, "printf") == 0 || strcmp(name, "fprintf") == 0) {
        int start = 0;
        if (strcmp(name, "fprintf") == 0) start = 1; /* skip FILE* arg */
        if (start < nargs && args[start].type == VAL_STRING)
            occ_printf(I, args[start].v.s, args + start + 1, nargs - start - 1);
        return make_int(0);
    }
    if (strcmp(name, "sprintf") == 0 || strcmp(name, "snprintf") == 0) {
        /* simplified: just format to output */
        int fmt_idx = (strcmp(name, "snprintf") == 0) ? 2 : 1;
        if (fmt_idx < nargs && args[fmt_idx].type == VAL_STRING)
            occ_printf(I, args[fmt_idx].v.s, args + fmt_idx + 1, nargs - fmt_idx - 1);
        return make_int(0);
    }
    if (strcmp(name, "puts") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) { out_append(I, args[0].v.s); out_append(I, "\n"); }
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

    /* string functions */
    if (strcmp(name, "strlen") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_int((long long)strlen(args[0].v.s));
        return make_int(0);
    }
    if (strcmp(name, "strcmp") == 0) {
        if (nargs >= 2 && args[0].type == VAL_STRING && args[1].type == VAL_STRING)
            return make_int(strcmp(args[0].v.s, args[1].v.s));
        return make_int(0);
    }
    if (strcmp(name, "atoi") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_int(atoi(args[0].v.s));
        return make_int(0);
    }
    if (strcmp(name, "atof") == 0) {
        if (nargs > 0 && args[0].type == VAL_STRING) return make_float(atof(args[0].v.s));
        return make_float(0);
    }

    /* time */
    if (strcmp(name, "time") == 0) return make_int((long long)time(NULL));
    if (strcmp(name, "clock") == 0) return make_int((long long)clock());

    /* rand */
    if (strcmp(name, "rand") == 0) return make_int(rand());
    if (strcmp(name, "srand") == 0) { srand((unsigned)val_to_int(args[0])); return make_void(); }

    /* malloc/free — simplified (just allocate array) */
    if (strcmp(name, "malloc") == 0 || strcmp(name, "calloc") == 0) {
        return make_int(0); /* return NULL-like */
    }
    if (strcmp(name, "free") == 0) return make_void();

    /* exit */
    if (strcmp(name, "exit") == 0) {
        I->returning = 1;
        I->return_val = make_int(val_to_int(args[0]));
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
            /* check if it's a defined constant */
            if (strcmp(n->name, "NULL") == 0) return make_int(0);
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
            occ_error(I, "Line %d: Undefined variable '%s'", n->line, n->name);
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

    /* arithmetic */
    case ND_ADD: case ND_SUB: case ND_MUL: case ND_DIV: case ND_MOD: {
        OccValue l = eval_node(I, n->children[0]);
        OccValue r = eval_node(I, n->children[1]);
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
            if (is_float_type(v->val)) v->val.v.f += (n->type == ND_PRE_INC ? 1.0 : -1.0);
            else v->val.v.i += (n->type == ND_PRE_INC ? 1 : -1);
            return v->val;
        }
        break;
    }
    case ND_POST_INC: case ND_POST_DEC: {
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (v) {
            OccValue old = v->val;
            if (is_float_type(v->val)) v->val.v.f += (n->type == ND_POST_INC ? 1.0 : -1.0);
            else v->val.v.i += (n->type == ND_POST_INC ? 1 : -1);
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
            v->val = rhs;
            return rhs;
        }
        if (n->children[0]->type == ND_INDEX) {
            OccVar *v = resolve_lvalue(I, n->children[0]->children[0]);
            if (v && v->val.type == VAL_ARRAY) {
                int idx = (int)val_to_int(eval_node(I, n->children[0]->children[1]));
                if (idx >= 0 && idx < v->val.v.arr.len)
                    v->val.v.arr.data[idx] = rhs;
                return rhs;
            }
        }
        return rhs;
    }
    case ND_COMPOUND_ASSIGN: {
        OccVar *v = resolve_lvalue(I, n->children[0]);
        if (!v) occ_error(I, "Line %d: Invalid assignment target", n->line);
        OccValue rhs = eval_node(I, n->children[1]);
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
                default: break;
            }
        }
        return v->val;
    }

    /* array index */
    case ND_INDEX: {
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

        /* check user-defined functions */
        for (int i = 0; i < I->n_funcs; i++) {
            if (strcmp(I->funcs[i].name, fname) == 0) {
                OccNode *fn = I->funcs[i].node;
                OccScope *fn_scope = scope_create(I->global_scope);
                /* bind params */
                for (int p = 0; p < fn->n_params && p < nargs; p++)
                    scope_set(I, fn_scope, fn->param_names[p], args[p]);
                /* execute body */
                OccScope *saved = I->current_scope;
                I->current_scope = fn_scope;
                I->returning = 0;
                if (fn->children[0]) exec_node(I, fn->children[0]);
                OccValue ret = I->return_val;
                I->returning = 0;
                I->current_scope = saved;
                scope_destroy(fn_scope);
                return ret;
            }
        }
        /* builtin */
        return call_builtin(I, fname, args, nargs);
    }

    case ND_COMMA:
        eval_node(I, n->children[0]);
        return eval_node(I, n->children[1]);

    case ND_ADDR: /* simplified — just return 0 */
        return make_int(0);
    case ND_DEREF:
        return eval_node(I, n->children[0]);

    default: break;
    }
    return make_int(0);
}

/* ── Statement execution ──────────────────────── */

static void exec_node(OccInterpreter *I, OccNode *n) {
    if (!n || I->returning || I->breaking || I->continuing) return;

    switch (n->type) {
    case ND_PROGRAM:
    case ND_BLOCK:
        for (int i = 0; i < n->n_stmts; i++) {
            exec_node(I, n->stmts[i]);
            if (I->returning || I->breaking || I->continuing) break;
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
        if (n->is_array) {
            int sz = n->array_size > 0 ? n->array_size : 16;
            if (n->children[0] && n->children[0]->type == ND_ARRAY_INIT)
                sz = n->children[0]->n_stmts > sz ? n->children[0]->n_stmts : sz;
            init.type = VAL_ARRAY;
            init.v.arr.len = sz;
            init.v.arr.cap = sz;
            init.v.arr.elem_type = n->val_type;
            init.v.arr.data = (OccValue *)calloc(sz, sizeof(OccValue));
            if (n->children[0] && n->children[0]->type == ND_ARRAY_INIT) {
                for (int i = 0; i < n->children[0]->n_stmts && i < sz; i++)
                    init.v.arr.data[i] = eval_node(I, n->children[0]->stmts[i]);
            }
        } else if (n->children[0]) {
            init = eval_node(I, n->children[0]);
        } else {
            switch (n->val_type) {
                case VAL_FLOAT: case VAL_DOUBLE: init = make_float(0); break;
                case VAL_CHAR: init = make_char(0); break;
                case VAL_STRING: init = make_string(""); break;
                default: init = make_int(0); break;
            }
        }
        scope_set(I, I->current_scope, n->name, init);
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
        if (n->children[0]) exec_node(I, n->children[0]); /* init */
        int limit = 1000000;
        while (--limit > 0) {
            if (n->children[1] && !val_to_bool(eval_node(I, n->children[1]))) break;
            exec_node(I, n->children[3]); /* body */
            if (I->breaking) { I->breaking = 0; break; }
            if (I->continuing) { I->continuing = 0; }
            if (I->returning) break;
            if (n->children[2]) eval_node(I, n->children[2]); /* increment */
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
    return I;
}

void occ_destroy(OccInterpreter *I) {
    if (!I) return;
    scope_destroy(I->global_scope);
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

    /* First pass: register functions */
    for (int i = 0; i < I->ast->n_stmts; i++) {
        if (I->ast->stmts[i]->type == ND_FUNCDECL) {
            exec_node(I, I->ast->stmts[i]);
        }
    }

    /* Check for main() */
    int has_main = 0;
    for (int i = 0; i < I->n_funcs; i++) {
        if (strcmp(I->funcs[i].name, "main") == 0) { has_main = 1; break; }
    }

    if (has_main) {
        /* Call main() */
        for (int i = 0; i < I->n_funcs; i++) {
            if (strcmp(I->funcs[i].name, "main") == 0) {
                OccNode *fn = I->funcs[i].node;
                OccScope *fn_scope = scope_create(I->global_scope);
                OccScope *saved = I->current_scope;
                I->current_scope = fn_scope;
                I->returning = 0;
                if (fn->children[0]) exec_node(I, fn->children[0]);
                I->current_scope = saved;
                scope_destroy(fn_scope);
                break;
            }
        }
    } else {
        /* Execute top-level statements (script mode) */
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
