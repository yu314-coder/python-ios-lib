# C Interpreter

> **Type:** Tree-walking C89/C99/C23 interpreter | **Location:** `gcc/offlinai_cc.c`, `gcc/offlinai_cc.h` | **Size:** ~3,450 lines | **Tests:** 48/49 passing

A self-contained C interpreter with virtual memory, real pointer arithmetic, structs, unions, function pointers, goto, and function-like macros. Lexes, parses, and interprets C code at runtime. No JIT, no code generation, no external compiler needed. App Store safe.

Supports C89, C99, and select C23 features.

Edits `.c` / `.h` files in the shared Monaco-powered editor with C-mode syntax highlighting and auto-save — changes persist on every keystroke (~600 ms debounce) plus on run, tab switch, view disappear, and app backgrounding.

---

## Quick Start

```c
#include <stdio.h>
#include <math.h>

#define MAX(a,b) ((a)>(b)?(a):(b))

struct Point {
    double x;
    double y;
};

double distance(struct Point a, struct Point b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
}

int main() {
    // Structs + compound literals
    struct Point p1 = {3.0, 4.0};
    struct Point p2 = (struct Point){7.0, 1.0};
    printf("Distance: %.4f\n", distance(p1, p2));

    // Pointers
    int x = 42;
    int *p = &x;
    *p = 100;
    printf("x = %d (via pointer write)\n", x);

    // 2D arrays + matrix multiply
    int a[2][2] = {1,2,3,4};
    int b[2][2] = {5,6,7,8};
    int c[2][2] = {0,0,0,0};
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++)
            for (int k = 0; k < 2; k++)
                c[i][j] += a[i][k] * b[k][j];
    printf("Matrix: %d %d %d %d\n", c[0][0], c[0][1], c[1][0], c[1][1]);

    // Function pointers
    // (see examples below)

    // Static variables
    // (see examples below)

    printf("MAX(3,9) = %d\n", MAX(3, 9));
    return 0;
}
```

---

## Architecture

```
Source code
    │
    ▼
┌──────────┐     ┌──────────────┐     ┌───────────────┐
│  Lexer   │────▶│   Parser     │────▶│  Tree-walking  │
│ tokenize │     │  recursive   │     │   evaluator    │
│          │     │  descent     │     │  eval_node()   │
└──────────┘     └──────────────┘     │  exec_node()   │
                                      └───────┬───────┘
                                              │
                                     ┌────────▼────────┐
                                     │  Virtual Memory  │
                                     │  vmem[32768]     │
                                     │  (pointer backing)│
                                     └─────────────────┘
```

---

## Supported Data Types

| Type | Internal Representation | Notes |
|------|------------------------|-------|
| `int` | 64-bit `long long` | All integer types map here |
| `long` / `long long` | 64-bit `long long` | Same as int internally |
| `short` | 64-bit `long long` | Parsed, no size difference |
| `unsigned` | 64-bit `long long` | Parsed, treated as signed internally |
| `float` | 64-bit `double` | Same as double internally |
| `double` | 64-bit `double` | Native double precision |
| `char` | Single character | `'A'`, escape sequences (`\n`, `\t`, `\\`, `\'`) |
| `void` | Return type only | |
| `int[]` | Array of OccValue | Fixed-size, heap allocated |
| `int[][]` | Flat 2D array | Stride-based indexing |
| `struct` | Named field collection | Dot/arrow access, compound literals |
| `union` | Overlapping fields | All fields share one storage slot |
| `enum` | Integer constants | Auto-incrementing values |
| `int *` | Virtual memory pointer | Real address-of, dereference, arithmetic |
| `int (*)(int,int)` | Function pointer | Callbacks, higher-order functions |

## Pointer System (Virtual Memory)

The interpreter has a virtual memory system (`vmem[32768]` OccValue slots) that backs real pointer operations:

