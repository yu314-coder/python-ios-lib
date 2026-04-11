# matplotlib - Plotly Backend Shim

> **Version:** 3.9.0-offlinai | **Type:** API compatibility layer (matplotlib -> Plotly) | **Modules:** 64 | **Location:** `matplotlib/`

Drop-in replacement for `matplotlib.pyplot` that renders interactive charts via Plotly.js. Import `matplotlib.pyplot as plt` and it just works. Provides comprehensive API coverage across 64 modules matching matplotlib's public interface.

---

## Quick Start

```python
import numpy as np
import matplotlib.pyplot as plt

x = np.linspace(0, 2 * np.pi, 200)
plt.plot(x, np.sin(x), label='sin(x)')
plt.plot(x, np.cos(x), label='cos(x)')
plt.title('Trigonometric Functions')
plt.xlabel('x')
plt.ylabel('y')
plt.legend()
plt.grid(True)
plt.show()
```

---

## Module Reference (64 modules)

### `matplotlib.pyplot` -- Primary Plotting Interface

#### 2D Plot Types

| Function | Description |
|----------|-------------|
| `plt.plot(x, y, fmt, **kwargs)` | Line plot. Format strings: `'b-'`, `'ro'`, `'g--'`, etc. |
| `plt.scatter(x, y, s, c, marker, alpha)` | Scatter plot with optional size/color arrays |
| `plt.bar(x, height, width, bottom, color)` | Vertical bar chart |
| `plt.barh(y, width, height, left, color)` | Horizontal bar chart |
| `plt.hist(data, bins, range, density, cumulative)` | Histogram |
| `plt.hist2d(x, y, bins, cmap)` | 2D histogram / heatmap |
| `plt.pie(sizes, labels, autopct, explode, shadow)` | Pie chart |
| `plt.fill_between(x, y1, y2, alpha, color)` | Filled area between curves |
| `plt.fill_betweenx(y, x1, x2, alpha)` | Horizontal filled area |
| `plt.stem(x, y, linefmt, markerfmt, basefmt)` | Stem plot |
| `plt.step(x, y, where, color, linewidth)` | Step plot |
| `plt.errorbar(x, y, yerr, xerr, fmt, capsize)` | Error bars |
| `plt.boxplot(data, notch, vert, labels)` | Box-and-whisker plot |
| `plt.violinplot(data, positions, showmeans)` | Violin plot |
| `plt.imshow(Z, cmap, aspect, interpolation, extent)` | Image / heatmap display |
| `plt.matshow(Z, cmap)` | Matrix display (calls imshow) |
| `plt.pcolormesh(X, Y, Z, cmap, shading)` | Pseudocolor mesh plot |
| `plt.contour(X, Y, Z, levels, colors, cmap)` | Contour lines |
| `plt.contourf(X, Y, Z, levels, cmap)` | Filled contours |
| `plt.polar(theta, r, **kwargs)` | Polar plot |
| `plt.stackplot(x, *ys, labels, colors)` | Stacked area chart |
| `plt.hexbin(x, y, gridsize, cmap, mincnt)` | Hexagonal binning plot |
| `plt.hlines(y, xmin, xmax, colors, linestyles)` | Horizontal line segments |
| `plt.vlines(x, ymin, ymax, colors, linestyles)` | Vertical line segments |
| `plt.quiver(X, Y, U, V, C)` | 2D vector field (arrows) |
| `plt.streamplot(X, Y, U, V, density, color)` | 2D streamlines |
| `plt.tricontour(x, y, z, levels)` | Unstructured triangular contour |
| `plt.tricontourf(x, y, z, levels)` | Filled triangular contour |
| `plt.tripcolor(x, y, z, cmap)` | Pseudocolor on triangular grid |
| `plt.spy(Z, precision, marker)` | Sparsity pattern visualization |
| `plt.eventplot(positions, orientation)` | Event/raster plot |
| `plt.broken_barh(xranges, yrange)` | Broken horizontal bars (Gantt-style) |

#### 3D Plot Types

