# manimpango

> **Version:** 0.6.1  | **Type:** Native iOS arm64 Cython binding to Pango (3 `.so` files, ~27 MB total)  | **Status:** Working — text2svg via Pango + pycairo-compatibility fallback for iOS

Cython bindings to [Pango](https://pango.gnome.org/) (text layout) +
[HarfBuzz](https://harfbuzz.github.io/) (text shaping). Used by
manim's `Text(...)` mobject to lay out and shape multi-script text
(English + CJK + Arabic + Indic). Without it, manim can only render
LaTeX math; with it, plain `Text("Hello 你好 مرحبا")` works.

---

## What's bundled

| File | Size | Purpose |
|---|---|---|
| `manimpango/cmanimpango.cpython-314-iphoneos.so` | 10 MB | The main Cython binding |
| `manimpango/_register_font.cpython-314-iphoneos.so` | 9.4 MB | Font registration helper |
| `manimpango/enums.cpython-314-iphoneos.so` | 7.7 MB | Pango enum constants |

The Pango / HarfBuzz / FreeType / GLib / libffi static archives that
these .so files link against live in `Sources/CairoGraphics/` — see
[docs/cairographics.md](cairographics.md).

---

## Quick start

```python
import manimpango

# List installed font families (whatever fontconfig found)
fams = manimpango.list_fonts()
print(fams)
# → ['KaTeX_Main', 'Noto Sans JP', ...] (depends on what app pre-registered)

# Register a font from disk so Pango can find it by family name
manimpango.register_font("/path/Documents/fonts/MyFont.ttf")

# Render text to SVG (returned as a string of XML)
svg = manimpango.text2svg(
    settings=[manimpango.TextSetting(
        start=0, end=11,
        font="Noto Sans JP",
        slant=manimpango.Slant.NORMAL,
        weight=manimpango.Weight.NORMAL,
        line_height=1.0,
        font_size=24,
    )],
    text="Hello 你好",
    lang_str="en-US",
    file_name="/path/Documents/out.svg",
    style_str="font-family: 'Noto Sans JP'",
)
```

Most users won't call manimpango directly — manim's `Text` mobject
wraps it. You'd call directly when:
- Building a custom text-rendering pipeline (e.g. a slide-show app)
- Pre-rendering glyph caches
- Validating that a font is registered correctly

---

## iOS-specific behaviors

### pycairo-compatibility fallback

manim's `Text` rendering normally takes Pango's native PangoCairo
output and parses it. On iOS that path occasionally produces SVG that
manim's svgelements parser silently drops (anti-aliasing artefacts,
fill-rule mismatches). The bundled manimpango ships a **pure-pycairo
fallback path** that builds the SVG by hand — flat `<path>` elements
with explicit `fill-rule="nonzero"`, `fill-opacity="1"`, and
`viewBox` attributes — bypassing the manimpango → svgelements
problem.

The fallback is selected automatically on iOS via:

```
[manimpango] Pango: pycairo compatibility mode (OFFLINAI_FORCE_PYCAIRO=1)
```

To force the native Pango path:
```bash
export OFFLINAI_FORCE_PYCAIRO=0
```

…you'll see the difference if your `Text("...")` shapes come out
invisible or at the wrong scale.

### Font registration timing

manimpango caches the fontconfig results aggressively. You MUST call
`register_font(...)` BEFORE the first `text2svg` / Text-mobject
construction, or the new font won't be visible until the process
restarts:

```python
# WRONG — second register_font is invisible
import manimpango
manim.Text("hello")              # caches "no fonts" or whatever was around
manimpango.register_font("/path/font.ttf")
manim.Text("hello", font="MyFont")  # → falls back to default; warning emitted

# RIGHT
import manimpango
manimpango.register_font("/path/font.ttf")
import manim
manim.Text("hello", font="MyFont")  # works
```

The host app's Python startup script handles this for KaTeX_Main +
NotoSansJP automatically (see [cairographics.md](cairographics.md#font-setup-on-ios)).

### Empty fontconfig

```python
print(manimpango.list_fonts())     # → []  on a fresh launch
```

This is normal — fontconfig hasn't scanned anything yet. The host
app's Python init scans `~/Documents/fonts/` and the bundled KaTeX
font directory, then re-runs `list_fonts()` to populate the cache.
After that you'll see the registered families.

---

## API surface (the parts manim uses)

| Function | What it does |
|---|---|
| `text2svg(settings, text, lang_str, file_name, style_str)` | Layout + shape `text`, save as SVG to `file_name` |
| `list_fonts()` | List installed font families (after fontconfig scan) |
| `register_font(path)` | Register a `.ttf` / `.otf` file with fontconfig |
| `unregister_font(path)` | Reverse |
| `TextSetting` | A namedtuple-shaped struct: start/end/font/slant/weight/font_size/line_height |
| `Slant.NORMAL / OBLIQUE / ITALIC` | Font slant enums |
| `Weight.THIN / LIGHT / NORMAL / BOLD / BLACK` | Font weight enums |

For the full Pango API surface (paragraphs, alignments, hyphenation,
…) you'd need to use Pango's C API directly via `cffi` — manimpango
doesn't expose that level.

---

## Limitations

- **No interactive layout adjustment.** Once `text2svg` runs, the
  SVG is final — you can't reposition individual glyphs without
  re-running the layout.
- **Font fallback only via fontconfig.** If a glyph isn't in the
  primary font, fontconfig's `<alias>` chain decides what to use.
  See `cairographics.md` for the iOS fonts.conf setup.
- **No bitmap font support.** Apple's emoji font, CJK bitmap fonts,
  etc. — only outline (TrueType / OpenType / Type1 / CFF) fonts work.
- **Empty `text=""`** — silently produces an empty SVG; manim drops
  this. Validate text isn't empty before calling.

---

## Build provenance

manimpango 0.6.1 — Cython bindings cross-compiled with:
- Cython 3.0+
- Pango 1.56.5, HarfBuzz 11.4.0, FreeType 2.13.3, FriBidi (all bundled
  in CairoGraphics/)
- iOS arm64 toolchain (`clang -arch arm64 -isysroot <iPhoneOS.sdk>`)
- ABI tag: `cpython-314-iphoneos`

---

## See also

- [docs/cairographics.md](cairographics.md) — Pango + HarfBuzz +
  FreeType + GLib stack
- [docs/manim.md](manim.md) — uses manimpango for `Text` mobjects
- [docs/manim-deps.md](manim-deps.md) — pathops, mapbox_earcut,
  isosurfaces (other manim deps)
