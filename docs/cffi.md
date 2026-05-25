# cffi + pycparser — C Foreign Function Interface

**Versions:** cffi 1.17.1 + pycparser 2.22
**Type:** cffi has a native iOS arm64 backend (`_cffi_backend.cpython-314-iphoneos.so`); pycparser is pure Python
**SPM target:** Bundled in the Python framework
**Total modules:** cffi 21 Python + 1 compiled ext, pycparser 13 (+ embedded `ply` parser)

C Foreign Function Interface — call C library functions from Python
without writing C extension boilerplate. Used internally by
`cryptography`, `cairo`'s pycairo binding, `pynacl`, `argon2-cffi`,
and any other "Python wrapper around a C lib" package. `pycparser`
is cffi's dep — it parses C header files so cffi knows function
signatures.

You won't usually import these directly unless you're writing your
own bindings.

---

## Modules — cffi

| Module | What it does |
|---|---|
| `cffi.__init__` | Public API: `FFI`, `VerificationError`, `CDefError`, `FFIError`, `__version__` |
| `_cffi_backend.cpython-314-iphoneos.so` | The C backend — at `site-packages/_cffi_backend.*.so` (root-level, not inside `cffi/`). Provides `Cdata`, `CType`, `Lib`, all the low-level ops |
| `cffi.api` | The `FFI` class — `.cdef()`, `.dlopen()`, `.new()`, `.cast()`, `.string()`, `.buffer()`, `.set_source()`, `.compile()` |
| `cffi.backend_ctypes` | Pure-Python ctypes fallback backend (unused on iOS since the C backend is present) |
| `cffi.cffi_opcode` | Opcode constants for the compiled-binding format |
| `cffi.commontypes` | Common C types (`size_t`, `intptr_t`, `wchar_t`, …) and their platform-specific sizes |
| `cffi.cparser` | C-source parser — wraps pycparser to extract typedefs/functions from `cdef` strings |
| `cffi.error` | `CDefError`, `VerificationError`, `VerificationMissing`, `PkgConfigError` |
| `cffi.ffiplatform` | Platform detection, compiler invocation (only used by API mode) |
| `cffi.lock` | Thread lock helpers |
| `cffi.model` | Type-model classes: `BasePrimitiveType`, `StructType`, `UnionType`, `FunctionPtrType`, `ArrayType`, … |
| `cffi.pkgconfig` | `pkg-config` shell-out (for finding system libs at compile time — not used on iOS) |
| `cffi.recompiler` | API-mode recompiler — generates C source from a cdef (build-time only) |
| `cffi.setuptools_ext` | setuptools integration (build-time) |
| `cffi.vengine_cpy` | CPython-API verification engine |
| `cffi.vengine_gen` | Generic verification engine |
| `cffi.verifier` | The deprecated "Verifier" — legacy API mode (kept for backwards compat) |
| `cffi._imp_emulation` | `imp` module emulation (Python 3.12+ removed `imp`) |
| `cffi._shimmed_dist_utils` | distutils shim (Python 3.12+ removed `distutils`) |
| `cffi._cffi_errors.h` / `_cffi_include.h` / `_embedding.h` / `parse_c_type.h` | C headers — used when API mode generates C source. Not runtime. |

## Modules — pycparser

| Module | What it does |
|---|---|
| `pycparser.__init__` | Public API: `parse_file`, `CParser`, `c_ast`, `c_generator`, `c_lexer` |
| `pycparser.c_ast` | AST node classes — `FuncDef`, `Decl`, `TypeDecl`, `Struct`, `Union`, `Enum`, etc. |
| `pycparser.c_lexer` | C tokenizer (PLY-based) |
| `pycparser.c_parser` | C grammar parser |
| `pycparser.c_generator` | AST → C source pretty-printer |
| `pycparser.ast_transforms` | Helpers used during parse (e.g. resolving typedefs) |
| `pycparser.plyparser` | Base class for PLY-driven parsers |
| `pycparser.lextab` / `pycparser.yacctab` | Pre-generated lex/yacc tables (parse-time speedup) |
| `pycparser._ast_gen` | `_c_ast.cfg`-driven AST class generator (build-time only) |
| `pycparser._build_tables` | Build lex/yacc tables (build-time only) |

### `pycparser.ply` — Embedded PLY

PLY (Python Lex-Yacc) is shipped inside pycparser to avoid an extra
dep. Provides `lex`, `yacc`, `cpp` (C preprocessor), `ctokens`, `ygen`.

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
how `pycairo`, `cryptography`, and `argon2-cffi` work.

---

## When to use cffi vs ctypes

iOS Python ships both. They overlap heavily; subtle differences:

| Feature | cffi | ctypes |
|---|---|---|
| Declaration syntax | C source in `cdef("…")` | Python attribute access (`lib.func.argtypes = [...]`) |
| Reads C headers? | Yes (paste prototypes into cdef) | No (manually convert each function) |
| Type safety | Verifies argument types at call time | Looser; segfault is yours to debug |
| Performance (call overhead) | ~2× faster than ctypes | slower |
| ABI compatibility checks | Yes (size + signedness checks) | None |
| Stdlib? | No — pip dep | Yes (`import ctypes`) |
| Apple Obj-C friendly | Awkward | Idiomatic via `objc_msgSend` |

**Rule of thumb on iOS**:
- Pure C function calls → **cffi** (cleaner)
- Apple framework / Obj-C classes → **ctypes** (better `objc_msgSend` interop)
- Just probing a system call → either

---

## pycparser

C header parser. Used by cffi when you `cdef("...")` to figure out
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
- **Apple framework dlopen paths**:
  `/System/Library/Frameworks/X.framework/X` is the canonical path;
  the `.framework` is a directory, the bare `X` inside is the
  binary. Works for Foundation, CoreFoundation, Metal, AVFoundation,
  Network, Security, …
- **No `dlopen` for arbitrary `.dylib` outside the app sandbox** —
  iOS only loads dylibs from the app bundle, the system, or app
  Documents (the last is permitted but uncommon).
- **No callback functions across the FFI boundary** when the host
  thread isn't the GIL-holder. Always call back into Python from a
  thread that holds the GIL.
- **`@ffi.callback`** works for synchronous callbacks but the
  callback function must be kept alive — store it on a long-lived
  Python object or it'll be garbage-collected and the C side
  segfaults.

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

You probably got the signature wrong. Print `ffi.sizeof(type)` for
each arg/return type and compare against `/usr/include/`'s actual
definition. The most common gotcha is `int` vs `long` on 64-bit
iOS: `int` = 32 bits, `long` = 64 bits, unlike most desktop
platforms.

---

## Packages that depend on cffi (all bundled)

- `cryptography` — TLS, hashing, asymmetric crypto
- `pycairo` — Cairo bindings (uses cffi internally via ABI)
- `pynacl` — libsodium bindings
- `argon2-cffi` — Argon2 password hashing
- `bcrypt` — bcrypt hashing
- Plus a long tail of niche packages

If you `import` any of those, cffi is being used transitively.

---

## Build provenance

- **cffi 1.17.1** — `_cffi_backend.cpython-314-iphoneos.so`
  cross-compiled via cibuildwheel on macOS hosts targeting
  `arm64-apple-ios17.0`
- **pycparser 2.22** — pure Python; identical to upstream PyPI wheel
- **ply** — embedded inside pycparser (no separate package)