| Function | Description |
|----------|-------------|
| `plt.plot_surface(X, Y, Z, cmap, alpha)` | 3D surface (auto-creates 3D axes) |
| `plt.plot_wireframe(X, Y, Z, color)` | 3D wireframe mesh |
| `plt.scatter3D(x, y, z, c, s, cmap)` | 3D scatter plot |
| `plt.plot3D(x, y, z, color)` | 3D line plot |
| `plt.bar3d(x, y, z, dx, dy, dz, color)` | 3D bar chart |
| `plt.plot_trisurf(x, y, z, cmap)` | 3D triangulated surface |
| `ax.contour3D(X, Y, Z, levels, cmap)` | 3D contour lines |
| `ax.contourf3D(X, Y, Z, levels, cmap)` | 3D filled contours |

#### Figure & Axes Management

| Function | Description |
|----------|-------------|
| `plt.figure(figsize, dpi, facecolor)` | Create new figure |
| `plt.subplots(nrows, ncols, sharex, sharey, figsize)` | Create figure + axes grid |
| `plt.subplot(nrows, ncols, index)` | Add subplot to current figure |
| `plt.subplot2grid(shape, loc, rowspan, colspan)` | Subplot with grid positioning |
| `plt.axes(rect)` | Add axes at arbitrary position |
| `plt.gca()` | Get current axes |
| `plt.gcf()` | Get current figure |
| `plt.cla()` | Clear current axes |
| `plt.clf()` | Clear current figure |
| `plt.close(fig)` | Close a figure |
| `ax.twinx()` | Create secondary y-axis |
| `ax.twiny()` | Create secondary x-axis |
| `fig.add_subplot(nrows, ncols, index, projection)` | Add subplot (`projection='3d'` for 3D) |

#### Annotations & Text

| Function | Description |
|----------|-------------|
| `plt.title(s, fontsize, fontweight)` | Set axes title |
| `plt.suptitle(s, fontsize)` | Set figure super title |
| `plt.xlabel(s, fontsize)` / `plt.ylabel(s)` | Axis labels |
| `plt.text(x, y, s, fontsize, ha, va)` | Place text at data coordinates |
| `plt.annotate(text, xy, xytext, arrowprops)` | Arrow annotation |
| `plt.figtext(x, y, s)` | Text in figure coordinates |
| `ax.set_title(s)` | Axes title (OO interface) |
| `ax.set_xlabel(s)` / `ax.set_ylabel(s)` | Axis labels (OO) |

#### Axis Configuration

| Function | Description |
|----------|-------------|
| `plt.xlim(left, right)` / `plt.ylim(bottom, top)` | Set axis limits |
| `plt.xscale('log')` / `plt.yscale('log')` | Set axis scale (`linear`/`log`/`symlog`/`logit`) |
| `plt.xticks(ticks, labels, rotation)` | Set tick positions and labels |
| `plt.yticks(ticks, labels)` | Set y-axis ticks |
| `plt.grid(visible, which, axis, linestyle)` | Toggle grid |
| `plt.legend(loc, fontsize, frameon, ncol)` | Show legend |
| `plt.colorbar(mappable, ax, label)` | Add colorbar |
| `plt.axis('equal'/'off'/'tight'/'scaled')` | Set axis mode |
| `plt.tight_layout(pad)` | Adjust subplot spacing |
| `plt.margins(x, y)` | Set axis margins |
| `plt.axhline(y, color, linestyle)` | Horizontal reference line |
| `plt.axvline(x, color, linestyle)` | Vertical reference line |
| `plt.axhspan(ymin, ymax, alpha, color)` | Horizontal span (shaded region) |
| `plt.axvspan(xmin, xmax, alpha, color)` | Vertical span |
| `plt.minorticks_on()` / `plt.minorticks_off()` | Toggle minor ticks |
| `ax.invert_xaxis()` / `ax.invert_yaxis()` | Invert axis direction |
| `ax.set_aspect('equal'/'auto')` | Set aspect ratio |

#### Output

