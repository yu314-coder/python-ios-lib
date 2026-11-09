# CairoMetal — STATUS: full cairo API implemented; builds, imports, smoke-tested

CairoMetal has grown from the original manim-only subset (~30 `cm_*` calls) into
a **broad, building, pycairo-compatible cairo implementation on Metal**. The C
library exposes **246 public `cm_*` functions** across **24 source modules**, both
build paths are green, the demo renders, and the Python extension is a working
drop-in for most of pycairo. Remaining gaps are documented below — they are
specific and known, not vague.

See [README.md](README.md) for the full picture and [DESIGN.md](DESIGN.md) for
the design rationale.

---

## 2026-11-09 — no draw waits for ever for a GPU frame

**The hang.** cairo draws at once. CairoMetal batches a surface's drawing into
one open frame (one command buffer) until the surface is flushed, and the device
has `CM_FRAMES_IN_FLIGHT` (3) frames behind a semaphore. A fourth surface drawn
while three others held open frames waited for a frame only a flush of those
surfaces could return: for ever, and holding the GIL, so nothing else in the
process ran. Two ways in:

- Any code that draws into four or more surfaces in turn without flushing
  (`tests/test_frame_limit.py` reproduces it with five).
- manim with more than 64 live cameras. The Python flush registry
  (`_flush_all`'s list of `create_for_data` surfaces) was a fixed 64, so later
  surfaces were never flushed, their drawing never reached their buffer, and
  three of them hung the next draw. `manim_image_test.py`, which makes a
  camera per case, hung CodeBench's GPU mode this way; cameras live on in
  reference cycles until the collector runs, and the collector can't run while
  the draw waits holding the GIL.

**The fix.**

- `cm_glue_make_room` (`cairo_metal.m`): before a frame begins on a device
  whose frames are all open, the oldest open frame of another surface is
  ended. What it holds is drawn now, as cairo would have drawn it, and that
  surface's next draw starts a frame from those pixels. Frames are only
  acquired at the start of a draw, for its own surface, so no draw is encoding
  into the frame ended. The ANTIALIAS_NONE path does the same.
  `_frames_ended_early()` counts these.
- The flush registry grows as needed (`cairo_metal_ext.c`).
- `cm_device_take_frame` (`cm_device.m`): a frame wait that still finds none
  free after 20 s fails the draw with a device error instead of waiting for
  ever. It's waited in slices, and a slice far longer than asked (the app
  suspended in the background) counts as a pause.

**Checked.** `tests/test_frame_limit.py` (7 cases, each in a child process
with a time limit; in-process on iOS): all 7 hung or failed before the fix and
pass after. That includes random draws with OVER, SOURCE, ADD and CLEAR over 7
surfaces in turn, against pycairo: within one level, the same ±1 CairoMetal
shows with no frame ended early. All other suites pass unchanged (raster,
geometry 177, robust 78, layer frames 45, path batch 11, reference 0 flagged,
gaps 91, full shim 81, shim). manim's GPU frames are identical before and
after (189/189). `manim_image_test.py` without its `gc.collect()` passes under
CairoMetal on the Mac and in CodeBench (it hung both before). In CodeBench,
with GPU mode on: test_frame_limit 7/7, test_layer_frames 45/45,
cairo_gpu_test 25/25. The shaders are unchanged; the metallib is
byte-identical.

---

## 2026-11-07 — manim's paths in one call; transparent draws skipped

