# CairoGraphics

> **Version:** Cairo 1.18.4 + Pango 1.56.5 + HarfBuzz 11.4.0 + FreeType 2.13.3 + GLib 2.86.0 + libffi 3.5.2  | **Type:** Native iOS arm64 static libraries  | **Status:** Fully working

Bundle of the Cairo 2D graphics stack — Cairo, Pango (text layout),
HarfBuzz (text shaping), FreeType (font rasterization), GLib (object
model + utilities), libffi — all cross-compiled to `arm64-apple-ios`
static archives. Provides everything `manim`, `pycairo`, and the
manimpango bindings need to draw vector graphics, lay out
multilingual text (CJK, RTL, complex Indic scripts), and render
LaTeX glyphs without spawning external processes.

This is the foundation layer underneath several higher-level packages:

```
   ┌──────────┐  ┌──────────┐  ┌──────────────┐
   │  manim   │  │  pycairo │  │  manimpango  │
   └────┬─────┘  └────┬─────┘  └──────┬───────┘
        │             │               │
        └─────────────┴───────────────┘
                      │
              ┌───────▼────────┐
              │ CairoGraphics  │   ← this package
              │ (Cairo + Pango │
              │  + HarfBuzz +  │
              │  FreeType +    │
              │  GLib + ffi)   │
              └────────────────┘
```

---

## When to add this target

Almost never directly. Add **`Manim`** or **`LaTeXEngine`** instead and
SPM will resolve `CairoGraphics` automatically as a dependency. Add it
explicitly only when you want raw `pycairo` / Pango access without the
full manim / LaTeX stack.

```swift
.dependencies = [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", from: "1.0.0"),
],
.target(name: "MyApp", dependencies: [
    .product(name: "CairoGraphics", package: "python-ios-lib"),
])
```

---

## What's bundled

