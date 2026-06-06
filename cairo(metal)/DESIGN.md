# CairoMetal — Design

A Metal-GPU implementation of the **exact** subset of the cairo 2D API that
manim's iOS Cairo renderer uses, rendering vector paths directly into an
**IOSurface-backed `MTLTexture`** so finished frames are handed to
`h264_videotoolbox` with **zero CPU readback**.

This document specifies the architecture, the stencil-then-cover pipeline, the
required optimizations, and how it replaces cairo inside manim's `camera.py`.

---

## 1. Why this exists

manim's `Camera` renders every frame on the CPU with pycairo. From
`manim/camera/camera.py`:

```python
surface = cairo.ImageSurface.create_for_data(pixel_array.data, cairo.FORMAT_ARGB32, pw, ph)
ctx = cairo.Context(surface)
ctx.scale(pw, ph)
ctx.set_matrix(cairo.Matrix((pw/fw), 0, 0, -(ph/fh), (pw/2)-fc[0]*(pw/fw), (ph/2)+fc[1]*(ph/fh)))
```

then for each `VMobject` (`display_vectorized`, lines ~692-695) it does
**background-stroke → fill → stroke** over the *same* path, which is why every
fill/stroke is the `_preserve` variant.

On iOS the pipeline is: cairo rasterizes on CPU → the ARGB32 buffer is copied →
uploaded to VideoToolbox. That copy + CPU rasterization dominates frame time.
**CairoMetal removes both**: paths rasterize on the GPU, and the render target
*is* the IOSurface VideoToolbox encodes from.

### The cairo subset we implement (and nothing else)

Taken verbatim from the calls `camera.py` makes:

| Area      | cairo call(s)                                                     | CairoMetal                              |
|-----------|------------------------------------------------------------------|-----------------------------------------|
| Surface   | `ImageSurface.create_for_data(data, FORMAT_ARGB32, w, h)`        | `cm_image_surface_create_argb32`        |
| Context   | `Context(surface)`                                                | `cm_context_create`                     |
| Transform | `scale`, `set_matrix(Matrix(...))`                               | `cm_scale`, `cm_set_matrix`             |
| Path      | `new_path`, `new_sub_path`, `move_to`, `line_to`, `curve_to`, `close_path` | `cm_new_path` … `cm_close_path` |
| Source    | `set_source_rgba`; `LinearGradient` + `add_color_stop_rgba` + `set_source` | `cm_set_source_rgba`, `cm_linear_gradient_create`, `cm_pattern_add_color_stop_rgba`, `cm_set_source` |
| Fill      | `fill_preserve` (NONZERO default + EVEN-ODD)                      | `cm_fill_preserve` + `cm_set_fill_rule` |
| Stroke    | `stroke_preserve` + `set_line_width`/`set_line_join`/`set_line_cap` | `cm_stroke_preserve` + setters        |
| Flush     | `surface.flush()`                                                 | `cm_surface_flush`                      |

> **`set_matrix` replaces, it does not compose.** cairo's `set_matrix` overrides
> the CTM, so manim's `ctx.scale(pw,ph)` on the line above is immediately
> superseded by the following `set_matrix(...)`. CairoMetal matches this exactly
> — `cm_scale` post-multiplies the CTM, `cm_set_matrix` replaces it.

### Pixel format contract (do not "fix")

cairo `FORMAT_ARGB32` is a 32-bit **native-endian, premultiplied** pixel; on
little-endian arm64 the in-memory byte order is **B, G, R, A**. The backing
texture is therefore `MTLPixelFormatBGRA8Unorm`.

manim already swaps colours to B,G,R before calling cairo
(`ctx.set_source_rgba(*rgbas[0][2::-1], rgbas[0][3])` and
`pat.add_color_stop_rgba(offset, *rgba[2::-1], rgba[3])`, lines ~754 and ~761).
Because our target has the **same BGRA layout**, CairoMetal keeps the identical
argument order and does **not** re-swap. It **does** premultiply alpha in the
fragment shader, matching cairo's premultiplied surface. Net effect: the
existing manim swap stays correct and output is byte-identical in ordering.

