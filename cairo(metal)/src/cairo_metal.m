/*
 * cairo_metal.m  --  CairoMetal public C API implementation (the glue)
 * ============================================================================
 *
 * This translation unit implements the CONTEXT half of the public C API in
 * include/cairo_metal.h -- the context lifecycle, transform, path-building,
 * source/paint, fill, stroke and diagnostics glue that makes CairoMetal a
 * drop-in for the exact cairo subset manim's camera.py uses.  The SURFACE half
 * (cm_image_surface_create_argb32 / destroy / flush / map / iosurface /
 * dimensions) lives in cm_surface.m, which alone owns the IOSurface/MTLTexture
 * internals; every public symbol is therefore defined exactly once across the
 * two files.  This file owns no rendering logic of its own: it is pure glue that
 *
 *   - allocates / frees the shared cm_context_t / cm_pattern_t state (whose
 *     concrete layouts are fixed in cm_internal.h),
 *   - records path verbs through the cm_path_* module,
 *   - drives one MTLCommandBuffer per frame (lazy cm_frame_begin on the first
 *     draw, cm_frame_end on flush) so every VMobject fill/stroke batches into a
 *     single command buffer, exactly as DESIGN.md §4.2 requires,
 *   - delegates fills/strokes to cm_fill_encode / cm_stroke_expand, and
 *   - delegates paint resolution to cm_paint.
 *
 * It is compiled as Objective-C (.m) because the per-frame driver uses
 * dispatch_* (the GCD serial queue guarding the active-frame registry) and
 * cooperates with the Objective-C frame objects vended by cm_device.m through
 * opaque handles.  No Metal/IOSurface objects are created here.
 *
 * Threading / ownership matches the public header: all cm_* calls for one
 * context come from a single thread; a context retains its surface; a pattern
 * handed to cm_set_source is retained by the context until the next set_source.
 *
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

#import <Foundation/Foundation.h>

/* ==========================================================================
 * Cross-module glue with cm_surface.m
 * --------------------------------------------------------------------------
 * The SURFACE public API (create / destroy / flush / map / iosurface /
 * dimensions) is owned by cm_surface.m, which alone can touch the IOSurface /
 * MTLTexture internals.  This translation unit owns the CONTEXT / path / paint /
 * fill / stroke public glue plus the per-frame command-buffer driver.
 *
 * The two files share exactly two things, declared here:
 *   - the thread-local "last global status" (cm_last_status), whose storage +
 *     accessor live in cm_surface.m; we set it through cm_set_last_status().
 *   - the active per-frame command buffer for a surface.  The frame registry
 *     lives in THIS file (it is the draw driver), and cm_surface.m's flush /
 *     destroy end the active frame through cm_glue_end_frame_for_surface().
 * ========================================================================== */
extern void cm_set_last_status(cm_status_t st);   /* defined in cm_surface.m */

/* Exported so cm_surface.m's flush/destroy can commit this surface's frame. */
void cm_glue_end_frame_for_surface(cm_surface_t *surface, bool wait);

/* Exported (external linkage) so cm_compose.m's paint/mask can batch into the
 * SAME per-surface command buffer that fill/stroke open here (and that
 * cm_surface_flush ends).  cm_compose.m references this through a `weak` extern;
 * giving it external linkage here is the one cross-module seam the BUILD note in
 * cm_compose.m calls out -- it mirrors the already-exported sibling
 * cm_glue_end_frame_for_surface.  Not in cm_internal.h (which only declares the
 * `_end_` half), so we forward-declare it here with the matching prototype. */
cm_frame *cm_glue_frame_for_surface(cm_surface_t *surface, bool create);

/* ==========================================================================
 * Active-frame registry (surface -> in-flight cm_frame*)
 * ==========================================================================
 * cairo has no explicit begin-frame: drawing just happens and surface.flush()
 * makes it coherent.  We mirror that by lazily creating ONE cm_frame (one
 * MTLCommandBuffer) per surface on the first draw and committing it on flush,
 * so all of a frame's VMobject fills/strokes batch into a single command
 * buffer (DESIGN.md §4.2).
 *
 * The in-flight frame is naturally owned by the context that is drawing
 * (cm_context.frame), but cm_surface_flush() is handed only a surface.  The
 * shared cm_surface struct has no frame field to repurpose, so we keep a tiny
 * glue-private surface->frame association here.  Per the threading contract a
 * surface is driven by one context on one thread, so this stays trivially
 * consistent; a small lock only guards the unusual case of several surfaces
 * being flushed from different threads.
 */
