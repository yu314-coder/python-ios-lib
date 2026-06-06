/*
 * cm_compose.m  --  CairoMetal operator + paint + mask + paint_with_alpha
 * ============================================================================
 *
 * MODULE OWNER of cm_internal.h "MODULE: cm_compose.m" -- the operator / paint /
 * mask encode path.  Where cm_fill.m rasterizes a *shape* (stencil-then-cover),
 * this file rasterizes a *region* (the clip): paint and mask have no path, so
 * there is NO stencil pass.  Coverage is the whole clip, so the work is a single
 * cover-quad draw spanning the clip extents (the surface bounds when unclipped)
 * with the chosen operator pipeline, the packed source/mask uniforms, the global
 * alpha, and -- once cm_clip.m builds the A8 plane -- the clip-coverage multiply.
 *
 *   cm_paint            : fill the source everywhere in the clip.
 *   cm_paint_with_alpha : same, scaled by a constant group alpha.
 *   cm_mask(pattern)    : composite source * mask-pattern-alpha over the clip.
 *   cm_mask_surface     : wrap a surface as a translated SurfacePattern + mask.
 *
 * It ALSO owns cm_compose_operator_pipeline(): the operator -> cover-pipeline
 * lookup hook cm_fill.m / cm_stroke.m call so set_operator is honored.  cairo
 * operators 0..13 are fixed-function blends (Porter-Duff: a blend-state choice
 * the device cover pipeline bakes per operator); 14..28 are the separable /
 * non-separable blend modes, which the programmable-blend cover fragments
 * implement by reading the `operator` uniform.  Both routes funnel through
 * cm_device_cover_pipeline(dev, op, aa_none, clip, kind), which this hook is the
 * single front door to (so every encode site selects pipelines identically).
 *
 * ----------------------------------------------------------------------------
 * GPU plumbing -- MATCHES cm_fill.m EXACTLY
 * ----------------------------------------------------------------------------
 * This unit talks to Metal only through the opaque void* handles vended by
 * cm_device.m / cm_surface.m: the per-frame command encoder, the bump-allocated
 * vertex + uniform ring (cm_frame_alloc_*), the persistent cover pipelines, and
 * cm_device_sampler for the surface/mask textures.  It builds NOTHING per draw
 * beyond ring sub-allocations.  The buffer/texture binding indices and the
 * to_clip / cover-quad packing are the same ones cm_fill.m uses (and mirror
 * shaders/fill.metal), kept in lock-step here.
 *
 * The cover pass for paint/mask uses a depth-stencil state that ALWAYS passes
 * and never touches the stencil buffer (there is no winding to test): binding a
 * nil MTLDepthStencilState selects Metal's default (compare Always, stencil
 * disabled), which is exactly the full-coverage semantics we want and leaves the
 * shared stencil attachment untouched for the next batched shape draw.
 *
 * Premultiplied OVER blending on the cover pipelines (configured once in
 * cm_device.m) means the fragment outputs premultiplied colour; the alpha-
 * weighting of paint_with_alpha is therefore applied to the (non-premultiplied)
 * source BEFORE the shader premultiplies -- see cm_apply_alpha_to_source below.
 *
 * SCAFFOLD INTERLOCK: cm_clip.m currently leaves clip->mask_tex == NULL (the A8
 * plane is not built yet) and cm_clip_bind() is a no-op, so the clip multiply is
 * latent: paint/mask cover the clip's AABB exactly, which is the correct result
 * for the rectangular clips manim uses and a conservative superset otherwise.
 * When cm_clip.m starts producing an A8 mask, the cm_clip_bind() call already
 * wired below binds it with no change here.
 * ============================================================================
 */

#import <Metal/Metal.h>

#include "cm_internal.h"
#include <string.h>
#include <math.h>

/* ---------------------------------------------------------------------------
 * Binding indices -- MUST match shaders/fill.metal (and cm_fill.m's mirror).
 * --------------------------------------------------------------------------- */
