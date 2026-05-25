# regex — iOS shim around stdlib `re`

**Version:** `2024.5.15-torch_ios-shim` (`__version__`); dist-info reports `2024.11.6`
**Type:** Pure Python — **iOS shim re-exporting `re`** (not the real Matthew Barnett extension)
**SPM target:** Bundled in the Python framework
**Total Python modules:** 1 (`regex/__init__.py`, 61 lines)

A 61-line shim that re-exports stdlib `re` under the `regex` name so
libraries that list the Matthew Barnett `regex` package as a dependency
continue to import on iOS. The real `regex` package ships a heavy C
extension (`_regex.so`) around PCRE2 that we haven't cross-compiled for
iOS arm64.

## Modules

| Module | What it does |
|---|---|
| `regex.__init__` | The shim. Re-exports `re`'s public surface via `from re import *`. Defines `regex`-specific flags (`V0`/`V1`/`BESTMATCH`/`ENHANCEMATCH`/`REVERSE`/`POSIX`/`WORD`/`F`) as `0` (no-op). Wraps `findall`/`finditer`/`sub`/`search`/`match`/`fullmatch`/`split` to accept and discard upstream-regex-only kwargs (`overlapped`, `pos`, `endpos`, `partial`, `concurrent`, `timeout`). 61 LOC total |

That's it — no submodules, no C extension.

## Shim status matrix

| Feature | Status on iOS |
|---|---|
| `import regex` | Works |
| `regex.match` / `regex.search` / `regex.findall` / `regex.sub` / `regex.compile` / `regex.split` / `regex.finditer` / `regex.fullmatch` | Work (delegated to `re`) |
| `re`'s flags: `IGNORECASE`, `MULTILINE`, `DOTALL`, `VERBOSE`, `UNICODE`, `ASCII` | Work |
| `regex`-extra flags: `V0`, `V1`, `BESTMATCH`, `ENHANCEMATCH`, `REVERSE`, `POSIX`, `WORD`, `F` | **No-op** (defined as `0`) |
| Extra kwargs: `overlapped`, `pos`, `endpos`, `partial`, `concurrent`, `timeout` | **Accepted and silently ignored** |
| Unicode property classes `\p{L}`, `\p{N}`, `\p{Greek}` | **Don't work** — raise `re.PatternError: bad escape \p` |
| Variable-width lookbehind | Works only if `re` supports it (Python 3.7+ for fixed, 3.11+ for some variable cases) |
| Fuzzy matching `(?e)` | Not supported |
| Named character classes `[[:alpha:]]` | Not supported |
| Atomic groups `(?>...)` | Not supported |
| Subroutine calls `(?&name)` | Not supported |

## What's exposed

```python
import re as _re
from re import *

__version__ = "2024.5.15-torch_ios-shim"

# regex flags mapped to no-ops or re equivalents
V1 = V0 = 0                # version flag
BESTMATCH = 0              # best-match-greedy
ENHANCEMATCH = 0
REVERSE = 0
POSIX = 0
WORD = 0
DEFAULT_VERSION = V0
B = _re.ASCII              # WORD boundary "ascii" alias
F = BESTMATCH              # fuzzy
```

Then thin wrappers around `_re.findall` / `_re.finditer` / `_re.sub` /
`_re.search` / `_re.match` / `_re.fullmatch` / `_re.split` that accept
the upstream-regex kwargs and pass only `flags` (and `count` / `maxsplit`
where applicable) through to `re`.

## Example — what works

```python
import regex

# Basic matching
m = regex.match(r"(\w+)@(\w+)", "user@example.com")
print(m.group(1), m.group(2))           # 'user', 'example'

# Substitution
print(regex.sub(r"\d+", "X", "abc123def456"))   # 'abcXdefX'

# Compilation + flags
pat = regex.compile(r"^foo", regex.IGNORECASE | regex.MULTILINE)

# overlapped= is silently ignored (kwarg accepted; behavior is non-overlapping)
matches = regex.findall(r"a.a", "abacada", overlapped=True)
# → ['aba', 'ada']   not ['aba', 'aca', 'ada'] like real regex would give
```

## What doesn't

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

## When you need real regex

If you're porting code that depends on `\p{...}`, detect the iOS shim
and branch:

```python
import regex
IS_SHIM = "torch_ios" in regex.__version__

if IS_SHIM:
    # Use re-equivalent that doesn't need property classes
    pattern = re.compile(r"[a-zA-Zà-üÀ-Ü…]+")
else:
    pattern = regex.compile(r"\p{L}+")
```

## When the shim is fine

Most regex usage in real codebases doesn't touch property classes. If
your dep listed `regex` for compatibility (transformers tokenizers,
black, etc.), the shim usually covers the calls those libs make.
HuggingFace tokenizers DO use `\p{...}` for some BPE pre-tokenizers —
the affected models will fail at tokenization time with the `bad escape
\p` error, in which case you either need a different model or to
build a real `regex` for iOS.

## iOS notes

- C extension `_regex.so` not cross-compiled for iOS arm64 — building it requires PCRE2 + a fair bit of glue
- Pure Python shim means no platform-specific bugs; behaves identically across all iOS architectures
- `__version__` includes `"torch_ios-shim"` substring so callers can sniff the shim status without try/except
- ~60 KB on disk (single small `.py` file) — no native code, no embedded tables

## See also

- The dist-info reports `2024.11.6` (the upstream wheel version that would have shipped with the C extension) but the actual import surface is the shim
- Python stdlib `re` module — what every call ultimately delegates to