typedef struct cm_active_frame {
    cm_surface_t           *surface;
    cm_frame               *frame;
    struct cm_active_frame *next;
} cm_active_frame;

static cm_active_frame *g_active_frames = NULL;
static dispatch_once_t  g_active_once   = 0;
static dispatch_queue_t g_active_q      = NULL;   /* serializes the list */

static void cm_glue_active_init(void)
{
    dispatch_once(&g_active_once, ^{
        g_active_q = dispatch_queue_create("com.cairometal.frames",
                                           DISPATCH_QUEUE_SERIAL);
    });
}

/* Look up (or, if create, lazily begin) the active frame for `surface`.
 * Returns the frame, or NULL if begin failed / none exists.
 *
 * EXTERNAL linkage (not static): fill/stroke here AND paint/mask in cm_compose.m
 * must batch into the one MTLCommandBuffer per surface that cm_surface_flush
 * ends, so cm_compose.m acquires the active frame through THIS accessor (via a
 * `weak` extern) rather than opening a second, untracked command buffer. */
cm_frame *cm_glue_frame_for_surface(cm_surface_t *surface, bool create)
{
    if (!surface) return NULL;
    cm_glue_active_init();

    __block cm_frame *result = NULL;
    dispatch_sync(g_active_q, ^{
        cm_active_frame *node = g_active_frames;
        while (node && node->surface != surface) node = node->next;
        if (node) { result = node->frame; return; }
        if (!create) return;

        cm_frame *f = cm_frame_begin(surface);   /* one command buffer / frame */
        if (!f) return;                          /* surface->status set inside */
        cm_active_frame *n = (cm_active_frame *)malloc(sizeof(*n));
        if (!n) { cm_frame_end(f, false); return; }
        n->surface = surface;
        n->frame   = f;
        n->next    = g_active_frames;
        g_active_frames = n;
        result = f;
    });
    return result;
}

/* Detach (without ending) the active frame for `surface`, returning it. */
static cm_frame *cm_glue_take_frame(cm_surface_t *surface)
{
    if (!surface) return NULL;
    cm_glue_active_init();

    __block cm_frame *taken = NULL;
    dispatch_sync(g_active_q, ^{
        cm_active_frame **pp = &g_active_frames;
        while (*pp && (*pp)->surface != surface) pp = &(*pp)->next;
        if (*pp) {
            cm_active_frame *node = *pp;
            taken = node->frame;
            *pp = node->next;
            free(node);
        }
    });
    return taken;
}

/* End and (optionally block on) the active frame for `surface`, if any.
 * Exported (non-static): cm_surface.m's flush/destroy call this so the surface
 * public API and the context draw driver share one frame lifecycle. */
void cm_glue_end_frame_for_surface(cm_surface_t *surface, bool wait)
{
    cm_frame *f = cm_glue_take_frame(surface);
    if (f) cm_frame_end(f, wait);
}

/* ==========================================================================
 * Per-draw frame acquisition (MSAA batched, or ANTIALIAS_NONE 1-sample)  BUG 7
 * --------------------------------------------------------------------------
 * The default (MSAA) path batches every draw into one command buffer per surface
 * via the active-frame registry above.  ANTIALIAS_NONE needs HARD per-pixel edges,
 * which the 4x MSAA attachments cannot give (a fully covered pixel resolves from 4
 * samples; a partial edge pixel resolves to a soft alpha).  So an AA-none draw runs
 * in its OWN 1-sample render pass (cm_frame_begin_single) that draws directly into
 * the surface's resolved colour texture with loadAction Load -- compositing OVER
 * whatever is already there -- and is committed IMMEDIATELY.
 *
 * To composite correctly over prior MSAA work, we first FLUSH the surface's active
 * MSAA frame (resolving it into the colour texture) before opening the 1-sample
 * pass.  cm_glue_frame_for_draw returns the frame to encode into and sets
 * *out_immediate when the caller must end it itself (immediate AA-none frames are
 * NOT in the registry, so cm_surface_flush would not find them).
 * ========================================================================== */
extern cm_frame *cm_frame_begin_single(cm_surface_t *surface);

