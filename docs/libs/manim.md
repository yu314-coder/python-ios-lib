# manim

**Community Edition** | v0.20.1 | 145+ mobjects | 73 animations | 40+ rate functions

> Create publication-quality math animations on iPad. Renders MP4 via VideoToolbox H.264 hardware encoder + FFmpeg/PyAV.

---

## Scene Types

| Class | Description |
|-------|-------------|
| `Scene` | Base class — `construct()` defines the animation timeline |
| `ThreeDScene` | 3D camera with phi/theta/gamma, ambient rotation |
| `SpecialThreeDScene` | Advanced 3D rendering |
| `MovingCameraScene` | Pan and zoom the 2D camera frame |
| `ZoomedScene` | Zooming and magnification |
| `VectorScene` | Vector graphics demonstrations |
| `LinearTransformationScene` | Matrix transformations on grids |

---

## Mobjects (145+ classes)

### Geometry — Basic Shapes

| Class | Key Parameters |
|-------|---------------|
| `Circle` | `radius`, `color`, `fill_opacity`, `stroke_width` |
| `Dot` / `SmallDot` / `Dot3D` | `point`, `radius`, `color` |
| `Square` | `side_length`, `color`, `fill_opacity` |
| `Rectangle` / `RoundedRectangle` | `width`, `height`, `corner_radius` |
| `Triangle` / `RegularPolygon` | `n` (sides), `start_angle` |
| `Polygon` | `*vertices` (arbitrary polygon) |
| `Star` | `n`, `outer_radius`, `inner_radius` |
| `Ellipse` | `width`, `height` |
| `Annulus` | `inner_radius`, `outer_radius` |
| `Arc` / `ArcBetweenPoints` | `start_angle`, `angle`, `radius` |
| `Sector` / `AnnularSector` | `inner_radius`, `outer_radius`, `angle` |

### Geometry — Lines & Arrows

| Class | Description |
|-------|-------------|
| `Line` / `DashedLine` | Straight line between two points |
| `Arrow` / `DoubleArrow` | Arrow with configurable tip |
| `Vector` | Arrow from origin |
| `CurvedArrow` | Curved arrow path |
| `TangentLine` | Tangent to a curve at a point |
| `Elbow` | Right-angle connector |
| `LabeledArrow` / `LabeledLine` | Line/arrow with text label |

### Geometry — Arrow Tips

`ArrowTip`, `ArrowTriangleTip`, `ArrowTriangleFilledTip`, `ArrowSquareTip`, `ArrowSquareFilledTip`, `ArrowCircleTip`, `ArrowCircleFilledTip`, `StealthTip`

### Geometry — Boolean Operations

`Intersection`, `Union`, `Difference`, `Exclusion`, `ConvexHull`

### Geometry — Angles & Braces

`Angle`, `RightAngle`, `Brace`, `BraceBetweenPoints`, `BraceLabel`, `BraceText`, `ArcBrace`

### Text & Labels

| Class | Description |
|-------|-------------|
| `Text` | Plain text (Cairo rendering on iOS) |
| `MarkupText` | Pango markup formatted text |
| `MathTex` | LaTeX math mode (`$...$`) |
| `Tex` | Full LaTeX document |
| `SingleStringMathTex` | Single math expression |
| `Title` | Centered title text |
| `BulletedList` | Bulleted list items |
| `Code` | Syntax-highlighted code block |
| `Paragraph` | Multi-line paragraph |
| `DecimalNumber` / `Integer` | Animated numeric displays |
| `Variable` | Variable with label + tracker |

### Graphing & Coordinate Systems

| Class | Description |
|-------|-------------|
| `Axes` | 2D coordinate axes with configurable ranges |
| `ThreeDAxes` | 3D coordinate axes |
| `NumberPlane` | Infinite grid with axes |
| `ComplexPlane` | Complex number plane |
| `PolarPlane` | Polar coordinate system |
| `NumberLine` | Single-axis number line |
| `BarChart` | Animated bar chart |
| `CoordinateSystem` | Base class for all coordinate systems |

### Graphing — Function Plots

| Class | Description |
|-------|-------------|
| `FunctionGraph` | Plot `f(x)` on axes |
| `ParametricFunction` | Parametric curve `(x(t), y(t))` |
| `ImplicitFunction` | Implicit equation `f(x,y)=0` |

### Graphing — Graphs & Networks

`GenericGraph`, `Graph`, `DiGraph`

### 3D Objects