```c
// Address-of and dereference
int x = 42;
int *p = &x;
printf("%d\n", *p);    // 42

// Write through pointer
*p = 100;
printf("%d\n", x);     // 100 (x is updated!)

// Pointer arithmetic
int arr[5] = {10, 20, 30, 40, 50};
int *q = &arr[0];
printf("%d\n", *(q + 2));   // 30
printf("%d\n", *(q + 4));   // 50

// Pointers as output parameters
void swap(int *a, int *b) {
    int t = *a; *a = *b; *b = t;
}
int a = 1, b = 2;
swap(&a, &b);   // a=2, b=1

// Pointer to array element
int *mid = &arr[2];
printf("%d\n", *mid);  // 30

// malloc / calloc / free
int *heap = malloc(10 * sizeof(int));
for (int i = 0; i < 10; i++) heap[i] = i * i;
printf("%d\n", heap[5]);  // 25
free(heap);
```

## Multi-Dimensional Arrays

```c
// 2D array declaration and access
int grid[3][3] = {1,0,0, 0,1,0, 0,0,1};
printf("%d %d %d\n", grid[0][0], grid[1][1], grid[2][2]);  // 1 1 1

// 2D array write
grid[1][2] = 99;

// Compound assignment on 2D elements
int c[2][2] = {0,0,0,0};
c[0][0] += 5;   // works correctly

// Matrix multiply
for (int i = 0; i < N; i++)
    for (int j = 0; j < N; j++)
        for (int k = 0; k < N; k++)
            result[i][j] += a[i][k] * b[k][j];  // compound assign on 2D
```

## Supported Operators (48)

### Arithmetic
`+`, `-`, `*`, `/`, `%`

### Comparison
`==`, `!=`, `<`, `>`, `<=`, `>=`

### Logical
`&&`, `||`, `!` (with short-circuit evaluation)

### Bitwise
`&`, `|`, `^`, `~`, `<<`, `>>`

### Assignment
`=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`

### Increment/Decrement
`++` (pre/post), `--` (pre/post)

### Other
`? :` (ternary, nestable), `sizeof()`, `(type)` (cast), `[]` (index, 1D and 2D), `.` (member), `->` (arrow), `,` (comma)

## Control Flow

| Statement | Supported | Notes |
|-----------|-----------|-------|
| `if / else if / else` | Yes | Full nesting |
| `for (init; cond; inc)` | Yes | Scoped variables, 1M iteration limit |
| `while (cond)` | Yes | 1M iteration limit |
| `do { } while (cond)` | Yes | 1M iteration limit |
| `switch / case / default` | Yes | Fall-through + break |
| `break` | Yes | Loops and switch |
| `continue` | Yes | Loops only |
| `return` | Yes | With or without value |
| `goto label` | Yes | Forward and backward jumps |
| `label:` | Yes | Named jump targets |

```c
// goto for error cleanup pattern
int main() {
    int *data = malloc(100);
    if (!data) goto error;
    // ... use data ...
    free(data);
    return 0;
error:
    printf("allocation failed\n");
    return 1;
}

// goto as loop
int i = 0;
top:
    if (i >= 5) goto done;
    printf("%d ", i);
    i++;
    goto top;
done:
    // prints: 0 1 2 3 4
```

## Functions

```c
// Basic function
int square(int x) { return x * x; }

// Recursive
long long factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

// Void function
void greet(char *name) {
    printf("Hello, %s!\n", name);
}

// Forward reference (call before definition)
int main() {
    printf("%d\n", helper(5));  // works
    return 0;
}
int helper(int x) { return x * 10; }

// Output parameters via pointers
void divmod(int a, int b, int *quotient, int *remainder) {
    *quotient = a / b;
    *remainder = a % b;
}
```

## Function Pointers

```c
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int mul(int a, int b) { return a * b; }

int main() {
    // Declare and assign
    int (*op)(int, int) = add;
    printf("%d\n", op(10, 3));  // 13

    // Switch at runtime
    op = sub;
    printf("%d\n", op(10, 3));  // 7

    // Pass as parameter
    int apply(int (*f)(int), int x) { return f(x); }
    int dbl(int x) { return x * 2; }
    printf("%d\n", apply(dbl, 21));  // 42
}
```

## Static Variables

```c
int counter() {
    static int n = 0;  // initialized once, persists across calls
    n++;
    return n;
}

int main() {
    for (int i = 0; i < 5; i++)
        printf("%d ", counter());
    // Output: 1 2 3 4 5
    return 0;
}
```

