# urllib3 — HTTP client library

**Version:** 2.6.3
**Type:** Pure Python (links against stdlib `ssl` / OpenSSL)
**SPM target:** Bundled in the Python framework
**Total modules:** 36

The HTTP client library that backs `requests`. You can use it directly
when you want connection pooling, retry strategies, custom adapters,
streaming uploads/downloads, or chunked-encoding control without the
extra `requests` layer.

For most use cases, prefer `requests` (see [requests.md](requests.md))
— urllib3 is the lower-level tool.

---

## Modules

### Top-level

| Module | What it does |
|---|---|
| `urllib3.__init__` | Re-exports `PoolManager`, `ProxyManager`, `HTTPConnectionPool`, `HTTPSConnectionPool`, `HTTPResponse`, `Retry`, `Timeout`, `make_headers` |
| `urllib3._version` | `__version__ = "2.6.3"` |
| `urllib3._base_connection` | `_TYPE_BODY` type alias + base socket helpers |
| `urllib3._collections` | `HTTPHeaderDict` (case-insensitive multi-value) |
| `urllib3._request_methods` | Mixin providing `.request()`, `.get()`, `.post()`, etc. on pools |
| `urllib3.connection` | `HTTPConnection`, `HTTPSConnection` (low-level socket wrappers) |
| `urllib3.connectionpool` | `HTTPConnectionPool`, `HTTPSConnectionPool`, `connection_from_url` |
| `urllib3.exceptions` | `HTTPError`, `MaxRetryError`, `TimeoutError`, `SSLError`, `InsecureRequestWarning`, 30+ others |
| `urllib3.fields` | `RequestField` (multipart form field) |
| `urllib3.filepost` | `encode_multipart_formdata` — for file uploads |
| `urllib3.poolmanager` | `PoolManager`, `ProxyManager`, `proxy_from_url` |
| `urllib3.response` | `HTTPResponse`, `BaseHTTPResponse` — `.data`, `.json()`, `.stream()`, `.read()` |

### `urllib3.util`

| Submodule | Provides |
|---|---|
| `util.__init__` | Re-exports `make_headers`, `Retry`, `Timeout`, `Url`, `parse_url` |
| `util.connection` | Socket helpers (`create_connection`, `is_connection_dropped`) |
| `util.proxy` | Proxy-URL handling |
| `util.request` | Header builders (`make_headers`) |
| `util.response` | Header/response helpers |
| `util.retry` | `Retry` class — backoff, status_forcelist, allowed_methods, history |
| `util.ssl_` | SSL context creation (`create_urllib3_context`, ALPN, hostname verification) |
| `util.ssl_match_hostname` | Hostname-cert match (stdlib fallback) |
| `util.ssltransport` | `SSLTransport` — TLS-in-TLS (for proxying HTTPS through HTTPS proxy) |
| `util.timeout` | `Timeout` — connect/read timeout pair |
| `util.url` | `Url` namedtuple + `parse_url` + `Url.url` reconstruction |
| `util.util` | `to_bytes`, `to_str`, generic helpers |
| `util.wait` | `wait_for_read` / `wait_for_write` (cross-platform select wrapper) |

### `urllib3.contrib`

| Submodule | Provides |
|---|---|
| `contrib.__init__` | Empty (just a package marker) |
| `contrib.pyopenssl` | `inject_into_urllib3()` — swap stdlib ssl for `pyOpenSSL`. **iOS-irrelevant** (we use stdlib ssl) |
| `contrib.socks` | `SOCKSProxyManager` — SOCKS4/5 proxy support (requires `PySocks`) |
| `contrib.emscripten` | Emscripten/WASM fetch backend (`fetch.py`, `connection.py`, `response.py`, `request.py`, `emscripten_fetch_worker.js`). **iOS-irrelevant** — different platform |

### `urllib3.http2`

| Submodule | Provides |
|---|---|
| `http2.__init__` | Optional HTTP/2 enablement |
| `http2.connection` | HTTP/2 connection implementation (requires `h2` package) |
| `http2.probe` | HTTP/2 ALPN probe helper |

By default urllib3 2.x is HTTP/1.1. To enable HTTP/2:
```python
import urllib3.http2
urllib3.http2.inject_into_urllib3()
```
Requires `pip install h2` — bundled? Check `import h2` first.

---

## Quick start

```python
import urllib3

http = urllib3.PoolManager()

r = http.request("GET", "https://httpbin.org/get",
                 fields={"q": "ios"},
                 headers={"User-Agent": "MyApp/1.0"},
                 timeout=10)

print(r.status)                    # 200
print(r.headers["Content-Type"])   # 'application/json'
print(r.data[:200])                # bytes — first 200
print(r.json())                    # parse JSON
```

