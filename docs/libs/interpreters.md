# C / C++ / Fortran Interpreters

**Tree-walking interpreters** | ~11,800 lines total | Pure Swift

> Write and run C, C++, and Fortran code directly on iPad. No compilation step — code is parsed and interpreted in real-time.

### Editor integration

All three languages are editable in the same Monaco-powered code editor (WKWebView-hosted) used for Python. Features that carry over from the Python editing experience:

- Monaco syntax highlighting for `c`, `cpp`, `fortran` modes (auto-picked from the file extension — `.c` / `.cpp` / `.cxx` / `.h` / `.hpp` / `.f90` / `.f95` / `.for` etc.)
- Debounced auto-save (~600 ms after the last keystroke) so edits persist across app launches without a manual save step
- Synchronous flush on run, tab switch, view disappear, and app background — "Run" always saves first
- Tombstone-aware file browser: deleting a `.c` / `.cpp` / `.f90` that was auto-generated as a starter script keeps it deleted across relaunches

---

## C Interpreter

### Supported Features

| Category | Details |
|----------|---------|
| **Data Types** | `int`, `long`, `long long`, `short`, `unsigned`, `float`, `double`, `char`, `_Bool`, `void`, arrays (1D/2D), `struct`, `union`, `enum`, `typedef` |
| **Pointers** | `*p`, `&x`, pointer arithmetic, `malloc`/`calloc`/`realloc`/`free`, `NULL`, function pointers |
| **Operators** | 48 operators: arithmetic, comparison, logical, bitwise, assignment, compound assignment, ternary, sizeof, cast |
| **Control Flow** | `if`/`else if`/`else`, `for`, `while`, `do-while`, `switch`/`case`/`default`, `break`, `continue`, `return`, `goto` |
| **Functions** | Declaration, recursion, function pointers, callbacks, static variables, forward references |
| **Preprocessor** | `#define` (object + function macros), `#ifdef`/`#ifndef`/`#if`/`#elif`/`#else`/`#endif`, `#undef`, `#include` |
| **Standard Library** | `printf`, `scanf`, `strlen`, `strcmp`, `strcpy`, `strcat`, `sprintf`, `sscanf`, `atoi`, `atof`, `abs`, `rand`, `srand`, `time`, `clock`, `math.h` (sin, cos, sqrt, pow, etc.) |

### Safety

- Loop iteration limit: 1,000,000
- Virtual memory for pointers (no real memory access)
- Stack depth protection

---

## C++ Interpreter

### Additional Features (on top of C)

| Category | Details |
|----------|---------|
| **Classes** | `class`, `struct`, constructors, destructors, `this`, access specifiers (`public`/`private`/`protected`) |
| **Inheritance** | Single inheritance, virtual functions, `override`, polymorphism |
| **Templates** | Basic function and class templates |
| **STL** | `string`, `vector`, `map`, `set`, `pair`, `tuple`, `stack`, `queue`, `deque`, `priority_queue`, `unordered_map`, `unordered_set` |
| **I/O** | `cout`, `cin`, `endl`, `cerr`, stream operators `<<` / `>>` |
| **Modern C++** | `auto`, `nullptr`, `bool`/`true`/`false`, range-based for, `constexpr`, `static_cast` |
| **Algorithms** | `sort`, `find`, `count`, `reverse`, `min_element`, `max_element`, `accumulate`, `transform` |
| **Operators** | Operator overloading, `new`/`delete` |

---

## Fortran Interpreter

### Supported Features

| Category | Details |
|----------|---------|
| **Data Types** | `integer`, `real`, `double precision`, `complex`, `character`, `logical` |
| **Control** | `if`/`then`/`else`/`endif`, `do`/`enddo`, `do while`, `select case`, `exit`, `cycle` |
| **Arrays** | Static + allocatable, `dimension`, `reshape`, `size`, `shape`, `matmul`, `transpose`, `dot_product` |
| **Subprograms** | `subroutine`, `function`, `module`, `use`, `contains`, `result`, `intent(in/out/inout)`, `recursive` |
| **I/O** | `print *`, `write`, `read`, format specifiers |
| **Intrinsics** | `abs`, `sqrt`, `sin`, `cos`, `exp`, `log`, `mod`, `min`, `max`, `sum`, `product`, `minval`, `maxval`, `any`, `all`, `count` |
