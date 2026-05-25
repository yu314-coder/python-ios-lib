# offlinai_ai — local LLM coding-CLI bridge

**Version:** 0.1.0 (dist-info) — `offlinai-ai` PyPI name
**Type:** Pure Python, single file
**SPM target:** Bundled in the Python framework (host-app glue)
**File size:** 1,352 lines
**Backend:** Swift `LlamaRunner` (llama.cpp on Metal) via file-IPC

The `ai` builtin in [offlinai_shell](offlinai-shell.md). Provides an
interactive REPL where each user turn ships a prompt to the Swift-side
`LlamaRunner`, streams the tokens back as they're sampled, optionally
extracts a fenced code block, and writes it to disk under a permission
mode the user controls.

The Python side never loads a model itself — model load / sampling / cancellation all happen in Swift's llama.cpp + Metal pipeline. Communication is by signal files in `$TMPDIR/latex_signals/` (same dir as [offlinai_latex](offlinai-latex.md)).

## Module structure

| File | What it does |
|---|---|
| `offlinai_ai/__init__.py` | Single module — `Session` dataclass, slash-command dispatch table, REPL loop, model-registry helpers, signal-file protocol |

## Public API

| Symbol | Purpose |
|---|---|
| `offlinai_ai.run(argv: list[str])` | Entry point — what `ai` in the shell invokes |
| `offlinai_ai.Session` | Per-REPL-session state (target file, history, mode, token counts, turns) |
| `offlinai_ai.PermissionMode` | One of `"nothing" | "allow" | "plan" | "auto" | "bypass"` |
| `offlinai_ai.MODEL_REGISTRY` | dict mapping shortname (e.g. `"qwen3.5:4b"`) → `(gguf_url, size_mb)` |

## Permission modes

| Mode | Behavior |
|---|---|
| `nothing` | Read-only — LLM can read files but every write is refused |
| `allow` | **Default.** Show each edit as a unified diff; prompt y/n |
| `plan` | LLM writes a multi-step plan first; user edits the plan; then it's applied |
| `auto` | Apply edits < 5 lines changed automatically; prompt for larger ones |
| `bypass` | Apply every edit automatically, no prompts |

All actual disk writes also append to an audit log at
`$TMPDIR/latex_signals/ai_audit.log` so a user can see exactly what
the assistant changed in a session.

## REPL surface

```text
$ ai                      # edit whatever file is in the editor
$ ai path/to/file.py      # pin the session to an explicit file
$ ai run qwen3.5:2b       # download (if needed) + load + drop into REPL
$ ai pull qwen3.5:0.8b    # download only
$ ai ls                   # list locally-cached GGUFs
$ ai load path/to/file.gguf  # load an arbitrary GGUF

ai> add type hints to all functions
ai> /mode bypass
ai> /model
ai> /usage
ai> /quit
```

## Slash commands

Found in the `_SLASH` dispatch dict at line 987 of `__init__.py`.

| Command | What it does |
|---|---|
| `/help` `/h` `/?` | Print the command list and current mode |
| `/quit` `/exit` `/q` | Leave the REPL |
| `/file [<path>]` | Show or pin the current edit target. Bare `/file` unpins (resumes auto-following the editor) |
| `/show [<path>]` (`/cat`) | Print the target or named file to the terminal |
| `/ls [<dir>]` | List files in current dir or given dir |
| `/mode [<mode>]` | Show or set permission mode (`nothing` / `allow` / `plan` / `auto` / `bypass`) |
| `/model [<name>]` | Show active GGUF, or alias of `/pull <name>` |
| `/models` | List locally-cached GGUFs under `~/Documents/Models/` |
| `/pull [<name>]` | Download a model (or list the registry) |
| `/run <name>` | Alias of `/pull` — Ollama-style verb |
| `/load <path>` | Load an already-downloaded `.gguf` (no download) |
| `/usage` | Tokens + turns this session |
| `/reset` | Wipe conversation history (keeps mode + target) |
| `/clear` | Clear the terminal screen |

## Model registry

The bundled `MODEL_REGISTRY` ships Qwen3.5 cards (released 2026-03-02) at four sizes:

| Shortname | Approx size |
|---|---|
| `qwen3.5:0.8b` | 560 MB (Q4_K_M) |
| `qwen3.5:2b` | 1.4 GB |
| `qwen3.5:4b` | 2.8 GB |
| `qwen3.5:9b` | 6.3 GB — fits on iPad M4 with 16 GB unified memory |

Pass a direct `https://…/foo.gguf` URL to `/pull` for anything outside the
registry. Models cache to `~/Documents/Models/` (visible in the iOS Files
app for inspection / delete).

