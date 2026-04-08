# jsonschema

> **Version:** 4.26.0 | **Type:** Stock + patched | **Status:** Working

JSON Schema validation library.

---

## iOS Patches

- `__version__` added to `__init__.py` (was lazy-loaded via importlib.metadata)
- `rpds` stub provides `HashTrieMap.convert()` class method
- Internal imports wrapped in try/except for graceful degradation

## Usage

```python
import jsonschema

schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "age": {"type": "integer", "minimum": 0},
        "email": {"type": "string", "format": "email"}
    },
    "required": ["name", "age"]
}

# Valid
jsonschema.validate({"name": "Alice", "age": 30}, schema)

# Invalid — raises ValidationError
try:
    jsonschema.validate({"name": "Bob", "age": -5}, schema)
except jsonschema.ValidationError as e:
    print(f"Validation error: {e.message}")
```

## Key Functions

| Function | Description |
|----------|-------------|
| `jsonschema.validate(instance, schema)` | Validate and raise on error |
| `jsonschema.Draft7Validator(schema)` | Create reusable validator |
| `validator.is_valid(instance)` | Check without raising |
| `validator.iter_errors(instance)` | Iterate all errors |
