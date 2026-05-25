# setuptools — Python package builder

**Version:** 82.0.1  
**Type:** Pure Python  
**SPM target:** Bundled in the Python framework  
**Auto-included by:** pip (build backend for sdists), `_distutils_hack`  
**Total Python modules:** 317

The classic Python package builder + the de-facto stdlib `distutils` replacement (now that `distutils` was removed in Python 3.12). Bundled so `pip install <sdist>` against a package whose `pyproject.toml` declares `build-system.requires = ["setuptools"]` can locate it. You won't run `setuptools` directly unless you're authoring a Python package — and on iOS you mostly can't build C extensions anyway.

The shipped tree includes a vendored copy of `wheel`, `packaging`, `tomli`, `more_itertools`, `jaraco.text`, `importlib_metadata`, `zipp`, `autocommand`, `backports`, and `platformdirs` so the build backend is self-contained.

## Modules

### Top-level (~30 modules)

| Module | What it does |
|---|---|
| `setuptools.__init__` | Public API — `setup()`, `find_packages()`, `find_namespace_packages()`, `Extension`, `Command`, `Distribution`, `Require` |
| `setuptools.build_meta` | PEP 517 build backend entry point — `build_wheel`, `build_sdist`, `get_requires_for_build_wheel` |
| `setuptools.dist` | The `Distribution` class — central metadata + command registry |
| `setuptools.discovery` | Auto-discovery of packages and modules (`PackageFinder`, `PEP420PackageFinder`) |
| `setuptools.extension` | `Extension` — C-extension declaration for `setup.py` builds |
| `setuptools.depends` | Dependency-introspection helpers (`Require`) |
| `setuptools.installer` | `fetch_build_eggs()` — internal sdist-time dependency fetching |
| `setuptools.archive_util` | tar / zip / egg unpacking |
| `setuptools.glob` | Glob enhanced with `**/` recursion |
| `setuptools.modified` | mtime-vs-target staleness checks |
| `setuptools.monkey` | Distutils monkey-patching layer |
| `setuptools.msvc` | MSVC compiler discovery (Windows; no-op on iOS) |
| `setuptools.namespaces` | PEP 420 namespace-package install support |
| `setuptools.warnings` | `SetuptoolsDeprecationWarning` + helpers |
| `setuptools.errors` | `BaseError`, `OptionError`, `RemovedCommandError`, etc. |
| `setuptools.logging` | Logging configuration |
| `setuptools.unicode_utils` | Path-encoding normalization |
| `setuptools.windows_support` | Windows-only file-attribute helpers (no-op on iOS) |
| `setuptools.launch`, `setuptools.wheel`, `setuptools.version` | Misc helpers |
| `setuptools._core_metadata` | Core-metadata 2.x emission |
| `setuptools._entry_points` | Entry-point parser |
| `setuptools._imp`, `setuptools._importlib` | Bridges to `imp` / `importlib` |
| `setuptools._normalization`, `setuptools._reqs`, `setuptools._static`, `setuptools._path`, `setuptools._itertools`, `setuptools._shutil` | Internal utilities |
| `setuptools._scripts`, `setuptools._discovery` | Script wrappers + helpers |

### `setuptools.command` — setup-script commands

24 modules. The ones you might invoke via `python -m build` or `pip install`:

| Module | Command name | What it does |
|---|---|---|
| `command.build` | `build` | Top-level build orchestrator |
| `command.build_py` | `build_py` | Copy `.py` files to build dir |
| `command.build_ext` | `build_ext` | Compile C extensions (mostly unused on iOS — no compiler) |
| `command.build_clib` | `build_clib` | Build static C libraries |
| `command.bdist_egg` | `bdist_egg` | Legacy egg builder |
| `command.bdist_wheel` | `bdist_wheel` | Wheel builder (delegates to `wheel` package) |
| `command.bdist_rpm` | `bdist_rpm` | RPM builder (unused on iOS) |
| `command.sdist` | `sdist` | Source-distribution builder |
| `command.install`, `command.install_lib`, `command.install_egg_info`, `command.install_scripts` | `install*` | Install commands |
| `command.develop` | `develop` | Editable install (`pip install -e .`) |
| `command.dist_info` | `dist_info` | Emit `.dist-info` metadata |
| `command.editable_wheel` | `editable_wheel` | PEP 660 editable-wheel emission |
| `command.egg_info` | `egg_info` | Emit `.egg-info` metadata |
| `command.easy_install` | `easy_install` | The legacy installer (deprecated) |
| `command.rotate`, `command.saveopts`, `command.setopt`, `command.alias`, `command.test`, `command._requirestxt` | misc | Misc + deprecated commands |

