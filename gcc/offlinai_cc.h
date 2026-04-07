/*
 * OfflinAi C Interpreter — a lightweight C89 interpreter for iOS.
 * No JIT, no code generation, pure interpretation.
 * Supports: int, float, double, char, arrays, pointers, structs,
 *           if/else, for, while, do-while, switch, functions, printf, math.
 */

#ifndef OFFLINAI_CC_H
#define OFFLINAI_CC_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum limits */
#define OCC_MAX_VARS      512
#define OCC_MAX_FUNCS     128
#define OCC_MAX_STACK     64
#define OCC_MAX_OUTPUT    65536
#define OCC_MAX_STRLEN    4096
#define OCC_MAX_ARRAY     10000
#define OCC_MAX_TOKENS    32768

/* ── Token types ────────────────────────────── */
typedef enum {
    TOK_EOF = 0,
    /* literals */
    TOK_INT_LIT, TOK_FLOAT_LIT, TOK_STRING_LIT, TOK_CHAR_LIT,
    /* identifier */
    TOK_IDENT,
    /* keywords */
    TOK_INT, TOK_FLOAT, TOK_DOUBLE, TOK_CHAR, TOK_VOID,
    TOK_LONG, TOK_SHORT, TOK_UNSIGNED, TOK_SIGNED, TOK_CONST,
    TOK_IF, TOK_ELSE, TOK_FOR, TOK_WHILE, TOK_DO,
    TOK_RETURN, TOK_BREAK, TOK_CONTINUE,
    TOK_SWITCH, TOK_CASE, TOK_DEFAULT,
    TOK_STRUCT, TOK_TYPEDEF, TOK_SIZEOF,
    TOK_INCLUDE, TOK_DEFINE,
    /* operators */
    TOK_PLUS, TOK_MINUS, TOK_STAR, TOK_SLASH, TOK_PERCENT,
    TOK_AMP, TOK_PIPE, TOK_CARET, TOK_TILDE, TOK_BANG,
    TOK_AND, TOK_OR,
    TOK_EQ, TOK_NEQ, TOK_LT, TOK_GT, TOK_LE, TOK_GE,
    TOK_LSHIFT, TOK_RSHIFT,
    TOK_ASSIGN, TOK_PLUS_ASSIGN, TOK_MINUS_ASSIGN,
    TOK_STAR_ASSIGN, TOK_SLASH_ASSIGN, TOK_PERCENT_ASSIGN,
    TOK_INC, TOK_DEC,
    /* punctuation */
    TOK_LPAREN, TOK_RPAREN, TOK_LBRACE, TOK_RBRACE,
    TOK_LBRACKET, TOK_RBRACKET,
    TOK_SEMICOLON, TOK_COMMA, TOK_DOT, TOK_ARROW,
    TOK_COLON, TOK_QUESTION,
    TOK_HASH,
} OccTokenType;

typedef struct {
    OccTokenType type;
    const char *start;
    int length;
    int line;
    double num_val;       /* for numeric literals */
} OccToken;

/* ── Value types ─────────────────────────────── */
typedef enum {
    VAL_INT = 0,
    VAL_FLOAT,
    VAL_DOUBLE,
    VAL_CHAR,
    VAL_STRING,
    VAL_ARRAY,
    VAL_VOID,
    VAL_PTR,
} OccValType;

typedef struct OccValue {
    OccValType type;
    union {
        long long   i;
        double      f;
        char        c;
        char       *s;
        struct {
            struct OccValue *data;
            int len;
            int cap;
            OccValType elem_type;
        } arr;
        struct OccValue *ptr;  /* pointer to another value */
    } v;
} OccValue;

/* ── AST node types ──────────────────────────── */
typedef enum {
    ND_PROGRAM, ND_BLOCK, ND_VARDECL, ND_FUNCDECL,
    ND_IF, ND_WHILE, ND_DOWHILE, ND_FOR, ND_RETURN,
    ND_BREAK, ND_CONTINUE, ND_SWITCH, ND_CASE, ND_DEFAULT,
    ND_EXPR_STMT,
    /* expressions */
    ND_ASSIGN, ND_COMPOUND_ASSIGN,
    ND_TERNARY,
    ND_OR, ND_AND,
    ND_BIT_OR, ND_BIT_XOR, ND_BIT_AND,
    ND_EQ, ND_NEQ, ND_LT, ND_GT, ND_LE, ND_GE,
    ND_LSHIFT, ND_RSHIFT,
    ND_ADD, ND_SUB, ND_MUL, ND_DIV, ND_MOD,
    ND_NEG, ND_NOT, ND_BIT_NOT,
    ND_PRE_INC, ND_PRE_DEC, ND_POST_INC, ND_POST_DEC,
    ND_DEREF, ND_ADDR,
    ND_SIZEOF,
    ND_CAST,
    ND_CALL, ND_INDEX, ND_MEMBER, ND_ARROW,
    ND_INT_LIT, ND_FLOAT_LIT, ND_STRING_LIT, ND_CHAR_LIT,
    ND_IDENT,
    ND_ARRAY_INIT,
    ND_COMMA,
} OccNodeType;

typedef struct OccNode {
    OccNodeType type;
    /* data depending on type */
    double num_val;
    char name[256];
    char str_val[OCC_MAX_STRLEN];
    OccValType val_type;       /* declared type */
    int is_array;
    int array_size;
    int op;                    /* for compound assign */
    /* children */
    struct OccNode *children[8]; /* up to 8 children */
    int n_children;
    /* for blocks / arg lists */
    struct OccNode **stmts;
    int n_stmts;
    /* for function declarations */
    char param_names[16][256];
    OccValType param_types[16];
    int n_params;
    /* source location */
    int line;
} OccNode;

/* ── Public API ──────────────────────────────── */

typedef struct OccInterpreter OccInterpreter;

/* Create/destroy */
OccInterpreter *occ_create(void);
void occ_destroy(OccInterpreter *interp);

/* Execute C source code. Returns 0 on success, -1 on error. */
int occ_execute(OccInterpreter *interp, const char *source);

/* Get output (stdout from printf etc.) */
const char *occ_get_output(OccInterpreter *interp);

/* Get error message (if occ_execute returned -1) */
const char *occ_get_error(OccInterpreter *interp);

/* Reset for next execution (clears output/errors but keeps state) */
void occ_reset(OccInterpreter *interp);

#ifdef __cplusplus
}
#endif

#endif /* OFFLINAI_CC_H */
