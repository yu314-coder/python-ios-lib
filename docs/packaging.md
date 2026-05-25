# packaging — PEP 440/508/517 version + tag utilities

**Version:** 26.0
**Type:** Pure Python
**SPM target:** Bundled in `Matplotlib` (no standalone target)
**Auto-included by:** Matplotlib, pip, importlib_metadata, and almost
every Python distribution tool
**Total Python modules:** 17 (15 top-level + 2 in `licenses/`)

The reference implementation of PEP 440 (version specifiers), PEP 508
(environment markers), PEP 517 (build-system spec), and the wheel/sdist
tag system. If you've ever compared `Version("3.14")` to `Version("3.5")`
or parsed `"requests>=2.0,<3"`, this is the package that does it.

Bundled because basically every install/metadata tool needs it. On iOS
its `tags.py` has explicit `arm64_iphoneos` / `x86_64_iphonesimulator`
support — see the patch notes below.

## Modules

| Module | What it does |
|---|---|
| `packaging.__init__` | Re-exports `__version__`; otherwise empty (submodule package) |
| `packaging.version` | `Version`, `InvalidVersion`, `parse` — PEP 440 version objects with rich comparison |
| `packaging.specifiers` | `Specifier`, `SpecifierSet`, `InvalidSpecifier` — `">=2.0,<3"` parsing and `Version in spec` matching |
| `packaging.requirements` | `Requirement` — full `"name[extras] op version; marker"` parser |
| `packaging.markers` | `Marker` — environment markers (`python_version >= '3.10'`, `sys_platform == 'darwin'`) |
| `packaging.tags` | `Tag`, `sys_tags()`, `compatible_tags()` — generates wheel-compatibility tags. **iOS-aware:** emits `ios_<major>_<minor>_arm64_iphoneos` tags |
| `packaging.utils` | `canonicalize_name`, `canonicalize_version`, `parse_wheel_filename`, `parse_sdist_filename` |
| `packaging.metadata` | `Metadata`, `RawMetadata` — `METADATA` / `PKG-INFO` field parsing |
| `packaging.pylock` | PEP 751 `pylock.toml` model |
| `packaging.licenses` | SPDX expression parsing (`licenses/__init__.py`, `licenses/_spdx.py`) |
| `packaging._parser` | Hand-rolled parser shared by markers/specifiers/requirements |
| `packaging._tokenizer` | Tokenizer feeding `_parser` |
| `packaging._structures` | `Infinity`, `NegativeInfinity` sentinels used in version comparison |
| `packaging._elffile` | Minimal ELF header reader (used by `_manylinux`) |
| `packaging._manylinux` | manylinux glibc-version detection (Linux only; safe no-op on iOS) |
| `packaging._musllinux` | musllinux libc-version detection (Linux only; safe no-op on iOS) |

## iOS-specific patches

None — `packaging` already ships native iOS support upstream.
`packaging.tags.ios_platforms()` emits the correct
`ios_<major>_<minor>_arm64_iphoneos` and `*_iphonesimulator` tags
when `sys.platform == "ios"` (relies on `platform.ios_ver()` from
Python 3.13+). `_manylinux` and `_musllinux` are no-ops on non-Linux
platforms — they probe `/etc/os-release` and gracefully return empty
tag sets.

## Standalone example

```python
from packaging.version import Version
from packaging.specifiers import SpecifierSet
from packaging.requirements import Requirement

v = Version("3.14.0a2")
print(v.is_prerelease, v.major, v.minor)   # True 3 14

spec = SpecifierSet(">=3.10,<4")
print(Version("3.14.0") in spec)           # True
print(Version("4.0.0") in spec)            # False

req = Requirement("torch[gpu] >=2.0; python_version >= '3.10'")
print(req.name, req.extras, req.specifier, req.marker)
# torch  {'gpu'}  >=2.0  python_version >= "3.10"
```

iOS-specific: inspect generated wheel tags

```python
from packaging.tags import sys_tags
for tag in list(sys_tags())[:5]:
    print(tag)
# cp314-cp314-ios_17_0_arm64_iphoneos
# cp314-abi3-ios_17_0_arm64_iphoneos
# cp314-none-ios_17_0_arm64_iphoneos
# py314-none-ios_17_0_arm64_iphoneos
# py3-none-ios_17_0_arm64_iphoneos
```

## See also

- [docs/pip.md](pip.md) — pip uses `packaging` for every dependency it resolves
- [docs/matplotlib.md](matplotlib.md) — bundled into the Matplotlib SPM target
