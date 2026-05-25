# Streamlit — script-style dashboards

**Version:** 1.50.x  
**Type:** Pure Python  
**SPM target:** `Streamlit`  
**Auto-includes:** Tornado, Click, Watchdog, Typing_extensions, PyArrow  
**Total Python modules:** 213

Re-runs your whole script top-to-bottom on every widget interaction. State persists automatically (widgets keep their values; `@st.cache_data` caches function results). Best fit for data-exploration UIs where you want to write Python, not callbacks.

## Modules

### Top-level entry points

| Module | What it does |
|---|---|
| `streamlit.__init__` | The big public API surface — every `st.something` is re-exported here. Categories below. |
| `streamlit.__main__` | `python -m streamlit run script.py` entry |
| `streamlit.config` / `config_option` / `config_util` | Config loading (env vars, `.streamlit/config.toml`, programmatic) |
| `streamlit.version` | Version string |
| `streamlit.errors` / `error_util` / `exception_util` | Error types + handlers |
| `streamlit.logger` | Logging setup |

### Top-level `st.*` API (curated)

| Category | Functions |
|---|---|
| **Text** | `st.write`, `st.markdown`, `st.title`, `st.header`, `st.subheader`, `st.caption`, `st.code`, `st.text`, `st.latex`, `st.divider` |
| **Data display** | `st.dataframe`, `st.table`, `st.metric`, `st.data_editor`, `st.json` |
| **Charts** | `st.line_chart`, `st.area_chart`, `st.bar_chart`, `st.scatter_chart`, `st.map`, `st.pyplot`, `st.altair_chart`, `st.vega_lite_chart`, `st.plotly_chart`, `st.bokeh_chart`, `st.pydeck_chart`, `st.graphviz_chart` |
| **Inputs** | `st.button`, `st.download_button`, `st.checkbox`, `st.toggle`, `st.radio`, `st.selectbox`, `st.multiselect`, `st.slider`, `st.select_slider`, `st.text_input`, `st.number_input`, `st.text_area`, `st.date_input`, `st.time_input`, `st.color_picker`, `st.file_uploader`, `st.camera_input` |
| **Media** | `st.image`, `st.audio`, `st.video`, `st.pdf` |
| **Layout** | `st.columns`, `st.tabs`, `st.expander`, `st.container`, `st.sidebar`, `st.empty`, `st.popover`, `st.form`, `st.form_submit_button` |
| **State / cache** | `st.session_state`, `st.cache_data`, `st.cache_resource`, `st.rerun`, `st.stop` |
| **Progress / status** | `st.progress`, `st.spinner`, `st.status`, `st.toast`, `st.balloons`, `st.snow` |
| **Alerts** | `st.success`, `st.info`, `st.warning`, `st.error`, `st.exception` |
| **Multi-page** | `st.navigation`, `st.Page`, `st.switch_page` |
| **Misc** | `st.write_stream`, `st.fragment`, `st.context`, `st.help`, `st.echo` |

### `streamlit.elements` — widget implementations

| Submodule | Provides |
|---|---|
| `elements.alert` | `success` / `info` / `warning` / `error` |
| `elements.arrow` | Apache Arrow-based dataframe serialization |
| `elements.balloons`, `elements.snow` | Celebration animations |
| `elements.bokeh_chart` | Bokeh chart renderer |
| `elements.code`, `elements.heading`, `elements.markdown`, `elements.html`, `elements.json`, `elements.text` | Text-display elements |
| `elements.dialog_decorator` | `@st.dialog` |
| `elements.doc_string`, `elements.exception`, `elements.empty` | Helper elements |
| `elements.form` | `st.form` / `st.form_submit_button` |
| `elements.graphviz_chart` | Graphviz renderer |
| `elements.iframe`, `elements.image`, `elements.media`, `elements.pdf` | Embeds |
| `elements.layouts` | `columns`, `tabs`, `expander`, `container`, `sidebar`, `popover` |
| `elements.map`, `elements.deck_gl_json_chart` | Map / 3D-map renderers |
| `elements.metric` | `st.metric` |
| `elements.plotly_chart`, `elements.altair_chart`, `elements.vega_lite_chart`, `elements.line_chart`, `elements.area_chart`, `elements.bar_chart`, `elements.scatter_chart`, `elements.pyplot` | Chart renderers |
| `elements.progress`, `elements.spinner`, `elements.toast` | Feedback |
| `elements.widgets/` | The actual input-widget implementations (button, checkbox, radio, …) |
| `elements.write_stream` | Async chunk streaming |

### `streamlit.runtime` — server runtime

