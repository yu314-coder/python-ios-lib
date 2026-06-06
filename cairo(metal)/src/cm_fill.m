//
// cm_fill.m  --  CairoMetal stencil-then-cover FILL encode (SOLE fill owner)
// ============================================================================
//
// Implements cm_fill_encode() from cm_internal.h: it encodes a complete fill of
// a (pre-flattened) path with the current paint into the frame's single render
// command encoder, using the classic two-pass STENCIL-THEN-COVER technique so
// arbitrary self-intersecting paths with holes render correctly with no CPU
// triangulation.  Strokes reach here too -- cm_stroke_expand() turns an outline
// into a fillable polygon that this same NONZERO fill rasterizes.
//
// This translation unit is the ONLY fill code that talks to Metal; it does so
// purely through the opaque void* handles vended by cm_device.m / cm_surface.m
// (pipeline states, depth-stencil states, the per-frame command encoder, and
// the bump-allocated vertex/uniform ring).  It builds NOTHING per draw beyond
// ring sub-allocations: every MTLRenderPipelineState and MTLDepthStencilState
// was created once in cm_device_create (or is built lazily + cached by
// cm_device_cover_pipeline) and is fetched O(1) here.
//
// Pass 1 STENCIL  (CM_PIPE_STENCIL_{NONZERO|EVENODD} + matching DSS):
//   draw a triangle fan per contour (cm_path_emit_fan) with colour writes
//   masked off (mask lives in the pipeline); the two-sided incr/decr-wrap
//   (nonzero) or invert (even-odd) stencil op accumulates winding/parity.
// Pass 2 COVER  (operator-selected cover pipeline + cover DSS):
//   for SOLID / LINEAR / RADIAL / SURFACE, draw the path's device-space bounding
//   quad; the cover DSS passes where the stencil indicates inside (!=0 nonzero,
//   &1 even-odd) AND zeroes the touched samples in the SAME op, so the stencil is
//   clean for the next batched path (no per-path clear).  For MESH the Gouraud
//   triangles ARE the coverage (cm_mesh_emit_triangles): there is NO bounding
//   quad -- the patch triangles are drawn directly, still gated by the pass-1
//   stencil, so the mesh paints only inside the fill path.  The fragment stage
//   resolves the paint per kind (solid colour / gradient LUT / source texture /
//   per-vertex Gouraud colour) and premultiplies; 4x MSAA gives the antialiased
//   edges, resolved at frame end.
//
// UPGRADES over the original solid/linear shipping path (which is KEPT
// byte-for-byte as the default OVER, unclipped, BGRA path):
//   - OPERATOR : the cover pipeline is selected through the single front-door
//     hook cm_compose_operator_pipeline() -> cm_device_cover_pipeline(op, ...),
//     so cm_set_operator is honored (fixed-function Porter-Duff blends for ops
//     0..13, programmable-blend cover frags for 14..28).
//   - CLIP     : cm_clip_bind() binds the active A8 clip mask + sampler to the
//     cover fragment stage (texture(1)/sampler(1)); the cover frags multiply
//     their coverage by the sampled mask.  A NULL / unbuilt clip binds nothing.
//   - PAINT    : the cover dispatch fans out by cm_pattern_type_t -- LINEAR /
//     RADIAL bind the gradient LUT (texture(0)); SURFACE / RASTER flush the
//     source surface first then bind its colour texture (texture(0)) + a runtime
//     sampler (sampler(0)) WITHOUT double-premultiplying; MESH streams Gouraud
//     triangles as the coverage.
//   - A8 TARGET: when the fill target is an A8 (R8) surface, the SOLID cover uses
//     the CM_PIPE_COVER_SOLID_A8 variant so coverage lands in the single alpha
//     channel.
//
// Non-preserve cm_fill() / cm_stroke() (= the preserve encode + cm_path_reset)
// also live here, matching cairo.  Both just delegate to their _preserve form and
// then cm_new_path; the operator, clip, and -- for stroke -- the gstate dash are
// all honored inside that preserve encode (cm_stroke_preserve runs the dash
// pre-pass before cm_stroke_expand).
//
// See shaders/fill.metal for the matching programmable stages and the
// buffer/texture binding contract mirrored by the CM_BUF_*/CM_TEX_* defines.
// ============================================================================

#import <Metal/Metal.h>

#include "cm_internal.h"
#include <string.h>
#include <math.h>