#define CM_BUF_VERTS      0   /* device const cm_vec2f*  vertices  [[buffer(0)]] */
#define CM_BUF_UNIFORMS   1   /* constant cm_uniforms&   uniforms  [[buffer(1)]] */
#define CM_TEX_GRAD_LUT   0   /* gradient LUT (linear/radial)      [[texture(0)]] */
#define CM_TEX_SOURCE     0   /* surface source / mask texture     [[texture(0)]] */
#define CM_SAMPLER_SOURCE 0   /* runtime sampler (surface/mask)    [[sampler(0)]] */

/* A cover quad is a 4-vertex triangle strip spanning the clip-extents box. */
#define CM_COVER_QUAD_VERTS 4

/* ===========================================================================
 * Cross-module seam (see the BUILD note at the bottom of this file)
 * ---------------------------------------------------------------------------
 * The per-surface active-frame registry (lazy "one MTLCommandBuffer per frame",
 * ended by cm_surface_flush) lives in cairo_metal.m, where cm_fill_preserve /
 * cm_stroke_preserve acquire their frame via cm_glue_frame_for_surface().  paint
 * and mask MUST batch into that SAME command buffer (and be ended by the same
 * flush), so we acquire through the same registry rather than calling
 * cm_frame_begin() directly (which would open a second, untracked command buffer
 * that flush never ends).
 *
 * It is declared `weak` so a build in which cairo_metal.m has not yet exported
 * the symbol (it is presently `static`) still links; in that case the acquire
 * resolves to NULL and paint/mask degrade to a clean no-op + DEVICE_ERROR rather
 * than crashing.  The Build phase reconciles this by giving cairo_metal.m's
 * cm_glue_frame_for_surface external linkage (one keyword), matching the already-
 * exported cm_glue_end_frame_for_surface it sits beside. */
extern cm_frame *cm_glue_frame_for_surface(cm_surface_t *surface, bool create)
    __attribute__((weak));

/* ===========================================================================
 * Small helpers (kept byte-identical to cm_fill.m where shared)
 * =========================================================================== */

/* device px -> Metal clip space, y-flip baked into a negative sy.  For WxH:
 *   to_clip = (2/W, -2/H, -1, +1).  Identical to cm_fill.m's cm_fill_set_to_clip. */
static inline void cm_compose_set_to_clip(cm_uniforms *u, int w, int h)
{
    float fw = (w > 0) ? (float)w : 1.0f;
    float fh = (h > 0) ? (float)h : 1.0f;
    u->to_clip[0] =  2.0f / fw;   /* sx */
    u->to_clip[1] = -2.0f / fh;   /* sy (y flipped) */
    u->to_clip[2] = -1.0f;        /* tx */
    u->to_clip[3] =  1.0f;        /* ty */
}

/* The device-space box paint/mask must cover: the clip's device AABB clamped to
 * the surface, or the whole surface when unclipped.  Returns false (caller
 * no-ops) if the box is empty.  Mirrors cm_fill.m's bounds->quad handoff. */
static bool cm_compose_cover_box(cm_context_t *ctx,
                                 float *minx, float *miny,
                                 float *maxx, float *maxy)
{
    float sw = (float)(ctx->surface ? ctx->surface->width  : 0);
    float sh = (float)(ctx->surface ? ctx->surface->height : 0);

    float x1 = 0.0f, y1 = 0.0f, x2 = sw, y2 = sh;
    if (ctx->clip) {
        /* Clip device AABB (cm_clip.m owns the values; cm_clip_extents_dev reads
         * them through the same struct). */
        float cx1, cy1, cx2, cy2;
        cm_clip_extents_dev(ctx->clip, &cx1, &cy1, &cx2, &cy2);
        /* Intersect with the surface bounds; a degenerate (all-zero) clip AABB
         * means "no recorded extents yet" -> fall back to the surface box so the
         * scaffold clip (mask_tex == NULL) still paints the whole target. */
        if (cx2 > cx1 && cy2 > cy1) {
            if (cx1 > x1) x1 = cx1;
            if (cy1 > y1) y1 = cy1;
            if (cx2 < x2) x2 = cx2;
            if (cy2 < y2) y2 = cy2;
        }
    }

    if (x1 < 0.0f) x1 = 0.0f;
    if (y1 < 0.0f) y1 = 0.0f;
    if (x2 > sw)   x2 = sw;
    if (y2 > sh)   y2 = sh;

    if (!(x2 > x1) || !(y2 > y1)) return false;   /* empty cover region */

    *minx = x1; *miny = y1; *maxx = x2; *maxy = y2;
    return true;
}

