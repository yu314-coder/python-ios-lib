# Tornado — async HTTP + WebSocket framework

**Version:** 6.5.5  
**Type:** Pure Python (macOS C extension stripped)  
**SPM target:** `Tornado`  
**Total Python modules:** 73

The async web framework Streamlit's transport layer is built on. Standalone-usable for any WebSocket or async-HTTP work — chat apps, server-sent events, long-polling.

## Modules

### HTTP server / client

| Module | What it does |
|---|---|
| `tornado.httpserver` | `HTTPServer` — non-blocking HTTP/1.1 server |
| `tornado.httpclient` | Async HTTP client (`AsyncHTTPClient`, `HTTPRequest`, `HTTPResponse`); pluggable transports |
| `tornado.simple_httpclient` | Pure-Python HTTP client transport (default) |
| `tornado.curl_httpclient` | libcurl-backed transport (not bundled — pure-Python only) |
| `tornado.http1connection` | HTTP/1.1 connection state machine |
| `tornado.httputil` | URL parsing, query/form parsing, multipart, cookies, `HTTPHeaders` |

### Web framework

| Module | What it does |
|---|---|
| `tornado.web` | `RequestHandler`, `Application`, `URLSpec`, decorators (`authenticated`, `addslash`, `removeslash`), `StaticFileHandler`, `RedirectHandler`, `ErrorHandler` |
| `tornado.routing` | Request routing — `Router`, `RuleRouter`, `PathMatches`, `URLSpec` |
| `tornado.template` | Tornado's templating engine — Python-like syntax, autoescape, includes, blocks |
| `tornado.escape` | `xhtml_escape`, `url_escape`, `json_encode`, `to_unicode`, `recursive_unicode`, `linkify` |
| `tornado.auth` | OAuth1/OAuth2 mix-ins (Google, Facebook, Twitter, GitHub) |

### WebSockets

| Module | What it does |
|---|---|
| `tornado.websocket` | `WebSocketHandler`, `websocket_connect` — server + client. **Streamlit's main runtime dependency.** Frame masking uses the Python fallback (the C `speedups.abi3.so` is macOS-only and was stripped). |

### IOLoop + concurrency

| Module | What it does |
|---|---|
| `tornado.ioloop` | `IOLoop` — the event loop. Modern code uses `asyncio` directly, but legacy Tornado code calls `IOLoop.current()`, `IOLoop.add_callback`, `IOLoop.run_sync` |
| `tornado.gen` | `@gen.coroutine`, `gen.sleep`, `gen.multi` — the old generator-based async API |
| `tornado.concurrent` | `Future`, `chain_future`, executor adapters |
| `tornado.locks` | `Event`, `Condition`, `Semaphore`, `Lock` — async-aware |
| `tornado.queues` | `Queue`, `PriorityQueue`, `LifoQueue` — async-aware |

### TCP / networking primitives

| Module | What it does |
|---|---|
| `tornado.tcpserver` | `TCPServer` base (HTTPServer inherits from it) |
| `tornado.tcpclient` | `TCPClient` — async connection establishment |
| `tornado.netutil` | `bind_sockets`, `Resolver`, `add_accept_handler`, SSL helpers |
| `tornado.iostream` | `IOStream`, `SSLIOStream` — non-blocking socket wrappers |

### Logging + processes + utilities

| Module | What it does |
|---|---|
| `tornado.log` | Color-coded log formatter (`enable_pretty_logging`) |
| `tornado.process` | `Subprocess`, `fork_processes`, `task_id` (not useful on iOS — fork is blocked) |
| `tornado.autoreload` | Source-watch + restart (not useful on iOS — fork is blocked) |
| `tornado.options` | `define`, `options` — CLI/file-driven config |
| `tornado.locale` | Translation framework (gettext-like) |
| `tornado._locale_data` | Locale name database |
| `tornado.util` | `import_object`, `unicode_type`, `errno_from_exception`, `Configurable`. **iOS: `_websocket_mask_python` fallback runs here.** |
| `tornado.wsgi` | `WSGIContainer` — adapt any WSGI app (Flask, Werkzeug) onto Tornado's IOLoop |
| `tornado.testing` | `AsyncTestCase`, `gen_test`, `AsyncHTTPTestCase` |

### `tornado.platform` — IOLoop / asyncio integration

| Submodule | Provides |
|---|---|
| `platform.asyncio` | `AsyncIOMainLoop`, `AsyncIOLoop`, `to_tornado_future`, `to_asyncio_future` — bidirectional asyncio bridge (this is what modern Tornado uses by default) |
| `platform.caresresolver` | c-ares resolver (not bundled) |
| `platform.twisted` | Twisted reactor bridge (not bundled) |

## iOS notes

**Stripped:** `tornado/speedups.abi3.so` (macOS-only Mach-O — wouldn't load). The lib's `util.py` has a `try/except ImportError` fallback to `_websocket_mask_python`. Perf hit only affects WebSocket frame masking — negligible at dashboard data rates.

**fork-dependent modules left in place but non-functional:**
- `tornado.autoreload` — auto-restart on file changes
- `tornado.process.fork_processes` — pre-fork worker model

Don't call these on iOS — they'll fail. The single-process async server is the iOS happy path.

## Standalone example

```python
import asyncio
import tornado.web

class MainHandler(tornado.web.RequestHandler):
    def get(self):
        self.write({"hello": "iOS", "framework": "tornado"})

class EchoWebSocket(tornado.websocket.WebSocketHandler):
    def on_message(self, msg):
        self.write_message(f"echo: {msg}")

async def main():
    app = tornado.web.Application([
        (r"/", MainHandler),
        (r"/ws", EchoWebSocket),
    ])
    app.listen(8888, address="127.0.0.1")
    print("http://127.0.0.1:8888  (ws://127.0.0.1:8888/ws)")
    await asyncio.Event().wait()  # run forever

asyncio.run(main())
```

See [web-stack.md](web-stack.md) for how Streamlit consumes Tornado and what Ctrl+C / Stop handling looks like across the whole stack.
