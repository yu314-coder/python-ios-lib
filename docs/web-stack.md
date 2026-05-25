# Web framework stack — Flask, Werkzeug, Dash, Streamlit, Tornado

Run real web apps **on-device**. The dashboard renders right inside CodeBench's preview panel — no external browser, no laptop tether.

| Library | Version | What it gives you | iOS-specific |
|---|---|---|---|
| **Werkzeug** | 3.1.x | WSGI utilities, dev server, request/response, routing primitives | Patched: `multiprocessing.Value` fallback, reloader auto-disable on worker thread, preview-signal hook, clean-shutdown hook |
| **Flask** | 3.x | Web framework on top of Werkzeug — routes, templates, sessions, blueprints | Inherits werkzeug patches; works as-is |
| **Dash** | 3.x | Plotly-based dashboards: reactive callbacks, charts, tables, components | Works once werkzeug patches are in; debug-mode pin-auth no longer crashes |
| **Streamlit** | 1.50.x | Script-style dashboards: declarative widgets, magic display, caching | Patched: signal-handler skip, preview hook, clean-shutdown hook |
| **Tornado** | 6.5.x | Async HTTP/WebSocket framework — streamlit's transport layer | Pure-Python; macOS `speedups.abi3.so` stripped (lib falls back transparently) |

All five ship as standalone SPM products. The dependency graph:

```
Streamlit  →  Tornado, Click, Watchdog, Typing_extensions, PyArrow
Dash       →  Flask, Plotly
Flask      →  Werkzeug, Jinja2, Markupsafe, Click
Werkzeug   →  (none — standalone)
Tornado    →  (none — standalone)
```

You only tick the top one you need in Xcode. SPM pulls everything else.

---

## Why these need iOS-specific patches

These frameworks assume a desktop POSIX environment that iOS doesn't fully provide. The patches we ship address every assumption that breaks:

| Desktop assumption | True on cmd? | True on iOS? | Patch |
|---|---|---|---|
| `_multiprocessing` C extension is available | ✅ | ❌ — iOS bans `fork()` so BeeWare omits it | Werkzeug `multiprocessing.Value` falls back to a `threading.Lock`-backed counter |
| `signal.signal()` works from any thread | ✅ | ❌ — only the main interpreter thread, and Python isn't on it | Streamlit and Werkzeug skip signal-handler registration on non-main thread |
| `fork()` is available for the reloader | ✅ | ❌ | Werkzeug reloader auto-disables on iOS / worker thread |
| Server can write PID/socket files to `/tmp` | ✅ | ⚠️ — sandbox-relative `$TMPDIR` only | Already works (everything uses `tempfile.gettempdir()`) |
| Ctrl+C delivers SIGINT to the foreground process | ✅ | ❌ — Python embedded in iOS app, no PTY signal flow | offlinai_shell installs a watchdog that polls a signal file written by Swift on Ctrl+C / Stop, then injects `KeyboardInterrupt` into the script thread via `PyThreadState_SetAsyncExc`. Werkzeug + Streamlit also poll the same file and call their clean `srv.shutdown()` / `server.stop()` directly. |

---

## Werkzeug

Standalone bundle (no Flask required). Use it for:
- Tiny WSGI apps without a framework (`from werkzeug.wrappers import Request, Response`)
- The dev server (`werkzeug.serving.run_simple`)
- URL routing primitives (`werkzeug.routing.Map`)
- Anything Flask gives you minus the framework layer

```python
from werkzeug.wrappers import Request, Response
from werkzeug.serving import run_simple

def app(environ, start_response):
    request = Request(environ)
    response = Response(f"Hello, {request.args.get('name', 'world')}!")
    return response(environ, start_response)

run_simple("127.0.0.1", 5000, app)
```

**Patches:**

1. **`multiprocessing.Value` fallback** — [werkzeug/debug/__init__.py](../app_packages/site-packages/werkzeug/debug/__init__.py).
   The debug-mode failed-pin counter calls `multiprocessing.Value("B")`. On iOS the lazy `import _multiprocessing` deep inside `Value()` fails. We wrap `Value` to fall back to a `threading.Lock`-backed `_ValueFallback` class with the same `.value` / `.get_lock()` API.

