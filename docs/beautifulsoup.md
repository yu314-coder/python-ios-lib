# BeautifulSoup (bs4)

> **Version:** 4.14.3 | **Type:** Stock (pure Python) | **Status:** Fully working

HTML/XML parsing library. Uses `html.parser` backend (no lxml on iOS).

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

## Key Functions

| Function | Description |
|----------|-------------|
| `BeautifulSoup(html, 'html.parser')` | Parse HTML |
| `soup.find(tag, attrs)` | Find first match |
| `soup.find_all(tag, attrs)` | Find all matches |
| `soup.select(css_selector)` | CSS selector query |
| `tag.text` / `tag.string` | Get text content |
| `tag['attr']` / `tag.get('attr')` | Get attribute |
| `tag.parent` / `tag.children` | Navigate tree |
| `tag.next_sibling` / `tag.previous_sibling` | Siblings |

## Not Available

- `lxml` parser backend (not compiled for iOS — use `html.parser`)
- `html5lib` parser backend
