# Pygments

> **Version:** 2.20.0 | **Type:** Stock (pure Python) | **Status:** Fully working

Syntax highlighting library. Used by manim and rich.

---

## Usage

```python
from pygments import highlight
from pygments.lexers import PythonLexer, CLexer, get_lexer_by_name, get_all_lexers
from pygments.formatters import HtmlFormatter, TerminalFormatter

code = """
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
"""

# HTML output
html = highlight(code, PythonLexer(), HtmlFormatter(full=True, style='monokai'))

# Get lexer by name
lexer = get_lexer_by_name('c')
lexer = get_lexer_by_name('javascript')

# Get CSS for HTML formatter
css = HtmlFormatter(style='monokai').get_style_defs('.highlight')
```

## Key Functions

| Function | Description |
|----------|-------------|
| `highlight(code, lexer, formatter)` | Highlight code string |
| `get_lexer_by_name(name)` | Get lexer by language name |
| `get_lexer_for_filename(fn)` | Get lexer by file extension |
| `get_all_lexers()` | List all available lexers |
| `get_all_formatters()` | List all formatters |
| `get_all_styles()` | List all color styles |

## Formatters

| Formatter | Description |
|-----------|-------------|
| `HtmlFormatter(full, style, linenos, cssclass)` | HTML output with CSS styling |
| `TerminalFormatter(style)` | ANSI terminal output |
| `Terminal256Formatter(style)` | 256-color terminal |
| `LatexFormatter()` | LaTeX output |
| `SvgFormatter()` | SVG output |
| `RawTokenFormatter()` | Raw token list |
| `NullFormatter()` | Plain text (no highlighting) |

## Built-in Styles

`monokai`, `default`, `emacs`, `friendly`, `fruity`, `manni`, `murphy`, `native`, `paraiso-dark`, `paraiso-light`, `pastie`, `perldoc`, `rrt`, `solarized-dark`, `solarized-light`, `tango`, `trac`, `vim`, `vs`, `xcode`, `zenburn`, `one-dark`, `github-dark`, `dracula`, `nord`

## Supported Languages

300+ lexers including: Python, C, C++, Java, JavaScript, TypeScript, Rust, Go, Swift, Kotlin, Ruby, PHP, SQL, HTML, CSS, JSON, YAML, XML, Bash, PowerShell, Haskell, Scala, Lua, R, MATLAB, Julia, Fortran, Assembly, Markdown, LaTeX, TOML, INI, Dockerfile, and many more.
