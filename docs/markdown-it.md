# markdown_it + mdurl — CommonMark parser

**Versions:** markdown-it-py 3.0.0 (`__version__ = "4.0.0"` internal) + mdurl 0.1.2
**Type:** Pure Python (both)
**SPM target:** Bundled in `Rich` dep chain (`Console.print(Markdown(...))`)
**Total modules:** markdown_it 66, mdurl 6

CommonMark-compliant Markdown parser (`markdown_it`) plus its small
URL-handling helper (`mdurl`). Used by `rich` for its
`Console.print(Markdown(...))` rendering, and importable directly when
you want to parse / transform Markdown in your own scripts.

---

## Modules — markdown_it

### Top-level

| Module | What it does |
|---|---|
| `markdown_it.__init__` | Re-exports `MarkdownIt` |
| `markdown_it.main` | `MarkdownIt` class — entry point. `.render(src)`, `.parse(src)`, `.enable(rule)`, `.disable(rule)`, `.use(plugin)` |
| `markdown_it.parser_block` | `ParserBlock` — block-level rule pipeline |
| `markdown_it.parser_core` | `ParserCore` — token-tree post-processing |
| `markdown_it.parser_inline` | `ParserInline` — inline-level rule pipeline |
| `markdown_it.renderer` | `RendererHTML` (default), `RendererProtocol` (custom-renderer interface) |
| `markdown_it.ruler` | `Ruler` — rule registry with `before/after/at` ordering |
| `markdown_it.token` | `Token` — parser output node |
| `markdown_it.tree` | `SyntaxTreeNode` — read-only tree wrapper for traversal |
| `markdown_it.utils` | `EnvType`, `OptionsDict`, `OptionsType`, `PresetType`, escape helpers |
| `markdown_it._compat` | py3-version shims |
| `markdown_it._punycode` | Punycode encoder (autolinks) |
| `markdown_it.port.yaml` | Port metadata (JS → Python provenance) |
| `markdown_it.cli.parse` | `python -m markdown_it` CLI |

### `markdown_it.common`

| Submodule | Provides |
|---|---|
| `common.entities` | HTML5 named-entity table (`&amp;` → `&`, etc.) |
| `common.html_blocks` | Block-level HTML element sets |
| `common.html_re` | HTML-token regex constants |
| `common.normalize_url` | URL normalization rules |
| `common.utils` | Whitespace, charcode, escape helpers |

### `markdown_it.helpers`

| Submodule | Provides |
|---|---|
| `helpers.parse_link_destination` | URL parser for `[text](url)` |
| `helpers.parse_link_label` | Label parser for `[text][ref]` |
| `helpers.parse_link_title` | Title parser for `[text](url "title")` |

### `markdown_it.rules_block`

| Submodule | Provides |
|---|---|
| `rules_block.blockquote` | `>` blockquotes |
| `rules_block.code` | Indented code blocks |
| `rules_block.fence` | ` ``` ` fenced code blocks |
| `rules_block.heading` | `#` ATX headings |
| `rules_block.lheading` | `=== / ---` Setext headings |
| `rules_block.hr` | `---` thematic breaks |
| `rules_block.html_block` | Raw HTML blocks |
| `rules_block.list` | Ordered/unordered lists |
| `rules_block.paragraph` | Paragraph |
| `rules_block.reference` | `[label]: url` link refs |
| `rules_block.table` | GFM tables (when enabled) |
| `rules_block.state_block` | Per-pass parser state |

### `markdown_it.rules_inline`

| Submodule | Provides |
|---|---|
| `rules_inline.autolink` | `<http://…>` |
| `rules_inline.backticks` | `` `code` `` |
| `rules_inline.emphasis` | `**bold**` / `*italic*` |
| `rules_inline.balance_pairs` | Emphasis-balancing post-pass |
| `rules_inline.entity` | `&amp;` entities |
| `rules_inline.escape` | `\*` backslash escapes |
| `rules_inline.html_inline` | Inline raw HTML |
| `rules_inline.image` | `![alt](src)` |
| `rules_inline.link` | `[text](url)` |
| `rules_inline.linkify` | Auto-detect URLs (needs `linkify-it`) |
| `rules_inline.newline` | Soft / hard breaks |
| `rules_inline.strikethrough` | `~~strike~~` (GFM) |
| `rules_inline.text` | Plain text |
| `rules_inline.fragments_join` | Adjacent-text-token merge |
| `rules_inline.state_inline` | Per-pass parser state |