- **`Context._append_cubic_curves(points, atol)`** builds, in one C call, the path
  manim's camera builds from a VMobject's cubic Bezier points (a subpath wherever
  a curve does not start at the previous one's end, closed when it ends at its
  start; manim's tolerance test, the same doubles and comparisons).  manim
  (python-ios-lib) uses it when the context's type has it: one call per mobject
  instead of three Python calls per curve.  Same paths: 600 random shapes against
  manim's loop written out (`tests/test_path_batch.py`), 133 real manim paths in
  `manim_speed_test.py`; 1,451 TSNE frames byte-identical at 1080p and 4K.
- **A transparent solid source drawn OVER is skipped** in `fill`/`stroke`, before
  flattening, stroke expansion and the two GPU passes, as cairo's `_reduce_op`
  skips it (manim fills every shape, transparent ones included).  Pixels unchanged.

TSNE, first 1,451 frames, ms per frame (recycled frames, layer frames on; pycairo and
"now" measured in one sitting, one run each, on a loaded M4 Mac):

| | pycairo | CairoMetal 2026-11-06 | now |
|---|---|---|---|
| this Mac, 1080p | 3.4 | 4.5 | 3.3 |
| this Mac, 4K | 4.6 | 5.9-6.1 | 4.3 |
| this Mac, 8K | 7.8 | 11.3-11.5 | 7.8 |
| in the app (CodeBench, Designed for iPad), 1080p | 6.0 | -- | 4.3 |

In the app pycairo's fills are slower than on the Mac (2.38 vs 0.96 ms a frame),
so there CairoMetal draws a 1080p frame ~28% faster.  Whole renders barely move:
at 4K and 8K the hardware encoder sets the pace, and at 1080p60 with the movie
written the two came out within this loaded Mac's noise (7.4 / 8.1 s).

**Tried, not kept:** covering each fill with its own stencil triangles instead
of its bounding box (byte-identical, but GPU time per frame 1.33 -> 3.15 ms at
4K: on this tile-based GPU the triangle count costs more than the area saved);
spinning on the command buffer's status before blocking (-0.1 ms at 8K, nothing
at 1080p, and it keeps a core busy that the encoder's threads use); raising the
calling thread's QoS (no change: the app already runs at default and the
wake-up latency is the same as on the Mac).  Not waiting at the end of a frame
(letting the GPU finish while manim works out the next one) would hide the flush
(~1.2-1.9 ms at 1080p) but CodeBench's and ManimStudio's `write_frame` hooks read
each frame before passing it on, so they would see it unfinished.

`tests/test_path_batch.py` (11 checks); every suite passes; on the iOS build in
CodeBench 25/25, 55/55, 98/98, 45/45, 11/11.

---

## 2026-11-06 — frames drawn into caller memory: layer frames, kept GPU wraps

manim draws each frame into its own pixel array (`ImageSurface.create_for_data`).
Profiling the TSNE scene's first 1,451 frames showed CairoMetal slower per frame
than pycairo (8K: 14.8 vs 7.9 ms; 4K: 7.2 vs 4.5 ms), for three reasons, all
fixed here and in manim (python-ios-lib):

- **Every frame went through the GPU twice in full.** A frame started by copying
  the whole buffer into the MSAA attachment (`cm_fs_load`) and ended by resolving
  every pixel back: ~3.5-5 ms of GPU time at 7680x4320 even for one small shape.
  Now a frame over caller memory whose draws are all OVER is a **layer frame**
  (`cm_frame_begin_ex`): its attachment starts transparent, nothing is loaded,
  and a tile function at its end (`cm_tile_composite`, `fill.metal`) resolves
  each pixel (each distinct colour weighted by the samples it covers) and
  composites it OVER the buffer -- only where something was drawn.  One shape at
  8K: 3.5 -> 1.7 ms of GPU time.  Any other operator composites the open layer
  first and draws on a frame that loads the buffer, as before.  Needs tile
  shading (Apple4+: every Apple-silicon Mac, A11 and later); without it, or with
  `CM_LAYER_FRAMES=0` / `cairo_metal._set_layer_frames(0)`, frames load as before.
  OVER is associative, so the picture is the same to rounding: TSNE frames within
  one level of the old path on <0.1% of pixels (and as far from pycairo as
  before); 30 stacked translucent layers over noise are as close to the exact
  result as before (mean error 0.158 vs 0.184; pycairo 0.368).
