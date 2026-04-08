# C Interpreter (offlinai_cc)

> **Type:** Tree-walking C89/C99 interpreter | **Location:** `gcc/offlinai_cc.c`, `gcc/offlinai_cc.h` | **Size:** ~2200 lines

A self-contained C interpreter that lexes, parses, and interprets C code at runtime. No JIT, no code generation, no external compiler needed. App Store safe.

---

## Quick Start

```c
#include <stdio.h>
#include <math.h>

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
    struct Point p1 = {3.0, 4.0};
    struct Point p2 = {7.0, 1.0};
    printf("Distance: %.4f\n", distance(p1, p2));

    // Bitwise flags
    int flags = 0;
    flags |= (1 << 0) | (1 << 3);
    printf("Flags: 0x%x\n", flags);
    return 0;
}
```

---

## Supported Data Types

| Type | Internal Representation | Notes |
|------|------------------------|-------|
| `int` | 64-bit `long long` | All integer types map here |
| `long` / `long long` | 64-bit `long long` | Same as int internally |
| `short` | 64-bit `long long` | Parsed but no size difference |
| `unsigned` | 64-bit `long long` | Parsed, treated as signed |
| `float` | 64-bit `double` | Same as double internally |
| `double` | 64-bit `double` | Native double precision |
| `char` | Single character | `'A'`, escape sequences |
| `void` | Return type only | |
| `int[]` / `char[]` | Array of OccValue | Fixed-size, heap allocated |
| `struct` | Named field collection | Dot and arrow access |
| `enum` | Integer constants | Auto-incrementing values |
| `*` (pointer) | Simplified pointer | Address-of and dereference |

## Supported Operators (48)

### Arithmetic
`+`, `-`, `*`, `/`, `%`

### Comparison
`==`, `!=`, `<`, `>`, `<=`, `>=`

### Logical
`&&`, `||`, `!`

### Bitwise
`&`, `|`, `^`, `~`, `<<`, `>>`

### Assignment
`=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`

### Increment/Decrement
`++` (pre/post), `--` (pre/post)

### Other
`? :` (ternary), `sizeof()`, `(type)` (cast), `[]` (index), `.` (member), `->` (arrow), `,` (comma)

## Control Flow

| Statement | Supported | Notes |
|-----------|-----------|-------|
| `if / else if / else` | Yes | Full nesting |
| `for (init; cond; inc)` | Yes | Scoped variables, 1M iteration limit |
| `while (cond)` | Yes | 1M iteration limit |
| `do { } while (cond)` | Yes | 1M iteration limit |
| `switch / case / default` | Yes | Fall-through, break |
| `break` | Yes | Loops and switch |
| `continue` | Yes | Loops only |
| `return` | Yes | With or without value |
| `goto` | No | Not implemented |

## Preprocessor Directives

| Directive | Supported | Notes |
|-----------|-----------|-------|
| `#include <...>` | Parsed | Recognized but no file loading |
| `#define NAME VALUE` | Yes | Simple macros with value substitution |
| `#define FLAG` | Yes | Flag-only macros (evaluates to 1) |
| `#undef NAME` | Yes | Remove a define |
| `#ifdef NAME` | Yes | Conditional compilation |
| `#ifndef NAME` | Yes | Conditional compilation |
| `#if EXPR` | Yes | Simple constant expressions |
| `#else` | Yes | Else branch |
| `#elif COND` | Yes | Else-if branch |
| `#endif` | Yes | End conditional |
| `#define FOO(x)` | No | Function-like macros not supported |
| `#pragma` | Ignored | |

```c
#define DEBUG
#define MAX_SIZE 100

#ifdef DEBUG
    printf("Debug mode: MAX_SIZE = %d\n", MAX_SIZE);
#else
    printf("Release mode\n");
#endif

#ifndef FEATURE_X
    printf("FEATURE_X not defined\n");
#endif
```

## Built-in Functions (60+)

### I/O Functions

| Function | Signature | Notes |
|----------|-----------|-------|
| `printf` | `printf(fmt, ...)` | Full format: `%d %i %u %f %e %g %x %X %o %s %c %p %%`, width/padding (`%5d`, `%-10s`, `%08x`) |
| `fprintf` | `fprintf(file, fmt, ...)` | FILE* arg skipped, outputs normally |
| `sprintf` | `sprintf(buf, fmt, ...)` | Outputs to stdout (simplified) |
| `snprintf` | `snprintf(buf, n, fmt, ...)` | Outputs to stdout (simplified) |
| `puts` | `puts(str)` | Print string + newline |
| `putchar` | `putchar(c)` | Print single character |
| `scanf` | `scanf(fmt, ...)` | Returns 0 (no stdin on iOS) |

### Math Functions (`<math.h>`)

