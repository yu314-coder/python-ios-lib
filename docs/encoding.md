# Encoding helpers — charset_normalizer + idna

> **charset_normalizer 3.4.7** + **idna 3.11**  | **Type:** Pure Python  | **Status:** Fully working

Two small but essential libraries that the HTTP / web stack pulls in.
You rarely call them directly — `requests` / `urllib3` use them
transparently — but knowing they're there helps when debugging
encoding issues.

---

## charset_normalizer

The "guess what encoding this byte sequence really is" library.
Drop-in replacement for `chardet`. Every `requests.Response.text`
call uses it to decode raw bytes when the server didn't specify
`charset=` in `Content-Type`.

### Direct use

```python
from charset_normalizer import from_bytes, from_path

# Detect encoding from raw bytes
sample = "héllo wörld".encode("latin-1")
result = from_bytes(sample).best()
print(result.encoding)         # 'iso-8859-1'
print(str(result))             # 'héllo wörld'  (decoded text)

# Detect from a file
result = from_path("/path/Documents/legacy.txt").best()
print(f"encoding={result.encoding!r}, confidence={result.chaos:.2f}")
print(str(result)[:200])
```

### Read all candidates

```python
from charset_normalizer import from_bytes

candidates = list(from_bytes(some_bytes))
for r in candidates[:5]:
    print(f"  {r.encoding:>12}  chaos={r.chaos:.2f}  alphabets={r.alphabets}")
```

### When to call directly

- Reading user-uploaded text files of unknown encoding (CSV, log)
- Migrating legacy data files (Latin-1, Windows-1252 → UTF-8)
- Parsing email message bodies (each part may be a different encoding)

For HTTP responses: `requests.Response.text` already does this
automatically. Don't double-process.

### Limitations

- **Statistical guesser, not a magic wand.** Short strings (< 10 bytes)
  are ambiguous; check `r.chaos` — values < 0.05 are confident,
  > 0.3 means "probably wrong, try another approach".
- **No streaming** — loads the whole input into memory. For multi-GB
  files, sample the first ~64 KB.

---

## idna

[Internationalized Domain Names](https://en.wikipedia.org/wiki/Internationalized_domain_name)
encoder / decoder. Lets you handle hostnames with non-ASCII characters
(`münchen.de`, `中国.中国`, `ดอทคอม.ไทย`) by converting them to ASCII
"Punycode" form (`xn--mnchen-3ya.de`).

`requests` / `urllib3` call this for you when you pass a Unicode URL.
You'd call it directly to validate input, normalize stored hostnames,
or implement a custom URL parser.

### Direct use

```python
import idna

# Encode → ASCII Punycode (for putting on the wire)
print(idna.encode("münchen.de"))          # b'xn--mnchen-3ya.de'
print(idna.encode("ドメイン.テスト"))      # b'xn--eckwd4c7c.xn--zckzah'

# Decode → human-readable Unicode
print(idna.decode("xn--mnchen-3ya.de"))   # 'münchen.de'

# Validate a label (single hostname segment, e.g. "münchen")
try:
    idna.uts46_remap("test_label")        # underscores forbidden
except idna.IDNAError as e:
    print(f"invalid: {e}")
```

```python
# Useful when normalizing user-typed URLs
from urllib.parse import urlparse

def canonical_host(url: str) -> str:
    """Return the URL's hostname in ASCII Punycode form."""
    host = urlparse(url).hostname or ""
    try:
        return idna.encode(host).decode("ascii")
    except idna.IDNAError:
        return host  # already ASCII or invalid
```

### When to call directly

- Validating hostname input before passing it to a non-Unicode API
- Comparing hostnames safely (always normalize via Punycode first)
- Building a DNS lookup tool / URL bar

### Limitations

- **UTS #46 strictness mode** — by default, `idna.encode` uses
  `uts46=False` and rejects some ambiguous Unicode (full-width
  ASCII, deprecated codepoints). Pass `uts46=True` to relax.
- **No internationalized scheme support** (e.g. `http://中国.中国/`
  works because `requests` calls `idna` on the hostname; but the
  scheme + path remain ASCII).
- **No emoji domains.** Per RFC 5891, emoji are intentionally not
  IDNA-allowed. `xn--` encodings of emoji you see in the wild are
  technically invalid even though they may resolve.

---

## How the HTTP stack uses these

When you do `requests.get("https://münchen.de")`, here's the path:

1. `requests` constructs a `urllib3.HTTPSConnectionPool` with
   `host="münchen.de"`.
2. `urllib3` passes the host to `idna.encode(...)` → `b'xn--mnchen-3ya.de'`.
3. `urllib3` opens a TCP socket to that ASCII hostname.
4. The server responds with bytes.
5. `requests.Response.text` calls `charset_normalizer.from_bytes(r.content).best()`
   to figure out the encoding.
6. Returns the decoded `str` to you.

Both libraries are essential AND silent — you'll only notice them
when something goes wrong (a server with `Content-Type: text/html`
no charset, or a hostname with disallowed characters).

---

## When NOT bundled but still imported

`charset_normalizer` and `idna` are both `requests` install-deps,
so they ship by default. If you `pip install` something that
specifies different versions, pip detects them as already satisfied
(via the dist-info we ship) and won't re-download.

For the absolute minimal install — if you don't use HTTP at all —
you could remove both. Saves ~600 KB. Not worth it for most apps.