cm_frame *cm_glue_frame_for_draw(cm_context_t *ctx, bool *out_immediate)
{
    if (out_immediate) *out_immediate = false;
    if (!ctx || !ctx->surface) return NULL;

    if (ctx->antialias == CM_ANTIALIAS_NONE) {
        /* Resolve any pending MSAA work into the colour texture first so the
         * 1-sample pass (loadAction Load) composites over the up-to-date image. */
        cm_glue_end_frame_for_surface(ctx->surface, /*wait=*/true);
        cm_frame *f = cm_frame_begin_single(ctx->surface);
        if (f) { if (out_immediate) *out_immediate = true; return f; }
        /* Fallback (non-BGRA8 target, or 1-sample stencil unavailable): use the
         * normal MSAA batched frame -- AA-none then degrades to MSAA edges, which
         * is still correct colour (just soft edges) rather than a dropped draw. */
    }
    return cm_glue_frame_for_surface(ctx->surface, /*create=*/true);
}

/* End an immediate (AA-none) draw frame: commit + wait so the colour texture holds
 * the composited result before the next draw or flush.  A no-op for a registered
 * MSAA frame (those are ended by cm_surface_flush). */
void cm_glue_end_draw_frame(cm_frame *frame, bool immediate)
{
    if (immediate && frame) cm_frame_end(frame, /*wait=*/true);
}

/* ==========================================================================
 * Small status helpers
 * ========================================================================== */
static inline void cm_ctx_set_status(cm_context_t *ctx, cm_status_t st)
{
    if (ctx && st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;          /* sticky first-error, like cairo_status */
}

/* Single source of truth for "the CTM just changed": mark the path's flattened
 * DEVICE cache stale (it was built against the old CTM) AND invalidate the
 * cached scaled font (cm_font.c re-derives it against the new CTM on next get).
 * EVERY CTM mutator in this file (set_matrix / scale / translate / rotate /
 * transform / identity_matrix) funnels through here so neither invalidation can
 * be forgotten -- the contract cm_path.m and cm_font.c document and rely on. */
static inline void cm_ctm_changed(cm_context_t *ctx)
{
    if (!ctx) return;
    ctx->path.dirty        = true;
    ctx->scaled_font_dirty = true;
}

/* ==========================================================================
 * Surface API
 * --------------------------------------------------------------------------
 * cm_image_surface_create_argb32 / cm_surface_destroy / cm_surface_flush /
 * cm_surface_get_iosurface / cm_surface_map_argb32 / cm_surface_get_width /
 * cm_surface_get_height are implemented in cm_surface.m (they are inseparable
 * from the Objective-C IOSurface/MTLTexture internals only that file touches).
 * They are intentionally NOT defined here to keep each public symbol defined
 * exactly once.  cm_surface.m's flush/destroy commit this surface's active
 * draw frame via cm_glue_end_frame_for_surface() above.
 * ========================================================================== */

/* ==========================================================================
 * Context API
 * ========================================================================== */

CM_PUBLIC cm_context_t *
cm_context_create(cm_surface_t *surface)
{
    if (!surface) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }

    cm_context_t *ctx = (cm_context_t *)calloc(1, sizeof(*ctx));
    if (!ctx) {
        cm_set_last_status(CM_STATUS_NO_MEMORY);
        return NULL;
    }

    ctx->surface = surface;                 /* context retains the surface     */
    cm_matrix_identity(&ctx->ctm);          /* default CTM = identity          */

    /* cairo default source: opaque black (0,0,0,1).  No re-swap (header). */
    ctx->source.kind        = CM_PAINT_SOLID;
    ctx->source.solid.r     = 0.0f;
    ctx->source.solid.g     = 0.0f;
    ctx->source.solid.b     = 0.0f;
    ctx->source.solid.a     = 1.0f;
    ctx->source.pattern     = NULL;

    ctx->fill_rule          = CM_FILL_RULE_WINDING;   /* cairo default */
    ctx->line_width         = 2.0;                     /* cairo default */
    ctx->line_join          = CM_LINE_JOIN_MITER;      /* cairo default */
    ctx->line_cap           = CM_LINE_CAP_BUTT;        /* cairo default */
    ctx->miter_limit        = 10.0;                    /* cairo default */

    /* Full cairo default compositing / dash / group / font state. */
    ctx->op                 = CM_OPERATOR_OVER;        /* cairo default */
    ctx->antialias          = CM_ANTIALIAS_DEFAULT;
    ctx->tolerance          = 0.1;                      /* cairo default */
    ctx->dash               = NULL;
    ctx->dash_count         = 0;
    ctx->dash_offset        = 0.0;
    ctx->global_alpha       = 1.0;

    ctx->stack              = NULL;
    ctx->clip               = NULL;                     /* unclipped           */
    ctx->target             = surface;                  /* draws to surface    */
    ctx->group_target       = NULL;
    ctx->groups             = NULL;

    /* cairo default font matrix is scale(10,10) (the default font size). */
    ctx->font_face          = NULL;
    cm_matrix_init_scale(&ctx->font_matrix, 10.0, 10.0);
    ctx->font_options       = NULL;
    ctx->scaled_font        = NULL;
    ctx->scaled_font_dirty  = true;

    cm_path_init(&ctx->path);

    ctx->frame              = NULL;
    ctx->last_pipeline_group = CM_PAINT_SOLID;
    ctx->status             = CM_STATUS_SUCCESS;

    cm_set_last_status(CM_STATUS_SUCCESS);
    return ctx;
}