/* Write the 4 triangle-strip corners of the device-space box into `quad`.
 * Strip order matches cm_fill.m: (minx,miny)(maxx,miny)(minx,maxy)(maxx,maxy). */
static inline void cm_compose_fill_quad(cm_vec2f *quad,
                                        float minx, float miny,
                                        float maxx, float maxy)
{
    quad[0].x = minx; quad[0].y = miny;
    quad[1].x = maxx; quad[1].y = miny;
    quad[2].x = minx; quad[2].y = maxy;
    quad[3].x = maxx; quad[3].y = maxy;
}

/* Fold a constant group alpha into a NON-premultiplied source.  paint_with_alpha
 * multiplies the source's alpha (cairo: "paint ... using the alpha value").  The
 * cover fragment premultiplies on output, so scaling .a here yields a correctly
 * weighted premultiplied result on the shipping solid/linear pipelines without a
 * shader change.  global_alpha is also carried in the uniform for the
 * programmable-blend fragments. */
static inline void cm_apply_alpha_to_source(cm_uniforms *u, float alpha)
{
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 1.0f) alpha = 1.0f;
    u->global_alpha = alpha;
    if (u->paint_kind == CM_PAINT_SOLID)
        u->solid.a *= alpha;
    /* For LINEAR/RADIAL/SURFACE the per-texel alpha lives in the LUT/texture; the
     * programmable-blend path applies global_alpha from the uniform.  The shipping
     * shaders ignore it, so a non-1 alpha on a gradient source is approximate
     * until the alpha-aware cover variants are wired -- documented, not silent. */
}

/* True for an opaque-or-degenerate source we can skip entirely (fully
 * transparent solid contributes nothing under any Porter-Duff "over"-family op).
 * Conservative: only skips SOLID with a==0, which is always a no-op for OVER. */
static inline bool cm_source_is_noop(const cm_uniforms *u, cm_operator_t op)
{
    if (op == CM_OPERATOR_CLEAR) return false;       /* clear always writes */
    if (op != CM_OPERATOR_OVER)  return false;       /* be safe for others  */
    return (u->paint_kind == CM_PAINT_SOLID) && (u->solid.a <= 0.0f);
}

/* ===========================================================================
 * Core cover-quad encode shared by paint and mask
 * ---------------------------------------------------------------------------
 * Encodes a single full-clip cover draw with the operator-selected pipeline.
 * `mask_pattern` != NULL routes the mask fragment (source * mask-alpha); NULL
 * routes the paint fragment for the source kind.  `global_alpha` weights the
 * source (paint_with_alpha; 1.0 for plain paint/mask).
 * =========================================================================== */
