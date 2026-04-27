# Requests

> **Version:** 2.32.5  | **Type:** Pure Python  | **Status:** Fully working

The standard "HTTP for humans" library. Pure-Python — runs unmodified
on iOS. Sessions, JSON encoding/decoding, multipart uploads, cookies,
redirects, custom adapters, and SSL verification (using the bundled
`certifi` CA bundle) all work the same as on a desktop.

---

## When to add this target

Whenever you want HTTP/HTTPS calls from Python in your app — REST API
clients, file downloads, OAuth flows, webhook posts, etc.

```swift
.dependencies = [
    .package(url: "https://github.com/yu314-coder/python-ios-lib", from: "1.0.0"),
],
.target(name: "MyApp", dependencies: [
    .product(name: "Requests", package: "python-ios-lib"),
])
```

---

## Quick start

```python
import requests

r = requests.get("https://httpbin.org/get",
                 params={"q": "ios"},
                 timeout=10)

print(r.status_code)        # 200
print(r.json()["args"])     # {'q': 'ios'}
print(r.headers["Content-Type"])
```

```python
# POST JSON
r = requests.post("https://httpbin.org/post",
                  json={"hello": "world"},
                  headers={"X-App": "my-ios-app"})
print(r.json()["json"])     # {'hello': 'world'}
```

```python
# Sessions — connection pooling, cookie persistence
with requests.Session() as s:
    s.headers.update({"Authorization": "Bearer abc123"})
    r = s.get("https://api.example.com/me")
    me = r.json()

    r = s.post("https://api.example.com/projects", json={"name": "demo"})
    new_project = r.json()
```

```python
# File download (streaming so a 500 MB file doesn't OOM)
import os
home = os.path.expanduser("~/Documents")
url = "https://example.com/big.zip"
with requests.get(url, stream=True, timeout=60) as r:
    r.raise_for_status()
    with open(f"{home}/big.zip", "wb") as f:
        for chunk in r.iter_content(chunk_size=64 * 1024):
            f.write(chunk)
```

```python
# Multipart upload
with open("/path/Documents/photo.png", "rb") as f:
    r = requests.post("https://httpbin.org/post",
                      files={"image": ("photo.png", f, "image/png")})
print(r.json()["files"].keys())   # dict_keys(['image'])
```

---

## API surface

