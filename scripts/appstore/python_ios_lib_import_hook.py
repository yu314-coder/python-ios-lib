"""
python_ios_lib_import_hook
============================

Runtime companion to scripts/appstore/wrap-binaries-as-frameworks.sh.

The wrap script moved every Python C extension out of its package
directory and into <App>.app/Frameworks/<sanitized>.framework/.
Without this hook, `import numpy._core._multiarray_umath` would
ImportError because the .so isn't where Python expects.

This hook reads the manifest the wrap script emitted
(<App>.app/python-ios-lib_extension_manifest.txt) and installs a
MetaPathFinder that:

  1. Watches for any import matching a manifest entry
  2. Loads the .so from inside the framework via
     importlib.machinery.ExtensionFileLoader
  3. Sets `module.__file__` to the original (placeholder) path so
     packages that introspect __file__ for data-file lookup keep
     working

INSTALL: in your app's Py_Initialize bootstrap, immediately after
`Py_Initialize()` returns and BEFORE any user-code import:

    PyRun_SimpleString("""
        import sys, os
        sys.path.insert(0, os.environ['PYTHON_IOS_LIB_HOOK_DIR'])
        import python_ios_lib_import_hook
        python_ios_lib_import_hook.install()
    """)

Set the env var beforehand:

    setenv("PYTHON_IOS_LIB_HOOK_DIR",
           Bundle.main.bundleURL
                  .appendingPathComponent("python-stdlib").path,
           1);

…and the hook file itself ends up in python-stdlib/ via your
build-script's stdlib copy step.
"""
from __future__ import annotations

import os
import sys
import importlib.abc
import importlib.machinery
import importlib.util


_INSTALLED = False


class FrameworkExtensionFinder(importlib.abc.MetaPathFinder):
    """Map dotted Python module names → .so binaries inside
    `<App>.app/Frameworks/<sanitized>.framework/<sanitized>`.

    The manifest is a plain text file, one entry per line:
        numpy._core._multiarray_umath=numpy_core_multiarray_umath
        scipy.linalg._fblas=scipy_linalg_fblas
        stdlib._struct=stdlib_struct
        ...

    The "stdlib." prefix on stdlib extensions disambiguates them from
    user-package modules (e.g. `_struct` is in stdlib AND could
    theoretically appear in a user package). At lookup time we strip
    the prefix so a real `import _struct` finds it.
    """

    __slots__ = ("frameworks_dir", "_map", "_origin_map")

    def __init__(self, frameworks_dir: str, manifest_path: str) -> None:
        self.frameworks_dir = frameworks_dir
        self._map: dict[str, str] = {}      # python.module → /path/to/.framework/binary
        self._origin_map: dict[str, str] = {}  # python.module → original .so path (for __file__)

        if not os.path.exists(manifest_path):
            return

        bundle_dir = os.path.dirname(manifest_path)
        with open(manifest_path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or "=" not in line:
                    continue
                module_name, fw_name = line.split("=", 1)
                fw_path = os.path.join(
                    frameworks_dir, f"{fw_name}.framework", fw_name)
                if not os.path.exists(fw_path):
                    continue
                # Stdlib stuff is keyed as "stdlib._struct" in the
                # manifest; strip the prefix for actual import lookup.
                key = module_name
                if key.startswith("stdlib."):
                    key = key[len("stdlib."):]
                self._map[key] = fw_path
                # Reconstruct what the original .so path would have
                # been, so we can hand it back as __file__ for
                # introspection-driven code (matplotlib, scipy do this).
                # For stdlib extensions the original lived under
                # python-stdlib/lib-dynload; for SPM bundles, under
                # python-ios-lib_<Pkg>.bundle/<package_name>/.../<name>.so.
                # We don't know the exact suffix the wrapper stripped,
                # so just point __file__ at the framework binary path.
                # Most code only checks `os.path.dirname(__file__)`.
                self._origin_map[key] = fw_path

    def find_spec(self, fullname: str, path=None, target=None):
        fw_path = self._map.get(fullname)
        if fw_path is None:
            return None
        loader = importlib.machinery.ExtensionFileLoader(fullname, fw_path)
        spec = importlib.util.spec_from_file_location(
            fullname, fw_path, loader=loader)
        # ExtensionFileLoader uses the path as __file__. That makes
        # introspection like `os.path.dirname(__file__)` resolve to
        # the framework dir — which is *correct* for sibling-data
        # lookup if we copied the data files alongside; otherwise
        # packages like scipy that use __file__ to find numpy headers
        # may still need the original-path hint we record above.
        return spec


def install() -> None:
    """Read the manifest from <App>.app/ and install the finder.
    Idempotent — safe to call multiple times.
    """
    global _INSTALLED
    if _INSTALLED:
        return

    # Bundle.main is the .app dir; the manifest lives at its root.
    # Discover it by walking up from Python's own location: PYTHONHOME
    # is set to <App>.app/python-stdlib, so .. is the .app dir.
    home = os.environ.get("PYTHONHOME")
    if not home:
        return
    bundle = os.path.dirname(home)
    manifest = os.path.join(bundle, "python-ios-lib_extension_manifest.txt")
    frameworks = os.path.join(bundle, "Frameworks")

    if not os.path.exists(manifest):
        # Either we're in a dev build that didn't run the wrap script,
        # or the script failed silently. Either way: don't blow up,
        # just skip the hook and let normal imports run.
        return

    finder = FrameworkExtensionFinder(frameworks, manifest)
    if not finder._map:
        return  # empty manifest, nothing to do

    # Insert at index 0 so we beat the standard PathFinder for any
    # module name we know about. Our finder returns None for unknown
    # names so it's transparent for everything else.
    sys.meta_path.insert(0, finder)
    _INSTALLED = True


def uninstall() -> None:
    """Remove our finder from sys.meta_path. Mainly for tests."""
    global _INSTALLED
    sys.meta_path[:] = [
        f for f in sys.meta_path
        if not isinstance(f, FrameworkExtensionFinder)
    ]
    _INSTALLED = False
