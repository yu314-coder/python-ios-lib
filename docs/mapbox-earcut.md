# mapbox_earcut — Polygon triangulation (earcut algorithm)

**Version:** 1.0.3
**Type:** Native iOS arm64 C++ extension (`_core.cpython-314-iphoneos.so`)
**SPM target:** `Mapbox_earcut`
**Auto-included by:** Manim (`manim/utils/space_ops.py` hard-imports at load)
**Total Python modules:** 1 thin `__init__.py` + the `.so` extension

Python bindings to Mapbox's [earcut](https://github.com/mapbox/earcut.hpp)
C++ polygon triangulation library — fast, robust, handles holes and
self-intersections gracefully. Takes a polygon outline (plus optional
holes) and emits a triangle index list suitable for OpenGL / Metal
rendering.

Bundled because manim's `space_ops` imports it unconditionally at
module load time for 2D polygon fills. Even if your manim scene doesn't
explicitly use polygon mobjects, removing this library breaks
`import manim`.

## Modules

| Module | What it does |
|---|---|
| `mapbox_earcut.__init__` | Re-exports `triangulate_float32`, `triangulate_float64`, `triangulate_int32`, `triangulate_int64`, `__version__` from the compiled extension |
| `mapbox_earcut._core.*.so` | The C++ binding (header-only earcut, compiled for `arm64-apple-ios`) |

The four `triangulate_*` functions are dtype variants of the same call:
pass an `(N, 2)` numpy array of vertices plus a 1D array of "ring
endpoints" telling earcut where the outer outline ends and holes
begin, and you get back a 1D array of triangle indices (`int32` length
`3 * num_triangles`).

## iOS-specific notes

Built from the upstream `mapbox-earcut-python` source against the
iOS Python 3.14 ABI. No Python-side patches — earcut is a header-only
C++ template library with no platform dependencies, so the bindings
cross-compile cleanly.

If `import mapbox_earcut` ever fails on iOS, the cause is essentially
always the bundled `.so` being for the wrong Python ABI (rebuild
needed), not anything in this Python layer.

## Standalone example

```python
import numpy as np
import mapbox_earcut as earcut

# A square with a square hole in the middle
# Outer ring: 4 vertices (CCW)
# Hole ring:  4 vertices (CW — opposite winding)
vertices = np.array([
    # outer
    [0.0, 0.0],
    [4.0, 0.0],
    [4.0, 4.0],
    [0.0, 4.0],
    # hole
    [1.0, 1.0],
    [1.0, 3.0],
    [3.0, 3.0],
    [3.0, 1.0],
], dtype=np.float64)

# rings = [end_index_of_outer, end_index_of_hole_0, ...]
rings = np.array([4, 8], dtype=np.uint32)

tris = earcut.triangulate_float64(vertices, rings)
# tris is a 1D array of indices into `vertices` — every 3 consecutive
# entries form one triangle.
print(tris.reshape(-1, 3))
# e.g.
# [[3 0 4]
#  [5 3 4]
#  [4 0 7]
#  ...]
```

For a simple convex polygon with no holes, pass `rings=[len(vertices)]`.

## See also

- [docs/manim.md](manim.md) — primary consumer; hard-imports at module load
- [docs/cairographics.md](cairographics.md) — Cairo also handles 2D fills, but via stroke/fill paths rather than triangulated meshes
