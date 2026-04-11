# Plotly

> **Version:** 6.6.0 | **Type:** Stock (pure Python) | **Status:** Fully working

Plotly is the rendering engine behind the matplotlib shim. Can also be used directly for interactive charts via the `graph_objects` API.

---

## Quick Start

```python
import plotly.graph_objects as go

fig = go.Figure()
fig.add_trace(go.Scatter(x=[1, 2, 3, 4], y=[10, 11, 12, 13], mode='lines+markers', name='Series A'))
fig.add_trace(go.Bar(x=[1, 2, 3, 4], y=[5, 4, 3, 6], name='Series B'))
fig.update_layout(title='Mixed Chart', xaxis_title='X', yaxis_title='Y')
fig.show()
```

---

## Trace Types (`plotly.graph_objects`)

### Basic Charts

| Trace | Description | Key Parameters |
|-------|-------------|----------------|
| `go.Scatter` | Line, scatter, bubble | `x`, `y`, `mode` (`lines`/`markers`/`lines+markers`/`text`), `marker`, `line`, `text`, `fill` |
| `go.Bar` | Bar chart | `x`, `y`, `orientation` (`v`/`h`), `marker`, `text`, `textposition` |
| `go.Pie` | Pie / donut | `labels`, `values`, `hole` (0-1 for donut), `pull`, `textinfo` |
| `go.Histogram` | Histogram | `x`, `nbinsx`, `histnorm`, `cumulative`, `opacity` |
| `go.Histogram2d` | 2D histogram | `x`, `y`, `nbinsx`, `nbinsy`, `colorscale` |
| `go.Box` | Box plot | `y`, `x`, `name`, `boxpoints` (`all`/`outliers`/`False`), `notched` |
| `go.Violin` | Violin plot | `y`, `x`, `box_visible`, `meanline_visible`, `side` |
| `go.Heatmap` | 2D heatmap | `z`, `x`, `y`, `colorscale`, `showscale`, `text` |
| `go.Contour` | Contour plot | `z`, `x`, `y`, `colorscale`, `contours`, `line` |
| `go.Table` | Data table | `header`, `cells`, `columnwidth` |

### Statistical

| Trace | Description |
|-------|-------------|
| `go.Histogram2dContour` | 2D histogram contour |
| `go.Scatterternary` | Ternary scatter |
| `go.Splom` | Scatter plot matrix |
| `go.Parcoords` | Parallel coordinates |
| `go.Parcats` | Parallel categories |
| `go.Indicator` | KPI indicator (number, gauge, delta) |

### 3D Charts

| Trace | Description | Key Parameters |
|-------|-------------|----------------|
| `go.Scatter3d` | 3D scatter/line | `x`, `y`, `z`, `mode`, `marker`, `line` |
| `go.Surface` | 3D surface | `z`, `x`, `y`, `colorscale`, `showscale`, `opacity` |
| `go.Mesh3d` | 3D mesh | `x`, `y`, `z`, `i`, `j`, `k`, `intensity`, `colorscale` |
| `go.Isosurface` | Isosurface | `x`, `y`, `z`, `value`, `isomin`, `isomax` |
| `go.Volume` | Volume rendering | `x`, `y`, `z`, `value`, `opacity`, `surface_count` |
| `go.Cone` | 3D cone (vector field) | `x`, `y`, `z`, `u`, `v`, `w` |
| `go.Streamtube` | 3D streamtube | `x`, `y`, `z`, `u`, `v`, `w` |

### Polar & Specialized

| Trace | Description |
|-------|-------------|
| `go.Scatterpolar` | Polar scatter/line |
| `go.Barpolar` | Polar bar chart |
| `go.Scattergeo` | Geographic scatter |
| `go.Choropleth` | Choropleth map |
| `go.Scattermapbox` | Mapbox scatter |
| `go.Choroplethmapbox` | Mapbox choropleth |
| `go.Densitymapbox` | Mapbox density |

### Financial & Hierarchical