| Function | Description |
|----------|-------------|
| `plt.show()` | Display chart (renders as interactive HTML in WKWebView) |
| `plt.savefig('chart.html')` | Save as interactive HTML |
| `plt.savefig('chart.png', dpi)` | Save as PNG (requires kaleido) |
| `plt.savefig('chart.svg')` | Save as SVG |
| `plt.savefig('chart.pdf')` | Save as PDF |

---

### `matplotlib.figure` -- Figure Class

| Class / Method | Description |
|---------------|-------------|
| `Figure(figsize, dpi, facecolor, edgecolor)` | Figure container |
| `fig.add_subplot(pos, projection)` | Add Axes to the figure |
| `fig.add_axes(rect)` | Add Axes at arbitrary position [left, bottom, width, height] |
| `fig.suptitle(t, fontsize)` | Super title for the figure |
| `fig.tight_layout()` | Adjust subplot params for tight layout |
| `fig.subplots_adjust(left, bottom, right, top, wspace, hspace)` | Fine-tune subplot spacing |
| `fig.savefig(fname, dpi, bbox_inches)` | Save figure |
| `fig.set_size_inches(w, h)` | Set figure size |
| `fig.get_axes()` | Return list of axes |

---

### `matplotlib.axes` -- Axes Class

The `Axes` object supports the full OO plotting interface. All `plt.xxx()` functions delegate to the current axes.

| Method | Description |
|--------|-------------|
| `ax.plot()`, `ax.scatter()`, `ax.bar()`, etc. | All plot types listed above |
| `ax.set_xlim()`, `ax.set_ylim()` | Axis limits |
| `ax.set_xscale()`, `ax.set_yscale()` | Axis scales |
| `ax.set_xticks()`, `ax.set_yticks()` | Tick positions |
| `ax.set_xticklabels()`, `ax.set_yticklabels()` | Tick labels |
| `ax.legend()` | Show legend |
| `ax.grid()` | Toggle grid |
| `ax.twinx()`, `ax.twiny()` | Secondary axes |
| `ax.tick_params(axis, which, direction, length)` | Configure tick appearance |

---

### `matplotlib.cm` -- Colormaps (50+ mapped)

Colormaps are callable objects that map normalized values [0, 1] to RGBA colors.

```python
from matplotlib import cm

# Callable colormaps
rgba = cm.viridis(0.5)    # Returns (R, G, B, A) tuple
rgba = cm.plasma(0.75)
rgba = cm.jet(0.25)

# Get colormap by name
cmap = cm.get_cmap('coolwarm')
colors = cmap(np.linspace(0, 1, 10))  # Array of 10 RGBA colors
```

**Sequential:** `viridis`, `plasma`, `inferno`, `magma`, `cividis`, `turbo`

**Perceptual:** `hot`, `cool`, `bone`, `copper`, `gray`, `binary`

**Seasonal:** `spring`, `summer`, `autumn`, `winter`

**Diverging:** `coolwarm`, `RdBu`, `RdYlGn`, `RdYlBu`, `Spectral`, `PiYG`, `PRGn`, `BrBG`, `seismic`, `bwr`

**Cyclic:** `twilight`, `twilight_shifted`, `hsv`

**Qualitative:** `tab10`, `tab20`, `tab20b`, `tab20c`, `Set1`, `Set2`, `Set3`, `Paired`, `Pastel1`, `Pastel2`, `Dark2`, `Accent`

**Multi-hue sequential:** `YlGnBu`, `YlOrRd`, `PuBu`, `BuGn`, `GnBu`, `PuRd`, `OrRd`, `RdPu`, `BuPu`, `YlGn`

**Single-hue sequential:** `Greens`, `Blues`, `Reds`, `Oranges`, `Purples`, `Greys`

**Other:** `jet`, `rainbow`, `gist_rainbow`, `nipy_spectral`, `terrain`, `ocean`, `cubehelix`

---

### `matplotlib.colors` -- Color Utilities

