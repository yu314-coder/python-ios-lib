# matplotlib - Plotly Backend Shim

> **Version:** 3.9.0-offlinai | **Type:** API compatibility layer (matplotlib -> Plotly) | **Location:** `matplotlib/`

Drop-in replacement for `matplotlib.pyplot` that renders interactive charts via Plotly.js. Import `matplotlib.pyplot as plt` and it just works.

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

## Implemented

### 2D Plot Types

| Function | Usage |
|----------|-------|
| `plt.plot(x, y)` | Line plot |
| `plt.scatter(x, y)` | Scatter plot |
| `plt.bar(x, height)` | Vertical bars |
| `plt.barh(y, width)` | Horizontal bars |
| `plt.hist(data, bins=20)` | Histogram |
| `plt.pie(sizes, labels=...)` | Pie chart |
| `plt.fill_between(x, y1, y2)` | Filled area |
| `plt.stem(x, y)` | Stem plot |
| `plt.step(x, y)` | Step plot |
| `plt.errorbar(x, y, yerr=...)` | Error bars |
| `plt.boxplot(data)` | Box-and-whisker |
| `plt.violinplot(data)` | Violin plot |
| `plt.imshow(Z)` | Heatmap |
| `plt.contour(X, Y, Z)` | Contour lines |
| `plt.contourf(X, Y, Z)` | Filled contours |
| `plt.polar(theta, r)` | Polar plot |
| `plt.stackplot(x, y1, y2)` | Stacked area |
| `plt.hexbin(x, y)` | Hexagonal binning |
| `plt.hlines(y, xmin, xmax)` | Horizontal lines |
| `plt.vlines(x, ymin, ymax)` | Vertical lines |

```python
# Contour plot for implicit equation e^x + y^3 = 1
x = np.linspace(-3, 3, 200)
y = np.linspace(-3, 3, 200)
X, Y = np.meshgrid(x, y)
Z = np.exp(X) + Y**3
plt.contour(X, Y, Z, levels=[1], colors='blue', linewidths=2)
plt.title('e^x + y^3 = 1')
plt.axis('equal')
plt.grid(True)
plt.show()
```

### 3D Plot Types

| Function | Usage |
|----------|-------|
| `plt.plot_surface(X, Y, Z)` | 3D surface (auto-creates 3D axes) |
| `plt.plot_wireframe(X, Y, Z)` | 3D wireframe |
| `plt.scatter3D(x, y, z)` | 3D scatter |
| `plt.plot3D(x, y, z)` | 3D line |
| `ax.plot_surface(X, Y, Z)` | Surface on explicit 3D axes |
| `ax.plot_wireframe(X, Y, Z)` | Wireframe on explicit 3D axes |
| `ax.scatter3D(x, y, z)` | 3D scatter on axes |

```python
# 3D surface - Unit sphere
fig = plt.figure()
ax = fig.add_subplot(111, projection='3d')
u = np.linspace(0, 2 * np.pi, 50)
v = np.linspace(0, np.pi, 50)
X = np.outer(np.cos(u), np.sin(v))
Y = np.outer(np.sin(u), np.sin(v))
Z = np.outer(np.ones_like(u), np.cos(v))
ax.plot_surface(X, Y, Z, cmap='viridis', alpha=0.8)
plt.title('Unit Sphere')
plt.show()

# Or the shorthand way:
plt.plot_surface(X, Y, Z, cmap='plasma')
plt.show()
```

### Subplots

```python
fig, axes = plt.subplots(2, 2)
axes[0, 0].plot(x, np.sin(x))
axes[0, 1].scatter(x, np.cos(x))
axes[1, 0].bar(['A', 'B', 'C'], [3, 7, 5])
axes[1, 1].hist(np.random.randn(200), bins=20)
plt.show()
```

### Dual Axes

```python
fig, ax1 = plt.subplots()
ax1.plot(x, np.sin(x), 'b-', label='sin')
ax2 = ax1.twinx()
ax2.plot(x, np.exp(x / 5), 'r-', label='exp')
plt.show()
```

### Annotations & Styling

| Function | Description |
|----------|-------------|
| `plt.title(s)` / `plt.suptitle(s)` | Title |
| `plt.xlabel(s)` / `plt.ylabel(s)` | Axis labels |
| `plt.xlim(a, b)` / `plt.ylim(a, b)` | Axis limits |
| `plt.xscale('log')` / `plt.yscale('log')` | Scale |
| `plt.grid(True)` | Grid |
| `plt.legend()` | Legend |
| `plt.annotate(text, xy=...)` | Arrow annotation |
| `plt.text(x, y, s)` | Text |
| `plt.axhline(y)` / `plt.axvline(x)` | Reference lines |
| `plt.colorbar()` | Colorbar |
| `plt.tight_layout()` | Layout |
| `plt.axis('equal'/'off')` | Axis mode |

### Colormaps (50 mapped)

`viridis`, `plasma`, `inferno`, `magma`, `cividis`, `hot`, `cool`, `coolwarm`, `jet`, `rainbow`, `turbo`, `gray`, `bone`, `copper`, `spring`, `summer`, `autumn`, `winter`, `RdYlGn`, `RdBu`, `Spectral`, `YlGnBu`, `YlOrRd`, `PuBu`, `BuGn`, `Greens`, `Blues`, `Reds`, `Oranges`, `Purples`, `PiYG`, `PRGn`, `BrBG`, `Set1`, `Set2`, `Set3`, `Paired`, `tab10`, `tab20`, `hsv`, `twilight`

### Figure Output

| Function | Description |
|----------|-------------|
| `plt.show()` | Display chart (renders as interactive HTML) |
| `plt.savefig('chart.html')` | Save as HTML |
| `plt.savefig('chart.png')` | Save as PNG (requires kaleido) |

---

## Not Implemented

- `rcParams` (only basic updates)
- FuncAnimation / animations
- Artist/Patch object model
- Quiver, streamplot
- 3D bar plots
- Geographic projections (Basemap, Cartopy)
- Seaborn compatibility layer
- Interactive pan/zoom (Plotly handles this)
