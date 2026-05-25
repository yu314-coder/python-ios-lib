# offlinai_latex — Python → Swift LaTeX bridge

**Version:** 1.0.1 (`__version__`) — `offlinai-latex` PyPI name
**Type:** Pure Python wrapper around the host app's `LaTeXEngine.swift`
**SPM target:** Bundled in the Python framework (host-app glue)
**File size:** 1,295 lines
**Backends:** SwiftMath (native math glyphs) · BusyTeX WASM (xelatex + CJK) · pdftex C library (1.40.20) · Cairo text-path fallback

Bridges Python LaTeX requests to the host app's pdftex / SwiftMath /
BusyTeX rendering pipeline. Used by manim's `MathTex` / `Tex` mobjects
under the hood, and called directly by the `pdflatex` / `latex` / `tex`
/ `pdftex` / `xelatex` builtins in [offlinai_shell](offlinai-shell.md).

## Module structure

| File | What it does |
|---|---|
| `offlinai_latex/__init__.py` | Single module — `tex_to_svg()`, `compile_tex()`, `_autowrap_math_in_text()` preprocessor, BusyTeX dispatch, Cairo fallback, SVG cache |

## Public API

| Symbol | Purpose |
|---|---|
| `offlinai_latex.tex_to_svg(expression, svg_path=None, tex_template_body=None) -> Path` | Render a single LaTeX expression to SVG. Auto-caches by SHA-256 hash so manim re-renders return the same file |
| `offlinai_latex.compile_tex(tex_source, output_dir=None, engine="pdftex")` | Compile a full `.tex` file via pdftex (one-shot per app session — see notes) |
| `offlinai_latex.__version__` | `"1.0.1"` |

## Rendering pipeline

```
your script
   ↓ tex_to_svg(...)
offlinai_latex
   ├─ cache hit? → return cached SVG (validates <path> or <image> presence)
   ├─ has CJK in \text{} OR uses \underbrace / \boxed / \cancel / \xrightarrow
   │  / multi-line environments?
   │       ↓ yes
   │  BusyTeX WASM (real xelatex + xeCJK + ctex) → PDF → high-DPI PNG → SVG with <image>
   │       ↓ fail
   │  log file excerpted, fall through to next backend
   └─ otherwise
       ├─ SwiftMath (native iOS, fastest, Latin Modern math glyphs only)
       ├─ pdftex via ctypes  ← disabled by default on iOS (see kill-switch)
       └─ Cairo text-path glyphs (always works, fastest fallback)
   ↓ writes SVG to $TMPDIR/tex_v7_<hash>.svg
return svg_path
```

## How it routes

```
your script
   ↓ tex_to_svg(...)
offlinai_latex
   ↓ writes request to $TMPDIR/latex_signals/compile_math_request.txt
LaTeXEngine.swift (host app)
   ├─ math-mode → SwiftMath (native, fast, no shell-out)
   ├─ doc-mode  → pdftex.xcframework + texmf
   └─ CJK / fontspec → BusyTeX WASM (xelatex with NotoSansJP)
   ↓ writes PDF / SVG / PNG to tmp dir
offlinai_latex returns the path
```

## Backends in detail

### 1. SwiftMath (preferred for pure math)

Native iOS port of iosMath. Real Computer Modern math fonts with
dvisvgm-quality glyph paths. Limited to Latin Modern math — anything
outside that (CJK, AMS extensions like `\underbrace`, color math,
`\boxed`) emits a single `<rect>` placeholder which renders as an
empty box in the manim video. **`offlinai_latex` detects these macros
and routes to BusyTeX instead** to avoid the empty-box symptom.

### 2. BusyTeX WASM (real xelatex)

Full TeX Live 2023 (pdftex 1.40.25 + xetex) compiled to WASM and run
inside the iOS app. Triggered when the expression contains:

- CJK characters in `\text{...}` (Unicode blocks 0x3000–0x9FFF, 0xAC00–0xD7AF, 0xF900–0xFAFF, 0xFF00–0xFFEF)
- Macros SwiftMath can't render: `\underbrace`, `\overbrace`, `\underline`, `\overline`, `\boxed`, `\cancel`, `\xrightarrow`, `\xleftarrow`, `\overrightarrow`, `\overleftarrow`, `\tag`
- Multi-line environments: `cases`, `align`, `aligned`, `matrix`, `pmatrix`, `bmatrix`, `vmatrix`, `smallmatrix`, `gathered`, `split`

Set `OFFLINAI_LATEX_FORCE_BUSYTEX=1` to force BusyTeX even when the
expression doesn't trigger auto-routing. `OFFLINAI_LATEX_DISABLE_BUSYTEX=1`
opts out entirely (falls straight to SwiftMath / Cairo).

Before handing to BusyTeX, the bridge:

- Strips manim's `\special{dvisvgm:raw <g id='unique000'>}` markers — they're a hint for the desktop dvisvgm driver, and xelatex parses the HTML `<` / `>` inside `\special{...}` and dies with status 1
- Runs `_autowrap_math_in_text()` to wrap math-only commands appearing inside `\text{...}` in `$...$` (see below)

### 3. pdftex via ctypes (disabled by default)