CM_PUBLIC void
cm_context_destroy(cm_context_t *ctx)
{
    if (!ctx) return;

    /* If this context began a frame that was never flushed, commit it (no need
     * to block) so the command buffer is not leaked, before the surface and its
     * textures can go away. */
    if (ctx->surface)
        cm_glue_end_frame_for_surface(ctx->surface, /*wait=*/false);

    /* Release a retained pattern source, if any. */
    if (ctx->source.kind != CM_PAINT_SOLID && ctx->source.pattern)
        cm_pattern_destroy(ctx->source.pattern);

    /* Release the gstate stack + owned dash / clip / group / font state. */
    cm_state_free(ctx);

    cm_path_free(&ctx->path);

    /* The context does NOT own the surface lifetime (header contract): it only
     * holds a reference; the caller destroys the surface separately. */
    free(ctx);
}

/* ---- transform ---------------------------------------------------------- */

CM_PUBLIC void
cm_set_matrix(cm_context_t *ctx, const cm_matrix_t *matrix)
{
    if (!ctx || !matrix) return;
    /* cairo set_matrix REPLACES the CTM (does not compose). */
    ctx->ctm = *matrix;
    cm_ctm_changed(ctx);             /* stale device geometry + scaled font */
    /* A non-invertible CTM cannot map device->user for gradients/flattening
     * sanity; record it but keep the matrix (cairo also stores it and errors
     * lazily). */
    if (!cm_matrix_is_invertible(&ctx->ctm))
        cm_ctx_set_status(ctx, CM_STATUS_INVALID_MATRIX);
}

CM_PUBLIC void
cm_scale(cm_context_t *ctx, double sx, double sy)
{
    if (!ctx) return;
    /* cairo scale POST-multiplies: CTM = CTM * scale(sx,sy). */
    cm_matrix_mul_scale(&ctx->ctm, sx, sy);
    cm_ctm_changed(ctx);
}

CM_PUBLIC void
cm_get_matrix(const cm_context_t *ctx, cm_matrix_t *out_matrix)
{
    if (!out_matrix) return;
    if (!ctx) { cm_matrix_identity(out_matrix); return; }
    *out_matrix = ctx->ctm;
}

CM_PUBLIC void
cm_identity_matrix(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_matrix_identity(&ctx->ctm);
    cm_ctm_changed(ctx);
}

CM_PUBLIC void
cm_translate(cm_context_t *ctx, double tx, double ty)
{
    if (!ctx) return;
    cm_matrix_translate(&ctx->ctm, tx, ty);
    cm_ctm_changed(ctx);
}

CM_PUBLIC void
cm_rotate(cm_context_t *ctx, double radians)
{
    if (!ctx) return;
    cm_matrix_rotate(&ctx->ctm, radians);
    cm_ctm_changed(ctx);
}

CM_PUBLIC void
cm_transform(cm_context_t *ctx, const cm_matrix_t *matrix)
{
    if (!ctx || !matrix) return;
    /* CTM = matrix * CTM (the new transform applies in the current space). */
    cm_matrix_multiply(&ctx->ctm, matrix, &ctx->ctm);
    cm_ctm_changed(ctx);
}

CM_PUBLIC void
cm_user_to_device(cm_context_t *ctx, double *x, double *y)
{
    if (!ctx || !x || !y) return;
    cm_matrix_transform_point(&ctx->ctm, x, y);
}

