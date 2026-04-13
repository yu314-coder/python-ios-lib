# Minor Libraries

Smaller utility packages included as dependencies or for specific functionality.

---

## attrs (26.1.0)
Python classes without boilerplate. Used by jsonschema.
```python
from attrs import define, field
@define
class Point:
    x: float
    y: float
```

## packaging (26.0)
Version parsing and specifiers.
```python
from packaging.version import Version
v = Version("3.14.0")
print(v.major, v.minor)  # 3, 14
```

## narwhals (2.18.1)
Lightweight dataframe-like operations. Used by plotly.

## referencing (0.37.0)
JSON reference resolution. Used by jsonschema.

## soupsieve (2.8.3)
CSS selector engine for BeautifulSoup.

## srt (3.5.3)
Subtitle file parsing.
```python
import srt
subs = list(srt.parse("1\\n00:00:01,000 --> 00:00:02,000\\nHello\\n"))
print(subs[0].content)  # "Hello"
```

## decorator (5.2.1)
Function decorator utilities.

## cloup (3.0.9)
Click extension for grouped options. Used by manim.

## markdown-it-py (4.0.0)
Markdown parser. Used by rich.

## mdurl (0.1.2)
URL parsing for markdown-it. 

## typing_extensions (4.15.0)
Backported typing features.

## isosurfaces (0.1.2)
Marching squares/cubes for implicit surfaces. Used by manim.
```python
from isosurfaces import plot_isoline
# Generates 2D isolines from implicit functions
```

## cffi (2.0.0)
C Foreign Function Interface. Used by cairo bindings.

## rpds (stub)
Persistent data structures stub for iOS.
```python
from rpds import HashTrieMap, HashTrieSet, List
m = HashTrieMap({"a": 1}).insert("b", 2)  # Immutable dict
```

## pycairo
Cairo 2D graphics bindings. Used by manim for rendering.
```python
import cairo
surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 400, 300)
ctx = cairo.Context(surface)
ctx.set_source_rgb(0, 0, 1)
ctx.rectangle(50, 50, 300, 200)
ctx.fill()
surface.write_to_png("/tmp/rect.png")
```

## manimpango (0.6.1)
Pango text rendering for manim.

## mapbox_earcut
Polygon triangulation using earcut algorithm.

## pathops (skia-pathops)
Skia path operations (union, intersection, difference, XOR) for vector graphics.

## audioop
Audio operations for raw audio data processing.

## pyaudioop
Compatibility shim redirecting to audioop for Python 3.14+.
