# charset_normalizer — universal charset detector

**Version:** `3.4.4` (`__version__`); dist-info reports `3.4.7`
**Type:** Pure Python (mypyc accelerator NOT bundled on iOS)
**SPM target:** Bundled in the Python framework (pulled in by `requests`)
**Total Python modules:** 12

Drop-in replacement for `chardet`. Every `requests.Response.text` call
uses it to decode raw bytes when the server didn't specify `charset=` in
`Content-Type`. You rarely call it directly — `requests` / `urllib3` use
it transparently — but knowing it's there helps when debugging encoding
issues.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `charset_normalizer.__init__` | Public API: `from_bytes`, `from_path`, `from_fp`, `is_binary`, `detect` (legacy chardet-compat), `CharsetMatch`, `CharsetMatches`, `set_logging_handler` |
| `charset_normalizer.__main__` | `python -m charset_normalizer FILE` CLI |
| `charset_normalizer.version` | `__version__` + `VERSION` tuple |
| `charset_normalizer.constant` | Charset language stats, frequency tables, alphabet sets (~2000 lines of embedded data) |
| `charset_normalizer.api` | The detection logic — `from_bytes` workhorse, multi-candidate scoring |
| `charset_normalizer.cd` | Coherence detector — language probability per candidate decoding |
| `charset_normalizer.md` | Mess detector — measures "chaos" score per decoding attempt |
| `charset_normalizer.models` | `CharsetMatch`, `CharsetMatches`, `CliDetectionResult` |
| `charset_normalizer.legacy` | `detect()` — chardet-compatible single-result API |
| `charset_normalizer.utils` | Byte-pattern checks, codepoint classification |

### `charset_normalizer.cli`

| Submodule | Provides |
|---|---|
| `cli.__init__` | CLI entry point |
| `cli.__main__` | `python -m charset_normalizer.cli ...` dispatcher |

## Quick start

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

## Read all candidates

```python
from charset_normalizer import from_bytes

candidates = list(from_bytes(some_bytes))
for r in candidates[:5]:
    print(f"  {r.encoding:>12}  chaos={r.chaos:.2f}  alphabets={r.alphabets}")
```

## chardet-compatible API

```python
from charset_normalizer import detect

result = detect(b"caf\xc3\xa9")
print(result)
# {'encoding': 'utf_8', 'confidence': 1.0, 'language': ''}
```

## When to call directly

- Reading user-uploaded text files of unknown encoding (CSV, log)
- Migrating legacy data files (Latin-1, Windows-1252 → UTF-8)
- Parsing email message bodies (each part may be a different encoding)

For HTTP responses: `requests.Response.text` already does this
automatically. Don't double-process.

## Limitations

- **Statistical guesser, not a magic wand.** Short strings (< 10 bytes) are ambiguous; check `r.chaos` — values < 0.05 are confident, > 0.3 means "probably wrong, try another approach"
- **No streaming** — loads the whole input into memory. For multi-GB files, sample the first ~64 KB
- **Loads big embedded tables** — `constant.py` is ~2000 lines of language-frequency data, parsed at import. ~50 ms first-import cost on iPad M-series

## iOS notes

- **No C accelerator.** Upstream charset_normalizer can ship an optional `mypyc`-compiled accelerator (`md.cp3*.so` / `md__mypyc.so`). The iOS bundle is pure Python only; **~2× slower on large inputs** vs the desktop pip wheel
- 100% pure Python — no platform-specific paths
- Works identically on iOS as on any other platform once you accept the speed cost

## How `requests` uses it

When you do `requests.get("https://example.com")` and call `.text`:

1. `requests` checks the `Content-Type` header for an explicit `charset=`
2. If missing, calls `charset_normalizer.from_bytes(r.content).best()` to detect
3. Decodes bytes → str using the detected encoding
4. Returns the decoded `str` to you

So almost every web app using `requests` is calling charset_normalizer
implicitly — you just don't see it.

## See also

- [requests.md](requests.md) — primary consumer
- [encoding.md](encoding.md) — TOC linking this + idna
- [idna.md](idna.md) — the other "requests pulls it in" encoding library