CM_PUBLIC void
cm_user_to_device_distance(cm_context_t *ctx, double *dx, double *dy)
{
    if (!ctx || !dx || !dy) return;
    cm_matrix_transform_distance(&ctx->ctm, dx, dy);
}

CM_PUBLIC void
cm_device_to_user(cm_context_t *ctx, double *x, double *y)
{
    if (!ctx || !x || !y) return;
    cm_matrix_t inv = ctx->ctm;
    if (cm_matrix_invert(&inv) != CM_STATUS_SUCCESS) {
        cm_ctx_set_status(ctx, CM_STATUS_INVALID_MATRIX);
        return;
    }
    cm_matrix_transform_point(&inv, x, y);
}

CM_PUBLIC void
cm_device_to_user_distance(cm_context_t *ctx, double *dx, double *dy)
{
    if (!ctx || !dx || !dy) return;
    cm_matrix_t inv = ctx->ctm;
    if (cm_matrix_invert(&inv) != CM_STATUS_SUCCESS) {
        cm_ctx_set_status(ctx, CM_STATUS_INVALID_MATRIX);
        return;
    }
    cm_matrix_transform_distance(&inv, dx, dy);
}

/* ---- path construction -------------------------------------------------- */

CM_PUBLIC void cm_new_path(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_path_reset(&ctx->path);
}

CM_PUBLIC void cm_new_sub_path(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_path_new_sub(&ctx->path);
}

CM_PUBLIC void cm_move_to(cm_context_t *ctx, double x, double y)
{
    if (!ctx) return;
    cm_path_move_to(&ctx->path, x, y);
}

CM_PUBLIC void cm_line_to(cm_context_t *ctx, double x, double y)
{
    if (!ctx) return;
    cm_path_line_to(&ctx->path, x, y);
}

CM_PUBLIC void cm_curve_to(cm_context_t *ctx,
                           double x1, double y1,
                           double x2, double y2,
                           double x3, double y3)
{
    if (!ctx) return;
    cm_path_curve_to(&ctx->path, x1, y1, x2, y2, x3, y3);
}

CM_PUBLIC void cm_close_path(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_path_close(&ctx->path);
}

/* ---- source / paint ----------------------------------------------------- */

CM_PUBLIC void
cm_set_source_rgba(cm_context_t *ctx,
                   double r, double g, double b, double a)
{
    if (!ctx) return;
    /* Drop any previously retained pattern source. */
    if (ctx->source.kind != CM_PAINT_SOLID && ctx->source.pattern) {
        cm_pattern_destroy(ctx->source.pattern);
        ctx->source.pattern = NULL;
    }
    /* PIXEL CONTRACT: manim already passes B,G,R,A; pass through unchanged.
     * GPU premultiplies by alpha at cover time. */
    ctx->source.kind    = CM_PAINT_SOLID;
    ctx->source.solid.r = (float)r;
    ctx->source.solid.g = (float)g;
    ctx->source.solid.b = (float)b;
    ctx->source.solid.a = (float)a;
}

/* cm_linear_gradient_create / cm_pattern_add_color_stop_rgba / cm_set_source /
 * cm_pattern_destroy now live in cm_pattern.c (the universal pattern owner);
 * they were MOVED out of this file so each public symbol is defined once. */

/* ---- fill --------------------------------------------------------------- */

CM_PUBLIC void
cm_set_fill_rule(cm_context_t *ctx, cm_fill_rule_t fill_rule)
{
    if (!ctx) return;
    ctx->fill_rule = fill_rule;
}