---

## 2. Architecture overview

```
        manim camera.py  (cm_* drop-in, see §6)
                 │  C API  (include/cairo_metal.h)
                 ▼
   ┌────────────────────────────────────────────────────────────┐
   │ cm_context.c   public glue + state machine + draw batching   │
   └───────┬───────────────┬───────────────┬──────────────┬──────┘
           │               │               │              │
           ▼               ▼               ▼              ▼
     cm_path.c        cm_stroke.c       cm_paint.c     cm_fill.c
   record/flatten/   stroke→fillable   solid+linear   stencil-then
   tessellate         polygon           gradient LUT   -cover encode
           │               │               │              │
           └───────────────┴───────┬───────┴──────────────┘
                                    ▼
                         cm_device.m + cm_surface.m
              MTLDevice/queue · persistent pipeline & depth-stencil
              states · triple-buffered ring + dispatch_semaphore ·
              IOSurface-backed BGRA8 target + MSAA + stencil
                                    │
                                    ▼  zero-copy IOSurfaceRef
                          h264_videotoolbox encode
```

Concrete struct layouts and the inter-module function names live in
`src/cm_internal.h`; that header is the coordination contract for the parallel
implementers. `.m` files own everything Objective-C/Metal; the `.c` modules are
pure C and touch GPU objects only through opaque `void*` handles + the
`cm_frame_*` / `cm_device_*` accessors.

---

## 3. The stencil-then-cover pipeline

Filling arbitrary self-intersecting paths with holes (manim draws plenty) is
done with the classic two-pass **stencil-then-cover** technique. We never CPU-
triangulate concave polygons; the stencil buffer resolves coverage.

### Pass 0 — CPU flatten (`cm_path_flatten`)
Cubic Béziers are flattened by **adaptive recursive de Casteljau**, with the
flatness test done in **device space** (after the CTM) so on-screen deviation is
bounded by `CM_FLATTEN_TOLERANCE` (≈0.1 px) regardless of zoom. The result is a
set of device-space polyline **contours**.

### Pass 1 — Stencil (write coverage, no colour)
For each contour, emit a **triangle fan** about its first vertex
(`cm_path_emit_fan`). Fans of a concave/self-intersecting contour overlap; the
stencil ops turn that overlap into correct coverage:

- **NONZERO** (`CM_FILL_RULE_WINDING`, cairo default):
  `CM_PIPE_STENCIL_NONZERO` + `CM_DSS_STENCIL_WRITE_NONZERO` — back/front faces
  use **increment-wrap / decrement-wrap**, accumulating winding number. Requires
  two-sided stencil (separate front/back ops); fans are emitted CCW and Metal's
  winding determines sign.
- **EVEN-ODD** (`CM_FILL_RULE_EVEN_ODD`):
  `CM_PIPE_STENCIL_EVENODD` + `CM_DSS_STENCIL_WRITE_EVENODD` — stencil op
  **invert** on the low bit (parity).

Colour write mask is **off** during this pass; only stencil is touched. Depth
testing is unused (2D); the stencil attachment is MSAA, sample count
`CM_MSAA_SAMPLE_COUNT`.

### Pass 2 — Cover (test stencil, write colour)
Draw the path's **device-space bounding quad** (`cm_path_bounds`). The
depth-stencil state tests the stencil (`!= 0` for nonzero, `& 1` for even-odd)
and, on the **same** op, **resets the touched stencil to 0** so the buffer is
clean for the next path in the batch (no per-path stencil clear needed). The
fragment shader produces the paint:

- `CM_PIPE_COVER_SOLID` — outputs the uniform `solid` colour, premultiplied.
- `CM_PIPE_COVER_LINEAR` — projects the fragment's device position onto the
  gradient axis `grad_axis` (`t = dot(p - a, b - a) / |b - a|²`, clamped) and
  samples the baked **1D LUT** (`cm_paint_gradient_lut`, 256×1 BGRA8), then
  premultiplies.

