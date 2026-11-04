//
// fill.metal  --  CairoMetal stencil-then-cover FILL shaders
// ============================================================================
//
// This file contains the Metal shader functions used by the stencil-then-cover
// fill (and, because strokes are expanded to fillable polygons CPU-side, by
// strokes too).  The render-pipeline-state and depth-stencil-state objects that
// *use* these functions are built ONCE in cm_device.m and fetched O(1) by
// cm_fill.m via cm_device_pipeline()/cm_device_depthstencil(); this file only
// declares the programmable stages.
//
// It is the ONE shipping shader source: the runtime loader (cm_device.m,
// cm_load_library) expects every cm_* entry point in a single default.metallib,
// the Makefile lists exactly one METAL_SRCS (shaders/fill.metal) and
// Package.swift ships exactly one .copy("shaders/fill.metal") resource.  So the
// full-contract cover variants, the programmable-blend fragments, and the
// clip-aware variants ALL live here, appended after the shipping four — a
// separate .metal would force Makefile/Package.swift/metallib-link changes for
// zero benefit.
//
// ----------------------------------------------------------------------------
// SHADER-NAME CONTRACT  (cm_device.m must reference these exact names)
// ----------------------------------------------------------------------------
//   cm_pipe_id                  vertex function        fragment function
//   --------------------------  ---------------------  -----------------------
//   CM_PIPE_STENCIL_NONZERO     cm_vs_stencil          cm_fs_stencil
//   CM_PIPE_STENCIL_EVENODD     cm_vs_stencil          cm_fs_stencil
//   CM_PIPE_COVER_SOLID         cm_vs_cover            cm_fs_cover_solid
//   CM_PIPE_COVER_LINEAR        cm_vs_cover            cm_fs_cover_linear
//   CM_PIPE_COVER_RADIAL        cm_vs_cover            cm_fs_cover_radial
//   CM_PIPE_COVER_SURFACE       cm_vs_cover            cm_fs_cover_surface
//   CM_PIPE_COVER_GOURAUD       cm_vs_cover_color      cm_fs_cover_gouraud
//   CM_PIPE_COVER_MASK          cm_vs_cover            cm_fs_mask
//   CM_PIPE_COVER_SOLID_A8      cm_vs_cover            cm_fs_cover_solid (R8 tgt)
//
// The NONZERO vs EVENODD difference is ENTIRELY in the MTLDepthStencilState
// (incr/decr-wrap two-sided vs invert) — the programmable stages are identical,
// so both stencil pipelines share cm_vs_stencil + cm_fs_stencil.  Likewise the
// "test stencil then zero it" of the cover pass lives in the cover
// MTLDepthStencilState, not here.
//
// CLIP-AWARE VARIANTS.  cm_device_cover_pipeline(dev, op, aa_none, clip, kind)
// selects a *_clip fragment when clip==true; that variant samples the A8 clip
// coverage plane and multiplies it into the premultiplied output.  The base
// (non-clip) variant is identical minus the clip multiply, so unclipped draws
// pay nothing.  The clip texture/sampler binding indices match cm_clip.m
// (cm_clip_bind): texture(1) / sampler(1).
//
// PROGRAMMABLE-BLEND VARIANTS (PDF blend modes, cairo operators 14..28).  The
// separable/non-separable blend modes are NOT expressible as a fixed-function
// MTLRenderPipelineColorAttachment blend, so cm_fs_blend_* read the destination
// via [[color(0)]] framebuffer fetch and compute the Porter-Duff "B(cb,cs)"
// composite in-shader.  Operators 0..13 are fixed-function blends (the device
// bakes the blend state per operator) and need NO new fragment — but they DO
// still need the clip multiply, which the *_clip cover variants above provide.
//
// ----------------------------------------------------------------------------
// BUFFER / TEXTURE BINDING CONTRACT  (cm_fill.m / cm_compose.m bind these)
// ----------------------------------------------------------------------------
//   buffer(0)  : device const cm_vec2f*  vertices   (DEVICE-space px positions)
//                (cm_vtx_color* for the Gouraud/mesh vertex stage)
//   buffer(1)  : constant cm_uniforms&   uniforms   (per-draw)
//   texture(0) : 256x1 BGRA8 gradient LUT           (LINEAR / RADIAL covers)
//                OR the source colour texture       (SURFACE / MASK covers)
//   sampler(0) : runtime MTLSamplerState             (SURFACE / MASK covers)
//   texture(1) : A8 (R8Unorm) clip coverage plane   (*_clip variants only)
//   sampler(1) : clip-mask sampler                   (*_clip variants only)
//
// The gradient-LUT sampler is a `constexpr sampler` declared in this file
// (linear / clamp to edge), so the LINEAR/RADIAL covers bind NO MTLSamplerState
// at sampler(0).  The SURFACE/MASK covers DO bind a runtime sampler at
// sampler(0) (cm_device_sampler, keyed by filter+extend).
//
// Vertices are indexed directly by vertex_id (NO MTLVertexDescriptor / stage_in)
// so cm_device.m needs no vertex layout — keeping the only cross-file coupling
// the function names above.  These binding indices are mirrored as #defines in
// cm_fill.m / cm_compose.m (CM_BUF_VERTS / CM_BUF_UNIFORMS / CM_TEX_GRAD_LUT /
// CM_TEX_SOURCE / CM_SAMPLER_SOURCE) and in cm_clip.m (CM_CLIP_BIND_*_INDEX).
//
// ----------------------------------------------------------------------------
// COORDINATE / PIXEL CONTRACT
// ----------------------------------------------------------------------------
// * The CTM is applied on the CPU at flatten time, so vertex positions arrive
//   already in DEVICE pixels.  The vertex stage only maps device px -> Metal
//   clip space via the `to_clip` uniform (which already encodes the y-flip:
//   to_clip = (2/W, -2/H, -1, +1)).  ctm_row0/row1 are carried for completeness
//   but the shipping path does not re-transform on the GPU.
// * Colour is premultiplied on OUTPUT here (rgb *= a) to match cairo's
//   premultiplied ARGB32 surface; cm_device.m configures the colour attachment
//   for PREMULTIPLIED OVER blending (srcRGB=One, dstRGB=OneMinusSrcAlpha,
//   srcA=One, dstA=OneMinusSrcAlpha).  EXCEPTION: surface texels are ALREADY
//   premultiplied (cairo ARGB32 source), so cm_fs_cover_surface does NOT
//   premultiply again.
// * No colour byte re-swap: manim pre-swaps to B,G,R,A, the LUT is baked B,G,R,A,
//   and the BGRA8Unorm target has the matching layout, so components pass
//   through unchanged.  NOTE the fragments themselves work in LOGICAL RGBA:
//   cm_paint_solid loads float4(solid.r, solid.g, solid.b, a) and Metal swizzles
//   .r -> the texture's R channel on write (and un-swizzles the [[color(0)]]
//   framebuffer read), so a float4's .r is logical R regardless of the BGRA byte
//   order.  The programmable-blend fragments operate per-channel and are
//   channel-order-agnostic for the separable modes; the HSL (non-separable) modes
//   compute luma with the spec's 0.30/0.59/0.11 weights applied in NATURAL (R,G,B)
//   order (cm_lum) — matching cairo's own HSL math byte-for-byte.
// * Anti-aliasing is 4x MSAA on the colour+stencil attachments (configured in
//   the pipeline sampleCount + the render pass), so these stages are written
//   per-fragment and need no analytic coverage.
//
// MUST stay binary-compatible with the C structs in src/cm_internal.h:
//   cm_vec2f  { float x, y; }
//   cm_rgba   { float r, g, b, a; }
//   cm_vtx_color { float x, y; cm_rgba color; }
//   cm_uniforms { float ctm_row0[4]; float ctm_row1[4]; float to_clip[4];
//                 int paint_kind; float grad_axis[4]; cm_rgba solid;
//                 float pat_inv_row0[4]; float pat_inv_row1[4];
//                 int op; float global_alpha; float mask_axis[4]; int mask_kind; }
// ============================================================================

#include <metal_stdlib>
using namespace metal;

// paint_kind values (mirror cm_paint_kind in cm_internal.h): SOLID=0, LINEAR=1,
// RADIAL=2, SURFACE=3, MESH=4.  The cover fragments do NOT branch on paint_kind
// — the per-kind choice is made by selecting the fragment via the pipeline state
// in cm_fill.m / cm_compose.m — so these values are documented, not declared.
//
// cm_operator_t values (mirror cairo_operator_t): the programmable-blend
// fragments DO branch on `op` (operators 14..28).  They are declared as an enum
// below so the dispatch reads clearly; the integer values are identical to the
// C cm_operator_t / cairo_operator_t.

// ---------------------------------------------------------------------------
// Shared POD types — MUST match cm_internal.h field-for-field.
// ---------------------------------------------------------------------------

/** Device-space (post-CTM) 2D position. Mirrors cm_vec2f. */
struct cm_vec2f {
    float x;
    float y;
};

/** RGBA float colour, stored NON-premultiplied. Mirrors cm_rgba. */
struct cm_rgba {
    float r;
    float g;
    float b;
    float a;
};

/** Per-vertex coloured position for the Gouraud (mesh) cover. Mirrors
 *  cm_vtx_color { float x, y; cm_rgba color; }. */
struct cm_vtx_color {
    float   x;
    float   y;
    cm_rgba color;
};

/**
 * Per-draw uniforms. Mirrors cm_uniforms in cm_internal.h.
 * Arrays are float[4] (not packed_float4) to match the C layout exactly:
 *   ctm_row0 = (xx, xy, x0, _)   ctm_row1 = (yx, yy, y0, _)
 *   to_clip  = (sx, sy, tx, ty)  ->  clip.xy = pos.xy * (sx,sy) + (tx,ty)
 *   grad_axis= (ax, ay, bx, by)  device-space gradient endpoints A->B (LINEAR)
 *            = (cx1, cy1, r1, _)  device-space OUTER circle           (RADIAL)
 *   pat_inv_row0/1 = device->pattern affine inverse rows (SURFACE/MASK; carried
 *                    for LINEAR/RADIAL/MESH too for a consistent definition)
 *   op           = cm_operator_t (programmable-blend frags dispatch on this)
 *   global_alpha = paint_with_alpha / group opacity
 *   mask_axis    = mask gradient axis (device space) when masking; ALSO the
 *                  RADIAL device-space INNER circle (cx0,cy0,r0,_) once
 *                  cm_paint.m packs it — see the cross-module seam note on
 *                  cm_fs_cover_radial below.
 *   mask_kind    = cm_paint_kind of the mask pattern
 */
