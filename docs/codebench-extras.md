# CodeBench extras — host-app glue libraries

Three custom Python packages that act as the in-app glue between the
host app and the bundled libraries. Their primary use is from inside
CodeBench's in-app shell, but they're importable from any Python script
that ships with this repo.

Each now has its own dedicated documentation:

| Package | Doc | What it does |
|---|---|---|
| `offlinai_shell` | [offlinai-shell.md](offlinai-shell.md) | In-app zsh-shaped shell; 116 `@builtin` registrations covering ~108 commands (ls, grep, pip, git, pdflatex, manim, ai, …). Ctrl+C watchdog, convenience-imports, HF clone via `huggingface_hub`, OSC wire-protocol markers, tombstone deletion. **220 KB / ~8,300 lines** — the largest of the three |
| `offlinai_ai` | [offlinai-ai.md](offlinai-ai.md) | The `ai` builtin's REPL. Talks to Swift's `LlamaRunner` via signal files. Five permission modes (`nothing` / `allow` / `plan` / `auto` / `bypass`), slash-command dispatch, Qwen3.5 model registry, edit-apply diff workflow |
| `offlinai_latex` | [offlinai-latex.md](offlinai-latex.md) | Python → Swift LaTeX bridge. Routes to SwiftMath (native math), BusyTeX WASM (xelatex + CJK), pdftex (kill-switched), or Cairo (fallback). Auto-wraps math commands inside `\text{}`, caches SVGs by SHA-256 |

## Why these are bundled

These packages are technically host-app glue (CodeBench-specific), not
library code anyone would `pip install`. They're shipped here because:

1. **Reproducibility** — anyone forking python-ios-lib gets the same shell + AI surface CodeBench has, ready to wire into their own host app
2. **Self-contained** — no dependency on CodeBench source code; you could swap out the host app's Swift side and keep these unchanged
3. **Documentation** — the codebase is a working reference for "how to glue Python to a Swift host via file IPC"

If you don't want them in your bundled site-packages, just delete them
— nothing else in the python-ios-lib build chain depends on them.
