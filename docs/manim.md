# Manim — math animation engine

**Version:** 0.19.0
**Type:** Pure Python + iOS patches (Cairo renderer only)
**SPM target:** `Manim` (depends on `CairoGraphics`, `ManimPango`)
**Total Python modules:** 166

Mathematical animation engine — declarative Scene class with `.play()`
animations, vectorized mobjects, LaTeX integration, programmatic camera
work. The bundled build is Cairo-only on iOS (no OpenGL); video output
goes through PyAV's VideoToolbox H.264 encoder.

---

## Modules

### Top-level

| Module | What it does |
|---|---|
| `manim.__init__` | Public API — re-exports from every subpackage |
| `manim.__main__` | `python -m manim` entry point (click CLI) |
| `manim.constants` | `UP`, `DOWN`, `LEFT`, `RIGHT`, `ORIGIN`, `PI`, `TAU`, frame dims, color presets |
| `manim.data_structures` | `Vector3D`, `Vector4D`, helpers used by typing |
| `manim.typing` | Type aliases (`ManimColor`, `Point3D`, `Vector3D`, …). **iOS-patched** — PIL Resampling fallback so import doesn't crash when PIL's C ext is partial |

### `manim._config` — Configuration system

| Submodule | Provides |
|---|---|
| `_config.__init__` | The global `config` object; **iOS-patched** to default `disable_caching=True` and `gc.set_threshold(200,5,5)` (16 GB jetsam limit) |
| `_config.utils` | Config file parser + arg merger |
| `_config.cli_colors` | Color theme for the CLI logger |
| `_config.logger_utils` | Rich-based logger setup |
| `_config.default.cfg` | Default config values |

### `manim.cli` — Command-line interface

| Submodule | Provides |
|---|---|
| `cli.render.commands` | `manim render scene.py SceneName` |
| `cli.render.global_options` | `-pql`, `-r`, `-o`, `--format`, `--disable_caching`, … |
| `cli.render.output_options` | `--media_dir`, `--video_dir`, `--save_pngs`, … |
| `cli.cfg.group` | `manim cfg show / write / export` |
| `cli.init.commands` | `manim init` — scaffold a new project |
| `cli.plugins.commands` | `manim plugins list / new` |
| `cli.checkhealth.checks` | `manim checkhealth` — verify deps. **iOS-aware** |
| `cli.default_group` | Click multi-command group |

### `manim.scene`

| Submodule | Provides |
|---|---|
| `scene.scene` | `Scene` base — `construct()`, `play()`, `add()`, `remove()`, `wait()` |
| `scene.scene_file_writer` | Frame → video pipeline. **iOS-patched:** uses `h264_videotoolbox` codec, falls back to `mpeg4` if `OFFLINAI_MANIM_SOFTWARE_ENCODER=1`; final-still `save_image` wrapped in try/except |
| `scene.section` | `Section` — scene partitioning for serialized rendering |
| `scene.moving_camera_scene` | `MovingCameraScene` — camera pans/zooms |
| `scene.three_d_scene` | `ThreeDScene` — perspective camera, `set_camera_orientation` |
| `scene.zoomed_scene` | `ZoomedScene` — inset zoom rect |
| `scene.vector_space_scene` | `VectorScene`, `LinearTransformationScene` (3Blue1Brown-style) |

### `manim.animation`

| Submodule | Provides |
|---|---|
| `animation.animation` | `Animation` base + `prepare_animation` |
| `animation.composition` | `AnimationGroup`, `Succession`, `LaggedStart`, `LaggedStartMap` |
| `animation.creation` | `Create`, `Write`, `Unwrite`, `DrawBorderThenFill`, `ShowIncreasingSubsets` |
| `animation.fading` | `FadeIn`, `FadeOut`, `FadeToColor` |
| `animation.growing` | `GrowFromCenter`, `GrowFromPoint`, `SpinInFromNothing` |
| `animation.indication` | `Indicate`, `Flash`, `Circumscribe`, `Wiggle`, `ApplyWave` |
| `animation.movement` | `Homotopy`, `ComplexHomotopy`, `PhaseFlow` |
| `animation.numbers` | `ChangingDecimal`, `ChangeDecimalToValue` |
| `animation.rotation` | `Rotate`, `Rotating` |
| `animation.transform` | `Transform`, `ReplacementTransform`, `MoveToTarget`, `ApplyMethod` |
| `animation.transform_matching_parts` | `TransformMatchingShapes`, `TransformMatchingTex` |
| `animation.changing` | `TracedPath` (live path drawn by a moving point) |
| `animation.specialized` | `Broadcast` |
| `animation.speedmodifier` | `ChangeSpeed` |
| `animation.updaters.update` | `UpdateFromFunc`, `UpdateFromAlphaFunc` |
| `animation.updaters.mobject_update_utils` | `always_redraw`, `always_shift`, `always_rotate` |

