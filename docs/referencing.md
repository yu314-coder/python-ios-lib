# referencing — Cross-spec JSON reference resolution

**Version:** 0.36.2
**Type:** Pure Python
**SPM target:** Bundled in `JsonSchema` (no standalone target)
**Auto-included by:** JsonSchema
**Total Python modules:** 7

The general-purpose engine behind `$ref` / `$dynamicRef` resolution in
JSON Schema. Was extracted from `jsonschema` so that other
specifications (OpenAPI, AsyncAPI) could share the same plumbing. You'll
import it directly only when wiring schemas into a `jsonschema`
validator with cross-document references.

## Modules

| Module | What it does |
|---|---|
| `referencing.__init__` | Re-exports `Anchor`, `Registry`, `Resource`, `Specification` |
| `referencing._core` | The implementation: `Registry` (immutable, copy-on-write resource store), `Resource`, `Resolver`, `Resolved`, `Specification`, `Anchor`. Backed by `rpds.HashTrieMap` / `rpds.List` for structural sharing |
| `referencing._attrs` | Project-local `frozen` decorator wrapping `attrs.frozen` |
| `referencing.jsonschema` | `DRAFT4`, `DRAFT6`, `DRAFT7`, `DRAFT201909`, `DRAFT202012` Specification objects + `SchemaResource`, `SchemaRegistry` type aliases |
| `referencing.exceptions` | `NoSuchResource`, `Unresolvable`, `Unretrievable`, `PointerToNowhere`, `NoSuchAnchor`, `CannotDetermineSpecification`, `InvalidAnchor` |
| `referencing.retrieval` | `to_cached_resource()` helper for plugging in your own URI-fetcher |
| `referencing.typing` | `URI`, `Anchor` (Protocol), `D` TypeVar, `Mapping`, `Retrieve` Protocol |

## iOS-specific patches

None — pure Python. **However**, it depends on the [`rpds`](rpds.md)
package, which on iOS is a hand-written Python stub (the upstream
Rust-backed `rpds-py` wheel isn't available for `arm64-apple-ios`). The
stub provides exactly the API surface `referencing` uses
(`HashTrieMap`, `HashTrieSet`, `List` with `insert` / `remove` /
`update` / `convert` returning new instances), so referencing works
without modification.

## Standalone example

```python
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012
from jsonschema import Draft202012Validator

# Define a reusable schema and register it
address_schema = {
    "$id": "https://example.com/schemas/address",
    "type": "object",
    "properties": {
        "street": {"type": "string"},
        "city":   {"type": "string"},
    },
    "required": ["street", "city"],
}

registry = Registry().with_resource(
    uri="https://example.com/schemas/address",
    resource=Resource.from_contents(address_schema, default_specification=DRAFT202012),
)

# Use the registry in a schema that $refs the address
person_schema = {
    "type": "object",
    "properties": {
        "name":    {"type": "string"},
        "address": {"$ref": "https://example.com/schemas/address"},
    },
}

validator = Draft202012Validator(person_schema, registry=registry)
validator.validate({
    "name":    "Ada",
    "address": {"street": "1 Mill Ln", "city": "London"},
})  # OK
```

## See also

- [docs/jsonschema.md](jsonschema.md) — primary (only) consumer in the bundle
- [docs/rpds.md](rpds.md) — the iOS stub that backs `referencing._core`'s persistent maps
- [docs/attrs.md](attrs.md) — `referencing._attrs` wraps `attrs.frozen`
