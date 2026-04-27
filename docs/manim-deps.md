# manim deps — pathops + mapbox_earcut + isosurfaces

> **skia-pathops 0.9.2** + **mapbox-earcut 1.0.3** + **isosurfaces 0.1.2**  | **Type:** Native iOS arm64 (skia-pathops + mapbox-earcut have `.so`s; isosurfaces is pure Python)  | **Status:** Imports work; runtime API has caveats

Three small geometry libraries that manim pulls in for path
operations, polygon triangulation, and 3D isosurface generation.
Documented together because they're rarely used directly by users —
they're transitive dependencies — but worth knowing about when
debugging manim rendering issues.

---

## pathops (skia-pathops 0.9.2)

Python bindings for [Skia](https://skia.org/)'s path-operations
library. Boolean operations on 2D vector paths: union, intersection,
difference, XOR. Used by manim's `Difference()` mobject and the
manimpango fallback path-builder.

### Quick start

```python
import pathops

# Build two square paths
a = pathops.Path()
a.moveTo(0, 0); a.lineTo(10, 0); a.lineTo(10, 10); a.lineTo(0, 10); a.close()

b = pathops.Path()
b.moveTo(5, 5); b.lineTo(15, 5); b.lineTo(15, 15); b.lineTo(5, 15); b.close()

# Union (combine into a single path)
out = pathops.Path()
pathops.union([a, b], out.getPen())
print(out.area)              # 175.0  (overlap counted once)

# Other ops:
pathops.intersection([a, b], out.getPen())      # the 5×5 overlap
pathops.difference([a], [b], out.getPen())      # a minus b
pathops.xor([a, b], out.getPen())               # symmetric difference
```

### iOS-specific notes

The 0.9.2 build ships an `_pathops.abi3.so` cross-compiled for
`arm64-apple-ios`. The smoke test sometimes shows it as **incompatible**
on the macOS Designed-for-iPad simulator (the `.so` was built for
device, not simulator):

```
ImportError: dlopen(.../pathops/_pathops.abi3.so, 0x0002):
  ... (mach-o file, but incompatible platform (have 'iOS', need 'macOS'))
```

This is **expected** when running iOS arm64 binaries on a Mac
simulator. On a real iOS device the import works.

### When you'd call it directly

- Computing a stencil mask from two arbitrary paths (e.g. clipping
  a chart to a non-rectangular region).
- Pre-computing complex shapes for SVG output that you then paint
  with PIL or Cairo.
- Manim's `Difference(MobjectA, MobjectB)` — pathops handles the
  outline subtraction.

### Limitations

- **Cubic Béziers only.** Paths use quadratic / cubic curves; if
  your input has higher-order Béziers, convert them first.
- **Single-thread** — Skia's path interpreter isn't reentrant; don't
  call `pathops.union(...)` from multiple threads simultaneously.

---

## mapbox_earcut

Pure-C polygon triangulation. Takes a polygon outline and returns a
list of triangle vertex indices suitable for OpenGL/Metal rendering.
Used by manim when converting filled shapes (Polygon, RegularPolygon,
Star, custom Polygons) into renderable triangle meshes.

### Quick start

```python
import mapbox_earcut as me
import numpy as np

# Triangulate a square (4 corners, no holes)
verts = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float64)
rings = np.array([4], dtype=np.uint32)         # one ring of 4 vertices
tris = me.triangulate_float64(verts, rings)
print(tris)        # [0 1 2  0 2 3]   — indices into verts

# Triangulate with a hole — outer ring then inner
outer = [[0,0], [10,0], [10,10], [0,10]]
hole  = [[2,2], [4,2], [4,4], [2,4]]            # square hole
verts = np.array(outer + hole, dtype=np.float64)
rings = np.array([4, 4], dtype=np.uint32)        # outer 4, then hole 4
tris = me.triangulate_float64(verts, rings)
```

### iOS-specific notes

The bundled mapbox-earcut is built with **nanobind** (a successor to
pybind11), and on iOS its strict argument typing rejects `numpy`
arrays returned by other iOS-bundled libraries that wrap them in a
`SafeArray` subclass.

If you see:

```
TypeError: triangulate_float64(): incompatible function arguments.
The following argument types are supported:
  1. triangulate_float64(arg0: ndarray[dtype=float64, shape=(*, 2), device='cpu'], …)
Invoked with types: __main__.SafeArray, __main__.SafeArray
```

…coerce explicitly via `.view(np.ndarray)`:

```python
verts_plain = np.ascontiguousarray(verts, dtype=np.float64).view(np.ndarray)
rings_plain = np.ascontiguousarray(rings, dtype=np.uint32).view(np.ndarray)
tris = me.triangulate_float64(verts_plain, rings_plain)
```

### Algorithm

Implements the [earcut algorithm](https://github.com/mapbox/earcut) —
O(n log n) average, O(n²) worst-case. Robust for any simple
polygon (no self-intersections); for crossed polygons, pre-process
with `pathops` to clean up.

### When you'd call it directly

- Custom 2D vector renderer (you have polygon paths, you want
  triangle indices for a Metal vertex buffer).
- Computing area / centroid via triangulation.

For most users: don't — manim handles this transparently.

---

## isosurfaces

Pure-Python implementation of Marching Cubes / Marching Squares
for 2D and 3D isosurface extraction. Used by manim's
`ImplicitFunction()` mobject — when you want to plot the curve where
`f(x, y) = 0`, isosurfaces extracts the polylines.

### Quick start

```python
import isosurfaces
import numpy as np

# 2D contour: x² + y² = 1 (a circle)
def f(x, y):
    return x**2 + y**2 - 1

xs = np.linspace(-2, 2, 200)
ys = np.linspace(-2, 2, 200)
contours = isosurfaces.plot_isoline(f, xs, ys, level=0)
# contours is a list of (N, 2) numpy arrays — each is a closed polyline
```

```python
# 3D: extract iso-surface mesh of a sphere
def f3(x, y, z):
    return x**2 + y**2 + z**2 - 1

xs = ys = zs = np.linspace(-2, 2, 50)
verts, tris = isosurfaces.plot_isosurface(f3, xs, ys, zs, level=0)
# verts: (N, 3)  tris: (M, 3)  — ready for Metal/OpenGL
```

### When you'd use it

- Implicit-function curves (Cassini ovals, Lissajous, anything not
  expressible as `y = f(x)`).
- Volume rendering — turn a scalar field into a mesh.
- Procedural geometry where the math is easier than the parametric form.

### Limitations

- **Pure Python — slow.** A 200×200 grid is fine; 1000×1000 is
  noticeable; 5000×5000 is painful (~30s+). For large grids,
  pre-compute on a desktop and bundle the result.
- **No adaptive sampling** — uniform grid only. Smooth functions
  with sharp corners need fine resolution to capture both regions.
- **Marching Squares topology** — for ambiguous saddle cells the
  default heuristic picks one of two valid topologies; for smooth
  surfaces this rarely matters.

---

## Why bundle these together

```
manim
 ├─ Difference / Intersection mobjects ──→ pathops
 ├─ Polygon / Star / RegularPolygon ─────→ mapbox_earcut
 └─ ImplicitFunction / FunctionGraph 3D ─→ isosurfaces
```

manim depends on all three at import time. Removing any of them
breaks `from manim import *`. They're small enough (combined ~3 MB)
that bundling all three is cheap; we don't bother gating them.

---

## Build provenance

- **skia-pathops 0.9.2** — built from upstream sources via the
  cibuildwheel iOS recipe. The Skia core is statically linked.
- **mapbox-earcut 1.0.3** — nanobind-based binding to the upstream
  C library; cross-compiled for arm64-apple-ios.
- **isosurfaces 0.1.2** — pure Python; identical to the PyPI wheel.
