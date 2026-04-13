# Rich

> **Version:** 14.3.3 | **Type:** Stock (pure Python) | **Status:** Working (text output only)

Rich text formatting library. On iOS, renders to plain text (no terminal colors).

---

## Key Classes

| Class | Description |
|-------|-------------|
| `Console(width, force_terminal)` | Main output console |
| `Table(title, show_header, show_lines)` | Rich tables with columns and rows |
| `Panel(content, title, subtitle, border_style)` | Bordered panel |
| `Tree(label)` | Tree visualization |
| `Columns(renderables, equal, expand)` | Multi-column layout |
| `Text(text, style)` | Styled text |
| `Markdown(markup)` | Render markdown |
| `Syntax(code, lexer, theme, line_numbers)` | Syntax-highlighted code |
| `Pretty(object)` | Pretty-print any Python object |
| `Padding(renderable, pad)` | Add padding |
| `Align(renderable, align)` | Align content (left/center/right) |
| `Group(*renderables)` | Group renderables |
| `Rule(title, style)` | Horizontal rule |

### Console Methods

| Method | Description |
|--------|-------------|
| `console.print(*objects, style, highlight)` | Print with formatting |
| `console.log(*objects)` | Print with timestamp |
| `console.rule(title)` | Print horizontal rule |
| `console.status(status)` | Spinner status |
| `console.input(prompt)` | Styled input prompt |
| `console.export_text()` | Export as plain text |
| `console.export_html()` | Export as HTML |

### Table Methods

| Method | Description |
|--------|-------------|
| `table.add_column(header, style, justify, width)` | Add column |
| `table.add_row(*cells)` | Add data row |
| `table.add_section()` | Add section divider |

### Progress Bars

```python
from rich.progress import Progress, track
for item in track(range(100), description="Processing"):
    pass  # work
```

## Limitations

- No ANSI color output (iOS has no terminal emulator)
- Progress bars render as text
- Markdown rendering works but without styling
