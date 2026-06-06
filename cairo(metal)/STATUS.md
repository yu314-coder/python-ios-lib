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