| File | Size | Purpose |
|---|---|---|
| `libcairo.a` | ~3.2 MB | 2D graphics — paths, surfaces, gradients, clipping |
| `libcairo-gobject.a` | ~50 KB | GObject bindings (used by Pango) |
| `libcairo-script-interpreter.a` | ~150 KB | Cairo script trace replay (debug) |
| `libpango-1.0.a` | ~1.1 MB | Text layout engine — line breaking, BiDi, hyphenation |
| `libpangocairo-1.0.a` | ~120 KB | Pango ↔ Cairo glue — render layouts onto Cairo surfaces |
| `libfreetype.a` | ~1.8 MB | TrueType / OpenType font rasterizer |
| `libharfbuzz.a` | ~3.5 MB | OpenType shaping — kerning, ligatures, complex scripts |
| `libharfbuzz-subset.a` | ~600 KB | Font subsetting (used by Pango) |
| `libfribidi.a` | ~80 KB | Unicode bidirectional algorithm (RTL support) |
| `libglib-2.0.a` | ~2.9 MB | GLib utility primitives (hash tables, quarks, refcount) |
| `libgio-2.0.a` | ~3.1 MB | GLib's I/O abstraction layer (Cairo's PNG / PDF backends) |
| `libffi.a` | ~70 KB | Foreign function interface (Pango's fontconfig wrapper) |

All static archives — get linked into the host app at build time, no
dylib loading at runtime, no separate codesigning step.

---

## Pure-C usage (Swift)

```swift
import CairoGraphics

// Resource bundle accessor — points at copied `cairo/`, `pango/`, `harfbuzz/` resources.
let bundlePath = PythonIOSLib.resourcePath
print("Cairo data files at:", bundlePath ?? "(unavailable)")
```

The Swift surface is intentionally minimal — the libraries are
designed to be called from Python via `pycairo`, not directly from
Swift. If you want a Swift Cairo wrapper, link `libcairo.a` to a
custom target and write the bridge by hand.

---

## Python usage (via pycairo)

```python
import cairo

# 800×600 ARGB surface, draw a red circle, save as PNG.
WIDTH, HEIGHT = 800, 600
surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
ctx = cairo.Context(surface)

# Background
ctx.set_source_rgb(1, 1, 1)
ctx.paint()

# Red filled circle
ctx.set_source_rgb(0.85, 0.20, 0.20)
ctx.arc(WIDTH / 2, HEIGHT / 2, 200, 0, 2 * 3.14159)
ctx.fill()

# Black outline
ctx.set_source_rgb(0, 0, 0)
ctx.set_line_width(4)
ctx.arc(WIDTH / 2, HEIGHT / 2, 200, 0, 2 * 3.14159)
ctx.stroke()

surface.write_to_png("/path/to/Documents/circle.png")
```

---

## Pango (multilingual text)

Pango handles all the text-layout complexity manim needs for Asian /
Arabic / Indic scripts. iOS apps that want to render `MathTex` text
or international `Text` objects in manim go through Pango → HarfBuzz →
FreeType.

The integration is wired up by `manimpango` (the Python binding); see
`docs/manim.md` for usage.

For raw access from Python:

```python
# manimpango exposes the low-level Pango render path
import manimpango
print(manimpango.list_fonts())            # font families that fontconfig found
manimpango.register_font("/path/to/font.ttf")
```

---

## Font setup on iOS

iOS has no `/etc/fonts/fonts.conf`, so neither Pango nor FreeType can
find system fonts the way they do on Linux. The app's Python startup
writes a minimal `fonts.conf` pointing at `Frameworks/katex/fonts/`
(Latin + CJK NotoSansJP) and sets `FONTCONFIG_FILE` so Pango uses it.

```python
import os
print(os.environ["FONTCONFIG_FILE"])      # → ~/Documents/tmp/fonts.conf
print(manimpango.list_fonts())            # → ['KaTeX_Main', 'Noto Sans JP']
```

If you need additional fonts, copy `.ttf` / `.otf` files into
`~/Documents/Workspace/fonts/` and call `manimpango.register_font(path)`
before importing manim.

---

## Limitations

- **No GPU acceleration.** Cairo's iOS build uses the software image
  backend only — no OpenGL, no Quartz back-end. Per-frame rendering
  for manim's high-quality presets (1080p / 4K) is CPU-bound; expect
  ~5-30 fps depending on scene complexity.
- **No PDF / PostScript backend.** The `cairo-pdf.h` and `cairo-ps.h`
  headers are absent — PDF output goes through `pdftex` / SwiftLaTeX
  in this project, not Cairo's PDF surface.
- **No SVG backend in pycairo.** Cairo's SVG surface is not built
  into this static archive. Use `svgwrite` or render via Cairo →
  raster → external SVG path tools (manim takes the rasterize path).
- **Threaded rendering NOT safe.** Cairo is officially thread-safe per
  *surface* but not across surfaces; manim happens to render serially
  and that's intentional. Don't share a `cairo.Context` across Python
  threads.
- **Font caching.** The first text-rendering call on a fresh font path
  takes 200-500 ms while FreeType rasterizes glyphs into the cache.
  Subsequent calls are instant. Pre-warm by calling
  `manimpango.list_fonts()` early in app startup.

---

## Troubleshooting

### `Pango-WARNING **: couldn't load font "Times 9.999"`

Pango's fontconfig fallback is missing. Set `FONTCONFIG_FILE` to a
generated `fonts.conf` *before* the first `import manim` /
`import pangocairo` — the app's Python startup script does this
automatically; if you're using CairoGraphics in your own target,
copy the equivalent from `app_packages/site-packages/offlinai_shell.py`'s
manim init block.

### `cairo_scaled_font_glyph_extents` SIGSEGV inside Pango

Same root cause — missing fontconfig. Pango falls back to a
non-existent font, then SIGSEGVs when Cairo tries to compute its
glyph extents. The `fonts.conf` aliases `Times` / `serif` /
`sans-serif` / `monospace` to your bundled font so this can't
happen.

### Linker error: `Undefined symbols for architecture arm64: _g_thread_*`

You're building against an old GLib that wanted pthreads symbols
exported. Make sure you're on the latest python-ios-lib release —
GLib 2.86 here uses GThread internally and doesn't export that ABI.

---

## Notes on the build

These libraries were cross-compiled with:
- Xcode 16+ command-line tools
- CMake + Meson cross-files targeting `arm64-apple-ios17.0`
- HarfBuzz built with `--with-cairo` and `--with-fontconfig=no`
  (we provide our own fonts.conf at runtime)
- Pango built with `-Dintrospection=disabled` (no GObject
  introspection — saves ~20 MB and isn't useful from Python)
- All `--enable-static --disable-shared` so no dylib copies needed