static cm_status_t
cm_compose_cover(cm_context_t *ctx, cm_frame *frame,
                 cm_pattern_t *mask_pattern, double global_alpha)
{
    if (!ctx || !frame) return CM_STATUS_DEVICE_ERROR;

    cm_device *dev = cm_frame_device(frame);
    if (!dev) return CM_STATUS_DEVICE_ERROR;
    id<MTLRenderCommandEncoder> enc =
        (__bridge id<MTLRenderCommandEncoder>)cm_frame_encoder(frame);
    if (!enc) return CM_STATUS_DEVICE_ERROR;

    /* ---- the device-space box to cover (clip AABB / surface) -------------- */
    float minx, miny, maxx, maxy;
    if (!cm_compose_cover_box(ctx, &minx, &miny, &maxx, &maxy))
        return CM_STATUS_SUCCESS;                 /* empty clip: nothing to do */

    /* ---- per-draw uniforms (paint fields from the source) ---------------- */
    void    *uni_mtlbuf = NULL;
    uint32_t uni_offset = 0;
    cm_uniforms *u = (cm_uniforms *)cm_frame_alloc_uniforms(
        frame, sizeof(cm_uniforms), &uni_mtlbuf, &uni_offset);
    if (!u || !uni_mtlbuf) { ctx->status = CM_STATUS_NO_MEMORY; return CM_STATUS_NO_MEMORY; }

    memset(u, 0, sizeof(*u));
    cm_paint_fill_uniforms(&ctx->source, &ctx->ctm, u);
    cm_compose_set_to_clip(u, ctx->surface ? ctx->surface->width  : 0,
                              ctx->surface ? ctx->surface->height : 0);
    u->operator     = (int)ctx->op;
    u->global_alpha = 1.0f;
    cm_apply_alpha_to_source(u, (float)global_alpha);

    /* Early out for a provably-empty contribution (transparent solid OVER). */
    if (!mask_pattern && cm_source_is_noop(u, ctx->op))
        return CM_STATUS_SUCCESS;

    /* ---- resolve the source's GPU resources (LUT / surface texture) ------ */
    cm_paint_kind paint_kind = (cm_paint_kind)u->paint_kind;

    id<MTLTexture>      src_lut  = nil;   /* gradient LUT (linear/radial)        */
    id<MTLTexture>      src_tex  = nil;   /* surface-pattern colour texture       */
    id<MTLSamplerState> src_samp = nil;   /* runtime sampler for surface/mask     */

    if (paint_kind == CM_PAINT_LINEAR || paint_kind == CM_PAINT_RADIAL) {
        if (ctx->source.pattern)
            src_lut = (__bridge id<MTLTexture>)cm_paint_gradient_lut(dev,
                                                                     ctx->source.pattern);
        if (!src_lut) {            /* LUT bake failed -> deterministic solid */
            paint_kind     = CM_PAINT_SOLID;
            u->paint_kind  = CM_PAINT_SOLID;
        }
    } else if (paint_kind == CM_PAINT_SURFACE) {
        cm_surface_t *ssurf = ctx->source.pattern
                            ? cm_pattern_surface_texture(ctx->source.pattern) : NULL;
        if (ssurf)
            src_tex = (__bridge id<MTLTexture>)cm_surface_color_texture(ssurf);
        if (src_tex) {
            cm_filter_t f = ctx->source.pattern ? ctx->source.pattern->filter
                                                : CM_FILTER_GOOD;
            cm_extend_t e = ctx->source.pattern ? ctx->source.pattern->extend
                                                : CM_EXTEND_NONE;
            src_samp = (__bridge id<MTLSamplerState>)cm_device_sampler(dev, f, e);
        } else {
            /* No usable source texture: fall back to solid so we still composite
             * something deterministic rather than sampling a nil texture. */
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    }

    /* ---- the mask pattern's GPU resources (cm_mask only) ----------------- */
    id<MTLTexture>      mask_tex  = nil;
    id<MTLSamplerState> mask_samp = nil;
    if (mask_pattern) {
        u->mask_kind = (int)mask_pattern->kind;
        if (mask_pattern->kind == CM_PAINT_SURFACE) {
            cm_surface_t *msurf = cm_pattern_surface_texture(mask_pattern);
            if (msurf)
                mask_tex = (__bridge id<MTLTexture>)cm_surface_color_texture(msurf);
            mask_samp = (__bridge id<MTLSamplerState>)cm_device_sampler(
                dev, mask_pattern->filter, mask_pattern->extend);

            /* Tell cm_fs_mask WHICH channel carries the mask coverage.  cairo's
             * cairo_mask composites the source THROUGH the mask surface's alpha.
             * An A8 mask is stored as an R8 texture whose single (.r) channel IS
             * that coverage -- sampling .a of an R8 texture returns a constant 1.0,
             * so the shader must read .r for an A8 mask.  A colour (ARGB32) mask is
             * premultiplied, so its coverage is the real alpha channel (.a).  We
             * repurpose mask_kind (unused elsewhere) as that selector:
             *   0 == coverage in .r (A8 / alpha-only surface)
             *   1 == coverage in .a (colour surface) */
            bool mask_is_a8 = (msurf && msurf->format == CM_FORMAT_A8);
            u->mask_kind = mask_is_a8 ? 0 : 1;

            /* Pack the inverse mask-pattern->device matrix into pat_inv rows so
             * cm_fs_mask maps device fragments back into the mask's texel space
             * (the same rows cm_paint.m packs for a SURFACE source).  The mask's
             * pattern matrix is user->pattern; compose with the inverse CTM to get
             * device->pattern, which is what cm_to_pattern() in the shader wants. */
            cm_matrix_t dev_to_user = ctx->ctm;
            if (cm_matrix_invert(&dev_to_user) == CM_STATUS_SUCCESS) {
                cm_matrix_t dev_to_pat;
                /* pattern->matrix maps user->pattern; apply dev->user THEN
                 * user->pattern: dev_to_pat = pattern_matrix * dev_to_user. */
                cm_matrix_multiply(&dev_to_pat, &dev_to_user, &mask_pattern->matrix);
                u->pat_inv_row0[0] = (float)dev_to_pat.xx;
                u->pat_inv_row0[1] = (float)dev_to_pat.xy;
                u->pat_inv_row0[2] = (float)dev_to_pat.x0;
                u->pat_inv_row0[3] = 0.0f;
                u->pat_inv_row1[0] = (float)dev_to_pat.yx;
                u->pat_inv_row1[1] = (float)dev_to_pat.yy;
                u->pat_inv_row1[2] = (float)dev_to_pat.y0;
                u->pat_inv_row1[3] = 0.0f;
            }
        }
        /* A solid mask is just a constant alpha: fold it into the source alpha so
         * the plain cover path renders it correctly with no mask texture bind. */
        if (mask_pattern->kind == CM_PAINT_SOLID) {
            cm_apply_alpha_to_source(u, mask_pattern->solid.a * (float)global_alpha);
            mask_pattern = NULL;    /* handled as alpha; take the paint route */
        }
    }

    /* ---- select the cover pipeline via the operator hook ----------------- */
    /* Antialias-none and clip flags feed the variant key; MSAA is the shipping
     * AA path so aa_none is false.  GPU per-pixel clip (a *_clip cover fragment
     * that samples the A8 clip plane) is selected ONLY for a NON-RECTANGULAR clip
     * whose A8 mask was actually built: a rectangular clip is already confined by
     * cm_compose_cover_box clamping the cover quad to the clip AABB (the fast
     * path), and a clip whose mask could not be built must not select a *_clip
     * fragment that would sample an unbound texture(1).  cm_clip_bind below binds
     * the mask + sampler for the *_clip fragment. */
    bool aa_none = (ctx->antialias == CM_ANTIALIAS_NONE);
    bool clip_on = (ctx->clip != NULL) && !ctx->clip->is_rectangle &&
                   (ctx->clip->mask_tex != NULL);

    /* For the mask draw we want the dedicated source*mask-alpha cover variant
     * (cm_fs_mask): it modulates the CURRENT SOURCE colour by the mask's coverage.
     * Routing through the SURFACE-family fragment instead (the old scaffold) would
     * sample the mask texture AS the colour and drop the source entirely -- the
     * mask_surface() colour bug.  pipe_kind tracks the SOURCE kind for the non-mask
     * (paint) path and for the batching group. */
    cm_paint_kind pipe_kind = paint_kind;

    /* A8 (R8) target: a SOLID source must use the dedicated A8 cover pipeline so
     * the single channel receives the source COVERAGE ALPHA (cm_fs_cover_solid_a8)
     * rather than the BGRA solid fragment's premultiplied colour byte (which would
     * store luminance -- opaque black/green -> 0 instead of 255).  This mirrors
     * cm_fill.m's want_a8_solid routing.  Only SOLID is special-cased (matching the
     * fill path); other kinds keep the BGRA cover.  Falls back to the BGRA selector
     * if the A8 variant is unavailable (still a usable, if colour-storing, draw).
     * A mask draw never targets A8 here, so the mask route takes precedence. */
    bool target_is_a8 = (ctx->surface && ctx->surface->format == CM_FORMAT_A8);
    bool want_a8_solid = target_is_a8 && !mask_pattern && (pipe_kind == CM_PAINT_SOLID);

    id<MTLRenderPipelineState> ps_cover = nil;
    if (mask_pattern) {
        /* Source (solid) * mask coverage, composited with the current operator. */
        ps_cover = (__bridge id<MTLRenderPipelineState>)
            cm_device_cover_pipeline_mask(dev, ctx->op, aa_none, clip_on);
    }
    if (!ps_cover && want_a8_solid) {
        ps_cover = (__bridge id<MTLRenderPipelineState>)
            cm_device_cover_pipeline_a8(dev, ctx->op, aa_none, clip_on, CM_PAINT_SOLID);
    }
    if (!ps_cover) {
        ps_cover = (__bridge id<MTLRenderPipelineState>)
            cm_compose_operator_pipeline(dev, ctx->op, aa_none, clip_on, pipe_kind);
    }
    if (!ps_cover) {
        /* Last-resort fallback to the always-built solid cover pipeline so a
         * missing variant never aborts the whole frame. */
        ps_cover = (__bridge id<MTLRenderPipelineState>)
                       cm_device_pipeline(dev, CM_PIPE_COVER_SOLID);
        paint_kind    = CM_PAINT_SOLID;
        u->paint_kind = CM_PAINT_SOLID;
        src_lut = nil; src_tex = nil; mask_tex = nil; mask_pattern = NULL;
    }
    if (!ps_cover) { ctx->status = CM_STATUS_DEVICE_ERROR; return CM_STATUS_DEVICE_ERROR; }

    /* ---- bump-allocate + fill the cover quad ----------------------------- */
    void    *quad_mtlbuf = NULL;
    uint32_t quad_offset = 0;
    cm_vec2f *quad = (cm_vec2f *)cm_frame_alloc_verts(
        frame, (size_t)CM_COVER_QUAD_VERTS * sizeof(cm_vec2f),
        &quad_mtlbuf, &quad_offset);
    if (!quad || !quad_mtlbuf) { ctx->status = CM_STATUS_NO_MEMORY; return CM_STATUS_NO_MEMORY; }
    cm_compose_fill_quad(quad, minx, miny, maxx, maxy);

    /* ======================================================================
     * COVER draw (no stencil pass; full-clip coverage)
     * ======================================================================
     * Bind a nil depth-stencil state == Metal default (compare Always, stencil
     * disabled): always pass, never write/clear the shared stencil attachment.
     * Cull none + CCW winding to match the rest of the encoder's convention. */
    [enc setRenderPipelineState:ps_cover];
    [enc setDepthStencilState:nil];
    [enc setStencilReferenceValue:0];
    [enc setCullMode:MTLCullModeNone];
    [enc setFrontFacingWinding:MTLWindingCounterClockwise];

    [enc setVertexBuffer:(__bridge id<MTLBuffer>)quad_mtlbuf
                  offset:quad_offset
                 atIndex:CM_BUF_VERTS];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                  offset:uni_offset
                 atIndex:CM_BUF_UNIFORMS];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                    offset:uni_offset
                   atIndex:CM_BUF_UNIFORMS];

    /* Source texture/LUT at texture(0). */
    if (src_lut) {
        [enc setFragmentTexture:src_lut atIndex:CM_TEX_GRAD_LUT];
    } else if (mask_pattern && mask_tex) {
        /* mask cover variant samples the mask in texture(0). */
        [enc setFragmentTexture:mask_tex atIndex:CM_TEX_SOURCE];
        if (mask_samp) [enc setFragmentSamplerState:mask_samp atIndex:CM_SAMPLER_SOURCE];
    } else if (src_tex) {
        [enc setFragmentTexture:src_tex atIndex:CM_TEX_SOURCE];
        if (src_samp) [enc setFragmentSamplerState:src_samp atIndex:CM_SAMPLER_SOURCE];
    }

    /* Bind the clip A8 coverage plane + its sampler to the cover fragment stage.
     * cm_clip_bind is presently a no-op (mask_tex still NULL), so this is a
     * forward-wired hook that activates the moment cm_clip.m builds the plane. */
    cm_clip_bind((__bridge void *)enc, ctx->clip);

    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
            vertexStart:0
            vertexCount:CM_COVER_QUAD_VERTS];

    /* Record the cover pipeline group so the batching driver coalesces runs that
     * share a cover pipeline (consistent with cm_fill.m). */
    ctx->last_pipeline_group = paint_kind;

    ctx->status = CM_STATUS_SUCCESS;
    return CM_STATUS_SUCCESS;
}