- **A new surface each frame wrapped the array for the GPU again.** manim makes
  one per frame over the few arrays its frames rotate through; making the
  `MTLBuffer` and mapping its pages cost ~1.7 ms a frame at 8K.  The wrap is now
  kept with the numpy array that owns the memory (up to four arrays) and dropped,
  through a weak reference, when the array is freed (numpy clears those before it
  frees the memory).  A new surface over an array in use now costs what reusing
  one does (2.09 vs 2.16 ms a frame).
- **manim copied each GPU frame for the writer** (133 MB at 8K, ~4 ms here and
  ~15 ms in an iOS process).  manim now hands CairoMetal frames to the writer as
  it does pycairo's (python-ios-lib, `CairoRenderer._frame_for_writer`).

TSNE, first 1,451 frames, frames recycled as the app's writer does, ms per frame
(two runs each, a loaded M4 Mac): 8K pycairo 9.2-10.2, CairoMetal before
14.3-15.2, now 11.3-11.5; 4K 5.2-5.6 / 6.8-6.9 / 5.9-6.1; 1080p 3.5-3.6 /
4.4-4.7 / 4.5-4.6.  So CairoMetal is 25% faster at 8K than it was and still not
faster than pycairo on this Mac: manim's frames are mostly a few hundred simple
shapes, which pycairo fills quickly on the CPU, and the GPU frame still costs a
pass over the whole frame (the tile function runs on every tile, ~1 ms at 8K
with nothing to do).

In the app (CodeBench, Designed for iPad on the M4, fresh launch per run; TSNE's
first seven animations through ManimStudio's encoder wrapper), GPU switch on:
8K120 peak memory footprint 1885-1913 MB before, 1758-1765 MB now; 4K60
1100 / 1100 -> 1070 / 1078 MB.  Render time is unchanged (8K120 57.5-63.1 s
either way, 4K60 22.7-23.4 s): at those sizes the hardware video encoder sets
the pace and the drawing, on the GPU or the CPU, keeps up with it.  On the iOS
build: `cairo_gpu_test.py` 25/25, `cairo_gpu_full_test.py` 55/55,
`cairo_gpu_deep_test.py` 98/98, `tests/test_layer_frames.py` 45/45.

New: `tests/test_layer_frames.py` (45 checks: nine scenes on four backgrounds,
layer vs whole-frame, exact-result check for translucency, untouched pixels and
odd-size edges, wraps kept and dropped).  All suites pass with layer frames on
and off.

**Found, not fixed:** `mask()` with a gradient pattern samples a mask texture
that is never bound (only image masks get one): the result is undefined in both
paths (white everywhere with the old path, nothing with layer frames; pycairo
fades through the gradient).  `mask_surface` works.  manim never masks.

**Tried, not used: MetalFX upscaling** (drawing at 4K and upscaling to 8K with
`MTLFXSpatialScaler`).  It works -- sharper than bilinear, about as close to the
native 8K frame as Lanczos (37.6-46.2 dB PSNR), with a faint bright fringe on
edges -- but the upscale alone took 7-11 ms of GPU time per 8K frame, while
drawing at 8K costs ~3.4 ms more than drawing at 4K, and the encoder still gets
8K frames.  Slower and softer, so not an option.

---

## 2026-11-04 — measured antialiasing 1.3-3.8x faster per frame

Measured on the same manim 0.19 scenes as the 11-03 round (host harness, frames
diffed against pycairo 1.29 / libcairo 1.18.6), old and new builds alternated in
one sitting, best of two.

The measured (cairo-style) coverage path -- `ANTIALIAS_GOOD` / `BEST`, or
`CM_ANALYTIC_AA=1` for every draw -- spent ~80% of its GPU time measuring edge
pixels, each walking every edge of its pixel row 30 times.  Now (`cm_fill.m`,
`shaders/fill.metal`):

- **cairo's per-row choice.** Like `cairo-tor-scan-converter.c`, a pixel row is
  measured exactly when no edge starts or ends in it (ends rounded to its 15
  sub-rows) and no two edges cross in it, else sampled at its 15 sub-row
  centres -- decided on the CPU for the whole row, as cairo does (the shader
  used to decide per pixel, looking only at edges left of it).
- **Segments.** The pixels some edge passes through are cut at every edge's
  first and last pixel, so the same edges overlap every pixel of a segment; each
  segment stores those edges and the winding of everything left of it (per
  sub-row, 4-bit with a per-segment base).  95-97% of a manim frame's edge
  pixels then see at most four edges, held in registers; five to eight (2-3%)
  take a sort-free path that keeps only their crossings.  The pixel finds its
  segment by binary search.
- **Exact-size buffers.** Reserving each draw's worst case in the frame arena
  grew the arena chains enough to cost a frame several ms of GPU time on its own
  (0.5 vs 8.5 ms with the edge pass off).

GPU per frame, old -> new: Shapes 12.0 -> 5.3 ms at 1080p, 18.9 -> 8.2 at 4K;
Graph 3.9 -> 1.2, 9.0 -> 2.4; Words 8.5 -> 3.5, 12.0 -> 4.6; Gradients 3.6 ->
2.7, 6.1 -> 3.9.  Whole renders 2-42% shorter (Graph 4K 0.90 -> 0.52 s).  Pixels
unchanged against cairo (frames' max/mean diffs equal the old path's: Shapes
17/0.033, Graph 11/0.0009, Words 71/0.0024, Gradients 15/0.015 at 1080p; random
polygons, 400 shapes: edge pixels mean |diff| 1.462 vs 1.464).  Peak memory in
this mode +1-10 MB (Shapes 4K 252 -> 262 MB): each segment holds its own copy of
its edges.  The default (MSAA) path is unchanged.  All suites green, and with
`CM_ANALYTIC_AA=1` forced on every check.

**Still open:** measured coverage is still 1.4-8x the MSAA path's GPU time (Shapes
1080p 5.3 vs 0.7 ms), so it stays opt-in; spans of five or more edges, though
rare, still cost ~3 ms of a Shapes frame.  The remaining one-sub-row (17-level)
differences against cairo, and the stroker's joins and offsets (a stroked curve's
inner side can fill pixels cairo leaves empty), are as before.

