# Werkzeug — WSGI utility library

**Version:** 3.1.x  
**Type:** Pure Python  
**SPM target:** `Werkzeug`  
**Auto-included by:** Flask, Dash  
**Total Python modules:** 52

The WSGI foundation everything else is built on. You rarely import it directly — Flask and Dash both use it internally. But if you want a tiny HTTP app without a framework, or you need URL routing, request parsing, or the dev server, Werkzeug is what you reach for.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `werkzeug.__init__` | Re-exports `Request`, `Response`, `run_simple`, `redirect`, `abort` |
| `werkzeug.serving` | **Dev HTTP server** (`run_simple`). iOS-patched: reloader auto-disabled on worker thread, preview-signal + clean-shutdown hooks |
| `werkzeug.wsgi` | WSGI helpers: `pop_path_info`, `get_current_url`, `wrap_file` |
| `werkzeug.urls` | URL parsing/joining (`url_quote`, `url_unquote`, `url_decode`, `url_encode`) |
| `werkzeug.http` | HTTP date/header parsing (`parse_date`, `parse_etags`, `parse_options_header`) |
| `werkzeug.formparser` | Multipart form + file-upload parsing |
| `werkzeug.utils` | `redirect`, `secure_filename`, `cached_property`, `header_property` |
| `werkzeug.security` | Password hashing (`generate_password_hash`, `check_password_hash`), `safe_join`, `safe_str_cmp` |
| `werkzeug.exceptions` | `HTTPException` hierarchy: `BadRequest`, `NotFound`, `Forbidden`, 30+ others |
| `werkzeug.local` | Thread/coroutine-local proxies (`Local`, `LocalProxy`) — how Flask's `request` global works |
| `werkzeug.test` | WSGI test client + test request builders |
| `werkzeug.testapp` | Tiny demo app for smoke-testing servers |
| `werkzeug.user_agent` | User-agent string parser |
| `werkzeug._internal` | Implementation details — don't import directly |
| `werkzeug._reloader` | Auto-reloader on file changes. **iOS-auto-disabled** (needs `fork()`, signal) |

### `werkzeug.routing` — URL routing

| Submodule | Provides |
|---|---|
| `routing.map` | `Map` (the URL map) |
| `routing.rules` | `Rule` (single route) |
| `routing.converters` | Type converters for URL variables (`int`, `float`, `uuid`, `path`) |
| `routing.matcher` | The matching engine |
| `routing.exceptions` | `RoutingException`, `RequestRedirect`, `BuildError` |

### `werkzeug.wrappers` — Request / Response objects

| Submodule | Provides |
|---|---|
| `wrappers.request` | `Request` — WSGI environ wrapper with `.args`, `.form`, `.files`, `.headers`, `.json` |
| `wrappers.response` | `Response` — WSGI-compatible response builder |

### `werkzeug.datastructures` — Specialized dict/list types

| Submodule | Provides |
|---|---|
| `datastructures.headers` | `Headers`, `EnvironHeaders` (multi-value, case-insensitive) |
| `datastructures.structures` | `MultiDict`, `ImmutableMultiDict`, `OrderedMultiDict`, `TypeConversionDict` |
| `datastructures.file_storage` | `FileStorage` (uploaded-file wrapper) |
| `datastructures.cache_control` | `CacheControl` parsed cache-control header |
| `datastructures.range` | `Range`, `ContentRange` (HTTP Range/Content-Range parsing) |
| `datastructures.accept` | `Accept`, `MIMEAccept`, `LanguageAccept` (Accept header parsing) |
| `datastructures.auth` | `Authorization`, `WWWAuthenticate` |
| `datastructures.etag` | `ETags` parser |
| `datastructures.mixins` | `ImmutableDictMixin`, `UpdateDictMixin` |

### `werkzeug.debug` — Interactive debugger

| Submodule | Provides |
|---|---|
| `debug.__init__` | `DebuggedApplication` WSGI middleware. **iOS-patched:** `Value("B")` falls back to threading-lock counter |
| `debug.console` | Live in-browser Python REPL frames |
| `debug.repr` | Object repr formatting for the debug page |
| `debug.tbtools` | Traceback formatting |

### `werkzeug.middleware`

| Submodule | Provides |
|---|---|
| `middleware.proxy_fix` | `ProxyFix` — for apps behind reverse proxy |
| `middleware.dispatcher` | `DispatcherMiddleware` — mount multiple WSGI apps at different paths |
| `middleware.shared_data` | `SharedDataMiddleware` — serve static files |
| `middleware.profiler` | `ProfilerMiddleware` — cProfile per-request |
| `middleware.lint` | `LintMiddleware` — WSGI-spec compliance check |
| `middleware.http_proxy` | `ProxyMiddleware` — forward requests to upstream |

### `werkzeug.sansio` — I/O-independent primitives

Used by Werkzeug itself + downstream async wrappers.

## iOS-specific patches

See [web-stack.md § Werkzeug](web-stack.md#werkzeug) for full details.

| Patch file | Why |
|---|---|
| `werkzeug/debug/__init__.py` | `multiprocessing.Value` fallback — iOS bans `fork()`, no `_multiprocessing` |
| `werkzeug/serving.py` | Reloader auto-disable + preview-signal + clean-shutdown hooks |

## Standalone example

```python
from werkzeug.wrappers import Request, Response
from werkzeug.serving import run_simple
from werkzeug.routing import Map, Rule

url_map = Map([
    Rule("/", endpoint="index"),
    Rule("/hello/<name>", endpoint="hello"),
])

def app(environ, start_response):
    request = Request(environ)
    urls = url_map.bind_to_environ(environ)
    endpoint, args = urls.match()
    if endpoint == "index":
        body = "<h1>Hi</h1><p>Try /hello/world</p>"
    else:
        body = f"<h1>Hello, {args['name']}!</h1>"
    return Response(body, content_type="text/html")(environ, start_response)

run_simple("127.0.0.1", 5000, app)
```
