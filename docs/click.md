# Click — composable CLI toolkit

**Version:** 8.1.7  
**Type:** Pure Python  
**SPM target:** `Click`  
**Auto-included by:** Flask, Dash, manim, pip  
**Total Python modules:** 17

Decorator-based command-line interface library. Flask's `flask` CLI, manim's `manim` CLI, and pip's argument parsing all run on Click. You rarely write a Click CLI for iOS (there's no shell to invoke it from), but it's a hard dependency of half the web/ML stack so it ships anyway. You can also use the underlying `style`/`echo`/`prompt` helpers from the in-app shell.

## Modules

| Module | What it does |
|---|---|
| `click.__init__` | Public API — re-exports `command`, `group`, `option`, `argument`, `echo`, `style`, `prompt`, `Context`, `Path`, all `ParamType` subclasses, etc. |
| `click.core` | Core classes: `BaseCommand`, `Command`, `Group`, `Context`, `Parameter`, `Argument`, `Option`, `CommandCollection` |
| `click.decorators` | `@command`, `@group`, `@option`, `@argument`, `@pass_context`, `@pass_obj`, `@make_pass_decorator`, `@version_option`, `@help_option`, `@password_option`, `@confirmation_option` |
| `click.types` | Built-in parameter types: `STRING`, `INT`, `FLOAT`, `BOOL`, `UUID`, `Path`, `File`, `Choice`, `IntRange`, `FloatRange`, `DateTime`, `Tuple`, `UNPROCESSED` |
| `click.termui` | Terminal I/O: `prompt`, `confirm`, `progressbar`, `style`, `secho`, `clear`, `pause`, `getchar`, `launch`, `edit`, `echo_via_pager` |
| `click.utils` | `echo`, `format_filename`, `get_app_dir`, `LazyFile`, `KeepOpenFile`, `PacifyFlushWrapper` |
| `click.exceptions` | `ClickException`, `UsageError`, `BadParameter`, `MissingParameter`, `NoSuchOption`, `BadOptionUsage`, `BadArgumentUsage`, `FileError`, `Abort`, `Exit` |
| `click.formatting` | `HelpFormatter`, `wrap_text` — help-text rendering |
| `click.parser` | The argument parser used internally by `Command.parse_args` |
| `click.testing` | `CliRunner`, `Result` — invoke commands in tests and capture stdout/stderr |
| `click.shell_completion` | Bash/zsh/fish autocompletion script generation (not useful on iOS — no shell) |
| `click.globals` | `get_current_context`, `push_context`, `pop_context` — thread-local context stack |
| `click.types` (`Path`, `File`) | Smart path/file params with `exists=`, `dir_okay=`, `writable=`, automatic open/close |
| `click._compat` | Stream encoding, Windows/Unix compat shims |
| `click._termui_impl` | Internal helpers for `termui` (progress bar engine, pager invocation) |
| `click._textwrap` | Help-text wrapping that respects ANSI escape codes |
| `click._winconsole` | Windows console handling — unused on iOS |
| `click._utils` | Internal sentinels (`UNSET`, `FLAG_NEEDS_VALUE`) |

## iOS notes

- **No shell to invoke from.** Click CLIs work when called via `CliRunner` programmatically or from the in-app shell, but you don't get a global `mycli` command at the OS prompt.
- **`prompt`/`confirm`** read from `sys.stdin`. In the in-app shell that's wired to the input field; in a script it'll block waiting for stdin that never arrives. Pass `default=` so non-interactive runs don't hang.
- **`launch(url)`** opens via `webbrowser.open` which on iOS does nothing useful — use the host app's WKWebView instead.
- **`edit()`** spawns `$EDITOR`, which doesn't exist on iOS. Don't use it.
- **`progressbar`** writes to stderr with carriage returns — renders fine in the in-app shell.

## Example

```python
import click

@click.group()
def cli():
    """Toy CodeBench command group."""

@cli.command()
@click.option("--name", default="world", help="Who to greet")
@click.option("--count", "-n", default=1, type=int, help="Repeat N times")
def hello(name, count):
    for _ in range(count):
        click.secho(f"Hello, {name}!", fg="green", bold=True)

@cli.command()
@click.argument("path", type=click.Path(exists=True, dir_okay=False))
def show(path):
    with open(path) as f:
        click.echo_via_pager(f.read())

# Programmatic invocation (works on iOS, no shell needed)
from click.testing import CliRunner
result = CliRunner().invoke(cli, ["hello", "--name", "CodeBench", "-n", "2"])
print(result.output)
```
