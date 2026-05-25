# offlinai_shell — in-app POSIX shell for the CodeBench Python runtime

**Version:** 0.1.0 (dist-info) — `offlinai-shell` PyPI name
**Type:** Pure Python, single file
**SPM target:** Bundled in the Python framework (host-app glue, not a public PyPI dep)
**File size:** 342 KB (~8,330 lines)
**Total `@builtin` decorations:** 116 (covers ~108 unique command names — some are aliased via stacked decorators)

A zsh-shaped REPL that runs inside the CodeBench Python interpreter. iOS bans
`fork()`, `exec()`, and `subprocess.Popen`, so every shell builtin is a pure
Python function. Anything the user types that isn't a registered builtin runs
as Python code in the same interpreter, with multi-line input buffered until
`code.compile_command()` says the statement is complete.

Called from Swift as `offlinai_shell.run_line(cmd)` per user input, or
`offlinai_shell.repl()` to take over stdin and loop forever.

## Module structure

| File | What it does |
|---|---|
| `offlinai_shell.py` | Single module — `Shell` class, 116 `@builtin` decorations, `run_line()`, `repl()`, `BUILTINS` dispatch dict |

That's it — one pure-Python file, no submodules, no C extensions.

## Public API

| Symbol | Purpose |
|---|---|
| `offlinai_shell.run_line(cmd: str)` | Run one user input line and stream output to stdout/stderr |
| `offlinai_shell.repl()` | Block forever as an interactive REPL — Swift's PTYBridge calls this |
| `offlinai_shell.Shell` | The shell state class — `prompt()`, `ps2()`, `run_line()` |
| `offlinai_shell.BUILTINS` | Dict mapping builtin name → handler function. Append-only at import time |
| `offlinai_shell.builtin(name)` | Decorator — register a new builtin. Usable from user code |

## The builtin catalog

Found via `grep -n "@builtin(" /Volumes/D/OfflinAi/app_packages/site-packages/offlinai_shell.py`
(116 decorations total — count includes stacked aliases like
`@builtin("python") @builtin("python3")`).

### File operations

| Command | Line | Notes |
|---|---|---|
| `pwd` | 1180 | Print working directory |
| `cd` | 1186 | Change directory; tracks history |
| `ls` | 1310 | ANSI-coloured listing; `-l`, `-a`, `-h` |
| `cat` | 1358 | Concatenate files |
| `head` | 1383 | First N lines |
| `tail` | 1410 | Last N lines |
| `mkdir` | 1436 | Create directories; `-p` for parents |
| `rm` | 1498 | Delete files; `-r` recursive, `-f` force. **Tombstones direct children of `~/Documents/Workspace/`** in `.codebench_deleted` so the starter-script seeder doesn't re-create them on next launch |
| `rmdir` | 1531 | Remove empty directories |
| `touch` | 1544 | Create empty files / update mtime |
| `cp` | 1555 | Copy files |
| `mv` | 1580 | Move / rename |
| `find` | 1695 | Pure-Python `find` clone — `-name`, `-type`, `-iname` |
| `tree` | 1722 | Indented tree view |
| `du` | 3585 | Disk usage per file |
| `df` | 3632 | Disk free (statvfs-based) |
| `ncdu` | 3884 | Interactive disk-usage explorer |
| `stat` | 4068 | File metadata |

### Text processing

| Command | Line | Notes |
|---|---|---|
| `echo` | 1596 | Print arguments |
| `grep` | 1666 | Regex search; `-i`, `-n`, `-r`, `-v` |
| `wc` | 1748 | Word / line / byte count |
| `sort` | 7284 | Stable sort with `-r`, `-n`, `-u` |
| `uniq` | 7324 | Adjacent-duplicate removal |
| `tr` | 7355 | Character translation |
| `cut` | 7737 | Column extraction; `-f`, `-d`, `-c` |
| `nl` | 7705 | Number lines |
| `tac` | 7719 | Reverse line order |
| `rev` | 7728 | Reverse characters in each line |
| `tee` | 7797 | Split stdout to file + screen |
| `diff` | 7817 | `difflib` unified diff |
| `xxd` / `hexdump` | 7845–46 | Hex dump |
| `less` / `more` | 7995–96 | Pager (one screen at a time) |
| `base64` | 7170 | Encode / decode |

### Hashes

| Command | Line | Algo |
|---|---|---|
| `sha256sum` | 7227 | SHA-256 |
| `sha1sum` | 7232 | SHA-1 |
| `md5sum` | 7237 | MD5 |

### System / process

