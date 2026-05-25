# pathops — Skia path boolean operations

**Version:** skia-pathops 0.9.2
**Type:** Native iOS arm64 Cython extension (`_pathops.abi3.so`)
**SPM target:** Bundled in `Manim` (no standalone target)
**Auto-included by:** Manim (via svgelements / vector-graphics ops)
**Total Python modules:** 3 (`__init__.py`, `operations.py`, `_version.py`) + the `.so`

Python bindings around Google [Skia](https://skia.org/)'s
`SkPathOps` — boolean operations on filled vector paths: **union**,
**intersection**, **difference**, **reverse_difference**, **xor**, plus
path simplification. Manim uses it to combine SVG-imported shapes
(e.g. for `Difference()`, `Union()`, `Intersection()` mobjects) and to
clean up self-intersecting paths.

The wheel name is `skia-pathops` on PyPI but it imports as `pathops` —
that's why the SPM bundle and the file all use `pathops/`.

## Modules

| Module | What it does |
|---|---|
| `pathops.__init__` | Re-exports the Cython extension's public API: `Path`, `PathPen`, `PathVerb`, `PathOp`, `FillType`, `LineCap`, `LineJoin`, `ArcSize`, `Direction`, `op`, `simplify`, `OpBuilder`, plus errors (`PathOpsError`, `UnsupportedVerbError`, `OpenPathError`, `NumberOfPointsError`) and conversion helpers (`bits2float`, `float2bits`, `decompose_quadratic_segment`). Also handles a Python 3.11+ IntFlag iteration quirk |
| `pathops.operations` | Friendly named wrappers around `op(...)` — `union`, `intersection`, `difference`, `reverse_difference`, `xor`. These accept lists of "drawable contours" (fontTools-style pen-protocol objects) instead of raw paths, which is what tools like manim and fontTools work with natively |
| `pathops._version` | `__version__ = '0.9.2'` (setuptools-scm generated) |
| `pathops._pathops.abi3.so` | The Cython extension (uses Python's `abi3` stable ABI, so it works across CPython 3.x versions on iOS arm64) |

## iOS-specific notes

The extension is `abi3`-tagged (`_pathops.abi3.so`), meaning it's
compatible with any CPython 3.x on iOS arm64 — no recompile needed when
the system Python version bumps from 3.13 → 3.14. This is unusual in
our bundle (most extensions are Python-version-locked
`.cpython-314-iphoneos.so`) and is a deliberate upstream design choice
from `skia-pathops`.

The underlying Skia path-ops library is a small subset of Skia
(geometry only, no rasterization), so the build doesn't drag in
Skia's full GPU/text/image stack. It links statically.

## Standalone example

```python
from pathops import Path, op, PathOp, simplify

# Build two overlapping circles
a = Path()
pen_a = a.getPen()
pen_a.moveTo((-1, 0))
pen_a.curveTo((-1, 0.55), (-0.55, 1), (0, 1))
pen_a.curveTo((0.55, 1), (1, 0.55), (1, 0))
pen_a.curveTo((1, -0.55), (0.55, -1), (0, -1))
pen_a.curveTo((-0.55, -1), (-1, -0.55), (-1, 0))
pen_a.closePath()

b = Path()
pen_b = b.getPen()
pen_b.moveTo((0, 0))
pen_b.curveTo((0, 0.55), (0.45, 1), (1, 1))
pen_b.curveTo((1.55, 1), (2, 0.55), (2, 0))
pen_b.curveTo((2, -0.55), (1.55, -1), (1, -1))
pen_b.curveTo((0.45, -1), (0, -0.55), (0, 0))
pen_b.closePath()

# Union of the two circles → a single combined path
result = Path()
op(a, b, PathOp.UNION, fix_winding=True, result=result)

# Iterate the resulting path's segments
for verb, points in result:
    print(verb, points)

# High-level wrappers for fontTools-style "draw onto a pen" inputs:
from pathops.operations import union, difference
out = Path()
out_pen = out.getPen()
union([a, b], out_pen)        # same effect as op(...) above
```

Use `simplify(path)` to remove self-intersections and combine overlapping
sub-paths into a single fill region — handy after combining manually
authored SVG geometry.

## See also

- [docs/manim.md](manim.md) — primary consumer (vector-shape boolean operations)
- [docs/cairographics.md](cairographics.md) — Cairo handles drawing; pathops handles algebra on paths before drawing
