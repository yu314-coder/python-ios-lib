# Encoding helpers — charset_normalizer + idna

Two small but essential libraries that the HTTP / web stack pulls in.
You rarely call them directly — `requests` / `urllib3` use them
transparently — but knowing they're there helps when debugging
encoding issues.

Each now has its own dedicated documentation:

| Package | Doc | What it does |
|---|---|---|
| `charset_normalizer` | [charset-normalizer.md](charset-normalizer.md) | Drop-in chardet replacement. Every `requests.Response.text` call uses it when the server didn't specify `charset=`. 12 modules. **iOS bundle is pure Python** — the optional `mypyc` accelerator (`md.cp3*.so`) isn't built, so detection is ~2× slower on large inputs |
| `idna` | [idna.md](idna.md) | Internationalized Domain Names encoder/decoder (Punycode). 8 modules with ~4.5 MB of embedded Unicode tables (`idnadata`, `uts46data`). Called by `urllib3` for every non-ASCII hostname |

## How the HTTP stack uses these

When you do `requests.get("https://münchen.de")`:

1. `requests` constructs a `urllib3.HTTPSConnectionPool` with `host="münchen.de"`
2. `urllib3` passes the host to `idna.encode(...)` → `b'xn--mnchen-3ya.de'`
3. `urllib3` opens a TCP socket to that ASCII hostname
4. The server responds with bytes
5. `requests.Response.text` calls `charset_normalizer.from_bytes(r.content).best()` to figure out the encoding
6. Returns the decoded `str` to you

Both libraries are essential AND silent — you'll only notice them
when something goes wrong (a server with `Content-Type: text/html`
no charset, or a hostname with disallowed characters).

## When NOT bundled but still imported

`charset_normalizer` and `idna` are both `requests` install-deps, so
they ship by default. If you `pip install` something that specifies
different versions, pip detects them as already satisfied (via the
dist-info we ship) and won't re-download.

For an absolute minimal install — if you don't use HTTP at all —
you could remove both. Saves ~600 KB. Not worth it for most apps.