CM_PUBLIC void
cm_fill_preserve(cm_context_t *ctx)
{
    if (!ctx || !ctx->surface) return;

    /* Empty path -> nothing to fill (and nothing to preserve differently). */
    if (ctx->path.verb_count == 0) return;

    /* Flatten the recorded path into device space using the current CTM.  This
     * is idempotent while the path is clean, so a following stroke_preserve on
     * the same (preserved) path reuses the flattened cache. */
    cm_status_t st = cm_path_flatten(&ctx->path, &ctx->ctm);
    if (st != CM_STATUS_SUCCESS) { cm_ctx_set_status(ctx, st); return; }

    /* Acquire the draw frame: the batched MSAA frame, or -- for ANTIALIAS_NONE --
     * an immediate 1-sample frame (hard edges). */
    bool immediate = false;
    cm_frame *frame = cm_glue_frame_for_draw(ctx, &immediate);
    if (!frame) {
        cm_ctx_set_status(ctx,
            ctx->surface->status != CM_STATUS_SUCCESS
                ? ctx->surface->status : CM_STATUS_DEVICE_ERROR);
        return;
    }

    /* Encode stencil-then-cover for the current source + fill rule. */
    st = cm_fill_encode(ctx, frame, &ctx->path, ctx->fill_rule);
    if (st != CM_STATUS_SUCCESS) cm_ctx_set_status(ctx, st);
    cm_glue_end_draw_frame(frame, immediate);   /* commits the AA-none pass */

    /* RecordingSurface ink: fold the filled path's device-space box into the
     * surface's recorded ink bounds (raster-backed recording surface; the op-log
     * is not appended for direct draws).  No-op for any non-recording target. */
    if (ctx->surface->kind == CM_SURFACE_TYPE_RECORDING) {
        float bx0, by0, bx1, by1;
        cm_path_bounds(&ctx->path, &bx0, &by0, &bx1, &by1);
        cm_recording_note_ink_user(ctx->surface, bx0, by0, bx1, by1);
    }

    /* PRESERVE: the path is intentionally NOT cleared (camera.py strokes the
     * same path right after).  cm_fill_encode must not mutate the recorded
     * verbs; the flattened cache stays valid for the stroke. */
}

/* ---- stroke ------------------------------------------------------------- */

CM_PUBLIC void
cm_set_line_width(cm_context_t *ctx, double width)
{
    if (!ctx) return;
    ctx->line_width = width;
}

CM_PUBLIC void
cm_set_line_join(cm_context_t *ctx, cm_line_join_t join)
{
    if (!ctx) return;
    ctx->line_join = join;
}

CM_PUBLIC void
cm_set_line_cap(cm_context_t *ctx, cm_line_cap_t cap)
{
    if (!ctx) return;
    ctx->line_cap = cap;
}

CM_PUBLIC void
cm_set_miter_limit(cm_context_t *ctx, double limit)
{
    if (!ctx) return;
    ctx->miter_limit = limit;
}

CM_PUBLIC void
cm_stroke_preserve(cm_context_t *ctx)
{
    if (!ctx || !ctx->surface) return;

    if (ctx->path.verb_count == 0) return;
    if (!(ctx->line_width > 0.0)) return;   /* zero/negative width: nothing */

    /* Flatten the source path into device space (idempotent if already clean
     * from a preceding fill_preserve on the same preserved path). */
    cm_status_t st = cm_path_flatten(&ctx->path, &ctx->ctm);
    if (st != CM_STATUS_SUCCESS) { cm_ctx_set_status(ctx, st); return; }

    /* Expand the stroke into a fillable outline polygon (device space), honoring
     * width/join/cap/miter limit.  The line width is in USER space, so scale it
     * by the CTM's device-px-per-user-unit before CPU expansion (the flattened
     * geometry is already in device space). */
    double dev_width = ctx->line_width * cm_matrix_max_scale(&ctx->ctm);

    /* Dash pre-pass (cm_stroke.m): when a dash pattern is set, chop the flattened
     * path into device-space capped on-pieces and stroke THOSE; with no dash the
     * helper hands back ctx->path unchanged so the result stays byte-for-byte
     * identical to the un-dashed path.  It pre-scales the user-space dash by the
     * SAME max-scale already folded into dev_width above. */
    cm_path dashed;
    cm_path_init(&dashed);
    const cm_path *stroke_src = &ctx->path;
    st = cm_dash_prepass(ctx, &ctx->path, &dashed, &stroke_src);
    if (st != CM_STATUS_SUCCESS) {
        cm_ctx_set_status(ctx, st);
        cm_path_free(&dashed);
        return;
    }

    /* Outline path lives across this call only; reset+fill it from stroke_src
     * (the dashed on-pieces when dashing, else the flattened path itself). */
    cm_path outline;
    cm_path_init(&outline);

    st = cm_stroke_expand(stroke_src, &outline, dev_width,
                          ctx->line_join, ctx->line_cap, ctx->miter_limit,
                          ctx->tolerance > 0.0 ? ctx->tolerance : CM_ARC_TOLERANCE);
    cm_path_free(&dashed);   /* on-pieces already copied into `outline` */
    if (st != CM_STATUS_SUCCESS) {
        cm_ctx_set_status(ctx, st);
        cm_path_free(&outline);
        return;
    }

    /* The outline is already device-space geometry; cm_fill_encode flattens via
     * the CTM, so feed it an IDENTITY CTM so it is not transformed twice. */
    cm_matrix_t saved_ctm = ctx->ctm;
    cm_matrix_identity(&ctx->ctm);
    st = cm_path_flatten(&outline, &ctx->ctm);
    if (st == CM_STATUS_SUCCESS) {
        bool immediate = false;
        cm_frame *frame = cm_glue_frame_for_draw(ctx, &immediate);
        if (!frame) {
            cm_ctx_set_status(ctx,
                ctx->surface->status != CM_STATUS_SUCCESS
                    ? ctx->surface->status : CM_STATUS_DEVICE_ERROR);
        } else {
            /* Stroke coverage is always NONZERO so overlapping stroke pieces
             * (segments + joins + caps) composite exactly once, matching
             * cairo's stroke semantics regardless of the context fill rule. */
            st = cm_fill_encode(ctx, frame, &outline, CM_FILL_RULE_WINDING);
            if (st != CM_STATUS_SUCCESS) cm_ctx_set_status(ctx, st);
            cm_glue_end_draw_frame(frame, immediate);

            /* RecordingSurface ink: the device-space `outline` is the exact
             * stroked footprint (width + caps + joins), so its bounds are the
             * ink the stroke deposited.  No-op for a non-recording target. */
            if (ctx->surface->kind == CM_SURFACE_TYPE_RECORDING) {
                float bx0, by0, bx1, by1;
                cm_path_bounds(&outline, &bx0, &by0, &bx1, &by1);
                cm_recording_note_ink_user(ctx->surface, bx0, by0, bx1, by1);
            }
        }
    } else {
        cm_ctx_set_status(ctx, st);
    }
    ctx->ctm = saved_ctm;   /* restore; gradient paint used the real CTM */

    cm_path_free(&outline);

    /* PRESERVE: original recorded path untouched. */
}