Identical to the upstream `requests` package — the library is shipped
without modification. The full reference is at
[requests.readthedocs.io](https://requests.readthedocs.io/).

Most-used entry points:

| Function | Purpose |
|---|---|
| `requests.get(url, **kwargs)` | HTTP GET |
| `requests.post(url, data, json, files, **kwargs)` | HTTP POST |
| `requests.put`, `patch`, `delete`, `head`, `options` | Other verbs |
| `requests.request(method, url, **kwargs)` | Generic |
| `requests.Session()` | Connection pool + cookie jar |
| `requests.Response` | Returned by every call |

Common `kwargs`:

| Key | Effect |
|---|---|
| `params=dict` | Query string |
| `data=dict` or `bytes` | Form-encoded or raw body |
| `json=dict` | JSON body + `Content-Type: application/json` |
| `headers=dict` | Custom headers |
| `cookies=dict` | Custom cookies |
| `files=dict` | Multipart upload |
| `auth=(user,pw)` or `HTTPBasicAuth(...)` | Authentication |
| `timeout=N` or `(connect, read)` | Per-call timeout |
| `allow_redirects=False` | Disable redirect-following |
| `stream=True` | Stream response (don't buffer all bytes) |
| `verify=True / False / "/path/ca.pem"` | TLS verification |
| `proxies={"http": "...", "https": "..."}` | Proxies |

`Response` attributes:

| Attribute | What it gives |
|---|---|
| `r.status_code` | int (e.g. 200) |
| `r.text` | str — decoded body |
| `r.content` | bytes — raw body |
| `r.json()` | parsed JSON (raises if not JSON) |
| `r.headers` | case-insensitive header dict |
| `r.url` | final URL after redirects |
| `r.cookies` | response cookies |
| `r.history` | list of intermediate redirects |
| `r.raise_for_status()` | raise HTTPError on 4xx / 5xx |
| `r.iter_content(chunk_size)` | streaming iterator |
| `r.encoding` | str (or None) |

---

## SSL / TLS

Uses urllib3's TLS via Apple's Network framework underneath. The
default trusted CA bundle is `certifi.where()` — the same one that
ships on Linux / macOS, NOT the iOS system trust store. That means:

- Any cert that's in the public Mozilla CA list verifies fine.
- iOS-specific certificates installed via Settings → Profiles
  (e.g. an enterprise / MDM cert) are NOT in `certifi`'s store.
  To trust those too, copy the cert to your app's bundle and pass
  `verify="/path/to/cert.pem"`.
- `verify=False` disables TLS verification — use only for dev /
  local testing. Real apps should never ship with this.

```python
# Custom CA bundle (e.g. self-signed cert for an internal API)
r = requests.get("https://internal.api/me",
                 verify="/path/Documents/internal-ca.pem")
```

---

## iOS sandbox notes

- **App Transport Security (ATS) doesn't block requests.** ATS only
  applies to NSURLSession-based code; requests goes through urllib3 →
  raw POSIX sockets, which iOS doesn't gate. That means you can hit
  `http://` URLs without an ATS exception — but you should avoid
  doing that in production for the same reasons as anywhere else.
- **VPN / proxy.** System-level VPN settings affect all socket
  traffic, so requests respects them automatically. Per-app proxies
  set in `proxies={...}` work too.
- **Background time.** A long requests call counts against the host
  app's background time budget (~3 minutes by default). Pair with
  `BackgroundExecutionGuard` (see CodeBench) for longer ops.
- **Local file URLs.** `requests.get("file:///path/...")` works
  because urllib3 has a file:// adapter; bypasses the network stack.
- **DNS lookup behaviour.** Goes through libresolv; respects the
  system resolver and any `/etc/resolv.conf` configuration. iOS
  Cellular vs Wi-Fi DNS server selection is automatic.

---

## Limitations

- **No HTTP/2 / HTTP/3.** urllib3 1.26.x base defaults to HTTP/1.1.
  For HTTP/2 you'd need `httpx` + `h2` — neither is bundled here.
- **No async.** This is the synchronous `requests`; for `async / await`
  use `aiohttp` (would need to be `pip install`ed) or write a thin
  wrapper around urllib3's connection pool.
- **No event-loop integration.** Calls block the calling thread. Run
  inside `DispatchQueue.global().async { … }` or a Python thread to
  keep the UI responsive.

---

## Troubleshooting

### `SSLError: HTTPSConnectionPool(host='...', port=443): Max retries exceeded`

Usually a CA / cert issue. Check:
1. Is the host's cert chain in Mozilla's trust list?
   ```python
   import certifi, ssl
   ctx = ssl.create_default_context(cafile=certifi.where())
   ctx.check_hostname = True
   ```
2. Does the host have a custom / self-signed cert? Pass it via
   `verify="/path/cert.pem"`.

### `ConnectionError: [Errno 50] Network is down`

Airplane mode, or no Wi-Fi / cellular. iOS doesn't expose a single
"is networking up?" API — easiest probe is a small `requests.head()`
to a reliable host with a short timeout.

### `requests.get('http://localhost:8080/...')` hangs

iOS apps have no loopback access to other apps' services (sandbox).
Localhost only reaches you — i.e. another HTTP server you've
started inside the same process.

### `MaxRetryError: HTTPSConnectionPool` with no detail

urllib3's retry default is silent. Set `requests.adapters.HTTPAdapter`
with `max_retries=Retry(total=0, ...)` or wrap in try/except to
surface the underlying socket error.

### Slow first request after app launch

`certifi.where()` is loaded lazily on the first SSL call (parses
the ~250 KB CA bundle). Pre-warm by calling `import certifi;
certifi.where()` early in your Python startup.
