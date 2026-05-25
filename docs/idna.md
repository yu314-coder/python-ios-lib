# idna — Internationalized Domain Names encoder/decoder

**Version:** `3.11` (`__version__`)
**Type:** Pure Python (with ~13 KLoC of embedded Unicode tables)
**SPM target:** Bundled in the Python framework (pulled in by `requests`)
**Total Python modules:** 8

[Internationalized Domain Names](https://en.wikipedia.org/wiki/Internationalized_domain_name)
encoder / decoder. Lets you handle hostnames with non-ASCII characters
(`münchen.de`, `中国.中国`, `ดอทคอม.ไทย`) by converting them to ASCII
"Punycode" form (`xn--mnchen-3ya.de`).

`requests` / `urllib3` call this for you when you pass a Unicode URL.
You'd call it directly to validate input, normalize stored hostnames,
or implement a custom URL parser.

## Modules

| Module | What it does |
|---|---|
| `idna.__init__` | Public API: `encode`, `decode`, `IDNAError`, `IDNABidiError`, `InvalidCodepoint`, `InvalidCodepointContext`, `alabel`, `ulabel`, `check_bidi`, `check_hyphen_ok`, `check_initial_combiner`, `check_label`, `check_nfc`, `uts46_remap`, `valid_contextj`, `valid_contexto`, `valid_label_length`, `valid_string_length`, `intranges_contain` |
| `idna.core` | The encoder/decoder algorithm — UTS #46 + RFC 3490 / 5891 (437 lines) |
| `idna.codec` | Python codec registration — `"name".encode("idna")` (122 lines) |
| `idna.compat` | py2/py3 shim (deprecated, kept for compat — 15 lines) |
| `idna.idnadata` | Unicode tables — joining types, categories, BIDI classes (4309 lines, ~1.5 MB) |
| `idna.intranges` | Range-based table compression / lookup (57 lines) |
| `idna.package_data` | `__version__ = "3.11"` |
| `idna.uts46data` | UTS #46 case-mapping + character-status table (8841 lines, ~3 MB) |

## Quick start

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

# Codec registration — once `import idna` runs, `"name".encode("idna")` works
print("münchen".encode("idna"))           # b'xn--mnchen-3ya'
print(b"xn--mnchen-3ya".decode("idna"))   # 'münchen'
```

## Common patterns

```python
# Useful when normalizing user-typed URLs
from urllib.parse import urlparse
import idna

def canonical_host(url: str) -> str:
    """Return the URL's hostname in ASCII Punycode form."""
    host = urlparse(url).hostname or ""
    try:
        return idna.encode(host).decode("ascii")
    except idna.IDNAError:
        return host  # already ASCII or invalid
```

## When to call directly

- Validating hostname input before passing it to a non-Unicode API
- Comparing hostnames safely (always normalize via Punycode first)
- Building a DNS lookup tool / URL bar

## Limitations

- **UTS #46 strictness mode** — by default, `idna.encode` uses `uts46=False` and rejects some ambiguous Unicode (full-width ASCII, deprecated codepoints). Pass `uts46=True` to relax
- **No internationalized scheme support** (e.g. `http://中国.中国/` works because `requests` calls `idna` on the hostname; the scheme + path remain ASCII)
- **No emoji domains.** Per RFC 5891, emoji are intentionally not IDNA-allowed. `xn--` encodings of emoji you see in the wild are technically invalid even though they may resolve

## Bundled tables

`idna.idnadata` (1.5 MB) holds joining types, Unicode categories, and BIDI
classes per codepoint. `idna.uts46data` (3 MB) holds UTS #46 case mappings
and per-character status (valid / disallowed / deviation / ignored / mapped).
Combined, the embedded data is ~4.5 MB — the biggest cost of bundling
idna, but it lets the library work with no external dependencies.

## How `requests` uses it

When you do `requests.get("https://münchen.de")`:

1. `requests` constructs a `urllib3.HTTPSConnectionPool` with `host="münchen.de"`
2. `urllib3` passes the host to `idna.encode(...)` → `b'xn--mnchen-3ya.de'`
3. `urllib3` opens a TCP socket to that ASCII hostname
4. Server responds; `requests` decodes the body via [`charset_normalizer`](charset-normalizer.md)

Both idna and charset_normalizer are essential AND silent — you'll only
notice them when something goes wrong (a server with `Content-Type:
text/html` no charset, or a hostname with disallowed characters).

## iOS notes

- 100% pure Python with embedded Unicode tables — no native code, no platform-specific paths
- ~4.5 MB on disk (mostly the `idnadata` + `uts46data` tables) — biggest cost item in this library
- Works identically on iOS as on any other platform

## See also

- [requests.md](requests.md) — primary consumer
- [encoding.md](encoding.md) — TOC linking this + charset_normalizer
- [charset-normalizer.md](charset-normalizer.md) — the other "requests pulls it in" encoding library
