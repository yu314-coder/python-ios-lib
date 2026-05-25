# BeautifulSoup (bs4) — HTML / XML parsing

**Version:** 4.14.3
**Type:** Pure Python (with soupsieve 2.8 for CSS selectors)
**SPM target:** Bundled in the Python framework
**Total modules:** 15 Python + soupsieve 7

HTML/XML parsing library. Uses the stdlib `html.parser` backend by
default on iOS (no lxml / html5lib compiled). Provides a Pythonic
tree-traversal API for navigating and modifying HTML documents.

---

## Modules

### Top-level

| Module | What it does |
|---|---|
| `bs4.__init__` | Public API: `BeautifulSoup`, `Tag`, `NavigableString`, `Comment`, `Declaration`, `ProcessingInstruction`, `ResultSet`, `CSS` |
| `bs4.element` | Core tree node types: `Tag`, `NavigableString`, `PageElement`, `SoupStrainer`, `Stylesheet`, `Script`, `RubyTextString`, `CData`, … |
| `bs4.css` | CSS-selector dispatcher (`Tag.select`, `Tag.select_one`) — delegates to soupsieve |
| `bs4.dammit` | `UnicodeDammit` — encoding detection (uses charset_normalizer) |
| `bs4.diagnose` | `diagnose(markup)` — debug helper printing what each parser sees |
| `bs4.exceptions` | `FeatureNotFound`, `ParserRejectedMarkup`, … |
| `bs4.filter` | `SoupStrainer` — pre-parse filter for memory efficiency |
| `bs4.formatter` | Output formatters: `HTMLFormatter`, `XMLFormatter`, `Formatter` base |
| `bs4._deprecation` | Deprecation-warning helpers |
| `bs4._typing` | Type aliases |
| `bs4._warnings` | Warning classes: `MarkupResemblesLocatorWarning`, `XMLParsedAsHTMLWarning`, … |

### `bs4.builder` — Parser back-ends

| Submodule | Backend | iOS status |
|---|---|---|
| `builder.__init__` | Registry — discovers `_htmlparser`, `_lxml`, `_html5lib`; selects via `features=` arg |
| `builder._htmlparser` | Wraps stdlib `html.parser` | **Works** — the iOS default |
| `builder._lxml` | Wraps lxml's HTML/XML parsers | Not bundled — `pip install lxml` fails on iOS (libxml2 not present) |
| `builder._html5lib` | Wraps html5lib (pure Python, browser-style) | `pip install html5lib` works (pure Python) |

### soupsieve (CSS selectors)

| Module | What it does |
|---|---|
| `soupsieve.__init__` | `compile`, `match`, `select`, `select_one`, `closest`, `filter`, `iselect` |
| `soupsieve.css_parser` | CSS selector → AST |
| `soupsieve.css_match` | AST → matcher engine |
| `soupsieve.css_types` | AST node types |
| `soupsieve.util` | Whitespace, namespace helpers |
| `soupsieve.pretty` | Pretty-printer for AST |
| `soupsieve.__meta__` | Version + metadata |

---

## Quick Start

```python
from bs4 import BeautifulSoup

html = """
<html><body>
<h1 class="title">Hello World</h1>
<ul>
  <li><a href="/page1">Page 1</a></li>
  <li><a href="/page2">Page 2</a></li>
</ul>
</body></html>
"""

soup = BeautifulSoup(html, 'html.parser')
print(soup.h1.text)                    # "Hello World"
print(soup.find('h1')['class'])        # ['title']

for link in soup.find_all('a'):
    print(f"{link.text}: {link['href']}")
```

---

## Parsing

| Constructor | Description |
|---|---|
| `BeautifulSoup(markup, 'html.parser')` | Parse HTML (built-in parser) |
| `BeautifulSoup(markup, 'xml')` | Parse XML (would use lxml — NOT on iOS; raises FeatureNotFound) |
| `BeautifulSoup(markup, features='html.parser')` | Explicit feature selection |
| `BeautifulSoup(markup, 'html.parser', parse_only=SoupStrainer('a'))` | Parse only `<a>` tags (lower memory) |

---

## Navigation

### Tag Access

| Method | Description |
|---|---|
| `soup.tag` | First tag by name (e.g. `soup.h1`) |
| `soup.tag.string` | Direct string content (`None` if nested) |
| `soup.tag.text` / `soup.tag.get_text()` | All text (recursive) |
| `soup.tag.get_text(separator, strip)` | Text with custom separator |
| `soup.tag.name` | Tag name string |
| `soup.tag['attr']` | Get attribute value (raises `KeyError`) |
| `soup.tag.get('attr', default)` | Get attribute (returns default) |
| `soup.tag.attrs` | Dict of all attributes |
| `soup.tag.has_attr('class')` | Check attribute existence |

