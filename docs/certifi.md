# certifi — Mozilla CA root bundle

**Version:** 2026.2.25 (dist) / 2026.01.04 (`__version__`)  
**Type:** Pure Python (wraps a 250 KB `.pem` file)  
**SPM target:** `Certifi`  
**Auto-included by:** requests, urllib3, httpx, huggingface_hub, openai SDK, anthropic SDK, anything that does HTTPS  
**Total Python modules:** 3

Mozilla's NSS root certificate store packaged for Python. Zero logic — `certifi.where()` returns the path to `cacert.pem`. Every HTTPS client in the stack pulls this for default TLS verification.

## Modules

| Module | What it does |
|---|---|
| `certifi.__init__` | Re-exports `contents`, `where`, `__version__` |
| `certifi.__main__` | `python -m certifi` — prints the path to the bundle |
| `certifi.core` | `where() -> str` — extract bundle from package data (handles zipimport via `importlib.resources.as_file`), cache the path globally, register `atexit` cleanup. `contents() -> str` — read PEM as text |
| `certifi/cacert.pem` | The bundle itself: ~140 root certificates, ~250 KB |
| `certifi/py.typed` | PEP 561 marker — type checkers see no public types here |

## What's in the bundle

Mozilla's NSS root certificate store, refreshed quarterly (this snapshot: 2026-02-25). Includes major commercial CAs (Let's Encrypt, DigiCert, GlobalSign, Sectigo, Amazon, Apple, …) plus government CAs the major browsers trust by default.

**Not included:**
- Self-signed certificates
- Internal-CA certificates (your company's intranet PKI)
- iOS-specific MDM-installed CAs (those live in the iOS Keychain and are **not** exposed to certifi)

## iOS notes

iOS has its own trust store managed via **Settings → General → About → Certificate Trust Settings**. Apps that use Apple's `URLSession` automatically use that store. But Python on iOS goes through OpenSSL + raw POSIX sockets, **not** `URLSession`, so it ONLY trusts what's in `certifi.where()`.

Practical implications:

- A custom CA you installed via Settings will NOT be auto-trusted by `requests`. Options:
  - `requests.get(url, verify="/path/to/your/ca.pem")` per call
  - Use `URLSession` from Swift and bridge the response into Python
  - Append your cert to `certifi.where()`'s file (NOT recommended — breaks on the next `pip install --upgrade certifi`)
- If a user reports "my Python script can't reach our enterprise API even though Safari can" — that's exactly this gap.
- `certifi.where()` extracts to a temp path on first call if running from a zip; on iOS we're not zipimported so the path is the static `app_packages/site-packages/certifi/cacert.pem`.

## When the bundle is too old

certifi is re-released ~quarterly with the latest Mozilla store. `pip install --upgrade certifi` fetches the newest, lands it in `~/Documents/site-packages/certifi/`, and that shadows the bundled version. `requests` / `urllib3` re-resolve `certifi.where()` per connection, so the new bundle takes effect immediately.

## Example

```python
import certifi
import ssl
import requests

# 1. Default — requests uses certifi automatically
r = requests.get("https://api.example.com")
print(r.status_code)

# 2. Custom SSLContext for raw socket / asyncio TLS
ctx = ssl.create_default_context(cafile=certifi.where())
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED

# 3. Override with internal CA
r = requests.get(
    "https://internal.api/",
    verify="/path/Documents/internal-ca.pem",
)

# 4. Inspect the bundle path / contents
print(certifi.where())
# → /var/.../app_packages/site-packages/certifi/cacert.pem
print(len(certifi.contents()))
# → ~250000  (raw PEM text)
```

## See also

- [requests.md](requests.md) — uses certifi by default
- [huggingface-hub.md](huggingface-hub.md) — same (and why your model downloads work over HTTPS)
