# regex + typing_extensions

**Versions:** regex 2024.11.6 (dist-info) / shim claims `2024.5.15-torch_ios-shim` + typing_extensions 4.15.0
**Type:** Both pure Python — **regex is an iOS shim around stdlib `re`**, typing_extensions is identical to upstream
**SPM target:** Bundled in the Python framework
**Total modules:** regex 1, typing_extensions 1

Two unrelated utility libraries. They're paired here only because
they're small and orthogonal — not because they're functionally related.

---

## Modules

### regex

| Module | What it does |
|---|---|
| `regex.__init__` | The shim — re-exports `re`'s public surface, defines extra flags (`V0`/`V1`/`BESTMATCH`/`ENHANCEMATCH`/`REVERSE`/`POSIX`/`WORD`/`F`) as no-ops, wraps `findall`/`finditer`/`sub`/`search`/`match`/`fullmatch`/`split` to accept and discard upstream-regex kwargs (`overlapped`, `pos`, `endpos`, `partial`, `concurrent`, `timeout`) |

That's it — `regex/__init__.py` is 61 LOC.

### typing_extensions

| Module | What it does |
|---|---|
| `typing_extensions.__init__` | Single file (~3500 LOC) re-exporting everything from stdlib `typing` and providing backport implementations for newer features |

Same shape as upstream — one `.py` file. Pure Python.

---

## regex

The Matthew Barnett `regex` package — a richer alternative to the
stdlib `re` module. Supports Unicode property classes (`\p{L}`),
named character sets, lookbehinds of variable width, branch reset
groups, fuzzy matching, and atomic groups.

### iOS shim status

The upstream `regex` ships a heavy C extension (`_regex.so`).
Cross-compiling it for iOS arm64 requires PCRE2 + a fair bit of
glue, and we haven't done that — so on iOS the bundled `regex` is
a **shim that re-exports the stdlib `re` module**. That means:

| Feature | Status |
|---|---|
| `import regex` | Works |
| `regex.match`, `regex.search`, `regex.findall`, `regex.sub`, etc. | Work (delegated to `re`) |
| `regex.compile` | Works |
| `re`'s flags (`IGNORECASE`, `MULTILINE`, `DOTALL`, `VERBOSE`, `UNICODE`, `ASCII`) | Work |
| `regex`'s extra flags (`V0`/`V1`/`BESTMATCH`/`ENHANCEMATCH`/`REVERSE`/`POSIX`/`WORD`) | Defined as `0` (no-op) |
| Extra kwargs (`overlapped`, `pos`, `endpos`, `partial`, `concurrent`, `timeout`) | Accepted and silently ignored |
| Unicode property classes (`\p{L}`, `\p{N}`, `\p{Greek}`) | **Don't work** — raise `re.PatternError: bad escape \p` |
| Variable-width lookbehind | Works only if `re` supports it (Python 3.7+ for fixed, 3.11+ for some variable cases) |
| Fuzzy matching `(?e)` | Not supported |
| Named character classes (`[[:alpha:]]`) | Not supported |
| Atomic groups `(?>...)` | Not supported |
| Subroutine calls `(?&name)` | Not supported |

### What works (because `re` supports it)

```python
import regex

# Basic matching
m = regex.match(r"(\w+)@(\w+)", "user@example.com")
print(m.group(1), m.group(2))           # 'user', 'example'

# Substitution
print(regex.sub(r"\d+", "X", "abc123def456"))   # 'abcXdefX'

# Compilation + flags
pat = regex.compile(r"^foo", regex.IGNORECASE | regex.MULTILINE)

# overlapped= is silently ignored (the kwarg is accepted; behavior is non-overlapping)
matches = regex.findall(r"a.a", "abacada", overlapped=True)
# → ['aba', 'ada']   not ['aba', 'aca', 'ada'] like real regex would give
```

### What you'd want regex for that doesn't work

```python
# Unicode property class — UNSUPPORTED
regex.match(r"\p{L}+", "café")          # → re.PatternError: bad escape \p
```

**Workaround**: use Python's stdlib character classes:

```python
import re
# \w matches Unicode letters by default in Python 3.x
re.match(r"\w+", "café").group()         # 'café'

# For specific scripts:
import unicodedata
def is_cjk(s): return any('CJK' in unicodedata.name(c, '') for c in s)
```