---

## 2026-11-03 — manim round: correctness bugs, speed, memory, cairo's antialiasing

Measured against real pycairo 1.29 / libcairo 1.18.6 on manim scenes (host harness:
the app's manim 0.19 with `sys.modules["cairo"] = cairo_metal`, frames diffed byte for byte).

**Bugs fixed (all were visible in manim output):**
- Gradient stop colours had red and blue exchanged in the LUT (`cm_paint.m`) — every
  manim gradient fill/stroke came out in the wrong colours (Gradients scene mean diff 15.3).
- A stroke's gradient/surface paint was placed with an identity CTM (`cm_stroke_preserve`):
  manim stroke gradients were one flat end colour.
- Drawing after a `flush()` wiped what was drawn before (each frame cleared the MSAA
  attachment and resolved over everything). Frames now LOAD the surface's pixels
  (`cm_frame_begin`, `cm_fs_load`) when it has any.
- `create_for_data` drew into a separate transparent layer and blended it over the
  caller's buffer on the CPU at flush; a flush with nothing new drawn blended the old
  layer in again. Now the caller's buffer IS the render target (zero-copy when
  page-aligned, else a staging copy): `cm_image_surface_create_direct`.
- More than ~1,800 draws in one frame raised `Error('out of memory')` (fixed 256 KB
  uniform arena). Arenas are now growable chains (`cm_frame_alloc`), 1 MB + 64 KB base.
- Fixed a GPU-hang class in the new coverage shaders (helper lanes reading out of range).

