# svgelements — SVG path parsing + transforms

**Version:** 1.9.6  
**Type:** Pure Python  
**SPM target:** `Svgelements`  
**Auto-included by:** manim (for `SVGMobject`)  
**Total Python modules:** 2 (one big file)

SVG parser focused on geometry — path arithmetic, transforms, length / bbox calculations, color/length parsing, full SVG-document traversal. Manim uses it to turn `.svg` files into mobjects. Implementation is one ~9.7 KLOC file derived from regebro's `svg.path` and mathandy's `svgpathtools`, plus a thin re-export `__init__.py`.

## Modules

| Module | What it does |
|---|---|
| `svgelements.__init__` | `from .svgelements import *` — flat re-export of every public class |
| `svgelements.svgelements` | The single implementation file. Contains 40+ classes (listed below) |

### Classes in `svgelements.svgelements`

| Class | Purpose |
|---|---|
| `SVG` | Parse + traverse a full SVG document (`SVG.parse("file.svg")`) — inherits from `Group` |
| `SVGElement` | Abstract base for all SVG elements |
| `SVGLexicalParser` | Internal recursive-descent parser for path `d=` strings and transform lists |
| `Group` | `<g>` container — `list` of children + transform |
| `Use` | `<use>` — referenced element clone |
| `ClipPath` | `<clipPath>` |
| `Pattern` | `<pattern>` |
| `Desc`, `Title` | `<desc>`, `<title>` metadata |
| `Image` | `<image>` — bitmap reference (gains rasterization if Pillow is installed) |
| `Text` | `<text>` |
| `Shape` | Base for all geometric shapes (mixes `SVGElement`, `GraphicObject`, `Transformable`) |
| `Path` | `<path>` — sequence of `PathSegment` (M, L, C, Q, A, Z); supports `*=` with `Matrix`, `.length()`, `.point(t)`, `.bbox()`, `+=` to append segments |
| `Subpath` | A subsequence of `Path` between `Move` commands |
| `Rect`, `Circle`, `Ellipse`, `SimpleLine`, `Polyline`, `Polygon` | Concrete `<rect>`/`<circle>`/`<ellipse>`/`<line>`/`<polyline>`/`<polygon>` |
| `PathSegment` | Base for path commands |
| `Move`, `Line`, `Close` (`Linear` subclass) | M, L, Z |
| `QuadraticBezier`, `CubicBezier` (`Curve` subclass) | Q, C |
| `Arc` | A — exact computation if `scipy` is importable, polyline approximation otherwise |
| `Matrix` | 3×3 affine transform — `Matrix.scale(s)`, `.rotate(deg)`, `.translate(x,y)`, `.skew(x,y)`; composition via `*`; applied to shapes via `shape *= matrix` |
| `Point` | 2D point with arithmetic and `distance_to` / `polar_to` / `angle_to` |
| `Angle` | `float` subclass — degrees / radians / turns conversion via classmethods |
| `Length` | Unit-aware (`px`, `pt`, `pc`, `mm`, `cm`, `in`, `em`, `ex`, `%`) — `.value(ppi=96, relative_length=…)` resolves to user units |
| `Color` | Hex, `rgb()`, `rgba()`, `hsl()`, named-color parsing; `Color.parse()`, `.hex`, `.red`/`.green`/`.blue`/`.alpha`, `Color.distance(a, b)` |
| `Viewbox` | `<svg viewBox="...">` parser + viewport→viewbox transform |
| `Transformable`, `GraphicObject` | Mixins providing `transform`, `stroke`, `fill`, `stroke_width`, `id`, `values` dict |

Plus a `SVGELEMENTS_VERSION = "1.9.6"` module constant.

## iOS notes

- Pure Python, no native deps — works as-is.
- File uses CRLF line terminators + `ISO-8859-1` source encoding — unusual but tolerated.
- `Arc` exact methods (chord length, midpoint at parameter `t`) prefer `scipy.special.ellipe` when scipy is available; otherwise falls back to numerical approximation. Either path works on iOS — scipy is shipped.
- `Image` rasterization needs Pillow — also shipped, so `<image>` elements decode fine.
- Manim's `SVGMobject(...)` consumes svgelements directly — see [manim-deps.md](manim-deps.md).

## Example

```python
from svgelements import SVG, Path, Circle, Rect, Matrix, Color, Length

# 1. Parse a path string
p = Path("M 10 10 L 100 10 L 100 100 Z")
print(p.length())                 # 270.0
print(p.bbox())                   # (10, 10, 100, 100)
print(p.point(0.5))               # midpoint along the path

# 2. Construct + transform shapes
circle = Circle(cx=50, cy=50, r=30, fill=Color("steelblue"))
rect   = Rect(x=10, y=10, width=80, height=60)

m = Matrix.scale(2, 2) * Matrix.translate(100, 0)
circle *= m

# 3. Resolve relative units against a viewport
w = Length("50%").value(relative_length=800)   # 400.0
em = Length("1.5em").value(ppi=96)             # 24.0

# 4. Walk a full document
doc = SVG.parse("/tmp/icon.svg", reify=True)
for el in doc.elements():
    if isinstance(el, Path):
        print(el.id, el.length())
```