> **Caveat:** Qwen3.5 GGUFs tag `arch=qwen35`, which llama.cpp maps to
> `LLM_ARCH_QWEN3NEXT` (hybrid mamba/attention with SSM kernels). On iOS
> Metal this path has previously crashed during tensor init — `EXC_BAD_ACCESS`
> loading a Qwen3.5 model is the SSM kernel, not the download.

## Signal-file protocol

All paths under `$TMPDIR/latex_signals/`. Same dir as
[offlinai_latex](offlinai-latex.md) — they don't collide because
filenames are prefixed with `ai_`.

| File | Writer | Reader | Purpose |
|---|---|---|---|
| `ai_request.json` | Python | Swift (`AIEngine`) | `{messages, max_tokens, stop?}` — written atomically via tmp + rename |
| `ai_response.stream` | Swift | Python | Appended one chunk per sampled token |
| `ai_done.txt` | Swift | Python | Two lines: status code + message. End-of-stream marker |
| `ai_cancel.txt` | Python | Swift | Touched on Ctrl-C; `AIEngine.pollCancel` calls `runner.cancelGeneration()` |
| `current_editor_file.txt` | Swift | Python | Updated on every Monaco file load; Python re-reads it before each unpinned turn |
| `ai_editor_apply.json` | Python | Swift (`LaTeXEngine`) | `{path, content}` — request to write a new file version + refresh Monaco |
| `ai_audit.log` | Python | (human) | One-line-per-write audit trail |

## Edit-apply protocol

When the LLM's response contains a fenced code block AND the block looks
like complete code (>= 80% of the original file's lines OR >= 10 lines),
the Python side treats it as an edit:

1. Build a `difflib.unified_diff` between current file and proposed content
2. Per the mode: show diff + prompt y/n, write plan, apply silently, etc.
3. If applying: write `ai_editor_apply.json` (atomic tmp + rename)
4. Swift's `LaTeXEngine.pollAIApply` (100 ms tick) picks it up and:
   - writes the new content to disk
   - refreshes Monaco's in-memory buffer
   - cancels any pending auto-save (otherwise Monaco's debounced save of the OLD buffer would immediately overwrite the AI's edit)
5. Append a line to `ai_audit.log`

## SSL context handling

iOS Python doesn't auto-discover system CA certs. `offlinai_ai` builds its
own `ssl.SSLContext` using certifi's bundled CA list — without this,
`urllib.request.urlretrieve` for model downloads would crash with
`EXC_BAD_ACCESS (code=1, address=0x1)`, which is OpenSSL deref'ing a nil
cert store on iOS. Cached after first call so we don't re-load certifi
per download.

## Use from Python

```python
import offlinai_ai

# Open the REPL with the editor-following target
offlinai_ai.run([])

# Pin a specific file
offlinai_ai.run(["src/main.py"])

# Download a model, no REPL
offlinai_ai.run(["pull", "qwen3.5:0.8b"])

# List cached models
offlinai_ai.run(["ls"])
```

Lower-level helpers exist (`_pull_and_load`, `_load_model`, `_stream_response`)
but are underscore-prefixed and not part of the stable API — the
file-IPC protocol may change.

## iOS-specific notes

- **No real `signal.signal()` interrupt** — Ctrl-C is delivered as a wire byte by `PTYBridge.LineBuffer`, the REPL writes `ai_cancel.txt`, and Swift's `runner.cancelGeneration()` aborts llama.cpp's sampling loop between tokens
- **Status code `-130`** = user-cancelled. Python doesn't record a truncated assistant turn in history when this fires
- **OSC marker `\x1b]codebench;ai-on\x1b\\`** tells the Swift LineBuffer to switch Tab-completion to slash-command vocabulary and auto-show the command menu when `/` is typed. `\x1b]codebench;ai-off\x1b\\` on exit restores shell defaults
- **Target auto-sync** — unpinned sessions re-read `current_editor_file.txt` at the top of every turn so the AI follows whichever file the user is looking at in Monaco
- **Models live in `~/Documents/Models/`** — visible in the iOS Files app, so users can delete them without the host app's help

## See also

- [offlinai-shell.md](offlinai-shell.md) — the `ai` builtin's caller
- [offlinai-latex.md](offlinai-latex.md) — uses the same `$TMPDIR/latex_signals/` IPC dir
- [huggingface-hub.md](huggingface-hub.md) — what `/pull` uses for model downloads when given an HF URL
- The host app's `AIEngine.swift` and `LlamaRunner.swift` for the Swift-side bridge