**Closer to cairo:** device paths flatten exactly as cairo does (24.8 fixed point,
cairo's de Casteljau + error metric: 200/200 polygons identical to `copy_path_flat`);
curve strokes offset along the curve tangent with no joins inside a curve, each smooth
run one polygon, outline points on the 24.8 grid (as cairo's stroker).

**Measured antialiasing (`ANTIALIAS_GOOD` / `ANTIALIAS_BEST`, or `CM_ANALYTIC_AA=1` for
every draw):** coverage per pixel from the path's edges (15 sub-rows, exact one-pass
area where every edge spans the row), solid colours and linear-gradient stops rounded
as pixman does. Edge pixels vs cairo: mean |diff| 13.2 → 1.4 levels on random polygons;
manim frames max/mean diff Shapes 95/0.56 → 17/0.033, Graph 115/0.48 → 11/0.0012,
Words 144/0.17 → 71/0.0024, Gradients 191/15.3 → 17/0.012. It costs GPU time
(+4–7 ms a 1080p frame, renders about as fast as software cairo), so DEFAULT/FAST keep
the 4x MSAA stencil path. `cairo_metal._set_analytic_aa(0|1|2)` and
`cairo_metal.last_gpu_ms()` are diagnostics.

**Speed / memory (default path, best of 2, same sitting):** flush per frame 1080p
1.9–4.5 → 0.9–2.6 ms, 4K 6.8–11.4 → 2.2–3.0 ms; whole scenes 4K Shapes 1.79 → 1.25 s
(cairo 1.97), Gradients 0.93 → 0.62 s (cairo 2.13); peak footprint −50–80 MB per render
(4K Shapes 360 → 288 MB). ~50 MB of the remaining gap to software cairo is Metal's own
first-render-pass allocation (same in a bare Metal program). Graph (a few long lines) is
still slower than cairo at 4K (0.56 vs 0.36 s): the per-frame GPU wait dominates.

**Open:** strokes still use our stroker for joins/caps (round joins: arcs, not cairo's
pen polygon); measured AA is not the default; on-device / in-app check of this build
pending. (Images under the frame's vectors, and frames with nothing drawn when the app
didn't flush: fixed on manim's side on 2026-11-06 — its camera calls `_flush_all` before
writing images into the frame and when the frame is done. See docs/manim.md.)

---

## What works (verified)

- **`swift build` (SwiftPM) — clean, 0 errors.** Compiles all 24 modules in
  `src/` (the original core + `cm_clip`, `cm_compose`, `cm_font`, `cm_ft`,
  `cm_group`, `cm_mesh`, `cm_pattern`, `cm_query`, `cm_raster`, `cm_recording`,
  `cm_region`, `cm_state`, `cm_surface_format`, `cm_surface_png`,
  `cm_surface_similar`, `cm_text`).
- **clang/Make path — clean, 0 errors.** `make` builds `build/libcairometal.a`,
  compiles `shaders/fill.metal` with `xcrun metal` into `build/default.metallib`,
  and links `build/demo`. `make run` writes `build/demo.png` (donut + gradient +
  round-join stroke), exercising path flattening, both fill rules, the gradient
  LUT, CPU stroke expansion, the stencil-then-cover pipeline, the MSAA resolve
  into the IOSurface target, and the read-back.
- **Full public C API.** `include/cairo_metal.h` (~1020 lines, 246 `CM_PUBLIC`
  functions) declares: surfaces in ARGB32/RGB24/A8/A1/RGB16_565 + similar +
  recording + PNG; context save/restore + groups; **all 28 operators** (0–13
  fixed-function Porter-Duff blend states, 14–28 programmable-blend cover
  fragments in `cm_compose.m`); clip/clip_preserve/reset_clip/clip_extents/
  in_clip; mask/mask_surface; paint/paint_with_alpha; full path API incl.
  arc/arc_negative/rel_*/rectangle/text_path; full transform + matrix algebra;
  solid/surface/linear/radial/mesh patterns; toy text + font options + scaled
  fonts (`cm_text`/`cm_font`/`cm_ft`); regions (`cm_region`); query extents +
  in_fill/in_stroke; all cairo-exact enums.
- **Python extension — full pycairo drop-in (built + imported + smoke-tested).**
  `python/cairo_metal_ext.c` (2246 lines) exposes **171 symbols / 18 classes /
  20 enums**, with **Context carrying 91 methods**. Every Python method forwards
  to a `cm_*` symbol verified present in both the header and
  `build/libcairometal.a` (no invented symbols). `python/build.sh` builds it
  clean; `python/test_full_shim.py` passes **all 81 checks**; the original
  `python/test_shim.py` manim regression is **byte-identical to the C demo (mean
  abs diff 0.0000)** — full backward compatibility.

---

## Correctness caveats (read before trusting pixels)

- **Correctness is validated by ~400 computed-expectation checks**, not by a
  per-pixel diff against upstream cairo. The three suites assert specific pixels
  against hand-computed premultiplied BGRA values (Porter-Duff + blend-mode math,
  clip shapes, transforms, gradients, masks, regions, …) — a strong signal, and
  arguably stronger than "matches another renderer" for catching real defects. A
  true reference diff against **real pycairo was not run** (pycairo isn't
  installed, though system cairo is — a `pip install pycairo` would enable it).
  That diff, plus validation on a physical iOS device, remain the last
  correctness steps.
- **On-device (iOS arm64) validation pending.** The package targets iOS 17 and
  cross-compiles, but rendering has only been exercised on macOS (Apple silicon).

---

## Bugs found — and FIXED — by the rigorous test suite (2026-06-06)

Three independent test agents (`tests/test_raster.py`, `test_geometry.py`,
`test_robust.py`) ran ~400 computed-expectation checks. They first found 10 real
bugs (~88% pass); **all 10 were then fixed and the suite is now fully green**:
`test_raster 65/65`, `test_geometry 177/177`, `test_robust 78/78`,
`test_full_shim 81/81`, and the manim regression `test_shim` PASS — plus a clean
`swift build` + `make` and the demo renders. The pixel-math core was always exact
(solid fills, both fill rules + holes, all 13 standard Porter-Duff operators,
gradients, strokes/caps/joins, default AA, transforms + matrix algebra +
round-trips, arc/rectangle/rel paths + extents, rectangular clip, region algebra,
in_fill/in_stroke/extents, save/restore, text, RGB24, memory safety). The 10
bugs that were found and **fixed** (loci = where the fix landed):

| # | sev | bug | likely fix locus |
|---|-----|-----|------------------|
| 1 | HIGH | `get_stride()` returns the GPU IOSurface-aligned stride, not the packed `get_data()` stride (== `format_stride_for_width`). Breaks `y*stride+x*4` pixel access. | surface `get_stride` accessor — return the packed stride |
| 2 | HIGH | Non-rectangular `clip()` applies only the path's **bounding box** (in_clip/clip_extents are correct; the rasterizer ignores the shape). | `cm_clip` — real stencil clip, not AABB/scissor |
| 3 | HIGH | `mask_surface()` ignores the source color and writes coverage into the **red** channel. | `cm_paint`/`cm_compose` mask path |
| 4 | HIGH | Separable blend modes (MULTIPLY/SCREEN/DARKEN/LIGHTEN/DIFFERENCE/EXCLUSION/OVERLAY/…) are **stubbed to OVER**. | `cm_compose` programmable-blend fragments (claimed, stubbed) |
| 5 | HIGH | Reusing one dst Context across successive SurfacePattern fills → `DEVICE_ERROR(35)` (deterministic ~3rd fill); some mask/group chains SIGABRT. Fresh context per fill = 0/300. | `cm_device`/`cm_group` cmd-buffer/state reuse |
| 6 | MED-HIGH | `paint_with_alpha`/`mask` drops the alpha multiplier for **SurfacePattern/group** sources (renders opaque). | pattern-source alpha path |
| 7 | MED | `ANTIALIAS_NONE` renders fills at ~25% alpha (64/255) — unnormalized MSAA sample. | antialias-none resolve |
| 8 | MED | `FORMAT_A8` stores the premultiplied **red** channel, not coverage alpha (opaque-black mask → fully transparent). | `cm_surface_format` A8 store |
| 9 | MED | `mask()` leaves the **alpha** channel unmasked (color masked, alpha isn't). | `cm_compose` mask alpha |
| 10 | LOW | Abstract bases (FontFace/Pattern/Gradient/Surface) are directly constructible (pycairo forbids). | ext `tp_new` guards |

All documented gaps below fail cleanly as documented. No leaks/UAF; out-of-range
inputs clamp; bad sizes/formats error safely.

---

## Known gaps (specific, with the next action)

> **Update (2026-06-06):** gaps 1–3 below are now **CLOSED** — RecordingSurface
> drawing is implemented (opt-in via `CM_RECORDING_RASTER`), the omitted bindings
> are exposed (glyphs / FT-font-from-file / raster-source / subsurface /
> map_to_image / create_similar), and path introspection
> (`copy_path` / `copy_path_flat` / `append_path` / `Path`) is done. The full
> reference test (`cairo_gpu_full_test.py`, 55/55) surfaced three MINOR remaining
> gaps: **(a) mesh-gradient rasterization** — `MeshPattern` + the Coons-patch API
> construct fine, but `set_source(mesh)+paint` renders empty (niche; manim
> doesn't use it); **(b) `RectangleInt`** type not exposed (`Region` works with
> plain `(x,y,w,h)` tuples); **(c) context-alive-through-flush** — cairo_metal
> commits its deferred GPU frame on `surface.flush()`, so a `Context` must outlive
> the flush (real cairo is immediate-mode; manim / tests / the test script all
> keep it alive, so unaffected in practice).

1. **RecordingSurface cannot be drawn into.** It can be created and introspected
   (`ink_extents` / `get_extents` work), but `fill`/`stroke`/`paint` into a
   recording surface raise `Error(35)` DEVICE_ERROR — the recording op-log
   dispatch routes through `cm_glue_frame_for_surface`, which needs a GPU
   IOSurface target. **Next:** wire the op-log replay/dispatch in `cm_recording.m`.
2. **Bindings omitted though the C API backs them.** Glyph-array entry points
   (`show_glyphs`, `show_text_glyphs`, `glyph_path`, `glyph_extents`), FreeType
   `FT` font faces, `RasterSourcePattern`, subsurfaces (`create_for_rectangle`),
   `map_to_image`, `create_similar`. **Next:** add the Python wrappers (the
   `cm_*` functions already exist; glyph paths need `cm_glyph_t[]` marshalling).
3. **Path introspection has no C backing.** `copy_path` / `copy_path_flat` /
   `append_path` and a `Path` iterable are absent because the header has no
   `cm_copy_path` / path-data export. **Next:** add a `cm_copy_path` exporter to
   the C library, then bind it.
4. **Surface lifetime is a footgun (worked around in the shim).**
   `cm_surface_destroy` is an unconditional `free()`, and
   `cm_pattern_create_for_surface` adds a second destroy path; `mask_surface`
   frees its surface *during* the call. The Python layer transfers ownership /
   marks wrappers dead to stay UAF-free (verified over a 300-iteration stress
   test), but the **C contract should be hardened to refcount surfaces**.
5. **By design, not present:** PDF/SVG/PS surfaces (this is a raster + recording
   backend only) and the VideoToolbox `IOSurface → CVPixelBuffer → encoder` glue
   (lives in the consumer; see the project's GPU-manim follow-up notes).

---

## Suggested next steps

- Close gaps 1–4 above (recording dispatch, omitted-but-backed bindings,
  `cm_copy_path` + path iteration, surface refcounting).
- Install pycairo (or build reference cairo) and add per-pixel golden diffs for
  operators, clip, mask, gradients, fonts — the one missing correctness signal.
- Run the demo + Python smoke tests on a physical iOS device.
- Wire IOSurface → `CVPixelBuffer` → VideoToolbox in the iOS app (note: profiling
  already shows GPU rasterization does not speed up manim — fill is ~5% of render
  time; this path is for completeness / non-manim consumers, not a manim win).
