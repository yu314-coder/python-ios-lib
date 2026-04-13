# manim

**Community Edition** | v0.20.1 | Hardware-accelerated video

> Create publication-quality math animations on iPad. Renders MP4 via VideoToolbox H.264 hardware encoder + FFmpeg.

---

## Core Classes

### Scene Types

| Class | Description |
|-------|-------------|
| `Scene` | Base class — `construct()` defines the animation timeline |
| `ThreeDScene` | 3D camera control with phi/theta/gamma |
| `MovingCameraScene` | Pan and zoom the 2D camera |

### Mobjects (Math Objects)

| Category | Classes |
|----------|---------|
| **Shapes** | `Circle`, `Square`, `Rectangle`, `Triangle`, `Polygon`, `RegularPolygon`, `Star`, `Annulus`, `Arc`, `ArcBetweenPoints`, `Ellipse`, `Sector`, `RoundedRectangle` |
| **Lines** | `Line`, `Arrow`, `DoubleArrow`, `DashedLine`, `TangentLine`, `Dot`, `SmallDot`, `CurvedArrow`, `Elbow` |
| **Text** | `Text`, `MathTex`, `Tex`, `MarkupText`, `Title`, `BulletedList`, `Code`, `Paragraph` |
| **Groups** | `VGroup`, `Group`, `VDict` |
| **Graphing** | `Axes`, `NumberPlane`, `ThreeDAxes`, `NumberLine`, `BarChart`, `CoordinateSystem` |
| **3D** | `Surface`, `Sphere`, `Cube`, `Cylinder`, `Cone`, `Torus`, `Arrow3D`, `Line3D`, `Dot3D` |
| **Special** | `ValueTracker`, `TracedPath`, `StreamLines`, `ArrowVectorField` |

### Animations

| Category | Animations |
|----------|-----------|
| **Create/Destroy** | `Create`, `Uncreate`, `DrawBorderThenFill`, `Write`, `Unwrite`, `ShowPassingFlash` |
| **Transform** | `Transform`, `ReplacementTransform`, `TransformFromCopy`, `MoveToTarget`, `ApplyMethod` |
| **Fade** | `FadeIn`, `FadeOut`, `FadeTransform` |
| **Indicate** | `Indicate`, `Flash`, `Circumscribe`, `Wiggle`, `FocusOn`, `ShowCreationThenFadeOut` |
| **Movement** | `Rotate`, `SpinInFromNothing`, `SpiralIn`, `GrowFromCenter`, `GrowFromEdge`, `GrowFromPoint`, `GrowArrow` |
| **Groups** | `LaggedStart`, `LaggedStartMap`, `AnimationGroup`, `Succession` |
| **Updaters** | `.animate` syntax, `always_redraw()`, `.add_updater()` |

### Rate Functions

`linear`, `smooth`, `rush_into`, `rush_from`, `slow_into`, `double_smooth`, `there_and_back`, `wiggle`, `ease_in_sine`, `ease_out_sine`, `ease_in_out_sine`

---

## Rendering Pipeline

```
Scene.construct()
  -> CairoRenderer (frame by frame)
    -> FFmpeg (PyAV) encoding
      -> h264_videotoolbox (hardware H.264)
        -> .mp4 output
```

### Quality Presets

| Preset | Resolution | FPS |
|--------|-----------|-----|
| Low (480p) | 854 x 480 | 15 |
| Medium (720p) | 1280 x 720 | 30 |
| High (1080p) | 1920 x 1080 | 60 |

---

## iOS Adaptations

- **Text rendering**: Cairo `text_path()` via pycairo (bypasses Pango)
- **LaTeX**: pdftex C library via ctypes, fallback to Cairo ASCII
- **Video**: PyAV + FFmpeg with VideoToolbox hardware encoding
- **No subprocess**: All tools run as libraries, not CLI processes