| Function / Class | Description |
|-----------------|-------------|
| `to_rgba(c, alpha)` | Convert any color spec to (R, G, B, A). Supports hex (`'#ff0000'`), named (`'red'`), CSS4, RGB tuples, shorthand (`'r'`, `'b'`) |
| `to_hex(c, keep_alpha)` | Convert color to hex string |
| `to_rgb(c)` | Convert to (R, G, B) tuple |
| `Normalize(vmin, vmax)` | Linear normalization to [0, 1] |
| `LogNorm(vmin, vmax)` | Logarithmic normalization |
| `SymLogNorm(linthresh, vmin, vmax)` | Symmetric log normalization |
| `PowerNorm(gamma, vmin, vmax)` | Power-law normalization |
| `BoundaryNorm(boundaries, ncolors)` | Map to discrete boundaries |
| `TwoSlopeNorm(vcenter, vmin, vmax)` | Diverging normalization around center |
| `Colormap(name, N)` | Base colormap class |
| `ListedColormap(colors, name)` | Colormap from explicit color list |
| `LinearSegmentedColormap(name, segmentdata)` | Colormap from linear segments |
| `LinearSegmentedColormap.from_list(name, colors)` | Create from list of colors |
| `CSS4_COLORS` | Dict of 148 CSS4 named colors |
| `TABLEAU_COLORS` | Dict of Tableau 10 colors |
| `BASE_COLORS` | Dict of single-letter colors (r, g, b, c, m, y, k, w) |
| `XKCD_COLORS` | Dict of 954 XKCD color survey names |

---

### `matplotlib.ticker` -- Tick Locators & Formatters

#### Locators

| Class | Description |
|-------|-------------|
| `AutoLocator()` | Automatic tick placement |
| `MaxNLocator(nbins)` | At most N bins |
| `MultipleLocator(base)` | Ticks at multiples of base |
| `FixedLocator(locs)` | Ticks at specific locations |
| `IndexLocator(base, offset)` | Ticks at index intervals |
| `LinearLocator(numticks)` | Evenly spaced ticks |
| `LogLocator(base, subs)` | Log-scale tick locations |
| `SymmetricalLogLocator(linthresh)` | Symmetric log ticks |
| `NullLocator()` | No ticks |
| `AutoMinorLocator(n)` | Automatic minor ticks |

#### Formatters

| Class | Description |
|-------|-------------|
| `ScalarFormatter(useOffset, useMathText)` | Default scalar formatting |
| `FuncFormatter(func)` | Custom function-based formatting |
| `FormatStrFormatter(fmt)` | Printf-style format string |
| `StrMethodFormatter(fmt)` | str.format()-style formatting |
| `FixedFormatter(seq)` | Fixed sequence of label strings |
| `PercentFormatter(xmax, decimals)` | Display as percentage |
| `LogFormatter(base)` | Log-scale labels |
| `LogFormatterMathtext(base)` | Log labels with mathtext |
| `NullFormatter()` | No labels |
| `EngFormatter(unit, places)` | Engineering notation (k, M, G) |

---

### `matplotlib.patches` -- 2D Shapes

| Class | Key Parameters | Description |
|-------|---------------|-------------|
| `Rectangle(xy, width, height, angle)` | Rectangle patch |
| `Circle(xy, radius)` | Circle patch |
| `Ellipse(xy, width, height, angle)` | Ellipse patch |
| `FancyBboxPatch(xy, width, height, boxstyle)` | Fancy box with rounded corners etc. |
| `Polygon(xy, closed)` | Arbitrary polygon |
| `RegularPolygon(xy, numVertices, radius)` | Regular polygon |
| `Arc(xy, width, height, angle, theta1, theta2)` | Elliptical arc |
| `Wedge(center, r, theta1, theta2, width)` | Wedge (pie slice) |
| `Arrow(x, y, dx, dy, width)` | Arrow patch |
| `FancyArrow(x, y, dx, dy, width, head_width)` | Fancy arrow |
| `FancyArrowPatch(posA, posB, arrowstyle)` | Arrow between two points with style |
| `PathPatch(path, **kwargs)` | Arbitrary path patch |
| `ConnectionPatch(xyA, xyB, coordsA, coordsB)` | Connect points across axes |
| `BoxStyle` | Box styles: `round`, `round4`, `roundtooth`, `sawtooth`, `square` |
| `ArrowStyle` | Arrow styles: `->`, `-[`, `-|>`, `<->`, `<|-|>`, `fancy`, `simple`, `wedge` |