struct cm_uniforms {
    float   ctm_row0[4];
    float   ctm_row1[4];
    float   to_clip[4];
    int     paint_kind;
    float   grad_axis[4];
    cm_rgba solid;
    // --- appended (full contract); MUST stay in LOCK-STEP with the C struct +
    //     the _Static_asserts in src/cm_paint.m (solid @68, pat rows @84,
    //     op @116, global_alpha @120, mask_axis @124, mask_kind @140). ---
    float   pat_inv_row0[4];   // inverse pattern->device rows (surface/radial)
    float   pat_inv_row1[4];
    int     op;                // cm_operator_t for programmable-blend frags
    float   global_alpha;      // paint_with_alpha / group opacity
    float   mask_axis[4];      // mask gradient axis (device space)
    int     mask_kind;         // cm_paint_kind of the mask pattern
};

// cm_operator_t mirror (cairo_operator_t; same integer values).  The separable
// blend modes are 14..24; the non-separable (HSL) modes are 25..28.  Only these
// 14..28 reach the programmable-blend fragments; 0..13 are fixed-function.
enum cm_operator {
    CM_OP_CLEAR = 0, CM_OP_SOURCE, CM_OP_OVER, CM_OP_IN, CM_OP_OUT, CM_OP_ATOP,
    CM_OP_DEST, CM_OP_DEST_OVER, CM_OP_DEST_IN, CM_OP_DEST_OUT, CM_OP_DEST_ATOP,
    CM_OP_XOR, CM_OP_ADD, CM_OP_SATURATE,
    CM_OP_MULTIPLY, CM_OP_SCREEN, CM_OP_OVERLAY, CM_OP_DARKEN, CM_OP_LIGHTEN,
    CM_OP_COLOR_DODGE, CM_OP_COLOR_BURN, CM_OP_HARD_LIGHT, CM_OP_SOFT_LIGHT,
    CM_OP_DIFFERENCE, CM_OP_EXCLUSION,
    CM_OP_HSL_HUE, CM_OP_HSL_SATURATION, CM_OP_HSL_COLOR, CM_OP_HSL_LUMINOSITY
};

