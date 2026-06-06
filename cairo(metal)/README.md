# CairoMetal

A Metal-GPU implementation of the **exact subset** of the cairo 2D graphics API
that [manim](https://www.manim.community/)'s iOS Cairo renderer
(`manim/camera/camera.py`) calls — rendering vector paths directly into an
**IOSurface-backed `MTLTexture`** so finished frames hand off to
`h264_videotoolbox` with **zero CPU readback**.

It is not a general cairo port. It implements precisely the surface / context /
path / source / fill / stroke calls `camera.py` makes, with cairo-identical
semantics and enum values, and nothing else (see [Scope](#scope)). The point is
to delete two costs from manim's iOS frame pipeline: CPU rasterization, and the
copy of the rasterized buffer up to the video encoder.

> **Status, up front:** the library **builds** (`swift build` and the
> `Makefile`/`build.sh` clang path both succeed) and the bundled demo
> **renders correctly on a Metal device** — donut with a hole, a linear
> gradient, and a round-join/round-cap stroke, all anti-aliased. What is *not*
> done: the manim Python shim, the VideoToolbox wiring, and a real test suite.
> Full honesty in [Current status](#current-status) and [STATUS.md](STATUS.md).

---

## Table of contents

- [Why this exists](#why-this-exists)
- [Scope](#scope)
- [The CairoMetal ↔ cairo API map](#the-cairometal--cairo-api-map)
- [Architecture](#architecture)
- [The stencil-then-cover pipeline](#the-stencil-then-cover-pipeline)
- [Optimizations](#optimizations)
- [Build & run](#build--run)
- [Consuming the library](#consuming-the-library)
- [manim integration plan](#manim-integration-plan)
- [Current status](#current-status)
- [Repository layout](#repository-layout)
- [Further reading](#further-reading)

---

## Why this exists

manim's `Camera` renders every frame on the CPU with pycairo. From
`manim/camera/camera.py`:

```python
surface = cairo.ImageSurface.create_for_data(pixel_array.data, cairo.FORMAT_ARGB32, pw, ph)
ctx = cairo.Context(surface)
ctx.scale(pw, ph)
ctx.set_matrix(cairo.Matrix((pw/fw), 0, 0, -(ph/fh), (pw/2)-fc[0]*(pw/fw), (ph/2)+fc[1]*(ph/fh)))
```

then, for each `VMobject` (`display_vectorized`), it draws
**background-stroke → fill → stroke** over the *same* path — which is why every
fill and stroke is the `_preserve` variant.

On iOS the pipeline is: cairo rasterizes on the CPU → the ARGB32 buffer is
copied → uploaded to VideoToolbox. That copy plus the CPU rasterization
dominate frame time. **CairoMetal removes both**: paths rasterize on the GPU,
and the render target *is* the IOSurface the H.264 encoder samples.

This package is part of the [OfflinAi](https://github.com/yu314-coder) effort to
run a real scientific-Python stack (including manim) entirely on-device on iOS.

---

## Scope

Implemented (because `camera.py` calls them), with cairo-identical semantics:

- **Surface:** `ImageSurface` create / flush / dimensions (ARGB32 only).
- **Context:** create / destroy.
- **Transform:** `set_matrix` (replaces the CTM, *does not* compose — exactly
  like cairo), `scale`, `get_matrix`.
- **Path:** `new_path`, `new_sub_path`, `move_to`, `line_to`, `curve_to`
  (cubic), `close_path`.
- **Source:** solid `set_source_rgba`; `LinearGradient` +
  `add_color_stop_rgba` + `set_source`.
- **Fill:** `fill_preserve`, `set_fill_rule` (NONZERO default **and** EVEN-ODD).
- **Stroke:** `stroke_preserve`, `set_line_width` / `set_line_join` /
  `set_line_cap` / `set_miter_limit`.

**Intentionally not supported** (manim's Cairo camera does not call them): text /
glyphs, images / `set_source_surface`, dashes, clipping, radial gradients,
`paint` / `mask`, operators other than `OVER`, and non-ARGB32 formats. The
contract in [`src/cm_internal.h`](src/cm_internal.h) is the place to extend if a
future call site needs one.

### Pixel-format contract (do not "fix" this)

cairo `FORMAT_ARGB32` is a 32-bit **native-endian, premultiplied** pixel; on
little-endian arm64 the in-memory byte order is **B, G, R, A**. The backing
texture is therefore `MTLPixelFormatBGRA8Unorm`.

manim already swaps colours into B,G,R order *before* calling cairo
(`ctx.set_source_rgba(*rgbas[0][2::-1], rgbas[0][3])` and
`pat.add_color_stop_rgba(offset, *rgba[2::-1], rgba[3])`). Because our target
has the **same BGRA layout**, CairoMetal keeps the identical argument order and
does **not** re-swap. It **does** premultiply alpha in the fragment shader, to
match cairo's premultiplied surface. Net effect: manim's existing swap stays
correct and byte ordering is identical.

---

## The CairoMetal ↔ cairo API map

The public C API is [`include/cairo_metal.h`](include/cairo_metal.h). Every
entry point mirrors a specific cairo / pycairo call:

| Area      | cairo / pycairo call                                                     | CairoMetal C API                                                                                   |
|-----------|--------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Surface   | `ImageSurface.create_for_data(data, FORMAT_ARGB32, w, h)`               | `cm_image_surface_create_argb32(CM_FORMAT_ARGB32, w, h)`                                            |
| Surface   | `surface.flush()`                                                        | `cm_surface_flush(s)`                                                                               |
| Surface   | `image_surface_get_width` / `_height`                                    | `cm_surface_get_width` / `cm_surface_get_height`                                                    |
| Surface   | *(no cairo equivalent — the whole point)*                                | `cm_surface_get_iosurface(s)` → `IOSurfaceRef` for zero-copy VideoToolbox                           |
| Surface   | raw `pixel_array.data`                                                   | `cm_surface_map_argb32(s, &stride)` (CPU fallback / tests)                                          |
| Context   | `Context(surface)`                                                       | `cm_context_create(s)`                                                                              |
| Transform | `ctx.set_matrix(Matrix(a,b,c,d,e,f))`                                    | `cm_set_matrix(ctx, &m)` — **replaces** the CTM                                                     |
| Transform | `ctx.scale(sx, sy)`                                                      | `cm_scale(ctx, sx, sy)` — post-multiplies                                                           |
| Transform | `ctx.get_matrix()`                                                       | `cm_get_matrix(ctx, &out)`                                                                          |
| Path      | `new_path` / `new_sub_path`                                             | `cm_new_path` / `cm_new_sub_path`                                                                   |
| Path      | `move_to` / `line_to` / `curve_to` / `close_path`                       | `cm_move_to` / `cm_line_to` / `cm_curve_to` / `cm_close_path`                                       |
| Source    | `ctx.set_source_rgba(r,g,b,a)`                                          | `cm_set_source_rgba(ctx, r, g, b, a)`                                                               |
| Source    | `LinearGradient(x0,y0,x1,y1)`                                            | `cm_linear_gradient_create(x0, y0, x1, y1)`                                                         |
| Source    | `pat.add_color_stop_rgba(off,r,g,b,a)`                                  | `cm_pattern_add_color_stop_rgba(pat, off, r, g, b, a)`                                              |
| Source    | `ctx.set_source(pat)`                                                    | `cm_set_source(ctx, pat)`                                                                           |
| Source    | `pattern.destroy` / GC                                                   | `cm_pattern_destroy(pat)`                                                                           |
| Fill      | `ctx.set_fill_rule(...)`                                                | `cm_set_fill_rule(ctx, rule)`                                                                       |
| Fill      | `ctx.fill_preserve()`                                                    | `cm_fill_preserve(ctx)`                                                                             |
| Stroke    | `set_line_width` / `set_line_join` / `set_line_cap` / `set_miter_limit` | `cm_set_line_width` / `cm_set_line_join` / `cm_set_line_cap` / `cm_set_miter_limit`                 |
| Stroke    | `ctx.stroke_preserve()`                                                  | `cm_stroke_preserve(ctx)`                                                                           |
| Status    | `cairo_status()` / `cairo_status_to_string()`                           | `cm_context_status` / `cm_last_status` / `cm_status_to_string`                                      |

**Enums are numerically identical to cairo's.** `cm_fill_rule_t`,
`cm_line_cap_t`, `cm_line_join_t`, and `CM_FORMAT_ARGB32` use the same integer
values as `CAIRO_FILL_RULE_*`, `CAIRO_LINE_CAP_*`, `CAIRO_LINE_JOIN_*`, and
`CAIRO_FORMAT_ARGB32`, so manim's `LINE_JOIN_MAP` / `CAP_STYLE_MAP` int mapping
transfers unchanged. `cm_matrix_t` is **field-for-field binary-compatible** with
`cairo_matrix_t` (`a=xx, b=yx, c=xy, d=yy, e=x0, f=y0`).

> **`set_matrix` replaces, it does not compose.** cairo's `set_matrix` overrides
> the CTM, so manim's `ctx.scale(pw, ph)` is immediately superseded by the
> following `set_matrix(...)`. CairoMetal matches this exactly: `cm_scale`
> post-multiplies, `cm_set_matrix` replaces.

State defaults also match cairo (identity CTM; source opaque black; fill rule
WINDING; line width 2.0; join MITER; cap BUTT; miter limit 10.0).

---

## Architecture

```
        manim camera.py  (cm_* drop-in via the Python shim, see plan below)
                 │  C API  (include/cairo_metal.h)
                 ▼
   ┌────────────────────────────────────────────────────────────┐
   │ cairo_metal.m    public glue + context state machine +       │
   │                  per-frame draw batching                      │
   └───────┬───────────────┬───────────────┬──────────────┬──────┘
           │               │               │              │
           ▼               ▼               ▼              ▼
     cm_path.m        cm_stroke.m       cm_paint.m     cm_fill.m
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

The concrete struct layouts and inter-module function names live in
[`src/cm_internal.h`](src/cm_internal.h) — that header is the coordination
contract for the modules. `cm_matrix.c` is pure C (affine helpers); everything
else is Objective-C because it touches Metal / IOSurface. The geometry
producers (path / stroke / paint / fill) deal in opaque `void*` GPU handles plus
the `cm_frame_*` / `cm_device_*` accessors, so the math is cleanly separated
from the GPU plumbing.

For the full design rationale, see [DESIGN.md](DESIGN.md).

---

## The stencil-then-cover pipeline

Filling arbitrary self-intersecting paths with holes (manim draws plenty) uses
the classic two-pass **stencil-then-cover** technique. Concave polygons are
never CPU-triangulated; the stencil buffer resolves coverage.

1. **CPU flatten** (`cm_path_flatten`). Cubic Béziers are flattened by adaptive
   recursive de Casteljau, with the flatness test in **device space** (after the
   CTM) so on-screen deviation stays under `CM_FLATTEN_TOLERANCE` (≈0.1 px)
   regardless of zoom. Output: device-space polyline contours.
2. **Stencil pass** (write coverage, no colour). Each contour emits a triangle
   fan about its first vertex. Overlapping fan triangles become correct coverage
   via the stencil ops: **NONZERO** uses two-sided increment-wrap /
   decrement-wrap (winding number); **EVEN-ODD** uses invert-on-the-low-bit
   (parity). Colour writes are masked off.
3. **Cover pass** (test stencil, write colour). The path's device-space bounding
   quad is drawn; the depth-stencil state tests the stencil **and resets the
   touched bits to 0 in the same op**, so no per-path stencil clear is needed.
   The fragment shader produces the paint — solid premultiplied colour, or a
   linear gradient sampled from a baked 1D LUT.

**Anti-aliasing** is 4× **MSAA** on the colour + stencil attachments (cairo-
quality edges with no analytic-coverage shader); `cm_frame_end` resolves MSAA
into the IOSurface-backed single-sample target.

**Strokes** are expanded on the CPU into a fillable outline polygon (segment
quads + join + cap geometry, honoring width / join / cap / miter limit, round
pieces tessellated to `CM_ARC_TOLERANCE`), then run through the **same**
stencil-then-cover fill with NONZERO winding — so overlapping stroke pieces
composite exactly once, matching cairo.

Shaders live in [`shaders/fill.metal`](shaders/fill.metal) — the full vertex +
stencil/cover-solid/cover-linear entry points.

---

## Optimizations

These are structural in the module split / `cm_internal.h`, not bolted on:

1. **Persistent pipeline & depth-stencil states.** Every
   `MTLRenderPipelineState` (4) and `MTLDepthStencilState` (4) is built **once**
   in `cm_device_create` and fetched O(1) via `cm_device_pipeline` /
   `cm_device_depthstencil`. Nothing is compiled or created per-frame or
   per-draw.
2. **One command buffer per frame.** A single `MTLCommandBuffer` + render
   encoder handles every fill and stroke of every VMobject in the frame; it is
   committed once. (manim renders one pixel array per frame across many
   VMobjects — this batches them all.)
3. **Triple-buffered dynamic buffers + `dispatch_semaphore`.** Vertex and
   uniform data come from a ring of `CM_FRAMES_IN_FLIGHT` (= 3) large
   `MTLBuffer`s, gated by a semaphore signalled from the GPU completion handler,
   so the CPU never writes a slice the GPU is still reading — no CPU↔GPU stalls.
4. **IOSurface-backed target → zero-copy encode.** The colour texture is wrapped
   around an `IOSurface`; `cm_surface_get_iosurface` returns the `IOSurfaceRef`
   so the caller feeds it straight to VideoToolbox via
   `CVPixelBufferCreateWithIOSurface`. No `glReadPixels`, no `getBytes`, no
   staging copy.
5. **Zero per-draw heap allocation.** Per-frame geometry is bump-allocated from
   the ring (`cm_frame_alloc_verts` / `cm_frame_alloc_uniforms`); recorded-path
   arrays grow amortized and are **reset, not freed**, between frames; the
   gradient LUT and pipeline states are cached. No `malloc` / `[NSObject alloc]`
   on the hot path.
6. **Group draws by pipeline state.** Encoding consults
   `ctx->last_pipeline_group` to coalesce consecutive draws that share a pipeline
   (e.g. runs of solid fills), minimizing
   `setRenderPipelineState`/`setDepthStencilState` churn inside the single
   encoder.

---

## Build & run

**Requirements:** a macOS host with Xcode / the Command Line Tools (`clang`,
`swift`) and the Metal toolchain (`xcrun -sdk macosx -f metal` must resolve).
Building needs no GPU; *rendering the demo* needs a usable Metal device (any
recent Mac).

### One command

```sh
./build.sh
```

`build.sh` runs the whole thing and is exactly what CI runs:

1. `swift build` — the canonical library build (SwiftPM).
2. `xcrun -sdk macosx metal` + `metallib` — compiles `shaders/*.metal` into
   `build/default.metallib`.
3. builds and runs the demo, rendering `build/demo.png`.

Flags: `./build.sh --no-run` (build only), `./build.sh --clean` (wipe `.build/`
and `build/` first).

### The pieces individually

```sh
swift build              # build the library via SwiftPM (the canonical path)

make                     # clang build: static lib + default.metallib + demo
make lib                 # build/libcairometal.a
make metallib            # build/default.metallib (compiled shaders)
make run                 # build + run the demo -> build/demo.png
make clean               # remove build/
```

#### Why both SwiftPM *and* a Makefile?

SwiftPM is the canonical build and how the library is consumed as a package.
But **SwiftPM has no command-line rule to compile a `.metal` source** (Metal
compilation is an Xcode-only build phase), so under `swift build` the shaders
ship as **resources** (copied, not compiled) and the runtime compiles or locates
them. The Makefile / `build.sh` path compiles the shaders ahead of time with
`xcrun metal` into a real `default.metallib`, and the demo finds it via the
`CM_METALLIB` environment variable (`make run` sets it to the absolute path).
The source/shader inventory is kept in lock-step across `Package.swift` and the
`Makefile`.

#### How the Metal library is found at runtime

`cm_device.m` (`cm_load_library`) tries, in order:

1. `$CM_METALLIB` — absolute path to a prebuilt `default.metallib` (the
   `make run` / `build.sh` path).
2. The app's `default.metallib` in the main bundle — when consumed in an
   Xcode/iOS app, add `shaders/fill.metal` to the app target so Xcode's Metal
   build phase produces it.
3. A self-contained fallback: compile the raw `shaders/fill.metal` at runtime
   from the SwiftPM resource bundle.

### The demo

The demo ([`examples/demo.m`](examples/demo.m)) drives the **public C API** to
render three shapes into an IOSurface-backed ARGB32 surface and writes a PNG:

1. a filled cubic-Bézier **donut** (outer ring CCW + inner ring CW → a hole
   under NONZERO winding),
2. a **linear-gradient** filled disc (two colour stops),
3. a **round-join / round-cap stroke** (zig-zag plus a trailing cubic).

A successful run prints:

```
demo: wrote demo.png (800x600): donut + gradient + round-join stroke
```

and `build/demo.png` shows all three shapes cleanly anti-aliased — which
exercises path recording, adaptive flattening, both fill rules, the gradient
LUT, CPU stroke expansion, the stencil-then-cover pipeline, MSAA resolve, and
the IOSurface map-back end to end.

---

## Consuming the library

As a SwiftPM dependency (Objective-C/C target named `CairoMetal`, importable
from Swift, Objective-C, or C):

```swift
// Package.swift
.package(path: "../cairo(metal)"),    // or a git URL once split into its own repo
// ...
.target(name: "YourApp", dependencies: ["CairoMetal"]),
```

```c
#include "cairo_metal.h"

cm_surface_t *s   = cm_image_surface_create_argb32(CM_FORMAT_ARGB32, w, h);
cm_context_t *ctx = cm_context_create(s);

cm_matrix_t m = { pw/fw, 0, 0, -(ph/fh), (pw/2)-fcx*(pw/fw), (ph/2)+fcy*(ph/fh) };
cm_set_matrix(ctx, &m);

cm_new_path(ctx);
cm_move_to(ctx, x0, y0);
cm_curve_to(ctx, c1x, c1y, c2x, c2y, x1, y1);
cm_close_path(ctx);
cm_set_source_rgba(ctx, r, g, b, a);   /* BGRA order if mirroring manim's swap */
cm_fill_preserve(ctx);
cm_stroke_preserve(ctx);

cm_surface_flush(s);
void *iosurf = cm_surface_get_iosurface(s);   /* zero-copy → VideoToolbox */
```

When embedding in an iOS/macOS **app target**, add `shaders/fill.metal` to that
target so Xcode compiles it into the app's `default.metallib` (runtime-location
option 2 above).

---

## manim integration plan

The goal: `camera.py` keeps its logic; only the cairo handle is swapped for a
CairoMetal one. Two tiers (see [DESIGN.md §6](DESIGN.md) for the full detail):

### 1. Python shim (a `cairo_metal` ext module) — *not yet built*

A small CPython extension exposes objects that **quack like pycairo**
(`Context`, `ImageSurface`, `LinearGradient`, `Matrix`, and the `FORMAT_ARGB32`
/ `LINE_JOIN_*` / `LINE_CAP_*` constants) and forward to the `cm_*` C API.
Because the enums are numerically identical to cairo's, manim's `LINE_JOIN_MAP`
/ `CAP_STYLE_MAP` transfer unchanged. `get_cairo_context` changes only at the
surface line:

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
`set_cairo_context_color`, `apply_fill`, `apply_stroke` call the same method
names and work unchanged.

### 2. Zero-copy to VideoToolbox — *not yet wired*

Instead of pushing `pixel_array` bytes to ffmpeg / the encoder:

```
cm_surface_flush(surface)                      # resolve MSAA, sync IOSurface
ios = cm_surface_get_iosurface(surface)        # IOSurfaceRef (no copy)
CVPixelBufferCreateWithIOSurface(... ios ...)  # wrap, still no copy
VTCompressionSessionEncodeFrame(...)           # h264_videotoolbox encodes it
```

The IOSurface the GPU rendered into is the exact memory the H.264 encoder
samples — no readback, no staging texture. This is the entire reason the target
is IOSurface-backed rather than a plain `MTLTexture` or CPU buffer.

---

## Current status

Honest state (see [STATUS.md](STATUS.md) for the running detail):

**Working today**

- ✅ `swift build` (SwiftPM) compiles the library cleanly.
- ✅ The clang/Make path (`make`, `build.sh`) compiles the lib, compiles both
  shaders into `default.metallib`, and links the demo.
- ✅ `make run` renders `build/demo.png` correctly on a Metal device: donut
  (hole via winding), linear gradient, round-join/round-cap stroke — all
  anti-aliased via MSAA.
- ✅ The full public C API ([`include/cairo_metal.h`](include/cairo_metal.h)) is
  implemented over the stencil-then-cover pipeline with all the optimizations
  above present in the device backbone.

**Not done yet**

- ⛔ **manim Python shim** (the `cairo_metal` ext module) — designed, not built.
- ⛔ **VideoToolbox wiring** — `cm_surface_get_iosurface` exists; the
  `CVPixelBuffer` + `VTCompressionSession` glue lives in the consumer and is not
  written here.
- ⛔ **Test suite** — `tests/` is a placeholder; correctness is currently
  asserted by the single visual demo. Fill rules, holes, stroke joins/caps, and
  gradients each deserve a golden-image test.
- ⚠️ **On-device (iOS arm64) validation** — the package targets iOS 17 and
  builds for it, but the rendering path has been exercised on macOS (Apple
  silicon), not yet on an iOS device.

> **Note:** earlier revisions of `STATUS.md` described a non-building,
> name-diverged scaffold. That has since been reconciled — the module names,
> `Package.swift`, and the `Makefile` now match the files on disk, and the
> backbone (`cm_device.m`, `cm_matrix.c`) is implemented. This README and the
> current `STATUS.md` reflect the reconciled, building state.

---

## Repository layout

```
cairo(metal)/
├── README.md                  this file
├── DESIGN.md                  full architecture + manim-integration design
├── STATUS.md                  honest running status
├── Package.swift              SwiftPM manifest (target: CairoMetal)
├── Makefile                   clang/metal fallback build + demo
├── build.sh                   one-shot: swift build + shaders + run demo
├── include/
│   └── cairo_metal.h          PUBLIC C API (the cairo subset)
├── src/
│   ├── cm_internal.h          INTERNAL contract: structs + module fn names
│   ├── cairo_metal.m          public glue + context state machine + batching
│   ├── cm_device.m            MTLDevice/queue, persistent states, ring+semaphore
│   ├── cm_surface.m           IOSurface-backed target, MSAA, flush/resolve/map
│   ├── cm_path.m              record / adaptive-flatten / tessellate fans
│   ├── cm_fill.m              stencil-then-cover encode
│   ├── cm_stroke.m            stroke expansion -> fillable polygon
│   ├── cm_paint.m             solid + linear gradient, 1D LUT bake
│   └── cm_matrix.c            affine math helpers (pure C)
├── shaders/
│   └── fill.metal             vertex + stencil/cover-solid/cover-linear shaders
├── examples/
│   └── demo.m                 standalone smoke test (renders demo.png)
├── tests/                     (placeholder — golden-image tests to come)
└── .github/workflows/build.yml  CI: build on a macOS runner + render the demo
```

> The folder name is `cairo(metal)` (with parentheses), but a Swift package /
> target identifier may not contain parentheses, so the package and its single
> target are named **`CairoMetal`**. `build.sh` and the CI workflow never rely on
> a relative path containing the parentheses.

---

## Further reading

- [DESIGN.md](DESIGN.md) — the full design: why, the cairo subset, the
  stencil-then-cover pipeline, every optimization, the module map, and the
  manim integration in detail.
- [STATUS.md](STATUS.md) — current build/render status and the remaining
  punch-list.
- [`include/cairo_metal.h`](include/cairo_metal.h) — the public API, fully
  documented inline.
- [`src/cm_internal.h`](src/cm_internal.h) — the internal contract between
  modules.
