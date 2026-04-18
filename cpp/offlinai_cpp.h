/*
 * OfflinAi C++ Interpreter — a lightweight C++ interpreter for iOS.
 * No JIT, no code generation, pure interpretation.
 * Supports: classes, single inheritance, virtual dispatch, templates,
 *           lambdas, references, namespaces, try/catch/throw,
 *           new/delete, operator overloading, range-for,
 *           std::string, std::vector, std::map, std::pair,
 *           cout/cin, auto, and most C features.
 */

#ifndef OFFLINAI_CPP_H
#define OFFLINAI_CPP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum limits */
#define OCPP_MAX_VARS      512
#define OCPP_MAX_FUNCS     128
#define OCPP_MAX_CLASSES   64
#define OCPP_MAX_METHODS   32
#define OCPP_MAX_FIELDS    32
#define OCPP_MAX_STACK     64
#define OCPP_MAX_OUTPUT    65536
#define OCPP_MAX_STRLEN    4096
#define OCPP_MAX_ARRAY     10000
#define OCPP_MAX_TOKENS    32768
#define OCPP_VMEM_SIZE     32768
#define OCPP_MAX_TEMPLATES 32
#define OCPP_MAX_NS        16
#define OCPP_MAX_CATCH     8

/* ── Token types ────────────────────────────── */
typedef enum {
    CTOK_EOF = 0,
    /* literals */
    CTOK_INT_LIT, CTOK_FLOAT_LIT, CTOK_STRING_LIT, CTOK_CHAR_LIT,
    CTOK_BOOL_LIT,
    /* identifier */
    CTOK_IDENT,
    /* C type keywords */
    CTOK_INT, CTOK_FLOAT, CTOK_DOUBLE, CTOK_CHAR, CTOK_VOID,
    CTOK_LONG, CTOK_SHORT, CTOK_UNSIGNED, CTOK_SIGNED, CTOK_CONST,
    /* C control keywords */
    CTOK_IF, CTOK_ELSE, CTOK_FOR, CTOK_WHILE, CTOK_DO,
    CTOK_RETURN, CTOK_BREAK, CTOK_CONTINUE,
    CTOK_SWITCH, CTOK_CASE, CTOK_DEFAULT,
    /* C misc keywords */
    CTOK_STRUCT, CTOK_TYPEDEF, CTOK_SIZEOF, CTOK_ENUM,
    CTOK_INCLUDE, CTOK_DEFINE,
    CTOK_STATIC, CTOK_UNION, CTOK_GOTO,
    /* C++ keywords */
    CTOK_CLASS, CTOK_PUBLIC, CTOK_PRIVATE, CTOK_PROTECTED,
    CTOK_NEW, CTOK_DELETE,
    CTOK_THIS,
    CTOK_VIRTUAL, CTOK_OVERRIDE,
    CTOK_NAMESPACE, CTOK_USING,
    CTOK_TEMPLATE, CTOK_TYPENAME,
    CTOK_AUTO,
    CTOK_TRY, CTOK_CATCH, CTOK_THROW,
    CTOK_NULLPTR,
    CTOK_BOOL,
    CTOK_OPERATOR,
    /* C++ STL tokens */
    CTOK_STRING_TYPE,  /* std::string or string */
    CTOK_ENDL,         /* std::endl or endl */
    CTOK_COUT,         /* std::cout or cout */
    CTOK_CIN,          /* std::cin or cin */
    /* operators */
    CTOK_PLUS, CTOK_MINUS, CTOK_STAR, CTOK_SLASH, CTOK_PERCENT,
    CTOK_AMP, CTOK_PIPE, CTOK_CARET, CTOK_TILDE, CTOK_BANG,
    CTOK_AND, CTOK_OR,
    CTOK_EQ, CTOK_NEQ, CTOK_LT, CTOK_GT, CTOK_LE, CTOK_GE,
    CTOK_LSHIFT, CTOK_RSHIFT,
    CTOK_ASSIGN, CTOK_PLUS_ASSIGN, CTOK_MINUS_ASSIGN,
    CTOK_STAR_ASSIGN, CTOK_SLASH_ASSIGN, CTOK_PERCENT_ASSIGN,
    CTOK_AMP_ASSIGN, CTOK_PIPE_ASSIGN, CTOK_CARET_ASSIGN,
    CTOK_LSHIFT_ASSIGN, CTOK_RSHIFT_ASSIGN,
    CTOK_INC, CTOK_DEC,
    /* punctuation */
    CTOK_LPAREN, CTOK_RPAREN, CTOK_LBRACE, CTOK_RBRACE,
    CTOK_LBRACKET, CTOK_RBRACKET,
    CTOK_SEMICOLON, CTOK_COMMA, CTOK_DOT, CTOK_ARROW,
    CTOK_COLON, CTOK_QUESTION,
    CTOK_HASH,
    /* C++ specific punctuation */
    CTOK_SCOPE,        /* :: */
    CTOK_ELLIPSIS,     /* ... for catch(...) */
} OcppTokenType;