| Trace | Description |
|-------|-------------|
| `go.Candlestick` | OHLC candlestick | 
| `go.Ohlc` | OHLC bar chart |
| `go.Funnel` | Funnel chart |
| `go.Funnelarea` | Funnel area |
| `go.Waterfall` | Waterfall chart |
| `go.Treemap` | Treemap |
| `go.Sunburst` | Sunburst (hierarchical pie) |
| `go.Icicle` | Icicle chart |
| `go.Sankey` | Sankey diagram |

### Carpet & Image

| Trace | Description |
|-------|-------------|
| `go.Carpet` | Carpet plot base |
| `go.Scattercarpet` | Scatter on carpet |
| `go.Contourcarpet` | Contour on carpet |
| `go.Image` | Display image data |
| `go.Scattersmith` | Smith chart scatter |

---

## Layout Configuration

```python
fig.update_layout(
    title=dict(text='Title', x=0.5, font=dict(size=20)),
    xaxis=dict(title='X', range=[0, 10], type='linear', showgrid=True, gridcolor='lightgray'),
    yaxis=dict(title='Y', type='log', zeroline=True),
    legend=dict(x=0, y=1, bgcolor='rgba(255,255,255,0.5)'),
    template='plotly_white',   # or plotly, plotly_dark, ggplot2, seaborn, simple_white
    font=dict(family='Arial', size=12, color='black'),
    width=800, height=600,
    margin=dict(l=60, r=30, t=60, b=60),
    showlegend=True,
    hovermode='closest',       # or x, y, x unified, y unified
    plot_bgcolor='white',
    paper_bgcolor='white',
)
```

### Axes Configuration

| Property | Description |
|----------|-------------|
| `title` | Axis title |
| `type` | `linear`, `log`, `date`, `category`, `multicategory` |
| `range` | [min, max] |
| `autorange` | `True`, `False`, `reversed` |
| `dtick` | Tick interval |
| `tickformat` | strftime or d3-format string |
| `tickvals` / `ticktext` | Custom tick positions/labels |
| `showgrid` / `gridcolor` | Grid visibility |
| `zeroline` / `zerolinecolor` | Zero line |
| `showline` / `linecolor` | Axis line |
| `mirror` | Mirror axis to opposite side |
| `side` | `left`, `right`, `top`, `bottom` |

---

## Subplots

```python
from plotly.subplots import make_subplots

fig = make_subplots(
    rows=2, cols=2,
    subplot_titles=['A', 'B', 'C', 'D'],
    specs=[[{"type": "scatter"}, {"type": "bar"}],
           [{"type": "pie"}, {"type": "heatmap"}]],
    shared_xaxes=True,
    vertical_spacing=0.1,
    horizontal_spacing=0.05,
)
fig.add_trace(go.Scatter(x=[1,2,3], y=[4,5,6]), row=1, col=1)
fig.add_trace(go.Bar(x=[1,2,3], y=[2,3,1]), row=1, col=2)
fig.show()
```

---

## Annotations & Shapes

```python
fig.add_annotation(x=2, y=5, text="Peak", showarrow=True, arrowhead=2)
fig.add_shape(type="rect", x0=1, y0=1, x1=3, y1=5, line=dict(color="red"))
fig.add_shape(type="circle", x0=0, y0=0, x1=2, y1=2, fillcolor="lightblue", opacity=0.3)
fig.add_shape(type="line", x0=0, y0=0, x1=5, y1=5, line=dict(dash="dash"))
fig.add_hline(y=3, line_dash="dot", line_color="green")
fig.add_vline(x=2, line_dash="dash")
fig.add_hrect(y0=1, y1=3, fillcolor="yellow", opacity=0.2)
fig.add_vrect(x0=0, x1=2, fillcolor="red", opacity=0.1)
```

---

## Output

Charts render as interactive HTML in WKWebView with:
- Hover tooltips
- Zoom and pan
- Box/lasso selection
- Legend toggle
- Axis range slider
- Export (screenshot)

## Not Available

- `plotly.express` (requires pandas -- use `go` objects directly)
- Dash (web framework, not applicable on iOS)
- Image export via orca/kaleido (no subprocess on iOS)