### Anti-aliasing
**MSAA** (4×) on the colour + stencil attachments gives cairo-quality edges
without an analytic-coverage shader. `cm_frame_end` resolves MSAA into the
IOSurface-backed single-sample BGRA8 texture. (Hook for a future
distance-to-edge AA exists but MSAA is the shipping path.)

### Stroke (`cm_stroke_expand`)
Strokes are **expanded on the CPU** into a fillable outline polygon — segment
quads plus join and cap geometry — honoring `line_width`, `line_join`
(miter/round/bevel, with `miter_limit`), and `line_cap` (butt/round/square).
Round joins/caps are tessellated to `CM_ARC_TOLERANCE`. The resulting polygon is
run through the **same** stencil-then-cover fill with **NONZERO** winding, so
overlapping stroke pieces composite exactly once — matching cairo's stroke
semantics. No separate stroke rasterizer.

### Vertex/fragment data flow
The vertex shader takes device-space `cm_vec2f` positions, applies the
`to_clip` uniform (device px → clip space, y-flipped for Metal), and passes
device position to the fragment stage for gradient projection. The CTM is
applied on the **CPU** at flatten time (so flattening tolerance is correct);
`ctm_row0/row1` in the uniforms are available for any GPU-side transform needs
but the shipping path pre-transforms.

---

## 4. Required optimizations (designed in, not bolted on)

All of these are structural in `cm_internal.h` / the module split:

1. **Persistent pipeline & depth-stencil states.** Every
   `MTLRenderPipelineState` (`CM_PIPE_*`, 4 of them) and `MTLDepthStencilState`
   (`CM_DSS_*`, 4 of them) is built **once** in `cm_device_create` and fetched
   O(1) via `cm_device_pipeline` / `cm_device_depthstencil`. Nothing is compiled
   or created per-frame or per-draw.

2. **One command buffer per frame.** `cm_frame_begin` creates a **single**
   `MTLCommandBuffer` + render command encoder for the whole frame; every fill
   and stroke of every VMobject encodes into that one encoder. `cm_frame_end`
   commits it once. (manim renders one pixel array per frame across many
   VMobjects — this batches them all.)

3. **Triple-buffered dynamic buffers + `dispatch_semaphore`.** Vertex and
   uniform data come from a ring of `CM_FRAMES_IN_FLIGHT` (=3) large
   `MTLBuffer`s. `cm_frame_begin` waits on a `dispatch_semaphore` of count 3 and
   the GPU completion handler signals it, so the CPU never writes a slice the GPU
   is still reading — **no CPU↔GPU stalls**.

4. **IOSurface-backed target → zero-copy encode.**
   `cm_image_surface_create_argb32` allocates an `IOSurface` and wraps it as the
   colour `MTLTexture`. `cm_surface_get_iosurface` returns the `IOSurfaceRef`;
   the caller wraps it in a `CVPixelBuffer` and feeds VideoToolbox directly. No
   `glReadPixels`, no `getBytes`, no staging copy.

5. **Zero per-draw heap allocation.** Per-frame geometry is **bump-allocated**
   from the ring via `cm_frame_alloc_verts` / `cm_frame_alloc_uniforms` (returns
   a pointer + `MTLBuffer` + offset). The recorded-path arrays in `cm_path` grow
   amortized and are **reset, not freed**, between frames. The gradient LUT and
   all pipeline states are cached. No `malloc`/`[NSObject alloc]` on the hot
   path.

6. **Group draws by pipeline state.** `cm_fill_encode` consults
   `ctx->last_pipeline_group` and orders the stencil/cover binds to coalesce
   consecutive draws that share a pipeline (e.g. runs of solid fills), minimizing
   `setRenderPipelineState`/`setDepthStencilState` churn within the single
   encoder.

---

## 5. Module / file layout