### `setuptools._distutils` — bundled distutils

The full `distutils` standard-library module, vendored because Python 3.12+ removed it. ~32 modules including `ccompiler`, `dist`, `cmd`, `extension`, `sysconfig`, `unixccompiler`, etc. + a `command/` sub-package + `compat/` + `compilers/` + `tests/`.

### `setuptools.config` — pyproject.toml / setup.cfg parsing

| Submodule | Provides |
|---|---|
| `config.pyprojecttoml` | `pyproject.toml` `[project]` table parser |
| `config.setupcfg` | `setup.cfg` parser |
| `config.expand` | Token expansion (`file:`, `attr:`, `find:`) |
| `config._apply_pyprojecttoml` | Apply parsed pyproject metadata to `Distribution` |
| `config._validate_pyproject/` | JSON-schema validators (auto-generated) |

### `setuptools.compat`

Per-version Python compatibility shims: `py39.py`, `py310.py`, `py311.py`, `py312.py`.

### `setuptools._vendor`

Vendored copies of `wheel 0.46.3`, `packaging 26.0`, `tomli 2.4.0`, `more_itertools 10.8.0`, `jaraco.text 4.0.0`, `jaraco_context 6.1.0`, `jaraco_functools 4.4.0`, `importlib_metadata 8.7.1`, `zipp 3.23.0`, `autocommand 2.2.2`, `backports.tarfile 1.2.0`, `platformdirs 4.4.0`. These are dependencies of the build backend itself — using vendored copies avoids bootstrap problems where setuptools needs `packaging` before the user's environment has it.

## iOS-specific notes

- **No iOS-specific patches** to setuptools itself.
- **`build_ext` mostly broken on iOS** — there's no C compiler on device. Most sdists that need to build C extensions will fail. The bundle pre-compiles native extensions at framework-build time on macOS so this is a non-issue for shipped packages.
- **Vendored `_vendor/` is mostly dead weight on iOS.** ~5 MB. The runtime path doesn't import it unless you invoke `pip install` on an sdist.
- **`setuptools.command.easy_install` deprecated** — don't use it. Use pip.
- **PEP 517 backend (`build_meta`) works** for pure-Python sdists. CodeBench's in-app `pip install foo.tar.gz` flow hits this path if `pyproject.toml` declares setuptools as the backend.

## Standalone example

You almost never invoke setuptools directly. The two realistic uses:

**1. Build a wheel from a source tree** (CodeBench's `pip install ./mypkg` flow):

```python
from setuptools.build_meta import build_wheel
out_dir = "/path/Documents/wheels"
wheel_name = build_wheel(out_dir, config_settings=None)
print("built:", out_dir + "/" + wheel_name)
```

**2. Parse a `pyproject.toml`** to inspect metadata without invoking pip:

```python
from setuptools.config.pyprojecttoml import read_configuration
cfg = read_configuration("/path/Documents/mypkg/pyproject.toml")
print(cfg["project"]["name"], cfg["project"].get("version"))
print(cfg["project"].get("dependencies", []))
```

The `setup()` function is for `setup.py` files — useful only if you author packages.

## See also

- [docs/pip.md](pip.md) — the consumer; drives setuptools via the PEP 517 backend
- [docs/wheel.md](wheel.md) — the wheel builder setuptools delegates to
- [docs/distutils-hack.md](distutils-hack.md) — the import-time shim that registers setuptools' bundled distutils
- [docs/pkg-resources.md](pkg-resources.md) — the legacy discovery API shipped alongside setuptools
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
