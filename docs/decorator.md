# decorator (CodeBench shim)

> **Version:** 5.1.1-offlinai-shim  | **Type:** Single-file pure-Python shim (~80 lines)  | **Status:** Fully working — covers manim's needs

Tiny shim of [Michele Simionato's `decorator` package](https://pypi.org/project/decorator/).
We don't ship the upstream wheel because:

1. It pulls in `inspect.Signature`-based source rewriting we don't need
   on iOS.
2. It was the lone unmet dep blocking `from manim import *` in the
   in-app shell — `manim/utils/deprecation.py:14` does `from decorator
   import decorate, decorator` and that's the only API surface manim uses.

So the shim provides exactly two functions, `decorate(func, caller)`
and `decorator(caller)`, built on `functools.wraps` + `inspect.signature`.
Anything else from upstream (`FunctionMaker`, `contextmanager`,
`dispatch_on`, …) is intentionally absent — importing those names raises
`AttributeError` so the gap is loud rather than silent.

---

## Quick start

```python
from decorator import decorate, decorator
import functools

# 1. decorate(func, caller) — wrap `func` with a `caller(func, *a, **kw)` shim
def trace(func, *args, **kwargs):
    print(f"calling {func.__name__}({args}, {kwargs})")
    return func(*args, **kwargs)

def add(x, y): return x + y
traced_add = decorate(add, trace)

print(traced_add(2, 3))
# → calling add((2, 3), {})
# → 5

# Signature is preserved (functools.wraps + __signature__ = inspect.signature(func))
print(traced_add.__name__)             # 'add'
import inspect
print(inspect.signature(traced_add))   # (x, y)


# 2. decorator(caller) — turn a caller into a decorator factory
@decorator
def doubler(func, *args, **kwargs):
    return func(*args, **kwargs) * 2

@doubler
def triple(x): return x * 3

print(triple(4))   # → 24  (3 * 4 doubled)
```

This is exactly the API manim's `deprecation.py` consumes — for
example:

```python
@deprecated(since="0.18", until="0.20")
def old_function():
    ...
```

…calls `decorate(old_function, deprecate_caller)` under the hood,
producing a wrapped `old_function` that emits a deprecation warning
on every call while preserving its signature in the docs.

---

## What's NOT supported

Importing any of the following raises `AttributeError`:

| Upstream API | Why it's missing |
|---|---|
| `decorator.FunctionMaker` | Source-rewriting class, hefty implementation manim doesn't need |
| `decorator.contextmanager` | Use `contextlib.contextmanager` from the stdlib |
| `decorator.dispatch_on` | Single-dispatch generic; use `functools.singledispatch` |
| `decorator.append` / `decorator.contextmanager` | Niche, unused |

If you actually need the full upstream package, `pip install decorator`
will fall through to fetching it from PyPI (the dist-info we ship just
labels the shim as v5.1.1; pip's resolver only verifies the version
string matches).

---

## Build provenance

Single file at `app_packages/site-packages/decorator.py`, ~80 lines.
No deps beyond stdlib (`functools`, `inspect`). Runs on any Python 3.8+.