/* ===========================================================================
 * Internal encode entry points (cm_internal.h contract)
 * =========================================================================== */
cm_status_t cm_compose_paint(cm_context_t *ctx, cm_frame *frame, double global_alpha)
{
    if (!ctx) return CM_STATUS_NO_MEMORY;
    if (!frame) return CM_STATUS_DEVICE_ERROR;
    return cm_compose_cover(ctx, frame, /*mask_pattern=*/NULL, global_alpha);
}

cm_status_t cm_compose_mask(cm_context_t *ctx, cm_frame *frame, cm_pattern_t *mask)
{
    if (!ctx) return CM_STATUS_NO_MEMORY;
    if (!frame) return CM_STATUS_DEVICE_ERROR;
    if (!mask) {
        /* cairo_mask with a NULL pattern is a programming error; treat as a
         * plain paint so callers still get the source over the clip. */
        return cm_compose_cover(ctx, frame, NULL, 1.0);
    }
    return cm_compose_cover(ctx, frame, mask, 1.0);
}

/* ---------------------------------------------------------------------------
 * Operator -> cover-pipeline lookup hook (used by cm_fill / cm_stroke too).
 *
 * The SINGLE front door to cm_device_cover_pipeline so every encode site (fill,
 * stroke, paint, mask) selects the (operator x aa x clip x paint-kind) variant
 * identically.  cairo ops 0..13 are fixed-function Porter-Duff blends (the device
 * bakes the per-operator MTLRenderPipelineColorAttachment blend state); 14..28
 * are the separable/non-separable blend modes the programmable-blend cover
 * fragments resolve from the `operator` uniform.  Both are the device's job to
 * realize; this hook just normalizes the call + clamps the operator to the valid
 * cairo range so an out-of-range value can never index a bogus pipeline.
 * --------------------------------------------------------------------------- */