## Structs

```c
struct Point { int x; int y; };
struct Color { int r; int g; int b; };

// Initialization
struct Point p1 = {3, 4};
struct Point p2 = (struct Point){7, 8};  // compound literal

// Field access and assignment
p1.x = 10;
printf("%d %d\n", p1.x, p1.y);

// As function parameter
double distance(struct Point a, struct Point b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return sqrt(dx*dx + dy*dy);
}

// Dot product
struct Vec { double x; double y; };
double dot(struct Vec a, struct Vec b) {
    return a.x*b.x + a.y*b.y;
}
```

## Unions

```c
union Number {
    int i;
    double f;
};

union Number n;
n.i = 42;
printf("%d\n", n.i);    // 42
n.f = 3.14;
printf("%.2f\n", n.f);  // 3.14 (overwrites i)
```

## Enums

```c
enum Direction { NORTH, EAST, SOUTH, WEST };
// NORTH=0, EAST=1, SOUTH=2, WEST=3

enum Status { OK = 200, NOT_FOUND = 404, ERROR = 500 };

enum Color { RED, GREEN = 5, BLUE };
// RED=0, GREEN=5, BLUE=6
```

## Preprocessor Directives

| Directive | Supported | Notes |
|-----------|-----------|-------|
| `#include <...>` | Parsed | Recognized but no file loading |
| `#define NAME VALUE` | Yes | Simple macros with value substitution |
| `#define NAME` | Yes | Flag-only macros (evaluates to 1) |
| `#define F(x,y) expr` | Yes | Function-like macros with parameter substitution |
| `#undef NAME` | Yes | Remove a define |
| `#ifdef NAME` | Yes | Conditional compilation |
| `#ifndef NAME` | Yes | Conditional compilation |
| `#if EXPR` | Yes | Simple constant expressions |
| `#else` | Yes | Else branch |
| `#elif COND` | Yes | Else-if branch |
| `#endif` | Yes | End conditional |
| `#pragma` | Ignored | |

```c
// Object-like macros
#define PI 3.14159265
#define MAX_SIZE 100

// Function-like macros
#define SQUARE(x) ((x)*(x))
#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))
#define ABS(x) ((x)>=0?(x):-(x))

printf("%d\n", SQUARE(5));      // 25
printf("%d\n", SQUARE(3+1));    // 16 (correct with parens!)
printf("%d\n", MAX(10, 20));    // 20
printf("%d\n", MIN(10, 20));    // 10

// Conditional compilation
#define DEBUG
#ifdef DEBUG
    printf("debug mode\n");
#else
    printf("release mode\n");
#endif

#ifndef FEATURE_X
    printf("FEATURE_X not defined\n");
#endif

// Undefine
#define TEMP 42
#undef TEMP
// TEMP is now undefined
```

## String Handling

```c
// Mutable char arrays
char str[20] = "hello";
str[0] = 'H';
str[4] = '!';
printf("%s\n", str);  // Hell!

// String reversal via pointer
void reverse(char *s, int n) {
    for (int i = 0; i < n/2; i++) {
        char t = s[i];
        s[i] = s[n-1-i];
        s[n-1-i] = t;
    }
}
char s[10] = "abcde";
reverse(s, 5);
printf("%s\n", s);  // edcba

// sprintf to buffer
char buf[100];
sprintf(buf, "x=%d y=%.1f", 42, 3.14);
printf("%s\n", buf);  // x=42 y=3.1
```

## Built-in Functions (70+)

### I/O Functions

| Function | Notes |
|----------|-------|
| `printf(fmt, ...)` | Full format: `%d %i %u %f %e %g %x %X %o %s %c %p %%`, width/padding (`%5d`, `%-10s`, `%05d`, `%08x`), precision (`%.3f`) |
| `fprintf(file, fmt, ...)` | FILE* arg skipped, outputs normally |
| `sprintf(buf, fmt, ...)` | Writes to char array buffer (not stdout!) |
| `snprintf(buf, n, fmt, ...)` | Writes to buffer with size limit |
| `puts(str)` | Print string + newline |
| `putchar(c)` | Print single character |
| `scanf(fmt, ...)` | Returns 0 (no stdin on iOS) |
| `getchar()` | Returns -1 (EOF) |
| `fgets(buf, n, fp)` | Returns 0 (no stdin) |

