# pkg_resources — legacy setuptools package-discovery API

**Version:** ships inside setuptools 82.0.1 (no own version)  
**Type:** Pure Python  
**SPM target:** Bundled in the Python framework (top-level `pkg_resources/` package, distributed with setuptools)  
**Auto-included by:** setuptools  
**Total Python modules:** 8

The legacy package-discovery API from setuptools. Many third-party libraries still import it for `pkg_resources.resource_filename(...)` (find a data file inside a package) or `pkg_resources.get_distribution(name).version`. Officially deprecated — the modern equivalents are `importlib.metadata` and `importlib.resources` (stdlib, faster, no setuptools dependency).

> **Layout note:** `pkg_resources` is shipped as part of the setuptools distribution but lives at the top level of `site-packages/`, not under `setuptools/`. Import as `import pkg_resources`. There is no separate `pkg_resources-*.dist-info`.

## Modules

| Module | What it does |
|---|---|
| `pkg_resources.__init__` | Public API. ~3000 LOC monolithic module. Re-exports `Distribution`, `WorkingSet`, `Environment`, `Requirement`, `ResolutionError`, plus `get_distribution()`, `get_provider()`, `iter_entry_points()`, `load_entry_point()`, `parse_requirements()`, `parse_version()`, `resource_filename()`, `resource_stream()`, `resource_string()`, `resource_listdir()`, `resource_exists()`, `cleanup_resources()`, `require()` |
| `pkg_resources.api_tests.txt` | doctest text file (not importable; used by setuptools' own test suite) |
| `pkg_resources/py.typed` | PEP 561 marker (types provided inline) |
| `pkg_resources/tests/` | Internal test suite (5 modules — not part of the public API) |

The whole library is in one giant `__init__.py`. The `tests/` directory ships but should not be imported.

## iOS-specific notes

- **No iOS patches.** Pure Python; runs anywhere CPython runs.
- **No `.egg-info` discovery on iOS.** All bundled packages use the modern `.dist-info` layout, so any code path that scans `.egg-info` is a no-op.
- **`resource_filename()` works** but returns paths inside the read-only app bundle. If you need to *modify* a resource, copy it to `~/Documents/` first.
- **Slow on first import.** Walks the entire `sys.path` building a `WorkingSet`. ~50–100 ms on iOS arm64. Prefer `importlib.metadata.version("foo")` for one-shot lookups.

## Standalone example

```python
import pkg_resources

# Get a version
print(pkg_resources.get_distribution("numpy").version)
# '1.26.4'

# Get a bundled data file's path (read-only — inside the app bundle)
path = pkg_resources.resource_filename("certifi", "cacert.pem")
print(path)

# Get the bytes directly (works even for non-filesystem packages)
schema = pkg_resources.resource_string("jsonschema", "schemas/draft7.json")
print(len(schema), "bytes")

# Iterate registered entry points (e.g. console_scripts of installed packages)
for ep in pkg_resources.iter_entry_points("console_scripts"):
    print(ep.name, "→", ep.module_name)
```

**Migrate to the stdlib API** when touching your own code:

```python
import importlib.metadata as im
import importlib.resources as ir

print(im.version("numpy"))                                       # replaces get_distribution(...).version
schema = ir.files("jsonschema").joinpath("schemas/draft7.json").read_bytes()
for ep in im.entry_points(group="console_scripts"):
    print(ep.name, "→", ep.value)
```

## See also

- [docs/setuptools.md](setuptools.md) — the parent distribution; pulls pkg_resources in via the same install
- [docs/pip.md](pip.md) — historically a heavy user, now mostly migrated to importlib.metadata
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
