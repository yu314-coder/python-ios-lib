# PyYAML — YAML 1.1 parser + emitter

**Version:** 6.0.3  
**Type:** Pure Python (LibYAML C extension intentionally not built — see below)  
**SPM target:** `PyYAML`  
**Auto-included by:** transformers, datasets, huggingface_hub, manim, plotly, anything with a `config.yaml`  
**Total Python modules:** 17

The standard YAML library for Python. `yaml.safe_load` / `yaml.safe_dump` covers 99% of uses. The full SAX-style parser is exposed if you want token-level access.

## Modules

| Module | What it does |
|---|---|
| `yaml.__init__` | Public API — `safe_load`, `safe_load_all`, `load`, `load_all`, `safe_dump`, `safe_dump_all`, `dump`, `dump_all`, `scan`, `parse`, `compose`, `compose_all`, `serialize`, `serialize_all`, `emit`, `add_constructor`, `add_representer`, `add_resolver`, `add_implicit_resolver`, `add_path_resolver`, `add_multi_constructor`, `add_multi_representer`, `add_multi_resolver`, `YAMLObject` |
| `yaml.error` | `YAMLError`, `MarkedYAMLError`, `Mark` — base exceptions + position info |
| `yaml.tokens` | Token classes from the scanner (`StreamStartToken`, `KeyToken`, `ValueToken`, `ScalarToken`, …) |
| `yaml.events` | Event classes from the parser (`StreamStartEvent`, `MappingStartEvent`, `ScalarEvent`, `SequenceEndEvent`, …) |
| `yaml.nodes` | `Node`, `ScalarNode`, `SequenceNode`, `MappingNode` — composed tree |
| `yaml.reader` | `Reader` — character-level stream input |
| `yaml.scanner` | `Scanner` — produces tokens |
| `yaml.parser` | `Parser` — produces events |
| `yaml.composer` | `Composer` — assembles events into a node tree |
| `yaml.constructor` | `BaseConstructor`, `SafeConstructor`, `FullConstructor`, `Constructor` — node → Python object. The `Safe`/`Full`/`Unsafe` distinction is enforced here |
| `yaml.resolver` | `BaseResolver`, `Resolver` — implicit type detection (`"42"` → `int`, `"true"` → `bool`, ISO dates → `datetime`) |
| `yaml.loader` | Five composite loaders: `BaseLoader`, `SafeLoader`, `FullLoader`, `Loader`, `UnsafeLoader` — pick how much trust |
| `yaml.emitter` | `Emitter` — events → text stream |
| `yaml.serializer` | `Serializer` — nodes → events (inverse of `Composer`) |
| `yaml.representer` | `BaseRepresenter`, `SafeRepresenter`, `Representer` — Python object → node |
| `yaml.dumper` | Three composite dumpers: `BaseDumper`, `SafeDumper`, `Dumper` |
| `yaml.cyaml` | C-extension wrappers (`CParser`, `CEmitter`, `CSafeLoader`, etc.) — import guarded; on iOS the C ext isn't built so this falls back |

### Loader trust levels

| Loader | Allows |
|---|---|
| `BaseLoader` | Strings only — even `42` stays `"42"` |
| `SafeLoader` | YAML 1.1 base spec — `int`, `float`, `bool`, `null`, `str`, `list`, `dict`, `bytes`, `set`, `datetime`. **Default for `safe_load`** |
| `FullLoader` | + arbitrary Python tags **without** instantiating unknown ones — default for `yaml.load` since 5.1 |
| `Loader` | + `!!python/object:foo.bar.Class` — **DANGEROUS**, full code execution |
| `UnsafeLoader` | Same as `Loader` — alias kept for back-compat |

## iOS notes

- **No LibYAML C extension.** `yaml.__with_libyaml__` is `False`. `yaml.CSafeLoader` and friends are unavailable — `yaml.safe_load` automatically uses the pure-Python path. Performance is ~5x slower than LibYAML but still plenty fast for config files.
- **`safe_load` is the default for untrusted YAML.** Never call `yaml.load(text)` (no `Loader=`) on user-supplied YAML — it defaults to `FullLoader` which can construct arbitrary Python objects, and `Loader`/`UnsafeLoader` is full RCE.
- **YAML 1.1 quirks:** `yes`/`no`/`on`/`off` parse as bools (the "Norway problem"); octal numbers use `0o` prefix; sexagesimal is supported. Quote scalars to dodge.

## Example

```python
import yaml

config_text = """
model:
  name: gpt2
  device: mps
  precision: float16
training:
  batch_size: 8
  lr: 3.0e-4
  epochs: 3
  augment:
    - flip
    - rotate
"""

cfg = yaml.safe_load(config_text)
print(cfg["model"]["name"])              # gpt2
print(cfg["training"]["lr"])             # 0.0003

# Round-trip
out = yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False)
print(out)

# Multi-document stream
for doc in yaml.safe_load_all(open("multi.yaml")):
    process(doc)
```
