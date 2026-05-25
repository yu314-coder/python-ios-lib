# isosurfaces — Marching squares / cubes for implicit functions

**Version:** 0.1.2
**Type:** Pure Python (NumPy-backed)
**SPM target:** `Isosurfaces`
**Auto-included by:** Manim (`manim/mobject/graphing/functions.py`)
**Total Python modules:** 5

A small NumPy library that turns an implicit function `f(x, y) = 0` or
`f(x, y, z) = 0` into a triangulated mesh (3D) or polyline (2D). Manim
uses it for its `ImplicitFunction` mobject and for plotting
parametric/implicit curves where you don't have an explicit y=f(x)
form.

## Modules

| Module | What it does |
|---|---|
| `isosurfaces.__init__` | Re-exports `plot_isoline`, `plot_isosurface` |
| `isosurfaces.isoline` | `plot_isoline(fn, min_depth, max_quads, ...)` — 2D marching squares with adaptive quadtree refinement; returns a list of `(N, 2)` numpy arrays (polylines) |
| `isosurfaces.isosurface` | `plot_isosurface(fn, min_depth, max_cells, ...)` — 3D marching cubes with adaptive octree refinement; returns `(vertices, triangles)` arrays |
| `isosurfaces.cell` | Internal: `Quad`/`Cell` (the spatial-subdivision primitives) |
| `isosurfaces.point` | Internal: `Point` helper |

## iOS-specific patches

None — pure Python on top of NumPy. The bundled iOS NumPy works
unchanged here.

## Standalone example

```python
import numpy as np
from isosurfaces import plot_isoline

# Implicit unit circle:  x^2 + y^2 - 1 = 0
def circle(x, y):
    return x * x + y * y - 1.0

# pmin, pmax are the bounding box corners
curves = plot_isoline(
    circle,
    pmin=(-1.5, -1.5),
    pmax=( 1.5,  1.5),
    min_depth=3,
    max_quads=200,
)

for curve in curves:
    # curve is a (N, 2) numpy array — one polyline
    print(curve.shape)         # e.g. (64, 2)

# In manim:
#   from manim import ImplicitFunction
#   ImplicitFunction(lambda x, y: x**2 + y**2 - 1, color=YELLOW)
# manim calls plot_isoline internally to triangulate the curve.
```

3D example (a sphere):

```python
from isosurfaces import plot_isosurface

verts, tris = plot_isosurface(
    lambda x, y, z: x*x + y*y + z*z - 1,
    pmin=(-1.2,) * 3,
    pmax=( 1.2,) * 3,
    min_depth=3,
    max_cells=1000,
)
print(verts.shape, tris.shape)   # (V, 3) (T, 3)
```

## See also

- [docs/manim.md](manim.md) — primary consumer
- [docs/numpy.md](numpy.md) — the array backbone