typedef struct {
    OcppTokenType type;
    const char *start;
    int length;
    int line;
    double num_val;       /* for numeric literals */
    int bool_val;         /* for bool literals */
} OcppToken;

/* ── Value types ─────────────────────────────── */
typedef enum {
    CVAL_INT = 0,
    CVAL_FLOAT,
    CVAL_DOUBLE,
    CVAL_CHAR,
    CVAL_BOOL,
    CVAL_STRING,
    CVAL_VOID,
    CVAL_PTR,
    CVAL_OBJECT,
    CVAL_VECTOR,
    CVAL_MAP,
    CVAL_PAIR,
    CVAL_LAMBDA,
    CVAL_NULLPTR,
} OcppValType;

/* Forward declarations for AST */
typedef struct OcppNode OcppNode;

typedef struct OcppValue {
    OcppValType type;
    union {
        long long   i;       /* CVAL_INT */
        double      f;       /* CVAL_FLOAT / CVAL_DOUBLE */
        char        c;       /* CVAL_CHAR */
        int         b;       /* CVAL_BOOL */
        char       *s;       /* CVAL_STRING (heap-allocated) */
        struct {             /* CVAL_PTR */
            int addr;
            OcppValType pointee_type;
            int stride;
        } ptr;
        struct {             /* CVAL_OBJECT */
            struct OcppValue *fields;
            char (*field_names)[64];
            int n_fields;
            char class_name[64];
            int vmem_addr;   /* for this pointer */
        } obj;
        struct {             /* CVAL_VECTOR */
            struct OcppValue *data;
            int len;
            int cap;
            OcppValType elem_type;
        } vec;
        struct {             /* CVAL_MAP */
            struct OcppValue *keys;
            struct OcppValue *vals;
            int len;
            int cap;
            OcppValType key_type;
            OcppValType val_type;
        } map;
        struct {             /* CVAL_PAIR */
            struct OcppValue *first;
            struct OcppValue *second;
        } pair;
        struct {             /* CVAL_LAMBDA */
            OcppNode *body;
            char (*param_names)[64];
            OcppValType *param_types;
            int n_params;
            struct OcppValue *captures;
            char (*capture_names)[64];
            int n_captures;
        } lambda;
    } v;
} OcppValue;