### `manim.camera`

| Submodule | Provides |
|---|---|
| `camera.camera` | `Camera` base — captures pixel_array per frame |
| `camera.moving_camera` | `MovingCamera` |
| `camera.three_d_camera` | `ThreeDCamera` |
| `camera.multi_camera` | `MultiCamera` (split-screen) |
| `camera.mapping_camera` | `MappingCamera` (apply a function to coordinates) |

### `manim.mobject` — Math objects

| Subpackage | Provides |
|---|---|
| `mobject.mobject` | `Mobject` base class |
| `mobject.frame` | `ScreenRectangle`, `FullScreenRectangle` |
| `mobject.matrix` | `Matrix`, `MathTable`, `MobjectMatrix` |
| `mobject.table` | `Table`, `MathTable`, `MobjectTable`, `IntegerTable`, `DecimalTable` |
| `mobject.graph` | `Graph`, `DiGraph` (networkx wrappers) |
| `mobject.logo` | `ManimBanner` (logo animation) |
| `mobject.vector_field` | `VectorField`, `ArrowVectorField`, `StreamLines` |
| `mobject.value_tracker` | `ValueTracker`, `ComplexValueTracker` |

### `manim.mobject.geometry`

| Submodule | Provides |
|---|---|
| `geometry.arc` | `Arc`, `Circle`, `Dot`, `AnnularSector`, `Sector`, `Annulus` |
| `geometry.line` | `Line`, `DashedLine`, `Arrow`, `DoubleArrow`, `Vector`, `Elbow`. **iOS-patched:** subdivide-curves disabled per-glyph (jetsam memory) |
| `geometry.polygram` | `Polygon`, `RegularPolygon`, `Triangle`, `Rectangle`, `Square`, `Star` |
| `geometry.boolean_ops` | `Union`, `Difference`, `Intersection`, `Exclusion` (pathops wrappers) |
| `geometry.labeled` | `LabeledLine`, `LabeledArrow` |
| `geometry.shape_matchers` | `SurroundingRectangle`, `BackgroundRectangle`, `Cross`, `Underline` |
| `geometry.tips` | `ArrowTriangleTip`, `ArrowCircleTip`, `ArrowStealthTip` |

### `manim.mobject.text`

| Submodule | Provides |
|---|---|
| `text.text_mobject` | `Text`, `MarkupText`, `Paragraph` (manimpango-driven). **iOS-aware:** falls back to PangoCairo pycairo path when needed |
| `text.tex_mobject` | `Tex`, `MathTex`, `BulletedList`, `Title`. **iOS-patched:** rasterized PNG fallback if LaTeX SVG path fails |
| `text.numbers` | `DecimalNumber`, `Integer`, `Variable`. **iOS-patched:** debug while-loop counter for "only first frame rendered" symptom |
| `text.code_mobject` | `Code` — pygments-syntax-highlighted source snippets |

### `manim.mobject.svg`

| Submodule | Provides |
|---|---|
| `svg.svg_mobject` | `SVGMobject` — parse SVG → VMobject. **iOS-patched:** `use_svg_cache=False` default (memory); rasterized-PNG embed accepted |
| `svg.brace` | `Brace`, `BraceLabel`, `ArcBrace` |

### `manim.mobject.types`

| Submodule | Provides |
|---|---|
| `types.vectorized_mobject` | `VMobject`, `VGroup`, `VDict`, `DashedVMobject`, `CurvesAsSubmobjects` |
| `types.point_cloud_mobject` | `PMobject`, `PGroup`, `Point` |
| `types.image_mobject` | `ImageMobject`, `ImageMobjectFromCamera` |

### `manim.mobject.three_d`

| Submodule | Provides |
|---|---|
| `three_d.three_dimensions` | `ThreeDVMobject`, `Surface`, `Sphere`, `Cube`, `Cylinder`, `Cone`, `Torus` |
| `three_d.polyhedra` | `Polyhedron`, `Tetrahedron`, `Octahedron`, `Icosahedron`, `Dodecahedron` |
| `three_d.three_d_utils` | Coordinate-system helpers |

### `manim.mobject.graphing`

| Submodule | Provides |
|---|---|
| `graphing.coordinate_systems` | `Axes`, `NumberPlane`, `PolarPlane`, `ComplexPlane`, `ThreeDAxes` |
| `graphing.functions` | `ParametricFunction`, `FunctionGraph`, `ImplicitFunction` |
| `graphing.number_line` | `NumberLine`, `UnitInterval` |
| `graphing.probability` | `SampleSpace`, `BarChart` |
| `graphing.scale` | `LinearBase`, `LogBase` |