### `markdown_it.rules_core`

| Submodule | Provides |
|---|---|
| `rules_core.block` | Block-level pass driver |
| `rules_core.inline` | Inline pass driver |
| `rules_core.linkify` | URL auto-link pass |
| `rules_core.normalize` | Newline + character normalization |
| `rules_core.replacements` | `(c) → ©`, `--- → —` |
| `rules_core.smartquotes` | `"foo"` → `"foo"` |
| `rules_core.state_core` | Core-pass state |
| `rules_core.text_join` | Adjacent text-token concatenation |

### `markdown_it.presets`

| Submodule | Provides |
|---|---|
| `presets.commonmark` | Strict CommonMark (default) |
| `presets.default` | CommonMark + table + strikethrough + linkify |
| `presets.zero` | Nothing — build up via `.enable(...)` |

`gfm-like` and `js-default` are also registered via `_PRESETS` in
`main.py` but constructed at import time, not via separate modules.

---

## Modules — mdurl

| Module | What it does |
|---|---|
| `mdurl.__init__` | Re-exports `parse`, `format`, `encode`, `decode`, `URL`, default char sets |
| `mdurl._parse` | URL string → `URL` parser (markdown-it specific quirks) |
| `mdurl._format` | `URL` → string |
| `mdurl._encode` | Percent-encode (markdown-it variant) |
| `mdurl._decode` | Percent-decode (markdown-it variant) |
| `mdurl._url` | `URL` dataclass (`protocol`, `hostname`, `port`, `pathname`, `search`, `hash`, …) |

---

## Quick start — markdown_it

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
md = (MarkdownIt("commonmark", {"breaks": True, "html": False})
      .enable("strikethrough")
      .enable("table"))

print(md.render("""
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
| `js-default` | Mirrors the JS markdown-it default profile |
| `gfm-like` | Closer to GitHub-Flavored Markdown |
| `zero` | Nothing — build up via `.enable(...)` |

### Extension plugins (not bundled — `pip install`)

The bundled markdown-it-py core doesn't ship the `extensions/`
subpackage. Common ones from PyPI (which work fine on iOS, pure Python):

- `mdit-py-plugins.tasklists` — `[x] checkbox` lists
- `mdit-py-plugins.footnote` — `[^1]` footnotes
- `mdit-py-plugins.front_matter` — YAML / TOML front-matter
- `mdit-py-plugins.myst_role` / `myst_blocks` — MyST extended syntax
- `mdit-py-plugins.dollarmath` / `texmath` — `$inline$` / `$$display$$`
- `mdit-py-plugins.container` — `:::name`-style fenced containers
- `mdit-py-plugins.deflist` — definition lists

Linkify (`rules_inline.linkify`) is bundled but **inert** unless you
also install `linkify-it-py` — see `main.py` `try: import linkify_it`.

---

## Quick start — mdurl

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
| Render Markdown to a colored terminal | `rich.markdown.Markdown` (uses markdown_it internally) |
| Convert Markdown to PDF | `markdown_it` → HTML → custom CSS-to-PDF (no headless browser on iOS); or Markdown → LaTeX → `offlinai_latex.pdftex` |
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
Works in CodeBench's in-app terminal.

---

## iOS notes

Both packages are pure Python — they work identically on iOS and any
other platform. No native extensions, no platform-specific paths.

- **`markdown_it/main.py`** has a guarded `import linkify_it` —
  optional dep, skipped if absent. Linkify URL auto-detection
  silently turns into a no-op without it.
- **CLI** (`python -m markdown_it`) reads stdin / file, prints HTML.
  Works in CodeBench's terminal.

---

## Limitations

- **Pure Python** — slower than C implementations (`mistune` ext,
  upstream `markdown` package's C accelerators). Fine for documents
  under ~1 MB; noticeable for huge corpora.
- **No streaming parser** — input parsed all at once.
- **HTML in Markdown sanitised by default** — `<script>` tags etc.
  passed through as text. Set `html=True` in MarkdownIt options to
  allow inline HTML (trusted input only).
- **`linkify-it` not bundled** — auto-URL detection rule is registered
  but skipped at runtime. `pip install linkify-it-py` to enable.

---

## Build provenance

- **markdown-it-py 3.0.0** — pure Python, identical to upstream PyPI
  wheel
- **mdurl 0.1.2** — pure Python, identical to upstream

Both minimal-dependency; bundled because rich declares them as required.
