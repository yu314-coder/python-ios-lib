# filelock — cross-process file locking

**Version:** 3.28.0  
**Type:** Pure Python (uses stdlib `fcntl.flock` on POSIX)  
**SPM target:** Bundled in the Python framework  
**Auto-included by:** HuggingFace `transformers`, `huggingface_hub`, `diffusers`, anywhere a "downloader + cache" pattern shows up  
**Total Python modules:** 14

For coordinating access to a shared resource between multiple processes — or, on iOS, between threads of the same process. The iOS sandbox doesn't run multiple processes per app, so filelock is effectively a process-wide mutex that survives across `import` cycles. Still useful for:

- Preventing concurrent writes to a shared SQLite file
- Serialising access to a downloaded model file (one thread fetches, others wait and reuse)
- Implementing single-instance locks within a thread pool
- HuggingFace's downloader uses it to deduplicate concurrent `from_pretrained()` calls

## Modules

| Module | What it does |
|---|---|
| `filelock.__init__` | Public API — re-exports `FileLock` (auto-platform), `AsyncFileLock`, `SoftFileLock`, `AsyncSoftFileLock`, `UnixFileLock`, `WindowsFileLock`, `Timeout`, `BaseFileLock`, `BaseAsyncFileLock`, `ReadWriteLock`, `AsyncReadWriteLock`, `SoftReadWriteLock`, `AsyncSoftReadWriteLock`, plus `AcquireReturnProxy` variants |
| `filelock._api` | `BaseFileLock` abstract class + `AcquireReturnProxy` (the context-manager wrapper for `lock.acquire()`) |
| `filelock._error` | `Timeout` exception |
| `filelock._unix` | `UnixFileLock` — `fcntl.flock(LOCK_EX | LOCK_NB)` implementation. `has_fcntl` flag |
| `filelock._windows` | `WindowsFileLock` — `msvcrt.locking()` (no-op on iOS) |
| `filelock._soft` | `SoftFileLock` — pure-Python `os.open(..., O_EXCL | O_CREAT)` for filesystems without `fcntl` |
| `filelock._soft_rw` | `SoftReadWriteLock` + `AsyncSoftReadWriteLock` (advisory R/W variant) |
| `filelock._read_write` | `ReadWriteLock` — multi-reader / single-writer (SQLite-backed counter) |
| `filelock._async_read_write` | `AsyncReadWriteLock` + `AsyncAcquireReadWriteReturnProxy` (asyncio wrapper) |
| `filelock.asyncio` | `BaseAsyncFileLock`, `AsyncFileLock`, `AsyncSoftFileLock`, `AsyncUnixFileLock`, `AsyncWindowsFileLock`, `AsyncAcquireReturnProxy` |
| `filelock._util` | Path-normalization + retry helpers |
| `filelock.version` | Single-string `version` = "3.28.0" |
| `filelock.py.typed` | PEP 561 marker (file, not module) |

On iOS the auto-picked `FileLock` resolves to `UnixFileLock` (because `has_fcntl` is True under the iOS Python build).

## iOS-specific notes

- **No iOS patches.** Pure Python; `fcntl.flock` is supported by iOS's POSIX layer.
- **Lock files live in your sandbox.** Use a path under `~/Documents/` or `tempfile.gettempdir()` (= the app's TMPDIR). NEVER use `/tmp` — iOS sandbox blocks writes there. NEVER use `/var/folders` — same.
- **Reentrant by default.** The same thread acquiring twice doesn't deadlock — `BaseFileLock` tracks `_lock_counter` per instance.
- **`fcntl.flock` semantics.** The lock is associated with the file *descriptor*, not the inode. If you fork (which iOS doesn't allow but is worth knowing), child processes don't inherit the hold.
- **`ReadWriteLock` / `AsyncReadWriteLock` need sqlite3.** They count readers in a tiny SQLite file. If your Python build was made without sqlite3 (the iOS framework includes it, so this isn't a problem), the import falls back to `None` and you get an `ImportError` at use time. The `__init__` already guards against that.
- **Stale lock cleanup is automatic.** If your process crashes mid-hold, the OS releases the `flock` when the file descriptor closes. No manual cleanup of `.lock` files needed.

## Standalone example

```python
from filelock import FileLock
import json, os

lock_path = "/path/Documents/cache.lock"

with FileLock(lock_path, timeout=10):
    # Critical section — only one thread holds the lock at a time
    with open("/path/Documents/shared.json", "r+") as f:
        data = json.load(f)
        data["counter"] += 1
        f.seek(0); json.dump(data, f); f.truncate()
# Lock released automatically on exit
```

Non-blocking acquire — try, give up if held:

```python
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

Asyncio variant (don't block the event loop):

```python
import asyncio
from filelock import AsyncFileLock

async def main():
    async with AsyncFileLock("/path/Documents/cache.lock", timeout=5):
        # critical section
        await asyncio.sleep(1)

asyncio.run(main())
```

Read/write lock (multi-reader, single-writer) — useful for caches that mostly read:

```python
from filelock import ReadWriteLock

lock = ReadWriteLock("/path/Documents/cache.rwlock")

# many readers can hold simultaneously
with lock.read():
    data = open("/path/Documents/cache.json").read()

# writers are exclusive
with lock.write():
    open("/path/Documents/cache.json", "w").write("...")
```

## See also

- [docs/psutil.md](psutil.md) — pairs naturally for "log who holds the lock" diagnostics
- [docs/watchdog.md](watchdog.md) — the third member of the original "process-and-io" trio
- [docs/process-and-io.md](process-and-io.md) — old combined doc, now a TOC
- [docs/huggingface-hub.md](huggingface-hub.md) — heavy user; every cached download takes a `FileLock`