| Class | Description |
|-------|-------------|
| `Surface` | Parametric 3D surface `(u,v) → (x,y,z)` |
| `Sphere` | 3D sphere |
| `Cube` / `Prism` | Rectangular 3D solids |
| `Cylinder` / `Cone` | Cylindrical/conical shapes |
| `Torus` | Toroidal shape |
| `Tetrahedron` / `Octahedron` | Regular solids |
| `Icosahedron` / `Dodecahedron` | Regular solids |
| `Line3D` / `Arrow3D` | 3D line/arrow |
| `Polyhedron` | Arbitrary polyhedron from vertices/faces |

### Vector Fields

| Class | Description |
|-------|-------------|
| `ArrowVectorField` | Vector field with arrows |
| `StreamLines` | Animated streamlines |
| `VectorField` | Base vector field |

### Groups & Containers

| Class | Description |
|-------|-------------|
| `VGroup` | Group of vectorized mobjects |
| `Group` | Group of any mobjects |
| `VDict` | Dictionary-like mobject container |

### Tables & Matrices

| Class | Description |
|-------|-------------|
| `Table` / `DecimalTable` / `IntegerTable` / `MathTable` | Table with rows/columns |
| `Matrix` / `DecimalMatrix` / `IntegerMatrix` / `MobjectMatrix` | Matrix display |

### Special & Utility

| Class | Description |
|-------|-------------|
| `ValueTracker` / `ComplexValueTracker` | Animatable scalar/complex values |
| `TracedPath` | Trail following a mobject |
| `SVGMobject` | Load and display SVG files |
| `ImageMobject` | Display raster images |
| `Cross` | X-mark |
| `ScreenRectangle` / `FullScreenRectangle` | Screen-sized rectangles |
| `AnnotationDot` / `LabeledDot` | Labeled dots |
| `AnimatedBoundary` | Animated border |
| `Frame` | Camera frame mobject |

---

## Animations (73 classes)

### Creation & Destruction

| Animation | Description |
|-----------|-------------|
| `Create` / `Uncreate` | Draw/undraw stroke |
| `DrawBorderThenFill` | Outline then fill |
| `Write` / `Unwrite` | Handwriting effect |
| `ShowPassingFlash` | Flash along path |
| `ShowIncreasingSubsets` | Reveal submobjects progressively |
| `ShowSubmobjectsOneByOne` | Reveal one at a time |
| `SpiralIn` | Spiral into position |
| `SpinInFromNothing` | Spin + scale from zero |
| `GrowFromCenter` / `GrowFromEdge` / `GrowFromPoint` | Grow from specified origin |
| `GrowArrow` | Grow an arrow from start |
| `ShrinkToCenter` | Shrink to nothing |

### Transformation

| Animation | Description |
|-----------|-------------|
| `Transform` | Morph one mobject into another |
| `ReplacementTransform` | Transform + replace in scene |
| `TransformFromCopy` | Transform a copy |
| `ClockwiseTransform` / `CounterclockwiseTransform` | Directional morph |
| `MoveToTarget` | Animate to `.target` copy |
| `ApplyMethod` | Apply any method as animation |
| `ApplyFunction` | Apply function to points |
| `ApplyMatrix` | Apply matrix transformation |
| `ApplyComplexFunction` | Apply complex function to plane |
| `ApplyPointwiseFunction` | Apply function point-by-point |
| `CyclicReplace` / `Swap` | Swap positions |
| `TransformMatchingShapes` / `TransformMatchingTex` | Smart shape/tex matching |
| `FadeTransform` / `FadeTransformPieces` | Fade-based transform |
| `Restore` | Restore to saved state |

### Fading

| Animation | Description |
|-----------|-------------|
| `FadeIn` | Fade in (with optional shift/scale) |
| `FadeOut` | Fade out (with optional shift/scale) |
| `FadeToColor` | Crossfade to new color |

### Indication

| Animation | Description |
|-----------|-------------|
| `Indicate` | Brief scale+color pulse |
| `Flash` | Radial flash effect |
| `Circumscribe` | Draw circle/rectangle around object |
| `Wiggle` | Wiggle side-to-side |
| `FocusOn` | Zoom focus effect |
| `ShowCreationThenFadeOut` | Create then fade |
| `Broadcast` | Expanding ring broadcast |

### Movement & Rotation

| Animation | Description |
|-----------|-------------|
| `Rotate` / `Rotating` | Rotate by angle |
| `MoveAlongPath` | Move along a curve |
| `.animate` syntax | `obj.animate.shift(RIGHT).scale(2)` |

### Text Animations

`AddTextLetterByLetter`, `RemoveTextLetterByLetter`, `TypeWithCursor`, `UntypeWithCursor`, `AddTextWordByWord`

### Composition

| Animation | Description |
|-----------|-------------|
| `AnimationGroup` | Play animations simultaneously |
| `LaggedStart` | Staggered start times |
| `LaggedStartMap` | Map function with stagger |
| `Succession` | Play animations in sequence |
| `ChangeSpeed` | Modify playback speed |

