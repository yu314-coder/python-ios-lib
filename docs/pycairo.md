# pycairo — Python bindings for Cairo 2D graphics

**Version:** 1.29.0
**Type:** Native iOS arm64 C extension (`_cairo.cpython-314-iphoneos.so`)
**SPM target:** Bundled in `CairoGraphics` (no standalone target)
**Auto-included by:** Manim (vector rendering), Manimpango (font glyph drawing)
**Total Python modules:** 1 thin `__init__.py` + the `.so` extension

The Python binding for [Cairo](https://www.cairographics.org/) — the
vector-graphics library that draws everything in manim, plus the glyph
geometry behind manimpango's text rendering. The bulk of the package is
a single `.so` extension built against the static `libcairo.a` that
ships in the `CairoGraphics` SPM target.

If you want to draw vector graphics directly (PNG, SVG, PDF output)
without going through manim, this is the binding to use.

## Modules

| Module | What it does |
|---|---|
| `cairo.__init__` | One-liner: `from ._cairo import *` plus a `get_include()` helper that returns the path to `cairo/include/` so C extensions linking against cairo can find headers |
| `cairo.__init__.pyi` | Full type stubs — surface classes (`ImageSurface`, `PDFSurface`, `SVGSurface`, `RecordingSurface`), `Context`, `Path`, `Pattern`, `LinearGradient`, `RadialGradient`, `Matrix`, `FontFace`, `ScaledFont`, `FontOptions`, plus enums (`FORMAT_*`, `CONTENT_*`, `ANTIALIAS_*`, `LINE_CAP_*`, `LINE_JOIN_*`, `OPERATOR_*`, `FILL_RULE_*`, `EXTEND_*`, `FILTER_*`, `HINT_STYLE_*`, `SUBPIXEL_ORDER_*`) |
| `cairo._cairo.*.so` | The compiled binding |
| `cairo/include/` | Cairo C headers (`cairo.h`, `cairo-ft.h`, `cairo-svg.h`, `cairo-pdf.h`, …) for downstream C extensions that want to call into cairo themselves |
| `cairo/py.typed` | PEP 561 marker so type-checkers pick up the `.pyi` |

`HAS_*` boolean flags in the module surface tell you which build-time
features were compiled in (`HAS_PNG_FUNCTIONS`, `HAS_PDF_SURFACE`,
`HAS_SVG_SURFACE`, `HAS_FT_FONT`, `HAS_USER_FONT`, etc.). On the iOS
build essentially all the format and font-backend flags are `True`
except the platform-specific ones (no `HAS_QUARTZ_SURFACE`,
`HAS_XLIB_SURFACE`, `HAS_WIN32_SURFACE`).

## iOS-specific notes

The binding itself is upstream pycairo, cross-compiled for
`arm64-apple-ios`. The interesting iOS work is in the underlying C
libraries — see [docs/cairographics.md](cairographics.md) for how
Cairo, Pango, HarfBuzz, FreeType, GLib, and libffi are built as static
archives. pycairo links against those statics at extension-build time.

There are no patches in pycairo's Python layer.

## Standalone example

```python
import cairo

# Draw a gradient-filled rectangle, save as PNG
WIDTH, HEIGHT = 400, 300
surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
ctx = cairo.Context(surface)

# White background
ctx.set_source_rgb(1, 1, 1)
ctx.paint()

# Linear gradient (left → right, blue → magenta)
gradient = cairo.LinearGradient(0, 0, WIDTH, 0)
gradient.add_color_stop_rgb(0, 0.0, 0.4, 1.0)
gradient.add_color_stop_rgb(1, 1.0, 0.0, 0.6)
ctx.set_source(gradient)
ctx.rectangle(50, 50, WIDTH - 100, HEIGHT - 100)
ctx.fill()

# Text
ctx.set_source_rgb(0, 0, 0)
ctx.select_font_face("sans-serif", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
ctx.set_font_size(28)
ctx.move_to(70, HEIGHT // 2 + 10)
ctx.show_text("Hello, iOS")

surface.write_to_png("/path/Documents/hello.png")
```

PDF / SVG output works the same way — swap `ImageSurface` for
`PDFSurface("out.pdf", w, h)` or `SVGSurface("out.svg", w, h)`.

## See also

- [docs/cairographics.md](cairographics.md) — the static-library bundle pycairo links against
- [docs/manim.md](manim.md) — primary consumer (every manim mobject ultimately calls cairo)
- [docs/manimpango.md](manimpango.md) — sibling binding for Pango text layout
