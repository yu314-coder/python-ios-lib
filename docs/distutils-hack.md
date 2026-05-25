# _distutils_hack — setuptools' distutils compatibility shim

**Version:** ships inside setuptools 82.0.1 (no own version)  
**Type:** Pure Python  
**SPM target:** Bundled in the Python framework (top-level package, name starts with `_`)  
**Auto-included by:** setuptools (loaded via `.pth` file at interpreter startup)  
**Total Python modules:** 2

Setuptools' compatibility shim for the (removed in Python 3.12) stdlib `distutils` module. When some legacy code does `import distutils.util`, this hack intercepts the import via a `sys.meta_path` hook and serves setuptools' bundled `setuptools._distutils` copy instead, so older C-extension sdists that haven't migrated to PEP 517 still install correctly.

You should never `import _distutils_hack` directly. It's an implementation detail of how setuptools registers itself.

## Modules

| Module | What it does |
|---|---|
| `_distutils_hack.__init__` | The meta-path finder + loader. Exports `add_shim()`, `clear_distutils()`, `ensure_local_distutils()`, `do_override()`, `warn_distutils_present()`. Loaded automatically by `distutils-precedence.pth` |
| `_distutils_hack.override` | One-line module: `__import__('_distutils_hack').do_override()` — the entry point a `.pth` file invokes |

## iOS-specific notes

- **No iOS patches.** Pure-Python interpreter logic; runs identically to upstream.
- **Loaded at import time of `setuptools`.** Never runs unless something pulls in setuptools (typically `pip install <sdist>`). At app launch nothing imports it.
- **No effect for wheels.** PEP 517 builds and pre-built wheels never touch `distutils`, so this shim is dead code for the iOS case where everything is pre-built.

## Standalone example

You don't call this. The point of it is invisibility:

```python
# Before _distutils_hack runs (or in Python 3.12+ stdlib without setuptools):
import distutils.util  # ModuleNotFoundError

# After importing setuptools (which triggers the .pth):
import setuptools           # noqa: F401  - triggers hack
import distutils.util       # works — served from setuptools._distutils
print(distutils.util.get_platform())
```

The only "API" worth knowing exists for diagnosing import-order bugs:

```python
import _distutils_hack
_distutils_hack.warn_distutils_present()  # nags if `distutils` loaded before setuptools
```

## See also

- [docs/setuptools.md](setuptools.md) — the package that owns this hack
- [docs/pip.md](pip.md) — the consumer (pip drives sdist builds through setuptools)
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