### Math Functions (`<math.h>`)

| Function | Description |
|----------|-------------|
| `sin`, `cos`, `tan` | Trigonometric |
| `asin`, `acos`, `atan`, `atan2` | Inverse trig |
| `sinh`, `cosh`, `tanh` | Hyperbolic |
| `exp`, `log`, `log2`, `log10` | Exponential/logarithmic |
| `sqrt`, `cbrt` | Roots |
| `pow` | Power |
| `fabs`, `abs`, `labs` | Absolute value |
| `ceil`, `floor`, `round` | Rounding |
| `fmod`, `fmax`, `fmin` | Modulo, min/max |

**Constants:** `M_PI`, `M_E`, `INT_MAX`, `INT_MIN`, `LLONG_MAX`, `DBL_MAX`, `RAND_MAX`, `CLOCKS_PER_SEC`, `NULL`, `TRUE`, `FALSE`, `EOF`

### String Functions (`<string.h>`)

| Function | Description |
|----------|-------------|
| `strlen(s)` | String length |
| `strcmp(a, b)` / `strncmp(a, b, n)` | String comparison |
| `strcpy(dst, src)` / `strncpy(dst, src, n)` | Copy string |
| `strcat(a, b)` / `strncat(a, b, n)` | Concatenate |
| `strstr(haystack, needle)` | Find substring |
| `strchr(s, c)` / `strrchr(s, c)` | Find character |
| `strdup(s)` | Duplicate string |
| `strtok(s, delim)` | Tokenize (first token) |
| `strspn(s, accept)` / `strcspn(s, reject)` | Span functions |
| `memcmp(a, b, n)` | Memory comparison |
| `memmove(dst, src, n)` | Memory move |

### Character Functions (`<ctype.h>`)

`isdigit`, `isalpha`, `isalnum`, `isupper`, `islower`, `isspace`, `ispunct`, `isxdigit`, `isprint`, `toupper`, `tolower`

### Conversion Functions

`atoi`, `atof`, `strtol` (any base), `strtod`, `strtof`, `itoa`

### Memory Functions

| Function | Description |
|----------|-------------|
| `malloc(size)` | Allocate from vmem (returns real pointer) |
| `calloc(n, size)` | Allocate zeroed memory |
| `realloc(ptr, size)` | Resize allocation |
| `free(ptr)` | Free memory (no-op in arena model) |

### Utility Functions

`time(NULL)`, `clock()`, `rand()`, `srand(seed)`, `exit(code)`, `assert(condition)`, `qsort(arr, n, size, cmp)` (with function pointer comparator)

## Printf Formatting

```c
printf("%d", 42);            // 42
printf("%05d", 42);          // 00042
printf("%-10d", 42);         // 42        (left-aligned)
printf("%10d", 42);          //         42 (right-aligned)
printf("%.3f", 3.14159);     // 3.142
printf("%e", 12345.6);       // 1.234560e+04
printf("%x %X", 255, 255);   // ff FF
printf("%o", 255);            // 377
printf("%lld", 123456789012LL); // 123456789012
printf("%-10s", "hi");       // hi         (left-aligned string)
printf("100%%");              // 100%
```

---

## Limits

| Limit | Value |
|-------|-------|
| Max variables per scope | 512 |
| Max functions | 128 |
| Max output buffer | 64 KB |
| Max string length | 4,096 chars |
| Max array elements | 10,000 |
| Max tokens | 32,768 |
| Max loop iterations | 1,000,000 |
| Max struct/union types | 64 |
| Max struct fields | 32 |
| Max `#define` macros | 256 |
| Max function-like macros | 64 |
| Max enum values | 256 |
| Max heap blocks | 256 |
| Virtual memory slots | 32,768 |
| Max static variables | 256 |

---

## Tested Algorithms

All verified working:

- **Sorting:** Bubble sort, Selection sort, qsort with comparator
- **Searching:** Binary search, Linear search
- **Math:** GCD (Euclid), Fast exponentiation, Sieve of Eratosthenes, Factorial, Fibonacci
- **Data structures:** Linked list (via arrays), Stack, Matrix operations (2x2 multiply)
- **Strings:** Reverse, sprintf formatting, Tokenization
- **Recursion:** Tower of Hanoi, Factorial, Fibonacci, Tree traversal patterns
- **Pointers:** Swap via pointers, Output parameters, Array traversal via pointer arithmetic

---

## C23 Features

The interpreter supports the following C23 additions:

| Feature | Syntax | Description |
|---------|--------|-------------|
| `_Static_assert` | `_Static_assert(expr, "msg");` | Compile-time assertion. Evaluates expression at parse time; emits error with message if false. Also available as `static_assert` (no underscore) |
| `_Generic` | `_Generic(expr, int: "int", double: "dbl", default: "other")` | Type-generic selection expression. Evaluates to the matching association based on the controlling expression's type |
| `typeof` | `typeof(expr) x = expr;` | Declare variable with same type as expression. Works with `int`, `double`, `char`, `struct`, pointer types |
| `auto` type inference | `auto x = 42;` | Automatic type deduction from initializer (C23-style, not C89 storage class). Deduces `int`, `double`, `char`, or pointer types |
| `constexpr` | `constexpr int N = 100;` | Compile-time constant. Evaluates initializer at parse time. Can be used in array sizes and `#if` expressions |
| Binary literals | `int b = 0b10110;` | Binary integer literals with `0b` or `0B` prefix |
| Digit separators | `int x = 1'000'000;` | Single-quote digit separators for readability in integer and floating-point literals |
| `[[attributes]]` | `[[nodiscard]] int f();` | C23-style attributes. Recognized: `[[nodiscard]]`, `[[maybe_unused]]`, `[[deprecated]]`, `[[fallthrough]]`, `[[noreturn]]`. Parsed and stored; `[[nodiscard]]` warns if return value discarded |
| `#warning` | `#warning "message"` | Preprocessor warning directive. Emits a warning message during preprocessing (does not halt execution) |
| `bool` / `true` / `false` | `bool flag = true;` | Boolean type as a keyword (not requiring `<stdbool.h>`) |
| `nullptr` | `int *p = nullptr;` | Null pointer constant (C23-style) |

```c
// C23 features in action
#include <stdio.h>

constexpr int SIZE = 10;
int arr[SIZE];

int main() {
    // Binary literals with digit separators
    int mask = 0b1111'0000;
    int million = 1'000'000;
    printf("mask = %d, million = %d\n", mask, million);

    // auto type inference
    auto x = 3.14;    // deduced as double
    auto n = 42;       // deduced as int

    // typeof
    typeof(x) y = 2.71;  // y is double
    printf("x=%.2f y=%.2f\n", x, y);

    // _Generic
    const char *type_name = _Generic(x,
        int: "integer",
        double: "double",
        default: "other"
    );
    printf("x is: %s\n", type_name);  // "double"

    // _Static_assert
    _Static_assert(SIZE > 0, "SIZE must be positive");

    // [[attributes]]
    [[maybe_unused]] int unused_var = 0;

    // bool as keyword
    bool ready = true;
    printf("ready = %d\n", ready);

    return 0;
}
```

---

## Not Supported

| Feature | Notes |
|---------|-------|
| 3D+ arrays | Only 1D and 2D supported |
| Real multi-file linking | Single-source only |
| `volatile`, `restrict`, `inline` | Parsed but ignored |
| Bit-field structs | Not implemented |
| Union in struct / struct in union | Basic nesting only |
| File I/O (`fopen`, `fread`) | No filesystem access from interpreter |
| Threads (`pthread`) | Not applicable on iOS |
| Pointer-to-pointer (`int **pp`) | Limited |
| Variable-length arrays (VLAs) | Not supported |
| `setjmp`/`longjmp` (user-level) | Used internally for error handling only |
| Variadic user functions (`...`) | Only built-in printf family |
| C23 `_BitInt` | Extended integer types not supported |
| C23 `#embed` | Binary embedding not supported |
| C23 `typeof_unqual` | Only `typeof` is supported |
