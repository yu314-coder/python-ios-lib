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
| `text.tex_mobject` | `Tex`, `MathTex`, `BulletedList`, `Title`. **iOS:** vector glyphs as on a desktop (pdflatex in BusyTeX → `offlinai_latex.pdf_vector`); rasterized PNG only as a fallback |
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

### High-resolution rendering (4K, 8K and past it)

Earlier the bundled config refused anything above 1080p outright: the
animated-GIF assembly buffer held every full-resolution frame as a PIL
image, so memory scaled with `resolution × frame_count` and tripped the
jetsam watermark long before 8K. The render path now *streams* rather
than accumulates, which makes 4K and 8K memory-safe:

- **Bounded GIF frame buffer.** Captured frames are capped
  (`_MAX_COLLECT = 240`) and downsampled at capture time
  (`_GIF_MAX_W = 480`), so the buffer is a small constant regardless of
  render resolution or scene length. Full-resolution frames still stream
  straight to the mp4 via `SceneFileWriter` and are never accumulated.
  (The GIF is a lightweight preview; the mp4 is the full-quality output.)
- **No resolution limit; a RAM estimate that only warns.** Every quality up
  to 8K renders regardless of free memory. Peak need is still estimated by
  resolution (≈ 3 GB for 8K, ≈ 2 GB for 4K, less below), but a shortfall now
  prints a *warning* and proceeds — it no longer refuses. The estimate is a
  generous upper bound on a **transient** per-frame working set (frames stream
  to ffmpeg and are freed each frame), so refusing on it blocked renders that
  would have completed. This replaced first the old hard 4K cap, and then the
  refusing pre-flight. The real safety net is the memory watchdog: if free
  memory actually falls below 150 MB mid-render it force-kills the render
  **workload** — injecting `SystemExit` into the render/encoder threads and
  force-closing the PyAV containers to release the VideoToolbox IOSurface
  pool — so a doomed render fails cleanly instead of jetsam-killing the app.
- **App developers configure the render from Swift.** The memory a render may
  hold is a property of the app and the device, not of the animation, so it is
  decided by whoever embeds the package rather than by whoever writes the
  scene. `ManimLib.renderConfiguration` (Sources/Manim/ManimRenderConfiguration.swift):

  ```swift
  import Manim

  // At app startup, before the interpreter imports manim.
  var render = ManimLib.RenderConfiguration()
  render.frameQueueDepth = 8        // fixed depth; 1 or more, 0 is unbounded
  render.videoCodec = .hevc         // or leave nil to ask the hardware
  ManimLib.renderConfiguration = render
  ```

  | property | default | what it does |
  |---|---|---|
  | `frameQueueDepth: Int?` | `nil` | a fixed depth, ignoring the budget; `nil` derives it from the budget |
  | `frameQueueBudgetMB: Int` | 256 | memory the queue may hold |
  | `frameQueueMinimum: Int` | 2 | the fewest frames a budget may work out to |
  | `frameQueueMaximum: Int` | 32 | the most; raise it if you have measured otherwise |
  | `videoCodec: VideoCodec?` | `nil` | `.h264` / `.hevc` / `.mpeg4`, or ask the hardware |

  `frameQueueDepth(forWidth:height:)` and `frameQueueBytes(forWidth:height:)`
  answer what a configuration works out to at a given size, so an app can show
  the cost before a render rather than discover it during one.

  Assigning applies the configuration by setting the process environment, and
  it works at any point before a render starts — including after the
  interpreter is running, which is the normal shape since an app usually
  starts Python long before the user picks a quality. Python's `os.environ` is
  a snapshot taken when `os` was imported, so the Python side reads these
  through libc instead and re-reads them at the start of each render;
  `OFFLINAI_MANIM_SOFTWARE_ENCODER` reaches Python the same way, which it did
  not when it was read from `os.environ` once at import. A value assigned from
  Python wins over one set here. The same values are reachable from Python as
  `manim.utils.ios_encoder.settings`, which is the script author's door onto
  them, not the app developer's.

