# markdown_it + mdurl

> **markdown-it-py 3.0.0** + **mdurl 0.1.2**  | **Type:** Pure Python  | **Status:** Fully working

CommonMark-compliant Markdown parser (`markdown_it`) plus its small
URL-handling helper (`mdurl`). Used by `rich` for its
`Console.print(Markdown(...))` rendering, and importable directly when
you want to parse / transform Markdown in your own scripts.

---

## markdown_it — quick start

```python
from markdown_it import MarkdownIt

md = MarkdownIt()
html = md.render("""
# Hello

Some **bold** text and a [link](https://example.com).

- one
- two
""")

print(html)
# → <h1>Hello</h1>
# → <p>Some <strong>bold</strong> text…
# → <ul><li>one</li><li>two</li></ul>
```

```python
# Parse to a token tree (instead of HTML) for custom transforms
md = MarkdownIt()
tokens = md.parse("# Hello\n\nWorld")
for t in tokens:
    print(f"{t.type:<20}  level={t.level}  content={t.content!r}")
# → heading_open    level=0  content=''
# → inline          level=1  content='Hello'
# → heading_close   level=0  content=''
# → paragraph_open  level=0  content=''
# → inline          level=1  content='World'
# → paragraph_close level=0  content=''
```

```python
# Configure features (CommonMark profile + extensions)
from markdown_it import MarkdownIt
from markdown_it.extensions.tasklists import tasklists_plugin

md = (MarkdownIt("commonmark", {"breaks": True, "html": False})
      .enable("strikethrough")
      .enable("table")
      .use(tasklists_plugin))

print(md.render("""
- [x] task one
- [ ] task two

| a | b |
|---|---|
| 1 | 2 |
"""))
```

### Available presets

| Preset | What's enabled |
|---|---|
| `commonmark` | Strict CommonMark (default) |
| `default` | CommonMark + table + strikethrough + linkify |
| `gfm-like` | Closer to GitHub-Flavored Markdown |
| `zero` | Nothing — build up via `.enable(...)` |

### Extension plugins

Bundled extensions (under `markdown_it.extensions.*`):

- `tasklists` — `[x] checkbox` lists
- `footnote` — `[^1]` style footnotes
- `front_matter` — YAML / TOML front-matter blocks
- `myst_role` / `myst_blocks` — MyST extended syntax (Sphinx-style)
- `dollarmath` / `texmath` — `$inline$` and `$$display$$` math (preserved as-is)
- `container` — `:::name`-style fenced containers
- `deflist` — definition lists
- `linkify` — auto-detect URLs in plain text

---

## mdurl — quick start

A small URL parser used internally by markdown_it for normalising and
encoding URLs in `[text](url)` syntax. You'd call directly only if
you're writing markdown-related tooling that needs the same
URL-handling rules:

```python
import mdurl

# Parse a URL into components (similar to urllib.parse but with markdown-specific quirks)
parsed = mdurl.parse("https://example.com/path?q=1#frag")
print(parsed.protocol, parsed.hostname, parsed.pathname)
# → 'https:' 'example.com' '/path?q=1'

# Encode a URL the way markdown_it does
encoded = mdurl.encode("https://example.com/with space")
print(encoded)              # 'https://example.com/with%20space'

# Decode
decoded = mdurl.decode("https%3A//example.com/with%20space")
```

For most purposes, prefer `urllib.parse` (stdlib). mdurl exists to
match Markdown's specific URL-handling rules (autolinks vs links,
percent-encoding edge cases) for parser compatibility with the JS
markdown-it package.

---

## When to use markdown_it vs alternatives

| Need | Use |
|---|---|
| Render Markdown to HTML | `markdown_it` |
| Render Markdown to a colored terminal | `rich.markdown.Markdown` (uses markdown_it under the hood) |
| Convert Markdown to PDF | markdown_it → HTML → wkhtmltopdf (the latter not on iOS); or use `pdflatex` via offlinai_latex with a Markdown-to-LaTeX step |
| Transform Markdown (custom rules) | `markdown_it`'s token-tree API |
| Strip Markdown to plain text | `markdown_it` → render → `bs4` strip |

---

## Pairing with rich

```python
from rich.console import Console
from rich.markdown import Markdown

console = Console()
console.print(Markdown("""
# Hello

Some **bold** text. Run `pip install rich` to get this.

```python
print("syntax highlighting works")
```
"""))
```

Rich's `Markdown` class converts the markdown_it token tree into rich
text + tables + syntax-highlighted code blocks for terminal display.
Works great in CodeBench's in-app terminal.

---

## Limitations

- **Pure Python** — slower than the C implementations (`mistune`,
  the original `markdown` package's C accelerators). Fine for
  documents under ~1 MB; noticeable for huge corpora.
- **No streaming parser** — input is parsed all at once. For
  multi-megabyte Markdown, split into smaller chunks.
- **HTML in Markdown is sanitised by default** — `<script>` tags
  etc. are passed through as text. Set `html=True` in MarkdownIt
  options to allow inline HTML (useful for trusted input only).

---

## Build provenance

- **markdown-it-py 3.0.0** — pure Python, identical to upstream PyPI
  wheel.
- **mdurl 0.1.2** — pure Python, identical to upstream.

Both are minimal-dependency packages; they're bundled because rich
declares them as required (rich's `Markdown` and `Console` rendering
depend on them).
