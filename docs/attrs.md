# attrs — Classes without boilerplate

**Version:** 24.2.0
**Type:** Pure Python
**SPM target:** Bundled in `JsonSchema` (no standalone target)
**Auto-included by:** JsonSchema, Referencing, Cattrs
**Total Python modules:** 6 (`attrs/`) + 13 (`attr/` sibling package)

`attrs` is the modern "decorator → class" generator: declare fields with
`@define`/`field()` and you get `__init__`, `__repr__`, `__eq__`,
`__hash__`, slots, type-validation, immutability, and converters for
free. The `attrs` package is the user-facing modern API; the older
`attr` namespace ships alongside it (re-exported) for backwards
compatibility — both come from the same wheel.

It's bundled because `referencing` (used by `jsonschema`) imports it for
its frozen dataclass machinery.

## Modules

### `attrs/` — modern API

| Module | What it does |
|---|---|
| `attrs.__init__` | Re-exports the public API: `define`, `field`, `frozen`, `mutable`, `Factory`, `Attribute`, `Converter`, `NOTHING`, `evolve`, `fields`, `fields_dict`, `validate`, `has`, `make_class`, `assoc`, `asdict`, `astuple`, `cmp_using`, `resolve_types`, `inspect` |
| `attrs.converters` | Stock converters: `optional`, `default_if_none`, `pipe`, `to_bool` |
| `attrs.exceptions` | `FrozenInstanceError`, `FrozenAttributeError`, `AttrsAttributeNotFoundError`, `NotAnAttrsClassError`, etc. |
| `attrs.filters` | Predicates for `asdict()` / `astuple()`: `include`, `exclude` |
| `attrs.setters` | Setter pipelines: `frozen`, `validate`, `convert`, `pipe`, `NO_OP` |
| `attrs.validators` | Stock validators: `instance_of`, `in_`, `lt`/`le`/`gt`/`ge`, `min_len`/`max_len`, `matches_re`, `deep_iterable`, `deep_mapping`, `optional`, `or_`, `and_` |

### `attr/` — classic API (re-exports)

The `attr.*` names that all old code uses (`attr.s`, `attr.ib`, `attr.attrs`, `attr.attrib`). Same submodule layout as `attrs/` plus `_make`, `_funcs`, `_cmp`, `_compat`, `_config`, `_next_gen`, `_version_info`. New code should `import attrs` (the plural form) instead.

## iOS-specific patches

None — `attrs` is pure Python with no platform-specific code paths.

## Standalone example

```python
from attrs import define, field, frozen, validators

@define
class Point:
    x: float = field(validator=validators.instance_of((int, float)))
    y: float = field(validator=validators.instance_of((int, float)))

@frozen
class Vector:
    """Immutable — assignment raises FrozenInstanceError."""
    dx: float
    dy: float

p = Point(1.5, 2.0)
print(p)          # Point(x=1.5, y=2.0)
print(p == Point(1.5, 2.0))  # True

v = Vector(3.0, 4.0)
# v.dx = 5.0  →  FrozenInstanceError
```

For a "tell me what fields this class has" workflow:

```python
from attrs import fields
for f in fields(Point):
    print(f.name, f.type, f.default)
```

## See also

- [docs/jsonschema.md](jsonschema.md) — primary consumer (via `referencing`)
- [docs/referencing.md](referencing.md) — uses `attrs.frozen` for its `Anchor`/`Resource`/`Specification` types
