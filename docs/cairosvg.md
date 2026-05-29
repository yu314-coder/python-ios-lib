# CairoSVG — SVG → PNG / PDF / PS rasteriser

**Version:** 1.7.1 (bundled) · **Type:** Pure Python + `cairocffi`
**SPM product:** *none* (by design — see [Why there's no SPM product](#why-theres-no-spm-product))
**Python packages:** `cairosvg`, `cairocffi`, `cffi`, `cssselect2`, `tinycss2`, `webencodings`, `defusedxml`, `pillow`

CairoSVG converts SVG documents to PNG, PDF, or PostScript. Unlike
**manim** (which uses *pycairo* — a statically-linked C extension, fully
self-contained), CairoSVG renders through **`cairocffi`**, which
`dlopen`s the **shared** `libcairo.dylib` at runtime. That one
difference is the entire reason CairoSVG needs extra setup on iOS while
manim does not.

> **TL;DR**
> - **Inside CodeBench:** `import cairosvg` works out of the box — the
>   app bundles `libcairo.dylib` and installs a `find_library` shim.
> - **In your own SwiftPM app:** CairoSVG is *not* a `.product(...)` you
>   can just link. You must (1) embed `libcairo.dylib` in your app and
>   (2) install the `find_library` shim shown below. Follow
>   [Using CairoSVG in your own app](#using-cairosvg-in-your-own-app).

---

## Why there's no SPM product

Every other bundled library in `python-ios-lib` ships as a self-contained
SwiftPM product. CairoSVG can't, because of *how* `cairocffi` loads
cairo:

```python
# cairocffi/__init__.py
cairo = dlopen(
    ffi, ('cairo-2', 'cairo', 'libcairo-2'),
    ('libcairo.so.2', 'libcairo.2.dylib', 'libcairo-2.dll'))
```

1. It calls `ctypes.util.find_library('cairo')`. On iOS there is no
   browsable `/usr/lib` and no `otool` in `PATH`, so the stock
   `find_library` returns **`None`** for everything.
2. It then `dlopen`s a *shared* `libcairo` by bare name. The Python C
   extension that performs the `dlopen` (`_cffi_backend...so`) has **no
   `LC_RPATH`**, so an `@rpath`-embedded dylib (e.g. one delivered by a
   SwiftPM `binaryTarget`) is **not** resolvable from it.

The only thing that works is an **absolute-path `dlopen`**, which means
something must (a) place a real `libcairo.dylib` inside the app and
(b) teach `find_library('cairo')` to return its absolute path. Both are
**app-bundle-layout-specific** and live outside what `Package.swift` can
express — so a `Cairosvg` product would raise `OSError` at
`import cairosvg` for any consumer. We don't ship broken products.

Contrast with **manim**: its `pycairo` (`cairo/_cairo...so`) *statically*
links libcairo + libpixman + libfreetype + libfribidi, so `import cairo`
needs no external dylib at all. That's why **full manim works as a clean
SPM product and CairoSVG does not.**

---

## How it works inside CodeBench

CodeBench solves both halves automatically:

1. **The dylib** — an Xcode *Run Script* build phase copies
   `Frameworks/cairo/libcairo.dylib` → `<App>.app/Frameworks/libcairo.dylib`,
   re-IDs it to `@rpath/libcairo.dylib`, and code-signs it.
2. **The shim** — `app_packages/site-packages/sitecustomize.py` installs
   a `ctypes.util.find_library` override that maps the cairo aliases to
   the bundled dylib's absolute path. Python runs `sitecustomize` at
   interpreter startup, so the shim is active before any
   `import cairosvg`.

```python
# sitecustomize.py (excerpt)
def _install_find_library_shim() -> None:
    import os, ctypes.util as _cu
    here   = os.path.dirname(os.path.abspath(__file__))
    fw_dir = os.path.normpath(os.path.join(here, "..", "..", "Frameworks"))
    cairo_candidates = ("libcairo.dylib", "libcairo.framework/libcairo")
    aliases = {n: cairo_candidates for n in
               ("cairo", "cairo-2", "libcairo-2",
                "libcairo.so.2", "libcairo.2.dylib")}
    _orig = _cu.find_library
    def _find_library(name):
        for rel in aliases.get(name, ()):
            path = os.path.join(fw_dir, rel)
            if os.path.isfile(path):
                return path
        try:    return _orig(name)
        except Exception: return None
    _cu.find_library = _find_library
```

So in CodeBench:

```python
import cairosvg
cairosvg.svg2png(url="diagram.svg", write_to="diagram.png", scale=2.0)
cairosvg.svg2pdf(bytestring=svg_text.encode(), write_to="out.pdf")
```

---

## Using CairoSVG in your own app

If you're building a SwiftPM app on top of `python-ios-lib` and want
CairoSVG, replicate the two pieces CodeBench provides. The pure-Python
dependencies are already linkable as SPM products; only the **native
dylib** and the **shim** are manual.

### 1. Link the Python-side dependencies

These are all self-contained SPM products in this package:

```swift
// Package.swift  (your app)
dependencies: [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", branch: "main"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Cffi",        package: "python-ios-lib"), // cairocffi backend
        .product(name: "Cssselect2",  package: "python-ios-lib"), // pulls Tinycss2
        .product(name: "Defusedxml",  package: "python-ios-lib"),
        .product(name: "Pillow",      package: "python-ios-lib"),
    ]),
]
```

Then add the `cairosvg/` and `cairocffi/` package directories to your
app's `site-packages` (they're pure-Python — copy them from this repo's
`app_packages/site-packages/{cairosvg,cairocffi}`, or `pip install`
them into your bundle).

> There is intentionally **no** `Cairosvg`/`Cairocffi` SPM product — see
> [Why there's no SPM product](#why-theres-no-spm-product). Ship those
> two pure-Python dirs as resources yourself.

### 2. Embed `libcairo.dylib` in your app

Add a **Run Script** build phase (after "Embed Frameworks") that copies
the dylib this repo already ships and re-IDs + signs it:

```bash
# Copy the prebuilt iOS arm64 libcairo (statically links pixman/freetype/
# fribidi) into the app's Frameworks/.
CAIRO_SRC="$SRCROOT/path/to/python-ios-lib/Frameworks/cairo/libcairo.dylib"
CAIRO_DST="$TARGET_BUILD_DIR/$WRAPPER_NAME/Frameworks/libcairo.dylib"
if [ -f "$CAIRO_SRC" ]; then
    cp "$CAIRO_SRC" "$CAIRO_DST"
    install_name_tool -id "@rpath/libcairo.dylib" "$CAIRO_DST" 2>/dev/null || true
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$CAIRO_DST" || true
fi
```

`libcairo.dylib` is iOS arm64, `minos 17.0`, install-name
`@rpath/libcairo.dylib`, ~6 MB. (No simulator slice — build on a real
device, matching the [pending iPhone-Simulator stub work](../README.md).)

### 3. Install the `find_library` shim

Ship a `sitecustomize.py` (or `usercustomize.py`) on `sys.path` in your
app that points the cairo aliases at wherever **your** app bundles the
dylib. The CodeBench version assumes
`<site-packages>/../../Frameworks/libcairo.dylib`; adjust `fw_dir` to
match your bundle layout. Copy the `_install_find_library_shim()`
function from
[the excerpt above](#how-it-works-inside-codebench) verbatim and call it
at startup.

If you can't run `sitecustomize`, do the equivalent inline **before the
first `import cairosvg`**:

```python
import os, ctypes, ctypes.util
_libcairo = os.path.join(os.environ["HOME"], "..",
                         "<YourApp>.app", "Frameworks", "libcairo.dylib")
ctypes.CDLL(_libcairo, mode=ctypes.RTLD_GLOBAL)          # preload
_orig = ctypes.util.find_library
ctypes.util.find_library = lambda n: _libcairo if "cairo" in n else _orig(n)

import cairosvg   # now resolves
```

### 4. Verify

```python
import cairosvg
png = cairosvg.svg2png(bytestring=b'<svg xmlns="http://www.w3.org/2000/svg" '
                                  b'width="16" height="16"><rect width="16" '
                                  b'height="16" fill="red"/></svg>')
assert png[:8] == b"\x89PNG\r\n\x1a\n", "cairo didn't render"
print("CairoSVG OK:", len(png), "bytes")
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `OSError: cannot load library 'cairo'` at `import cairosvg` | `find_library('cairo')` returned `None` and `dlopen` found no `libcairo.2.dylib` | Step 3 shim not active / wrong `fw_dir` path |
| `dlopen(...): image not found` | `libcairo.dylib` not in `<App>.app/Frameworks/` | Step 2 build phase didn't run, or wrong `CAIRO_SRC` |
| Renders blank / wrong fonts | font discovery, not cairo | cairo statically links freetype/fribidi; supply fonts via fontconfig or embed in the SVG |
| Works in CodeBench, fails in your app | you inherited the shim's hard-coded `../../Frameworks` path | recompute `fw_dir` for your bundle layout (Step 3) |

---

## Do you actually need CairoSVG?

- **Rendering math / animations?** Use **manim** — it needs none of this
  (statically-linked pycairo). See [manim.md](manim.md).
- **Just rasterising an SVG to PNG once?** If you already depend on
  manim, you can load the SVG as an `SVGMobject` and export a frame, or
  use Pillow + a simpler path, avoiding the cairo-shared-lib dance
  entirely.
- **Need CairoSVG's exact SVG feature coverage (CSS, filters, gradients)?**
  Then follow the 4 steps above.
