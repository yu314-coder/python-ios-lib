# decorator — minimal shim of Michele Simionato's package

**Version:** 5.1.1-offlinai-shim (single-file)  
**Type:** Pure Python (~80 lines)  
**SPM target:** N/A — single `decorator.py` file lives at the site-packages root  
**Auto-included by:** manim (`manim.utils.deprecation`)  
**Total Python modules:** 1

Manim's `manim/utils/deprecation.py` does `from decorator import decorate, decorator` and uses nothing else. The full upstream package pulls in `inspect.Signature`-based source rewriting we don't need on iOS, so we ship a 80-line shim that provides exactly those two names. Anything else (`FunctionMaker`, `contextmanager`, `dispatch_on`, `append`) raises `AttributeError` — the gap is intentionally loud so silent breakage is impossible.

## Modules

| Module | What it does |
|---|---|
| `decorator` (single file) | `decorate(func, caller)` — wrap `func` with a `caller(func, *a, **kw)` shim; `decorator(caller)` — turn a caller into a decorator factory. Both preserve name, qualname, docstring, annotations, signature via `functools.wraps` + explicit `__signature__` assignment |

## What's NOT supported

| Upstream API | Drop-in replacement |
|---|---|
| `decorator.FunctionMaker` | None — full source-rewriting class manim doesn't need |
| `decorator.contextmanager` | `contextlib.contextmanager` (stdlib) |
| `decorator.dispatch_on` | `functools.singledispatch` (stdlib) |
| `decorator.append` | None — niche, unused |

Importing any of these raises `AttributeError: module 'decorator' has no attribute '<name>'`.

## iOS notes

- No deps beyond `functools` + `inspect` (both stdlib).
- The dist-info ships a version string of `5.1.1` so `pip install`'s resolver thinks the upstream is already satisfied — `pip install --upgrade decorator` won't replace us unless you `--force-reinstall`.
- If you actually need the full upstream API, `pip install --force-reinstall decorator` lands the real wheel in `~/Documents/site-packages/decorator/` which shadows this shim.

## Example

```python
from decorator import decorate, decorator
import inspect

# 1. decorate(func, caller) — wrap func with a caller shim
def trace(func, *args, **kwargs):
    print(f"calling {func.__name__}({args}, {kwargs})")
    return func(*args, **kwargs)

def add(x, y): return x + y
traced_add = decorate(add, trace)

print(traced_add(2, 3))
# → calling add((2, 3), {})
# → 5

# Signature preserved
print(traced_add.__name__)             # 'add'
print(inspect.signature(traced_add))   # (x, y)


# 2. decorator(caller) — caller → decorator factory
@decorator
def doubler(func, *args, **kwargs):
    return func(*args, **kwargs) * 2

@doubler
def triple(x): return x * 3

print(triple(4))   # → 24  (3 * 4 doubled)
```

This is exactly the API manim's `deprecation.py` consumes:

```python
@deprecated(since="0.18", until="0.20")
def old_function():
    ...
```

…calls `decorate(old_function, deprecate_caller)` under the hood, producing a wrapped `old_function` that emits a deprecation warning on every call while preserving its signature for Sphinx / IDE tooltips.

## Build provenance

Single file at `app_packages/site-packages/decorator.py`, ~80 lines, Python 3.8+ compatible. The `decorator-5.1.1.dist-info/` directory next to it ships only `METADATA`, `RECORD`, and `WHEEL` (no upstream source).
