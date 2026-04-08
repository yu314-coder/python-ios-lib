# tqdm

> **Version:** 4.67.3 | **Type:** Stock (pure Python) | **Status:** Working (text output)

Progress bar library. On iOS renders as text updates.

---

## Usage

```python
from tqdm import tqdm
import time

for i in tqdm(range(100), desc="Processing"):
    time.sleep(0.01)

# Manual control
results = []
pbar = tqdm(total=50, desc="Computing")
for i in range(50):
    results.append(i**2)
    pbar.update(1)
pbar.close()
```
