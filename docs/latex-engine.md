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

365 `.sty` / `.cls` files across 17 document classes — enough to compile
the vast majority of real-world documents. Full list in the
**[Bundled package inventory](#bundled-package-inventory)** appendix below.

Highlights by category:

- **Classes**: `article`, `report`, `book`, `letter`, `beamer`, `amsart`,
  `amsbook`, `amsproc`, `proc`, `slides`, `minimal`
- **Math**: `amsmath`, `amssymb`, `amsthm`, `amsbsy`, `amscd`, `amsfonts`,
  `amsopn`, `amstext`, `mathtools`, `bbm`, `amstex`
- **Drawing**: `pgf` + full `tikz` library set (arrows, decorations,
  patterns, plots, shapes, snakes, automata, calendar, …)
- **Slides**: `beamer` + all `beamerbase*` modules + beamer themes
- **Hyperlinks**: `hyperref` + dependencies (`pdfescape`, `kvsetkeys`,
  `hypcap`, `backref`, `refcount`, `letltxmacro`, `atveryend`,
  `atbegshi`, `auxhook`)
- **Layout**: `geometry`, `fancyhdr`, `setspace`, `microtype`,
  `booktabs`, `float`, `listings`, `enumitem`, `caption` / `subcaption`
  / `bicaption` / `ltcaption`, `titlesec`-friendly stack
- **Cross-refs**: `cleveref`, `refcount`, `etoolbox`
- **Graphics**: `graphicx`, `color`, `graphpap`
- **CJK**: `CJK`, `CJKutf8`, `CJKnumb`, `CJKfntef`, `CJKulem`,
  `CJKspace`, `CJKvert`
- **Fonts**: full Latin Modern Type 1 (92 `.pfb` files, 596 `.tfm`
  metrics, italic / bold / bolditalic / smallcaps), `fontenc`,
  `inputenc`, `t1enc`
- **Engine plumbing**: `expl3`, `l3kernel`, `firstaid`,
  `graphics-def`, `pdftexcmds`, `pdfescape`, `etoolbox`, `fp`
- **Hyphenation**: English + many other languages

## What's NOT included

- **xelatex / lualatex** — only pdftex is wired up in this SPM target.
  Documents using `\usepackage{fontspec}` won't compile through
  `LaTeXEngine` (no Unicode font loading). For arbitrary Unicode,
  CodeBench's busytex-WASM path supports xelatex — see
  [docs/offlinai-latex.md](offlinai-latex.md).
- **Computer Modern bitmap fonts** — `cm-super` not shipped; Latin
  Modern (`lmodern`) is auto-substituted via the engine's
  preamble-injection hook so docs requesting cm fonts still compile.
- **biber** — only legacy `bibtex` (8-bit) reachable in-process.
  For modern bibliography, pre-compile the `.bbl` outside the app
  and ship it alongside the source. `backref` is bundled so back-
  references in PDFs still work.
- **`pythontex` / `minted`** — both rely on `\write18` (shell
  escape), which iOS forbids. Use `listings` instead for code
  blocks; it's bundled and produces good syntax-coloured output.
- **External tools** — `dvips`, `dvipdfmx`, `epstopdf`, `latexmk`
  are not bundled. Stick to PDF output and PDF-native graphics.

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

---

## Bundled package inventory

Generated via `find Sources/LaTeXEngine/latex/texmf -name '*.sty' -o -name '*.cls'`.
Total: **365 packages, 17 document classes**.

For each: just `\documentclass{...}` or `\usepackage{...}` and it works
— no `! LaTeX Error: File ... not found`.

### Document classes (17)

| Class | Purpose |
|---|---|
| `article` | Standard short documents (most common) |
| `report` | Multi-chapter reports |
| `book` | Books with parts / chapters / front-matter |
| `letter` | Business letters with `\opening` / `\closing` |
| `beamer` | **Full beamer** for slide decks |
| `proc` | Proceedings articles |
| `slides` | Plain LaTeX slides (legacy) |
| `minimal` | Empty class for testing |
| `amsart`, `amsbook`, `amsproc` | AMS journal/book/proceedings |
| `amsdtx`, `amsldoc` | AMS documentation classes |
| `l3doc`, `ltxguide`, `ltxnews`, `ltxdoc` | LaTeX kernel documentation classes |

### Math + AMS

| Package | What it gives you |
|---|---|
| `amsmath` | `align`, `gather`, `matrix`, `cases`, `\dfrac`, `\substack`, … |
| `amssymb` | `\mathbb{R}`, `\mathfrak`, `\mathcal`, `\hbar`, `\square`, … |
| `amsthm` | `\newtheorem`, `proof` environment, `\qedhere` |
| `amsbsy` | Bold math (`\boldsymbol`, `\pmb`) |
| `amscd` | Commutative diagrams (`CD` environment) |
| `amsfonts` | `\mathbb`, `\mathfrak` base fonts |
| `amsgen`, `amsopn`, `amstext`, `amstex`, `amsbooka`, `amsmidx`, `amsxtra` | AMS support packages |
| `mathtools` | Extends `amsmath` — `\coloneqq`, `\DeclarePairedDelimiter`, mat\* envs |
| `bbm` (+ `bbm-macros`) | `\mathbbm{1}` blackboard-bold double-struck |

### Graphics, color, drawing

| Package | What it gives you |
|---|---|
| `graphics`, `graphicx` | `\includegraphics{file.pdf}` |
| `graphics-def` | Engine-specific driver definitions |
| `color`, `xcolor` (via `graphics-def`) | Named colors, color models |
| `graphpap` | Graph paper backgrounds |
| `pgf` | **Full PGF** — basic drawing primitives |
| `tikz` | **Full TikZ** — high-level drawing language |
| `pgfarrows`, `pgfautomata`, `pgfcalendar` | TikZ libraries (arrow tips, automata, calendar) |
| `pgfbase{image,layers,matrix,patterns,plot,shapes,snakes}` | TikZ base modules |
| `pgfcomp-version-{0-65,1-18}` | PGF version-compatibility shims |
| `pdfescape`, `pdftexcmds` | pdftex string-escape helpers (hyperref dep) |

### Layout, sectioning, page geometry

| Package | What it gives you |
|---|---|
| `geometry` | `\geometry{a4paper, margin=2cm}` |
| `setspace` | `\onehalfspacing`, `\doublespacing` |
| `fancyhdr` | Custom headers/footers (`\fancyhead`, `\fancyfoot`) |
| `fancyheadings` | Legacy precursor (kept for old docs) |
| `microtype` | Character protrusion + font expansion → tighter, better-looking paragraphs |
| `booktabs` | Pro-quality tables: `\toprule`, `\midrule`, `\bottomrule` |
| `float` | Custom float types via `\newfloat`, `[H]` placement |
| `listings` | Source-code listings with language syntax highlighting |
| `enumitem` | Customizable `enumerate` / `itemize` / `description` |
| `caption`, `caption2`, `caption3`, `subcaption`, `bicaption`, `ltcaption` | Float caption customization |
| `nohyperref` | Disable hyperref for one section |

### Hyperlinks, cross-references, bookmarks

| Package | What it gives you |
|---|---|
| `hyperref` | `\href`, `\url`, clickable refs/cites, PDF bookmarks/metadata |
| `cleveref` | `\cref{eq:foo}` → "equation (3)" (auto-types references) |
| `refcount`, `etoolbox`, `letltxmacro` | hyperref deps + general macro plumbing |
| `hypcap` | Anchors at the top of floats, not the caption |
| `backref` | Back-references from bibliography to citing pages |
| `atbegshi`, `atveryend`, `auxhook` | Engine event hooks used by hyperref |

### Bibliography (limited)

Only `bibtex` (8-bit legacy) reachable in-process. Pre-compile `.bbl` for
modern bibliography:
- `backref` for back-refs in PDFs (clickable from bib entry to citing page)
- Native `\bibliography{file}` works if a pre-built `.bbl` is present

### CJK + Unicode

| Package | What it gives you |
|---|---|
| `CJK`, `CJKutf8` | Chinese/Japanese/Korean (Type1 fonts, UTF-8 encoding) |
| `CJKnumb` | CJK numeral conversion |
| `CJKfntef`, `CJKulem` | CJK accent/underline support |
| `CJKspace`, `CJKvert` | CJK line-spacing, vertical writing |
| `MULEenc` | Multi-language encoding |

(For full Unicode beyond CJK Type1, use CodeBench's busytex+xelatex path.)

### Fonts

| What | Detail |
|---|---|
| **Latin Modern Type 1** | 92 `.pfb` font files, 596 `.tfm` metrics |
| Roman | `lmroman10-{regular,italic,bold,bolditalic,slanted,smallcaps,demi}` + 5/6/7/8/9/12/17pt design sizes |
| Sans | `lmsans10-{regular,italic,bold,boldoblique,demicondensed}` + design sizes |
| Mono | `lmmono10-{regular,italic,bold,boldoblique,slanted}` + `lmmonoltcond` |
| Caps | `lmromancaps10`, `lmromandunh10` (demi unslanted) |
| `lmodern.sty` | Selects Latin Modern as the default family |
| `fontenc` (T1) | 8-bit T1 encoding |
| `inputenc` | Reads UTF-8 source |
| `t1enc` | Legacy T1 encoding shim |

### Slides (full beamer)

| Module | What it does |
|---|---|
| `beamer.cls` | The main beamer class |
| `beamerarticle` | Render beamer source as article output |
| `beamerbase{article,auxtemplates,boxes,color,compatibility,decode,font,frame}` | beamer's internal modules — needed for any non-trivial use |
| Beamer themes (Default, Boadilla, AnnArbor, Berkeley, etc.) | Pre-set color + layout themes for slides |

`\documentclass{beamer}` with frames, transitions, overlays, themes — all
working in-process, no internet, no missing-package errors.

### Engine plumbing (not user-facing, but needed)

| Package | Purpose |
|---|---|
| `expl3` / `l3kernel` | Modern LaTeX3 programming layer (~1.3 MB) |
| `firstaid` | Compatibility patches for older / conflicting packages |
| `etoolbox` | General-purpose macro plumbing (used everywhere) |
| `fp` | Fixed-point arithmetic |
| `tools` package set | `multicol`, `xspace`, `array`, `dcolumn`, `tabularx`, `varioref` |
| `array`, `array-2016-10-06` | Extended column types for tables |
| `afterpage` | Defer commands to after current page break |
| `alltt` | Verbatim-like block with active commands |

### Hyphenation

English + many other languages in `tex/plain/hyphenation/`.

### Format compatibility shims

Several packages have date-suffixed copies so older documents that
reference a specific version still work:
- `amsmath-2018-12-01.sty`
- `array-2016-10-06.sty`
- `graphics-2017-06-25.sty`

### Looking up whether a specific package is bundled

From the in-app Python shell:

```python
import os, glob
texmf = "/path/to/texmf"   # see LaTeXEngine.shared.texmfPath
hits = glob.glob(f"{texmf}/**/PACKAGENAME.sty", recursive=True)
print(hits or "not bundled")
```

Or from the CodeBench terminal:

```bash
find /path/to/texmf -name "PACKAGENAME.sty"
```

If the search returns nothing AND you can't easily rewrite the document
to avoid it, two options:
1. **Drop the missing `.sty` into your document's directory** —
   kpathsea searches the source directory first.
2. **For CodeBench specifically**, the busytex-WASM path has a much
   larger TeX Live overlay (`offlinai-texmf` adds ~23 MB on top of
   ubuntu-texlive-{latex-base,latex-recommended,fonts-recommended,
   latex-extra,science}). Switch via the
   `OFFLINAI_LATEX_ENGINE=busytex` env var.
