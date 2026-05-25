# Rich — terminal formatting, tables, progress

**Version:** 13.7.0  
**Type:** Pure Python  
**SPM target:** `Rich`  
**Auto-included by:** pip, manim (via `pip._vendor`), tqdm.rich, transformers logging  
**Total Python modules:** 100

Rich text, tables, syntax-highlighted code, trees, progress bars, status spinners, pretty-printed Python objects — all rendered via ANSI escapes. On iOS the in-app shell strips ANSI for plain output by default; pass `force_terminal=True` to keep escapes if your renderer handles them.

## Modules

### Core console + output

| Module | What it does |
|---|---|
| `rich.__init__` | `print`, `inspect`, `print_json`, `get_console`, `reconfigure` |
| `rich.console` | `Console` — the central renderer; `Capture`, `Group`, `RenderGroup`, `ConsoleOptions`, `ScreenUpdate`, capture/page helpers |
| `rich.theme` | `Theme` — style-name → `Style` mapping; load from file with `Theme.from_file` |
| `rich.themes` | Built-in `DEFAULT` theme |
| `rich.default_styles` | The default style table (`bar.complete`, `progress.description`, `status.spinner`, …) |
| `rich.terminal_theme` | `TerminalTheme` — color palettes for HTML/SVG export (`MONOKAI`, `DIMMED_MONOKAI`, `NIGHT_OWLISH`, `DEFAULT_TERMINAL_THEME`) |
| `rich.measure` | `Measurement` — width measurement protocol |
| `rich.protocol` | `is_renderable`, `rich_cast` — the renderable protocol |
| `rich.region` | `Region` named tuple |
| `rich.abc` | `RichRenderable` abstract base |
| `rich.errors` | `MissingStyle`, `StyleError`, `StyleSyntaxError`, `MarkupError`, `LiveError`, `NotRenderableError` |

### Renderable widgets

| Module | What it does |
|---|---|
| `rich.text` | `Text` — styled text with span-based markup |
| `rich.style` | `Style`, `StyleType` — color + bold/italic/underline/etc. |
| `rich.styled` | `Styled` — wrap any renderable in a style |
| `rich.color` | `Color`, `ColorSystem`, `ColorType`, color-name lookups |
| `rich.color_triplet` | `ColorTriplet` named tuple (r, g, b) |
| `rich.palette` | `Palette` |
| `rich._palettes` | Built-in palette tables (256-color, EGA, Windows, Solarized) |
| `rich.markup` | BBCode-ish markup parser: `render("[bold red]hi[/]")` |
| `rich.table` | `Table`, `Column`, `Row` — the most-used widget |
| `rich.panel` | `Panel` — bordered box around any renderable |
| `rich.box` | Border-character sets (`ROUNDED`, `HEAVY`, `DOUBLE`, `SIMPLE`, `MINIMAL`, `ASCII`, `SQUARE`, …) |
| `rich.rule` | `Rule` — horizontal divider line |
| `rich.bar` | `Bar` — generic horizontal bar |
| `rich.progress` | `Progress`, `track`, `wrap_file`, `open` + all column types (`BarColumn`, `TextColumn`, `TaskProgressColumn`, `TimeRemainingColumn`, `DownloadColumn`, `TransferSpeedColumn`, `SpinnerColumn`, `MofNCompleteColumn`) |
| `rich.progress_bar` | `ProgressBar` — single bar widget |
| `rich.spinner` | `Spinner` — animated spinner |
| `rich._spinners` | Spinner-frame tables (`dots`, `line`, `arc`, `aesthetic`, `bouncingBall`, …) |
| `rich.status` | `Status` — context manager combining `Spinner` + label |
| `rich.live` | `Live` — refresh a renderable in place |
| `rich.live_render` | Internal renderer state for `Live` |
| `rich.layout` | `Layout` — split-screen / split-pane layouts |
| `rich.screen` | `Screen` — fill-the-terminal full-screen mode |
| `rich.align` | `Align` — left/center/right/justify any renderable |
| `rich.padding` | `Padding` — pad any renderable |
| `rich.constrain` | `Constrain` — cap width |
| `rich.columns` | `Columns` — multi-column flow layout |
| `rich.tree` | `Tree` — hierarchical/tree display |
| `rich.markdown` | `Markdown` — render markdown (headings, lists, code, tables) |
| `rich.syntax` | `Syntax` — Pygments-highlighted source code |
| `rich.json` | `JSON` — syntax-colored JSON with line numbers |
| `rich.pretty` | `Pretty`, `pprint`, `install` — rich `repr()` |
| `rich.repr` | `auto`, `rich_repr` — opt your class into Rich's pretty repr |
| `rich.scope` | `render_scope` — debug-print locals/globals dict |
| `rich.traceback` | `Traceback`, `install` — colored, source-context tracebacks |
| `rich.highlighter` | `Highlighter`, `ReprHighlighter`, `JSONHighlighter`, `ISO8601Highlighter`, `NullHighlighter` |
| `rich.containers` | `Renderables`, `Lines` — internal container types |
| `rich.segment` | `Segment`, `Segments` — atomic styled text run |
| `rich.cells` | Cell-width measurement (handles East Asian wide / emoji) |
| `rich.control` | ANSI cursor / screen control codes |
| `rich.ansi` | `AnsiDecoder` — parse ANSI escape sequences |
| `rich.emoji` | `Emoji`, `:rocket:`-style shortcode expansion |
| `rich._emoji_codes` / `_emoji_replace` | Emoji shortcode table + replacer |
| `rich.file_proxy` | `FileProxy` — wrap a file to route writes through Rich |
| `rich.filesize` | Human-readable byte sizes |
| `rich.logging` | `RichHandler` — drop-in `logging.Handler` |
| `rich.diagnose` | `report()` — print env diagnostics |