```
cairo(metal)/
├── include/cairo_metal.h     PUBLIC C API (the cairo subset)
├── src/cm_internal.h         INTERNAL contract: structs + function names
├── src/cm_api.c              implements cairo_metal.h, thin glue → modules
├── src/cm_context.c          context state machine, batching, frame driver
├── src/cm_path.c             record / adaptive-flatten / tessellate fans
├── src/cm_stroke.c           stroke expansion → fillable polygon
├── src/cm_paint.c            solid + linear gradient, 1D LUT bake
├── src/cm_fill.c             stencil-then-cover encode
├── src/cm_matrix.c           affine math helpers
├── src/cm_device.m           MTLDevice/queue, persistent states, ring+semaphore
├── src/cm_surface.m          IOSurface-backed target, MSAA, flush/resolve/map
├── shaders/cairo_metal.metal vertex + stencil/cover-solid/cover-linear shaders
├── examples/                 standalone smoke tests (render → PNG / IOSurface)
└── tests/                    fill rules, holes, stroke joins/caps, gradient
```

---

## 6. manim integration (replace cairo `ImageSurface`)

The goal: `camera.py` keeps its logic; only the cairo handle is swapped for a
CairoMetal one. Two integration tiers:

### 6a. Python shim (`cairo_metal` ext module)
A small CPython extension exposes objects that **quack like pycairo**
(`Context`, `ImageSurface`, `LinearGradient`, `Matrix`, the `FORMAT_ARGB32` /
`LineJoin` / `LineCap` constants) and forward to the `cm_*` C API. The enums are
numerically identical to cairo's, so `LINE_JOIN_MAP` / `CAP_STYLE_MAP`
(camera.py lines ~47-57) transfer unchanged.

`get_cairo_context` (lines ~607-633) changes only at the surface line:

```python
# before
surface = cairo.ImageSurface.create_for_data(pixel_array.data, cairo.FORMAT_ARGB32, pw, ph)
ctx = cairo.Context(surface)
# after  (cm = the cairo_metal shim)
surface = cm.ImageSurface(cm.FORMAT_ARGB32, pw, ph)   # owns IOSurface storage
ctx = cm.Context(surface)
# … unchanged: ctx.scale(pw, ph); ctx.set_matrix(cm.Matrix(...))
```

Because CairoMetal owns the IOSurface pixel storage, `pixel_array` is created to
**wrap the surface's mapped buffer** (`cm_surface_map_argb32`) instead of the
surface wrapping `pixel_array.data`. The rest of `set_cairo_context_path`,
`set_cairo_context_color`, `apply_fill`, `apply_stroke` (lines ~698-823) call
the same method names and Just Work. The per-pixel-array context cache
(`pixel_array_to_cairo_context`) is unchanged.

### 6b. Zero-copy to VideoToolbox
manim's file writer normally pushes `pixel_array` bytes to ffmpeg/the encoder.
On iOS we instead:

```
cm_surface_flush(surface)                      # resolve MSAA, sync IOSurface
ios = cm_surface_get_iosurface(surface)        # IOSurfaceRef (no copy)
CVPixelBufferCreateWithIOSurface(... ios ...)  # wrap, still no copy
VTCompressionSessionEncodeFrame(...)           # h264_videotoolbox encodes it
```

The `IOSurface` the GPU rendered into is the exact memory the H.264 encoder
samples — **no `glReadPixels`, no CPU readback, no staging texture**. This is
the whole reason the target is IOSurface-backed rather than a plain `MTLTexture`
or a CPU buffer.

### What is intentionally NOT supported
Text/glyphs, images/`set_source_surface`, dashes, clipping, radial gradients,
`paint`/`mask`, operators other than OVER, non-ARGB32 formats. manim's Cairo
camera does not call them. If a future call site needs one, add it to the
public header and a module — the contract in `cm_internal.h` is the place to
extend.

---

## 7. State defaults (match cairo)

| State        | cairo default              | CairoMetal default            |
|--------------|----------------------------|-------------------------------|
| CTM          | identity                   | identity                      |
| source       | opaque black (0,0,0,1)     | `CM_PAINT_SOLID` (0,0,0,1)    |
| fill rule    | `WINDING`                  | `CM_FILL_RULE_WINDING`        |
| line width   | 2.0                        | 2.0                           |
| line join    | `MITER`                    | `CM_LINE_JOIN_MITER`          |
| line cap     | `BUTT`                     | `CM_LINE_CAP_BUTT`            |
| miter limit  | 10.0                       | 10.0                          |