| Command | Line | Notes |
|---|---|---|
| `uname` | 7243 | Kernel info |
| `whoami` | 7262 | Current user |
| `hostname` | 7274 | Device hostname (iOS device name or platform fallback) |
| `env` | 1602 | List env vars |
| `export` | 1609 | Set env vars |
| `date` | 1640 | Current time, formatted |
| `uptime` | 1646 | Shell uptime (since the `Shell` was constructed — iOS has no per-process accounting) |
| `top` / `htop` | 5104–05 | Live process list via `psutil` |
| `history` | 1764 | Command history |
| `sleep` | 7444 | Delay in seconds |
| `time` | 7458 | Time a command |
| `nproc` | 7584 | CPU core count |
| `id` | 7596 | User / group IDs |
| `bc` | 7867 | Calculator (Python expression evaluator) |
| `cal` | 7887 | Calendar (`calendar` module) |
| `ps` | 7907 | Process list (`psutil`) |
| `kill` | 7938 | Send signal — limited on iOS (no `fork()` means no child processes to kill, but you can kill threads) |
| `watch` | 7965 | Repeat a command every N seconds |

### Networking

| Command | Line | Notes |
|---|---|---|
| `ping` | 6664 | TCP-connect probe (iOS forbids raw ICMP sockets without entitlements) |
| `wget` | 6837 | `requests`-based download |
| `curl` | 6868 | `requests`-based, flag-compatible |

### Archive / compression

| Command | Line | Notes |
|---|---|---|
| `zip` | 6906 | Create `.zip` |
| `unzip` | 6949 | Extract `.zip` |
| `tar` | 6993 | Create / extract tarballs |
| `gzip` | 7071 | Compress |
| `gunzip` | 7091 | Decompress |

### Programming languages

| Command | Line | Notes |
|---|---|---|
| `python` / `python3` | 1972–73 | Run a `.py` file, `-c snippet`, `-m module`, version flags. Installs the **interrupt watchdog** (see below) for the duration of the script |
| `js` / `node` | 2359–60 | QuickJS-backed JS interpreter (see [js-engine.md](js-engine.md)) |
| `cc` / `gcc` / `clang` | 4188–90 | C compiler (TCC-based — see [c-interpreter.md](c-interpreter.md)) |
| `c++` / `g++` / `clang++` | 4200–02 | C++ compiler (see [cpp-interpreter.md](cpp-interpreter.md)) |
| `gfortran` / `f77` / `f90` / `f95` | 4212–15 | Fortran interpreter (see [fortran-interpreter.md](fortran-interpreter.md)) |
| `swift` | 4225 | Swift interpreter wrapper |

### LaTeX

| Command | Line | Notes |
|---|---|---|
| `pdflatex` | 4424 | Route through `offlinai_latex.compile_tex` |
| `latex` | 4468 | Same |
| `tex` / `pdftex` | 4478–79 | Same |
| `xelatex` | 4488 | XeLaTeX with `xeCJK` (CJK support) |
| `latex-diagnose` | 4562 | Print pdftex / BusyTeX / kpathsea framework status |
| `manim` | 7111 | Wrap manim's CLI; injects `render` subcommand if missing; uses click's `standalone_mode=False` so manim's `sys.exit()` doesn't tear down the REPL |

### AI

| Command | Line | Notes |
|---|---|---|
| `ai` | 4506 | Drop into [`offlinai_ai`](offlinai-ai.md) REPL — local llama.cpp via Swift's `LlamaRunner`. Slash commands `/help /file /show /mode /model /pull /load /ls /usage /reset /clear /quit` |

### Pip

| Command | Line | Notes |
|---|---|---|
| `pip` / `pip3` | 3107–08 | `pip._internal.cli.main.main`. Injects `--target ~/Documents/site-packages` (sandbox-writable). Skips packages already on `sys.path` so bundled torch / numpy / matplotlib aren't re-downloaded. Honours `-U` only when explicitly passed |
| `pip-install` | 4691 | Shortcut → `pip install` |
| `pip-uninstall` | 4697 | Shortcut → `pip uninstall` |
| `pip-list` | 4703 | Shortcut → `pip list` |
| `pip-show` | 4709 | Shortcut → `pip show` |
| `pip-freeze` | 4715 | Shortcut → `pip freeze` |
| `pip-check` | 4721 | Shortcut → `pip check` + diagnostic of bundled-vs-user-installed |

### Version control

| Command | Line | Notes |
|---|---|---|
| `git` | 5805 | `git clone` only — no daemon. Dispatches on URL host: GitHub / GitLab / Bitbucket / Codeberg / Gitea / Forgejo → **zipball over HTTPS**; HuggingFace → `huggingface_hub.snapshot_download` (LFS-aware). HuggingFace URLs auto-route based on prefix: `/spaces/`, `/datasets/`, bare `USER/REPO` (model). `git@host:user/repo` SSH form parsed too |