- **The render tunables are editable, from code or the environment.** They
  live on one object, `manim.utils.ios_encoder.settings`, so a developer
  changes them without editing the vendored manim:

  ```python
  from manim.utils.ios_encoder import settings
  settings.frame_queue_budget_mb = 1024        # more overlap, more memory
  settings.video_codec = "hevc_videotoolbox"   # skip the capability probe
  ```

  | field | environment | default | what it does |
  |---|---|---|---|
  | `frame_queue_budget_mb` | `OFFLINAI_MANIM_QUEUE_MB` | 256 | memory the encoder queue may hold |
  | `frame_queue_frames` | `OFFLINAI_MANIM_QUEUE_FRAMES` | — | an exact depth, ignoring the budget; `0` is unbounded |
  | `frame_queue_min` | `OFFLINAI_MANIM_QUEUE_MIN` | 2 | below this the renderer and encoder stop overlapping |
  | `frame_queue_max` | `OFFLINAI_MANIM_QUEUE_MAX` | 32 | past this the encoder is the bottleneck |
  | `video_codec` | `OFFLINAI_MANIM_CODEC` | — | force an encoder instead of probing |
  | `encoder_stall_seconds` | `OFFLINAI_MANIM_ENCODER_STALL_S` | — | how long the encoder may finish no frame before the render fails as stuck; `0` waits for as long as it takes |

  Each field is seeded from its variable at import, so the environment sets
  defaults and code assigned afterwards wins — later simply happens later.
  Nothing is read until a render starts, so a scene file can set them at
  module level. `OFFLINAI_MANIM_SOFTWARE_ENCODER=1` still works; it is read
  once here and sets `video_codec = "mpeg4"`.

  The queue is bounded by *bytes* rather than a frame count because thirty-two
  frames is ~256 MB at 1080p but 4.25 GB at 8K — the cap that existed to
  prevent a jetsam kill was causing one. With the default budget: 1080p queues
  32, 4K queues 8, 8K queues 2.

  The two clamps make the budget an approximation rather than a promise, and
  in opposite directions: a small budget at 8K still holds the floor, a large
  one at 1080p still stops at the ceiling. `frame_queue_depth()` returns the
  reason alongside the number and the `[manim] frame queue:` line prints it,
  so a setting that is being overruled can be seen to be overruled rather than
  looking inert. Both clamps are themselves fields, for a device that wants
  different ones.

- **Each animation's clip closes only after its encoder has finished.** A
  writer thread encodes each animation's frames from a bounded queue. At the
  animation's end the clip used to give that thread 60 s, then close the
  container and — on iOS, to free memory — drop the stream, container and
  queue. At 8K and 120 fps with 32 frames queued, an iPad's encoder is still
  working normally after 60 s; it then wrote into None and the render died
  with `AttributeError: 'NoneType' object has no attribute 'mux'` (reported by
  ManimStudio as "the video encoder stopped"). Worse, the thread looked its
  queue up through the writer, so it could take the next clip's frames.

  Now the clip waits for as long as the encoder keeps finishing frames,
  printing `[manim-debug] writer still encoding (N frames left), waiting…`
  each minute so a long wait is visible. Only if no frame comes out for the
  stall window does it give up, and then it raises — `RuntimeError: the video
  encoder made no progress for N s at WxH` — rather than closing the container
  under a thread that may still be writing. The window is five minutes, in
  proportion to the pixel count above 4K, up to twenty
  (`settings.encoder_stall_window()` says which and why); it is measured per
  frame, so it only has to cover one frame's encode. Each thread reads its own
  clip's queue, a clip cannot open while the previous one's thread runs, and
  the memory release still happens, after the thread has exited.
  `manim_writer_test.py` checks all of it.
