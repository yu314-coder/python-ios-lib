# regex + typing_extensions

> **regex 2024.11.6** + **typing_extensions 4.15.0**  | **Type:** Pure Python (regex has a `.so` upstream; on iOS it falls back to a pure-Python shim of `re`)  | **Status:** regex is partial (Unicode property classes unavailable), typing_extensions is full

Two unrelated utility libraries. They're paired here only because
they're small and orthogonal — not because they're functionally related.

---

## regex

The Matthew Barnett regex package — a richer alternative to the
stdlib `re` module. Supports Unicode property classes (`\p{L}`),
named character sets, lookbehinds of variable width, branch reset
groups, fuzzy matching, and atomic groups.

### iOS shim status

The upstream `regex` ships a heavy C extension (`_regex.so`).
Cross-compiling it for iOS arm64 requires PCRE2 + a fair bit of
glue, and we haven't done that — so on iOS the bundled `regex` is
a **shim that re-exports the stdlib `re` module**. That means:

- `import regex` works
- `regex.match`, `regex.search`, `regex.findall`, `regex.sub`, etc.
  work (delegated to `re`)
- `regex.compile` works
- **Unicode property classes (`\p{L}`, `\p{N}`, `\p{Greek}`)** — DON'T
  work; raise `re.PatternError: bad escape \p`
- **Variable-width lookbehind** — works only if `re` supports it
  (Python 3.7+ does for fixed-width, 3.11+ for some variable cases)
- **Fuzzy matching `(?e)`** — not supported
- **Named character classes (`[[:alpha:]]`)** — not supported

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
   IS_SHIM = not hasattr(regex, '_regex')
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
on lists it as a requirement (e.g. transformers tokenizers), the
shim covers the calls those libs make.

---

## typing_extensions

Backport of typing features from newer Python versions. Used by
libraries that want to support `Annotated`, `ParamSpec`, `TypeAlias`,
`Self`, `LiteralString`, `Required`/`NotRequired` (TypedDict),
`override`, `assert_type`, etc. on older Python interpreters.

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
  `get_type_hints` with extras stripping, `is_typeddict`. The
  stdlib has most of these, but the typing_extensions versions are
  often documented as the "stable" API.

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

- `__version__` attribute is present (4.15.0)
- Pure Python — works in any Python sandbox
- ~80 KB on disk, no native code
