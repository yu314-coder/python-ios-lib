# manimpango — Cython Pango bindings for manim

**Version:** 0.6.1
**Type:** Native iOS arm64 Cython binding to Pango + HarfBuzz (3 `.so` files, ~27 MB total)
**SPM target:** `ManimPango` (links into `CairoGraphics` for Pango/HarfBuzz/FreeType/GLib)
**Total submodules:** 4 Python + 3 compiled extensions

Cython bindings to [Pango](https://pango.gnome.org/) (text layout) +
[HarfBuzz](https://harfbuzz.github.io/) (text shaping). Used by
manim's `Text(...)` mobject to lay out and shape multi-script text
(English + CJK + Arabic + Indic). Without it, manim can only render
LaTeX math; with it, plain `Text("Hello 你好 مرحبا")` works — when
the native path is enabled.

---

## Modules

### Compiled extensions

| File | Size | Purpose |
|---|---|---|
| `manimpango/cmanimpango.cpython-314-iphoneos.so` | 10 MB | The main Cython binding — `text2svg`, Pango layout, MarkupUtils |
| `manimpango/_register_font.cpython-314-iphoneos.so` | 9.4 MB | Font registration via FreeType / fontconfig |
| `manimpango/enums.cpython-314-iphoneos.so` | 7.7 MB | Pango enum constants — `Slant`, `Weight`, `Variant`, `Stretch`, `Style`, `Alignment` |

### Python modules

| Module | What it does |
|---|---|
| `manimpango.__init__` | Public API; **iOS-specific** native-vs-pycairo selector (see below) |
| `manimpango._version` | `__version__ = "0.6.1"` |
| `manimpango.register_font` | Pure-Python wrapper around `_register_font.register_font_with_freetype` |
| `manimpango.utils` | Helpers — argument-validation, fontconfig probes |

### Cython `.pxd` declaration headers (link-time only)

| Header | Maps to |
|---|---|
| `cmanimpango.pxd` | libpango function declarations |
| `_register_font.pxd` | fontconfig + FreeType declarations |
| `cairo.pxd` | pycairo PyObject declarations (for handoff to Pango) |
| `pango.pxd` | Pango function prototypes |
| `glib.pxd` | GLib types referenced by Pango |

The Pango / HarfBuzz / FreeType / GLib / libffi static archives that
these `.so` files link against live in `Sources/CairoGraphics/` — see
[cairographics.md](cairographics.md).

---

## Quick start

```python
import manimpango

# List installed font families (whatever fontconfig found)
fams = manimpango.list_fonts()
print(fams)
# → ['KaTeX_Main', 'Noto Sans JP', ...]  (depends on what app pre-registered)

# Register a font from disk so Pango can find it by family name
manimpango.register_font("/path/Documents/fonts/MyFont.ttf")

# Render text to SVG
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
wraps it. Direct usage cases:
- Building a custom text-rendering pipeline (e.g. a slide-show app)
- Pre-rendering glyph caches
- Validating that a font is registered correctly

---

## API surface (the parts manim uses)

| Function | What it does |
|---|---|
| `text2svg(settings, text, lang_str, file_name, style_str)` | Layout + shape `text`, save SVG to `file_name` |
| `list_fonts()` | List installed font families (after fontconfig scan) |
| `register_font(path)` | Register a `.ttf` / `.otf` file with fontconfig |
| `unregister_font(path)` | Reverse |
| `MarkupUtils.validate(markup)` | Check Pango-markup string validity |
| `TextSetting` | A namedtuple-shaped struct: `start/end/font/slant/weight/font_size/line_height` |
| `Slant.NORMAL` / `OBLIQUE` / `ITALIC` | Font slant enums |
| `Weight.THIN` / `LIGHT` / `NORMAL` / `BOLD` / `BLACK` | Font weight enums |
| `Variant.NORMAL` / `SMALL_CAPS` / `ALL_SMALL_CAPS` / … | Pango variant enums |
| `Stretch.ULTRA_CONDENSED` / `EXPANDED` / … | Pango stretch enums |
| `Style.NORMAL` / `OBLIQUE` / `ITALIC` | Pango style enums |
| `Alignment.LEFT` / `CENTER` / `RIGHT` | Paragraph alignment |

For the full Pango API surface (paragraphs, alignments, hyphenation,
…) you'd need to use Pango's C API directly via `cffi` — manimpango
doesn't expose that level.

---

## iOS-specific behaviors

### Native Pango vs pycairo-compat fallback

`manimpango/__init__.py` selects between **two rendering backends**
on iOS based on `OFFLINAI_FORCE_PYCAIRO`:

| Path | When | Multi-font fallback | CJK / RTL |
|---|---|---|---|
| **Native Pango** (`OFFLINAI_FORCE_PYCAIRO=0`) | Only when fontconfig is fully set up (host app's Swift bootstrap) | Yes — Pango picks first font with matching glyph | Works (CJK, Arabic, Indic) |
| **pycairo fallback** (default, `OFFLINAI_FORCE_PYCAIRO=1`) | REPL imports, no fontconfig, or after Pango crash | No — Cairo "toy font" API only, no FreeType backend | Basic Latin only; CJK characters invisible |

**Why default to pycairo:** native Pango SIGSEGVs at first layout if
fontconfig can't resolve the default `"Times 9.999"` family. The Swift
manim bootstrap (`PythonRuntime.swift` ~line 1081) writes a runtime
`fonts.conf` with `serif/Times → KaTeX_Main` aliases and sets
`FONTCONFIG_FILE` BEFORE importing manim. REPL contexts skip that
bootstrap, so they need pycairo or they'd crash on first text render.

When the pycairo path is selected, you'll see:
```
[manimpango] Pango: pycairo compatibility mode (OFFLINAI_FORCE_PYCAIRO=1)
```

To force the native path (after FONTCONFIG_FILE is in env):
```bash
export OFFLINAI_FORCE_PYCAIRO=0
```

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

The host app's Python startup script handles this for `KaTeX_Main` +
`NotoSansJP` automatically (see [cairographics.md](cairographics.md#font-setup-on-ios)).

### Empty fontconfig

```python
print(manimpango.list_fonts())     # → []  on a fresh launch
```

This is normal — fontconfig hasn't scanned anything yet. The host
app's Python init scans `~/Documents/fonts/` and the bundled KaTeX
font directory, then re-runs `list_fonts()` to populate the cache.
After that you'll see the registered families.

### Markup validation

`MarkupUtils.validate(markup)` returns `True` for valid Pango markup
(e.g. `<b>bold</b> and <i>italic</i>`). On iOS it works in both
backends since it's pure parser code — no font lookup involved.

---

## Limitations

- **No interactive layout adjustment.** Once `text2svg` runs, the
  SVG is final — you can't reposition individual glyphs without
  re-running the layout.
- **Font fallback only via fontconfig.** If a glyph isn't in the
  primary font, fontconfig's `<alias>` chain decides what to use.
  See `cairographics.md` for the iOS `fonts.conf` setup.
- **CJK in pycairo mode is invisible.** Workaround: switch to native
  Pango if your fontconfig is bootstrapped, OR pre-render CJK strings
  via Pillow's `ImageDraw.text` + traced paths.
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

- [cairographics.md](cairographics.md) — Pango + HarfBuzz + FreeType + GLib stack
- [manim.md](manim.md) — uses manimpango for `Text` mobjects
- [manim-deps.md](manim-deps.md) — pathops, mapbox_earcut, isosurfaces (other manim deps)