- **An image costs what it covers, not what the frame covers.** A BusyTeX
  `MathTex` is a PNG, so it reaches the camera as an `ImageMobject` (see
  *Write / Create on busytex MathTex* below), and a 20×16 matrix of numbers is
  320 of them. `Camera.display_image_mobject` used to paste each one into a
  transparent image the size of the frame (built from a frame-sized float64
  array, 265 MB at 8K) and alpha-composite the whole frame, so each number
  cost about 45 ms at 7680×4320: 14.5 s a frame for the matrix on an M4 Mac,
  33–40 s on an iPad Air M3. It now composites only the rectangle the
  transformed image covers, clipped to the frame (skipped when it is wholly
  off it): about 1.5 ms a number, 0.53 s a frame on the same Mac, so the
  FadeIn's 180 frames at 120 fps take 1.6 min instead of 44. In the scene it
  came from (a TSNE explainer's data matrix, with everything else on screen)
  a frame went from 20.4 s to 0.32 s. Compositing is per pixel and
  the frame-sized overlay was transparent outside that rectangle, which
  `alpha_composite` leaves exactly as it was, so frames are pixel-identical;
  the perspective transform, its resampling and the early returns are
  unchanged. The CairoMetal GPU toggle only replaces `cairo`, which never
  draws these images, so it takes the same path. `manim_image_test.py`
  checks it.
- **Per-frame cost cut in the library, same frames.** Profiling a TSNE
  explainer (the scene behind the 8K reports) showed the time going to
  Python bookkeeping, not to drawing or encoding. Each change below gives
  byte-identical frames (every frame of the scene hashed, old vs new, at
  1080p and 8K; `manim_speed_test.py` checks each one):
  - `Camera.set_cairo_context_path` walked every curve as NumPy scalars
    (three tiny slices per curve, a NumPy comparison per anchor), about
    50 µs per VMobject before cairo drew anything. It now reads the points
    once as plain floats and makes the same cairo calls with the same
    numbers: a 1000-curve path 15.2 → 2.0 ms. Classes that override the
    path methods keep the old loop.
  - `Mobject.get_family` recursed with a dedupe at every level (a list
    and a set per family member, many times a frame); it now walks the
    family once and dedupes once, which gives the same list.
  - Each frame starts with `set_pixel_array(background)`, which copied the
    background into a new array and then into the frame: two full-frame
    copies and a 133 MB temporary at 8K. Now one copy into the frame.
  - Starting an animation copies mobjects. Every glyph of a `Text` carried
    its parsed svgelements path, which `deepcopy` rebuilt object by object
    (7.6 ms for a 25-letter Text); glyph copies now share it (it is only
    read), and immutable values are handed over without `copy.deepcopy`:
    0.8 ms.
  - Large images are resampled (PIL's `transform`, which releases the GIL)
    on worker threads while the next ones are placed, and composited in
    their original order, at most 4 MB in flight: 320 numbers at 8K
    0.49 → 0.12 s a frame. `OFFLINAI_MANIM_IMAGE_THREADS=0` draws them one
    by one.
  - `ThreeDCamera.project_points` worked the perspective factor out twice.

  With MathTex now vector glyphs as well (next section), the scene's first
  30 animations render 1.8× faster at 1080p30 (16.6 → 9.3 s) and 2.5× at
  8K30 (42.4 → 16.8 s) on an M4 Mac; the 20×16 number matrix's FadeIn at 8K
  went from 0.70 to 0.044 s a frame. Peak memory footprint is unchanged
  (1080p 396 → 391 MB, mean of 4 runs; 8K 869 → 867 MB, mean of 2). The
  encoder and the frame queue are untouched.
- **Second pass: one full-frame pass per frame instead of two, and less
  bookkeeping.** Same rule as above: every frame of the TSNE scene hashed,
  old vs new (771 frames, byte-identical); `manim_speed_test.py` checks each
  change (18 checks).
  - The renderer gave the writer a copy of every finished frame
    (`get_frame`), then copied the background over the frame to start the
    next one: two passes over 133 MB per frame at 8K. The finished frame
    itself now goes to the writer (`Camera.release_frame`) and the next
    frame starts in a new array holding the background. The cached cairo
    context moves to the new array with everything set on it (matrix, line
    join and cap, ...), so drawing is the same. A `get_frame` that was
    replaced (CodeBench's GPU cairo flushes there) or a cairo that is not
    pycairo keeps the copy. Memory is the same: the writer held copies
    before, it holds the frames now.
  - Rows of the starting picture that are one colour are filled rather than
    copied (a fill writes the memory once, a copy also reads it: 4.7 → 2.2 ms
    for a plain 8K frame). It needs the picture not to change after it was
    looked at, so the camera's one-colour background and the renderer's
    static frame are read-only arrays now; `set_background` and
    `background_color` still replace them.
  - The camera's list of what to draw asked each of the scene's (already
    flattened) mobjects for its family, every frame; it is one walk now.
    `remove_list_redundancies` runs in C (`dict.fromkeys`). `Mobject.update`
    goes through the family without a Python call per member. The iOS image
    fade in `Animation.interpolate_mobject` looked through every family on
    every frame for an `ImageMobject`; until one exists in the process it
    returns at once.
  - Paths are built in one pass, and an anchor exactly equal to the previous
    one skips the tolerance test (a 1000-curve path 13.6 → 2.0 ms).
    `interpolate_color` has `interpolate()` written out; `ThreeDCamera`
    scales x and y in one step.

  The whole TSNE video (186 s, 5,580 frames) at 8K30, written through
  ManimStudio's encoder wrapper (hardware HEVC) on an M4 Mac: 448 s with
  `3938e8d7`, 387 s now. Drawing went from 124 to 49 s and interpolation
  from 14.5 to 8.9 s; peak memory footprint 2.07 → 2.02 GB. What is left
  is the encoder: hardware HEVC takes about 55 ms per 8K frame on that
  Mac (about 18 frames a second) whatever it is fed — frames converted to
  YUV ahead of it on other threads were 6% faster, `prio_speed` changed
  nothing — so the render now runs within about 25% of what the encoder
  allows, and at 8K the encoder decides how long a render takes. 47% of
  this video's frames are `wait()` holds, each one converted and encoded
  again.

  In the app's own build (CodeBench, Designed for iPad, M4; iOS PyAV,
  FFmpeg and VideoToolbox), the scene's first seven animations at 8K120
  (1,020 frames, written through ManimStudio's encoder wrapper) took
  105.4 s with `3938e8d7` and 68.5 s with this and the converted frames
  below (CPU cairo); 70.6 s with CairoMetal, whose frames now have
  something on them.

- **Frames reach the encoder already converted, on several cores.** PyAV
  turns each RGBA frame into the encoder's YUV inside `encode()`, with the
  encoder's thread count, and VideoToolbox's is one: 37 ms an 8K frame on
  one core, on the writer thread, on top of the hardware encoder's own
  ~55 ms. The writer's stream now does the same `reformat` first with up
  to four threads (`settings.convert_threads`, `OFFLINAI_MANIM_CONVERT_THREADS`;
  `1` leaves it to PyAV), so `encode()` has nothing to convert. HEVC, its
  options, the queue and the frames the encoder gets are unchanged: the
  threaded conversion gave the same bytes as the single-core one for every
  even size checked (480 conversions, 2×2 to 14336×8064, yuv420p and nv12,
  2–8 threads, with the app's FFmpeg). FFmpeg 8.0.1's swscale (9.1) differed
  at 854×480, so it is only used from swscale 9.7, for even sizes and those
  two formats. ManimStudio's own encode wrapper goes through the same
  stream. In the app's build on an M4, an 8K frame's encode went from about
  105 to 76 ms. What remains on the writer is PyAV's `from_ndarray`, which
  copies the array twice (`tobytes()` first) and holds the GIL meanwhile
  (33 ms at 8K in the app's build); that needs a PyAV rebuild.
- **A `wait()` is written as its first and last frame.** A frozen frame
  held for *n* frames used to be converted and encoded *n* times; at 8K the
  hardware encoder takes ~55 ms a frame whatever it gets, and holds were
  47% of the TSNE video's frames. The writer now encodes the first frame,
  moves the time stamps on (`_WriterStream.hold`) and encodes the last, so
  the first stays on screen until the second: the clip is as long as
  before and shows the same picture at every moment (the movie is variable
  frame rate across a hold). Only with VideoToolbox, which does not
  reorder frames — libx264's B-frames made the joined movie short across a
  hold, so software encoders and GIF output still write every frame.
  `settings.hold_frames = "every"` (or `OFFLINAI_MANIM_HOLD_FRAMES=every`)
  writes every frame everywhere. If ManimStudio's encoder wrapper moves an
  animation to a new clip in the middle of a hold (iOS took the hardware
  encoder away), the rest of the hold is written frame by frame. Its join
  copies packets when the clips share an encoding (the holds keep their
  times); when a software clip made them differ, it decodes every clip and
  numbers the frames one by one, which would shrink a hold to two frames
  (a 3.2 s test video came back 1.6 s). Before combining, the writer sees
  that case (`_ms_segments` and clips in more than one encoding) and writes
  its hold clips out frame by frame first (`_fill_holds_before_reencoding`),
  so the join keeps their length — no change in ManimStudio. In the app's
  build at 8K120 (TSNE scene, first seven animations, CPU cairo,
  ManimStudio's encoder wrapper) the movie is 10.600 s either way, 666
  frames written instead of 1,272, the same picture at every moment; run
  alternately against the previous commit on a loaded Mac: 111.6 and
  133.3 s → 86.5 and 84.6 s. 14336×8064 (14K) HEVC
  renders as before (checked: same duration and pictures, 4.49 GB peak
  footprint vs 4.50 GB before).
- **VideoToolbox holds at most two frames, and frames are drawn again in
  once the writer is done with them.** VideoToolbox takes frames as fast
  as they come and keeps a copy of each until it is encoded; FFmpeg's
  wrapper hands back at most one packet per frame sent and had no way to
  wait for it, so a writer quicker than the hardware left it holding a
  queue of whole frames. python-ios-lib's libavcodec (`ffmpeg_ios/`: the
  app's FFmpeg snapshot `git-2026-04-07-0510aff`, rebuilt with
  `videotoolbox_max_pending.patch`; same 445 exported symbols) adds the
  encoder option `max_pending_frames`, counted by VideoToolbox's own output
  callback; the writer sets it to `settings.encoder_pending_frames` (2,
  `OFFLINAI_MANIM_ENCODER_PENDING`; 0 leaves it to VideoToolbox). Sending
  8K frames as fast as possible in the app: no limit 52.6–53.6 ms a frame
  and +424–620 MB at the peak; limit 2, 53.7 ms and +190 MB.

  With the encoder capped, finished frames go back to the camera
  (`camera._FramePool`, `_return_frame`): in an iOS process a newly
  allocated 8K array costs ~9 ms more than one already in use (a 133 MB
  copy: 15 vs 6 ms in the app's build). Only frames the camera handed out,
  only if nothing else holds them (a hook that kept the array keeps it as
  it was), one waiting at most, emptied when the scene's movie is finished,
  only while the stream is capped (stock FFmpeg, and ManimStudio's own
  split clips, are not), and only for frames within the frame queue's
  budget (`frame_queue_budget_mb`, 256 MB: up to 8K; at 14K the frame kept
  for the camera cost ~330 MB at the peak). `OFFLINAI_MANIM_FRAME_POOL=0`
  turns the pool off, `=1` on whatever the encoder. The encoder gets
  byte-identical frames either way (791 hashed). Without the cap the pool
  had cost ~400 MB at 8K (10 frames in the encoder instead of 6).

  In the app's build (fresh launch each, TSNE scene, ManimStudio's encoder
  wrapper), peak footprint, previous default → now: 8K120 1497–1902 MB
  (four runs) → 1543 / 1545 MB (1585 / 1585 with a limit of 3); 14K30
  3983–4313 MB (five runs) → 4147–4153 MB (three); the same
  movie length; times within this loaded Mac's noise (8K at the hardware
  encoder's floor either way).
- **GPU cairo (CairoMetal) frames were blank.** CairoMetal records fills and
  strokes and renders them into the frame's memory only when flushed
  (`cairo._flush_all`). manim never flushed, so with the GPU switch on every
  frame came out with nothing drawn on it, unless the app flushed in its own
  `get_frame` hook (CodeBench's editor does; ManimStudio and a script run
  from the terminal did not): a 1,272-frame 8K render was all black. The
  camera now flushes when a frame is done, and before images, point clouds
  and background-coloured shapes, which it writes into the frame with NumPy
  and which therefore landed under the shapes drawn before them. pycairo
  has no `_flush_all` and is never asked.
- **Return freed pages to the OS.** `PYTHONMALLOC=malloc` plus
  `malloc_zone_pressure_relief(NULL, 0)` between animations, so released
  memory actually leaves `phys_footprint` (what jetsam measures) instead
  of sitting in CPython's allocator pool.
- **Quality presets extended.** Selectable quality now runs
  480p / 720p / 1080p / 1440p / **4K** / **8K** / **12K** / **14K**.
  Indices 0–4 are manim's built-in presets; 5–7 are custom resolutions with an
  explicit frame rate, defined once in `_CUSTOM_RES` and read by both the
  initial config and the pre-render re-apply, so the two cannot drift:

  | index | preset | pixels | shorter side | encoder |
  |---|---|---|---|---|
  | 5 | 8K UHD | 7680×4320 | 4320 | hardware HEVC |
  | 6 | 12K | 11520×6480 | 6480 | hardware HEVC |
  | 7 | 14K | 14336×8064 | 8064 | hardware HEVC |

  16K UHD is deliberately absent: its shorter side is 8640, past the encoder's
  8192, so it would fall back to software mpeg4 and crawl. Higher resolutions
  are still reachable by setting `config.pixel_width` directly — the presets
  are a convenience, not a limit.

  **The queue is the memory cost at these sizes.** A frame is 133 MB of RGBA at
  8K, 299 MB at 12K and 462 MB at 14K, and the queue's floor of two frames
  outranks the 256 MB budget well before 12K:

  | | per frame | queued | held |
  |---|---|---|---|
  | 8K | 133 MB | 2 | 265 MB |
  | 12K | 299 MB | 2 | 597 MB |
  | 14K | 462 MB | 2 | **925 MB** |

  That is on top of the render's own working set. On a memory-tight device,
  `settings.frame_queue_min = 1` halves it, at the cost of the renderer and
  the encoder no longer overlapping.
- **The codec is chosen by asking VideoToolbox, not by assuming H.264.**
  ffmpeg's `h264_videotoolbox` binds Apple's *hardware* H.264 encoder and
  nothing else — there is no slow path. Above the size that encoder supports,
  `avcodec_open2("h264_videotoolbox")` fails outright and the render dropped to
  software `mpeg4`. Anything H.264 cannot take goes to `hevc_videotoolbox`
  instead, which every Apple silicon media engine encodes far higher.

  Measured on an M4 Mac mini with VideoToolbox directly, then confirmed by real
  encodes through PyAV:

  | resolution | H.264 | HEVC | 3 frames |
  |---|---|---|---|
  | 4K UHD 3840×2160 | hardware | hardware | 0.69 s / **0.50 s** |
  | 8K UHD 7680×4320 | **cannot open** | hardware | — / **0.48 s** |
  | 12K 11520×6480 | cannot open | hardware | — / 0.94 s |
  | 14K 14336×8064 | cannot open | hardware | — / 1.46 s |
  | 16K UHD 15360×8640 | cannot open | **cannot open** | falls back to mpeg4 |

  HEVC is *faster than H.264 even at 4K* on this chip, so the switch costs
  nothing where both work.

- **Frame rate (FPS) is honored.** The Settings FPS selector applies to
  every quality. manim's quality preset *resets* `frame_rate` to its built-in
  default (15 / 30 / 60), so the chosen fps is re-applied **after** the preset
  (in both the initial config and the per-render re-apply); before this fix
  the FPS selector did nothing except at 8K. **Lower fps is the single biggest
  speed lever** — 4K@60 → 4K@30 roughly halves the render, since nearly all the
  per-frame cost scales with frame count. The `manim quality idx=… fps=…` log
  line shows the fps actually applied.

### Where the ceiling actually is

The limit is **not** total pixels and **not** the longer side. Bisected one
size per process, so a resource-exhaustion artefact could not masquerade as
a limit:

> **Hardware HEVC requires the _shorter_ side to be ≤ 8192.**
> The longer side reaches at least 20480.

| | shorter side | result |
|---|---|---|
| 16384 × 8192 | 8192 | hardware |
| 16384 × **8193** | 8193 | fails — one pixel over |
| 20480 × 8192 | 8192 | hardware |
| 8193 × 8193 | 8193 | fails |

So 168 megapixels encodes (20480×8192) and 67 does not (8193×8193), decided
entirely by the shorter side. For 16:9 that puts the ceiling at about **14336×8064**;
**16K UHD (15360×8640) misses it by 448 pixels of height**, not by pixel
count — it is 132.7 Mpx against 14K's 115.6 Mpx, and a 132.1 Mpx frame at
16386×8064 encodes fine because its height stays under 8192. Reported from an
iPad Pro M5, and consistent with the rule measured on M4.

A device whose encoder reaches further keeps the benefit automatically: the
ceiling is probed at run time, never written down. Nothing here is a table
the code consults.

### The two tagging traps

Both produced a *finished* render that the device which made it could not
open. HEVC in an mp4 must be tagged `hvc1` — ffmpeg's default `hev1` is legal
and AVFoundation reports it as neither playable nor decodable — and the tag
has to be re-applied when `combine_files` copies the partials, since
`add_stream_from_template` does not carry it. The copy stream also reports
its codec as `libx265` rather than `hevc`, so a `== "hevc"` check never
fires. Covered by `manim_encoder_test.py`.

Rendering stays on cairo's CPU rasterizer by default; only the *encode* uses
the GPU (`h264_videotoolbox`, or `hevc_videotoolbox` above the H.264 ceiling). An **experimental Metal cairo backend
(CairoMetal)** can be toggled on (**Settings → Manim → GPU rendering**) — it
renders correctly on the GPU but does **not** speed manim up: profiling a 4K
render shows the cairo fill is only ~5% of the time, while ~67% is manim's
per-frame Python animation engine (mobject interpolation), ~12% CPU
path-building, and ~11% the already-hardware video encode. So GPU
rasterization can't move the needle — use **lower fps** for real speedups.
(manim's own OpenGL renderer remains unusable on iOS — `moderngl` is a stub.)
See `cairo(metal)/` and `docs/cairographics.md`.

### Unicode math glyphs in `Text()` (fonts)

`Text()` renders through Pango, which needs a font that actually contains the
codepoint. KaTeX's fonts are keyed to **LaTeX command slots, not Unicode math
codepoints**, so a user typing math characters directly used to get silent
drops — the glyph simply wasn't drawn:

| Codepoint | Example | Present in the KaTeX set? |
|---|---|---|
| U+211D and the letterlike block | `ℝ ℂ ℕ ℤ ℚ` | no |
| U+2080–2089 / U+2070–2079 | `₁ ₂ ₖ ᵖ ⁱ` | no |
| U+1D400–1D7FF math alphanumerics | `𝑝 𝐀 𝔸` | no |

The visible symptom was partial text: in `{Δ₁, Δ₂}` the **Δ rendered but the
subscript digits vanished** (Δ exists in `KaTeX_Main`; `₁` does not), and in
`{xᵢ ∈ ℝᵖ}` the `∈` rendered while `ℝ` and `ᵖ` disappeared. LaTeX forms such as
`p_i` were never affected, because LaTeX *positions an ASCII digit* rather than
using U+2081.

Two complementary OFL faces in `Frameworks/katex/fonts/` close the gap — neither
is sufficient alone:

- **`NotoSansMath-Regular.ttf`** — math alphanumerics, operators, letterlike
- **`NotoSans-Regular.ttf`** — sub/superscript digits, letterlike

**Host apps must append them to the fontconfig `<prefer>` list, and append them
LAST**, after any CJK fallbacks:

```xml
<alias><family>sans-serif</family><prefer>
  <family>KaTeX_Main</family>
  <family>Noto Sans SC</family><family>Noto Sans JP</family><family>Noto Sans KR</family>
  <family>Noto Sans Math</family><family>Noto Sans</family>   <!-- last -->
</prefer></alias>
```

Order matters: fontconfig selects whichever family *has* the requested glyph and
uses list order only to break ties. Trailing position therefore still resolves
the missing codepoints while leaving the default face for ordinary Latin text
unchanged. Placing them earlier flips the default and silently restyles every
existing render.

Worth knowing when debugging: **`KaTeX_Main` is not the effective default** even
though it is listed first — its charset is too narrow for fontconfig to score it
on a generic `sans-serif` request, so a broader face (Noto Sans SC in the
CodeBench bundle) wins. Verify any change with
`FONTCONFIG_FILE=… fc-match "sans-serif:charset=211d"`.

### Multi-core / parallel CPU rendering

The per-frame cost that scales with resolution is cairo's software pixel
fill, and animation frames are independent — so rendering frames across
multiple CPU cores would cut 4K/8K wall-clock roughly linearly. **It is not
enabled, because iOS blocks every cheap way to get there:**

- **`multiprocessing` / `fork` / `subprocess` — unavailable on iOS.** The
  sandbox forbids spawning processes; per PEP 730, invoking `fork`/`spawn`
  freezes the calling process (`[Errno 45] ios does not support processes`).
- **Threads don't parallelize CPU work.** The bundled CPython 3.14 is a
  standard GIL build (`cpython-314`, not the free-threaded `cpython-314t`),
  so a thread pool gives no speedup for the cairo fill.
- **Sub-interpreters** (3.14 ships `concurrent.interpreters`) would side-step
  the GIL in-process, but NumPy is not sub-interpreter-safe — a worker
  interpreter crashes on `import`, and manim is built entirely on NumPy.

The only real path is a **free-threaded Python rebuild** (`3.14t`,
`Py_GIL_DISABLED`): threads *are* allowed on iOS (only processes aren't), and
cairo is thread-safe per surface, so a thread pool could render frames
concurrently — each worker with its own cairo context. Output stays
byte-identical; speedup is bounded by core count and, at 8K, by memory
(~132 MB per frame → roughly 2–3× there, more at lower resolutions).

Note: the **video encode already overlaps rendering** — manim's
`SceneFileWriter` runs the H.264 encoder on a background thread fed by a
bounded frame queue (`listen_and_write`), so encode latency is hidden behind
the next frame's render today.

### MathTex and Tex are vector glyphs, as on a desktop

Desktop manim gets each formula from `dvisvgm`: a path per glyph and a
`<g id='uniqueNNN'>` per MathTex part. On iOS formulas used to be one PNG
each (BusyTeX → PDF → picture), so they animated differently from real
manim. Rendered side by side with manim 0.20 on a Mac, 12 common equation
animations showed it: `Write` and `Create` were a left-to-right wipe instead
of drawn strokes, `Indicate` and `set_color_by_tex` didn't recolour, and 6 of
the 12 failed — `Transform` / `ReplacementTransform` between two formulas
("Mobject pixel array shapes incompatible for interpolation"),
`MathTex("a^2", "+", "b^2", ...)`, `TransformMatchingTex`, and `Tex` with
inline math (the last three didn't compile).

`offlinai_latex` now compiles manim's own .tex with pdflatex in BusyTeX and
turns the PDF's glyph outlines into the SVG dvisvgm would have written (see
[offlinai-latex.md](offlinai-latex.md), backend 0). All 12 animations match
the desktop frame by frame (0.09% of pixels differ, by at most 31/255, on
glyph edges); a whole TSNE explainer video (2,879 frames) matches too, with
1,152 of its first 1,263 frames byte-identical. In the CodeBench app with the
real BusyTeX, `manim_tex_vector_test.py` passes 11/11 and the same 12
animations match the desktop. manim's iOS cache check in `tex_file_writing.py`
accepts these SVGs (their `offlinai_latex vector` marker).

Templates that need XeLaTeX (ctex, fontspec…) and CJK keep the picture path
below.

### Write / Create on busytex MathTex (column reveal)

*Only for formulas that still come back as a picture (XeLaTeX templates,
CJK, or the vector path turned off).* The picture becomes an
`ImageMobject` straight from its decoded pixels; it used to go through a
temporary PNG that was never deleted, one left in the temp folder per
formula (thousands over a few renders).

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
| Pillow 11.0.0 | Working (PIL.Image patched) |
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
manim/animation/animation.py          — iOS-specific defaults; image fade
                                       skipped until an ImageMobject exists
manim/animation/creation.py           — Write/Create iOS tweaks
manim/animation/fading.py             — iOS tweaks
manim/camera/camera.py                — images composited over their own box
                                       only, not the whole frame; paths built
                                       from plain floats; one-copy frame reset;
                                       images resampled on worker threads;
                                       frames handed to the writer
                                       (release_frame); one-colour rows filled
manim/renderer/cairo_renderer.py      — hands the frame over instead of
                                       copying it; read-only static frame
manim/utils/family.py                 — the scene's family list in one walk
manim/utils/iterables.py              — remove_list_redundancies in C
manim/camera/three_d_camera.py        — perspective factor worked out once,
                                       x and y scaled in one step
manim/mobject/types/image_mobject.py  — notes when an ImageMobject exists
manim/mobject/types/vectorized_mobject.py — interpolate_color written out
manim/mobject/mobject.py              — get_family in one walk; faster
                                       __deepcopy__ (_shared_on_copy); update
                                       without recursion
manim/constants.py                    — frame defaults
manim/mobject/geometry/line.py        — subdivide curves disabled
manim/mobject/svg/svg_mobject.py      — cache off, rasterized embed; glyph
                                       copies share the parsed path
manim/mobject/text/tex_mobject.py     — PNG-fallback path
manim/utils/tex_file_writing.py       — iOS: offlinai_latex; cache accepts its
                                       vector SVGs
manim/mobject/text/numbers.py         — debug counter
manim/scene/scene_file_writer.py      — VideoToolbox codec choice by resolution
                                       (h264/hevc) + hvc1 tagging; save_image guard;
                                       frames converted to YUV on several cores;
                                       holds written once; VideoToolbox capped at
                                       encoder_pending_frames; finished frames
                                       given back to the camera
manim/utils/ios_encoder.py           — NEW: VideoToolbox capability probe +
                                       RenderSettings (queue depth, codec,
                                       convert_threads, hold_frames,
                                       encoder_pending_frames)

Native, rebuilt from recipes in the repo:
Frameworks/ffmpeg/libavcodec.62.29.101.dylib
                                     — VideoToolbox max_pending_frames option
                                       (ffmpeg_ios/build_libavcodec_ios.sh)
av/video/frame.cpython-314-iphoneos.so
                                     — from_ndarray: one copy, GIL released
                                       (pyav_ios/build_frame_ios.sh)

Swift, for apps embedding the package:
Sources/Manim/ManimRenderConfiguration.swift
                                     — NEW: ManimLib.renderConfiguration
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
- 4K / 8K now render memory-safe (GIF buffer bounded, frames stream to
  the mp4 instead of accumulating — see *High-resolution rendering*), and
  the *encode* is hardware at every resolution now that the codec is chosen
  by capability rather than fixed to H.264. Rendering itself stays CPU-bound
  and slow: cairo rasterizes every frame on the CPU, so 8K is ~16× the
  per-frame cost of 1080p whatever the encoder does. Scenes with > ~5000
  simultaneous VMobjects can still approach the jetsam ceiling regardless of
  resolution — that limit is structural (see issue #1).
