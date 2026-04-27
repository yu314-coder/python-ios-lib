# LaTeXEngine

> **Engine:** pdftex (TeX Live) — pre-built XCFrameworks  | **Texmf:** ~33 MB Latin Modern + amsmath + hyperref + expl3 + firstaid + graphics-def + hyphenation + stringenc + unicode-data  | **Type:** In-process LaTeX compilation, no subprocess  | **Status:** Working — `pdflatex foo.tex → foo.pdf` end-to-end

In-process LaTeX compilation for iOS. Compiles `.tex` source to PDF
inside the host app — no `fork`/`exec` (which iOS forbids), no
external `pdflatex` binary, no network round-trip. Powered by three
xcframeworks plus a curated TeX Live texmf tree.

```
   ┌────────────────────┐
   │ Your Swift / Python│
   │  app code          │
   └─────────┬──────────┘
             │  TeX source string
             ▼
   ┌────────────────────┐         pdftex.framework        ┌────────┐
   │ ios_system bridge  │  ────►  kpathsea (file lookup)  │  PDF   │
   │ (POSIX shim)       │         pdftex (typesetter)     │ bytes  │
   └────────────────────┘         texmf/ (font + macros)  └────────┘
```

---

## When to add this target

Two main use cases:

1. **Math rendering** — render LaTeX math snippets (`E = mc^2`,
   `\int_0^\infty e^{-x^2} dx`, …) inside your app, either as a
   PDF page or rasterised to a PNG / SVG.
2. **Document compilation** — let users author full `.tex` documents
   (articles, theses, slides) in your app and produce a PDF on-device
   with no internet.

```swift
.dependencies = [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", from: "1.0.0"),
],
.target(name: "MyApp", dependencies: [
    .product(name: "LaTeXEngine", package: "python-ios-lib"),
])
```

`LaTeXEngine` depends on `CairoGraphics` (for the texmf font
rasterisation pipeline) — SPM resolves that automatically.

---

## What's bundled

```
Sources/LaTeXEngine/latex/
├── ios_system.xcframework      ← POSIX shim providing fork-free CLI surface
├── kpathsea.xcframework        ← TeX Live's file-lookup library
├── pdftex.xcframework          ← The actual pdftex compiler
└── texmf/                      ← 33 MB curated texmf tree
    ├── fonts/                  ← Latin Modern Type 1 (.pfb), .tfm metrics
    │   ├── type1/public/lm/    ← 92 .pfb files
    │   └── tfm/public/lm/      ← 596 .tfm files
    ├── tex/latex/              ← .sty / .cls macro packages
    │   ├── base/               ← article.cls, etc.
    │   ├── amsmath/            ← AMS-math
    │   ├── amsfonts/
    │   ├── tools/              ← multicol, xspace, …
    │   ├── hyperref/           ← clickable links + bookmarks
    │   └── lm/                 ← Latin Modern declarations
    ├── tex/generic/
    │   ├── expl3/              ← expl3 + l3kernel (1.3 MB)
    │   ├── firstaid/           ← compatibility patches
    │   ├── graphics-def/
    │   ├── stringenc/
    │   └── unicode-data/
    └── tex/plain/
        └── hyphenation/        ← Knuth's English + lots of others
```

The texmf tree is a curated subset of TeX Live full — enough to run
modern `\documentclass{article}` + `amsmath` + `hyperref` end-to-end
without "missing package" errors. Total static-archive footprint
of the three xcframeworks: ~12 MB.

---

## Pure-Swift usage

```swift
import LaTeXEngine

// The Swift surface is intentionally tiny — it's just the resource
// bundle accessor. Drive pdftex via the bundled CLI shim.
let bundlePath = PythonIOSLib.resourcePath
print("texmf at:", bundlePath ?? "(unavailable)")
```

Real integrations call into pdftex via the C API, with the
`TEXMFCNF` / `TEXMFROOT` environment variables pointing at the
bundled `texmf/` directory. See OfflinAi's
`CodeBench/LaTeXEngine.swift` for a reference implementation
that:

1. Sets up the texmf paths on first launch
2. Generates the `.fmt` (format) file from `latex.ltx` via the
   `pdftex --ini` mode (no pre-built format needed)
3. Streams `.tex` strings into a temp file
4. Calls `pdftex_main(argc, argv)` directly
5. Reads the output `.pdf` from the temp dir

---

## Python usage (via offlinai_latex)

The Manim target ships an `offlinai_latex` Python module that wraps
all of this for you. From the in-app Python shell:

```python
from offlinai_latex import tex_to_svg

svg = tex_to_svg(r"E = mc^2")
print(f"SVG written to: {svg}")

# Math mode with display style
svg2 = tex_to_svg(r"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}")
```

`tex_to_svg` runs the full pipeline:
1. Wraps your LaTeX in a minimal preamble (`\documentclass{standalone}`
   + `\usepackage{amsmath, amssymb, mathtools}`)
2. Calls pdftex to produce a 1-page PDF
3. Rasterizes the PDF to SVG via Cairo's PDF→cairo→SVG path
   (or to PNG via Cairo's image surface, used by manim's CJK
   MathTex fallback)
4. Returns the output file path

---

## Manim integration

manim's `MathTex` and `Tex` mobjects route through this pipeline:

