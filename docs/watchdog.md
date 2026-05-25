# watchdog — filesystem change notifications

**Version:** 4.0.0  
**Type:** Pure Python frontend; per-platform observer backends (`fsevents`, `inotify`, `kqueue`, `read_directory_changes`, polling)  
**SPM target:** Bundled in the Python framework  
**Auto-included by:** several reloader / hot-reload integrations; CodeBench's live-preview pane  
**Total Python modules:** 25

For watching a directory and reacting to file create / modify / delete events. iOS doesn't expose `kqueue`'s VNODE notifications outside the app sandbox, and FSEvents is macOS-only, so the auto-selected `Observer` on iOS resolves to **`PollingObserver`** — it `os.scandir()`s the watched tree on a timer and diffs snapshots.

- Within your app's sandbox: works via `PollingObserver` (default on iOS)
- For files outside your sandbox (e.g. Photos library, iCloud Drive): doesn't work — those need iOS-specific frameworks (PhotoKit, NSMetadataQuery)

## Modules

### Top-level

| Module | What it does |
|---|---|
| `watchdog.__init__` | Empty package marker |
| `watchdog.events` | `FileSystemEvent`, `FileCreatedEvent`, `FileModifiedEvent`, `FileDeletedEvent`, `FileMovedEvent`, `DirCreatedEvent`, `DirModifiedEvent`, `DirDeletedEvent`, `DirMovedEvent`, plus `FileSystemEventHandler`, `PatternMatchingEventHandler`, `RegexMatchingEventHandler`, `LoggingEventHandler` |
| `watchdog.version` | Version string |
| `watchdog.watchmedo` | CLI tool — `watchmedo shell-command --patterns="*.py" --command="echo {} changed"` (rarely useful on iOS — there's no shell to invoke it from) |

### `watchdog.observers` — the backends

| Submodule | What it does |
|---|---|
| `observers.__init__` | Auto-selects the best `Observer` for the platform. On iOS this falls through every native backend and lands on `PollingObserver` |
| `observers.api` | `BaseObserver`, `EventEmitter`, `EventQueue`, `ObservedWatch` — abstract base classes all backends implement |
| `observers.polling` | **`PollingObserver` — the iOS path**. `os.scandir()` + snapshot diffing on a `timeout` interval |
| `observers.fsevents` | macOS FSEvents-based observer (unavailable on iOS — no `FSEventStreamCreate` in the iOS framework) |
| `observers.fsevents2` | Newer FSEvents-based observer (same iOS limitation) |
| `observers.kqueue` | BSD `kqueue(2)` VNODE-event observer (kernel allows kqueue but apps lack the entitlement for sandbox-escaping watches) |
| `observers.inotify`, `observers.inotify_c`, `observers.inotify_buffer` | Linux `inotify(7)` observer (not applicable to iOS) |
| `observers.read_directory_changes`, `observers.winapi` | Windows `ReadDirectoryChangesW` observer (not applicable to iOS) |

### `watchdog.utils` — internal helpers

| Submodule | What it does |
|---|---|
| `utils.__init__` | `BaseThread`, `UnsupportedLibcError`, common utils |
| `utils.platform` | `is_linux()`, `is_darwin()`, `is_windows()`, `is_bsd()` — used by the auto-selector. On iOS, `is_darwin()` returns `True` but every macOS native backend import fails, so the selector falls back to polling |
| `utils.dirsnapshot` | `DirectorySnapshot`, `DirectorySnapshotDiff` — the engine powering `PollingObserver` |
| `utils.delayed_queue` | A queue that holds items for a debounce window |
| `utils.event_debouncer` | Coalesces rapid-fire events into one |
| `utils.bricks` | `SkipRepeatsQueue` — drops duplicate events |
| `utils.patterns` | `match_any_paths` + glob helpers used by `PatternMatchingEventHandler` |
| `utils.echo` | Trace-style decorator (debugging only) |
| `utils.process_watcher` | Watches a child process and emits events when it exits (CLI-only) |

### `watchdog.tricks`

| Submodule | What it does |
|---|---|
| `tricks.__init__` | Stub package — the upstream "tricks" plugins (auto-restart, shell-command, etc.) were extracted to a separate `watchdog-tricks` package. On iOS this is effectively empty |

## iOS-specific notes

- **`Observer` (auto) resolves to `PollingObserver`.** The auto-selector tries `FSEventsObserver` first (we're `is_darwin()`), but the FSEvents C API isn't in the iOS framework, so the import raises and the selector falls through `KqueueObserver` (entitlement gated) → `PollingObserver`. You can short-circuit this by importing `PollingObserver` directly.
- **Polling overhead.** For ~100 files at 1 Hz: negligible CPU. For >10k files, raise `timeout=` to 5+ seconds, or scope your watch to a smaller subtree.
- **Modification times have ~1 second resolution on iOS APFS.** Rapid-fire writes within the same second look like a single event — the snapshot diff sees one new mtime, not several.
- **`recursive=True` works** but allocates a tracking set proportional to the file count under the path. Avoid watching `~/` (entire Documents dir) recursively — too many files. Watch a workspace subdirectory instead.
- **Directory must exist** when you `schedule()` — `PollingObserver` doesn't auto-create or wait for it.
- **No iOS source patches** — the polling fallback is upstream behavior that happens to be the right choice for our platform.
- **`kqueue` quirk on iOS.** Even when `KqueueObserver` imports successfully (Apple ships the `kqueue` syscall), event delivery for sandbox-internal paths is unreliable in practice. CodeBench's preview pane explicitly forces `PollingObserver` rather than trusting auto-detect.

## Standalone example

Polling-based watcher (the iOS path):

```python
from watchdog.observers.polling import PollingObserver
from watchdog.events import FileSystemEventHandler
import time, os

class Handler(FileSystemEventHandler):
    def on_created(self, event):
        print(f"created: {event.src_path}")
    def on_modified(self, event):
        print(f"modified: {event.src_path}")
    def on_deleted(self, event):
        print(f"deleted: {event.src_path}")
    def on_moved(self, event):
        print(f"moved: {event.src_path} -> {event.dest_path}")

observer = PollingObserver(timeout=1.0)   # poll once per second
observer.schedule(Handler(),
                  path=os.path.expanduser("~/Documents/Workspace"),
                  recursive=True)
observer.start()

try:
    while True:
        time.sleep(60)
except KeyboardInterrupt:
    observer.stop()
observer.join()
```

Pattern-matching handler (only `.py` files):

```python
from watchdog.observers.polling import PollingObserver
from watchdog.events import PatternMatchingEventHandler

class OnPyChange(PatternMatchingEventHandler):
    patterns = ["*.py"]
    ignore_patterns = ["*/__pycache__/*", "*/.git/*"]
    def on_modified(self, event):
        print(f"{event.src_path} changed; reload?")

obs = PollingObserver(timeout=2.0)
obs.schedule(OnPyChange(), "/path/Documents/Workspace", recursive=True)
obs.start()
```

### Use cases

- **Hot-reload:** re-import a Python module when the user edits it
- **Asset sync:** regenerate a cache when a config file changes
- **Live preview:** refresh a chart when its data file is rewritten (this is how CodeBench's editor live-reloads HTML in the preview pane — see [webview.md](webview.md))

## See also

- [docs/psutil.md](psutil.md) — pairs for diagnostics ("which thread last touched this file")
- [docs/filelock.md](filelock.md) — pairs to serialise writes the watcher observes
- [docs/process-and-io.md](process-and-io.md) — old combined doc, now a TOC
- [docs/webview.md](webview.md) — CodeBench's live-preview pane consumer