### `manim.mobject.opengl` — OpenGL mobjects

Mirrors of the Cairo mobjects for the OpenGL renderer. **Imports
work on iOS but instantiating any of them raises NotImplementedError**
(via the moderngl stub — see [moderngl.md](moderngl.md)). Kept so
`from manim import *` doesn't break.

Includes: `opengl_mobject`, `opengl_geometry`, `opengl_vectorized_mobject`,
`opengl_surface`, `opengl_three_dimensions`, `opengl_image_mobject`,
`opengl_point_cloud_mobject`, `dot_cloud`, `opengl_compatibility`.

### `manim.renderer`

| Submodule | Provides |
|---|---|
| `renderer.cairo_renderer` | `CairoRenderer` — the default + only working renderer on iOS |
| `renderer.opengl_renderer` | OpenGL renderer (import-only stub; raises on use) |
| `renderer.opengl_renderer_window` | GLFW window (stub) |
| `renderer.shader`, `renderer.shader_wrapper`, `renderer.shaders/` | GL shader infra (unused on iOS) |
| `renderer.vectorized_mobject_rendering` | Cairo path tessellation helpers |

### `manim.utils`

| Subpackage | Provides |
|---|---|
| `utils.color.core` | `ManimColor` class — RGB/RGBA/hex/HSL parsing |
| `utils.color.manim_colors` | Named manim palette: `RED`, `BLUE`, `GREEN`, `YELLOW_E`, … |
| `utils.color.AS2700` / `BS381` / `DVIPSNAMES` / `SVGNAMES` / `X11` / `XKCD` | Named color sets from various standards |
| `utils.bezier` | `bezier`, `partial_bezier_points`, `subdivide_bezier`, control-point math |
| `utils.caching` | `handle_caching_play` (the cache layer — auto-disabled on iOS) |
| `utils.commands` | Subprocess helpers (LaTeX, FFmpeg invocation) |
| `utils.config_ops` | Config helpers |
| `utils.debug` | Debug utilities |
| `utils.deprecation` | `@deprecated` decorator |
| `utils.exceptions` | `EndSceneEarlyException`, `RerunSceneException`, … |
| `utils.family` / `utils.family_ops` | Mobject parent/child tree traversal |
| `utils.file_ops` | `add_extension_if_not_present`, `guarantee_existence`, … |
| `utils.hashing` | Scene-cache hashing (disabled on iOS) |
| `utils.images` | PIL-based image I/O |
| `utils.ipython_magic` | `%manim` Jupyter magic. **iOS-patched** — non-Jupyter friendly |
| `utils.iterables` | `make_even`, `adjacent_pairs`, `tuplify`, … |
| `utils.module_ops` | Dynamic scene-module loading |
| `utils.opengl` | OpenGL math helpers (matrices, transforms) |
| `utils.parameter_parsing` | flatten_iterable_parameters |
| `utils.paths` | `straight_path`, `path_along_arc`, `clockwise_path` |
| `utils.polylabel` / `utils.qhull` | Geometry helpers |
| `utils.rate_functions` | `linear`, `smooth`, `there_and_back`, `wiggle`, … |
| `utils.simple_functions` | `sigmoid`, `choose`, `clip_in_place`, `binary_search` |
| `utils.sounds` | Audio playback (limited on iOS — no portaudio bridge) |
| `utils.space_ops` | `rotate_vector`, `angle_between_vectors`, quaternion ops |
| `utils.tex` / `utils.tex_file_writing` / `utils.tex_templates` | LaTeX → SVG pipeline (uses pdftex via offlinai_latex) |
| `utils.unit` | `Pixels`, `Degrees`, `Munits`, `Percent` |
| `utils.testing/*` | Frame-comparison test infra |
| `utils.docbuild/*` | Sphinx extension utilities (not used at runtime) |

### `manim.plugins`

| Submodule | Provides |
|---|---|
| `plugins.plugins_flags` | Plugin loader (entry-point discovery) |

---

## Quick start

```python
from manim import *

class HelloWorld(Scene):
    def construct(self):
        title = Tex(r"$\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}$")
        circle = Circle().shift(DOWN)
        square = Square().shift(DOWN)

        self.play(Write(title))
        self.play(Create(circle))
        self.play(Transform(circle, square))
        self.play(FadeOut(title), FadeOut(circle))
```

Render with `manim render -pql script.py HelloWorld` — produces an MP4
in `media/videos/script/480p15/HelloWorld.mp4`.

---

## iOS notes

### Renderer

Only the **Cairo renderer works** on iOS. The OpenGL renderer's imports
succeed (so `from manim import *` works), but instantiating any GL
mobject raises `NotImplementedError` via the moderngl stub. Configure
via `manim.config.renderer = "cairo"` (default).

