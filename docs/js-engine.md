# js — JavaScript REPL backed by JavaScriptCore

> **Engine:** Apple's JavaScriptCore.framework (built into iOS — zero
> bundle cost) | **JIT:** off (iOS sandbox restriction) | **REPL persistent:**
> yes (one JSContext per app launch)

A sibling to the `python` builtin in CodeBench's shell. Type `js` to drop
into a REPL, `js -e "code"` for one-liners, or `js script.js` to run a
file. Globals persist across REPL inputs the same way Node.js' interactive
mode works.

The implementation lives in two pieces:

- **Swift** ([CodeBench/JSEngine.swift](../../OfflinAi/CodeBench/JSEngine.swift)) —
  long-lived `JSContext`, signal-watcher, exposed globals.
- **Python** (`js` builtin in
  [offlinai_shell.py](../app_packages/site-packages/offlinai_shell.py)) —
  REPL loop, file IPC over `$TMPDIR/latex_signals/js_eval_*.txt`.

---

## Quick start

```sh
% js -e "1 + 2 * 3"
7

% js -e 'console.log("hi"); 42'
hi
42

% cat > script.js << 'EOF'
const docs = __documents__;
console.log("docs lives at", docs);
const files = fs.readdirSync(docs);
console.log(`${files.length} entries`);
EOF
% js script.js
docs lives at /var/mobile/.../Documents
12 entries

% js
js (JavaScriptCore — no JIT). Blank line submits, `.exit` or Ctrl-D to quit.
js[1]> let xs = [1,2,3,4,5]
     ...
=> undefined
js[2]> xs.reduce((a,b)=>a+b)
     ...
=> 15
js[3]> .exit
%
```

---

## What's available

| Global | Notes |
|---|---|
| `console.{log,info,debug,warn,error}` | Goes to the REPL stdout. Errors come back ANSI-red. |
| `fetch(url, opts)` | **Synchronous** — semaphore-blocks the JS thread until the response arrives. Returns `{ok, status, statusText, headers, text(), json(), arrayBuffer()}`. Not spec-compliant async fetch, but ergonomic for REPL scripting. |
| `setTimeout(fn, ms)` / `setInterval(fn, ms)` | Schedules on the iOS RunLoop. Returns a numeric handle. |
| `clearTimeout(h)` / `clearInterval(h)` | Cancel a scheduled callback. |
| `fs.readFileSync(path)` | UTF-8. Returns `null` on error (no exceptions). |
| `fs.writeFileSync(path, content)` | Creates parent dirs. Returns `true`/`false`. |
| `fs.existsSync(path)` | Boolean. |
| `fs.readdirSync(path)` | Array of filenames. |
| `fs.unlinkSync(path)` | Returns `true`/`false`. |
| `__documents__` | Absolute path to `~/Documents` — paths in `fs.*` resolve against this when relative. |
| `process.{platform, version, env, cwd()}` | Node-shaped shim. `platform === "ios"`, `cwd() === __documents__`. |

Plus everything ECMAScript 2020-ish gives you natively: `Array`, `Map`,
`Set`, `Promise`, `JSON`, `Math`, async/await syntax, optional chaining,
destructuring, template literals, BigInt, `globalThis`, etc.

---

## What's NOT available

- **`require` / `import`** — there's no module loader. Drop helpers into
  globals manually, or use template literals to inline:
  ```js
  Function("module", "exports", fs.readFileSync("/path/lodash.js"))(...);
  ```
- **`npm install`** — no Node, no native modules, no fork/exec.
- **Worker threads / cluster / async hooks** — single JSContext, no
  worker pool.
- **DOM** — JSC isn't a browser. For DOM work use the pywebview shim
  (loads pages into the in-app preview pane via WKWebView).
- **JIT** — Apple restricts the JIT entitlement to Safari. Execution is
  interpreted/baseline-compiled, which costs ~3-5× vs. JIT but is fine
  for everything you'd reasonably do at a REPL.

---

## CLI flags

```sh
js [script.js | -e "code" | --reset | -h]
```

| Flag | Meaning |
|---|---|
| `<script.js> [args...]` | Read & evaluate the file. |
| `-e "<code>"` | Run a one-liner. The last expression's value (if not `undefined`/`null`) is printed. |
| `--reset` | Rebuild the JSContext — clears all globals. Useful when accumulated REPL state gets messy. |
| `-h, --help` | Help. |

`node` is registered as an alias for `js` (no Node.js compatibility
beyond what's listed above — it's there because `node script.js` is
muscle-memory for many users).

---

## REPL specifics

- Multi-line input: lines accumulate until you press Enter on a blank
  line. The whole buffer is then submitted as one script (so a function
  declaration on line 1 is in scope when you call it on line 2).
- `.exit` / `.quit` leaves the REPL.
- `.reset` rebuilds the JSContext mid-session.
- Ctrl-D / EOF leaves the REPL.

---

## Implementation notes

The REPL doesn't run JS in-process — it can't. The Python shell sends
source code to Swift's `JSEngine.shared` over the same file-IPC channel
LaTeX uses:

```
write   $TMPDIR/latex_signals/js_eval_request.txt   {id, src, reset}
        ↓ (50 ms poll on Swift side)
read    JSEngine evaluates in JSContext
write   $TMPDIR/latex_signals/js_eval_resp_<id>.txt {ok, stdout, result, error?}
        ↑ (20 ms poll on Python side)
read    Python prints stdout + result, or red-coloured error
```

Latency: ~50-100 ms per round-trip. Imperceptible at a REPL.

---

## Limitations

- **fetch blocks the JS thread.** A long network call freezes the REPL
  until it returns. There's no Promise-based variant because we have no
  way to pump the JS microtask queue from outside an active JS frame.
- **stdout is captured per-eval.** `console.log` inside a `setTimeout`
  callback fires AFTER the eval returns, so it lands in the buffer of
  the NEXT eval (or the next REPL print, if no new eval comes). Not a
  bug — just how synchronous capture interacts with deferred callbacks.
- **No Promise top-level await at the REPL.** You can write `await` in
  scripts that wrap themselves in `(async () => { … })()`, but the
  REPL doesn't auto-wrap.
- **No source maps / debug API.** Stack traces are JSC's defaults.

---

## See also

- [pywebview.md](pywebview.md) — for DOM-y JS that needs a real browser
- [CodeBench/JSEngine.swift](../../OfflinAi/CodeBench/JSEngine.swift) — Swift bridge
