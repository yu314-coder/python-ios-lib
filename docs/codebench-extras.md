# CodeBench extras — offlinai_shell + offlinai_ai + offlinai_latex

Three custom Python packages that act as the in-app glue between the
host app and the bundled libraries. Bundled here for completeness;
their primary use is from inside CodeBench's in-app shell, but they're
importable from any Python script that ships with this repo.

---

## offlinai_shell

> **6,124 lines, 108 builtins** | **Pure Python** | **Status:** Fully working

The interactive REPL behind CodeBench's terminal pane. Provides a
zsh-shaped shell where every builtin is a Python function — `ls`,
`grep`, `wget`, `pip`, `top`, `manim`, `git`, `pdflatex`, etc. all
work without any external binaries (which iOS forbids). Anything
that's not a builtin runs as Python code in the same interpreter.

### Use as a library (outside the host app)

```python
import offlinai_shell

# Run a single line — same as typing it at the prompt
offlinai_shell.run_line("ls /path/Documents")
offlinai_shell.run_line("grep -i error /path/log.txt")
offlinai_shell.run_line("pip install some-package")
offlinai_shell.run_line("manim -ql scene.py SquareToCircle")

# Block forever as an interactive REPL (used by the host app)
# offlinai_shell.repl()
```

### Builtins (108 total)

| Category | Commands |
|---|---|
| **File ops** | ls, cat, head, tail, cp, mv, rm, rmdir, mkdir, touch, cd, pwd, find, tree, stat, du, df, ncdu |
| **Text** | grep, sort, uniq, wc, tr, base64, echo, sed (basic), cut, nl, tac, rev, tee, diff, xxd, less |
| **Hashes** | sha256sum, sha1sum, md5sum |
| **System** | uname, whoami, hostname, env, export, date, uptime, top, htop, history, sleep, time, nproc, id, bc, cal, ps, kill, watch |
| **Network** | ping (TCP-connect probe), wget, curl |
| **Archive** | zip, unzip, tar, gzip, gunzip |
| **Programming** | python, python3, gcc, g++, clang, clang++, cc, c++, gfortran, f77, f90, f95 |
| **LaTeX** | pdflatex, latex, tex, pdftex, xelatex, latex-diagnose, manim |
| **Pip** | pip, pip3, pip-install, pip-uninstall, pip-list, pip-show, pip-freeze, pip-check |
| **VCS** | git (zipball-based clone via HTTPS — no real git daemon) |
| **AI** | ai (interactive CLI — model load, slash commands) |
| **Misc** | clear, cls, exit/quit (closes the app), help, man, which, seq, yes, file, mktemp, basename, dirname, realpath |

Each builtin understands the universal help token set: `--help`, `-h`,
`--h`, `-H`, `-help`, `help`, `-?`, `/?`. Help shows the docstring +
flags.

### iOS-specific behaviors

- **No fork/exec.** Every builtin is implemented in pure Python via
  the bundled libraries (e.g. `requests` for wget, `zipfile` for zip,
  `psutil` for top).
- **Wire-protocol OSC markers** — `\x1b]codebench;raw\x1b\\` etc. let
  the host app's PTY bridge switch into raw input mode for line
  editing inside `ai`. See PTYBridge.swift.
- **Tombstone deletion** — `rm` of a file under
  `~/Documents/Workspace/` writes its name to
  `.codebench_deleted` so the starter-script seeder doesn't re-create
  it on next launch. The legacy `.offlinai_deleted` is also still
  read for backward compatibility.

### Extending it

To add your own builtin:

```python
import offlinai_shell

@offlinai_shell.builtin("hello")
def my_hello(sh: offlinai_shell.Shell, argv: list[str]) -> None:
    """hello [name]  — print a greeting."""
    name = argv[0] if argv else "world"
    print(f"hello, {name}!")

# Now `hello manim` works at the prompt.
```

---

## offlinai_ai

> **1,352 lines** | **Pure Python** | **Status:** Working — supports llama.cpp + ExecuTorch backends

The `ai` builtin in offlinai_shell. Provides:

- Interactive REPL with slash commands (`/load`, `/save`, `/help`, `/temperature`, `/permission`, `/clear`)
- Model registry (Qwen3.5 0.8B / 2B / 4B preset cards)
- Streaming generation with cancellation
- Safety modes: `confirm` (ask before disk writes), `auto` (allow), `read-only` (no writes)
- Edit-apply: AI proposes a file edit → optional user confirmation → write to disk → notify the editor (via file IPC) so Monaco refreshes
- Auto-create scratch file when the editor has no target

### Use from Python

```python
import offlinai_ai

# Lower-level: send one prompt, get the response
response = offlinai_ai.chat("Explain manim's MathTex briefly")
print(response)

# Stream tokens
for token in offlinai_ai.chat_stream("Write a haiku about iOS"):
    print(token, end="", flush=True)

# Load a model explicitly (otherwise auto-loads on first call)
offlinai_ai.load("Qwen2.5-1.5B-Instruct-Q4")

# Available models in the bundled registry
print(offlinai_ai.list_models())
```

