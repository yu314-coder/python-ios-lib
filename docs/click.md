# Click

> **Version:** 8.3.2 | **Type:** Stock (pure Python) | **Status:** Working

Command-line interface creation library. Used by manim as a dependency.

---

## Usage

```python
import click

@click.command()
@click.option('--name', default='World', help='Who to greet')
@click.option('--count', default=1, type=int, help='Number of greetings')
def hello(name, count):
    for _ in range(count):
        click.echo(f'Hello, {name}!')

# Note: CLI commands don't run interactively on iOS
# Click is included as a dependency for manim
```