The bundled `pdftex.xcframework` is holzschu/lib-tex v1.40.20 from 2019.
Calling `dllpdftexmain` crashes with `EXC_BAD_ACCESS @ 0x68`
([holzschu/lib-tex#1](https://github.com/holzschu/lib-tex/issues/1))
because modern `latex.ltx` + `expl3` use pdftex primitives added after
1.40.20. Neither pthread isolation nor ini-mode wrappers fix this.

Until the bundled xcframework is rebuilt from current lib-tex master, the
C library is **refused at the kill-switch**. Set
`OFFLINAI_LATEX_FORCE_NATIVE=1` to override for debugging.

`compile_tex()` itself also enforces a one-shot-per-session rule via
`_pdftex_called_this_session`: pdftex's static C state corrupts after
one invocation, so a second call would crash the app. Users must
restart between full-document compiles.

### 4. Cairo text-path fallback (always works)

Renders LaTeX → Unicode (Greek letters, common operators, `\frac{a}{b}` → `(a)/(b)`, `\sqrt{x}` → `√(x)`) and then uses pycairo's `text_path()` to extract glyph outlines as SVG `<path>` elements. Three render styles via `OFFLINAI_LATEX_GLYPH_STYLE`:

| Style | What |
|---|---|
| `outline` (default) | Full Cairo glyph outlines via `copy_path()` — 50–200 VMobject points per character, prettiest |
| `coarse` | `copy_path_flat()` with high tolerance — ~5× lighter, line-segment glyphs |
| `rect` | One bounding-box rectangle per character — ~16 points, math shows as blocks |
| `empty` | Zero geometry, math invisible |

Each character gets its own `<g id="uniqueNNN">` wrapper — what manim's
`MathTex` parser looks for via dvisvgm's `\special{...}` markers.

## Auto-wrap math in `\text{}`

```latex
\text{對稱性: } |QR| = |RP| = 2\sqrt{2}        ← user wrote
\text{對稱性: $|QR| = |RP| = 2\sqrt{2}$}       ← auto-wrap rewrites
```

amsmath's `\text{...}` is text-mode and does NOT auto-switch back to math
for nested commands. Manim users mixing CJK labels with math (`\underbrace`,
`\boxed`, `\frac`, accents, big operators, math styles) would otherwise hit
`! Missing $ inserted`. The walker at line 514 scans every `\text{}` block
with proper brace matching, finds each math command + braced args + any
`_{...}` / `^{...}` tail, and wraps the whole chunk in `$...$`. Recurses
into nested `\text{}` so deeply-nested expressions are fully resolved.
Existing `$...$` regions are detected and left alone.

Coverage: `\underbrace`, `\overbrace`, `\boxed`, `\frac` / `\dfrac` / `\tfrac`, `\binom` / `\dbinom` / `\tbinom`, `\sqrt`, big operators (`\sum`, `\prod`, `\int`, `\oint`, `\iint`, `\iiint`, `\bigcup`, `\bigcap`, etc.), accents (`\hat`, `\bar`, `\vec`, `\tilde`, `\dot`, `\ddot`, `\widehat`, `\widetilde`), `\overline` / `\underline`, math-style (`\mathbb`, `\mathbf`, `\mathcal`, `\mathfrak`, `\mathsf`, `\mathtt`, `\mathit`, `\mathrm`, `\operatorname`).

## SVG cache

Keyed by SHA-256 of the LaTeX source. Cached SVGs are validated for either
a `<path>` (SwiftMath / Cairo output) or `<image>` (BusyTeX → PNG-in-SVG)
element before reuse — stale broken SVGs (single `<rect>` with no glyph
data) caused the "last MathTex shows just dvi" symptom in earlier
versions and now get evicted on read. Cache is in-memory only (`_svg_cache`
dict), but disk paths are deterministic (`$TMPDIR/tex_v7_<hash>.svg`) so
they survive across process invocations.

## Signal-file protocol

All paths under `$TMPDIR/latex_signals/`. Same dir as
[offlinai_ai](offlinai-ai.md) — they don't collide because filenames
differ (compile_*, math_done_*, etc.).

| File | Purpose |
|---|---|
| `compile_math_request.txt` | Math expression for BusyTeX: `<id>\n<svg_path>\nFFFFFF\n<expression>\n` |
| `math_done_<id>.txt` | Two lines: status + message. Swift writes when BusyTeX done |
| `compile_request.txt` | Full-document path for Swift's pdf→SVG conversion: `<input_path>\n<svg_path>\n` |
| `<svg_path>.latex.log` | xelatex log Swift writes alongside the SVG on compile failure |

## Public API examples

```python
from offlinai_latex import tex_to_svg

# Render math LaTeX to an SVG file
svg_path = tex_to_svg(r"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}")
print(svg_path)   # /private/var/.../tmp/tex_v7_<hash>.svg

# CJK expression auto-routes through BusyTeX
svg_path = tex_to_svg(r"\text{中文 = } |QR|")

# Full document via pdftex (one shot per app session — see notes)
from offlinai_latex import compile_tex
pdf_path = compile_tex(r"""
\documentclass{article}
\usepackage{amsmath}
\begin{document}
\section{Hello}
$E = mc^2$
\end{document}
""")
```

## Environment flags

| Variable | Effect |
|---|---|
| `OFFLINAI_LATEX_USE_PDFTEX=1` | Try pdftex via ctypes (off by default — pdftex crashes after one call). Use only for one-off previews |
| `OFFLINAI_LATEX_FORCE_NATIVE=1` | Override the kill-switch that refuses to call lib-tex v1.40.20 |
| `OFFLINAI_LATEX_FORCE_BUSYTEX=1` | Always route through BusyTeX, even for trivial math |
| `OFFLINAI_LATEX_DISABLE_BUSYTEX=1` | Skip BusyTeX entirely (SwiftMath → Cairo path only) |
| `OFFLINAI_LATEX_GLYPH_STYLE=outline|coarse|rect|empty` | Cairo fallback glyph-extraction mode |

## iOS-specific notes

- **pdftex is not re-entrant.** `_pdftex_called_this_session` guards against the second call that would crash the app — users must restart between `compile_tex()` invocations even when the first one succeeded
- **No `subprocess.run` to shell out to pdflatex** — the entire pipeline is in-process: ctypes for pdftex, Swift file-IPC for SwiftMath / BusyTeX, pycairo for the fallback
- **Threading lock** (`_pdftex_lock`) serializes pdftex calls within a single session, reducing crash risk when multiple manim renders fire concurrently
- **Cache dir is `$TMPDIR`** — iOS may purge between launches, but that's fine because the cache key is content-hash and the next render regenerates

## See also

- [offlinai-shell.md](offlinai-shell.md) — what wraps `pdflatex` / `xelatex` / `manim` builtins
- [latex-engine.md](latex-engine.md) — pdftex + texmf details
- [manim.md](manim.md) — `MathTex` / `Tex` use this bridge
- [cairographics.md](cairographics.md) — what the Cairo fallback uses
- The host app's `LaTeXEngine.swift` for the Swift-side bridges
