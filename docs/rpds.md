# rpds — Persistent data structures (iOS Python stub)

**Version:** Stub replacing `rpds-py` 0.22.3
**Type:** Pure Python stub (NOT the Rust-backed upstream)
**SPM target:** Bundled in `JsonSchema` (no standalone target)
**Auto-included by:** Referencing (and transitively JsonSchema)
**Total Python modules:** 1 (90-line `__init__.py`)

The upstream `rpds-py` is a Rust crate compiled via PyO3 — providing
true persistent (structural-sharing, copy-on-write) `HashTrieMap`,
`HashTrieSet`, and `List` data structures. There is **no upstream wheel
for `arm64-apple-ios`**, so this iOS build ships a hand-written Python
stub that preserves the IMMUTABLE API surface (`insert`/`remove`/
`update`/`convert` return new instances) but is backed by stdlib `dict`,
`frozenset`, and `tuple` under the hood.

The semantics are correct for `referencing`'s use case — every operation
that "modifies" returns a new object, leaving the receiver alone — but
the asymptotic guarantees are different: real `rpds` shares structure
between versions (O(log n) updates with persistent trees), the stub
does naive copies (O(n) per update). Acceptable here because
`referencing`'s ref-resolution caches are small.

## Module

Single file: `app_packages/site-packages/rpds/__init__.py`.

| Symbol | Backed by | What it provides |
|---|---|---|
| `HashTrieMap(mapping)` | `dict` subclass | `.insert(k, v)`, `.remove(k)`, `.update(*args, **kw)`, `.evolve(**kw)`, `.convert(mapping)` — all return new `HashTrieMap` instances |
| `HashTrieSet(iterable)` | `frozenset` subclass | `.insert(v)`, `.remove(v)`, `.update(*others)`, `.convert(iterable)` — all return new `HashTrieSet` instances |
| `List(iterable)` | `tuple` subclass | `.push_front(v)`, `.push_back(v)`, `.drop_first()`, `.first()`, `.rest()`, `.convert(iterable)` — all return new `List` instances |

`HashTrieMap`'s `.convert()` classmethod is the one `referencing` is
especially picky about — it short-circuits on `None`, returns
the receiver if input is already a `HashTrieMap`, otherwise wraps.

## iOS-specific notes

**This entire package is the iOS workaround.** It exists because the
real `rpds-py` cannot build for `arm64-apple-ios` (the Rust toolchain's
`cargo build` for `aarch64-apple-ios` works but PyO3 doesn't have a CI
target for it). Rather than maintaining a custom PyO3 build, we ship
a behavioral-equivalence stub.

The stub is intentionally minimal — it implements only what
`referencing._core` actually calls. If something else in the bundle ever
needs persistent structural sharing for performance reasons, swap in a
pure-Python persistent library like
[`pyrsistent`](https://pypi.org/project/pyrsistent/).

## Standalone example

```python
from rpds import HashTrieMap, HashTrieSet, List

# HashTrieMap — immutable dict
m1 = HashTrieMap({"a": 1, "b": 2})
m2 = m1.insert("c", 3)
m3 = m2.remove("a")
print(m1)   # {'a': 1, 'b': 2}        ← unchanged
print(m2)   # {'a': 1, 'b': 2, 'c': 3}
print(m3)   # {'b': 2, 'c': 3}

# Useful classmethod used by referencing
print(HashTrieMap.convert(None))         # HashTrieMap({})
print(HashTrieMap.convert({"x": 9}))     # HashTrieMap({'x': 9})

# HashTrieSet — immutable set
s = HashTrieSet([1, 2, 3]).insert(4).remove(1)
print(s)    # frozenset({2, 3, 4})

# List — immutable list with O(1)-ish front operations
lst = List([1, 2, 3]).push_front(0).push_back(4)
print(lst)         # (0, 1, 2, 3, 4)
print(lst.first()) # 0
print(lst.rest())  # (1, 2, 3, 4)
```

## See also

- [docs/referencing.md](referencing.md) — the entire reason this stub exists
- [docs/jsonschema.md](jsonschema.md) — pulls in referencing → rpds transitively
- [docs/small-utils.md](small-utils.md) — sibling doc that also mentions rpds
