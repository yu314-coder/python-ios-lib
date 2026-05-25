# mdurl — URL parsing for markdown-it-py

**Version:** 0.1.2
**Type:** Pure Python
**SPM target:** Bundled in `Rich` (no standalone target)
**Auto-included by:** Rich, markdown-it-py
**Total Python modules:** 6

A small port of the JavaScript `mdurl` package to Python. It exists
because `markdown-it-py` needs a URL encoder/decoder/parser that matches
the reference JS `markdown-it` implementation byte-for-byte (for
character-class compatibility in autolinks and image references).
Stdlib's `urllib.parse` doesn't match precisely enough.

You'll almost never import `mdurl` directly — it's machinery for
the Markdown parser.

## Modules

| Module | What it does |
|---|---|
| `mdurl.__init__` | Re-exports the public API: `parse`, `format`, `encode`, `decode`, `URL`, `ENCODE_DEFAULT_CHARS`, `ENCODE_COMPONENT_CHARS`, `DECODE_DEFAULT_CHARS`, `DECODE_COMPONENT_CHARS` |
| `mdurl._parse` | `url_parse(url, slashes_denote_host=False)` — returns a `URL` namedtuple |
| `mdurl._format` | `format(url)` — rebuild a URL string from a `URL` object |
| `mdurl._encode` | `encode(string, exclude=DEFAULT_CHARS, keep_escaped=True)` — percent-encode unsafe characters (JS-compatible) |
| `mdurl._decode` | `decode(string, exclude=DEFAULT_CHARS)` — percent-decode while preserving certain characters |
| `mdurl._url` | The `URL` dataclass-like object (protocol, slashes, auth, host, port, pathname, search, hash) |

## iOS-specific patches

None — pure Python, stdlib-only. Works on iOS without modification.

## Standalone example

```python
import mdurl

# Parse
u = mdurl.parse("https://user:pass@example.com:8080/path/file?q=1#frag")
print(u.protocol)  # 'https:'
print(u.host)      # 'example.com:8080'
print(u.hostname)  # 'example.com'
print(u.port)      # '8080'
print(u.pathname)  # '/path/file'
print(u.search)    # '?q=1'
print(u.hash)      # '#frag'
print(u.auth)      # 'user:pass'

# Encode / decode (matches JS markdown-it's character classes)
print(mdurl.encode("hello world/foo<bar>"))
# 'hello%20world/foo%3Cbar%3E'

print(mdurl.decode("hello%20world"))
# 'hello world'

# Round-trip
print(mdurl.format(u))
# 'https://user:pass@example.com:8080/path/file?q=1#frag'
```

## See also

- [docs/markdown-it.md](markdown-it.md) — primary consumer
- [docs/rich.md](rich.md) — re-exports markdown-it for `rich.markdown.Markdown`
