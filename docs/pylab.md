# pylab — legacy MATLAB-style namespace

**Version:** ships with matplotlib (no own version)  
**Type:** Pure Python (single file)  
**SPM target:** Bundled in the Python framework (single `pylab.py` at site-packages root)  
**Auto-included by:** matplotlib (historical convenience shim)  
**Total Python modules:** 1

A six-line module that re-exports everything from `numpy` and `matplotlib.pyplot` into a single flat namespace, mimicking MATLAB's "function-name = call" style. Bundled for backward compatibility with old scripts and Jupyter notebooks that start with `from pylab import *`.

Modern code uses explicit `import matplotlib.pyplot as plt; import numpy as np` instead. `pylab` exists only because so much pedagogical material (Hunter & VanderPlas era tutorials, early SciPy lecture notes) still leads with it.

## Modules

| Module | What it does |
|---|---|
| `pylab` (single file) | `from matplotlib.pyplot import *` + `import numpy as np` + `from numpy import *`. Nothing else. |

## iOS-specific notes

- **Inherits whatever pyplot does.** `plot()`, `figure()`, `show()` go through matplotlib's backend, which on iOS routes to the WebKit-based Plotly preview pane. See [matplotlib.md](matplotlib.md) for backend details.
- **Namespace pollution.** `from pylab import *` dumps ~600 names into your namespace and shadows builtins (`sum`, `min`, `max`, `any`, `all`, `abs`, `round`) with NumPy versions. Convenient for quick exploration; bad for libraries.
- **No iOS-specific patches.** The file is six lines unchanged from upstream.

## Standalone example

```python
import pylab

pylab.plot([1, 2, 3], [4, 5, 6])
pylab.title("hello")
pylab.show()
# (renders via matplotlib's Plotly-backend shim → in-app preview pane)
```

Or the MATLAB-style "everything in one namespace" form:

```python
from pylab import *

t = linspace(0, 2 * pi, 200)
plot(t, sin(t), label="sin")
plot(t, cos(t), label="cos")
legend()
show()
```

## See also

- [docs/matplotlib.md](matplotlib.md) — the actual plotting library; what `pyplot` and the iOS preview backend belong to
- [docs/numpy.md](numpy.md) — the numerical-array core that gets star-imported alongside pyplot
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