---

### `matplotlib.lines` -- Line2D

| Property | Values |
|----------|--------|
| `linestyle` / `ls` | `'-'`, `'--'`, `'-.'`, `':'`, `'None'` |
| `linewidth` / `lw` | Float (points) |
| `color` / `c` | Any color spec |
| `marker` | `'o'`, `'s'`, `'^'`, `'v'`, `'D'`, `'*'`, `'+'`, `'x'`, `'.'`, `','`, `'h'`, `'p'`, `'|'`, `'_'` |
| `markersize` / `ms` | Float (points) |
| `markerfacecolor` / `mfc` | Marker fill color |
| `markeredgecolor` / `mec` | Marker edge color |
| `alpha` | Float 0-1 transparency |
| `label` | String for legend |
| `zorder` | Drawing order (higher = on top) |

---

### `matplotlib.animation` -- Animation

| Class | Description |
|-------|-------------|
| `FuncAnimation(fig, func, frames, init_func, interval, blit)` | Animation by repeatedly calling a function |
| `ArtistAnimation(fig, artists, interval)` | Animation from a list of artist sequences |

Note: Animation renders as a sequence of frames. Video export requires ffmpeg (limited on iOS).

---

### `matplotlib.gridspec` -- Grid Layout

| Class | Description |
|-------|-------------|
| `GridSpec(nrows, ncols, figure, width_ratios, height_ratios, wspace, hspace)` | Flexible subplot grid specification |
| `SubplotSpec` | Specifies location of a subplot in a GridSpec |
| `GridSpecFromSubplotSpec(nrows, ncols, subplot_spec)` | Nested grid spec |

```python
import matplotlib.gridspec as gridspec
fig = plt.figure(figsize=(12, 8))
gs = gridspec.GridSpec(2, 3, width_ratios=[1, 2, 1], height_ratios=[2, 1])
ax1 = fig.add_subplot(gs[0, :])   # Top row, all columns
ax2 = fig.add_subplot(gs[1, 0])   # Bottom-left
ax3 = fig.add_subplot(gs[1, 1:])  # Bottom-right spanning 2 cols
```

---

### `matplotlib.text` -- Text Rendering

| Class / Property | Description |
|-----------------|-------------|
| `Text(x, y, text, fontsize, ha, va, rotation, color, fontweight, fontstyle)` | Text artist |
| `Annotation(text, xy, xytext, arrowprops, fontsize)` | Annotated text with arrow |
| `fontsize` | Integer or `'xx-small'`, `'x-small'`, `'small'`, `'medium'`, `'large'`, `'x-large'`, `'xx-large'` |
| `fontweight` | `'normal'`, `'bold'`, `'light'`, `'heavy'` |
| `fontstyle` | `'normal'`, `'italic'`, `'oblique'` |
| `ha` (horizontalalignment) | `'left'`, `'center'`, `'right'` |
| `va` (verticalalignment) | `'top'`, `'center'`, `'bottom'`, `'baseline'` |

---

### `matplotlib.image` -- Image Handling

| Function | Description |
|----------|-------------|
| `imread(fname)` | Read image file to numpy array |
| `imsave(fname, arr, cmap)` | Save numpy array as image |
| `AxesImage` | Image displayed on axes (returned by `imshow`) |

---

### `matplotlib.collections` -- Efficient Drawing

| Class | Description |
|-------|-------------|
| `PathCollection` | Collection of paths (used by `scatter()`) |
| `LineCollection(segments, colors, linewidths)` | Collection of line segments |
| `PatchCollection(patches, match_original)` | Collection of patches |
| `PolyCollection(verts, **kwargs)` | Collection of polygons |
| `QuadMesh` | Quadrilateral mesh (used by `pcolormesh()`) |
| `EventCollection(positions, orientation)` | Collection of events |

---