/* ANTIALIAS_NONE single-sample path (BUG 7): when the encode runs in a 1-sample
 * frame (cm_frame_begin_single), the stencil pass must use the matching 1-sample
 * stencil pipeline (the shipping CM_PIPE_STENCIL_* are 4x MSAA and would mismatch
 * the 1-sample pass).  Declared here until promoted to cm_internal.h. */
extern bool  cm_frame_is_single_sample(cm_frame *f);
extern void *cm_device_stencil_pipeline_aa_none(cm_device *dev, bool evenodd);

// ---------------------------------------------------------------------------
// Binding indices -- MUST match shaders/fill.metal (and cm_compose.m's mirror).
// ---------------------------------------------------------------------------
#define CM_BUF_VERTS      0    /* device const cm_vec2f / cm_vtx_color*  [[buffer(0)]] */
#define CM_BUF_UNIFORMS   1    /* constant cm_uniforms&  uniforms        [[buffer(1)]] */
#define CM_TEX_GRAD_LUT   0    /* texture2d<float> gradient LUT (lin/rad) [[texture(0)]] */
#define CM_TEX_SOURCE     0    /* surface-pattern colour texture          [[texture(0)]] */
#define CM_SAMPLER_SOURCE 0    /* runtime sampler (surface)               [[sampler(0)]] */
/* The clip A8 mask binds at texture(1)/sampler(1) -- owned by cm_clip_bind(). */

// A cover quad is a 4-vertex triangle strip spanning the path's device bounds.
#define CM_COVER_QUAD_VERTS 4

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/** Fill the to_clip uniform from the surface dimensions: device px -> Metal clip
 *  space with the y-flip baked into a negative sy.  For a WxH target:
 *    clip.x = px * (2/W) - 1
 *    clip.y = 1 - py*(2/H) = py*(-2/H) + 1
 *  => to_clip = (2/W, -2/H, -1, +1). */
static inline void cm_fill_set_to_clip(cm_uniforms *u, int w, int h) {
    float fw = (w > 0) ? (float)w : 1.0f;
    float fh = (h > 0) ? (float)h : 1.0f;
    u->to_clip[0] =  2.0f / fw;   /* sx */
    u->to_clip[1] = -2.0f / fh;   /* sy (y flipped) */
    u->to_clip[2] = -1.0f;        /* tx */
    u->to_clip[3] =  1.0f;        /* ty */
}

/** Carry the CTM into the uniform's two float4 rows (for completeness; the
 *  shipping path pre-transforms on the CPU, so the GPU does not re-apply this).
 *    row0 = (xx, xy, x0, _)   row1 = (yx, yy, y0, _). */
static inline void cm_fill_set_ctm_rows(cm_uniforms *u, const cm_matrix_t *m) {
    u->ctm_row0[0] = (float)m->xx; u->ctm_row0[1] = (float)m->xy;
    u->ctm_row0[2] = (float)m->x0; u->ctm_row0[3] = 0.0f;
    u->ctm_row1[0] = (float)m->yx; u->ctm_row1[1] = (float)m->yy;
    u->ctm_row1[2] = (float)m->y0; u->ctm_row1[3] = 0.0f;
}

/** Write the 4 triangle-strip corners of the device-space bounding box into
 *  `quad`.  Strip order matches cm_compose.m / the original cover quad:
 *  (minx,miny) (maxx,miny) (minx,maxy) (maxx,maxy). */
static inline void cm_fill_fill_quad(cm_vec2f *quad,
                                     float minx, float miny,
                                     float maxx, float maxy) {
    quad[0].x = minx; quad[0].y = miny;
    quad[1].x = maxx; quad[1].y = miny;
    quad[2].x = minx; quad[2].y = maxy;
    quad[3].x = maxx; quad[3].y = maxy;
}

/** True when the fill target is an alpha-only surface (A8 -> R8 texture), so the
 *  SOLID cover must route through the A8 cover pipeline (coverage into .r). */
static inline bool cm_fill_target_is_a8(const cm_context_t *ctx) {
    return ctx && ctx->surface && ctx->surface->format == CM_FORMAT_A8;
}

