# svgelements

> **Version:** 1.9.6 | **Type:** Stock (pure Python) | **Status:** Fully working

SVG path parsing and manipulation. Used by manim for vector graphics.

---

## Usage

```python
from svgelements import SVG, Path, Circle, Rect, Line, Matrix

# Parse SVG path
path = Path("M 10 10 L 100 10 L 100 100 Z")
print(f"Length: {path.length()}")
print(f"Bounding box: {path.bbox()}")

# Create shapes
circle = Circle(cx=50, cy=50, r=30)
rect = Rect(x=10, y=10, width=80, height=60)

# Transform
m = Matrix.scale(2, 2)
path *= m
```

## Key Classes

| Class | Description |
|-------|-------------|
| `Path` | SVG path (M, L, C, Q, A, Z commands) |
| `Circle`, `Ellipse` | Circle/ellipse shapes |
| `Rect`, `Line`, `Polyline`, `Polygon` | Basic shapes |
| `Matrix` | 2D affine transform (translate, rotate, scale, skew) |
| `SVG` | Full SVG document parser |
| `Color` | Color parsing (hex, rgb, named colors) |
| `Length` | Unit-aware length (px, pt, em, %) |
