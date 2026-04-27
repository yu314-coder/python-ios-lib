# Process & I/O — psutil + filelock + watchdog

> **psutil 5.9.8** + **filelock 3.28.0** + **watchdog 4.0.0**  | **Type:** Mixed (psutil has a `.so`; filelock is pure Python; watchdog uses POSIX/native)  | **Status:** Working with iOS-specific caveats

Three small libraries that handle process introspection, cross-process
file locking, and filesystem-change notifications. All have iOS-sandbox
considerations.

---

## psutil — system + process info

> 5.9.8 — `_psutil_osx.cpython-314-iphoneos.so` is the iOS arm64 build

iOS sandbox limits what's visible: you CAN inspect your own process
+ its child threads; you CANNOT enumerate other apps' processes,
read kernel statistics that require entitlements, or get system-wide
load averages reliably.

### What works

```python
import psutil, os

# This process
me = psutil.Process(os.getpid())
print(me.memory_info().rss / 1024**2, "MiB")
print(me.cpu_percent(interval=0.5), "%")
print(me.num_threads())
print(me.create_time())                 # Unix timestamp
print(me.status())                      # 'running' / 'sleeping' / etc.
print([f.path for f in me.open_files()])
print([c.laddr for c in me.connections()])

# Children + grandchildren of THIS process
for child in me.children(recursive=True):
    print(f"  {child.pid}  {child.name()}")

# System CPU
print(psutil.cpu_count(logical=True))         # # of cores
print(psutil.cpu_percent(interval=1.0))       # whole-system %
print(psutil.cpu_percent(interval=1.0, percpu=True))  # per core

# Memory
vm = psutil.virtual_memory()
print(f"total={vm.total/1024**3:.1f}GB  used={vm.used/1024**3:.1f}GB  pct={vm.percent}%")

# Disk usage of YOUR sandbox (not / which iOS won't show)
du = psutil.disk_usage(os.path.expanduser("~/Documents"))
print(f"docs: {du.used/1024**3:.1f}GB / {du.total/1024**3:.1f}GB ({du.percent}%)")
```

### What fails on iOS

```python
psutil.process_iter()       # → only returns YOUR process + its children
psutil.boot_time()          # works, but it's the iOS device boot
psutil.users()              # → []  (no concept of users in iOS sandbox)
psutil.net_if_addrs()       # works, returns Wi-Fi + cellular interfaces
psutil.net_if_stats()       # works
psutil.sensors_battery()    # works on real device, returns None on simulator
psutil.sensors_temperatures()  # → {}  (no thermal zones exposed)
psutil.swap_memory()        # works but reports 0 — iOS uses XNU's compressor pool, not disk swap
```

### Used by CodeBench's `top` builtin

The shell's `top` / `htop` commands lean on psutil heavily for
per-process stats, then fall back to direct mach calls (via `ctypes`)
for things psutil's iOS port can't see (compressed memory pool,
GPU memory budget via Metal). See `app_packages/site-packages/offlinai_shell.py`'s `_top` function.

---

## filelock — cross-process file locking

> 3.28.0 — pure Python, uses `fcntl.flock` on POSIX

For coordinating access to a shared resource between multiple
processes (or threads). On iOS this is mostly thread-coordination
because the sandbox doesn't run multiple processes per app, but it's
still useful for:

- Preventing concurrent writes to a shared SQLite file
- Serialising access to a downloaded model file (one thread fetches,
  others wait + reuse)
- Implementing single-instance locks within a thread pool

### Usage

```python
from filelock import FileLock

lock_path = "/path/Documents/cache.lock"

with FileLock(lock_path, timeout=10):
    # Critical section — only one thread holds the lock at a time
    with open("/path/Documents/shared.json", "r+") as f:
        data = json.load(f)
        data["counter"] += 1
        f.seek(0); json.dump(data, f); f.truncate()
# Lock released
```

```python
# Non-blocking acquire — try, give up if held
from filelock import FileLock, Timeout

lock = FileLock(lock_path, timeout=0)   # 0 = don't wait
try:
    lock.acquire()
    # got it
except Timeout:
    # someone else holds the lock; do something else
    print("lock is held; skipping this round")
finally:
    if lock.is_locked:
        lock.release()
```

### iOS-specific notes

- **Lock files live in your sandbox.** Use a path under `~/Documents/`
  or `tempfile.gettempdir()` (= the app's TMPDIR). NEVER use `/tmp` —
  iOS sandbox blocks writes there.
- **Reentrant by default** — same thread acquiring twice doesn't
  deadlock (unlike a true mutex).
- **`fcntl.flock` semantics** — the lock is associated with the file
  *descriptor*, not the file. If you fork (which iOS doesn't, but
  it's worth knowing), child processes don't inherit the hold.

---

## watchdog — filesystem change notifications

> 4.0.0 — pure Python frontend; native observer per platform

For watching a directory and reacting to file create/modify/delete
events. iOS doesn't expose `kqueue`'s VNODE notifications outside
the app sandbox, so:

- Within your app's sandbox: works via `PollingObserver` (default
  on iOS)
- For files outside your sandbox (e.g. Photos library, iCloud Drive):
  doesn't work — those need iOS-specific APIs

### Polling-based watcher (the iOS path)

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
        print(f"moved: {event.src_path} → {event.dest_path}")

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

### Why polling instead of event-based

- iOS doesn't expose `FSEvents` (macOS) or `inotify` (Linux) to apps
- The default `Observer` (auto-pick) on iOS resolves to
  `PollingObserver`
- Polling overhead for ~100 files at 1 Hz is negligible
- For >10k files, increase `timeout=` to 5+ seconds

### Use cases

- Hot-reload: re-import a Python module when the user edits it
- Asset sync: regenerate a cache when a config file changes
- Live preview: refresh a chart when its data file is rewritten
  (this is how CodeBench's editor live-reloads HTML in the preview
  pane — see [webview.md](webview.md))

### iOS-specific notes

- **`Observer` (auto)** = falls back to `PollingObserver` on iOS
- **Directory must exist** when you `schedule()` — recursive watching
  doesn't auto-create
- **Modification times have ~1 second resolution** on iOS APFS;
  rapid-fire writes within the same second look like a single event
- **`recursive=True`** works but allocates a tracking set proportional
  to the file count under the path. Avoid watching `~/` (entire
  Documents dir) recursively — too many files

---

## Pairing them

A common pattern: poll a downloaded models dir, take the lock when
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
            # ... pretend-load...
            time.sleep(2)
            print(f"  loaded; rss={psutil.Process().memory_info().rss/1024**2:.0f}MiB")

obs = PollingObserver(timeout=2.0)
obs.schedule(LoadOnNew(), MODELS_DIR, recursive=False)
obs.start()
```
