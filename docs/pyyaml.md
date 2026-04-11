# PyYAML

> **Version:** 6.0.3 | **Type:** Stock | **Status:** Fully working

YAML parser and emitter for Python.

---

## Quick Start

```python
import yaml

data = yaml.safe_load("""
name: OfflinAi
version: 1.0
features:
  - local LLM
  - Python runtime
  - C interpreter
settings:
  temperature: 0.7
  max_tokens: 2048
""")
print(data['name'])           # OfflinAi
print(data['features'][0])    # local LLM
```

---

## Loading (Parsing)

| Function | Description |
|----------|-------------|
| `yaml.safe_load(stream)` | Parse YAML string or file (safe -- no arbitrary objects) |
| `yaml.safe_load_all(stream)` | Parse multi-document YAML (returns generator) |
| `yaml.load(stream, Loader=yaml.SafeLoader)` | Parse with explicit loader |
| `yaml.load_all(stream, Loader=yaml.SafeLoader)` | Parse multi-document with loader |

**Loaders:** `SafeLoader` (recommended), `FullLoader` (default), `UnsafeLoader` (arbitrary Python objects -- avoid)

## Dumping (Serializing)

| Function | Description |
|----------|-------------|
| `yaml.dump(data, stream=None)` | Serialize to YAML string |
| `yaml.dump(data, stream, default_flow_style=False)` | Block style (human-readable) |
| `yaml.dump(data, stream, default_flow_style=True)` | Flow style (compact) |
| `yaml.dump_all(documents, stream)` | Serialize multiple documents |
| `yaml.safe_dump(data, stream)` | Safe serialization (no Python objects) |
| `yaml.safe_dump_all(documents, stream)` | Safe multi-document dump |

### Dump Options

| Parameter | Description |
|-----------|-------------|
| `default_flow_style` | `False` = block style, `True` = flow style, `None` = auto |
| `indent` | Indentation width (default 2) |
| `width` | Line width before wrapping (default 80) |
| `allow_unicode` | Allow unicode characters (default True) |
| `sort_keys` | Sort dict keys (default True) |
| `explicit_start` | Add `---` document start marker |
| `explicit_end` | Add `...` document end marker |
| `default_style` | Quote style for scalars (`None`, `'`, `"`, `|`, `>`) |

---

## YAML Data Types Mapped

| YAML | Python |
|------|--------|
| `string` | `str` |
| `integer` | `int` |
| `float` | `float` |
| `boolean` (`true`/`false`) | `bool` |
| `null` | `None` |
| `sequence` (`- item`) | `list` |
| `mapping` (`key: value`) | `dict` |
| `date` (`2024-01-15`) | `datetime.date` |
| `timestamp` | `datetime.datetime` |
