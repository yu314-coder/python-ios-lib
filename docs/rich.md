# Rich

> **Version:** 14.3.3 | **Type:** Stock (pure Python) | **Status:** Working (text output only)

Rich text formatting library. On iOS, renders to plain text (no terminal colors).

---

## Usage

```python
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.tree import Tree
from rich import print as rprint

# Tables
table = Table(title="Results")
table.add_column("Name", style="bold")
table.add_column("Score")
table.add_row("Alice", "95")
table.add_row("Bob", "87")
console = Console()
console.print(table)

# Trees
tree = Tree("Root")
tree.add("Branch 1").add("Leaf A")
tree.add("Branch 2").add("Leaf B")
console.print(tree)

# Panels
console.print(Panel("Hello from iOS!", title="OfflinAi"))
```

## Limitations

- No ANSI color output (iOS has no terminal emulator)
- Progress bars render as text
- Markdown rendering works but without styling