### Miscellaneous

| Command | Line | Notes |
|---|---|---|
| `clear` / `cls` | 1655–56 | ANSI clear screen |
| `exit` / `quit` | 1774–75 | Close the app (Swift listens for OSC marker) |
| `help` | 1078 | List builtins, or `help <name>` for one |
| `man` | 4100 | Print docstring (no real groff) |
| `which` | 1622 | Locate a builtin or `console_scripts` entry |
| `seq` | 7397 | Number sequence |
| `yes` | 7425 | Repeat a string forever (interruptible) |
| `file` | 7638 | Magic-byte file type identifier |
| `mktemp` | 7686 | `tempfile` wrapper |
| `basename` | 7611 | Strip directory |
| `dirname` | 7622 | Strip filename |
| `realpath` | 7630 | Resolve symlinks + relative paths |
| `crash-log` / `crashlog` | 7479–80 | Tail `~/Documents/log.txt` for previous fatal-crash records |
| `test-libs` / `test_libs` | 7535–36 | Smoke-test every bundled library — sanity check after a build |

### Universal help-flag handling

Every builtin accepts the same set of help tokens (`--help`, `-h`, `--h`, `-H`,
`-help`, `help`, `-?`, `/?`). When the user types one of these as the sole
argument, the universal handler prints the builtin's docstring instead of
running the command. Builtins that wrap a richer external CLI
(`python`, `pip`, `git`, the C/C++/Fortran compilers, the LaTeX engines) are
on a `_FORWARD_HELP` allow-list — their own help output is preserved, and
non-standard synonyms get rewritten to `--help` before dispatch.

## Runtime features

### Ctrl+C interrupt watchdog (lines 2115–2195)

On iOS the Python REPL runs on a worker thread, not the main interpreter
thread, so `signal.signal()` can't install a SIGINT handler and Swift's
`PyErr_SetInterrupt()` only reaches the main thread. Long-blocking
servers (Flask, Dash, Streamlit, anything calling `socket.accept` in a
loop) would otherwise be impossible to stop.

The `python` builtin spawns a daemon thread that polls two signal files:

- `$TMPDIR/offlinai_interrupt` — generic, any caller
- `$TMPDIR/codebench_kill.signal` — what the Swift `PythonRuntime.forceKillRunningTask` long-press Stop writes today

When either file appears, the watchdog calls
`ctypes.pythonapi.PyThreadState_SetAsyncExc()` on every live Python thread
to inject `KeyboardInterrupt`. Then it enters a 5-second burst window
re-injecting every 500 ms — the script might be in a tight C call that
won't tick bytecode until a syscall returns, so the next select/poll/sleep
return wakes up holding the exception.

### Convenience-imports for scripts (line 1913)

Before `runpy.run_path()` executes a user script, the shell pre-populates
the script's globals with ~35 stdlib names so casual scripting works
without explicit imports:

- Modules: `collections`, `csv`, `filecmp`, `json`, `math`, `re`, `shutil`, `tempfile`, `threading`, `time`, `itertools`, `functools`, `pickle`, `pathlib`, `subprocess`, `io`, `glob`, `uuid`, `hashlib`, `random`, `statistics`, `warnings`
- From `collections`: `defaultdict`, `Counter`, `OrderedDict`, `deque`, `namedtuple`, `ChainMap`
- From `concurrent.futures`: `ThreadPoolExecutor`, `ProcessPoolExecutor`, `as_completed`
- From `datetime`: `datetime`, `timedelta`, `date`
- From `itertools`: `chain`, `combinations`, `permutations`, `product`, `groupby`, `count`, `cycle`, `islice`, `accumulate`
- From `functools`: `partial`, `reduce`, `lru_cache`, `wraps`, `cache`
- From `pathlib`: `Path`

Scripts that rely on these aren't portable to vanilla Python — anything the
script's own `import` statements would resolve to overrides them, so it's
purely additive.

### SSL / certifi auto-wiring (lines 41–112)

On import, sets `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE` to
certifi's bundled CA list, and monkey-patches `ssl.create_default_context`
+ `SSLContext.load_default_certs` to inject `cafile=certifi.where()` so
**every** library that didn't ship its own bundle (httpx, urllib3,
google-cloud-storage, openai) gets working TLS verification without
per-library configuration. Required because iOS has no system CA store.

### `pip 26.3` deprecation noise filter (lines 117–184)

