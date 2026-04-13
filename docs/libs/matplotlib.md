# matplotlib

**Plotly backend shim** | v3.9.0-offlinai | 64 modules

> Drop-in replacement that translates `matplotlib.pyplot` API calls into interactive Plotly HTML charts. Works offline on iPad.

---

## Plot Types

### 2D Plots

| Function | Description |
|----------|-------------|
| `plot(x, y)` | Line plot (color, linestyle, linewidth, marker, label) |
| `scatter(x, y)` | Scatter plot (s, c, cmap, alpha, marker) |
| `bar(x, h)` / `barh(y, w)` | Vertical / horizontal bar charts |
| `hist(x, bins)` | Histogram (bins, alpha, density, cumulative) |
| `pie(sizes)` | Pie chart (labels, autopct, explode) |
| `fill_between(x, y1, y2)` | Filled area between curves |
| `stem(x, y)` | Stem (lollipop) plot |
| `step(x, y)` | Step function (pre/post/mid) |
| `errorbar(x, y, yerr)` | Error bars (xerr, capsize) |
| `boxplot(data)` | Box-and-whisker |
| `violinplot(data)` | Violin distribution plot |
| `stackplot(x, ys)` | Stacked area chart |
| `hexbin(x, y)` | Hexagonal binning heatmap |
| `hlines` / `vlines` | Horizontal / vertical reference lines |

### Heatmaps & Contours

| Function | Description |
|----------|-------------|
| `imshow(data)` | 2D array heatmap (cmap, aspect, interpolation) |
| `contour(X, Y, Z)` | Contour lines (levels, colors) |
| `contourf(X, Y, Z)` | Filled contours (levels, cmap) |
| `matshow(data)` | Matrix display |
| `pcolormesh(X, Y, Z)` | Pseudocolor mesh |

### 3D Plots

| Function | Description |
|----------|-------------|
| `plot_surface(X, Y, Z)` | 3D surface (cmap, alpha) |
| `plot_wireframe(X, Y, Z)` | 3D wireframe mesh |
| `scatter3D(x, y, z)` | 3D scatter (c, cmap, s) |
| `plot3D(x, y, z)` | 3D line plot |

### Annotations & Text

`annotate()`, `text()`, `title()`, `suptitle()`, `xlabel()`, `ylabel()`, `table()`

### Axes & Layout

`xlim`, `ylim`, `xticks`, `yticks`, `xscale`, `yscale`, `grid`, `legend`, `axis`, `tight_layout`, `axhline`, `axvline`, `axhspan`, `axvspan`, `twinx`, `twiny`

### Figure Management

`figure()`, `subplots(nrows, ncols)`, `subplot()`, `axes()`, `gca()`, `gcf()`, `savefig()`, `show()`, `close()`, `clf()`, `cla()`, `colorbar()`, `clim()`

---

## Colormaps (50+)

Sequential: `viridis`, `plasma`, `inferno`, `magma`, `cividis`, `hot`, `cool`, `bone`, `copper`, `gray`

Diverging: `coolwarm`, `RdBu`, `RdYlGn`, `Spectral`, `PiYG`, `PRGn`, `BrBG`, `seismic`

Qualitative: `Set1`, `Set2`, `Set3`, `Paired`, `tab10`, `tab20`

Cyclic: `twilight`, `twilight_shifted`, `hsv`

Seasonal: `spring`, `summer`, `autumn`, `winter`

Perceptual: `turbo`, `rainbow`, `jet`

---

## Submodules

| Module | Contents |
|--------|----------|
| `matplotlib.pyplot` | Main plotting interface |
| `matplotlib.cm` | `get_cmap()`, `ScalarMappable`, 50+ colormaps |
| `matplotlib.colors` | `Normalize`, `LogNorm`, `to_rgba`, `ListedColormap` |
| `matplotlib.figure` | `Figure` class |
| `matplotlib.axes` | `Axes` class |
| `matplotlib.patches` | `Circle`, `Rectangle`, `FancyArrowPatch` stubs |
| `matplotlib.lines` | `Line2D` stub |
| `matplotlib.ticker` | `MaxNLocator`, `MultipleLocator` stubs |
| `matplotlib.animation` | `FuncAnimation` stub (not animated) |
| `mpl_toolkits.mplot3d` | `Axes3D`, `art3d`, `proj3d` |

---

## Output

All plots render as **interactive Plotly HTML** files. Pan, zoom, and hover are built-in. Saved via `savefig()` as HTML (PNG/PDF if kaleido is available).

---

## Limitations

- No `rcParams` (only basic `plt.rcParams.update()`)
- No true matplotlib Artist/Patch object model
- No `FuncAnimation` playback
- No interactive backends (Qt, Tk) — Plotly HTML only
- Quiver, streamplot, 3D bar plots not yet mapped