void *cm_compose_operator_pipeline(cm_device *dev, cm_operator_t op,
                                   bool aa_none, bool clip, cm_paint_kind kind)
{
    if (!dev) return NULL;
    if ((int)op < (int)CM_OPERATOR_CLEAR)        op = CM_OPERATOR_CLEAR;
    if ((int)op > (int)CM_OPERATOR_HSL_LUMINOSITY) op = CM_OPERATOR_OVER;
    return cm_device_cover_pipeline(dev, op, aa_none, clip, kind);
}

/* ===========================================================================
 * Public API
 * ---------------------------------------------------------------------------
 * cairo has no explicit begin-frame: drawing just happens and surface.flush()
 * commits it.  We acquire (lazily begin) the surface's single per-frame command
 * buffer through the same registry cm_fill_preserve / cm_stroke_preserve use, so
 * paint/mask batch into it and cm_surface_flush ends it -- see the seam note up
 * top.  An empty path is irrelevant here (paint/mask cover the clip, not a path).
 * =========================================================================== */

/* ANTIALIAS_NONE per-draw frame helpers (BUG 7), owned by cairo_metal.m: acquire
 * the right frame (batched MSAA, or an immediate 1-sample AA-none pass) and end an
 * immediate frame.  Declared weak so a build where cairo_metal.m has not yet
 * exported them still links and degrades to the registry frame. */
