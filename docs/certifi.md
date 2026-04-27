# certifi

> **Version:** 2026.2.25  | **Type:** Pure Python  | **Status:** Fully working

Mozilla's CA root certificate bundle as a Python package. Used by
`requests`, `urllib3`, `httpx`, `huggingface_hub`, and any other
HTTPS client that needs a trusted-CA store. No code — just a single
`cacert.pem` file with ~140 root certificates, plus a tiny Python
wrapper that returns its path.

---

## Quick start

```python
import certifi

print(certifi.where())
# → '/path/to/python-ios-lib/.../certifi/cacert.pem'
```

That path is what `requests` uses by default for TLS verification:

```python
import requests
r = requests.get("https://api.example.com")
# under the hood: ssl.create_default_context(cafile=certifi.where())
```

You'd call `certifi.where()` directly only when:
- You're using a non-`requests` HTTP client and need to point it at
  a CA bundle
- Building a custom `ssl.SSLContext`

```python
import ssl, certifi
ctx = ssl.create_default_context(cafile=certifi.where())
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED
# Use ctx with raw socket / asyncio TLS
```

---

## What's in the bundle

Mozilla's NSS root certificate store, refreshed on a regular cadence
(this version: 2026-02-25). Includes all major commercial CAs (Let's
Encrypt, DigiCert, GlobalSign, Sectigo, Apple Inc., …) plus government
CAs the browsers trust by default.

**Does NOT include**:
- Self-signed certificates
- Internal-CA certificates (your company's intranet PKI)
- iOS-specific MDM-installed CAs (those live in the iOS Keychain
  and are NOT exposed to certifi)

For internal CAs, use `verify="/path/to/your/ca.pem"` instead of
the certifi default:

```python
import requests
r = requests.get("https://internal.api/", verify="/path/Documents/internal-ca.pem")
```

---

## iOS-specific note

iOS has its OWN trust store (managed via Settings → General → About
→ Certificate Trust Settings). Apps that use Apple's `URLSession`
automatically use that store. But Python on iOS goes through OpenSSL
+ raw POSIX sockets, NOT URLSession — so it ONLY trusts what's in
`certifi.where()`. That's deliberate (cross-platform consistency)
but means:

- Custom CA installed via Settings → won't be auto-trusted by
  `requests`. Either:
  - Pass `verify="/path/to/cert.pem"` per call
  - Append your cert to `certifi.where()`'s file (NOT recommended —
    breaks on `pip install --upgrade certifi`)
  - Use `URLSession` from Swift instead

- If a user reports "my Python script can't reach our enterprise API
  even though Safari can" — that's exactly this gap.

---

## When the bundle is too old

certifi gets re-released ~quarterly with the latest Mozilla store. On
PyPI, `pip install --upgrade certifi` fetches the newest. iOS pip's
auto-target lands the upgrade in `~/Documents/site-packages/certifi/`,
which takes precedence over the bundled version.

```
pip install --upgrade certifi
```

`requests` / `urllib3` re-resolve `certifi.where()` per-call, so the
new bundle takes effect immediately for new connections.

---

## Limitations

- **One bundle for everything.** No way to use a different CA store
  for different hosts (other than passing `verify=` per request).
- **Memory**: the cacert.pem is ~250 KB; lazily loaded on first
  `certifi.where()` call.

---

## See also

- [docs/requests.md](requests.md) — uses certifi by default
- [docs/urllib3.md](urllib3.md) — same
- [docs/huggingface-hub.md](huggingface-hub.md) — same (and is the
  reason your model downloads work over HTTPS)