### Special

`Wait`, `Homotopy`, `ComplexHomotopy`, `PhaseFlow`, `ApplyWave`, `ChangingDecimal`, `ChangeDecimalToValue`

---

## Rate Functions (40+)

### Standard
`linear`, `smooth`, `smoothstep`, `smootherstep`, `smoothererstep`

### Movement
`rush_into`, `rush_from`, `slow_into`, `double_smooth`, `lingering`

### Complex
`there_and_back`, `there_and_back_with_pause`, `running_start`, `not_quite_there`, `wiggle`, `exponential_decay`

### Easing (30 functions)

| Family | In | Out | InOut |
|--------|-----|------|-------|
| Sine | `ease_in_sine` | `ease_out_sine` | `ease_in_out_sine` |
| Quad | `ease_in_quad` | `ease_out_quad` | `ease_in_out_quad` |
| Cubic | `ease_in_cubic` | `ease_out_cubic` | `ease_in_out_cubic` |
| Quart | `ease_in_quart` | `ease_out_quart` | `ease_in_out_quart` |
| Quint | `ease_in_quint` | `ease_out_quint` | `ease_in_out_quint` |
| Expo | `ease_in_expo` | `ease_out_expo` | `ease_in_out_expo` |
| Circ | `ease_in_circ` | `ease_out_circ` | `ease_in_out_circ` |
| Back | `ease_in_back` | `ease_out_back` | `ease_in_out_back` |
| Elastic | `ease_in_elastic` | `ease_out_elastic` | `ease_in_out_elastic` |
| Bounce | `ease_in_bounce` | `ease_out_bounce` | `ease_in_out_bounce` |

---

## Colors (60+ constants)

### Primary Palette
`WHITE`, `GRAY_A` through `GRAY_E`, `BLACK`

### Color Families (each has A/B/C/D/E variants)
`BLUE`, `TEAL`, `GREEN`, `YELLOW`, `GOLD`, `RED`, `MAROON`, `PURPLE`

### Named Colors
`PINK`, `LIGHT_PINK`, `ORANGE`, `LIGHT_BROWN`, `DARK_BROWN`, `GRAY_BROWN`, `DARK_BLUE`

### Pure Colors
`PURE_RED`, `PURE_GREEN`, `PURE_BLUE`, `PURE_CYAN`, `PURE_MAGENTA`, `PURE_YELLOW`

### Additional Palettes
XKCD named colors, X11 colors, SVG colors, BS381, DVIPSNAMES, AS2700

---

## Camera System

| Class | Description |
|-------|-------------|
| `Camera` | Base 2D camera |
| `MovingCamera` | Pannable/zoomable 2D camera |
| `MultiCamera` | Multiple viewports |
| `MappingCamera` | Custom coordinate mapping |
| `ThreeDCamera` | 3D perspective camera with phi/theta/gamma |

---

## Rendering Pipeline (iOS)

```
Scene.construct()
  -> CairoRenderer (frame by frame, RGBA)
    -> Strip alpha (RGBA -> RGB)
      -> PyAV VideoFrame.from_ndarray()
        -> h264_videotoolbox (hardware H.264)
          -> .mp4 container
```

### Quality Presets

| Preset | Resolution | FPS | Bitrate |
|--------|-----------|-----|---------|
| Low (480p) | 854 x 480 | 15 | 2 Mbps |
| Medium (720p) | 1280 x 720 | 30 | 4 Mbps |
| High (1080p) | 1920 x 1080 | 60 | 8 Mbps |

### iOS Adaptations
- **Text rendering**: Cairo `text_path()` via pycairo (bypasses broken Pango)
- **LaTeX**: pdftex C library, fallback to Cairo ASCII
- **Video codec**: `h264_videotoolbox` hardware encoder, `mpeg4` fallback
- **Frame format**: RGBA -> RGB -> yuv420p
- **No subprocess**: All tools run as in-process libraries
- **Streaming output**: Real-time terminal feedback during rendering

---

## Utility Modules

| Module | Description |
|--------|-------------|
| `manim.utils.bezier` | Bezier curve construction and evaluation |
| `manim.utils.space_ops` | 3D spatial math (rotations, projections) |
| `manim.utils.color` | Color parsing, conversion, interpolation |
| `manim.utils.paths` | Path construction utilities |
| `manim.utils.rate_functions` | All easing/rate functions |
| `manim.utils.tex` | LaTeX template management |
| `manim.utils.file_ops` | File I/O helpers |
| `manim.utils.iterables` | List/array utility functions |
| `manim.utils.sounds` | Audio integration |
| `manim.utils.images` | Image loading and processing |