| Function | Description |
|----------|-------------|
| `sin`, `cos`, `tan` | Trigonometric |
| `asin`, `acos`, `atan`, `atan2` | Inverse trig |
| `sinh`, `cosh`, `tanh` | Hyperbolic |
| `exp`, `log`, `log2`, `log10` | Exponential/logarithmic |
| `sqrt`, `cbrt` | Roots |
| `pow` | Power |
| `fabs`, `abs` | Absolute value |
| `ceil`, `floor`, `round` | Rounding |
| `fmod`, `fmax`, `fmin` | Modulo, min/max |

**Constants:** `M_PI`, `M_E`, `INT_MAX`, `INT_MIN`, `LLONG_MAX`, `DBL_MAX`, `RAND_MAX`, `CLOCKS_PER_SEC`, `NULL`, `TRUE`, `FALSE`

### String Functions (`<string.h>`)

| Function | Description |
|----------|-------------|
| `strlen(s)` | String length |
| `strcmp(a, b)` | String comparison |
| `strncmp(a, b, n)` | Compare first n chars |
| `strcpy(dst, src)` | Copy string |
| `strncpy(dst, src, n)` | Copy n chars |
| `strcat(a, b)` | Concatenate |
| `strncat(a, b, n)` | Concatenate n chars |
| `strstr(haystack, needle)` | Find substring |
| `strchr(s, c)` | Find character |
| `strrchr(s, c)` | Find last occurrence |
| `strdup(s)` | Duplicate string |
| `strtok(s, delim)` | Tokenize (first token only) |

### Character Functions (`<ctype.h>`)

| Function | Description |
|----------|-------------|
| `isdigit(c)` | Is digit 0-9 |
| `isalpha(c)` | Is letter a-z/A-Z |
| `isalnum(c)` | Is alphanumeric |
| `isupper(c)` / `islower(c)` | Case check |
| `isspace(c)` | Is whitespace |
| `ispunct(c)` | Is punctuation |
| `isxdigit(c)` | Is hex digit |
| `isprint(c)` | Is printable |
| `toupper(c)` / `tolower(c)` | Case conversion |

### Conversion Functions

| Function | Description |
|----------|-------------|
| `atoi(s)` | String to int |
| `atof(s)` | String to double |
| `strtol(s, NULL, base)` | String to long (any base) |
| `strtod(s, NULL)` | String to double |
| `strtof(s, NULL)` | String to float |
| `itoa(n)` | Int to string |

### Memory Functions

| Function | Description |
|----------|-------------|
| `malloc(size)` | Allocate heap memory (returns ID) |
| `calloc(n, size)` | Allocate zeroed memory |
| `free(ptr)` | Free heap memory |
| `memset(ptr, val, n)` | Set memory (stub) |
| `memcpy(dst, src, n)` | Copy memory (stub) |

### Utility Functions

| Function | Description |
|----------|-------------|
| `time(NULL)` | Current Unix timestamp |
| `clock()` | CPU clock ticks |
| `rand()` | Random integer |
| `srand(seed)` | Seed random |
| `exit(code)` | Exit program |
| `assert(condition)` | Assert (errors on false) |

## Structs

```c
struct Circle {
    double cx;
    double cy;
    double radius;
};

struct Circle c = {0.0, 0.0, 5.0};
printf("Radius: %.1f\n", c.radius);
c.radius = 10.0;
```

**Supported:** Field access (`.`), arrow access (`->`), initializer lists (`{1, 2, 3}`), nested struct types, typedef aliases.

## Enums

```c
enum Color { RED, GREEN = 5, BLUE };
// RED = 0, GREEN = 5, BLUE = 6
printf("BLUE = %d\n", BLUE);
```

---

## Limits

| Limit | Value |
|-------|-------|
| Max variables per scope | 512 |
| Max functions | 128 |
| Max output buffer | 64 KB |
| Max string length | 4096 chars |
| Max array elements | 10,000 |
| Max tokens | 32,768 |
| Max loop iterations | 1,000,000 |
| Max struct types | 64 |
| Max struct fields | 32 |
| Max #defines | 256 |
| Max enum values | 256 |
| Max heap blocks | 256 |

---

## Not Supported

| Feature | Notes |
|---------|-------|
| Multi-dimensional arrays | Single dimension only |
| Function pointers | Not implemented |
| Variadic user functions | Only built-in printf family |
| `goto` / labels | Not implemented |
| `static` variables | Not implemented |
| `extern` declarations | Not implemented |
| Inline assembly | Not applicable |
| File I/O (`fopen`, `fread`) | No filesystem access |
| Threads (`pthread`) | Not applicable |
| C11/C23 features | C89/C99 subset only |
| Pointer arithmetic (`ptr + i`) | Limited |
| Union types | Not implemented |
| Bit-field structs | Not implemented |
| Function-like macros (`#define F(x)`) | Not implemented |
| `volatile`, `restrict` | Parsed but ignored |