extern cm_frame *cm_glue_frame_for_draw(cm_context_t *ctx, bool *out_immediate)
    __attribute__((weak));
extern void      cm_glue_end_draw_frame(cm_frame *frame, bool immediate)
    __attribute__((weak));

/* Acquire the surface's draw frame (batched MSAA or, for ANTIALIAS_NONE, an
 * immediate 1-sample frame), set the sticky context status on failure, and return
 * NULL so the caller bails.  *out_immediate tells the caller it must end the frame
 * itself via cm_glue_end_draw_frame (an AA-none frame is not in the registry). */
static cm_frame *cm_compose_acquire_frame(cm_context_t *ctx, bool *out_immediate)
{
    if (out_immediate) *out_immediate = false;
    if (!ctx || !ctx->surface) return NULL;
    if (!cm_glue_frame_for_surface) {
        /* Build-phase seam unresolved (symbol still static in cairo_metal.m). */
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = CM_STATUS_DEVICE_ERROR;
        return NULL;
    }
    cm_frame *frame = cm_glue_frame_for_draw
                    ? cm_glue_frame_for_draw(ctx, out_immediate)
                    : cm_glue_frame_for_surface(ctx->surface, /*create=*/true);
    if (!frame) {
        cm_status_t st = (ctx->surface->status != CM_STATUS_SUCCESS)
                       ? ctx->surface->status : CM_STATUS_DEVICE_ERROR;
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    }
    return frame;
}

