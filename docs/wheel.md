# wheel — `.whl` builder and packer

**Version:** 0.46.3  
**Type:** Pure Python  
**SPM target:** Bundled in the Python framework  
**Auto-included by:** pip (build backend invokes it via setuptools), setuptools (via `bdist_wheel` command)  
**Total Python modules:** 14

Builds `.whl` files from a source tree, or repacks existing wheels. Bundled so pip can build wheels when needed (sdist → wheel as part of install). For most users: nothing to do unless you're authoring a Python package or repacking a sdist on device.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `wheel.__init__` | Exposes `__version__` only |
| `wheel.__main__` | CLI entry — `python -m wheel <command>` |
| `wheel._bdist_wheel` | The internal `bdist_wheel` implementation (the part setuptools' `command.bdist_wheel` proxies into) |
| `wheel.bdist_wheel` | Deprecated public shim for `_bdist_wheel` (kept for backward compat) |
| `wheel.wheelfile` | `WheelFile` — read / write `.whl` archives (zip with metadata + `RECORD`) |
| `wheel.metadata` | `metadata.json` ↔ core-metadata translation |
| `wheel._metadata` | Internal metadata helpers |
| `wheel.macosx_libfile` | Parse macOS Mach-O headers (extract deployment target / arch from `.dylib`) — used when tagging macOS wheels |
| `wheel._setuptools_logging` | Logging-format compatibility with setuptools |

### `wheel._commands` — CLI subcommands

| Submodule | Command | What it does |
|---|---|---|
| `_commands.__init__` | (driver) | Argument-parser + dispatch for `python -m wheel <cmd>` |
| `_commands.convert` | `wheel convert` | Convert an `.egg` to a `.whl` |
| `_commands.pack` | `wheel pack` | Repack an unpacked wheel directory back into a `.whl` |
| `_commands.unpack` | `wheel unpack` | Extract a `.whl` into a directory tree |
| `_commands.tags` | `wheel tags` | Inspect / retag a wheel's compatibility tags (`cp314-cp314-iphoneos_15_0_arm64`) |

## iOS-specific notes

- **No iOS patches** to wheel itself.
- **`macosx_libfile` not exercised on iOS.** It reads macOS-only Mach-O metadata to pick a `macosx_*` platform tag. iOS wheels use `iphoneos_*` tags emitted by pip + setuptools directly.
- **Pure Python — works anywhere.** No C, no native deps. Unpacking and packing wheels on device is fine.
- **Wheels with C extensions can be REPACKED** on iOS but not BUILT — there's no on-device compiler. The `pack` / `unpack` / `tags` commands operate only on the zip + metadata and don't touch the binaries inside.

## Standalone example

Build a wheel from a source tree (one-shot, via setuptools' delegating command):

```python
import subprocess, sys
subprocess.check_call([sys.executable, "-m", "setuptools.build_meta",
                       "build_wheel", "/path/Documents/mypkg/dist"])
# or, equivalently, from setuptools.build_meta import build_wheel; build_wheel(...)
```

Direct wheel-file manipulation via the library:

```python
from wheel.wheelfile import WheelFile

# Read a wheel and list its contents
with WheelFile("/path/Documents/mypkg-1.0-py3-none-any.whl") as wf:
    for name in wf.namelist():
        print(name)
    # Verify all file hashes match the RECORD
    wf.validate_record()
```

Use the CLI for repack / unpack workflows:

```bash
# (in the in-app shell)
python -m wheel unpack mypkg-1.0-py3-none-any.whl -d /tmp/unpacked
# edit files under /tmp/unpacked/mypkg-1.0/
python -m wheel pack /tmp/unpacked/mypkg-1.0
# re-tag for a different platform
python -m wheel tags --platform-tag iphoneos_15_0_arm64 mypkg-1.0-py3-none-any.whl
```

## See also

- [docs/setuptools.md](setuptools.md) — the PEP 517 backend that drives wheel building
- [docs/pip.md](pip.md) — the primary consumer (`pip install` calls into wheel for both build and unpack)
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