### `matplotlib.legend` -- Legend

| Parameter | Description |
|-----------|-------------|
| `loc` | `'best'`, `'upper right'`, `'upper left'`, `'lower left'`, `'lower right'`, `'center'`, etc. |
| `fontsize` | Legend font size |
| `frameon` | Draw frame around legend |
| `ncol` | Number of columns |
| `title` | Legend title |
| `bbox_to_anchor` | Anchor point for positioning |
| `borderaxespad` | Padding between legend and axes |

---

### `matplotlib.transforms` -- Coordinate Transforms

| Class | Description |
|-------|-------------|
| `Affine2D()` | 2D affine transform (rotate, translate, scale) |
| `Bbox(points)` | Bounding box |
| `TransformedBbox(bbox, transform)` | Transformed bounding box |
| `BlendedGenericTransform(x_transform, y_transform)` | Blend separate x and y transforms |
| `CompositeGenericTransform(a, b)` | Composition of two transforms |

---

### `matplotlib.dates` -- Date Handling

| Class / Function | Description |
|-----------------|-------------|
| `DateFormatter(fmt)` | Format dates on axis (e.g. `'%Y-%m-%d'`) |
| `AutoDateLocator()` | Automatic date tick placement |
| `DayLocator(bymonthday)` | Tick every N days |
| `MonthLocator(bymonth)` | Tick every N months |
| `YearLocator(base)` | Tick every N years |
| `HourLocator(byhour)` | Tick every N hours |
| `MinuteLocator(byminute)` | Tick every N minutes |
| `date2num(d)` | Convert datetime to matplotlib float |
| `num2date(n)` | Convert matplotlib float to datetime |
| `datestr2num(d)` | Convert date string to float |

---

### `matplotlib.scale` -- Axis Scales

| Scale | Description |
|-------|-------------|
| `'linear'` | Default linear scale |
| `'log'` | Logarithmic scale (base 10) |
| `'symlog'` | Symmetric log (linear near zero, log for large values) |
| `'logit'` | Logit scale for probabilities |
| `'function'` | Custom function-based scale |

---

### `matplotlib.style` -- Style Sheets

```python
import matplotlib.style as mplstyle
print(mplstyle.available)  # List available styles
mplstyle.use('ggplot')     # Apply a style
mplstyle.use('seaborn-v0_8')
mplstyle.use('dark_background')
```

Available styles: `default`, `classic`, `ggplot`, `seaborn-v0_8`, `bmh`, `dark_background`, `fivethirtyeight`, `grayscale`, `Solarize_Light2`, `tableau-colorblind10`

---

### `matplotlib.rcParams` -- Configuration

```python
import matplotlib as mpl
mpl.rcParams['figure.figsize'] = [10, 6]
mpl.rcParams['font.size'] = 14
mpl.rcParams['lines.linewidth'] = 2
mpl.rcParams['axes.grid'] = True
```

Note: Only basic rcParams are supported. Complex configuration may not propagate to the Plotly backend.

---

### `matplotlib.mathtext` -- Math Text Rendering

Supports TeX-like math expressions in labels and titles:

```python
plt.title(r'$\alpha \cdot \beta = \gamma$')
plt.xlabel(r'$x^2 + y^2 = r^2$')
plt.ylabel(r'$\frac{d}{dx} e^x = e^x$')
```

Supported: Greek letters, superscripts, subscripts, fractions, square roots, summation, integrals, common math symbols.

---

### `mpl_toolkits.mplot3d` -- 3D Plotting Toolkit

| Class / Method | Description |
|---------------|-------------|
| `Axes3D(fig)` | 3D axes object |
| `ax.plot_surface(X, Y, Z, cmap, alpha, rstride, cstride)` | 3D surface mesh |
| `ax.plot_wireframe(X, Y, Z, rstride, cstride)` | 3D wireframe mesh |
| `ax.scatter(x, y, z, c, s, marker)` | 3D scatter points |
| `ax.plot(x, y, z, color)` | 3D line |
| `ax.bar3d(x, y, z, dx, dy, dz, color)` | 3D bar chart |
| `ax.plot_trisurf(x, y, z, cmap)` | 3D triangulated surface |
| `ax.contour(X, Y, Z, levels)` | 3D contour |
| `ax.contourf(X, Y, Z, levels)` | 3D filled contour |
| `ax.set_zlabel(s)` | Z-axis label |
| `ax.set_zlim(low, high)` | Z-axis limits |
| `ax.view_init(elev, azim)` | Set camera angle |
| `ax.dist` | Camera distance |

