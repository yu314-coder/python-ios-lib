# tqdm

> **Version:** 4.67.3 | **Type:** Stock (pure Python) | **Status:** Working (text output)

Progress bar library. On iOS renders as text updates.

---

## Usage

```python
from tqdm import tqdm, trange
import time

# Wrap any iterable
for i in tqdm(range(100), desc="Processing"):
    time.sleep(0.01)

# trange shorthand
for i in trange(100, desc="Computing"):
    time.sleep(0.01)

# Manual control
pbar = tqdm(total=50, desc="Uploading", unit="file")
for i in range(50):
    pbar.update(1)
pbar.close()

# Nested progress bars
for i in tqdm(range(3), desc="Outer"):
    for j in tqdm(range(100), desc="Inner", leave=False):
        time.sleep(0.001)
```

## Key Parameters

| Parameter | Description |
|-----------|-------------|
| `iterable` | Iterable to wrap |
| `desc` | Prefix description string |
| `total` | Total iterations (auto-detected if possible) |
| `unit` | Unit name (default: "it") |
| `unit_scale` | Auto-scale units (K, M, G) |
| `leave` | Keep bar after completion (default True) |
| `ncols` | Width of bar |
| `miniters` | Minimum update interval (iterations) |
| `mininterval` | Minimum update interval (seconds, default 0.1) |
| `disable` | Disable progress bar |
| `bar_format` | Custom format string |
| `position` | Bar position (for nested bars) |
| `initial` | Starting value |
| `dynamic_ncols` | Auto-resize width |

## Methods

| Method | Description |
|--------|-------------|
| `pbar.update(n)` | Increment by n |
| `pbar.set_description(desc)` | Update description |
| `pbar.set_postfix(**kwargs)` | Set postfix stats |
| `pbar.close()` | Close and clean up |
| `pbar.reset(total)` | Reset with new total |
| `pbar.refresh()` | Force display update |
| `pbar.clear()` | Clear display |
| `pbar.unpause()` | Resume timing |