// ===========================================================================
// cm_fill_encode
// ===========================================================================
//
// Encode a full stencil-then-cover fill of `path` (already device-space
// flattened by the caller) with the context's current paint, operator, and
// clip into the frame's render command encoder.  Returns CM_STATUS_SUCCESS on
// success (a degenerate / empty path is a successful no-op).
//
// The structure is the SAME two passes for every paint kind; only the cover
// pass's pipeline + bound resources + (for MESH) cover geometry differ:
//
//   1) bump-allocate + fill the stencil fan vertices (path contours);
//   2) bump-allocate + build the per-draw uniforms (paint + operator + to_clip);
//   3) resolve the operator-selected cover pipeline + the per-kind GPU resources
//      (gradient LUT / source texture+sampler / Gouraud triangle stream);
//   4) PASS 1 stencil (winding/parity), PASS 2 cover (test stencil + paint),
//      binding the clip mask to the cover stage.
//
cm_status_t
cm_fill_encode(cm_context_t *ctx, cm_frame *frame,
               const cm_path *path, cm_fill_rule_t rule)
{
    if (!ctx || !frame || !path) {
        return CM_STATUS_DEVICE_ERROR;
    }

    // The path must already be flattened (device space) by the caller
    // (cairo_metal.m drives flatten -> fill).  Nothing to fill if it produced no
    // geometry -- a valid no-op, e.g. an empty or fully-degenerate path.
    if (path->pts_count == 0 || path->contour_count == 0) {
        return CM_STATUS_SUCCESS;
    }

    // ---- how many stencil-fan vertices does the whole path need? -----------
    uint32_t fan_vtx = cm_path_fan_vertex_count(path);
    if (fan_vtx == 0) {
        // Every contour was degenerate (<3 points): no fillable area.
        return CM_STATUS_SUCCESS;
    }

    cm_device *dev = cm_frame_device(frame);
    if (!dev) {
        return CM_STATUS_DEVICE_ERROR;
    }
    id<MTLRenderCommandEncoder> enc =
        (__bridge id<MTLRenderCommandEncoder>)cm_frame_encoder(frame);
    if (!enc) {
        return CM_STATUS_DEVICE_ERROR;
    }

    // -----------------------------------------------------------------------
    // 1) Bump-allocate + fill the stencil-fan vertex buffer (no malloc).
    // -----------------------------------------------------------------------
    void    *fan_mtlbuf = NULL;
    uint32_t fan_offset = 0;
    cm_vec2f *fan_dst = (cm_vec2f *)cm_frame_alloc_verts(
        frame, (size_t)fan_vtx * sizeof(cm_vec2f), &fan_mtlbuf, &fan_offset);
    if (!fan_dst || !fan_mtlbuf) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }

    // Emit each contour's fan; cm_path_emit_fan returns the count it appended
    // (0 for a degenerate contour), so we advance the write cursor by it.  The
    // total is exactly fan_vtx, matching the allocation above.
    uint32_t written = 0;
    for (uint32_t ci = 0; ci < path->contour_count; ++ci) {
        uint32_t n = cm_path_emit_fan(path, ci, fan_dst + written);
        written += n;
    }
    // Defensive: never exceed the allocation (would corrupt the ring).
    if (written > fan_vtx) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }
    if (written == 0) {
        return CM_STATUS_SUCCESS;   // nothing fillable after all
    }

    // -----------------------------------------------------------------------
    // 2) Path device-space bounds (the cover quad for the quad-cover kinds).
    //    A zero-area bound is nothing to cover -- a valid no-op.
    // -----------------------------------------------------------------------
    float minx, miny, maxx, maxy;
    cm_path_bounds(path, &minx, &miny, &maxx, &maxy);
    if (!(maxx > minx) || !(maxy > miny)) {
        return CM_STATUS_SUCCESS;   // zero-area bounds: nothing to cover
    }

    // -----------------------------------------------------------------------
    // 3) Bump-allocate + build per-draw uniforms (shared by both passes).
    // -----------------------------------------------------------------------
    void    *uni_mtlbuf = NULL;
    uint32_t uni_offset = 0;
    cm_uniforms *u = (cm_uniforms *)cm_frame_alloc_uniforms(
        frame, sizeof(cm_uniforms), &uni_mtlbuf, &uni_offset);
    if (!u || !uni_mtlbuf) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }
    memset(u, 0, sizeof(*u));
    // Paint fields (paint_kind / grad_axis in device space / solid / pat_inv /
    // operator default / global_alpha default) come from the source; we then
    // write to_clip + ctm rows + the live operator LAST so they survive
    // regardless of how much of the struct cm_paint_fill_uniforms touches.
    cm_paint_fill_uniforms(&ctx->source, &ctx->ctm, u);
    cm_fill_set_to_clip(u, ctx->surface ? ctx->surface->width  : 0,
                           ctx->surface ? ctx->surface->height : 0);
    cm_fill_set_ctm_rows(u, &ctx->ctm);
    // Honor set_operator: the programmable-blend cover frags read this, and it is
    // the key cm_device_cover_pipeline selects the fixed-function blend state by.
    u->operator = (int)ctx->op;

    // -----------------------------------------------------------------------
    // 4) Resolve the paint kind + its GPU resources.
    //
    // paint_kind is what cm_paint_fill_uniforms derived (SOLID / LINEAR /
    // RADIAL / SURFACE / MESH).  Each kind may DOWNGRADE to SOLID if its GPU
    // resource is unavailable (LUT bake failed / no source texture / empty mesh)
    // so we never issue a draw that samples a nil texture -- exactly the
    // deterministic fallback cm_compose.m uses.
    // -----------------------------------------------------------------------
    cm_paint_kind paint_kind = (cm_paint_kind)u->paint_kind;

    id<MTLTexture>      src_lut  = nil;   // gradient LUT (LINEAR / RADIAL)
    id<MTLTexture>      src_tex  = nil;   // surface-pattern colour texture
    id<MTLSamplerState> src_samp = nil;   // runtime sampler for the surface
    bool                is_mesh  = false; // MESH: triangles ARE the coverage

    if (paint_kind == CM_PAINT_LINEAR || paint_kind == CM_PAINT_RADIAL) {
        if (ctx->source.pattern)
            src_lut = (__bridge id<MTLTexture>)cm_paint_gradient_lut(dev,
                                                                     ctx->source.pattern);
        if (!src_lut) {
            // LUT bake failed; fall back to solid so we still composite
            // something deterministic rather than sampling a nil texture.
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    } else if (paint_kind == CM_PAINT_SURFACE) {
        cm_surface_t *ssurf = ctx->source.pattern
                            ? cm_pattern_surface_texture(ctx->source.pattern) : NULL;
        if (ssurf) {
            // FLUSH THE SOURCE FIRST: a surface pattern may itself be a draw
            // target with pending GPU work (e.g. a push_group result); resolve it
            // so the texture we sample is coherent.  flush() is a no-op when the
            // source has no in-flight frame.  We must NOT flush our OWN target
            // surface here (that would end the frame we are encoding into), so
            // only flush a DIFFERENT source surface.
            if (ssurf != ctx->surface && ssurf != ctx->target)
                cm_surface_flush(ssurf);
            src_tex = (__bridge id<MTLTexture>)cm_surface_color_texture(ssurf);
        }
        if (src_tex) {
            cm_filter_t f = ctx->source.pattern ? ctx->source.pattern->filter
                                                : CM_FILTER_GOOD;
            cm_extend_t e = ctx->source.pattern ? ctx->source.pattern->extend
                                                : CM_EXTEND_NONE;
            src_samp = (__bridge id<MTLSamplerState>)cm_device_sampler(dev, f, e);
            // Texels are ALREADY premultiplied (cairo ARGB32 source); the surface
            // cover fragment does NOT premultiply again -- nothing to do here.
        } else {
            // No usable source texture: deterministic solid fallback.
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    } else if (paint_kind == CM_PAINT_MESH) {
        // MESH: the per-vertex Gouraud triangles emitted by cm_mesh.c ARE the
        // cover geometry; there is no bounding quad.  We still run the stencil
        // pass so the mesh paints only inside the fill path.
        is_mesh = (ctx->source.pattern != NULL);
        if (!is_mesh) {
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    }

    // -----------------------------------------------------------------------
    // 5) Resolve the cover pipeline DEFINITIVELY (before allocating cover
    //    geometry), settling the final paint_kind / is_mesh.
    //
    // The operator front-door (cm_compose_operator_pipeline ->
    // cm_device_cover_pipeline) is the single source of truth for the
    // (operator x aa x clip x paint-kind) variant, so every encode site selects
    // pipelines identically and set_operator is honored.  For the default OVER /
    // unclipped / BGRA + SOLID|LINEAR case the device scaffold resolves this to
    // exactly CM_PIPE_COVER_SOLID / _LINEAR, so the shipping path is preserved
    // byte-for-byte.
    //
    // The appended cover variants (RADIAL / SURFACE / GOURAUD / SOLID_A8) are
    // built lazily by the device; until a variant exists the hook falls back to
    // the SOLID cover.  A solid-cover fallback is fine for the quad kinds (it
    // just composites a solid colour), but the GOURAUD cover takes a WIDER
    // cm_vtx_color vertex, so drawing the mesh stream through a non-Gouraud
    // pipeline would misread vertices.  We therefore detect that fallback (the
    // hook handed back CM_PIPE_COVER_SOLID for a non-solid kind) and, for MESH,
    // collapse to the solid quad path instead of streaming Gouraud verts.
    // -----------------------------------------------------------------------
    bool aa_none = (ctx->antialias == CM_ANTIALIAS_NONE);
    // GPU per-pixel clip: only when a NON-RECTANGULAR clip with a built A8 mask is
    // active.  A purely-rectangular clip stays on the fast path (its bounding box
    // already constrains the draw) so the common case pays no clip-sample cost, and
    // a clip whose GPU mask could not be built must NOT select a *_clip fragment
    // (which would sample an unbound texture(1)); it degrades to the CPU-query clip.
    bool clip_on = (ctx->clip != NULL) && !ctx->clip->is_rectangle &&
                   (ctx->clip->mask_tex != NULL);

    // A8 target: SOLID coverage must land in the single alpha channel (R8).  We
    // special-case only SOLID into A8 (the manim A8 use is a coverage/clip mask
    // filled solid); other kinds keep their BGRA cover.
    bool want_a8_solid = (paint_kind == CM_PAINT_SOLID) && cm_fill_target_is_a8(ctx);

    id<MTLRenderPipelineState> ps_solid =
        (__bridge id<MTLRenderPipelineState>)cm_device_pipeline(dev, CM_PIPE_COVER_SOLID);

    id<MTLRenderPipelineState> ps_cover =
        (__bridge id<MTLRenderPipelineState>)
            cm_compose_operator_pipeline(dev, ctx->op, aa_none, clip_on, paint_kind);

    // Did the hook fall back to the plain solid cover for a non-solid kind?
    // (Either the variant is not built yet, or the device genuinely maps this
    // op/kind to the solid pipeline.)  Treat that as "solid cover".
    bool got_solid_cover = (ps_cover == ps_solid) || (ps_cover == nil);

    if (paint_kind != CM_PAINT_SOLID && got_solid_cover) {
        // The kind-specific cover is unavailable.  For the quad kinds we keep the
        // solid fallback (deterministic), dropping the now-unusable source
        // texture/LUT.  For MESH we MUST switch to the quad path (we cannot draw
        // the Gouraud stream through the solid pipeline).
        paint_kind    = CM_PAINT_SOLID;
        u->paint_kind = CM_PAINT_SOLID;
        src_lut = nil; src_tex = nil; src_samp = nil;
        is_mesh = false;
        // Re-evaluate the A8-solid request now that we are solid.
        want_a8_solid = cm_fill_target_is_a8(ctx);
        ps_cover      = ps_solid;
    }

    if (want_a8_solid) {
        // Dedicated A8 (R8) solid cover: writes the source COVERAGE ALPHA into the
        // single channel via cm_fs_cover_solid_a8 -- NOT the BGRA solid fragment's
        // premultiplied colour byte, which would store luminance (opaque
        // black/green -> 0 instead of 255).  Built/cached lazily + operator-aware
        // by the device (cm_device_pipeline(CM_PIPE_COVER_SOLID_A8) is never
        // populated -- the variant table owns it).  Falls back to the BGRA solid
        // only if the R8 variant is unavailable.
        id<MTLRenderPipelineState> ps_a8 =
            (__bridge id<MTLRenderPipelineState>)
                cm_device_cover_pipeline_a8(dev, ctx->op, aa_none, clip_on, CM_PAINT_SOLID);
        if (ps_a8) ps_cover = ps_a8;
    }
    if (!ps_cover) ps_cover = ps_solid;   // never issue a nil-pipeline draw

    // -----------------------------------------------------------------------
    // 6) Bump-allocate the cover geometry now that the kind is settled.
    //    MESH streams the Gouraud triangles (cm_vtx_color, wider than cm_vec2f,
    //    so its own ring sub-allocation); every other kind draws the device-space
    //    bounding quad.
    // -----------------------------------------------------------------------
    void    *mesh_mtlbuf  = NULL;
    uint32_t mesh_offset  = 0;
    uint32_t mesh_vtx     = 0;
    void    *quad_mtlbuf  = NULL;
    uint32_t quad_offset  = 0;

    if (is_mesh) {
        uint32_t mverts = cm_mesh_triangle_vertex_count(ctx->source.pattern, &ctx->ctm);
        cm_vtx_color *mdst = (mverts > 0)
            ? (cm_vtx_color *)cm_frame_alloc_verts(
                  frame, (size_t)mverts * sizeof(cm_vtx_color),
                  &mesh_mtlbuf, &mesh_offset)
            : NULL;
        if (mverts > 0 && (!mdst || !mesh_mtlbuf)) {
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        mesh_vtx = (mdst != NULL)
            ? cm_mesh_emit_triangles(ctx->source.pattern, &ctx->ctm, mdst) : 0;
        if (mesh_vtx > mverts) {        // emit must not exceed the size it asked for
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        if (mesh_vtx == 0) {
            // Empty tessellation: collapse to a solid quad fill so the stencilled
            // path still composites the solid fallback deterministically.
            is_mesh       = false;
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
            ps_cover      = ps_solid;
            if (cm_fill_target_is_a8(ctx)) {
                id<MTLRenderPipelineState> ps_a8 =
                    (__bridge id<MTLRenderPipelineState>)
                        cm_device_cover_pipeline_a8(dev, ctx->op, aa_none, clip_on,
                                                    CM_PAINT_SOLID);
                if (ps_a8) ps_cover = ps_a8;
            }
        }
    }
    if (!is_mesh) {
        cm_vec2f *quad = (cm_vec2f *)cm_frame_alloc_verts(
            frame, (size_t)CM_COVER_QUAD_VERTS * sizeof(cm_vec2f),
            &quad_mtlbuf, &quad_offset);
        if (!quad || !quad_mtlbuf) {
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        cm_fill_fill_quad(quad, minx, miny, maxx, maxy);
    }

    // -----------------------------------------------------------------------
    // 7) Resolve the stencil pipeline + the two depth-stencil states (O(1)).
    // -----------------------------------------------------------------------
    cm_pipe_id stencil_pipe = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_PIPE_STENCIL_EVENODD : CM_PIPE_STENCIL_NONZERO;
    cm_dss_id  stencil_dss  = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_DSS_STENCIL_WRITE_EVENODD : CM_DSS_STENCIL_WRITE_NONZERO;
    cm_dss_id  cover_dss    = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_DSS_COVER_TEST_EVENODD : CM_DSS_COVER_TEST_NONZERO;

    // ANTIALIAS_NONE renders into a 1-sample pass: use the 1-sample stencil
    // pipeline (the MSAA CM_PIPE_STENCIL_* would mismatch the pass's sample count).
    // The cover pipeline already came from the aa_none variant cells above, and the
    // depth-stencil STATES are sample-count-independent so they are reused.
    id<MTLRenderPipelineState> ps_stencil =
        cm_frame_is_single_sample(frame)
            ? (__bridge id<MTLRenderPipelineState>)
                  cm_device_stencil_pipeline_aa_none(dev, rule == CM_FILL_RULE_EVEN_ODD)
            : (__bridge id<MTLRenderPipelineState>)cm_device_pipeline(dev, stencil_pipe);
    id<MTLDepthStencilState>   ds_stencil =
        (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, stencil_dss);
    id<MTLDepthStencilState>   ds_cover =
        (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, cover_dss);
    if (!ps_stencil || !ds_stencil || !ps_cover || !ds_cover) {
        ctx->status = CM_STATUS_DEVICE_ERROR;
        return CM_STATUS_DEVICE_ERROR;
    }

    // Two-sided stencil (NONZERO) needs BOTH faces rasterized so the front/back
    // incr/decr-wrap ops can accumulate winding; never cull.  Front-facing =
    // CCW matches the "fans emitted CCW" convention in DESIGN.md (and the
    // cover-pass !=0 test is sign-agnostic, so the exact front/back->incr/decr
    // assignment in the DSS does not change the result).
    [enc setCullMode:MTLCullModeNone];
    [enc setFrontFacingWinding:MTLWindingCounterClockwise];

    // =======================================================================
    // PASS 1 -- STENCIL (no colour; pipeline masks colour writes off)
    // =======================================================================
    [enc setRenderPipelineState:ps_stencil];
    [enc setDepthStencilState:ds_stencil];
    // Reference 0: harmless for the write ops (incr/decr-wrap, invert ignore it)
    // and is what the cover pass compares against, so set it once consistently.
    [enc setStencilReferenceValue:0];

    [enc setVertexBuffer:(__bridge id<MTLBuffer>)fan_mtlbuf
                  offset:fan_offset
                 atIndex:CM_BUF_VERTS];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                  offset:uni_offset
                 atIndex:CM_BUF_UNIFORMS];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle
            vertexStart:0
            vertexCount:written];

    // =======================================================================
    // PASS 2 -- COVER (test stencil + zero it; write premultiplied paint)
    // =======================================================================
    [enc setRenderPipelineState:ps_cover];
    [enc setDepthStencilState:ds_cover];
    // Stencil reference already 0 from the stencil pass; the cover DSS tests
    // NotEqual(ref=0) (nonzero) or NotEqual(ref=0, readMask=1) (even-odd).

    // Vertex buffer(0): the cover quad for quad kinds, or the Gouraud triangle
    // stream for MESH (cm_vs_cover_color reads cm_vtx_color from buffer(0)).
    if (is_mesh) {
        [enc setVertexBuffer:(__bridge id<MTLBuffer>)mesh_mtlbuf
                      offset:mesh_offset
                     atIndex:CM_BUF_VERTS];
    } else {
        [enc setVertexBuffer:(__bridge id<MTLBuffer>)quad_mtlbuf
                      offset:quad_offset
                     atIndex:CM_BUF_VERTS];
    }
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                  offset:uni_offset
                 atIndex:CM_BUF_UNIFORMS];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                    offset:uni_offset
                   atIndex:CM_BUF_UNIFORMS];

    // Source texture / LUT at texture(0) (+ runtime sampler for SURFACE).  MESH
    // and SOLID bind no source texture (their colour is per-vertex / uniform).
    if (src_lut) {
        [enc setFragmentTexture:src_lut atIndex:CM_TEX_GRAD_LUT];
    } else if (src_tex) {
        [enc setFragmentTexture:src_tex atIndex:CM_TEX_SOURCE];
        if (src_samp) [enc setFragmentSamplerState:src_samp atIndex:CM_SAMPLER_SOURCE];
    }

    // Bind the active clip A8 coverage plane + its sampler to the cover fragment
    // stage (texture(1)/sampler(1)); the cover frags multiply their coverage by
    // the sampled mask.  No-op when unclipped or the GPU mask was not built.
    cm_clip_bind((__bridge void *)enc, ctx->clip);

    if (is_mesh) {
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:mesh_vtx];
    } else {
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:CM_COVER_QUAD_VERTS];
    }

    // Record the pipeline group of the draw we just finished so the batching
    // driver in cairo_metal.m can coalesce runs that share a cover pipeline
    // (e.g. many solid fills) and skip redundant state churn within the frame.
    ctx->last_pipeline_group = paint_kind;

    ctx->status = CM_STATUS_SUCCESS;
    return CM_STATUS_SUCCESS;
}