Access via: `fig.add_subplot(111, projection='3d')` or `from mpl_toolkits.mplot3d import Axes3D`

---

### `mpl_toolkits.axes_grid1` -- Axes Grid Helpers

| Class | Description |
|-------|-------------|
| `make_axes_locatable(ax)` | Create divider for appending axes (used for colorbars) |
| `ImageGrid(fig, rect, nrows_ncols, axes_pad)` | Grid of axes for images |
| `AxesDivider` | Divide axes into sub-axes |
| `inset_locator.inset_axes(parent_axes, width, height, loc)` | Create inset axes |
| `inset_locator.mark_inset(parent_axes, inset_axes, loc1, loc2)` | Mark inset region |

---

### `mpl_toolkits.axisartist` -- Custom Axis

| Class | Description |
|-------|-------------|
| `Subplot(fig, *args)` | Subplot with axisartist features |
| `Axes(fig, rect)` | Axes with custom axis drawing |
| `floating_axes.FloatingSubplot(fig, rect, transform)` | Floating axes (curved coordinate systems) |
| `grid_helper_curvelinear` | Curvilinear grid helper |

---

### Additional Modules

| Module | Description |
|--------|-------------|
| `matplotlib.backend_bases` | Abstract backend interface |
| `matplotlib.backends` | Backend implementations |
| `matplotlib.bezier` | Bezier curve utilities |
| `matplotlib.blocking_input` | Blocking input helpers |
| `matplotlib.category` | Categorical axis support |
| `matplotlib.cbook` | Utility functions (deprecated_warning, etc.) |
| `matplotlib.colorbar` | Colorbar class and helpers |
| `matplotlib.container` | Artist containers (BarContainer, ErrorbarContainer, StemContainer) |
| `matplotlib.contour` | Contour computation |
| `matplotlib.dviread` | DVI file reading |
| `matplotlib.font_manager` | Font discovery and management |
| `matplotlib.ft2font` | FreeType font interface |
| `matplotlib.hatch` | Hatch pattern definitions |
| `matplotlib.markers` | Marker style definitions |
| `matplotlib.mlab` | MATLAB-compatible helper functions |
| `matplotlib.offsetbox` | Offset box for annotations (AnchoredText, TextArea, DrawingArea) |
| `matplotlib.path` | Path class for arbitrary curves |
| `matplotlib.patheffects` | Path effects (shadow, stroke, normal) |
| `matplotlib.projections` | Projection registry (polar, etc.) |
| `matplotlib.quiver` | Quiver and barbs |
| `matplotlib.sankey` | Sankey diagram |
| `matplotlib.spines` | Axes spines (borders) |
| `matplotlib.stackplot` | Stacked area plot |
| `matplotlib.streamplot` | Streamline plots |
| `matplotlib.table` | Table rendering on axes |
| `matplotlib.texmanager` | TeX rendering manager |
| `matplotlib.textpath` | Text as Path objects |
| `matplotlib.tri` | Triangulation and triangular grids |
| `matplotlib.units` | Unit conversion support |
| `matplotlib.widgets` | Interactive widgets (Slider, Button, etc.) |

---

## Compatibility Notes

- All plots render as interactive Plotly.js charts in WKWebView
- Plotly provides built-in hover, zoom, pan, and legend toggle
- `plt.show()` generates HTML output (not bitmap)
- Most `rcParams` are accepted but not all propagate to Plotly
- The OO interface (`fig, ax = plt.subplots()`) is fully supported
- Format strings (`'r--'`, `'bo'`, `'g^'`) are parsed and mapped to Plotly styles
