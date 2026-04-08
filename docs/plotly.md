# Plotly

> **Version:** 6.6.0 | **Type:** Stock (pure Python) | **Status:** Fully working

Plotly is the rendering engine behind the matplotlib shim. Can also be used directly for interactive charts.

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

## Available Trace Types

| Trace | Usage |
|-------|-------|
| `go.Scatter` | Line, scatter, bubble charts |
| `go.Bar` | Bar charts |
| `go.Pie` | Pie/donut charts |
| `go.Heatmap` | 2D heatmaps |
| `go.Contour` | Contour plots |
| `go.Histogram` | Histograms |
| `go.Box` | Box plots |
| `go.Violin` | Violin plots |
| `go.Scatter3d` | 3D scatter/line |
| `go.Surface` | 3D surface |
| `go.Mesh3d` | 3D mesh |
| `go.Scatterpolar` | Polar plots |
| `go.Table` | Data tables |
| `go.Funnel` | Funnel charts |
| `go.Waterfall` | Waterfall charts |
| `go.Treemap` | Treemap |
| `go.Sunburst` | Sunburst |
| `go.Sankey` | Sankey diagram |
| `go.Choropleth` | Map visualizations |
| `go.Candlestick` | Financial charts |

## Subplots

```python
from plotly.subplots import make_subplots

fig = make_subplots(rows=2, cols=2, subplot_titles=['A', 'B', 'C', 'D'])
fig.add_trace(go.Scatter(x=[1,2,3], y=[4,5,6]), row=1, col=1)
fig.add_trace(go.Bar(x=[1,2,3], y=[2,3,1]), row=1, col=2)
fig.show()
```

## Output

Charts render as interactive HTML files displayed in WKWebView. Features:
- Hover tooltips
- Zoom and pan
- Legend toggle
- Export (screenshot)

## Not Available

- `plotly.express` (requires pandas — use `go` objects directly)
- Dash (web framework, not applicable on iOS)
- Image export via orca/kaleido (no subprocess on iOS)
