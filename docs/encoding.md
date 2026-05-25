# Encoding helpers — charset_normalizer + idna

**Versions:** charset_normalizer 3.4.7 + idna 3.11
**Type:** Pure Python (both)
**SPM target:** Bundled in the Python framework (pulled in by `requests`)
**Total modules:** charset_normalizer 14, idna 9

Two small but essential libraries that the HTTP / web stack pulls in.
You rarely call them directly — `requests` / `urllib3` use them
transparently — but knowing they're there helps when debugging
encoding issues.

---

## Modules — charset_normalizer

### Top-level

| Module | What it does |
|---|---|
| `charset_normalizer.__init__` | Public API: `from_bytes`, `from_path`, `from_fp`, `is_binary`, `detect` (legacy chardet-compat) |
| `charset_normalizer.__main__` | `python -m charset_normalizer FILE` CLI |
| `charset_normalizer.version` | `__version__` + protocol version tuples |
| `charset_normalizer.constant` | Charset language stats, frequency tables, alphabet sets |
| `charset_normalizer.api` | The detection logic — `from_bytes` workhorse, multi-candidate scoring |
| `charset_normalizer.cd` | Coherence detector — language probability per candidate decoding |
| `charset_normalizer.md` | Mess detector — measures "chaos" score per decoding attempt |
| `charset_normalizer.models` | `CharsetMatch`, `CharsetMatches`, `CliDetectionResult` |
| `charset_normalizer.legacy` | `detect()` — chardet-compatible single-result API |
| `charset_normalizer.utils` | Helpers — byte-pattern checks, codepoint classification |

### `charset_normalizer.cli`

| Submodule | Provides |
|---|---|
| `cli.__init__` | CLI entry point |
| `cli.__main__` | `python -m charset_normalizer.cli ...` dispatcher |

The "guess what encoding this byte sequence really is" library.
Drop-in replacement for `chardet`. Every `requests.Response.text`
call uses it to decode raw bytes when the server didn't specify
`charset=` in `Content-Type`.

---

## charset_normalizer — quick start

```python
from charset_normalizer import from_bytes, from_path

# Detect encoding from raw bytes
sample = "héllo wörld".encode("latin-1")
result = from_bytes(sample).best()
print(result.encoding)         # 'iso-8859-1'
print(str(result))             # 'héllo wörld'  (decoded text)

# Detect from a file
result = from_path("/path/Documents/legacy.txt").best()
print(f"encoding={result.encoding!r}, chaos={result.chaos:.2f}")
print(str(result)[:200])
```

### Read all candidates

```python
from charset_normalizer import from_bytes

candidates = list(from_bytes(some_bytes))
for r in candidates[:5]:
    print(f"  {r.encoding:>12}  chaos={r.chaos:.2f}  alphabets={r.alphabets}")
```

### chardet-compatible API

```python
from charset_normalizer import detect

result = detect(b"caf\xc3\xa9")
print(result)
# {'encoding': 'utf_8', 'confidence': 1.0, 'language': ''}
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
- **No C accelerator on iOS** — upstream charset_normalizer can ship
  an optional `mypyc`-compiled accelerator (`md.cp3*.so` / `md__mypyc.so`).
  The iOS bundle is pure Python only; ~2× slower on large inputs.

---

## Modules — idna

| Module | What it does |
|---|---|
| `idna.__init__` | Public API: `encode`, `decode`, `IDNAError`, `IDNABidiError`, `valid_label_length`, `valid_string_length`, `check_initial_combiner`, `uts46_remap`, `nameprep`, `ToASCII`, `ToUnicode`, `alabel`, `ulabel` |
| `idna.core` | The encoder/decoder algorithm — UTS #46 + RFC 3490 / 5891 |
| `idna.codec` | Python codec registration — `"name".encode("idna")` |
| `idna.compat` | py2/py3 shim (deprecated, kept for compat) |
| `idna.idnadata` | Unicode tables — joining types, Unicode categories, BIDI classes |
| `idna.intranges` | Range-based table compression / lookup |
| `idna.package_data` | `__version__` |
| `idna.uts46data` | UTS #46 case-mapping + character-status table |

[Internationalized Domain Names](https://en.wikipedia.org/wiki/Internationalized_domain_name)
encoder / decoder. Lets you handle hostnames with non-ASCII characters
(`münchen.de`, `中国.中国`, `ดอทคอม.ไทย`) by converting them to ASCII
"Punycode" form (`xn--mnchen-3ya.de`).

`requests` / `urllib3` call this for you when you pass a Unicode URL.
You'd call it directly to validate input, normalize stored hostnames,
or implement a custom URL parser.

---

## idna — quick start

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

# Codec registration
print("münchen".encode("idna"))           # b'xn--mnchen-3ya'
print(b"xn--mnchen-3ya".decode("idna"))   # 'münchen'
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

When you do `requests.get("https://münchen.de")`:

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

## iOS notes

Both are pure Python — no platform-specific paths. They work
identically on iOS as on any other platform.

- **charset_normalizer**: bundled without the optional `mypyc`
  accelerator. Adds ~2× detection cost on large inputs vs the
  desktop pip wheel.
- **idna**: 100% pure Python with embedded Unicode tables
  (`idnadata.py`, `uts46data.py` — ~2 MB combined). No external
  dependencies.

---

## When NOT bundled but still imported

`charset_normalizer` and `idna` are both `requests` install-deps,
so they ship by default. If you `pip install` something that
specifies different versions, pip detects them as already satisfied
(via the dist-info we ship) and won't re-download.

For an absolute minimal install — if you don't use HTTP at all —
you could remove both. Saves ~600 KB. Not worth it for most apps.
