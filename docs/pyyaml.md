# PyYAML

> **Version:** 6.0.3 | **Type:** Stock | **Status:** Fully working

YAML parser and emitter.

---

## Usage

```python
import yaml

# Parse YAML
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

# Generate YAML
output = yaml.dump({'key': 'value', 'list': [1, 2, 3]}, default_flow_style=False)
print(output)
```

## Key Functions

| Function | Description |
|----------|-------------|
| `yaml.safe_load(string)` | Parse YAML string |
| `yaml.safe_load_all(string)` | Parse multi-document YAML |
| `yaml.dump(data)` | Serialize to YAML string |
| `yaml.dump_all(documents)` | Serialize multiple documents |