### Video encoder

`scene_file_writer.py` auto-selects `h264_videotoolbox` (Apple's HW
encoder via PyAV) on iOS. Falls back to software `mpeg4` if
`OFFLINAI_MANIM_SOFTWARE_ENCODER=1` is set — useful for long scenes
where VideoToolbox's frame pool grows into jetsam territory.

### Caching disabled

`disable_caching=True` is forced by default on iOS. The cache hashes
every mobject in `scene.mobjects` on every `play()` by JSON-serializing
the whole tree; LaTeX-heavy scenes cross the documented 170k
sub-mobject threshold quickly and consume gigabytes. Set
`config.disable_caching = False` to re-enable, but expect to be
killed by jetsam on long scenes.

### Memory tweaks

- `gc.set_threshold(200, 5, 5)` is set in `_config/__init__.py` —
  more aggressive collection because each 1920×1080 RGBA frame is
  8 MB and queues add up fast.
- `should_subdivide_sharp_curves=False` and `should_remove_null_curves=False`
  on each VMobject — keeps the point count ~40% lower for math glyphs.
- `use_svg_cache=False` default on `SVGMobject`.

### Write / Create on busytex MathTex (column reveal)

`MathTex` / `Tex` route through `offlinai_latex`, which produces a
PNG-in-`<image>` SVG when busytex (real xelatex) handles the expression.
manim turns that into an `ImageMobject` — which has no strokes for
`Write` to animate. Without intervention `Write(MathTex(...))` collapses
to a flat opacity ramp and the formula just appears.

iOS patch: `DrawBorderThenFill` (parent of `Write`/`Unwrite`) and
`ShowPartial` (parent of `Create`/`Uncreate`) carry the class attribute
`_offlinai_reveal_image_children = True`. The image-fallback post-loop
in `Animation.interpolate_mobject` reads this marker and, when set,
does a left-to-right column reveal of the `pixel_array` —
`pa[:, :int(width * alpha), 3] = orig_alpha` and
`pa[:, int(width * alpha):, 3] = 0`. The visual effect closely matches
the stroke-by-stroke `Write` you get on a VMobject without needing to
vectorise the raster output.

Other introducer/remover animations (`FadeIn`, `FadeOut`, `AddCovering`,
…) lack the marker and keep the flat fade — so non-Write semantics
are preserved.

### Dependencies (all bundled)

| Package | Status |
|---|---|
| numpy 2.3.5 | Working |
| scipy 1.15.2 | Partial (fortran stubs route through libfortran_io_stubs) |
| Pillow 12.2.0 | Working (PIL.Image patched) |
| pycairo + CairoGraphics | Working |
| manimpango 0.6.1 | Working (pycairo-compat fallback enabled) |
| svgelements 1.9.6 | Working |
| isosurfaces 0.1.2 | Working |
| mapbox_earcut, pathops (skia) | Working |
| moderngl 5.12.0+stub | Importable; raises on use |
| screeninfo 0.8.1 | Returns synthetic single-display entry |
| watchdog | Stub (no inotify on iOS) |
| click 8.3.2, rich 14.3.3, pygments 2.20.0, networkx 3.6.1, srt 3.5.3 | Working |

### Patched files (`.py.bak` siblings exist for reference)

```
manim/_config/__init__.py             — disable_caching, gc threshold
manim/typing.py                       — PIL Resampling fallback
manim/animation/animation.py          — iOS-specific defaults
manim/animation/creation.py           — Write/Create iOS tweaks
manim/animation/fading.py             — iOS tweaks
manim/constants.py                    — frame defaults
manim/mobject/geometry/line.py        — subdivide curves disabled
manim/mobject/svg/svg_mobject.py      — cache off, rasterized embed
manim/mobject/text/tex_mobject.py     — PNG-fallback path
manim/mobject/text/numbers.py         — debug counter
manim/scene/scene_file_writer.py      — h264_videotoolbox; save_image guard
manim/cli/checkhealth/checks.py       — iOS-aware health checks
manim/utils/ipython_magic.py          — non-Jupyter cleanups
manim/utils/color/core.py             — color parsing edge cases
```

Don't `git checkout` these files casually — see `~/.claude/projects/-Volumes-D-OfflinAi/memory/gotchas_ios_patches.md`.

---

## Limitations

- No 3D OpenGL rendering — `ThreeDScene` works for the camera math
  but the rendered output is Cairo's 2D projection.
- No interactive preview (`-p` flag opens a file in iOS Files; can't
  invoke macOS QuickTime).
- LaTeX rendering requires offlinai_latex's pdftex; complex packages
  may need adding to `tex_template.tex` manually.
- Long scenes (> 30 s @ 1080p) hit jetsam if not chunked into sections.