### When you actually need real regex

If you're porting code that depends on `\p{...}`, the cleanest fix is:

1. Detect the iOS shim:
   ```python
   import regex
   IS_SHIM = "torch_ios" in regex.__version__
   ```
2. Branch:
   ```python
   if IS_SHIM:
       # Use re-equivalent that doesn't need property classes
       pattern = re.compile(r"[a-zA-Zà-üÀ-Ü…]+")
   else:
       pattern = regex.compile(r"\p{L}+")
   ```

### When the shim is fine

Most regex usage in real codebases doesn't actually use property
classes. If you're calling `regex` because some library you depend
on lists it as a requirement (e.g. transformers tokenizers, black),
the shim covers the calls those libs make. HF tokenizers do use
`\p{...}` for some BPE pre-tokenizers — see `transformers` docs for
which models are affected.

---

## typing_extensions

Backport of typing features from newer Python versions. Used by
libraries that want to support `Annotated`, `ParamSpec`, `TypeAlias`,
`Self`, `LiteralString`, `Required`/`NotRequired` (TypedDict),
`override`, `assert_type`, `deprecated`, etc. on older Python
interpreters.

iOS Python is 3.14, so most of `typing_extensions`' content is
already in the stdlib `typing` module. Importing it just re-exports
the stdlib version — but having `typing_extensions` available means
libraries that pinned to it as a dep continue to work.

### Quick start

```python
from typing_extensions import (
    Annotated, ParamSpec, TypeAlias, Self,
    Literal, LiteralString,
    TypedDict, NotRequired, Required,
    override, assert_type, deprecated,
    TypeVarTuple, Unpack,
    get_type_hints, get_args, get_origin,
    assert_never, reveal_type,
)

# Annotated metadata (PEP 593)
UserID: TypeAlias = Annotated[int, "must be > 0"]

# Self (PEP 673)
class Tree:
    def add_child(self, x: int) -> Self:
        ...
        return self

# TypedDict with optional fields (PEP 655)
class UserDict(TypedDict):
    id: Required[int]
    name: Required[str]
    nickname: NotRequired[str]

# @override decorator (PEP 698)
class Animal:
    def speak(self) -> str: return "..."
class Dog(Animal):
    @override
    def speak(self) -> str: return "Woof"

# @deprecated (PEP 702)
@deprecated("Use new_thing() instead")
def old_thing(): ...

# ParamSpec (PEP 612)
P = ParamSpec("P")
def log_call(f: "Callable[P, R]") -> "Callable[P, R]": ...

# TypeVarTuple (PEP 646)
Ts = TypeVarTuple("Ts")
def first(x: tuple[int, *Ts]) -> int: return x[0]
```

### Why bundle this if Python 3.14 already has it

- **Wheels pin** — `transformers`, `pydantic`, `huggingface_hub`,
  many others require `typing_extensions>=4.x` even when the stdlib
  has the same names. Without the dep present, their imports fail.
- **Provides `deprecated` decorator** — PEP 702 backport. The stdlib
  version is in 3.13+ but iOS Python 3.14's `warnings` module emits
  the warning slightly differently; typing_extensions' implementation
  is more consistent across versions.
- **Some niche runtime helpers** — `assert_never`, `clear_overloads`,
  `get_type_hints` with extras stripping, `is_typeddict`. The stdlib
  has most of these, but the typing_extensions versions are often
  documented as the "stable" API.

### When to import typing_extensions vs typing

```python
# Prefer the stdlib when both work — fewer imports
from typing import Annotated, ParamSpec, Self        # Python 3.11+

# Fall back to typing_extensions if you support older Python OR if
# your dep specifies it
from typing_extensions import override                # only in 3.12+

# The "always works" pattern most libraries use:
try:
    from typing import override
except ImportError:
    from typing_extensions import override
```

### iOS notes

- `__version__` attribute is `4.15.0`
- Pure Python, single file (~3500 LOC) — works in any Python sandbox
- ~80 KB on disk, no native code
- Importable from REPL, scripts, and packages without bootstrap

---

## iOS limitations summary

| Lib | iOS-specific issue |
|---|---|
| `regex` | C ext not cross-compiled; running as a `re`-only shim. Property classes, fuzzy matching, atomic groups silently unavailable. |
| `typing_extensions` | None — identical to upstream wheel. |
