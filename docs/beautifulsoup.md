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

---

## Parsing

| Constructor | Description |
|-------------|-------------|
| `BeautifulSoup(markup, 'html.parser')` | Parse HTML (built-in parser) |
| `BeautifulSoup(markup, 'xml')` | Parse XML (requires lxml -- use html.parser on iOS) |
| `BeautifulSoup(markup, features='html.parser')` | Explicit feature selection |

---

## Navigation

### Tag Access

| Method | Description |
|--------|-------------|
| `soup.tag` | First tag by name (e.g., `soup.h1`, `soup.p`, `soup.a`) |
| `soup.tag.string` | Direct string content (None if nested) |
| `soup.tag.text` / `soup.tag.get_text()` | All text content (recursive) |
| `soup.tag.get_text(separator, strip)` | Text with custom separator |
| `soup.tag.name` | Tag name string |
| `soup.tag['attr']` | Get attribute value (raises KeyError) |
| `soup.tag.get('attr', default)` | Get attribute (returns default) |
| `soup.tag.attrs` | Dict of all attributes |
| `soup.tag.has_attr('class')` | Check attribute existence |

### Tree Navigation

| Property | Description |
|----------|-------------|
| `tag.parent` | Parent element |
| `tag.parents` | Iterator over all ancestors |
| `tag.children` | Direct children iterator |
| `tag.descendants` | All descendants (recursive) |
| `tag.contents` | List of direct children |
| `tag.next_sibling` | Next sibling element |
| `tag.previous_sibling` | Previous sibling element |
| `tag.next_siblings` | Iterator over following siblings |
| `tag.previous_siblings` | Iterator over preceding siblings |
| `tag.next_element` | Next element in parse order |
| `tag.previous_element` | Previous element in parse order |

---

## Searching

### `find()` -- First Match

```python
soup.find('div')                            # First <div>
soup.find('div', class_='content')          # First <div class="content">
soup.find('a', href='/page1')               # <a> with specific href
soup.find('div', id='main')                 # By id
soup.find('span', attrs={'data-id': '42'})  # By arbitrary attribute
soup.find('p', string='Hello')              # By text content
soup.find('p', string=re.compile('Hell'))   # By regex
```

### `find_all()` -- All Matches

```python
soup.find_all('a')                          # All <a> tags
soup.find_all(['a', 'p'])                   # All <a> and <p>
soup.find_all('div', class_='item')         # All with class
soup.find_all('a', limit=5)                 # First 5 matches
soup.find_all('p', string=True)             # All <p> with direct string
soup.find_all('div', recursive=False)       # Direct children only
soup.find_all(True)                         # All tags
soup.find_all(class_=re.compile('^nav'))    # Class matching regex
soup.find_all(attrs={'data-type': 'item'})  # Custom attributes
```

### `select()` -- CSS Selectors

```python
soup.select('div.content')                  # <div class="content">
soup.select('#main')                        # id="main"
soup.select('ul > li')                      # Direct children
soup.select('div li')                       # Descendants
soup.select('a[href]')                      # <a> with href attribute
soup.select('a[href="/page1"]')             # Exact attribute value
soup.select('a[href^="http"]')              # Starts with
soup.select('a[href$=".pdf"]')              # Ends with
soup.select('a[href*="example"]')           # Contains
soup.select('li:nth-of-type(2)')            # N-th of type
soup.select('p:first-child')               # First child
soup.select('h1, h2, h3')                  # Multiple selectors
soup.select('div.a.b')                     # Multiple classes
soup.select_one('div.content')             # First match only
```

---

## Modification

| Method | Description |
|--------|-------------|
| `tag.string = 'new text'` | Replace string content |
| `tag['attr'] = 'value'` | Set attribute |
| `del tag['attr']` | Delete attribute |
| `tag.append(child)` | Append child element |
| `tag.insert(position, child)` | Insert child at position |
| `tag.insert_before(sibling)` | Insert before tag |
| `tag.insert_after(sibling)` | Insert after tag |
| `tag.clear()` | Remove all children |
| `tag.decompose()` | Remove tag and destroy |
| `tag.extract()` | Remove tag and return it |
| `tag.replace_with(replacement)` | Replace tag |
| `tag.wrap(wrapper)` | Wrap tag in another tag |
| `tag.unwrap()` | Replace tag with its children |
| `soup.new_tag(name, attrs)` | Create new tag |
| `soup.new_string(s)` | Create new NavigableString |

---

## Output

| Method | Description |
|--------|-------------|
| `str(soup)` | HTML string |
| `soup.prettify()` | Formatted HTML with indentation |
| `soup.encode('utf-8')` | Encoded bytes |
| `soup.decode()` | Unicode string |

---

## Not Available

- `lxml` parser backend (not compiled for iOS -- use `html.parser`)
- `html5lib` parser backend