/* ==========================================================================
 * Diagnostics
 * ========================================================================== */

CM_PUBLIC cm_status_t cm_context_status(const cm_context_t *ctx)
{
    return ctx ? ctx->status : CM_STATUS_NO_MEMORY;
}

/* cm_last_status() is defined in cm_surface.m (single owner of the thread-local
 * global-status storage; this file sets it via cm_set_last_status()). */

CM_PUBLIC const char *cm_status_to_string(cm_status_t status)
{
    /* Mirrors cairo_status_to_string(): always returns a non-NULL static C
     * string. */
    switch (status) {
        case CM_STATUS_SUCCESS:
            return "no error has occurred";
        case CM_STATUS_NO_MEMORY:
            return "out of memory";
        case CM_STATUS_NO_METAL_DEVICE:
            return "no Metal device available";
        case CM_STATUS_INVALID_FORMAT:
            return "invalid or unsupported surface format/size";
        case CM_STATUS_SURFACE_TYPE_MISMATCH:
            return "operation requires an IOSurface-backed surface";
        case CM_STATUS_INVALID_MATRIX:
            return "invalid (non-invertible) matrix";
        case CM_STATUS_DEVICE_ERROR:
            return "Metal command buffer or pipeline error";
        case CM_STATUS_INVALID_RESTORE:
            return "cairo_restore() without matching cairo_save()";
        case CM_STATUS_INVALID_POP_GROUP:
            return "no matching push group";
        case CM_STATUS_NO_CURRENT_POINT:
            return "no current point defined";
        case CM_STATUS_INVALID_DASH:
            return "invalid dash setting";
        case CM_STATUS_CLIP_NOT_REPRESENTABLE:
            return "clip region not representable as a rectangle list";
        case CM_STATUS_INVALID_INDEX:
            return "invalid index passed to getter";
        case CM_STATUS_PATTERN_TYPE_MISMATCH:
            return "pattern type mismatch";
        case CM_STATUS_SURFACE_FINISHED:
            return "the target surface has been finished";
        case CM_STATUS_FONT_TYPE_MISMATCH:
            return "font type mismatch";
        default:
            return "unknown error status";
    }
}

