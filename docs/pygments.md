# Pygments — syntax highlighting

**Version:** 2.18.0 (dist) / 2.19.2 (`__version__`)  
**Type:** Pure Python  
**SPM target:** `Pygments`  
**Auto-included by:** Rich (`rich.syntax`), manim, IPython, sphinx, mkdocs  
**Total Python modules:** 338 (most are auto-generated lexer files)

Syntax highlighter for ~570 languages. Three-stage pipeline — `Lexer` tokenizes source → `Formatter` emits HTML/ANSI/LaTeX/SVG/RTF/image. The top-level `highlight(code, lexer, formatter)` glues them together. Rich's `Syntax` widget and manim's `Code` mobject both delegate to Pygments under the hood.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `pygments.__init__` | `__version__`, `lex`, `format`, `highlight` (the 3 main entry points) |
| `pygments.__main__` | `python -m pygments` CLI |
| `pygments.cmdline` | CLI argument parsing + dispatch |
| `pygments.console` | ANSI color helpers (`colorize`, `reset`, `ansiformat`) |
| `pygments.token` | Token type enum — `Token.Keyword`, `Token.String`, `Token.Comment`, etc. The tree the lexer produces |
| `pygments.lexer` | Base classes: `Lexer`, `RegexLexer`, `ExtendedRegexLexer`, `DelegatingLexer`, `bygroups`, `include`, `using` |
| `pygments.formatter` | `Formatter` base class |
| `pygments.style` | `Style` base class — defines token-type → color/bold/italic map |
| `pygments.filter` | `Filter`, `simplefilter` — transform token stream between lexer + formatter |
| `pygments.util` | `get_choice_opt`, `get_int_opt`, `ClassNotFound`, encoding helpers |
| `pygments.scanner` | `Scanner` — used by hand-written lexers (e.g. Perl) |
| `pygments.regexopt` | Optimize alternation in long regex (e.g. keyword list of 1000 words) |
| `pygments.modeline` | Parse Vim/Emacs modelines to pick a lexer |
| `pygments.unistring` | Unicode category → regex character class (`Pygments.unistring.Ll`, `.Nd`, …) |
| `pygments.plugin` | Entry-point discovery for third-party lexers/formatters |
| `pygments.sphinxext` | Sphinx directive for `..pygments::` blocks |

### `pygments.lexers` — 250+ language lexers

One file per language family. Discover with `get_lexer_by_name("python")`, `get_lexer_for_filename("foo.rs")`, `get_lexer_for_mimetype("application/json")`, or `guess_lexer(code)`. Listed in `lexers._mapping`.

Highlights: `python`, `c_cpp`, `javascript` (also TypeScript, JSX, TSX), `rust`, `go`, `java`, `kotlin`, `swift`, `objective_c`, `csharp`, `ruby`, `php`, `perl`, `lisp` (Scheme, Racket, Clojure), `haskell`, `scala`, `lua`, `r`, `matlab`, `julia`, `fortran`, `asm`, `markup` (HTML), `css`, `data` (JSON, YAML, TOML, INI), `templates` (Jinja2, Mako, Django, Twig), `shell` (Bash, PowerShell, Fish), `sql`, `make`, `configs` (Apache, Nginx, Dockerfile), `dotnet`, `dart`, `elixir`, `erlang`, `nim`, `zig`, `crystal`, `solidity`, `webassembly`, `verilog`, `vhdl`, `tcl`, `vbscript`, `j` , `q`, `clean`, `prolog`, `agda`, `coq`, `lean`, `ocaml`, `sml`, plus 200+ more.

Builtin keyword/identifier tables: `_*_builtins.py` (Ada, Asymptote, CL, Cocoa, Csound, CSS, GoogleSQL, Julia, Lasso, Lilypond, Lua, Luau, MQL, MySQL, OpenEdge, PHP, Postgres, Qlik, Scheme, Scilab, SourceMod, SQL, Stan, Stata, TSQL, USD, VBScript).

### `pygments.formatters` — 13 output backends