### Tree Navigation

| Property | Description |
|---|---|
| `tag.parent` | Parent element |
| `tag.parents` | Iterator over all ancestors |
| `tag.children` | Direct children iterator |
| `tag.descendants` | All descendants (recursive) |
| `tag.contents` | List of direct children |
| `tag.next_sibling` / `previous_sibling` | Adjacent siblings |
| `tag.next_siblings` / `previous_siblings` | Iterators |
| `tag.next_element` / `previous_element` | Parse-order traversal |

---

## Searching

### `find()` — First Match

```python
soup.find('div')
soup.find('div', class_='content')
soup.find('a', href='/page1')
soup.find('div', id='main')
soup.find('span', attrs={'data-id': '42'})
soup.find('p', string='Hello')
soup.find('p', string=re.compile('Hell'))
```

### `find_all()` — All Matches

```python
soup.find_all('a')
soup.find_all(['a', 'p'])
soup.find_all('div', class_='item')
soup.find_all('a', limit=5)
soup.find_all('p', string=True)
soup.find_all('div', recursive=False)
soup.find_all(True)
soup.find_all(class_=re.compile('^nav'))
```

### `select()` — CSS Selectors (via soupsieve)

```python
soup.select('div.content')                  # <div class="content">
soup.select('#main')                        # id="main"
soup.select('ul > li')                      # Direct children
soup.select('div li')                       # Descendants
soup.select('a[href]')                      # Has attribute
soup.select('a[href="/page1"]')             # Exact value
soup.select('a[href^="http"]')              # Starts with
soup.select('a[href$=".pdf"]')              # Ends with
soup.select('a[href*="example"]')           # Contains
soup.select('li:nth-of-type(2)')
soup.select('p:first-child')
soup.select('h1, h2, h3')                   # Multiple selectors
soup.select('div.a.b')                      # Multiple classes
soup.select_one('div.content')              # First match only
```

soupsieve supports CSS Level 4 selectors (`:has()`, `:is()`,
`:where()`, `:not()` with complex selectors) and most pseudo-classes.

---

## Modification

| Method | Description |
|---|---|
| `tag.string = 'new text'` | Replace string content |
| `tag['attr'] = 'value'` | Set attribute |
| `del tag['attr']` | Delete attribute |
| `tag.append(child)` | Append child |
| `tag.insert(position, child)` | Insert child at position |
| `tag.insert_before(sibling)` | Insert before tag |
| `tag.insert_after(sibling)` | Insert after tag |
| `tag.clear()` | Remove all children |
| `tag.decompose()` | Remove tag and destroy |
| `tag.extract()` | Remove tag and return it |
| `tag.replace_with(replacement)` | Replace tag |
| `tag.wrap(wrapper)` | Wrap tag in another |
| `tag.unwrap()` | Replace tag with its children |
| `soup.new_tag(name, attrs)` | Create new tag |
| `soup.new_string(s)` | Create new NavigableString |

---

## Output

| Method | Description |
|---|---|
| `str(soup)` | HTML string |
| `soup.prettify()` | Formatted HTML with indentation |
| `soup.encode('utf-8')` | Encoded bytes |
| `soup.decode()` | Unicode string |
| `tag.smooth()` | Merge adjacent NavigableStrings (cleanup pass) |

---

## Encoding (UnicodeDammit)

```python
from bs4 import UnicodeDammit

# Detect encoding of unknown-encoding bytes
dammit = UnicodeDammit(b"caf\xe9", ["utf-8", "iso-8859-1"])
print(dammit.unicode_markup)       # 'café'
print(dammit.original_encoding)    # 'iso-8859-1'
```

`UnicodeDammit` uses `charset_normalizer` internally (see
[encoding.md](encoding.md)).

---

## iOS notes

- **Pure Python parse path**: bs4 + soupsieve are pure Python. No
  native extensions, no platform-specific code paths.
- **`html.parser` only**: lxml and html5lib backends not bundled.
  `pip install html5lib` works (pure Python). lxml requires libxml2
  cross-compilation (not bundled).
- **`features='xml'` raises** `FeatureNotFound: Couldn't find a tree
  builder with the features you requested: xml`. Use
  `BeautifulSoup(xml, 'html.parser')` for relaxed parsing, or pair
  with stdlib `xml.etree.ElementTree` for strict XML.
- **No JS execution** (universal to bs4 — not iOS-specific). For
  JavaScript-heavy sites, you'd need a headless browser (not
  available on iOS).

---

## Limitations

- **lxml backend unavailable** on iOS — accept the ~3× slowdown of
  `html.parser` for large documents.
- **No XML parser** without `pip install lxml` (which fails).
- **`html.parser` is permissive but quirky** — handles malformed
  HTML differently than html5lib. If you need browser-accurate
  parsing, `pip install html5lib`.
