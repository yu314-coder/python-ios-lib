# cffi + pycparser

> **cffi 1.17.1** + **pycparser 2.22**  | **Type:** Native iOS arm64 (cffi has a `.so`) + pure Python (pycparser)  | **Status:** Working — ABI mode + API mode

C Foreign Function Interface — call C library functions from Python
without writing C extension boilerplate. Used internally by
`cryptography`, `cairo`'s pycairo binding, `pynacl`, `argon2-cffi`,
and any other "Python wrapper around a C lib" package. `pycparser` is
cffi's dep — it parses C header files so cffi knows the function
signatures.

You won't usually import these directly unless you're writing your
own bindings.

---

## Quick start — call a C library

iOS exposes most BSD libc + Apple's frameworks (Foundation, Metal,
Network, …) as dynamically-loadable libraries. The shim works for
either:

```python
import cffi

ffi = cffi.FFI()

# Tell cffi what the function looks like
ffi.cdef("""
    int abs(int);
    double floor(double);
""")

# Open libm and resolve the symbols
libm = ffi.dlopen(None)         # None = the global symbol table

print(libm.abs(-7))             # → 7
print(libm.floor(3.9))          # → 3.0
```

```python
# Working with strings + structs
ffi.cdef("""
    int snprintf(char *str, size_t size, const char *format, ...);
""")
libc = ffi.dlopen(None)

buf = ffi.new("char[64]")
libc.snprintf(buf, 64, b"x=%d y=%.2f", ffi.cast("int", 10), ffi.cast("double", 3.14))
print(ffi.string(buf).decode())   # 'x=10 y=3.14'
```

```python
# Open a specific library by path (Apple frameworks)
foundation = ffi.dlopen(
    "/System/Library/Frameworks/Foundation.framework/Foundation")
ffi.cdef("""
    void *NSHomeDirectory(void);
""")
# (call objc_msgSend on the returned NSString to get its UTF8 bytes —
#  cleaner to use ctypes directly for Obj-C, see below)
```

---

## ABI mode vs API mode

| Mode | What you do | Use when |
|---|---|---|
| **ABI mode** (`ffi.cdef` + `ffi.dlopen`) | Declare the C functions in `cdef`, dlopen the library at runtime, call functions | The lib is already compiled; you have headers; one-shot bindings |
| **API mode** (`ffi.set_source` + `ffi.compile`) | Compile a small wrapper C file at build time | You're shipping a polished package; want compile-time errors; faster runtime |

API mode requires a C compiler. iOS doesn't have one (no `clang`
binary you can invoke), so **ABI mode is the only option** for
runtime bindings on-device. Pre-compiled API-mode bindings (built
on macOS via cibuildwheel and shipped as `.so`) work fine — that's
how pycairo works.

---

## When to use cffi vs ctypes

iOS Python ships both. They overlap heavily; subtle differences:

| Feature | cffi | ctypes |
|---|---|---|
| Declaration syntax | C source in `cdef("…")` | Python attribute access (`lib.func.argtypes = [...]`) |
| Reads C headers? | Yes (paste the prototypes into cdef) | No (manually convert each function) |
| Type safety | Verifies argument types at call time | Looser; segfault is yours to debug |
| Performance (call overhead) | ~2× faster than ctypes | slower |
| ABI compatibility checks | Yes (size + signedness checks) | None |
| Stdlib? | No — pip dep | Yes (`import ctypes`) |
| Apple Obj-C friendly | Awkward | Idiomatic via `objc_msgSend` |

**Rule of thumb on iOS**:
- Pure C function calls → **cffi** (cleaner)
- Apple framework / Obj-C classes → **ctypes** (better
  `objc_msgSend` interop)
- Just probing a system call → either (whichever you remember)

---

## pycparser

C header parser. Used by cffi when you `cdef("..."` to figure out
the structure of the C source you pasted in. You wouldn't import it
directly unless writing C-source-analysis tooling:

```python
from pycparser import c_parser, c_ast

parser = c_parser.CParser()
ast = parser.parse("int add(int a, int b) { return a + b; }")
ast.show()
# FileAST:
#   FuncDef:
#     Decl: add, [], [], []
#       FuncDecl:
#         ParamList:
#           Decl: a, [], [], []
#             TypeDecl: a, [], None
#               IdentifierType: ['int']
#           ...
```

Use cases:
- Static analysis of generated C code (verify a code-gen pipeline)
- Compatibility checking between C library versions

For 99% of users this is "the package cffi imports under the hood."

---

## iOS-specific limitations

- **No on-device compilation**. cffi's `set_source` + `compile()` API
  modes require an external C compiler. On iOS that means you must
  ship pre-compiled `.so` extensions built on macOS.
- **`dlopen(None)`** gives you the merged global symbol table —
  includes libc, libm, libdispatch, plus anything statically linked
  into the app binary (Cairo, FFmpeg, freetype, etc., if you bundled
  them). You can resolve any of those symbols by name.
- **Apple framework dlopen paths**: `/System/Library/Frameworks/X.framework/X`
  is the canonical path; the `.framework` is a directory, the bare
  `X` inside is the binary. Works for Foundation, CoreFoundation,
  Metal, AVFoundation, Network, Security, …
- **No `dlopen` for arbitrary `.dylib` outside the app sandbox** —
  iOS only loads dylibs from the app bundle, the system, or app
  Documents (the last is permitted but uncommon).
- **No callback functions across the FFI boundary** when the host
  thread isn't the GIL-holder. Always call back into Python from a
  thread that holds the GIL.

---

## Troubleshooting

### `OSError: cannot load library '...': dlopen(...) image not found`

The dylib path doesn't exist OR isn't signed for the current
provisioning profile. iOS won't load unsigned dylibs. For Apple
frameworks, double-check the case-sensitive path
(`Foundation.framework/Foundation`, not `foundation`).

### `cdef` parsing fails with "before token X" error

pycparser doesn't understand C preprocessor macros, attributes
(`__attribute__((...))`), `inline`, GCC-specific extensions. Strip
those out of headers you paste into `cdef`, or use `cffi`'s
[fake-headers approach](https://cffi.readthedocs.io/en/latest/cdef.html#preprocessor-defines).

### Calls into a function silently return wrong values

You probably got the signature wrong. Print
`ffi.sizeof(type)` for each arg/return type and compare against
`/usr/include/`'s actual definition. The most common gotcha is
`int` vs `long` on 64-bit iOS: `int` = 32 bits, `long` = 64 bits,
unlike most desktop platforms.

---

## Build provenance

- **cffi 1.17.1** — `_cffi_backend.cpython-314-iphoneos.so`
  cross-compiled via cibuildwheel on macOS hosts targeting
  `arm64-apple-ios17.0`
- **pycparser 2.22** — pure Python; identical to upstream PyPI wheel
