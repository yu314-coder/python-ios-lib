# Process & I/O — index

Three small libraries that handle process introspection, cross-process
file locking, and filesystem-change notifications. All have iOS-sandbox
considerations. Each now has its own page — this file is just a table
of contents.

## Per-library docs

| Library | Version | What it does | Doc |
|---|---|---|---|
| **psutil** | 5.9.8 (iOS shim) | process + system info; iOS sandbox limits what's visible | [psutil.md](psutil.md) |
| **filelock** | 3.28.0 | cross-process file locking; on iOS becomes a process-wide mutex | [filelock.md](filelock.md) |
| **watchdog** | 4.0.0 | filesystem change notifications; on iOS falls back to `PollingObserver` | [watchdog.md](watchdog.md) |

## Pairing them

A common pattern: poll a downloaded-models directory, take the lock when
loading a new model, log thread state via psutil:

```python
import os, time, psutil, threading
from watchdog.observers.polling import PollingObserver
from watchdog.events import FileSystemEventHandler
from filelock import FileLock

MODELS_DIR = os.path.expanduser("~/Documents/models")
LOCK = FileLock(MODELS_DIR + "/.load.lock", timeout=30)

class LoadOnNew(FileSystemEventHandler):
    def on_created(self, event):
        if not event.src_path.endswith(".pte"):
            return
        with LOCK:
            print(f"[t={threading.get_ident()}] loading {event.src_path}")
            # ... pretend-load ...
            time.sleep(2)
            print(f"  loaded; rss={psutil.Process().memory_info().rss/1024**2:.0f}MiB")

obs = PollingObserver(timeout=2.0)
obs.schedule(LoadOnNew(), MODELS_DIR, recursive=False)
obs.start()
```

## See also

- [docs/huggingface-hub.md](huggingface-hub.md) — heavy filelock user (downloader deduplication)
- [docs/transformers.md](transformers.md) — pulls in all three indirectly
- [docs/webview.md](webview.md) — uses watchdog's `PollingObserver` for live-preview refresh
