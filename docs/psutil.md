# psutil — process and system information

**Version:** 5.9.8 (iOS shim — original C extension neutered for sandbox)  
**Type:** Mixed (Python frontend + two `.abi3.so` native modules, `_psutil_osx.abi3.so` and `_psutil_posix.abi3.so`)  
**SPM target:** Bundled in the Python framework  
**Auto-included by:** CodeBench shell builtins (`top`, `ps`), HuggingFace `accelerate`, several diagnostics tools  
**Total Python modules:** 6

Cross-platform process + system-statistics library. The iOS port reuses the macOS `_psutil_osx` C extension with the iOS-incompatible private APIs (`_IOPSCopyPowerSourcesInfo`, IOKit power-source helpers) stripped at framework-build time. What's left is enough for self-introspection and gross system stats — anything that needed Apple private APIs is gone.

iOS sandbox limits what's visible: you CAN inspect your own process and its child threads; you CANNOT enumerate other apps' processes, read kernel statistics that require entitlements, or get system-wide load averages reliably.

## Modules

| Module | What it does |
|---|---|
| `psutil.__init__` | Public API — `Process`, `cpu_count`, `cpu_percent`, `virtual_memory`, `disk_usage`, `disk_partitions`, `net_io_counters`, `net_if_addrs`, `net_if_stats`, `boot_time`, `users`, `pids`, `process_iter`, `pid_exists`, `wait_procs`, `getloadavg`, `sensors_battery`, `sensors_temperatures`, `sensors_fans`. ~5000 LOC. |
| `psutil._common` | Shared constants (`CONN_ESTABLISHED`, `CONN_LISTEN`, `STATUS_RUNNING`, `BSD`, `AIX`, `LINUX`, `MACOS`, `WINDOWS`, `SUNOS`, etc.), named tuples, helpers |
| `psutil._compat` | Python 2/3 compatibility shims (mostly no-op in this build) |
| `psutil._psposix` | POSIX-shared helpers — `wait_pid()`, `disk_usage()` via `statvfs` |
| `psutil._psosx` | macOS-specific implementation — calls into `_psutil_osx.abi3.so` and `_psutil_posix.abi3.so` |
| `psutil._psutil_osx` | Python-level wrapper around the macOS C extension (constants + error mapping) |
| `psutil._psutil_osx.abi3.so` | The native C extension (iOS-patched: IOKit power-source private API calls removed) |
| `psutil._psutil_posix.abi3.so` | POSIX-shared C helpers (network interface enumeration via `getifaddrs`) |

## iOS-specific notes

### What works

- **Self-process introspection.** `Process(os.getpid())` and everything on it: memory, CPU, threads, open files, connections, environment, command line.
- **Children of your process.** Threads exist on iOS; child processes don't. Iterating children returns at most your own pid.
- **System-wide CPU / memory.** `cpu_count()`, `cpu_percent()`, `virtual_memory()` work — they hit `host_processor_info` / `host_statistics64` mach calls which iOS allows.
- **Network interface enumeration.** `net_if_addrs()` + `net_if_stats()` return your Wi-Fi + cellular interfaces.
- **Disk usage of paths inside your sandbox.** `disk_usage("~/Documents")` works. `disk_usage("/")` is rejected by the sandbox.

### What's broken / quirky

- **`process_iter()` returns only YOUR process + children.** iOS sandbox forbids enumerating other apps. This is not a bug — the C code does `proc_listallpids()`, gets `EPERM`, returns an empty list, and psutil filters that down to "just me".
- **`users()` returns `[]`.** No concept of users in the iOS sandbox.
- **`sensors_temperatures()` returns `{}`.** Thermal zones aren't exposed to apps.
- **`sensors_battery()` returns `None` on the Simulator, real values on device.** The IOKit power-source API was stripped; we use `UIDevice.batteryLevel` exposed through a Swift bridge — only registered on real devices.
- **`swap_memory()` returns 0.** iOS uses XNU's compressor pool (compressed-memory pages in RAM), not a disk-backed swap file. The stat doesn't translate to "swap".
- **`boot_time()` returns the *device* boot time.** Useful as a uniqueish identifier; less useful for "when did my app start" (use `Process().create_time()` for that).

### Patch summary

- **`_IOPSCopyPowerSourcesInfo` and related IOKit symbols** are stripped from the C extension at build time. Calling `sensors_battery()` falls back to a Swift bridge for real-device battery state and `None` otherwise.
- **No `.py` source patches.** All deltas are in the C extension build.

## Standalone example

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

# Children + grandchildren of THIS process (usually empty on iOS)
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

### Used by CodeBench's `top` builtin

The shell's `top` / `htop` commands lean on psutil heavily for per-process stats, then fall back to direct Mach calls (via `ctypes`) for things psutil's iOS port can't see (compressed memory pool, GPU memory budget via Metal). See `app_packages/site-packages/offlinai_shell.py`'s `_top` function.

## See also

- [docs/filelock.md](filelock.md) — pairs naturally with psutil for "log who holds the lock" diagnostics
- [docs/watchdog.md](watchdog.md) — the third member of the original "process-and-io" trio
- [docs/process-and-io.md](process-and-io.md) — old combined doc, now a TOC