// cm_extend_t mirror (cairo_extend_t): NONE=0, REPEAT=1, REFLECT=2, PAD=3.
// The gradient covers fold the raw axis parameter t into [0,1] per the extend
// mode; the mode is read from grad_axis[3] for RADIAL (free slot) and is PAD for
// LINEAR (the shipping clamp).  See cm_extend_fold().
enum cm_extend {
    CM_EXTEND_NONE = 0, CM_EXTEND_REPEAT, CM_EXTEND_REFLECT, CM_EXTEND_PAD
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Map a device-pixel position to Metal clip space using to_clip (y already
 *  flipped via a negative sy). z=0, w=1 for 2D. */
static inline float4 cm_to_clip(float2 device_px, constant cm_uniforms &u) {
    float2 s = float2(u.to_clip[0], u.to_clip[1]);   // (sx, sy)
    float2 t = float2(u.to_clip[2], u.to_clip[3]);   // (tx, ty)
    return float4(device_px * s + t, 0.0, 1.0);
}

/** The surface's inverse pixel size (1/W, 1/H), recovered from to_clip without a
 *  new uniform: to_clip[0] = 2/W and to_clip[1] = -2/H (y flipped), so
 *  1/W = to_clip[0]/2 and 1/H = -to_clip[1]/2.  Used to turn a device-pixel
 *  position into the [0,1] UV the A8 clip plane is sampled at (the clip mask is a
 *  full-surface texture rendered in device space — see cm_clip.m). */
static inline float2 cm_dev_to_clip_uv(float2 device_px, constant cm_uniforms &u) {
    float inv_w = u.to_clip[0] * 0.5;
    float inv_h = -u.to_clip[1] * 0.5;
    return float2(device_px.x * inv_w, device_px.y * inv_h);
}

/** Map a device-space position back into pattern space via the inverse
 *  pattern->device rows (pat_inv_row0/1, the 2x3 affine inverse). */
static inline float2 cm_to_pattern(float2 dev, constant cm_uniforms &u) {
    float2 r0 = float2(u.pat_inv_row0[0], u.pat_inv_row0[1]);
    float2 r1 = float2(u.pat_inv_row1[0], u.pat_inv_row1[1]);
    float  t0 = u.pat_inv_row0[2];
    float  t1 = u.pat_inv_row1[2];
    return float2(dot(r0, dev) + t0, dot(r1, dev) + t1);
}

/** Fold a raw gradient parameter t (any real) into the [0,1] LUT domain per the
 *  cairo extend mode.  Mirrors cm_extend_fold_t() in cm_paint.m exactly so the
 *  CPU bake (PAD ends) and the GPU sample agree:
 *    PAD/NONE : clamp(t,0,1)   (clamp-to-edge LUT sampler already gives the ends)
 *    REPEAT   : t - floor(t)   (saw wave)
 *    REFLECT  : triangle wave, period 2.
 *  NONE folds to PAD here (the transparent border NONE paints needs an alpha=0
 *  ring the clamp-only LUT sampler cannot express; PAD is the conservative
 *  shipping behaviour, matching cm_paint.m's note). */
static inline float cm_extend_fold(float t, int extend) {
    switch (extend) {
        case CM_EXTEND_REPEAT:
            return t - floor(t);
        case CM_EXTEND_REFLECT: {
            float m = fmod(fabs(t), 2.0);          // [0,2)
            return (m > 1.0) ? (2.0 - m) : m;
        }
        case CM_EXTEND_NONE:
        case CM_EXTEND_PAD:
        default:
            return clamp(t, 0.0, 1.0);
    }
}

/** Sample the A8 clip coverage plane (R8Unorm) at the fragment's device pixel
 *  and return coverage in [0,1].  The clip-aware cover variants multiply the
 *  PREMULTIPLIED fragment output by this so the clip both darkens colour and
 *  cuts alpha (premultiplied-correct).  The clip plane is a full-surface texture
 *  rendered in device space (cm_clip.m), so the UV is device_px*(1/W,1/H). */
static inline float cm_clip_coverage(float2 dev, constant cm_uniforms &u,
                                     texture2d<float> clipmask,
                                     sampler clipsamp) {
    float2 uv = cm_dev_to_clip_uv(dev, u);
    return clipmask.sample(clipsamp, uv).r;
}

// The constexpr LUT sampler shared by the gradient covers: linear filter, clamp
// to edge (so the [0,1] LUT ends reproduce cairo EXTEND_PAD).  REPEAT/REFLECT
// are a fold of the SAMPLE coordinate (cm_extend_fold), not of this sampler.
constant sampler cm_lut_sampler(filter::linear,
                                mip_filter::none,
                                address::clamp_to_edge);

// ===========================================================================
// PASS 1 — STENCIL  (write winding/parity into stencil, NO colour)
// ===========================================================================
//
// Used by CM_PIPE_STENCIL_NONZERO and CM_PIPE_STENCIL_EVENODD.  The pipeline's
// colour write mask is set to none in cm_device.m, so the fragment output is
// discarded; only the stencil op (incr/decr-wrap or invert) takes effect.
// Triangle fans for each contour are drawn here; overlap + the stencil op yield
// correct coverage for holes and self-intersection without CPU triangulation.

vertex float4
cm_vs_stencil(uint                       vid      [[vertex_id]],
              device const cm_vec2f     *verts    [[buffer(0)]],
              constant cm_uniforms      &u        [[buffer(1)]])
{
    cm_vec2f p = verts[vid];
    return cm_to_clip(float2(p.x, p.y), u);
}

// Colour is masked off by the pipeline; emit a trivial value.  Declared with
// [[color(0)]] so the function is a valid fragment stage for an attachment that
// exists (with a zero write-mask) in the stencil pipeline.
fragment float4
cm_fs_stencil(void)
{
    return float4(0.0);
}

// ===========================================================================
// FRAME LOAD  (start a frame from the surface's own pixels)
// ===========================================================================
//
// The MSAA colour attachment is memoryless, so a frame cannot LOAD the resolve
// texture; the first draw of a frame that must keep the surface's pixels is
// this fullscreen triangle instead, copying each pixel into all of its samples
// (cm_frame_begin, cm_device.m).  The source is a second texture object on the
// same storage; each fragment reads only its own pixel.

struct LoadInOut { float4 position [[position]]; };

vertex LoadInOut
cm_vs_fullscreen(uint vid [[vertex_id]])
{
    float2 p = float2((vid << 1) & 2, vid & 2);          // (0,0) (2,0) (0,2)
    LoadInOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

fragment float4
cm_fs_load(LoadInOut in [[stage_in]],
           texture2d<float, access::read> src [[texture(0)]])
{
    return src.read(uint2(in.position.xy));
}

// ===========================================================================
// PASS 2 — COVER  (test stencil, write paint; stencil self-resets to 0)
// ===========================================================================
//
// Draw the path's device-space bounding quad.  The cover MTLDepthStencilState
// tests the stencil (!=0 for nonzero, &1 for even-odd via readMask) and zeroes
// the touched samples in the SAME op, so no separate per-path stencil clear is
// needed when many paths batch into one command buffer.  MSAA resolves the
// antialiased edge from the per-sample stencil coverage.

struct CoverInOut {
    float4 position [[position]];   // clip space
    float2 dev;                     // device-space px, for gradient projection
};

vertex CoverInOut
cm_vs_cover(uint                    vid    [[vertex_id]],
            device const cm_vec2f  *verts  [[buffer(0)]],
            constant cm_uniforms   &u      [[buffer(1)]])
{
    cm_vec2f p = verts[vid];
    CoverInOut out;
    out.dev      = float2(p.x, p.y);
    out.position = cm_to_clip(out.dev, u);
    return out;
}

// ---------------------------------------------------------------------------
// Paint evaluators (return PREMULTIPLIED colour) shared by the base covers, the
// clip-aware covers, and the programmable-blend covers.  Factoring the paint out
// of the entry points keeps the solid/linear/radial/surface maths in ONE place
// so the *_clip and cm_fs_blend_* variants composite the exact same source.
// ---------------------------------------------------------------------------

// Solid: the uniform colour, premultiplied (components already B,G,R,A).
static inline float4 cm_paint_solid(constant cm_uniforms &u) {
    float4 c = float4(u.solid.r, u.solid.g, u.solid.b, u.solid.a);
    c.rgb *= c.a;
    return c;
}

// Linear gradient: project the fragment onto the device-space axis A->B and
// sample the baked 256x1 BGRA8 LUT, then premultiply.  Degenerate axis (A==B)
// paints the last stop everywhere (t=1 at the clamped LUT right edge), matching
// cairo.  PAD is the shipping clamp; the LUT clamp-to-edge sampler realises it.
static inline float4 cm_paint_linear(float2 dev, constant cm_uniforms &u,
                                     texture2d<float> lut) {
    float2 A = float2(u.grad_axis[0], u.grad_axis[1]);
    float2 B = float2(u.grad_axis[2], u.grad_axis[3]);
    float2 ab = B - A;
    float  denom = dot(ab, ab);
    float  t = (denom > 0.0) ? clamp(dot(dev - A, ab) / denom, 0.0, 1.0) : 1.0;
    float4 c = lut.sample(cm_lut_sampler, float2(t, 0.5));
    c.rgb *= c.a;
    return c;
}

// Radial gradient: the cairo two-circle cone.  See cm_fs_cover_radial below for
// the full derivation + the cross-module seam (inner circle in mask_axis).
//
// Solve for the largest s in [0,1] with |p - c(s)| = r(s), where
//   c(s) = c0 + s*(c1-c0),  r(s) = r0 + s*(r1-r0),  r(s) >= 0.
// With pd = p - c0, dc = c1-c0, dr = r1-r0 this is the quadratic
//   A s^2 - 2 B s + C = 0,  A = dot(dc,dc) - dr^2,
//                           B = dot(pd,dc) + r0*dr,
//                           C = dot(pd,pd) - r0^2.
// We take the larger valid root, fold it through the extend mode, and sample the
// LUT (same 256x1 BGRA8 LUT as linear; the bake is gradient-kind-agnostic).
static inline float4 cm_paint_radial(float2 dev, constant cm_uniforms &u,
                                     texture2d<float> lut) {
    float2 c1 = float2(u.grad_axis[0], u.grad_axis[1]);   // device outer centre
    float  r1 = u.grad_axis[2];                            // device outer radius
    int    extend = int(u.grad_axis[3] + 0.5);            // packed extend (0 dflt)

    // Inner circle (device space) from mask_axis.  cm_paint.m currently zeroes
    // mask_axis for a radial paint; an all-zero inner circle is treated as
    // CONCENTRIC + point (c0=c1, r0=0), which reduces the solve EXACTLY to the
    // shipping single-circle projection length(p-c1)/r1.  When cm_paint.m packs a
    // real device-space inner circle into mask_axis, the full two-circle cone
    // lights up with no shader change (see the seam note on cm_fs_cover_radial).
    float2 c0 = float2(u.mask_axis[0], u.mask_axis[1]);
    float  r0 = u.mask_axis[2];
    bool   inner_unset = (c0.x == 0.0 && c0.y == 0.0 && r0 == 0.0);
    if (inner_unset) { c0 = c1; r0 = 0.0; }

    float2 pd = dev - c0;
    float2 dc = c1 - c0;
    float  dr = r1 - r0;

    float A = dot(dc, dc) - dr * dr;
    float B = dot(pd, dc) + r0 * dr;
    float C = dot(pd, pd) - r0 * r0;

    float s;
    bool  have = false;
    const float EPS = 1e-7;
    if (fabs(A) < EPS) {
        // Degenerate quadratic (concentric or |dc|==|dr|): linear B s == C/2.
        // Concentric point source (dc==0,r0==0) -> 2*B = 0 handled below.
        if (fabs(B) > EPS) {
            s = C / (2.0 * B);
            have = (r0 + s * dr) >= 0.0;
        } else if (fabs(C) < EPS) {
            // p sits on the (degenerate) source: paint the first stop.
            s = 0.0; have = true;
        }
    } else {
        // Largest root with non-negative radius.  disc = B^2 - A*C.
        float disc = B * B - A * C;
        if (disc >= 0.0) {
            float sq = sqrt(disc);
            float inv = 1.0 / A;
            float s_hi = (B + sq) * inv;
            float s_lo = (B - sq) * inv;
            if (s_hi < s_lo) { float t = s_hi; s_hi = s_lo; s_lo = t; }
            // Prefer the larger root whose interpolated radius is >= 0.
            if ((r0 + s_hi * dr) >= 0.0)      { s = s_hi; have = true; }
            else if ((r0 + s_lo * dr) >= 0.0) { s = s_lo; have = true; }
        }
    }

    if (!have) {
        // No circle of the family passes through p -> outside the gradient cone.
        // cairo paints nothing there; premultiplied transparent black is the
        // identity for OVER and never tints the framebuffer.
        return float4(0.0);
    }

    float t = cm_extend_fold(s, extend);
    float4 c = lut.sample(cm_lut_sampler, float2(t, 0.5));
    c.rgb *= c.a;
    return c;
}

// Surface texture: sample the source via the runtime sampler.  Texels are
// ALREADY premultiplied (cairo ARGB32), so we do NOT premultiply again.  The
// fragment is mapped device px -> pattern/texel space via the inverse rows, then
// normalised to [0,1] UV by the texture size (the runtime sampler's address mode
// — set by cm_device_sampler from the pattern extend — realises REPEAT/REFLECT/
// PAD/border for surface patterns).
static inline float4 cm_paint_surface(float2 dev, constant cm_uniforms &u,
                                      texture2d<float> src, sampler samp) {
    float2 pat = cm_to_pattern(dev, u);
    float2 uv = pat / float2(max(1.0, float(src.get_width())),
                             max(1.0, float(src.get_height())));
    return src.sample(samp, uv);   // already premultiplied
}

// ---- base cover entry points (no clip) -------------------------------------

fragment float4
cm_fs_cover_solid(CoverInOut            in [[stage_in]],
                  constant cm_uniforms &u  [[buffer(1)]])
{
    return cm_paint_solid(u);
}

// A8 (R8Unorm) target solid cover.  FORMAT_A8 is an ALPHA/COVERAGE-only surface:
// it stores ONLY the source's alpha, INDEPENDENT of its RGB (real cairo: an
// opaque source -> 0xFF regardless of colour).  The R8 attachment takes the
// fragment's .r component, so we must place the COVERAGE alpha there -- NOT the
// premultiplied blue/red of cm_paint_solid (which would store luminance and make
// opaque black/green read 0).  u.solid.a already folds paint_with_alpha + any
// solid-mask weight (cm_apply_alpha_to_source).  We replicate the alpha into all
// four channels so the premultiplied OVER blend (which weights the destination by
// 1-src.a) composites coverage correctly: dst = a + dst*(1-a).
fragment float4
cm_fs_cover_solid_a8(CoverInOut            in [[stage_in]],
                     constant cm_uniforms &u  [[buffer(1)]])
{
    float a = clamp(u.solid.a, 0.0, 1.0);
    return float4(a, a, a, a);
}

// global_alpha (paint_with_alpha / group opacity) is applied HERE for the
// LINEAR/RADIAL/SURFACE/MESH covers because — unlike a SOLID source, whose alpha
// the CPU folds into solid.a (cm_apply_alpha_to_source) — these sources carry
// their alpha in the LUT/texture/per-vertex colour, which the CPU does not touch.
// Scaling the PREMULTIPLIED evaluator output by the scalar global_alpha is
// premultiplied-correct (rgb and a scale together).  global_alpha defaults to 1.0
// so a plain paint() is unchanged.  The SOLID cover deliberately does NOT do this
// (its alpha is already folded) to avoid double-applying.

fragment float4
cm_fs_cover_linear(CoverInOut             in       [[stage_in]],
                   constant cm_uniforms  &u        [[buffer(1)]],
                   texture2d<float>       lut      [[texture(0)]])
{
    return cm_paint_linear(in.dev, u, lut) * u.global_alpha;
}

fragment float4
cm_fs_cover_radial(CoverInOut             in   [[stage_in]],
                   constant cm_uniforms  &u    [[buffer(1)]],
                   texture2d<float>       lut  [[texture(0)]])
{
    return cm_paint_radial(in.dev, u, lut) * u.global_alpha;
}

fragment float4
cm_fs_cover_surface(CoverInOut             in   [[stage_in]],
                    constant cm_uniforms  &u    [[buffer(1)]],
                    texture2d<float>       src  [[texture(0)]],
                    sampler                samp [[sampler(0)]])
{
    return cm_paint_surface(in.dev, u, src, samp) * u.global_alpha;
}

// ---- analytic-coverage covers (no stencil pass, no MSAA edges) -------------
//
// cairo's image backend antialiases by AREA: each pixel's alpha is how much of
// it the path covers, measured on a grid far finer than 4x MSAA (whose edges
// can only be 0, 1/4, 1/2, 3/4 or 1 -- up to ~60 levels off cairo on every
// edge pixel).  These covers compute that coverage per pixel from the path's
// own edges: the pixel is cut into 15 sub-rows, each sampled at its centre;
// on each, the edge crossings give the exact covered length inside the pixel
// under the fill rule.  The CPU bins the edges by pixel row (cm_fill.m) so a
// pixel walks only the few edges that cross its row.  Measured against cairo
// 1.18 on random polygons: edge pixels mean |diff| 1.4 levels (MSAA: 13.2).
//
// The cover quad spans whole pixels, so every sample of a pixel takes the
// same value and the frame's MSAA resolve passes it through unchanged.

// An edge as the row lists hold it, one float4: (x at the top, the two ends'
// y, dx/dy).  The y order carries the winding: (top, bottom) is +1, (bottom,
// top) is -1.  A horizontal edge (top == bottom) is kept only so a pixel it
// passes through is not taken for a solid one; its .w is its width, and it
// never winds.  Each row's edges are stored together (cm_fill.m), so a pixel
// reads them with one load each.
static inline float cm_acov_top(float4 a)  { return min(a.y, a.z); }
static inline float cm_acov_bot(float4 a)  { return max(a.y, a.z); }
static inline int   cm_acov_dir(float4 a)  { return a.y < a.z ? 1 : -1; }

struct cm_acov_params {      // mirrors cm_acov_params in cm_fill.m (192 bytes)
    int    row0;             // first pixel row binned
    int    nrows;
    int    evenodd;          // 0 nonzero, 1 even-odd
    int    nstops;           // linear: stops below (0 = use the LUT)
    float4 solid;            // SOLID: premultiplied, rounded as cairo rounds, /255
    float  stop_x[8];        // linear: sorted offsets
    float4 stop_c[8];        // linear: colours as pixman gets them (16-bit), 0..1
};

// A linear gradient's colour at t, as pixman's gradient walker makes it: the
// two bracketing stops interpolated in float, premultiplied, each channel
// rounded to a byte.  (The 8-bit 256-texel LUT came out a level off on about
// half of a gradient's pixels.)
static inline float4 cm_acov_stops(float t, constant cm_acov_params &P)
{
    // A fixed bound (the eight stops the params hold): a data-dependent loop
    // here hung the GPU inside the coverage shader.
    int n = P.nstops;
    float4 c = P.stop_c[0];
    for (int i = 0; i < 7; ++i) {
        if (i + 1 < n && t >= P.stop_x[i]) {
            float lx = P.stop_x[i], rx = P.stop_x[i + 1];
            float f = (rx > lx) ? clamp((t - lx) / (rx - lx), 0.0, 1.0) : 1.0;
            c = mix(P.stop_c[i], P.stop_c[i + 1], f);
        }
    }
    float a = c.a * 255.0;
    return float4(floor(a * c.rgb + 0.5), floor(a + 0.5)) / 255.0;
}

#define CM_ACOV_SUB 15

static inline bool cm_acov_in(int w, int evenodd) { return evenodd ? ((w & 1) != 0) : (w != 0); }

// x of edge `a` on the sub-row at yc, relative to the pixel's left side, or a
// flag that the edge is not on that sub-row.
static inline bool cm_acov_on(float4 a, float yc) { return cm_acov_top(a) < yc && yc <= cm_acov_bot(a); }

// Area of [0,1] where the linear u(t) from u0 to u1, clamped to [0,1], is
// integrated: F is the antiderivative of clamp(u, 0, 1).
static inline float cm_acov_F(float u) { return u <= 0.0 ? 0.0 : (u >= 1.0 ? u - 0.5 : 0.5 * u * u); }

// Area of the pixel [fx, fx+1] x [row] to the right of a line crossing the row
// from xt (top) to xb (bottom).
static inline float cm_acov_aright(float xt, float xb, float fx)
{
    float u0 = fx + 1.0 - xt, u1 = fx + 1.0 - xb;
    if (fabs(u1 - u0) < 1.0e-5) return clamp(0.5 * (u0 + u1), 0.0, 1.0);
    return (cm_acov_F(u1) - cm_acov_F(u0)) / (u1 - u0);
}

// ---- the span-local measurement ---------------------------------------------
// cm_fill.m makes cairo's per-row choice (exact row or 15 sub-rows), groups a
// row's edges by SPAN -- a run of pixels some edge passes through -- and
// stores with each span the winding of everything left of it.  A pixel reads
// its span's record and walks only that span's edges.
//   rows[r]:  (first segment, segment count, 0, 0)
//   segments: one uint4 each -- (x0 | x1 << 16, first edge | edge count << 24,
//             left windings' nibbles 0-6 | a base in bits 28-30 | 0x80000000
//             for an exact row, nibbles 7-14).  Sub-row k's left winding is
//             8 * base + nibble k, both signed; an exact row's is sub-row 0's.

// Sub-row k's left winding.
static inline int cm_acov_wsub(uint4 S, int k)
{
    // Selected rather than indexed by a variable, so S stays in registers.
    uint bits = k < 7 ? (S.z >> (4 * k)) : (S.w >> (4 * (k - 7)));
    return (int(bits << 28) >> 28) + 8 * (int(S.z << 1) >> 29);
}

// A segment's edges, held in registers (a struct by value; an array
// parameter would live in memory).  Unused slots: a zero-height edge far
// above -- never active, never winds, never crosses.
template <int N> struct cm_acov_set { float4 e[N]; };

template <int N>
static inline cm_acov_set<N> cm_acov_load(device const float4 *E, uint n)
{
    cm_acov_set<N> S;
    #pragma unroll
    for (int j = 0; j < N; ++j) S.e[j] = uint(j) < n ? E[j] : float4(-1.0e9, -1.0e9, -1.0e9, 0.0);
    return S;
}

// A sampled row: per sub-row, the winding entering the pixel, each edge's
// crossing (or 2.0), an odd-even transposition sort, then the walk across
// the pixel.
template <int N>
static inline float cm_acov_subT(cm_acov_set<N> S, uint4 W, float fx, float fy, int evenodd)
{
    float total = 0.0;
    for (int k = 0; k < CM_ACOV_SUB; ++k) {
        float yc = fy + (float(k) + 0.5) / float(CM_ACOV_SUB);
        int w = cm_acov_wsub(W, k);
        float c[N]; int d[N];
        #pragma unroll
        for (int j = 0; j < N; ++j) {
            float4 a = S.e[j];
            float t = cm_acov_top(a), b = cm_acov_bot(a);
            bool act = t < yc && yc <= b;
            float x = (a.x + (yc - t) * a.w) - fx;
            int dir = cm_acov_dir(a);
            w += (act && x < 0.0) ? dir : 0;
            bool inpx = act && x >= 0.0 && x < 1.0;
            c[j] = inpx ? x : 2.0;
            d[j] = inpx ? dir : 0;
        }
        #pragma unroll
        for (int p = 0; p < N; ++p) {
            #pragma unroll
            for (int j = (p & 1); j + 1 < N; j += 2) {
                bool s_ = c[j + 1] < c[j]; float tc = c[j]; int td = d[j];
                c[j] = s_ ? c[j + 1] : c[j]; d[j] = s_ ? d[j + 1] : d[j];
                c[j + 1] = s_ ? tc : c[j + 1]; d[j + 1] = s_ ? td : d[j + 1];
            }
        }
        float at = 0.0, cov = 0.0;
        bool in = cm_acov_in(w, evenodd);
        #pragma unroll
        for (int j = 0; j < N; ++j) {
            bool real = c[j] < 1.0;
            cov += (real && in) ? c[j] - at : 0.0;
            at   = real ? c[j] : at;
            w   += d[j];
            in   = cm_acov_in(w, evenodd);
        }
        total += in ? cov + 1.0 - at : cov;
    }
    return total / float(CM_ACOV_SUB);
}

// An exact row (no edge ends in it, no two cross in it): the pixel splits into
// strips between the edges crossing it, each wholly in or out by the fill
// rule, each strip's area a difference of two trapezoid integrals.
template <int N>
static inline float cm_acov_fullT(cm_acov_set<N> S, int wl, float fx, float fy, int evenodd)
{
    int   w0 = wl;
    float xm[N], xt[N], xb[N]; int d[N];
    #pragma unroll
    for (int j = 0; j < N; ++j) {
        float4 a = S.e[j];
        float t = cm_acov_top(a);
        // cairo's: an edge in an exact row spans all its sub-rows, and one
        // that reaches none of their centres is not in its polygon at all.
        bool act = cm_acov_on(a, fy + 0.5 / float(CM_ACOV_SUB));
        float xa = a.x + (fy - t) * a.w;
        float xz = a.x + (fy + 1.0 - t) * a.w;
        bool right = min(xa, xz) >= fx + 1.0;
        bool left = act && !right && max(xa, xz) <= fx;
        bool cross = act && !right && !left;
        w0 += left ? cm_acov_dir(a) : 0;
        xm[j] = cross ? 0.5 * (xa + xz) : 3.0e9;
        xt[j] = xa; xb[j] = xz; d[j] = cross ? cm_acov_dir(a) : 0;
    }
    #pragma unroll
    for (int p = 0; p < N; ++p) {
        #pragma unroll
        for (int j = (p & 1); j + 1 < N; j += 2) {
            bool s_ = xm[j + 1] < xm[j];
            float a_ = xm[j]; xm[j] = s_ ? xm[j + 1] : xm[j]; xm[j + 1] = s_ ? a_ : xm[j + 1];
            a_ = xt[j]; xt[j] = s_ ? xt[j + 1] : xt[j]; xt[j + 1] = s_ ? a_ : xt[j + 1];
            a_ = xb[j]; xb[j] = s_ ? xb[j + 1] : xb[j]; xb[j + 1] = s_ ? a_ : xb[j + 1];
            int b_ = d[j]; d[j] = s_ ? d[j + 1] : d[j]; d[j + 1] = s_ ? b_ : d[j + 1];
        }
    }
    float area = 0.0, prev = 1.0;       // area right of the previous boundary
    int   w = w0;
    #pragma unroll
    for (int j = 0; j < N; ++j) {
        bool real = xm[j] < 1.0e9;
        float ar = real ? cm_acov_aright(xt[j], xb[j], fx) : 0.0;
        if (real && cm_acov_in(w, evenodd)) area += prev - ar;
        prev = real ? ar : prev;
        w += d[j];
    }
    if (cm_acov_in(w, evenodd)) area += prev;
    return clamp(area, 0.0, 1.0);
}

// A sampled row, five to eight edges, with as little held at once as
// possible: per sub-row the edges are read again (from cache) and only their
// crossings are kept; the covered length is summed interval by interval --
// each crossing's interval runs to the nearest crossing right of it, at the
// winding of every crossing at or left of it -- with no sort and no array
// indexed by a variable.
static inline float cm_acov_sub8(device const float4 *E, uint n, uint4 W, float fx, float fy, int evenodd)
{
    float total = 0.0;
    for (int k = 0; k < CM_ACOV_SUB; ++k) {
        float yc = fy + (float(k) + 0.5) / float(CM_ACOV_SUB);
        int w0 = cm_acov_wsub(W, k);
        float c[8]; int d[8];
        float first = 1.0;
        #pragma unroll
        for (int j = 0; j < 8; ++j) {
            float4 a = uint(j) < n ? E[j] : float4(-1.0e9, -1.0e9, -1.0e9, 0.0);
            float t = cm_acov_top(a), b = cm_acov_bot(a);
            bool act = t < yc && yc <= b;
            float x = (a.x + (yc - t) * a.w) - fx;
            int dir = cm_acov_dir(a);
            w0 += (act && x < 0.0) ? dir : 0;
            bool inpx = act && x >= 0.0 && x < 1.0;
            c[j] = inpx ? x : 2.0;
            d[j] = inpx ? dir : 0;
            first = min(first, c[j]);
        }
        float cov = cm_acov_in(w0, evenodd) ? first : 0.0;
        #pragma unroll
        for (int i = 0; i < 8; ++i) {
            int w = w0; float nx = 1.0;
            #pragma unroll
            for (int j = 0; j < 8; ++j) {
                w += (c[j] <= c[i]) ? d[j] : 0;
                nx = (c[j] > c[i]) ? min(nx, c[j]) : nx;
            }
            // an interval opened by a tie is counted once, at its first index
            bool lead = true;
            #pragma unroll
            for (int j = 0; j < i; ++j) lead = lead && c[j] != c[i];
            cov += (c[i] < 1.0 && lead && cm_acov_in(w, evenodd)) ? nx - c[i] : 0.0;
        }
        total += cov;
    }
    return total / float(CM_ACOV_SUB);
}

// A sampled row, a span of more than four edges: per sub-row the crossings
// taken in (x, index) order by repeated selection over the span's edges.
static inline float cm_acov_subn(device const float4 *E, uint n, uint4 W, float fx, float fy, int evenodd)
{
    float total = 0.0;
    for (int k = 0; k < CM_ACOV_SUB; ++k) {
        float yc = fy + (float(k) + 0.5) / float(CM_ACOV_SUB);
        int w = cm_acov_wsub(W, k), crossings = 0;
        for (uint i = 0; i < n; ++i) {
            float4 a = E[i];
            if (!cm_acov_on(a, yc)) continue;
            float x = (a.x + (yc - cm_acov_top(a)) * a.w) - fx;
            if (x < 0.0) w += cm_acov_dir(a);
            else if (x < 1.0) ++crossings;
        }
        bool in = cm_acov_in(w, evenodd);
        float at = 0.0, cov = 0.0, lx = -1.0;
        int   li = -1;
        for (int c = 0; c < crossings; ++c) {
            float bx = 2.0; int bi = 0x7fffffff; int bd = 0;
            for (uint i = 0; i < n; ++i) {
                float4 a = E[i];
                if (!cm_acov_on(a, yc)) continue;
                float x = (a.x + (yc - cm_acov_top(a)) * a.w) - fx;
                if (x < 0.0 || x >= 1.0) continue;
                bool after = (x > lx) || (x == lx && int(i) > li);
                bool before = (x < bx) || (x == bx && int(i) < bi);
                if (after && before) { bx = x; bi = int(i); bd = cm_acov_dir(a); }
            }
            if (in) cov += bx - at;
            at = bx; lx = bx; li = bi;
            w += bd;
            in = cm_acov_in(w, evenodd);
        }
        total += in ? cov + 1.0 - at : cov;
    }
    return total / float(CM_ACOV_SUB);
}

// An exact row, a span of more than four edges: the strips, the crossing
// edges taken in order of their x at the row's middle (no two cross here).
static inline float cm_acov_fulln(device const float4 *E, uint n, int wl, float fx, float fy, int evenodd)
{
    int w = wl, crossings = 0;
    for (uint i = 0; i < n; ++i) {
        float4 a = E[i];
        float t = cm_acov_top(a);
        if (!cm_acov_on(a, fy + 0.5 / float(CM_ACOV_SUB))) continue;
        float xa = a.x + (fy - t) * a.w;
        float xz = a.x + (fy + 1.0 - t) * a.w;
        if (min(xa, xz) >= fx + 1.0) continue;
        if (max(xa, xz) <= fx) w += cm_acov_dir(a); else ++crossings;
    }
    float area = 0.0, prev = 1.0, lm = -1.0e9;
    int   li = -1;
    for (int c = 0; c < crossings; ++c) {
        float bm = 3.0e9, bt = 0.0, bb = 0.0; int bi = 0x7fffffff, bd = 0;
        for (uint i = 0; i < n; ++i) {
            float4 a = E[i];
            float t = cm_acov_top(a);
            if (!cm_acov_on(a, fy + 0.5 / float(CM_ACOV_SUB))) continue;
            float xa = a.x + (fy - t) * a.w;
            float xz = a.x + (fy + 1.0 - t) * a.w;
            if (min(xa, xz) >= fx + 1.0 || max(xa, xz) <= fx) continue;
            float m = 0.5 * (xa + xz);
            bool after = (m > lm) || (m == lm && int(i) > li);
            bool before = (m < bm) || (m == bm && int(i) < bi);
            if (after && before) { bm = m; bi = int(i); bt = xa; bb = xz; bd = cm_acov_dir(a); }
        }
        float ar = cm_acov_aright(bt, bb, fx);
        if (cm_acov_in(w, evenodd)) area += prev - ar;
        prev = ar; lm = bm; li = bi;
        w += bd;
    }
    if (cm_acov_in(w, evenodd)) area += prev;
    return clamp(area, 0.0, 1.0);
}

static inline float cm_acov_span_coverage(float2 pos, device const float4 *edges, uint4 S,
                                          int evenodd)
{
    float fx = floor(pos.x), fy = floor(pos.y);
    device const float4 *E = edges + (S.y & 0xffffffu);
    uint n = S.y >> 24;
    bool full = (S.z & 0x80000000u) != 0;
    int  wl = cm_acov_wsub(S, 0);
    uint4 W = S;
    // At most four edges for 95-97% of a manim frame's edge pixels: held in
    // registers.  Five to eight (2-3%) take the sort-free path below, which
    // holds only their crossings; walking them in device memory, sub-row by
    // sub-row, cost a manim frame milliseconds for that few pixels.
    if (n <= 4) {
        cm_acov_set<4> R = cm_acov_load<4>(E, n);
        return full ? cm_acov_fullT<4>(R, wl, fx, fy, evenodd) : cm_acov_subT<4>(R, W, fx, fy, evenodd);
    }
    if (n <= 8 && !full) return cm_acov_sub8(E, n, W, fx, fy, evenodd);
    return full ? cm_acov_fulln(E, n, wl, fx, fy, evenodd)
                : cm_acov_subn(E, n, W, fx, fy, evenodd);
}

// The pixel's segment in its row, or 0xffffffff: a binary search, the row's
// segments being sorted and disjoint.
static inline uint cm_acov_find_span(uint px, uint4 R, device const uint4 *spans)
{
    uint lo = R.x, hi = R.x + R.y;
    while (lo < hi) {
        uint mid = (lo + hi) >> 1;
        if (px < (spans[mid].x & 0xffffu)) hi = mid; else lo = mid + 1;
    }
    if (lo == R.x) return 0xffffffffu;
    uint sp = spans[lo - 1].x;
    return px < (sp >> 16) ? lo - 1 : 0xffffffffu;
}

#define CM_ACOV_ARGS                                                      \
    CoverInOut in [[stage_in]],                                          \
    constant cm_uniforms &u [[buffer(1)]],                               \
    device const float4 *edges [[buffer(2)]],                            \
    device const uint4 *rows [[buffer(3)]],                              \
    device const uint4 *spans [[buffer(4)]],                             \
    constant cm_acov_params &P [[buffer(5)]]

// The edge pixel's coverage, or discard for a pixel no edge passes through.
// Every read stays in range even for a lane that will be discarded: a shader
// that samples a texture keeps discarded lanes running as helpers (for the
// derivatives), and a helper outside the rows once read a garbage span count
// and hung the GPU.  So: guarded reads, and the discard last.
#define CM_ACOV_COVERAGE(cov)                                                 \
    int py_ = int(floor(in.position.y)) - P.row0;                             \
    bool ok_ = py_ >= 0 && py_ < P.nrows;                                     \
    uint4 R_ = ok_ ? rows[py_] : uint4(0);                                    \
    uint px_ = uint(max(floor(in.position.x), 0.0));                          \
    uint k_ = ok_ ? cm_acov_find_span(px_, R_, spans) : 0xffffffffu;          \
    ok_ = ok_ && k_ != 0xffffffffu;                                           \
    uint4 S_ = ok_ ? spans[k_] : uint4(0);                                    \
    float cov = ok_ ? cm_acov_span_coverage(in.position.xy, edges, S_, P.evenodd) : 0.0; \
    if (!ok_) discard_fragment()

fragment float4 cm_fs_acov_solid(CM_ACOV_ARGS)
{
    CM_ACOV_COVERAGE(cov);
    if (cov <= 0.0) discard_fragment();
    return P.solid * cov;
}

fragment float4 cm_fs_acov_linear(CM_ACOV_ARGS, texture2d<float> lut [[texture(0)]])
{
    CM_ACOV_COVERAGE(cov);
    if (cov <= 0.0) discard_fragment();
    if (P.nstops == 0) return cm_paint_linear(in.dev, u, lut) * (u.global_alpha * cov);
    float2 A = float2(u.grad_axis[0], u.grad_axis[1]);
    float2 B = float2(u.grad_axis[2], u.grad_axis[3]);
    float2 ab = B - A;
    float  d = dot(ab, ab);
    float  t = (d > 0.0) ? clamp(dot(in.position.xy - A, ab) / d, 0.0, 1.0) : 1.0;
    return cm_acov_stops(t, P) * (u.global_alpha * cov);
}

// The interior of an analytic fill: the stencil cover's quad (cm_vs_cover)
// over the pixels the edge spans left, at full coverage, with the edge spans'
// own paint so the two meet without a seam.
fragment float4 cm_fs_acov_full_solid(CoverInOut in [[stage_in]],
                                      constant cm_uniforms &u [[buffer(1)]],
                                      constant cm_acov_params &P [[buffer(5)]])
{
    return P.solid;
}

fragment float4 cm_fs_acov_full_linear(CoverInOut in [[stage_in]],
                                       constant cm_uniforms &u [[buffer(1)]],
                                       constant cm_acov_params &P [[buffer(5)]],
                                       texture2d<float> lut [[texture(0)]])
{
    if (P.nstops == 0) return cm_paint_linear(in.dev, u, lut) * u.global_alpha;
    float2 A = float2(u.grad_axis[0], u.grad_axis[1]);
    float2 B = float2(u.grad_axis[2], u.grad_axis[3]);
    float2 ab = B - A;
    float  d = dot(ab, ab);
    float  t = (d > 0.0) ? clamp(dot(in.position.xy - A, ab) / d, 0.0, 1.0) : 1.0;
    return cm_acov_stops(t, P) * u.global_alpha;
}

fragment float4 cm_fs_acov_full_radial(CoverInOut in [[stage_in]],
                                       constant cm_uniforms &u [[buffer(1)]],
                                       texture2d<float> lut [[texture(0)]])
{
    return cm_paint_radial(in.dev, u, lut) * u.global_alpha;
}

fragment float4 cm_fs_acov_radial(CM_ACOV_ARGS, texture2d<float> lut [[texture(0)]])
{
    CM_ACOV_COVERAGE(cov);
    if (cov <= 0.0) discard_fragment();
    return cm_paint_radial(in.dev, u, lut) * (u.global_alpha * cov);
}

// ---- mask cover (source * mask-alpha) --------------------------------------
// Multiply the PREMULTIPLIED solid source by the mask's sampled alpha.  cairo's
// cairo_mask composites source THROUGH the mask's alpha channel; scaling a
// premultiplied colour by a scalar alpha is premultiplied-correct (both rgb and
// a scale together).  The mask texture is sampled in its own pattern/texel space
// via the same inverse rows (cm_compose.m packs the mask pattern's device->
// pattern matrix into pat_inv for this).  global_alpha further weights it (the
// compose path folds a solid mask into the source alpha and a non-1 paint alpha
// into global_alpha).
// Read the mask surface's COVERAGE at a sampled texel.  cairo composites the
// source THROUGH the mask surface's alpha; which physical channel holds that
// alpha depends on the mask surface's format, signalled by u.mask_kind:
//   0 == A8 / alpha-only surface (R8 texture): coverage is the single .r channel
//        (sampling .a of an R8 texture returns a constant 1.0, so .r is required).
//   1 == colour (ARGB32) surface: the coverage is the premultiplied .a channel.
static inline float cm_mask_coverage(float4 sampled, constant cm_uniforms &u) {
    return (u.mask_kind == 0) ? sampled.r : sampled.a;
}

fragment float4
cm_fs_mask(CoverInOut             in   [[stage_in]],
           constant cm_uniforms  &u    [[buffer(1)]],
           texture2d<float>       msk  [[texture(0)]],
           sampler                samp [[sampler(0)]])
{
    float2 pat = cm_to_pattern(in.dev, u);
    float2 uv = pat / float2(max(1.0, float(msk.get_width())),
                             max(1.0, float(msk.get_height())));
    float ma = cm_mask_coverage(msk.sample(samp, uv), u);
    float4 c = cm_paint_solid(u);     // premultiplied source (solid.a already folds
                                      // paint_with_alpha / group alpha on the CPU)
    return c * ma;                    // scale premultiplied colour by mask coverage
}

// ===========================================================================
// GOURAUD (mesh) COVER — per-vertex colour
// ===========================================================================
// cm_mesh.c tessellates each Coons patch into Gouraud triangles (cm_vtx_color),
// already pre-transformed to DEVICE space CPU-side.  The vertex stage forwards
// the per-vertex NON-premultiplied colour; the fragment premultiplies on output.

struct GouraudInOut {
    float4 position [[position]];
    float4 color;                  // per-vertex, NON-premultiplied
    float2 dev;                    // device px, for the clip-aware variant
};

vertex GouraudInOut
cm_vs_cover_color(uint                       vid   [[vertex_id]],
                  device const cm_vtx_color *verts [[buffer(0)]],
                  constant cm_uniforms      &u     [[buffer(1)]])
{
    cm_vtx_color v = verts[vid];
    GouraudInOut out;
    out.dev      = float2(v.x, v.y);
    out.position = cm_to_clip(out.dev, u);
    out.color    = float4(v.color.r, v.color.g, v.color.b, v.color.a);
    return out;
}

fragment float4
cm_fs_cover_gouraud(GouraudInOut in [[stage_in]],
                    constant cm_uniforms &u [[buffer(1)]])
{
    float4 c = in.color;
    c.rgb *= c.a;                  // premultiply on output
    return c * u.global_alpha;     // mesh colour is per-vertex; apply group alpha here
}

// ===========================================================================
// CLIP-AWARE COVER VARIANTS  (sample the A8 clip plane + multiply)
// ===========================================================================
//
// Identical to the base covers above, plus the clip multiply.  Selected by
// cm_device_cover_pipeline(..., clip=true, ...); the encoder calls
// cm_clip_bind(enc, ctx->clip) which binds the A8 plane at texture(1)/sampler(1)
// (cm_clip.m).  Multiplying the PREMULTIPLIED output by coverage in [0,1] both
// scales colour and cuts alpha, so the premultiplied OVER blend then composites
// only the in-clip fraction — antialiased clip edges come straight from the
// resolved A8 coverage.  The separable fixed-function operators (0..13) reuse
// these same clip variants (the operator lives in the blend STATE, the clip in
// the fragment), which is why ops 0..13 need no new fragment but DO need these.

fragment float4
cm_fs_cover_solid_clip(CoverInOut            in       [[stage_in]],
                       constant cm_uniforms &u        [[buffer(1)]],
                       texture2d<float>      clipmask [[texture(1)]],
                       sampler               clipsamp [[sampler(1)]])
{
    float4 c = cm_paint_solid(u);
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

fragment float4
cm_fs_cover_linear_clip(CoverInOut             in       [[stage_in]],
                        constant cm_uniforms  &u        [[buffer(1)]],
                        texture2d<float>       lut      [[texture(0)]],
                        texture2d<float>       clipmask [[texture(1)]],
                        sampler                clipsamp [[sampler(1)]])
{
    float4 c = cm_paint_linear(in.dev, u, lut) * u.global_alpha;
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

fragment float4
cm_fs_cover_radial_clip(CoverInOut             in       [[stage_in]],
                        constant cm_uniforms  &u        [[buffer(1)]],
                        texture2d<float>       lut      [[texture(0)]],
                        texture2d<float>       clipmask [[texture(1)]],
                        sampler                clipsamp [[sampler(1)]])
{
    float4 c = cm_paint_radial(in.dev, u, lut) * u.global_alpha;
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

fragment float4
cm_fs_cover_surface_clip(CoverInOut             in       [[stage_in]],
                         constant cm_uniforms  &u        [[buffer(1)]],
                         texture2d<float>       src      [[texture(0)]],
                         sampler                samp     [[sampler(0)]],
                         texture2d<float>       clipmask [[texture(1)]],
                         sampler                clipsamp [[sampler(1)]])
{
    float4 c = cm_paint_surface(in.dev, u, src, samp) * u.global_alpha; // premultiplied
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

fragment float4
cm_fs_mask_clip(CoverInOut             in       [[stage_in]],
                constant cm_uniforms  &u        [[buffer(1)]],
                texture2d<float>       msk      [[texture(0)]],
                sampler                samp     [[sampler(0)]],
                texture2d<float>       clipmask [[texture(1)]],
                sampler                clipsamp [[sampler(1)]])
{
    float2 pat = cm_to_pattern(in.dev, u);
    float2 uv = pat / float2(max(1.0, float(msk.get_width())),
                             max(1.0, float(msk.get_height())));
    float ma = cm_mask_coverage(msk.sample(samp, uv), u);
    float4 c = cm_paint_solid(u);     // solid.a already folds group / pwa alpha
    c *= ma;
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

fragment float4
cm_fs_cover_gouraud_clip(GouraudInOut          in       [[stage_in]],
                         constant cm_uniforms &u        [[buffer(1)]],
                         texture2d<float>      clipmask [[texture(1)]],
                         sampler               clipsamp [[sampler(1)]])
{
    float4 c = in.color;
    c.rgb *= c.a;                  // premultiply on output
    c *= u.global_alpha;           // mesh colour is per-vertex; apply group alpha
    return c * cm_clip_coverage(in.dev, u, clipmask, clipsamp);
}

// ===========================================================================
// PROGRAMMABLE-BLEND COVER FRAGMENTS  (PDF blend modes, cairo operators 14..28)
// ===========================================================================
//
// cairo operators 14..28 (MULTIPLY..HSL_LUMINOSITY) are the PDF/SVG blend modes.
// They are NOT a fixed-function MTLRenderPipelineColorAttachment blend, so these
// fragments read the destination via [[color(0)]] framebuffer fetch (Apple GPUs
// support programmable blending: declaring a [[color(0)]] fragment argument reads
// the current attachment value) and compute the composite in-shader.
//
// The blend modes are defined on NON-premultiplied colour; cairo's compositing
// formula for a separable blend B over premultiplied src (Cs,as) and dest
// (Cb,ab) is the general Porter-Duff "source over" with the blended source
// colour:
//   result_rgb = (1 - ab)*Cs + (1 - as)*Cb + as*ab*B(Cb/ab, Cs/as)   [premult]
//   result_a   = as + ab - as*ab
// (PDF blend mode composited with the OVER coverage operator, which is what
// cairo uses for these operators.)  We carry src/dest in premultiplied form,
// un-premultiply to evaluate B, then re-form the premultiplied result.  The
// colour-attachment blend state for these pipelines is configured by cm_device.m
// to OPAQUE pass-through (src=One, dst=Zero) so the value we return IS the final
// pixel — all compositing is done here.
//
// These fragments are clip-aware-capable too: when a clip is bound the device
// selects the *_blend_* fragment with the clip texture, and we LERP the result
// toward the untouched destination by clip coverage (so out-of-clip fragments
// keep dest exactly).  When unclipped, cm_device binds a 1x1 white clip dummy OR
// selects the non-clip blend variant; to keep ONE blend fragment per mode we
// read coverage from an optional clip texture and the device binds a fully-opaque
// (coverage==1) plane when unclipped.  (cm_device owns that choice; if it instead
// ships distinct clip/non-clip blend variants, the coverage read is a constant 1
// and folds away.)

// --- separable blend primitives B(cb, cs), all on NON-premultiplied [0,1] ----
static inline float cm_b_multiply (float cb, float cs) { return cb * cs; }
static inline float cm_b_screen   (float cb, float cs) { return cb + cs - cb * cs; }
static inline float cm_b_overlay  (float cb, float cs) {
    return (cb <= 0.5) ? (2.0 * cb * cs)
                       : (1.0 - 2.0 * (1.0 - cb) * (1.0 - cs));
}
static inline float cm_b_darken   (float cb, float cs) { return min(cb, cs); }
static inline float cm_b_lighten  (float cb, float cs) { return max(cb, cs); }
static inline float cm_b_color_dodge(float cb, float cs) {
    if (cb <= 0.0) return 0.0;
    if (cs >= 1.0) return 1.0;
    return min(1.0, cb / (1.0 - cs));
}
static inline float cm_b_color_burn(float cb, float cs) {
    if (cb >= 1.0) return 1.0;
    if (cs <= 0.0) return 0.0;
    return 1.0 - min(1.0, (1.0 - cb) / cs);
}
static inline float cm_b_hard_light(float cb, float cs) {
    return (cs <= 0.5) ? (2.0 * cb * cs)
                       : (1.0 - 2.0 * (1.0 - cb) * (1.0 - cs));
}
static inline float cm_b_soft_light(float cb, float cs) {
    // PDF/SVG soft-light.
    if (cs <= 0.5) {
        return cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
    } else {
        float d = (cb <= 0.25) ? (((16.0 * cb - 12.0) * cb + 4.0) * cb)
                               : sqrt(cb);
        return cb + (2.0 * cs - 1.0) * (d - cb);
    }
}
static inline float cm_b_difference(float cb, float cs) { return fabs(cb - cs); }
static inline float cm_b_exclusion (float cb, float cs) { return cb + cs - 2.0 * cb * cs; }

// Apply a separable blend mode component-wise to a colour triple.
static inline float3 cm_blend_separable(int op, float3 cb, float3 cs) {
    switch (op) {
        case CM_OP_MULTIPLY:
            return float3(cm_b_multiply(cb.r,cs.r), cm_b_multiply(cb.g,cs.g), cm_b_multiply(cb.b,cs.b));
        case CM_OP_SCREEN:
            return float3(cm_b_screen(cb.r,cs.r), cm_b_screen(cb.g,cs.g), cm_b_screen(cb.b,cs.b));
        case CM_OP_OVERLAY:
            return float3(cm_b_overlay(cb.r,cs.r), cm_b_overlay(cb.g,cs.g), cm_b_overlay(cb.b,cs.b));
        case CM_OP_DARKEN:
            return float3(cm_b_darken(cb.r,cs.r), cm_b_darken(cb.g,cs.g), cm_b_darken(cb.b,cs.b));
        case CM_OP_LIGHTEN:
            return float3(cm_b_lighten(cb.r,cs.r), cm_b_lighten(cb.g,cs.g), cm_b_lighten(cb.b,cs.b));
        case CM_OP_COLOR_DODGE:
            return float3(cm_b_color_dodge(cb.r,cs.r), cm_b_color_dodge(cb.g,cs.g), cm_b_color_dodge(cb.b,cs.b));
        case CM_OP_COLOR_BURN:
            return float3(cm_b_color_burn(cb.r,cs.r), cm_b_color_burn(cb.g,cs.g), cm_b_color_burn(cb.b,cs.b));
        case CM_OP_HARD_LIGHT:
            return float3(cm_b_hard_light(cb.r,cs.r), cm_b_hard_light(cb.g,cs.g), cm_b_hard_light(cb.b,cs.b));
        case CM_OP_SOFT_LIGHT:
            return float3(cm_b_soft_light(cb.r,cs.r), cm_b_soft_light(cb.g,cs.g), cm_b_soft_light(cb.b,cs.b));
        case CM_OP_DIFFERENCE:
            return float3(cm_b_difference(cb.r,cs.r), cm_b_difference(cb.g,cs.g), cm_b_difference(cb.b,cs.b));
        case CM_OP_EXCLUSION:
        default:
            return float3(cm_b_exclusion(cb.r,cs.r), cm_b_exclusion(cb.g,cs.g), cm_b_exclusion(cb.b,cs.b));
    }
}

// --- non-separable (HSL) helpers, per PDF/SVG (W3C Compositing) ---------------
// Luma weights as in the spec (and cairo's CAIRO_OPERATOR_HSL_*): the
// 0.30/0.59/0.11 coefficients applied to the (R,G,B) ordered triple.
//
// IMPORTANT: although the BACKING texture is BGRA8, the fragment works in LOGICAL
// RGBA — cm_paint_solid loads float4(solid.r, solid.g, solid.b, a) (logical R in
// .r) and Metal swizzles .r -> the texture's R channel on write; the [[color(0)]]
// framebuffer fetch likewise un-swizzles to logical RGBA on read.  So c.r/.g/.b
// ARE logical R/G/B here and the weights must be in the natural (R,G,B) order
// (0.30 on .r).  The separable modes are per-channel symmetric so a channel-order
// mistake is invisible there, but HSL luma is a weighted sum where the R and B
// weights differ, so the order is load-bearing for the non-separable modes.
static inline float cm_lum(float3 c) {
    return dot(c, float3(0.30, 0.59, 0.11));   // (R,G,B) logical-channel weights
}
static inline float3 cm_clip_color(float3 c) {
    float l = cm_lum(c);
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = l + (c - l) * (l / max(l - n, 1e-6));
    if (x > 1.0) c = l + (c - l) * ((1.0 - l) / max(x - l, 1e-6));
    return c;
}
static inline float3 cm_set_lum(float3 c, float l) {
    float d = l - cm_lum(c);
    return cm_clip_color(c + d);
}
static inline float cm_sat(float3 c) {
    return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
}
// Set saturation of `c` to `s`, preserving relative ordering (PDF SetSat).
static inline float3 cm_set_sat(float3 c, float s) {
    // Sort the three channels by value via index, scale the mid/max, zero min.
    float cmin = min(min(c.r, c.g), c.b);
    float cmax = max(max(c.r, c.g), c.b);
    float3 res = float3(0.0);
    if (cmax > cmin) {
        // mid value:
        float cmid = c.r + c.g + c.b - cmin - cmax;
        float mid_scaled = (cmid - cmin) * s / (cmax - cmin);
        // Re-distribute to the original channels by matching values.
        // Build per-channel result: min->0, max->s, mid->mid_scaled.
        res.r = (c.r == cmax) ? s : ((c.r == cmin) ? 0.0 : mid_scaled);
        res.g = (c.g == cmax) ? s : ((c.g == cmin) ? 0.0 : mid_scaled);
        res.b = (c.b == cmax) ? s : ((c.b == cmin) ? 0.0 : mid_scaled);
        // Guard against two channels equal to cmax/cmin (ties): clamp.
        res = clamp(res, 0.0, s);
    }
    return res;
}
static inline float3 cm_blend_nonseparable(int op, float3 cb, float3 cs) {
    switch (op) {
        case CM_OP_HSL_HUE:
            return cm_set_lum(cm_set_sat(cs, cm_sat(cb)), cm_lum(cb));
        case CM_OP_HSL_SATURATION:
            return cm_set_lum(cm_set_sat(cb, cm_sat(cs)), cm_lum(cb));
        case CM_OP_HSL_COLOR:
            return cm_set_lum(cs, cm_lum(cb));
        case CM_OP_HSL_LUMINOSITY:
        default:
            return cm_set_lum(cb, cm_lum(cs));
    }
}

// Composite a (non-premultiplied) blended source colour B over the destination
// using the OVER coverage operator, in PREMULTIPLIED space.  Inputs:
//   src_pm  = premultiplied source (Cs, as)
//   dst_pm  = premultiplied dest   (Cb, ab)
//   B       = non-premultiplied blend result B(Cb', Cs')
// Returns the premultiplied composited pixel:
//   Co = (1-ab)*Cs_pm + (1-as)*Cb_pm + as*ab*B
//   ao = as + ab - as*ab
static inline float4 cm_blend_composite(float4 src_pm, float4 dst_pm, float3 B) {
    float as = src_pm.a;
    float ab = dst_pm.a;
    float3 Cs_pm = src_pm.rgb;
    float3 Cb_pm = dst_pm.rgb;
    float3 Co = (1.0 - ab) * Cs_pm + (1.0 - as) * Cb_pm + (as * ab) * B;
    float  ao = as + ab - as * ab;
    return float4(Co, ao);
}

// Evaluate the blend B for an operator, given non-premultiplied colours.
static inline float3 cm_blend_eval(int op, float3 cb, float3 cs) {
    if (op >= CM_OP_HSL_HUE) return cm_blend_nonseparable(op, cb, cs);
    return cm_blend_separable(op, cb, cs);
}

// Un-premultiply a premultiplied colour (a==0 -> black).
static inline float3 cm_unpremul(float4 pm) {
    return (pm.a > 0.0) ? (pm.rgb / pm.a) : float3(0.0);
}

// The shared programmable-blend body: take a PREMULTIPLIED source colour, read
// the destination via framebuffer fetch, blend per `op`, composite OVER, and
// optionally fold in clip coverage (lerp toward the untouched dest).
static inline float4 cm_blend_body(float4 src_pm, float4 dst_pm,
                                   constant cm_uniforms &u, float coverage) {
    float3 cb = cm_unpremul(dst_pm);
    float3 cs = cm_unpremul(src_pm);
    float3 B  = cm_blend_eval(u.op, cb, cs);
    float4 out = cm_blend_composite(src_pm, dst_pm, B);
    // coverage in [0,1]: out-of-clip keeps dest exactly.
    return mix(dst_pm, out, coverage);
}

// One entry point per paint kind; the device selects by (op, paint_kind).  Each
// reads dest via [[color(0)]] and writes the final composited pixel (the blend
// pipeline's colour attachment is src=One,dst=Zero pass-through).  global_alpha
// weights the source alpha (paint_with_alpha) BEFORE compositing.

fragment float4
cm_fs_blend_solid(CoverInOut            in       [[stage_in]],
                  float4                dst      [[color(0)]],
                  constant cm_uniforms &u        [[buffer(1)]])
{
    // SOLID alpha (incl. paint_with_alpha / group opacity) is already folded into
    // solid.a on the CPU (cm_apply_alpha_to_source); do NOT re-apply global_alpha
    // here or it would double-weight.  The non-solid blend frags below DO apply it
    // (their alpha lives in the LUT/texture/per-vertex colour, untouched by the CPU).
    float4 src = cm_paint_solid(u);                    // premultiplied
    return cm_blend_body(src, dst, u, 1.0);
}

fragment float4
cm_fs_blend_linear(CoverInOut            in       [[stage_in]],
                   float4                dst      [[color(0)]],
                   constant cm_uniforms &u        [[buffer(1)]],
                   texture2d<float>      lut      [[texture(0)]])
{
    float4 src = cm_paint_linear(in.dev, u, lut) * u.global_alpha;
    return cm_blend_body(src, dst, u, 1.0);
}

fragment float4
cm_fs_blend_radial(CoverInOut            in       [[stage_in]],
                   float4                dst      [[color(0)]],
                   constant cm_uniforms &u        [[buffer(1)]],
                   texture2d<float>      lut      [[texture(0)]])
{
    float4 src = cm_paint_radial(in.dev, u, lut) * u.global_alpha;
    return cm_blend_body(src, dst, u, 1.0);
}

fragment float4
cm_fs_blend_surface(CoverInOut            in       [[stage_in]],
                    float4                dst      [[color(0)]],
                    constant cm_uniforms &u        [[buffer(1)]],
                    texture2d<float>      src      [[texture(0)]],
                    sampler               samp     [[sampler(0)]])
{
    float4 s = cm_paint_surface(in.dev, u, src, samp) * u.global_alpha;
    return cm_blend_body(s, dst, u, 1.0);
}

fragment float4
cm_fs_blend_gouraud(GouraudInOut          in       [[stage_in]],
                    float4                dst      [[color(0)]],
                    constant cm_uniforms &u        [[buffer(1)]])
{
    float4 src = in.color;
    src.rgb *= src.a;
    src *= u.global_alpha;
    return cm_blend_body(src, dst, u, 1.0);
}

// Clip-aware programmable-blend variants: same, with the A8 clip coverage folded
// in (out-of-clip fragments keep dest exactly via the mix() in cm_blend_body).

fragment float4
cm_fs_blend_solid_clip(CoverInOut            in       [[stage_in]],
                       float4                dst      [[color(0)]],
                       constant cm_uniforms &u        [[buffer(1)]],
                       texture2d<float>      clipmask [[texture(1)]],
                       sampler               clipsamp [[sampler(1)]])
{
    float4 src = cm_paint_solid(u);   // solid.a already folds group / pwa alpha
    float  cov = cm_clip_coverage(in.dev, u, clipmask, clipsamp);
    return cm_blend_body(src, dst, u, cov);
}

fragment float4
cm_fs_blend_linear_clip(CoverInOut            in       [[stage_in]],
                        float4                dst      [[color(0)]],
                        constant cm_uniforms &u        [[buffer(1)]],
                        texture2d<float>      lut      [[texture(0)]],
                        texture2d<float>      clipmask [[texture(1)]],
                        sampler               clipsamp [[sampler(1)]])
{
    float4 src = cm_paint_linear(in.dev, u, lut) * u.global_alpha;
    float  cov = cm_clip_coverage(in.dev, u, clipmask, clipsamp);
    return cm_blend_body(src, dst, u, cov);
}

fragment float4
cm_fs_blend_radial_clip(CoverInOut            in       [[stage_in]],
                        float4                dst      [[color(0)]],
                        constant cm_uniforms &u        [[buffer(1)]],
                        texture2d<float>      lut      [[texture(0)]],
                        texture2d<float>      clipmask [[texture(1)]],
                        sampler               clipsamp [[sampler(1)]])
{
    float4 src = cm_paint_radial(in.dev, u, lut) * u.global_alpha;
    float  cov = cm_clip_coverage(in.dev, u, clipmask, clipsamp);
    return cm_blend_body(src, dst, u, cov);
}

fragment float4
cm_fs_blend_surface_clip(CoverInOut            in       [[stage_in]],
                         float4                dst      [[color(0)]],
                         constant cm_uniforms &u        [[buffer(1)]],
                         texture2d<float>      src      [[texture(0)]],
                         sampler               samp     [[sampler(0)]],
                         texture2d<float>      clipmask [[texture(1)]],
                         sampler               clipsamp [[sampler(1)]])
{
    float4 s   = cm_paint_surface(in.dev, u, src, samp) * u.global_alpha;
    float  cov = cm_clip_coverage(in.dev, u, clipmask, clipsamp);
    return cm_blend_body(s, dst, u, cov);
}

fragment float4
cm_fs_blend_gouraud_clip(GouraudInOut          in       [[stage_in]],
                         float4                dst      [[color(0)]],
                         constant cm_uniforms &u        [[buffer(1)]],
                         texture2d<float>      clipmask [[texture(1)]],
                         sampler               clipsamp [[sampler(1)]])
{
    float4 src = in.color;
    src.rgb *= src.a;
    src *= u.global_alpha;
    float cov = cm_clip_coverage(in.dev, u, clipmask, clipsamp);
    return cm_blend_body(src, dst, u, cov);
}

// ===========================================================================
// CROSS-MODULE SEAMS  (for the Build phase to reconcile)
// ===========================================================================
//
// 1. NEW PIPELINE WIRING (cm_device.m).  cm_device_create currently builds only
//    the four shipping pipelines and validates [0, CM_PIPE_COVER_LINEAR]; the
//    appended CM_PIPE_COVER_{RADIAL,SURFACE,GOURAUD,MASK,SOLID_A8} are built
//    lazily by cm_device_cover_pipeline (today a SCAFFOLD that maps every kind to
//    the SOLID/LINEAR slot).  To light up the full contract, cm_device must:
//      - build CM_PIPE_COVER_RADIAL  = cm_vs_cover / cm_fs_cover_radial,
//              CM_PIPE_COVER_SURFACE = cm_vs_cover / cm_fs_cover_surface,
//              CM_PIPE_COVER_GOURAUD = cm_vs_cover_color / cm_fs_cover_gouraud,
//              CM_PIPE_COVER_MASK    = cm_vs_cover / cm_fs_mask,
//              CM_PIPE_COVER_SOLID_A8= cm_vs_cover / cm_fs_cover_solid with the
//              colour attachment pixelFormat = MTLPixelFormatR8Unorm (A8 target);
//      - for clip==true, select the *_clip fragment of the chosen kind;
//      - for op in 14..28, select the cm_fs_blend_<kind>[_clip] fragment AND
//        configure that pipeline's colour attachment as OPAQUE pass-through
//        (sourceRGB/A=One, destRGB/A=Zero, blendingEnabled=NO) because the blend
//        fragment composites OVER internally via framebuffer fetch.  All other
//        cover pipelines keep the premultiplied-OVER blend state.
//    Every fragment name above already exists in this single metallib, so this is
//    pure cm_device.m pipeline-table work — no new .metal file, no Makefile /
//    Package.swift change (the whole reason the contract APPENDS here).
//
// 2. RADIAL INNER CIRCLE (cm_paint.m).  cm_fs_cover_radial does the full cairo
//    TWO-circle quadratic solve, reading the device-space OUTER circle from
//    grad_axis (already packed) and the device-space INNER circle (cx0,cy0,r0)
//    from mask_axis.  cm_paint.m presently ZEROES mask_axis for a radial paint,
//    which the shader treats as a concentric point source (c0=c1, r0=0) — this
//    reduces the solve EXACTLY to the shipping single-circle projection
//    length(p-c1)/r1, so the current output is unchanged and correct for the
//    common concentric case manim draws.  To enable the general two-circle cone
//    (non-concentric c0!=c1 or r0>0), cm_paint.m's RADIAL branch packs the folded
//    device inner circle into mask_axis:
//        cm_matrix_apply(&fold, cx0, cy0, &dcx0, &dcy0);  // fold = ctm*inv(pat)
//        out->mask_axis[0]=dcx0; out->mask_axis[1]=dcy0;
//        out->mask_axis[2]=r0 * cm_matrix_max_scale(&fold);
//    and may pack the gradient extend mode into grad_axis[3] (0 == PAD default;
//    the shader reads it through cm_extend_fold, mirroring cm_extend_fold_t).
//    No mask is in flight during a radial paint, so reusing mask_axis is free;
//    mask_kind stays SOLID.  (A non-zero genuine inner circle at exactly (0,0,0)
//    is degenerate, so the all-zero sentinel never misfires in practice.)
//
// 3. CLIP TEXTURE/SAMPLER BINDING (cm_fill.m / cm_compose.m).  The *_clip and
//    *_blend_*_clip fragments sample the A8 clip plane at texture(1)/sampler(1),
//    the exact indices cm_clip.m's cm_clip_bind() binds (CM_CLIP_BIND_TEX_INDEX /
//    CM_CLIP_BIND_SMP_INDEX == 1).  cm_compose.m ALREADY calls cm_clip_bind(enc,
//    ctx->clip) before its cover draw; cm_fill.m must add the same call (and
//    request the clip variant via cm_device_cover_pipeline(...,clip=true,...))
//    once the clip pipelines are wired in (1).  The clip UV needs no new uniform:
//    cm_dev_to_clip_uv recovers (1/W,1/H) from to_clip (= 2/W, -2/H).
// ===========================================================================
