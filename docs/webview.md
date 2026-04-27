# pywebview (CodeBench shim)

> **Version:** 5.4.0-codebench-shim  | **Type:** Pure-Python shim (~470 lines)  | **Status:** Fully working — windows route into the host app's preview pane via file IPC

CodeBench-flavoured replacement for the [pywebview](https://pywebview.flowrl.com/)
package. Real pywebview spawns native OS windows (Cocoa / GTK / Qt) and
embeds a system web view — none of that works in our iOS sandbox (no
fork/exec, no AppKit access, no separate process). This shim accepts
the same `webview.create_window(...)` / `webview.start()` calls and
routes them into the host app's preview pane via the same file-IPC
channel the LaTeX engine uses.

```
   user script                   shim writes a tiny HTML file
   ──────────                    ──────────────────────────────
   import webview         ──►    $TMPDIR/pywebview_scratch/
   webview.create_window(             page_<uuid>.html
       "Hello",                  
       html="<h1>x</h1>")        atomic-rename a path-pointer to
   webview.start()           ──► $TMPDIR/latex_signals/preview_request.txt

                                              │  Swift polls @ 100 ms
                                              ▼
                                      LaTeXEngine.onPreviewRequest
                                              │
                                              ▼
                                   CodeEditorViewController
                                       outputWebView.loadFileURL(...)
```

---

## When to add this target

You want to embed an HTML/CSS/JS UI in your iOS app from Python without
writing any Swift, OR you have an existing pywebview script and want it
to run on iOS unchanged.

```swift
.dependencies = [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", from: "1.0.0"),
],
.target(name: "MyApp", dependencies: [
    .product(name: "PyWebView", package: "python-ios-lib"),
])
```

The host app must include a Python preview pane wired to the
`preview_request.txt` signal file (see CodeBench's
`CodeEditorViewController.showImageOutput(path:)` for a reference).

---

## Quick start

```python
import webview

# Show inline HTML
webview.create_window("Hello", html="<h1 style='color:dodgerblue'>Hi</h1>")
webview.start()

# Show a URL — http(s):// gets a meta-refresh redirect page,
# file:// and absolute paths render directly so sibling CSS/JS resolve
webview.create_window("Docs", "https://docs.python.org")
webview.create_window("App",  "/path/to/Documents/myapp/index.html")

# Mutate after creation
w = webview.create_window("Live", html="<div id='x'>0</div>")
for i in range(10):
    w.evaluate_js(f"document.getElementById('x').textContent = {i}")
    time.sleep(1)
```

---

## API surface

| Module-level | Per-Window |
|---|---|
| `webview.create_window(title, url=…, html=…, **kwargs)` → `Window` | constructor (called by create_window) |
| `webview.start(func=None, args=())` | — |
| `webview.windows` (list of all created Window objects) | — |
| `webview.token` (random per-process hex) | — |
| `webview.set_cookie(name, value, **kw)` | `w.set_cookie(name, value, **kw)` |
| `webview.get_cookies(url=None)` | `w.get_cookies()` (auto-scoped to current URL) |
| `webview.delete_cookie(name, domain="", path="/")` | `w.delete_cookie(name, domain="", path="/")` |
| `webview.clear_cookies(domain="")` | `w.clear_cookies(domain="")` |
| `webview.save_cookies(path=DEFAULT_COOKIE_FILE)` | `w.save_cookies(path)` |
| `webview.load_cookies(path, *, replace=False)` | `w.load_cookies(path, replace=False)` |
| `webview.cookies_autopersist = True` | (module-level toggle) |

`Window` methods:

| Method | What it does |
|---|---|
| `w.load_url(url)` | Navigate. http(s) → meta-refresh; file:// or path → direct |
| `w.load_html(content)` | Replace content with raw HTML |
| `w.evaluate_js(script, callback=None)` | Append `<script>` and reload (NOT a real eval — no return-value bridge) |
| `w.set_title(title)` / `w.title` | Cached title (preview pane has no title bar) |
| `w.get_current_url()` | `file://` URL of last scratch HTML |
| `w.get_size()` | `(0, 0)` — preview is pane-sized |
| `w.show()` / `w.hide()` / `w.destroy()` | Re-signal / blank / mark dead |

---

## Cookie management

The shim maintains a **Python-side cookie jar** independent of the
WKWebView store. When `load_url()` runs, jar cookies that scope to the
URL (browser-style domain/path/secure rules) get auto-injected into
the loaded page via `<script>document.cookie = "…"</script>` so the
WKWebView store sees them too.

```python
import webview

# Set
webview.set_cookie("session", "abc123",
                   domain="example.com",
                   path="/",
                   expires=time.time() + 86400,
                   secure=True,
                   samesite="Lax")

# Get — all cookies in the jar
all_cookies = webview.get_cookies()

# Get — only those that would scope to a URL
relevant = webview.get_cookies("https://example.com/api")

# Delete one
webview.delete_cookie("session", domain="example.com")

# Delete all for a domain (suffix-match: also catches .api.example.com)
webview.clear_cookies("example.com")

# Persist to disk
webview.save_cookies()                               # → ~/Documents/.codebench-pywebview-cookies.json
webview.save_cookies("/path/my-cookies.json")        # custom path
webview.load_cookies()                               # restore (missing file = 0, no error)

# Auto-persist on every change
webview.cookies_autopersist = True
webview.set_cookie("foo", "bar")     # ← also writes to default file
```

**Cookie shape**:

```python
{
    "name": str, "value": str,
    "domain": str, "path": str,
    "expires": float | None,        # Unix timestamp
    "secure": bool, "httponly": bool,
    "samesite": str,                # "Lax" / "Strict" / "None"
}
```

---

## Verbose logging

Every operation prints a compact one-line `[pywebview]` log to stdout
so you can trace what the shim is doing in the in-app terminal:

```
[pywebview] create_window(uid=1e2dc5bd, title='T', url='https://example.com')
[pywebview]   injecting 1 cookie(s) for example.com: ['session']
[pywebview] load_url(uid=1e2dc5bd, url='https://example.com')  → http(s) → meta-refresh redirect page
[pywebview]   scratch html → .../pywebview_scratch/redirect_c9539991.html
[pywebview]   signal → .../latex_signals/preview_request.txt  (412 bytes)
[pywebview] start()  — 1 window(s) registered, returning immediately
```

Silence with:

```bash
export CODEBENCH_PYWEBVIEW_QUIET=1
```

---

## What's stubbed (calls succeed silently with a one-line warning)

- **`js_api=...`** — JS-to-Python callbacks need a WKScriptMessage
  bridge; the shim doesn't ship one. The window still renders; calls
  into your `js_api` object from JS just no-op.
- **Confirmation / file dialogs** — no `webview.confirmation_dialog`,
  `webview.file_dialog`, etc. Use the host app's UIKit alerts instead.
- **Window chrome flags** — `fullscreen`, `frameless`, `on_top`,
  `resizable`, `transparent` are accepted as kwargs (no AttributeError)
  but ignored. The preview pane's appearance is host-app-controlled.
- **Multiple windows** — the API works (you can create as many as you
  want), but the preview pane shows only the most-recently-signalled
  one. Real pywebview displays each in its own OS window.
- **`webview.GUI` selection** — `cocoa` / `qt` / `gtk` choice doesn't
  apply; backend is fixed to `webview.guilib = "codebench"`.

## What's NOT supported

- System-tray menus, native menubars
- Drag-and-drop from the OS into the web view
- WebSocket inspection / DevTools attach
- HTTP cookie store sharing with `URLSession` / Safari (the WKWebView
  store is separate; cookies the shim sets via JS land in WKWebView's
  store but won't be visible to other iOS network stacks)

---

## How URLs become pages

| You call | Shim does |
|---|---|
| `load_url("https://example.com")` | Writes a meta-refresh redirect HTML, signals it. WebKit follows the refresh to the real URL. |
| `load_url("file:///path/index.html")` | Strips the `file://`, signals the path directly so sibling CSS/JS/img resolve via `loadFileURL(allowingReadAccessTo: parent)`. |
| `load_url("/abs/path/index.html")` | Same as `file://` — direct signal. |
| `load_url("custom://...")` | Best-effort: build a redirect page and let WebKit decide. |
| `load_html("<h1>x</h1>")` | Writes raw HTML to a scratch file, signals it. |
| `evaluate_js("...")` | Appends `<script>try { ... } catch(_e){}</script>` to the current scratch HTML, re-signals. |

Scratch files live in `$TMPDIR/pywebview_scratch/` and accumulate over
the session. Auto-pruned when iOS reaps app temp storage; you can
manually clear with `import shutil; shutil.rmtree($TMPDIR/pywebview_scratch)`.

---

## Limitations

- **No HTTP/2 / HTTP/3 negotiation control** — that's the underlying
  WKWebView's call.
- **JS execution timing** — `evaluate_js` rewrites the file on disk
  and re-signals; the WebView's reload takes ~50-200 ms. For
  high-frequency animations, do the work inside the page's existing
  JS rather than calling `evaluate_js` per frame.
- **No cookie expiry GC** — expired cookies stay in the jar until
  `clear_cookies()` (their `_cookie_matches_url` filter still skips
  them, so they don't get sent; they just take up jar space).
- **No `Set-Cookie` parsing from server responses** — the JS-injected
  cookies set via `document.cookie =` end up in WKWebView's store, but
  cookies returned in HTTP response headers stay there too and AREN'T
  reflected back into the Python jar. One-way for now.

---

## Build provenance

Single Python file at `app_packages/site-packages/webview/__init__.py`,
470 lines. No native extensions. Uses the stdlib `urllib.parse`,
`tempfile`, `threading`, `json`, `email.utils`. Runs on any Python 3.8+.