/* ==========================================================================
 * Public cairo-numbered status mapping
 * --------------------------------------------------------------------------
 * cairo_status_t numbering (subset we reference): SUCCESS=0, NO_MEMORY=1,
 * INVALID_RESTORE=2, INVALID_POP_GROUP=3, NO_CURRENT_POINT=4, INVALID_MATRIX=5,
 * SURFACE_FINISHED=12, SURFACE_TYPE_MISMATCH=13, PATTERN_TYPE_MISMATCH=14,
 * INVALID_FORMAT=16, INVALID_DASH=19, CLIP_NOT_REPRESENTABLE=23, INVALID_INDEX
 * =26, FONT_TYPE_MISMATCH=27, DEVICE_ERROR=35.
 * ========================================================================== */
CM_PUBLIC int cm_to_cairo_status(cm_status_t status)
{
    switch (status) {
        case CM_STATUS_SUCCESS:                 return 0;
        case CM_STATUS_NO_MEMORY:               return 1;
        case CM_STATUS_INVALID_RESTORE:         return 2;
        case CM_STATUS_INVALID_POP_GROUP:       return 3;
        case CM_STATUS_NO_CURRENT_POINT:        return 4;
        case CM_STATUS_INVALID_MATRIX:          return 5;
        case CM_STATUS_SURFACE_FINISHED:        return 12;
        case CM_STATUS_SURFACE_TYPE_MISMATCH:   return 13;
        case CM_STATUS_PATTERN_TYPE_MISMATCH:   return 14;
        case CM_STATUS_INVALID_FORMAT:          return 16;
        case CM_STATUS_INVALID_DASH:            return 19;
        case CM_STATUS_CLIP_NOT_REPRESENTABLE:  return 23;
        case CM_STATUS_INVALID_INDEX:           return 26;
        case CM_STATUS_FONT_TYPE_MISMATCH:      return 27;
        case CM_STATUS_NO_METAL_DEVICE:         return 35;   /* DEVICE_ERROR    */
        case CM_STATUS_DEVICE_ERROR:            return 35;
        default:                                return 6;    /* INVALID_STATUS  */
    }
}

/* Full ~45-entry cairo status table for the cairo-numbered status. */
CM_PUBLIC const char *cm_cairo_status_to_string(int cairo_status)
{
    static const char *const tbl[] = {
        "no error has occurred",                                 /* 0  SUCCESS  */
        "out of memory",                                         /* 1  */
        "cairo_restore() without matching cairo_save()",         /* 2  */
        "no matching push group",                                /* 3  */
        "no current point defined",                              /* 4  */
        "invalid matrix (not invertible)",                       /* 5  */
        "invalid value for an input cairo_status_t",             /* 6  */
        "NULL pointer",                                          /* 7  */
        "input string not valid UTF-8",                          /* 8  */
        "input path data not valid",                             /* 9  */
        "error while reading from input stream",                 /* 10 */
        "error while writing to output stream",                  /* 11 */
        "the target surface has been finished",                  /* 12 */
        "the surface type is not appropriate for the operation", /* 13 */
        "the pattern type is not appropriate for the operation", /* 14 */
        "invalid value for an input cairo_content_t",            /* 15 */
        "invalid value for an input cairo_format_t",             /* 16 */
        "invalid value for an input Visual*",                    /* 17 */
        "file not found",                                        /* 18 */
        "invalid value for a dash setting",                      /* 19 */
        "invalid value for a clip operation",                    /* 20 */
        "invalid operation",                                     /* 21 */
        "input value invalid",                                   /* 22 */
        "clip region not representable in rectangular form",     /* 23 */
        "error while writing to temporary file",                 /* 24 */
        "invalid value for an input cairo_font_options_t",       /* 25 */
        "the specified index was out of range",                  /* 26 */
        "the specified font type is not appropriate",            /* 27 */
        "the operation requires that the surface support being read", /* 28 */
        "user-font error",                                       /* 29 */
        "negative number used where positive expected",          /* 30 */
        "input value not valid",                                 /* 31 */
        "no such device",                                        /* 32 */
        "device unsupported operation",                          /* 33 */
        "device type mismatch",                                  /* 34 */
        "an error occurred on the device",                       /* 35 DEVICE_ERROR */
    };
    int n = (int)(sizeof(tbl) / sizeof(tbl[0]));
    if (cairo_status < 0 || cairo_status >= n) return "unknown error status";
    return tbl[cairo_status];
}

/* ==========================================================================
 * Version
 * ========================================================================== */
CM_PUBLIC int          cm_version(void)        { return CM_CAIRO_VERSION; }
CM_PUBLIC const char  *cm_version_string(void) { return CM_CAIRO_VERSION_STRING; }
