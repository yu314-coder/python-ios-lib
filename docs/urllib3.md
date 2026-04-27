# urllib3

> **Version:** 2.6.3  | **Type:** Pure Python  | **Status:** Fully working

The HTTP client library that backs `requests`. You can use it directly
when you want connection pooling, retry strategies, custom adapters,
streaming uploads/downloads, or chunked-encoding control without the
extra `requests` layer.

For most use cases, prefer `requests` (see [requests.md](requests.md))
— urllib3 is the lower-level tool.

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

---

## When to use urllib3 directly vs requests

| Need | Use |
|---|---|
| One-off GET/POST, sessions, cookies | `requests` (simpler API) |
| Streaming a 500MB upload to S3 | `urllib3` (tighter memory control) |
| Custom retry strategy with backoff | `urllib3` (Retry object is more granular) |
| Connection pooling for many hosts | `urllib3` (PoolManager is the primitive) |
| HTTP/2 | Neither — both are HTTP/1.1 in this version |
| Async | Neither — both are sync. For async, you'd `pip install aiohttp` |

---

## iOS sandbox notes

- Same as `requests`: no ATS gating, network calls go through urllib3 →
  raw POSIX sockets (which iOS doesn't intercept).
- VPN / per-app proxies / cellular vs Wi-Fi DNS selection: all handled
  by the system socket stack; urllib3 sees them transparently.
- Long-running calls count against the host app's background time
  budget. Pair with `BackgroundExecutionGuard` for ops > 30 s.

---

## Limitations

- **No HTTP/2** — urllib3 2.x base is HTTP/1.1.
- **No async** — sync only. Run inside `DispatchQueue.global().async`
  or a Python thread to keep the UI responsive.
- **TLS protocol pinning is partial** — you can request a min TLS
  version via `ssl_minimum_version=TLSVersion.TLSv1_3` but cipher
  suite selection is up to Apple's stack.

---

## Notes

- This is the package `requests` calls into. If you `import requests`
  in your script, you're using urllib3 transitively.
- `urllib3.disable_warnings(...)` is the only way to silence the
  default `InsecureRequestWarning` when `cert_reqs="CERT_NONE"`.
- For HTML scraping, pair with `bs4` (BeautifulSoup): `urllib3` →
  `r.data` → `BeautifulSoup(r.data, "html.parser")`.
