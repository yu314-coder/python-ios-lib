# jsonschema — JSON Schema validation

**Version:** 4.26.0  
**Type:** Pure Python (vendored + patched for iOS)  
**SPM target:** `JSONSchema`  
**Auto-included by:** jupyter, nbformat, openai SDK, anthropic SDK, OpenAPI tooling, anything that ships a `*.schema.json`  
**Total Python modules:** 37 (incl. tests + benchmarks)  
**Companion package:** `jsonschema_specifications` 2024.10.1

Validates JSON-shaped Python data (dicts/lists/scalars) against a JSON Schema. All six drafts supported: 3, 4, 6, 7, 2019-09, 2020-12. Patched on iOS to avoid `importlib.metadata` runtime lookups and to ship a tiny in-house `referencing` shim so cold-start stays fast.

## Modules

### Core

| Module | What it does |
|---|---|
| `jsonschema.__init__` | Lazy-imported public API — `Draft3Validator`, `Draft4Validator`, `Draft6Validator`, `Draft7Validator`, `Draft201909Validator`, `Draft202012Validator`, `FormatChecker`, `SchemaError`, `TypeChecker`, `ValidationError`, `validate`. Lazy `__getattr__` avoids circular imports |
| `jsonschema.validators` | The `Draft*Validator` factory (`create()`, `extend()`), the `validate()` convenience function, `validator_for(schema)`, `validates(uri)` decorator, deprecated `_RefResolver` |
| `jsonschema.exceptions` | `ValidationError`, `SchemaError`, `UndefinedTypeCheck`, `UnknownType`, `FormatError`, `ErrorTree`, `best_match`, `by_relevance`, `relevance` |
| `jsonschema.protocols` | `Validator` typing.Protocol — for static type checking |
| `jsonschema.cli` | `python -m jsonschema schema.json instance.json` CLI |

### Internal (underscore-prefixed)

| Module | What it does |
|---|---|
| `jsonschema._format` | `FormatChecker` — pluggable validators for `format: email/date-time/uri/ipv4/uuid/regex/…` |
| `jsonschema._types` | `TypeChecker` — the `type:` keyword's pluggable type system |
| `jsonschema._keywords` | Modern draft (2019-09, 2020-12) keyword implementations |
| `jsonschema._legacy_keywords` | Draft 3/4/6/7 keyword implementations |
| `jsonschema._typing` | Internal type aliases |
| `jsonschema._utils` | `equal`, `find_additional_properties`, `find_evaluated_*_by_schema`, `unbool`, `URIDict`, `Unset` |

### Tests + benchmarks (skip on iOS)

`jsonschema.tests.*` — pytest suite (`test_validators`, `test_cli`, `test_format`, `test_exceptions`, `test_types`, `test_deprecations`, `test_jsonschema_test_suite`, `fuzz_validate`).

`jsonschema.benchmarks.*` — pyperf benchmarks (`const_vs_enum`, `contains`, `import_benchmark`, `json_schema_test_suite`, `nested_schemas`, `subcomponents`, `unused_registry`, `useless_applicator_schemas`, `useless_keywords`, `validator_creation`).

### Companion package `jsonschema_specifications`

| Module | What it does |
|---|---|
| `jsonschema_specifications.__init__` | `REGISTRY` — URI-keyed map of the six draft meta-schemas. iOS-patched: a self-contained `_SpecRegistry` that defers the `referencing` import to `.combine()` time, avoiding a circular import with jsonschema itself |

## iOS patches

| File | Why |
|---|---|
| `jsonschema/__init__.py` | `__version__ = "4.26.0"` set inline instead of via `importlib.metadata` (avoids `pkg_resources` cold-start) — accessing `__version__` does NOT trigger the deprecation warning the upstream version emits |
| `jsonschema_specifications/__init__.py` | Stripped-down `_SpecRegistry` — full upstream uses `referencing.Registry`; this one duck-types it and only imports `referencing` lazily inside `combine()`. Breaks the import cycle that was blocking `from jsonschema import validate` |
| `rpds` (sibling shim) | Provides `HashTrieMap.convert()` classmethod — `referencing`'s only `rpds` requirement |
| `referencing` | Lightweight subset — `Registry`, `Resource`, draft specifications. Full PyPI `referencing` package isn't bundled |

Anything not listed here is unchanged from upstream 4.26.0.

## Example

```python
import jsonschema
from jsonschema import Draft202012Validator, FormatChecker

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "name":  {"type": "string", "minLength": 1},
        "email": {"type": "string", "format": "email"},
        "age":   {"type": "integer", "minimum": 0, "maximum": 150},
        "tags":  {"type": "array", "items": {"type": "string"}, "uniqueItems": True},
    },
    "required": ["name", "email"],
    "additionalProperties": False,
}

# One-shot — raises on first error
jsonschema.validate(
    {"name": "Alice", "email": "alice@example.com", "age": 30, "tags": ["dev", "ios"]},
    schema,
)

# Reusable validator with format checking + ALL errors
v = Draft202012Validator(schema, format_checker=FormatChecker())
for err in v.iter_errors({"name": "", "email": "not-an-email", "age": -1, "extra": "x"}):
    print(f"{list(err.absolute_path)}: {err.message}")
# []: 'email' is a required property — wait, no, name is empty
# ['name']: '' is too short
# ['email']: 'not-an-email' is not a 'email'
# ['age']: -1 is less than the minimum of 0
# []: Additional properties are not allowed ('extra' was unexpected)
```