```python
from manim import *

class HelloMath(Scene):
    def construct(self):
        eq = MathTex(r"E = mc^2", font_size=72)
        self.play(Write(eq))
        self.wait()
```

When you `self.play(Write(eq))`, manim:
1. Calls `offlinai_latex.tex_to_svg(r"E = mc^2")`
2. pdftex compiles → PDF
3. Cairo rasterises → SVG paths
4. manim parses the SVG into VMobject paths
5. Animates the path drawing

For CJK content (`MathTex(r"\text{你好} = ...")`), the same pipeline
runs but with xelatex-style font fallback — see `cairographics.md`
for the fontconfig setup.

---

## What's INCLUDED in texmf

This is enough to compile most standard documents:

- **`article` / `report` / `book` / `letter`** classes
- **`amsmath`** — display math, alignments, matrices, theorems
- **`amssymb`** — extended math symbols (`\mathbb`, `\mathfrak`, …)
- **`amsthm`** — theorem environments
- **`mathtools`** — extends amsmath with `\coloneqq`, `\DeclarePairedDelimiter`, etc.
- **`hyperref`** — clickable links, bookmarks, PDF metadata
- **`graphicx`** — include external images (PDF / PNG)
- **`xcolor`** — full named-color palette
- **`tikz`** — partial — base + arrows + decorations + positioning libraries
- **`expl3` / `l3kernel`** — needed by modern packages
- **`firstaid`** — compatibility shims for older code
- **Latin Modern** font family — `lmroman10-regular`, `lmsans10-regular`,
  `lmmono10-regular`, italic / bold / bolditalic / smallcaps variants
- **English hyphenation** + many other languages

## What's NOT included

- **xelatex / lualatex** — only pdftex. Documents using
  `\usepackage{fontspec}` won't compile (no Unicode font loading).
  For CJK / arbitrary Unicode, use the Pango fallback path through
  `offlinai_latex.tex_to_image()` instead.
- **Beamer** — too large to ship; if you need slides, use
  `\documentclass{article}` + `\usepackage{geometry}` + custom layout.
- **Heavy font families** — Computer Modern Type1 (`cm-super`),
  Source Sans, EB Garamond, etc. The lmodern declarations are
  auto-injected so docs don't need cm-super.
- **biber / bibtex8** — only the legacy `bibtex` (8-bit) is
  reachable, and only via the in-process pdftex driver. For modern
  bibliography, pre-compile the `.bbl` outside the app and ship it
  alongside the source.
- **External system tools** — `dvips`, `dvipdfmx`, `epstopdf` are
  not bundled. Stick to PDF output and PDF-native graphics.

---

## Limitations

- **No `\write18` / shell escape.** iOS forbids subprocess; pdftex
  was built with `-shell-escape` permanently disabled.
- **Single document at a time per process.** pdftex's globals
  aren't thread-safe; serialise compilations.
- **Format file regeneration on first launch.** The first
  compilation pre-builds `latex.fmt` (~5 MB) by running
  `pdftex --ini` over `latex.ltx`. Takes 2-3 seconds; cached
  after that.
- **PDF post-processing.** No `qpdf` / `pdftk` for merge / split.
  Consume the raw PDF in your app or convert to images.

---

## Troubleshooting

### `! LaTeX Error: File 'amsmath.sty' not found.`

The texmf tree's path-cache (`ls-R`) hasn't been built. The host
app should run `mktexlsr <texmf>/` once on first launch — the
xcframework includes the `mktexlsr` Lua script. Without it,
kpathsea linear-scans every directory, which is slow but works;
if it fails, the cache wasn't generated AND the directory layout
is wrong.

### `! Undefined control sequence. l.5 \maketitle`

Same root cause — kpathsea didn't find the class file. Verify
`TEXMFROOT` and `TEXMFCNF` are set in the environment before
calling `pdftex_main`.

### `! pdfTeX error: pdflatex: format file 'latex.fmt' not found.`

The `--ini` step didn't run (or failed silently). Look for
`fmtutil` / `pdftex --ini` errors in the host app's NSLog
output. Manually:
```
pdftex --ini --jobname=latex --etex 'pdflatex.ini'
```
should produce `latex.fmt` in the current directory; copy it
into `texmf/web2c/pdftex/`.

### Output PDF is blank

Almost always a missing font. Check the `.log` file (sibling of
the `.pdf` that was supposed to be generated) for
`! Font \LMR/regular/n/10=lmr10 at 10.0pt not loadable: Metric (TFM) file or installed font not found.`
The `.tfm` files for Latin Modern are bundled — if they're
missing, the texmf tree didn't get copied. Check the SPM
`.copy("latex")` build phase ran.

### Compilation hangs

pdftex's interactive prompt is asking for input ("`?`"). Make
sure you call it with `\nonstopmode` injected at the top of the
TeX source, or pass `-interaction=nonstopmode` as a CLI arg.

---

## Build provenance

- pdftex 1.40.25 from TeX Live 2024
- kpathsea built with `--disable-shared --enable-static --enable-ipc`
- ios_system from Nicolas Holzschuch's repo, patched to suppress
  the `.bash_profile` parsing path
- texmf curated by hand from a `texlive-full` install, removing
  unused languages (kept ~50 MB → ~33 MB after pruning)
- All three xcframeworks built with Xcode 16, targeting iOS 17+