### Edit-apply protocol

When `ai` proposes an edit to the open file, it writes a JSON request
file at `$TMPDIR/latex_signals/ai_editor_apply.json`:

```json
{ "path": "/path/to/file.py", "content": "<full new content>" }
```

The Swift host's `LaTeXEngine` polls this every 100 ms and calls
`onEditorApplyRequest(path, content)`, which:

1. Writes the new content to disk
2. Refreshes Monaco's in-memory buffer
3. Cancels any pending auto-save (so the AI's edit isn't immediately
   overwritten by the editor's debounced save of the OLD buffer)

### Safety / permission modes

```python
import offlinai_ai

offlinai_ai.set_permission("read-only")    # AI cannot write any file
offlinai_ai.set_permission("confirm")      # AI proposes; UI confirmation needed
offlinai_ai.set_permission("auto")          # AI writes immediately
```

Default is `confirm`. Switch to `read-only` for "explain my code" use
cases where you don't want any disk side effects.

---

## offlinai_latex

> **1,295 lines** | **Pure Python wrapper around LaTeXEngine** | **Status:** Working — pdftex + Cairo + SwiftMath fallbacks

Bridges Python LaTeX requests to the host app's pdftex / SwiftMath
rendering pipeline. Used by manim's `MathTex` / `Tex` mobjects under
the hood.

### Public API

```python
from offlinai_latex import tex_to_svg, tex_to_png

# Render math LaTeX to an SVG file
svg_path = tex_to_svg(r"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}")
print(svg_path)   # /path/Documents/tmp/tex_<hash>.svg

# Render to PNG (used by CJK MathTex fallback)
png_path = tex_to_png(r"\text{中文 = } |QR|", dpi=300)

# Compile a full document via pdflatex
from offlinai_latex import compile_document
pdf_path = compile_document(r"""
\documentclass{article}
\usepackage{amsmath}
\begin{document}
\section{Hello}
$E = mc^2$
\end{document}
""")
```

### How it routes

```
your script
   ↓ tex_to_svg(...)
offlinai_latex
   ↓ writes request to $TMPDIR/latex_signals/compile_*.txt
LaTeXEngine.swift (host app)
   ├─ math-mode → SwiftMath (native, fast, no shell-out)
   ├─ doc-mode  → pdftex.xcframework + texmf
   └─ CJK / fontspec → BusyTeX WASM (xelatex with NotoSansJP)
   ↓ writes PDF / SVG / PNG to tmp dir
offlinai_latex returns the path
```

### Auto-wrap math in \text{}

A pre-processor wraps math-only commands appearing inside `\text{...}`
with `$...$` so user scripts that mix CJK labels with math commands
(`\underbrace`, `\boxed`, `\frac`, accents, big operators, math styles)
compile without manual fixing:

```latex
\text{對稱性: } |QR| = |RP| = 2\sqrt{2}        ← user wrote
\text{對稱性: $|QR| = |RP| = 2\sqrt{2}$}       ← auto-wrap rewrites
```

Coverage: any `\underbrace`, `\overbrace`, `\boxed`, `\frac` /
`\dfrac` / `\tfrac`, `\binom`, `\sqrt`, big operators (`\sum`,
`\prod`, `\int`, etc.), accents (`\hat`, `\bar`, `\vec`,
`\widehat`, …), `\overline` / `\underline`, math-style
(`\mathbb`, `\mathbf`, `\mathcal`, …) appearing inside `\text{}`
will be auto-wrapped, including their subscripts/superscripts and
recursively into nested `\text{}`. Existing `$...$` regions are
detected and left alone.

### Fallback chain

If pdftex fails (missing package, runaway-input loop, font lookup
miss), the bridge tries:

1. **SwiftMath** (math-only, native iOS, fastest)
2. **pdftex with --ini regenerate** (force a fresh format file)
3. **Cairo PDF→raster** (renders the partial PDF to PNG even if
   the doc was incomplete)
4. **Best-effort error message** with the offending line number

This keeps manim renders going even when individual MathTex strings
have problems.

---

## Why these are bundled in python-ios-lib

These packages are technically host-app glue (CodeBench-specific),
not library code anyone would `pip install`. They're shipped here
because:

1. **Reproducibility** — anyone forking python-ios-lib gets the same
   shell + AI surface CodeBench has, ready to wire into their own
   host app.
2. **Self-contained** — no dependency on CodeBench source code; you
   could swap out the host app's Swift side and keep these unchanged.
3. **Documentation** — the codebase is a working reference for
   "how to glue Python to a Swift host via file IPC."

If you don't want them in your bundled site-packages, just delete
them — nothing else in the python-ios-lib build chain depends on
them.

---

## See also

- [latex-engine.md](latex-engine.md) — pdftex + texmf details
- [webview.md](webview.md) — pywebview shim (uses similar file-IPC pattern)
- The host app's `LaTeXEngine.swift`, `PTYBridge.swift`, and
  `BackgroundExecutionGuard.swift` for the Swift-side bridges
