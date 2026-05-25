# regex + typing_extensions

Two unrelated small utility libraries. Each now has its own dedicated documentation:

| Package | Doc | What it does |
|---|---|---|
| `regex` | [regex.md](regex.md) | Matthew Barnett's `regex` package — **iOS shim**, 61 lines. Re-exports stdlib `re` because the C extension `_regex.so` isn't cross-compiled for iOS arm64. Property classes (`\p{L}`), fuzzy matching, atomic groups silently unavailable; basic match/search/sub/compile work via `re` |
| `typing_extensions` | [minor-libs.md](minor-libs.md) (or its dedicated split) | Backport of typing features from newer Python versions. iOS Python is 3.14 so most names are already in stdlib `typing`, but the package is bundled so libraries that pin it as a dep still import |

They were paired in this doc only because they're both small and orthogonal —
not because they're functionally related.