### Interactive

| Module | What it does |
|---|---|
| `rich.prompt` | `Prompt`, `Confirm`, `IntPrompt`, `FloatPrompt`, `InvalidResponse` |
| `rich.pager` | `Pager`, `SystemPager`, `PagerType` — paged output |

### Jupyter / IPython

| Module | What it does |
|---|---|
| `rich.jupyter` | `JupyterRenderable`, `JupyterMixin`, `print` |
| `rich._extension` | `load_ipython_extension` — `%load_ext rich` |

### Internal

| Module | What it does |
|---|---|
| `rich._null_file` | `/dev/null`-like writer for `quiet=True` consoles |
| `rich._fileno` | Safe `fileno()` lookup |
| `rich._log_render` | `RichHandler`'s row-renderer |
| `rich._inspect` | Backend for `rich.inspect()` |
| `rich._ratio` | Layout/column ratio math |
| `rich._loop` | Iter-with-first/last helpers |
| `rich._pick` | First-non-None helper |
| `rich._stack` | LIFO helper |
| `rich._timer` | Monotonic-time wrapper |
| `rich._wrap` | Soft-wrap helper |
| `rich._unicode_data` | Unicode east-asian-width / emoji-presentation tables (per Unicode 4.1–17.0) |
| `rich._export_format` | HTML/SVG export templates |
| `rich._win32_console` / `_windows` / `_windows_renderer` | Windows console shims — unused on iOS |

## iOS notes

- The in-app shell renders Rich's output as plain UTF-8 — ANSI escapes are stripped. Use `Console(force_terminal=True)` if you want raw escapes (useful for `Console.export_html()` to preserve color).
- Width is read from `shutil.get_terminal_size()` which on iOS returns `(80, 24)` unless you override. Pass `Console(width=...)` to set explicitly.
- `Live` and `Status` work but the in-app shell may not redraw at 30 FPS — bump `refresh_per_second=4` for less flicker.
- `RichHandler` works as a logging backend with no caveats.

## Example

```python
from rich.console import Console
from rich.table import Table
from rich.progress import track
import time

console = Console()

table = Table(title="iOS Python libs", show_lines=True)
table.add_column("Name", style="cyan")
table.add_column("Version", style="green", justify="right")
table.add_column("Type", style="magenta")
table.add_row("numpy",  "2.1.0",  "Native iOS arm64")
table.add_row("manim",  "0.18.x", "Pure Python")
table.add_row("rich",   "13.7.0", "Pure Python")
console.print(table)

for _ in track(range(20), description="Rendering frames"):
    time.sleep(0.05)

console.rule("[bold]done[/]")
```