/* End an immediate (AA-none) compose frame if one was opened. */
static void cm_compose_end_frame(cm_frame *frame, bool immediate)
{
    if (immediate && cm_glue_end_draw_frame) cm_glue_end_draw_frame(frame, true);
}

/* Fold a full-surface paint footprint into a RecordingSurface's ink bounds.
 * paint covers the whole surface (within the clip); for a bounded raster-backed
 * recording surface that is its [0,0 .. w,h] device box.  No-op otherwise. */
static void cm_compose_note_paint_ink(cm_context_t *ctx)
{
    if (!ctx || !ctx->surface) return;
    if (ctx->surface->kind != CM_SURFACE_TYPE_RECORDING) return;
    cm_recording_note_ink_user(ctx->surface, 0.0, 0.0,
                               (double)ctx->surface->width,
                               (double)ctx->surface->height);
}

void cm_paint(cm_context_t *ctx)
{
    if (!ctx || !ctx->surface) return;
    bool immediate = false;
    cm_frame *frame = cm_compose_acquire_frame(ctx, &immediate);
    if (!frame) return;
    cm_status_t st = cm_compose_paint(ctx, frame, ctx->global_alpha);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    cm_compose_end_frame(frame, immediate);
    if (st == CM_STATUS_SUCCESS) cm_compose_note_paint_ink(ctx);
}

void cm_paint_with_alpha(cm_context_t *ctx, double alpha)
{
    if (!ctx || !ctx->surface) return;
    if (alpha < 0.0) alpha = 0.0;
    if (alpha > 1.0) alpha = 1.0;
    bool immediate = false;
    cm_frame *frame = cm_compose_acquire_frame(ctx, &immediate);
    if (!frame) return;
    /* paint_with_alpha composes the constant alpha with the context's group
     * alpha (cairo applies the explicit alpha on top of any group opacity). */
    cm_status_t st = cm_compose_paint(ctx, frame, alpha * ctx->global_alpha);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    cm_compose_end_frame(frame, immediate);
    if (st == CM_STATUS_SUCCESS) cm_compose_note_paint_ink(ctx);
}

void cm_mask(cm_context_t *ctx, cm_pattern_t *pattern)
{
    if (!ctx || !ctx->surface) return;
    if (!pattern) {
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = CM_STATUS_PATTERN_TYPE_MISMATCH;
        return;
    }
    bool immediate = false;
    cm_frame *frame = cm_compose_acquire_frame(ctx, &immediate);
    if (!frame) return;
    cm_status_t st = cm_compose_mask(ctx, frame, pattern);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    cm_compose_end_frame(frame, immediate);
}

void cm_mask_surface(cm_context_t *ctx, cm_surface_t *surface, double x, double y)
{
    if (!ctx) return;
    /* Wrap the surface as a SurfacePattern translated to (x,y): cairo's
     * cairo_mask_surface(surface, x, y) is mask(pattern) with the pattern matrix
     * translate(-x,-y) -- the SAME convention cm_set_source_surface uses. */
    cm_pattern_t *p = cm_pattern_create_for_surface(surface);
    if (!p) {
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = CM_STATUS_NO_MEMORY;
        return;
    }
    cm_matrix_init_translate(&p->matrix, -x, -y);
    cm_mask(ctx, p);
    cm_pattern_destroy(p);
}

/* ===========================================================================
 * BUILD NOTE (cross-module seam to reconcile)
 * ---------------------------------------------------------------------------
 * cairo_metal.m declares the per-surface active-frame registry accessor
 *     static cm_frame *cm_glue_frame_for_surface(cm_surface_t *, bool create);
 * It must be given EXTERNAL linkage (drop `static`) so paint/mask here share the
 * one-command-buffer-per-frame batch that fill/stroke use and that
 * cm_surface_flush ends.  This is the exact pattern its sibling
 * cm_glue_end_frame_for_surface (already non-static + declared in cm_internal.h)
 * follows.  Until then the weak reference above resolves to NULL and paint/mask
 * are a safe no-op (DEVICE_ERROR), so the library still links and renders fills.
 * =========================================================================== */