/* ── AST node types ──────────────────────────── */
typedef enum {
    /* program structure */
    NP_PROGRAM, NP_BLOCK, NP_VARDECL, NP_FUNCDECL,
    /* control flow */
    NP_IF, NP_WHILE, NP_DOWHILE, NP_FOR, NP_RETURN,
    NP_BREAK, NP_CONTINUE, NP_SWITCH, NP_CASE, NP_DEFAULT,
    NP_EXPR_STMT,
    /* expressions */
    NP_ASSIGN, NP_COMPOUND_ASSIGN,
    NP_TERNARY,
    NP_OR, NP_AND,
    NP_BIT_OR, NP_BIT_XOR, NP_BIT_AND,
    NP_EQ, NP_NEQ, NP_LT, NP_GT, NP_LE, NP_GE,
    NP_LSHIFT, NP_RSHIFT,
    NP_ADD, NP_SUB, NP_MUL, NP_DIV, NP_MOD,
    NP_NEG, NP_NOT, NP_BIT_NOT,
    NP_PRE_INC, NP_PRE_DEC, NP_POST_INC, NP_POST_DEC,
    NP_DEREF, NP_ADDR,
    NP_SIZEOF,
    NP_CAST,
    NP_CALL, NP_INDEX, NP_MEMBER, NP_ARROW,
    NP_INT_LIT, NP_FLOAT_LIT, NP_STRING_LIT, NP_CHAR_LIT,
    NP_BOOL_LIT, NP_NULLPTR_LIT,
    NP_IDENT,
    NP_ARRAY_INIT,
    NP_COMMA,
    NP_STRUCT_DECL,
    NP_STRUCT_INIT,
    NP_GOTO, NP_LABEL,
    /* C++ specific nodes */
    NP_CLASS_DECL,     /* class definition */
    NP_NEW_EXPR,       /* new ClassName(args) */
    NP_DELETE_EXPR,    /* delete ptr */
    NP_THIS_EXPR,      /* this */
    NP_SCOPE_EXPR,     /* :: access */
    NP_LAMBDA_EXPR,    /* [captures](params){ body } */
    NP_RANGE_FOR,      /* for (auto& x : container) */
    NP_TRY_CATCH,      /* try { } catch { } */
    NP_THROW_EXPR,     /* throw expr */
    NP_NAMESPACE_DECL, /* namespace Name { ... } */
    NP_USING_DECL,     /* using namespace std; */
    NP_TEMPLATE_DECL,  /* template<typename T> ... */
    NP_COUT_EXPR,      /* cout << ... */
    NP_CIN_EXPR,       /* cin >> ... */
    NP_OPERATOR_DECL,  /* operator overload */
} OcppNodeType;

struct OcppNode {
    OcppNodeType type;
    /* data depending on type */
    double num_val;
    char name[256];
    char str_val[OCPP_MAX_STRLEN];
    OcppValType val_type;       /* declared type */
    int is_array;
    int array_size;
    int op;                    /* for compound assign */
    int is_static;
    int is_virtual;
    int is_reference;          /* T& ref */
    int is_const;
    int access;                /* 0=public, 1=private, 2=protected */
    char label[64];
    char class_name[64];       /* for method context, new, etc. */
    char base_class[64];       /* for inheritance */
    char type_param[64];       /* template type parameter */
    /* children */
    struct OcppNode *children[8];
    int n_children;
    /* for blocks / arg lists */
    struct OcppNode **stmts;
    int n_stmts;
    /* for function declarations */
    char param_names[16][256];
    OcppValType param_types[16];
    int param_is_ref[16];
    int n_params;
    /* for catch clauses */
    struct OcppNode *catch_clauses[OCPP_MAX_CATCH];
    int n_catches;
    /* source location */
    int line;
};

/* ── Public API ──────────────────────────────── */

typedef struct OcppInterpreter OcppInterpreter;

/* Create/destroy */
OcppInterpreter *ocpp_create(void);
void ocpp_destroy(OcppInterpreter *interp);

/* Execute C++ source code. Returns 0 on success, -1 on error. */
int ocpp_execute(OcppInterpreter *interp, const char *source);

/* Get output (stdout from cout etc.) */
const char *ocpp_get_output(OcppInterpreter *interp);

/* Get error message (if ocpp_execute returned -1) */
const char *ocpp_get_error(OcppInterpreter *interp);

/* Reset for next execution (clears output/errors but keeps state) */
void ocpp_reset(OcppInterpreter *interp);

#ifdef __cplusplus
}
#endif

#endif /* OFFLINAI_CPP_H */
