# Pygments

> **Version:** 2.20.0 | **Type:** Stock (pure Python) | **Status:** Fully working

Syntax highlighting library. Used by manim and rich.

---

## Usage

```python
from pygments import highlight
from pygments.lexers import PythonLexer, CLexer, get_lexer_by_name
from pygments.formatters import HtmlFormatter, TerminalFormatter

code = """
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
"""

# HTML output
html = highlight(code, PythonLexer(), HtmlFormatter(full=True))
print(html[:200])

# Get lexer by name
lexer = get_lexer_by_name('c')
```

## Supported Languages

300+ lexers including: Python, C, C++, Java, JavaScript, Rust, Go, SQL, HTML, CSS, JSON, YAML, Bash, Swift, Kotlin, Ruby, PHP, and many more.