| Submodule | Emits |
|---|---|
| `formatters.html` | `HtmlFormatter` — `<span class="k">if</span>` markup + matching CSS |
| `formatters.terminal` | `TerminalFormatter` — ANSI 16-color |
| `formatters.terminal256` | `Terminal256Formatter`, `TerminalTrueColorFormatter` — 256-color / truecolor ANSI |
| `formatters.latex` | `LatexFormatter` — `\textbf`/`\textit` with `\PYG{...}` macro |
| `formatters.svg` | `SvgFormatter` — `<text>` elements |
| `formatters.rtf` | `RtfFormatter` — Microsoft RTF |
| `formatters.bbcode` | `BBCodeFormatter` — `[color=…][b]` markup |
| `formatters.irc` | `IRCFormatter` — mIRC color codes |
| `formatters.img` | `ImageFormatter`, `JpgImageFormatter`, `GifImageFormatter`, `BmpImageFormatter` — raster image (needs Pillow) |
| `formatters.pangomarkup` | `PangoMarkupFormatter` — GTK Pango markup |
| `formatters.groff` | `GroffFormatter` — `man` page output |
| `formatters.other` | `NullFormatter`, `RawTokenFormatter`, `TestcaseFormatter` |
| `formatters._mapping` | Name → class table for `get_formatter_by_name` |

### `pygments.styles` — 46 color themes

`default`, `emacs`, `friendly`, `friendly_grayscale`, `colorful`, `autumn`, `murphy`, `manni`, `material`, `monokai`, `perldoc`, `pastie`, `borland`, `trac`, `native`, `fruity`, `bw`, `vim`, `vs`, `tango`, `rrt`, `xcode`, `igor`, `paraiso_light`, `paraiso_dark`, `lovelace`, `algol`, `algol_nu`, `arduino`, `rainbow_dash`, `abap`, `solarized` (light + dark via flag), `sas`, `staroffice`, `stata_light`, `stata_dark`, `inkpot`, `zenburn`, `gruvbox` (light + dark via flag), `dracula`, `nord` (+ `nord-darker`), `gh_dark` (GitHub dark), `one-dark` (Atom One Dark), `lilypond`, `coffee`, `lightbulb`. Listed in `styles._mapping`.

### `pygments.filters` — token-stream transforms

Built-ins (in `filters.__init__`): `CodeTagFilter` (highlight TODO/XXX/FIXME), `KeywordCaseFilter` (force upper/lower/capitalize on keywords), `NameHighlightFilter` (mark specific identifiers), `ErrorLexerFilter`, `RaiseOnErrorTokenFilter`, `VisibleWhitespaceFilter`, `GobbleFilter`, `TokenMergeFilter`.

## iOS notes

- Pure Python, no native code — works as-is.
- `formatters.img` needs Pillow + a TTF font; Pillow is shipped so it works, but choose a font that's bundled (`DejaVuSansMono.ttf` lives in `app_packages/site-packages/matplotlib/mpl-data/fonts/`).
- `TerminalFormatter` writes ANSI escapes — in the in-app shell they're stripped to plain text by default. Use `HtmlFormatter` if you want styled output in a WKWebView.
- The `_mapping` files are pre-built so `get_lexer_by_name(…)` doesn't need entry-point scanning at import time — keeps startup fast.

## Example

```python
from pygments import highlight
from pygments.lexers import get_lexer_by_name, guess_lexer
from pygments.formatters import HtmlFormatter, TerminalFormatter

code = '''
def fib(n):
    return n if n < 2 else fib(n-1) + fib(n-2)
'''

# HTML for WKWebView
fmt = HtmlFormatter(style="monokai", linenos=True, cssclass="hl")
html_page = f"<style>{fmt.get_style_defs('.hl')}</style>{highlight(code, get_lexer_by_name('python'), fmt)}"

# ANSI for the in-app shell (will be stripped to plain text, but still readable)
print(highlight(code, guess_lexer(code), TerminalFormatter(style="native")))
```