| Submodule | Provides |
|---|---|
| `runtime.app_session` | Per-session state + script-runner orchestration |
| `runtime.caching` | `cache_data` / `cache_resource` backends, hashing, storage |
| `runtime.fragment` | `@st.fragment` partial re-renders |
| `runtime.legacy_caching` | Older `@st.cache` (kept for compat) |
| `runtime.memory_session_storage`, `runtime.memory_uploaded_file_manager`, `runtime.memory_media_file_storage` | In-memory storage backends |
| `runtime.runtime` | The `Runtime` orchestrator |
| `runtime.scriptrunner/` | Compiles + executes user scripts on every run |
| `runtime.secrets` | `st.secrets` (Tomli-backed `secrets.toml` loader) |
| `runtime.state/` | `st.session_state` machinery |
| `runtime.stats` | Internal metrics |
| `runtime.uploaded_file_manager` | `st.file_uploader` server side |
| `runtime.websocket_session_manager` | Tornado WebSocket plumbing |

### `streamlit.web` — HTTP / WebSocket server

| Submodule | Provides |
|---|---|
| `web.bootstrap` | `bootstrap.run(script, …)` — programmatic launch entry. **iOS-patched:** signal-handler skip on non-main thread + preview-signal + clean-shutdown hooks |
| `web.cli` | The `streamlit` CLI (`streamlit run …`, `streamlit hello`, …) |
| `web.server/` | Tornado handlers: WebSocket, static assets, health, media, components |
| `web.cache_storage_manager_config` | Cache backend selection |

### `streamlit.commands` — top-level shorthand commands

| Submodule | Provides |
|---|---|
| `commands.page_config` | `st.set_page_config(...)` |
| `commands.execution_control` | `st.rerun`, `st.stop` |
| `commands.experimental_query_params` | URL query params API |
| `commands.navigation` | `st.navigation`, `st.Page`, `st.switch_page` |

### `streamlit.components`

| Submodule | Provides |
|---|---|
| `components.v1.components` | Iframe-based custom components |
| `components.v1.custom_component` | `declare_component` (third-party React component loader) |

### `streamlit.connections` — data-source helpers

| Submodule | Provides |
|---|---|
| `connections.base_connection` | Base class for `st.connection` |
| `connections.snowflake_connection`, `connections.sql_connection`, `connections.snowpark_connection` | Built-in connectors |

### `streamlit.proto`, `streamlit.vendor`, `streamlit.external`

`proto` — protobuf message types for the wire protocol.  
`vendor` — copies of small third-party utilities streamlit depends on.  
`external` — third-party adapters.

### Other utilities

| Module | What it does |
|---|---|
| `streamlit.dataframe_util` | DataFrame coercion (pandas, polars, pyarrow, numpy) |
| `streamlit.delta_generator` | Core widget-tree builder |
| `streamlit.column_config` | Column-config types for `st.dataframe` |
| `streamlit.cursor` | Element-tree cursor |
| `streamlit.user_info`, `streamlit.auth_util` | User identity helpers |
| `streamlit.material_icon_names` | All Material Symbols icon names |

### `streamlit.watcher`

File-watching for auto-rerun on save. **Flaky in the iOS sandbox** — set `server.runOnSave=False` and use the rerun button instead.

### `streamlit.hello`

Built-in demo app (`streamlit hello`).

## iOS-specific patches

See [web-stack.md § Streamlit](web-stack.md#streamlit) for details.

| Patch file | Why |
|---|---|
| `streamlit/web/bootstrap.py` `_set_up_signal_handler` | `signal.signal` works only on main thread of main interpreter — Python isn't there in CodeBench |
| `streamlit/web/bootstrap.py` `_on_server_start` | Preview-panel auto-load + clean-shutdown via `call_soon_threadsafe(server.stop)` |
| `PythonRuntime.swift` SafeArray | `__reduce__` / `__reduce_ex__` so `@st.cache_data` can pickle DataFrames containing numpy columns |

**Feature test:** [`streamlit_test.py`](../streamlit_test.py) — 8 tabs covering text, data, charts, inputs, layout, state/cache, progress/forms, misc.

## Limits on iOS

| Feature | Status |
|---|---|
| `st.file_uploader` | Works for small files; large uploads may OOM |
| `st.camera_input` | No AVCapture bridge — not wired |
| `st.video` | Works for H.264/MP4 (WKWebView native); other codecs no |
| Hot-reload on save (`server.runOnSave=True`) | Disabled — watchdog flaky in iOS sandbox |
| `streamlit run` CLI subprocess | Works (no fork needed for the server loop) |

## Example

```python
import streamlit as st
import pandas as pd
import numpy as np

st.title("Demo")
n = st.slider("Rows", 10, 1000, 100)

@st.cache_data
def make_data(rows):
    return pd.DataFrame({
        "x": range(rows),
        "y": np.random.default_rng(42).normal(size=rows).cumsum(),
    })

df = make_data(n)
st.line_chart(df.set_index("x"))
st.dataframe(df.head(20), use_container_width=True)
```

Run with either `streamlit run app.py` from the shell, or programmatically via `streamlit.web.bootstrap.run(...)` — see [web-stack.md § Streamlit](web-stack.md#streamlit) for the launcher pattern.
