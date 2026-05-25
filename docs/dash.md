# Dash — reactive dashboards

**Version:** 3.x  
**Type:** Pure Python (+ bundled JS renderer assets)  
**SPM target:** `Dash`  
**Auto-includes:** Flask, Werkzeug, Jinja2, Markupsafe, Click, Plotly  
**Total Python modules:** 211

Plotly-based dashboard framework — declarative layout (HTML + dcc components), reactive callbacks, interactive charts. Build a real on-device data app in a single Python file. Runs on Flask, served by Werkzeug; the JS renderer ships pre-built inside the package.

## Modules

### Core API (top-level)

| Module | What it does |
|---|---|
| `dash.__init__` | Public API exports: `Dash`, `html`, `dcc`, `dash_table`, `Input`, `Output`, `State`, `MATCH`, `ALL`, `ALLSMALLER`, `ctx` (callback context), `no_update`, `Patch`, `clientside_callback`, `register_page` |
| `dash.dash` | The `Dash` application class |
| `dash._callback` | `@app.callback` decorator — wires inputs/outputs to handlers |
| `dash._callback_context` | `ctx.triggered_id`, `ctx.inputs`, `ctx.states`, `ctx.outputs_grouping` |
| `dash._configs` | Config resolution (env vars, kwargs) |
| `dash._dash_renderer` | Renderer asset wiring (the JS bundle for the browser) |
| `dash._get_app` / `_get_paths` | App + path helpers used by pages and assets |
| `dash._grouping` | Dict/list grouping helpers for nested outputs |
| `dash._hooks` | Plugin / hook points |
| `dash._jupyter` | Jupyter-mode integration |
| `dash._no_update` | `no_update` sentinel for callbacks that conditionally skip outputs |
| `dash._obsolete` | Friendly errors for renamed/removed APIs (e.g., `app.run_server` → `app.run`) |
| `dash._pages` | Multi-page apps (`register_page`, automatic routing) |
| `dash._patch` | `Patch` — partial updates to nested component props |
| `dash._utils` / `_validate` / `_watch` | Internal helpers |
| `dash.dependencies` | `Input`, `Output`, `State`, `ClientsideFunction`, `MATCH`/`ALL`/`ALLSMALLER` |
| `dash.exceptions` | `PreventUpdate`, `DuplicateCallback`, `NonExistentIdException`, etc. |
| `dash.fingerprint` | Asset-cache busting |
| `dash.resources` | Resource (CSS/JS) registration |
| `dash.types` | Type aliases |
| `dash.version` | Package version |
| `dash._plotly_cli` | Embedded plotly CLI shim |

### `dash.html` — HTML primitives (auto-generated)

One file per HTML element. Use any like `html.Div(...)`, `html.H1(...)`, etc.

Includes: `Div`, `Span`, `H1`–`H6`, `P`, `A`, `Img`, `Button`, `Hr`, `Br`, `Pre`, `Code`, `Table`, `Thead`, `Tbody`, `Tr`, `Td`, `Th`, `Ul`, `Ol`, `Li`, `Form`, `Label`, `Input`, `Textarea`, `Select`, `Option`, `Header`, `Footer`, `Main`, `Section`, `Article`, `Aside`, `Nav`, `Figure`, `Figcaption`, `Details`, `Summary`, `Iframe`, `Canvas`, `Video`, `Audio`, `Source`, `Track`, … (135+ tags).

### `dash.dcc` — Dash Core Components

Interactive widgets. Auto-rendered by the JS renderer.

| Component | What it is |
|---|---|
| `Graph` | Plotly figure renderer (the main charting widget) |
| `Input` | Text / number / password input |
| `Textarea` | Multi-line text |
| `Dropdown` | Single + multi-select dropdown |
| `Checklist` | Multi-check group |
| `RadioItems` | Single-select radio group |
| `Slider`, `RangeSlider` | Numeric sliders |
| `DatePickerSingle`, `DatePickerRange` | Date pickers |
| `Upload` | Drag-drop file upload |
| `Markdown` | Render markdown (with mathjax, fenced code) |
| `Tabs`, `Tab` | Tabbed layout |
| `Store` | Client-side state |
| `Interval` | Periodic timer (for live updates) |
| `Loading` | Spinner wrapper for slow callbacks |
| `Link`, `Location` | Client-side routing |
| `Download` | Triggered file downloads |
| `Clipboard` | Copy-to-clipboard |
| `LogoutButton`, `ConfirmDialog`, `ConfirmDialogProvider` | Misc UX |

### `dash.dash_table`

| Module | What it does |
|---|---|
| `dash_table.DataTable` | The interactive data grid: sort, filter, paginate, edit, dropdown cells, conditional formatting, row selection, virtualization, fixed headers |

Plus `Format` / `FormatTemplate` helpers for column formatting.

### `dash.background_callback` — long-running callbacks

| Submodule | Provides |
|---|---|
| `background_callback.__init__` | `CeleryManager`, `DiskcacheManager` |
| `background_callback._proxy_set_props` | Async progress / set_progress hooks |

**iOS note:** Celery + Diskcache backends aren't bundled by default. For dashboards that need long-running background work, use `dcc.Loading` + sync callbacks instead.

### `dash.development`

Internal tools for component-library development (extracting metadata from React components). Not needed at runtime.

### `dash.testing`

Selenium-based testing utilities. Doesn't apply on iOS — no Selenium.

## iOS notes

Inherits all Flask + Werkzeug iOS patches (see [werkzeug.md](werkzeug.md)). Server starts via `app.run()` which calls `flask.app.run()` → `werkzeug.serving.run_simple`, so the preview-panel + clean-shutdown hooks fire automatically.

**Dark-mode workaround:** WKWebView auto-applies dark mode based on system preference. Dash's default-styled components render black-on-black. Override `app.index_string` to force a light color scheme — see [web-stack.md § Dash](web-stack.md#dash) for the snippet.

**Feature test:** [`dash_test.py`](../dash_test.py) — 6 tabs exercising every common component + callback pattern (including pattern-matching callbacks with `ALL` wildcard).

## Example

```python
import dash
from dash import Dash, html, dcc, Input, Output
import plotly.express as px
import pandas as pd

app = Dash(__name__)
app.layout = html.Div([
    html.H1("Live data"),
    dcc.Slider(id="n", min=10, max=200, step=10, value=50),
    dcc.Graph(id="chart"),
])

@app.callback(Output("chart", "figure"), Input("n", "value"))
def render(n):
    df = pd.DataFrame({"x": range(n), "y": [i*i for i in range(n)]})
    return px.line(df, x="x", y="y", title=f"y = x² for n={n}")

app.run(host="127.0.0.1", port=8050, debug=False)
```

See [web-stack.md](web-stack.md) for the full iOS framework story.