```python
# POST JSON
import json
r = http.request("POST", "https://httpbin.org/post",
                 body=json.dumps({"x": 1}).encode(),
                 headers={"Content-Type": "application/json"})

# Streaming download
with http.request("GET", "https://example.com/big.zip",
                  preload_content=False) as r:
    with open("/path/Documents/big.zip", "wb") as f:
        for chunk in r.stream(1 << 16):
            f.write(chunk)
    r.release_conn()
```

```python
# Connection pool tuning
http = urllib3.PoolManager(
    num_pools=20,        # one pool per host, max 20 hosts
    maxsize=4,           # connections per pool
    block=False,         # if pool full, open a new conn (don't block)
)
```

```python
# Retries with backoff
from urllib3.util.retry import Retry

retry = Retry(
    total=3,
    backoff_factor=0.5,           # 0.5, 1, 2, 4 second waits
    status_forcelist=[502, 503, 504],
    allowed_methods=["GET", "HEAD"],
)
http = urllib3.PoolManager(retries=retry)
```

```python
# Multipart file upload
fields = {
    "file": ("report.pdf", open("/path/report.pdf", "rb").read(), "application/pdf"),
    "name": "Annual Report",
}
r = http.request("POST", "https://example.com/upload", fields=fields)
```

---

## SSL / TLS

Same story as `requests` — uses Apple's Network framework via the
underlying socket layer. The default trusted CA bundle comes from
`certifi`, NOT from iOS's system trust store.

```python
import certifi
http = urllib3.PoolManager(
    cert_reqs="CERT_REQUIRED",
    ca_certs=certifi.where(),
)
```

Custom self-signed cert (e.g. internal API):

```python
http = urllib3.PoolManager(
    cert_reqs="CERT_REQUIRED",
    ca_certs="/path/Documents/internal-ca.pem",
)
```

Disable verification (DEV ONLY):

```python
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
http = urllib3.PoolManager(cert_reqs="CERT_NONE")
```

Minimum TLS version:
```python
from ssl import TLSVersion
http = urllib3.PoolManager(ssl_minimum_version=TLSVersion.TLSv1_3)
```

---

## When to use urllib3 directly vs requests

| Need | Use |
|---|---|
| One-off GET/POST, sessions, cookies | `requests` (simpler API) |
| Streaming a 500MB upload to S3 | `urllib3` (tighter memory control) |
| Custom retry strategy with backoff | `urllib3` (Retry object is more granular) |
| Connection pooling for many hosts | `urllib3` (PoolManager is the primitive) |
| HTTP/2 | `urllib3.http2.inject_into_urllib3()` (with `h2` installed) |
| Async | Neither — both sync. Use `aiohttp` (pure Python, works on iOS) |
| SOCKS5 proxy | `urllib3.contrib.socks.SOCKSProxyManager` (needs PySocks) |

---

## iOS sandbox notes

- Same as `requests`: no ATS gating, network calls go through urllib3 →
  raw POSIX sockets (which iOS doesn't intercept).
- VPN / per-app proxies / cellular vs Wi-Fi DNS selection: all handled
  by the system socket stack; urllib3 sees them transparently.
- Long-running calls count against the host app's background time
  budget. Pair with `BackgroundExecutionGuard` for ops > 30 s.
- `urllib3.contrib.emscripten` is dead code on iOS — the discovery
  guard checks for the Emscripten runtime and skips the import on iOS.

---

## Limitations

- **HTTP/2 not enabled by default** — `pip install h2` + manual
  injection required. The bundled `urllib3.http2/*` modules are
  there but inert.
- **No async** — sync only. Run inside `DispatchQueue.global().async`
  or a Python thread to keep the UI responsive.
- **TLS protocol pinning is partial** — `ssl_minimum_version` works;
  cipher-suite pinning at the urllib3 layer is best-effort (Apple's
  stack has final say).
- **SOCKS proxy needs `PySocks`** (`pip install PySocks` — pure Python,
  works).

---

## Notes

- This is the package `requests` calls into. If you `import requests`
  in your script, you're using urllib3 transitively.
- `urllib3.disable_warnings(...)` is the only way to silence the
  default `InsecureRequestWarning` when `cert_reqs="CERT_NONE"`.
- For HTML scraping, pair with `bs4` (BeautifulSoup): `urllib3` →
  `r.data` → `BeautifulSoup(r.data, "html.parser")`.