// ===========================================================================
// Non-preserve fill / stroke (= the preserve variant + clear the path)
// ===========================================================================
//
// cairo_fill / cairo_stroke are exactly the _preserve variant followed by an
// implicit new_path (the path is consumed).
//
//   cm_fill   : cm_fill_preserve already flattens + runs cm_fill_encode with the
//               current source + fill rule, and cm_fill_encode now honors the
//               operator + clip + per-kind paint dispatch (LINEAR/RADIAL/SURFACE/
//               MESH + A8), so the non-preserve form is just that + new_path.
//   cm_stroke : cm_stroke_preserve (cairo_metal.m) does the WHOLE stroke encode --
//               flatten -> dash pre-pass (cm_dash_prepass, honoring an active
//               cairo_set_dash by chopping BEFORE cm_stroke_expand) -> expand ->
//               NONZERO cm_fill_encode with the operator + clip -- so the
//               non-preserve form is just that + new_path, exactly cairo's
//               stroke == stroke_preserve + new_path with no separate dashed fork.

void cm_fill(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_fill_preserve(ctx);     // flatten + stencil-then-cover (operator + clip)
    cm_new_path(ctx);          // cairo_fill CONSUMES the path
}

void cm_stroke(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_stroke_preserve(ctx);   // flatten -> dash pre-pass -> expand -> NONZERO fill
    cm_new_path(ctx);          // cairo_stroke CONSUMES the path
}