pip 26.3 prints `DEPRECATION: Unexpected import of 'X' after pip install
started.` for every import that happens after `pip install` returns. iOS
runs everything in one long-lived process, so this fires ~50 times for
every subsequent shell command. The filter drops it from both the
`logging` machinery and `sys.stderr`.

### Crash logging (lines 211–486)

Every builtin call writes a breadcrumb to `~/Documents/log.txt` via direct
`os.write()` + `os.fsync()`. When a builtin raises, `_log_crash` appends
a full record: timestamp, command + argv, traceback, `sys.platform`,
`uname`, app bundle path, all SSL / proxy / Python env vars, OpenSSL
version, and versions of the most common HTTP libraries (`requests`,
`urllib3`, `httpx`, `httpcore`, `h11`). Non-zero exits get the same
record without the traceback.

`faulthandler.enable()` is installed early in `repl()` so C-level
crashes (SIGSEGV, SIGBUS, SIGFPE, SIGABRT) write a thread-by-thread
Python stack trace to the same log before the kernel kills the process.

### Tombstone deletion (lines 1463–1495)

`rm` of a direct child of `~/Documents/Workspace/` appends the basename
to `.codebench_deleted` (and the legacy `.offlinai_deleted` is still
read for backward compatibility). The Swift `FilesBrowserViewController.markStarterDeleted`
mirror checks this set before re-seeding starter scripts on next launch.

### Console-script auto-dispatch (lines 730–800)

After builtin lookup fails, the shell checks for an `importlib.metadata`
`console_scripts` entry point matching the command name. If found, it
evicts the entry-point module + every submodule of its top package from
`sys.modules` (mirroring what a fresh subprocess would do — required
because module-level argparse parsers conflict on re-entry), then calls
the entry-point function directly. Makes `pypistats recent numpy` work
after `pip install pypistats` with no restart.

### OSC wire-protocol markers

ANSI OSC sequences like `\x1b]codebench;ai-on\x1b\\` switch Swift's
PTYBridge LineBuffer into AI-aware completion mode. `\x1b]codebench;ai-off\x1b\\`
restores shell defaults. The markers are stripped from the visible
terminal text.

## Use from Python (outside the host app)

```python
import offlinai_shell

# Run a single line — same as typing it at the prompt
offlinai_shell.run_line("ls /path/Documents")
offlinai_shell.run_line("grep -i error /path/log.txt")
offlinai_shell.run_line("pip install some-package")
offlinai_shell.run_line("manim -ql scene.py SquareToCircle")
offlinai_shell.run_line("git clone https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF")

# Block forever as an interactive REPL (used by the host app)
# offlinai_shell.repl()
```

## Extending it

```python
import offlinai_shell

@offlinai_shell.builtin("hello")
def my_hello(sh: offlinai_shell.Shell, argv: list[str]) -> None:
    """hello [name]  — print a greeting."""
    name = argv[0] if argv else "world"
    print(f"hello, {name}!")

# Now `hello manim` works at the prompt.
```

The decorator inserts into `BUILTINS` at registration time. Stacking
two `@builtin(...)` calls aliases (`@builtin("python") @builtin("python3")`).

## iOS-specific notes

- **No fork/exec.** Every builtin is implemented in pure Python via bundled libraries (`requests` for wget, `zipfile` for zip, `psutil` for top, `huggingface_hub` for git HF clone).
- **No real `git` daemon.** Code-hosting clones use the provider's HTTPS zipball endpoint (GitHub `/zipball/`, GitLab `/repository/archive.zip`, etc.). HuggingFace uses `huggingface_hub.snapshot_download` for proper LFS handling.
- **No real `signal.signal()`** on the worker thread — the watchdog file pattern is the iOS-safe substitute.
- **No `/etc/ssl/cert.pem`** — certifi is auto-wired at import.
- **`exit`/`quit` close the app** (via an OSC marker the Swift host listens for); they don't `sys.exit(0)` the Python interpreter.

## See also

- [offlinai-ai.md](offlinai-ai.md) — what the `ai` builtin opens
- [offlinai-latex.md](offlinai-latex.md) — what `pdflatex` / `xelatex` route to
- [pip.md](pip.md) — how the `pip` builtin's target-directory injection works
- [huggingface-hub.md](huggingface-hub.md) — the HF clone path's backend
- [c-interpreter.md](c-interpreter.md), [cpp-interpreter.md](cpp-interpreter.md), [fortran-interpreter.md](fortran-interpreter.md) — what the compiler builtins delegate to
- The host app's `PTYBridge.swift` and `PythonRuntime.swift` for the Swift-side bridges
