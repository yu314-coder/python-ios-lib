# matplotlib — REAL matplotlib 3.11 (iOS arm64) + plotly interactive showcase

> **Version:** 3.11.0 (real C build) · **C extensions:** `ft2font` (vendored FreeType 2.14.3), `_path`, `_image`, `_tri`, `_qhull`, `_backend_agg`, `_c_internal_utils`, `_tkagg` · **deps:** contourpy 1.3.3, kiwisolver 1.5.0 (both native arm64) + cycler / pyparsing / python-dateutil / packaging / fonttools · **Location:** `matplotlib/`, `mpl_toolkits/`, `pylab.py` · **Recipe:** `matplotlib_ios/build_matplotlib_ios.sh`

The bundled `import matplotlib` is the **real** matplotlib — the identical
3.11.0 source cross-compiled for iOS arm64, C extensions and all. This is not
an emulation layer: `matplotlib.__version__ == "3.11.0"`, `matplotlib.ft2font`
reports the real FreeType version, and every artist renders through the real
Agg/SVG/PDF backends. Anything from an upstream tutorial, a notebook, or
StackOverflow runs unmodified.

> The legacy pure-Python **plotly-backend shim** (the previous `3.9.0-offlinai`)
> is preserved and selectable per run — see [the appendix](#appendix--legacy-plotly-backend-shim). Real matplotlib is the default.

---

## Quick start

```python
import numpy as np
import matplotlib.pyplot as plt

x = np.linspace(0, 4 * np.pi, 400)
fig, ax = plt.subplots(figsize=(7, 4))
ax.plot(x, np.sin(x), label="sin")
ax.plot(x, np.cos(x), "--", label="cos")
ax.fill_between(x, np.sin(x), alpha=0.15)
ax.set_title(r"$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$")  # real mathtext
ax.legend(); ax.grid(True)
plt.show()   # → interactive in the CodeBench preview (see below)

fig.savefig("out.pdf")   # real vector PDF — no kaleido, no shim
```

## Verified on device (M-series, Designed-for-iPad)

| Feature | Status |
|---|---|
| 2-D lines / scatter / bars / legend / grid | ✅ |
| **mathtext** (`$…$` TeX-style) via the internal renderer + bundled fonts | ✅ |
| `contourf` + colorbar (contourpy) | ✅ |
| **real mplot3d** `plot_surface` / `plot_wireframe` / 3-D scatter | ✅ |
| 28 style sheets + full `rcParams` | ✅ |
| **SVG + PDF** vector output | ✅ |
| pandas `Series.plot()` / `DataFrame.plot()` with date axes | ✅ |
| **GIF animation** (`FuncAnimation` + `PillowWriter`) | ✅ |
| `savefig` PNG (Agg) / SVG / PDF — every format, natively | ✅ |

---

## How figures display in CodeBench

`plt.show()` is hooked (in `sitecustomize`) so a figure lands in the preview
pane with real interactivity. The figure type picks the renderer:

| Figure | Renderer | Interaction |
|---|---|---|
| **2-D** | converted to plotly (`codebench_mpl2plotly`) | hover = **data values**, wheel/pinch **zoom**, drag **pan**, click legend to **toggle** series |
| **3-D** | plotly WebGL (`go.Surface` / `go.Scatter3d`) | drag = **orbit**, tap = **x/y/z values**. Axis text lives in the SVG layer (a title + a `x: [min…max] · …` ranges line) because iOS WebKit cannot rasterize plotly's WebGL glyph atlas — see the note below |
| **animation** | `Animation.to_jshtml()` player | **play / pause / step / loop** + frame slider (self-contained HTML, always plays) |
| **2-D that won't convert** | crisp-SVG viewer (`codebench_mpl_viewer`) | exact mpl vector + zoom/pan + nearest-point tooltip |
| **last resort** | WebAgg live canvas → static PNG | matplotlib's own pan/zoom toolbar |

A PNG snapshot is **always** written to `ToolOutputs/` as the static record,
regardless of which renderer runs.

**Conversion coverage** (host-verified, 17/17): lines, scatter, bar, hist,
`fill_between`, `imshow` (grayscale + RGB), `contour`/`contourf` (exact grids
via capture-at-call), `pcolormesh`, `pie`, log & date axes, subplots, and 3-D
surface / wireframe / scatter / line. Grids whose source arrays can't be
recovered from the artist tree are captured at call time, so the plotly trace
is exact rather than approximate.

### Display modes

| `CODEBENCH_MPL_INTERACTIVE` | Behaviour |
|---|---|
| `1` / `plotly` *(default)* | plotly showcase (hover, zoom, orbit) |
| `webagg` | matplotlib's own WebAgg server + navigation toolbar (raster, live) |
| `0` | static PNG only |

Set `CODEBENCH_MPL_BACKEND=plotly` to swap the whole `matplotlib` package for
the [legacy shim](#appendix--legacy-plotly-backend-shim) instead.

### Why 3-D axis labels live in the SVG layer

The app's WKWebView runs the **iOS** WebKit stack, which fails to rasterize
plotly's WebGL glyph atlas — 3-D tick labels and axis titles come out as empty
"tofu" boxes (the *same* HTML renders perfectly in macOS Safari). So 3-D scenes
are emitted with **no** WebGL text: ticks hidden, axis titles at a sub-pixel
font, and the readable information moved to the SVG layer (a centered title
plus a `x: [-2 … 2] · y: [-2 … 2] · z: [-1 … 1]` ranges line) with a rich
`hovertemplate` so a **tap** still shows the exact `x/y/z` under the finger.
Grid lines (pure geometry) are kept for depth.

### `savefig` — every format, native

`plt.savefig()` / `fig.savefig()` is untouched real matplotlib and is
completely independent of the display pipeline above:

| Format | Backend | Notes |
|---|---|---|
| `.png` | Agg | **no kaleido** — the real raster backend |
| `.svg` | SVG | true vector |
| `.pdf` | PDF | true vector, embeds subsetted fonts |
| `.jpg` / `.tif` / `.webp` | Agg + Pillow | via the bundled Pillow |
| `.gif` (animation) | `PillowWriter` | frame-by-frame GIF |

---

## API reference (real matplotlib — full public interface)

This is the genuine library, so its entire public API is present. The tables
below are a quick cheat-sheet of the most-used surface; anything not listed
still works exactly as upstream.

### `matplotlib.pyplot` — primary interface

**2-D plot types:** `plot`, `scatter`, `bar`, `barh`, `hist`, `hist2d`, `pie`,
`fill_between`, `fill_betweenx`, `stem`, `step`, `errorbar`, `boxplot`,
`violinplot`, `imshow`, `matshow`, `pcolormesh`, `pcolor`, `contour`,
`contourf`, `polar`, `stackplot`, `hexbin`, `hlines`, `vlines`, `quiver`,
`streamplot`, `tricontour`, `tricontourf`, `tripcolor`, `spy`, `eventplot`,
`broken_barh`.

**3-D plot types** (`projection='3d'`): `plot_surface`, `plot_wireframe`,
`scatter` / `scatter3D`, `plot` / `plot3D`, `bar3d`, `plot_trisurf`,
`contour3D`, `contourf3D`, `voxels`, `quiver` (3-D).

**Figure & axes:** `figure`, `subplots`, `subplot`, `subplot2grid`,
`subplot_mosaic`, `axes`, `gca`, `gcf`, `cla`, `clf`, `close`, `twinx`,
`twiny`, `add_subplot(projection=…)`.

**Annotations & text:** `title`, `suptitle`, `xlabel`, `ylabel`, `text`,
`annotate`, `figtext`; OO forms `ax.set_title/set_xlabel/set_ylabel`.

**Axis config:** `xlim`, `ylim`, `xscale`, `yscale` (`linear`/`log`/`symlog`/
`logit`), `xticks`, `yticks`, `grid`, `legend`, `colorbar`, `axis`,
`tight_layout`, `margins`, `axhline`, `axvline`, `axhspan`, `axvspan`,
`minorticks_on/off`, `ax.invert_xaxis/yaxis`, `ax.set_aspect`.

**Output:** `show()` (→ interactive preview, see above), `savefig(...)` (every
format above, natively).

### Other modules (all real)

| Module | What it provides |
|---|---|
| `matplotlib.figure` | `Figure`, `add_subplot`, `add_axes`, `suptitle`, `savefig`, `subplots_adjust`, `set_size_inches` |
| `matplotlib.axes` | full OO `Axes` API — every `plt.*` plot delegates here |
| `matplotlib.cm` / `matplotlib.colormaps` | **all** built-in colormaps (sequential / perceptual / diverging / cyclic / qualitative), callable + registry |
| `matplotlib.colors` | `to_rgba/to_hex/to_rgb`, `Normalize`, `LogNorm`, `SymLogNorm`, `PowerNorm`, `BoundaryNorm`, `TwoSlopeNorm`, `ListedColormap`, `LinearSegmentedColormap`, `CSS4_COLORS`, `TABLEAU_COLORS`, `XKCD_COLORS` |
| `matplotlib.ticker` | locators (`MaxNLocator`, `MultipleLocator`, `LogLocator`, …) + formatters (`ScalarFormatter`, `FuncFormatter`, `PercentFormatter`, `EngFormatter`, `LogFormatterMathtext`, …) |
| `matplotlib.patches` | `Rectangle`, `Circle`, `Ellipse`, `Polygon`, `Wedge`, `Arc`, `FancyArrowPatch`, `PathPatch`, `ConnectionPatch`, `BoxStyle`, `ArrowStyle` |
| `matplotlib.lines` | `Line2D` (linestyle / marker / color / width / alpha / zorder) |
| `matplotlib.collections` | `PathCollection`, `LineCollection`, `PatchCollection`, `PolyCollection`, `QuadMesh`, `EventCollection` |
| `matplotlib.animation` | `FuncAnimation`, `ArtistAnimation`; writers `PillowWriter` (GIF) + `HTMLWriter` / `to_jshtml` (HTML player). *MP4 needs an ffmpeg binary — export on host.* |
| `matplotlib.gridspec` | `GridSpec`, `SubplotSpec`, `GridSpecFromSubplotSpec` |
| `matplotlib.text` | `Text`, `Annotation`, alignment / weight / style |
| `matplotlib.image` | `imread`, `imsave`, `AxesImage` |
| `matplotlib.legend` | `loc`, `ncol`, `bbox_to_anchor`, `frameon`, `title`, … |
| `matplotlib.transforms` | `Affine2D`, `Bbox`, blended / composite transforms |
| `matplotlib.dates` | `DateFormatter`, auto/day/month/year/hour locators, `date2num`/`num2date` |
| `matplotlib.scale` | `linear` / `log` / `symlog` / `logit` / custom `FuncScale` |
| `matplotlib.style` | **28** style sheets — `mplstyle.use('ggplot')`, `plt.style.context(...)`, `plt.style.available` |
| `matplotlib.rcParams` | **full** rcParams — every parameter propagates (it *is* real matplotlib); e.g. `mpl.rcParams['lines.linewidth'] = 2` |
| `matplotlib.mathtext` | **full** internal TeX-style math renderer (Greek, sub/superscripts, fractions, roots, sums, integrals, accents, `\mathbb`/`\hat`/`\frac`, …) rendered by ft2font |
| `mpl_toolkits.mplot3d` | real `Axes3D` — `plot_surface`, `plot_wireframe`, `scatter`, `bar3d`, `plot_trisurf`, `view_init`, `set_zlabel/set_zlim` |
| `mpl_toolkits.axes_grid1` | `make_axes_locatable`, `ImageGrid`, `inset_axes`, `mark_inset` |
| `mpl_toolkits.axisartist` | curvilinear / floating axes |

### mathtext example

```python
plt.title(r'$\alpha \cdot \beta = \gamma$')
plt.xlabel(r'$\hat\beta = (X^{T}X)^{-1}X^{T}y$')
plt.ylabel(r'$\frac{d}{dx} e^{x} = e^{x}$')
```

Rendered by matplotlib's own mathtext engine through ft2font — no external
LaTeX needed. (`usetex=True`, which shells out to a real `latex` binary, is
**not** available on iOS.)

---

## What's absent on iOS (inherent)

| Missing | Why | Workaround |
|---|---|---|
| `macosx` GUI backend | needs AppKit windows | headless Agg + the preview pipeline replace it |
| ffmpeg-binary MP4 animation writer | `anim.save('x.mp4')` shells out to an ffmpeg executable | `PillowWriter` GIF + `to_jshtml` HTML work on device; render MP4 on host |
| `usetex=True` (real LaTeX text) | needs a `latex` binary | built-in mathtext covers ~95% of use |

These are absent from *any* headless environment — not gaps specific to this
port.

---

## Appendix — Legacy plotly-backend shim

> **Version:** 3.9.0-offlinai · **Type:** pure-Python API-compat layer (matplotlib → Plotly) · **Location:** `site-packages/_mpl_plotly_shim/`

Before the real build, matplotlib on iOS was a pure-Python shim that
re-implemented a slice of the API by translating calls into Plotly traces and
rendering interactive Plotly.js HTML. It is **preserved** and selectable per
run:

```bash
CODEBENCH_MPL_BACKEND=plotly   # sitecustomize front-loads sys.path with the shim
```

When it might be worth choosing:

- you specifically want Plotly's *2-D* HTML output (hover/zoom) with zero
  conversion step, or
- a much smaller memory / import footprint than the real C build.

Its limitations (why it's no longer the default): rendering isn't
pixel-faithful to matplotlib; mathtext, exact styling, many artists, precise
layouts, real 3-D, SVG/PDF `savefig`, and true animation are approximate or
absent. `plt.savefig()` on the shim writes Plotly artifacts (`.html`, or
`.png` **via kaleido**), not real matplotlib output. `rcParams` and styles only
partially propagate. The shim's broad API surface (64 modules of stubs) exists
to keep scripts from crashing on unshimmed attributes — for anything beyond
basic 2-D charts, prefer the real build (the default).