2. **Reloader auto-disable** — [werkzeug/serving.py](../app_packages/site-packages/werkzeug/serving.py).
   The reloader needs `fork()` (forbidden on iOS) and `signal.signal(SIGTERM)` (main thread only — and Python isn't there). When `sys.platform == "ios"` OR the current thread isn't the main thread, `use_reloader` is force-disabled. Server still runs; you just lose auto-reload on file changes.

3. **Preview-signal hook** — same file. When `run_simple` starts the server, it writes `$TMPDIR/latex_signals/preview_request.txt` with the URL. CodeBench's editor polls that file at 100 ms and loads the URL into the preview panel.

4. **Clean-shutdown hook** — same file. A daemon thread polls `$TMPDIR/offlinai_interrupt` (the same file the Ctrl+C watchdog writes) and calls `srv.shutdown()` cleanly when it appears. This is the no-traceback path; the generic `KeyboardInterrupt` injection runs in parallel as backup.

---

## Flask

```python
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route("/")
def index():
    return "<h1>Hello from iOS</h1>"

@app.route("/api/echo", methods=["POST"])
def echo():
    return jsonify(received=request.get_json())

app.run(host="127.0.0.1", port=5000, debug=False)
```

**Notes:**
- `debug=True` works thanks to the werkzeug `_multiprocessing` fallback patch.
- Hot-reload via `debug=True` is silently disabled (see above) — file changes won't reload the app, you have to restart it.
- All Flask features (blueprints, sessions, templates, send_from_directory, error handlers) work unchanged.

---

## Dash

Plotly-based dashboards. **Recommended path for any data-viz UI.**

```python
import dash
from dash import Dash, html, dcc, Input, Output
import plotly.express as px
import pandas as pd

app = Dash(__name__)
app.layout = html.Div([
    dcc.Slider(id="n", min=10, max=200, value=50),
    dcc.Graph(id="chart"),
])

@app.callback(Output("chart", "figure"), Input("n", "value"))
def render(n):
    return px.line(x=range(n), y=[i*i for i in range(n)])

app.run(host="127.0.0.1", port=8050, debug=False)
```

**Notes:**
- Includes `dcc`, `html`, `dash_table`, callback context, pattern-matching callbacks (`ALL`, `MATCH`), client-side callbacks, `dcc.Store`, `dcc.Interval`.
- `dash.html` covers the standard HTML primitives; styling via inline `style={}` dicts.
- For dark-mode-aware iOS WKWebView, override `app.index_string` to force a light color scheme — otherwise default-styled components render black-on-black:
  ```python
  app.index_string = """
  <!DOCTYPE html><html><head>{%metas%}
  <meta name="color-scheme" content="light">
  <title>{%title%}</title>{%favicon%}{%css%}
  <style>html, body { background: #fff; color: #1a1a1a; color-scheme: light; }
         input, textarea, select, button { background: #fff; color: #1a1a1a; }
  </style></head><body>{%app_entry%}<footer>{%config%}{%scripts%}{%renderer%}</footer></body></html>
  """
  ```
- Comprehensive feature test: [`dash_test.py`](../dash_test.py) — 6 tabs covering text, data, charts, inputs, layout, state/callbacks.

---

## Streamlit

Declarative script-as-app. Each interaction re-runs the whole script top-to-bottom; widgets persist state automatically.

```python
import streamlit as st
import pandas as pd

st.title("On-device dashboard")
n = st.slider("Rows", 10, 1000, 100)
df = pd.DataFrame({"x": range(n), "x²": [i*i for i in range(n)]})
st.line_chart(df.set_index("x"))
st.dataframe(df, use_container_width=True)
```

**Run it:**

Streamlit normally uses `streamlit run script.py` from the shell. That works in CodeBench's terminal, but for a self-contained launcher you can also bootstrap programmatically:

```python
# launcher.py
from streamlit.web import bootstrap
from streamlit import config as st_config

st_config.set_option("server.port", 8501)
st_config.set_option("server.address", "127.0.0.1")
st_config.set_option("server.headless", True)
st_config.set_option("server.runOnSave", False)        # watchdog flaky on iOS
st_config.set_option("browser.gatherUsageStats", False)

bootstrap.run("my_streamlit_app.py", is_hello=False, args=[], flag_options={})
```

**Patches:**

1. **Signal-handler skip** — [streamlit/web/bootstrap.py](../app_packages/site-packages/streamlit/web/bootstrap.py) `_set_up_signal_handler`.
   On non-main thread or `sys.platform == "ios"`, skips `signal.signal(SIGTERM/SIGINT/SIGQUIT/SIGBREAK)`. Server runs; you just lose POSIX-signal-driven graceful shutdown (Ctrl+C now uses the file-signal path instead).

2. **Preview-signal hook** — same file, `_on_server_start`.
   Writes `$TMPDIR/latex_signals/preview_request.txt` so CodeBench auto-loads the page.

3. **Clean-shutdown hook** — same file.
   Daemon thread polls `$TMPDIR/offlinai_interrupt` and schedules `server.stop()` on the asyncio loop's thread via `call_soon_threadsafe`.

**Bundled extras:** the SafeArray pickling fix in `PythonRuntime.swift` is critical for `@st.cache_data` — without it, any DataFrame containing numpy columns fails to pickle (numpy arrays inherit a `SafeArray` subclass injected at runtime, and pickle can't find `__main__.SafeArray` when unpickling). The fix gives SafeArray a `__reduce__` that pickles as plain `ndarray`.

**Limits:**
- `st.file_uploader` works for small files; large uploads can OOM since iOS doesn't stream-process them.
- Audio/video components depend on iOS WKWebView codec support — `st.video` with H.264 + MP4 container works, others may not.
- Hot-reload (`server.runOnSave=True`) — watchdog file events flaky in iOS sandbox. Set it to `False` and click Force Re-Run instead.

Comprehensive feature test: [`streamlit_test.py`](../streamlit_test.py) — 8 tabs covering text, data, charts, inputs, layout, state/cache, progress/forms, misc.

---

## Tornado

Async HTTP / WebSocket framework. **Streamlit's transport layer** is its biggest user here, but you can also use it standalone:

```python
import tornado.ioloop
import tornado.web

class Handler(tornado.web.RequestHandler):
    def get(self):
        self.write({"hello": "iOS"})

app = tornado.web.Application([(r"/", Handler)])
app.listen(8000, address="127.0.0.1")
print("http://127.0.0.1:8000")
tornado.ioloop.IOLoop.current().start()
```

**Notes:**
- The macOS `tornado/speedups.abi3.so` is stripped during bundling — it's a Mach-O for the wrong platform. Tornado's `tornado/util.py` falls back to a pure-Python `_websocket_mask_python` via `try/except ImportError`. The fallback is ~3× slower for WebSocket frame masking but negligible at dashboard data rates.
- No signal handlers installed by default — works on any thread.

---

## How Ctrl+C / Stop works on iOS

Three paths to interrupt a running web server, fired in parallel — whichever lands first wins:

1. **PyErr_SetInterrupt + 0x03 to PTY** (Swift, original) — only reaches the main interpreter thread and stdin readers. Doesn't help for `python script.py` (script runs on a worker thread) or for servers blocked in `socket.accept`.

2. **File signal + watchdog + `PyThreadState_SetAsyncExc`** ([offlinai_shell.py](../app_packages/site-packages/offlinai_shell.py)) — Swift writes `$TMPDIR/offlinai_interrupt`. The watchdog (started before every `runpy.run_path`) polls every 100 ms; on detection it injects `KeyboardInterrupt` into the script's thread AND all worker threads, then re-injects every 500 ms for 5 s to catch syscall returns.

3. **Framework-specific clean shutdown** (werkzeug + streamlit patches) — the same signal file is polled by daemon threads inside each framework, which call the framework's own clean shutdown (`srv.shutdown()` / `server.stop()`). This is the no-traceback path.

Together: one Ctrl+C tap stops the server within ~500 ms with a clean exit log.

---

## Preview panel

When any of these frameworks start a server, the URL is auto-loaded into CodeBench's preview panel (right side of the editor). Same mechanism we use for matplotlib charts and LaTeX previews — write the path/URL to `$TMPDIR/latex_signals/preview_request.txt`, Swift polls it every 100 ms and routes `http://` paths into the existing WKWebView preview controller.

You can also trigger a preview load manually from any script:

```python
import os, tempfile
sig_dir = os.path.join(tempfile.gettempdir(), "latex_signals")
os.makedirs(sig_dir, exist_ok=True)
with open(os.path.join(sig_dir, "preview_request.txt"), "w") as f:
    f.write("http://127.0.0.1:9999/\n")
```

---

## Putting it together

A complete iOS-ready Flask example with all the patches transparent:

```python
from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
    return """
    <!DOCTYPE html><html><head>
    <meta name='color-scheme' content='light'>
    <style>body { font-family: sans-serif; padding: 20px; }</style>
    </head><body><h1>Hello from iOS</h1><p>Running on Werkzeug.</p>
    </body></html>
    """

# debug=True works (multiprocessing fallback), reloader auto-disabled,
# preview auto-loads, Ctrl+C / Stop terminates cleanly.
app.run(host="127.0.0.1", port=5000, debug=True)
```

For Dash, see [`dash_test.py`](../dash_test.py); for Streamlit, see [`streamlit_test.py`](../streamlit_test.py). Both walk through every commonly-used widget.
