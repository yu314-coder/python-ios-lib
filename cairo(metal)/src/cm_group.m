/*
 * cm_group.m  --  CairoMetal push/pop_group offscreen targets
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_group.m"):
 *   - The offscreen group-target stack behind cairo_push_group /
 *     cairo_push_group_with_content / cairo_pop_group / cairo_pop_group_to_source
 *     and cairo_get_target / cairo_get_group_target.
 *
 * A group redirects all subsequent drawing into its OWN offscreen surface so the
 * caller can later composite the whole sub-scene at once (with an alpha, through
 * a mask, etc.).  Each push therefore needs a fresh render target that the same
 * stencil-then-cover fill / CPU stroke / paint path can draw into unchanged, and
 * each pop must hand that target back as a paint source.
 *
 *   push_group(content):
 *     1. cm_state_push  -- snapshot the FULL gstate (CTM, source, clip, line
 *        params, dash, font, ...) so pop restores it exactly (cairo_save).
 *     2. Size an offscreen MSAA+resolve target to the current clip extents in
 *        device space (the whole surface when unclipped), per the requested
 *        content: COLOR_ALPHA -> ARGB32 (BGRA8), ALPHA -> A8, COLOR -> RGB24
 *        (opaque BGRX).  cm_offscreen_surface_create (cm_surface.m) owns the
 *        format selection + the MSAA colour / stencil attachments + the resolve.
 *     3. RETARGET the context's draw frame at that surface: every fill / stroke /
 *        paint encoder in cairo_metal.m / cm_fill.m / cm_compose.m drives the
 *        per-frame command buffer through ctx->surface (it is the key into the
 *        active-frame registry AND the source of the to_clip viewport size), so
 *        pointing ctx->surface at the group target is what actually redirects
 *        rendering.  Each group gets its OWN cm_frame on its own offscreen
 *        texture this way.  ctx->target stays pinned to the ORIGINAL surface so
 *        cm_context_get_target keeps reporting the outermost target (cairo).
 *     4. Translate the live CTM by the negated extents origin so geometry that
 *        mapped to parent-device (px,py) now lands at group-pixel (px-ex,py-ey).
 *        (The flatten path applies only the CTM, not the surface device offset,
 *        so the offset has to live in the CTM to actually move the geometry; we
 *        also record it on the surface's device_offset for parity / queries.)
 *
 *   pop_group() -> SurfacePattern (NOT installed):
 *     1. End (commit + wait) the group's draw frame so its MSAA samples RESOLVE
 *        into the offscreen single-sample texture before we sample it as a
 *        source (cm_glue_end_frame_for_surface, owned by cairo_metal.m).
 *     2. Restore ctx->surface to the parent target (the enclosing group's target,
 *        else the original surface) and cm_state_pop the gstate (restores the
 *        CTM we offset in push, the source, the clip, ...).
 *     3. Wrap the resolved offscreen surface as a CM_PATTERN_TYPE_SURFACE pattern
 *        whose matrix is translate(-ex,-ey) -- the DEVICE-ORIGIN matrix that maps
 *        the group back to where it was drawn (identity for the common unclipped,
 *        origin-zero case), exactly as cm_set_source_surface places a surface at
 *        a device origin.  Ownership of the offscreen surface TRANSFERS into the
 *        pattern (cm_pattern_destroy releases it).  We do NOT install it.
 *
 *   pop_group_to_source() = pop_group + cm_set_source (install + drop our ref).
 *
 * This file is .m only so it can share an @autoreleasepool with the offscreen
 * surface create/destroy; it touches NO Metal objects directly -- it drives the
 * offscreen target, the frame lifecycle, the gstate stack, the clip extents, the
 * pattern, and the matrix purely through the cross-module C contract.
 * ============================================================================
 */

#import <Foundation/Foundation.h>

#include "cm_internal.h"

#include <math.h>
#include <stdlib.h>

/* ==========================================================================
 * Clip-extents -> integer offscreen size + device origin
 * --------------------------------------------------------------------------
 * cairo sizes a push_group target to the current clip's device-space extents
 * (so a clipped group allocates only what it can paint into), and shifts the
 * group's device origin to the extents' top-left.  Our clip module exposes the
 * clip's device AABB (cm_clip_extents_dev); when there is no clip we fall back
 * to the whole surface, matching cm_clip_extents_user's unclipped branch.
 *
 * Returns the integer pixel size in out_w/out_h (>= 1) and the device origin the
 * group is offset by in out_ex/out_ey (the floored AABB top-left).  Everything
 * is clamped to the parent surface bounds so the offscreen never needs to be
 * larger than the surface it composites back onto.
 * ========================================================================== */
static void cm_group_extents(cm_context_t *ctx,
                             int *out_w, int *out_h,
                             double *out_ex, double *out_ey)
{
    double sx2 = ctx->surface ? (double)ctx->surface->width  : 0.0;
    double sy2 = ctx->surface ? (double)ctx->surface->height : 0.0;

    double x1, y1, x2, y2;
    if (ctx->clip) {
        float cx1, cy1, cx2, cy2;
        cm_clip_extents_dev(ctx->clip, &cx1, &cy1, &cx2, &cy2);
        x1 = (double)cx1; y1 = (double)cy1;
        x2 = (double)cx2; y2 = (double)cy2;
    } else {
        /* Unclipped: the whole surface (device space [0,0]..[W,H]). */
        x1 = 0.0; y1 = 0.0; x2 = sx2; y2 = sy2;
    }

    /* Clamp the AABB to the surface bounds (a clip can extend past the edge). */
    if (x1 < 0.0)  x1 = 0.0;
    if (y1 < 0.0)  y1 = 0.0;
    if (x2 > sx2)  x2 = sx2;
    if (y2 > sy2)  y2 = sy2;

    /* Snap to whole pixels: origin floors down, far edge ceils up, so the group
     * fully covers the (possibly fractional) clip extents. */
    double fx = floor(x1), fy = floor(y1);
    double w  = ceil(x2) - fx;
    double h  = ceil(y2) - fy;

    /* Degenerate / empty extents (no clip area, or a zero-size surface): fall
     * back to a 1x1 target so cm_offscreen_surface_create gets a valid size and
     * pop still returns a usable (transparent) pattern rather than NULL. */
    if (!(w >= 1.0) || !isfinite(w)) { w = 1.0; }
    if (!(h >= 1.0) || !isfinite(h)) { h = 1.0; }
    if (!isfinite(fx)) fx = 0.0;
    if (!isfinite(fy)) fy = 0.0;

    if (out_w)  *out_w  = (int)w;
    if (out_h)  *out_h  = (int)h;
    if (out_ex) *out_ex = fx;
    if (out_ey) *out_ey = fy;
}

/* The parent draw target underneath group node `g`: the enclosing group's
 * offscreen target if there is one, else the context's ORIGINAL surface.  This
 * is what ctx->surface (the live draw target) must be restored to when `g` is
 * popped.  ctx->target is pinned to the original surface for the whole context
 * lifetime (cairo_get_target), so it is the reliable bottom of the stack. */
static cm_surface_t *cm_group_parent_surface(cm_context_t *ctx, cm_group *g)
{
    if (g && g->next && g->next->target) return g->next->target;
    return ctx->target;   /* original surface (pinned at create time) */
}

/* ==========================================================================
 * Internal push / pop  (cm_internal.h "MODULE: cm_group.m")
 * ========================================================================== */
cm_status_t cm_group_push(cm_context_t *ctx, cm_content_t content)
{
    if (!ctx) return CM_STATUS_NO_MEMORY;
    if (!ctx->surface) return CM_STATUS_SURFACE_TYPE_MISMATCH;

    /* 1) Snapshot the full graphics state FIRST so the gstate the group saves
     *    holds the ORIGINAL (un-offset) CTM; pop restores it verbatim. */
    cm_status_t st = cm_state_push(ctx);
    if (st != CM_STATUS_SUCCESS) return st;

    cm_group *g = (cm_group *)calloc(1, sizeof(*g));
    if (!g) { cm_state_pop(ctx); return CM_STATUS_NO_MEMORY; }
    g->content = content;

    /* 2) Size + allocate the offscreen target from the clip extents. */
    int w = 0, h = 0;
    double ex = 0.0, ey = 0.0;
    cm_group_extents(ctx, &w, &h, &ex, &ey);

    @autoreleasepool {
        g->target = cm_offscreen_surface_create(w, h, content);
    }
    if (!g->target) {
        /* Could not allocate the group surface: undo the gstate snapshot so the
         * push is atomic (no half-entered group) and report the failure. */
        free(g);
        cm_state_pop(ctx);
        cm_status_t why = cm_last_status();
        return (why != CM_STATUS_SUCCESS) ? why : CM_STATUS_NO_MEMORY;
    }

    /* Record the group's device origin on the surface (parity with cairo's
     * group device offset; queries that read it stay consistent). */
    g->target->dev_off_x = ex;
    g->target->dev_off_y = ey;

    /* 3) Push the node, then RETARGET: ctx->surface drives the per-frame command
     *    buffer + the to_clip viewport, so pointing it at the group target is
     *    what actually redirects every following fill/stroke/paint into the
     *    group.  ctx->target stays the original surface (cairo_get_target). */
    g->next           = ctx->groups;
    ctx->groups       = g;
    ctx->group_target = g->target;
    ctx->surface      = g->target;

    /* 4) Offset the live CTM by the negated extents origin so geometry lands in
     *    the group's [0,w]x[0,h] pixel space.  The flatten path applies only the
     *    CTM (not the surface device offset), so the shift must live in the CTM.
     *    Post-compose in DEVICE space: new = CTM then translate(-ex,-ey), i.e.
     *    device' = device - (ex,ey).  cm_matrix_multiply(r,a,b) == apply a then
     *    b, so r = (CTM, T(-ex,-ey)).  (No-op when ex==ey==0, the common case.) */
    if (ex != 0.0 || ey != 0.0) {
        cm_matrix_t t;
        cm_matrix_init_translate(&t, -ex, -ey);
        cm_matrix_multiply(&ctx->ctm, &ctx->ctm, &t);
        ctx->path.dirty        = true;   /* CTM changed -> stale device cache */
        ctx->scaled_font_dirty = true;
    }

    return CM_STATUS_SUCCESS;
}

cm_pattern_t *cm_group_pop(cm_context_t *ctx)
{
    if (!ctx || !ctx->groups) {
        /* pop without a matching push: cairo_pop_group sets INVALID_POP_GROUP. */
        if (ctx && ctx->status == CM_STATUS_SUCCESS)
            ctx->status = CM_STATUS_INVALID_POP_GROUP;
        return NULL;
    }

    cm_group *g = ctx->groups;
    cm_surface_t *group_surface = g->target;

    /* 1) End (commit + wait) this group's draw frame so its MSAA samples resolve
     *    into the offscreen single-sample texture BEFORE we sample it as a
     *    source.  No-op if nothing was drawn into the group. */
    if (group_surface)
        cm_glue_end_frame_for_surface(group_surface, /*wait=*/true);

    /* Read the device origin back from the surface (set in push); it drives the
     * returned pattern's device-origin matrix. */
    double ex = group_surface ? group_surface->dev_off_x : 0.0;
    double ey = group_surface ? group_surface->dev_off_y : 0.0;

    /* 2) Pop the node + restore the live draw target to the parent surface
     *    (enclosing group, else the original) BEFORE restoring the gstate. */
    ctx->groups  = g->next;
    ctx->surface = cm_group_parent_surface(ctx, g);

    cm_state_pop(ctx);   /* restores CTM (incl. the push-time offset), source... */

    /* Re-point the group-target tracker at the new innermost group, if any. */
    ctx->group_target = ctx->groups ? ctx->groups->target : NULL;

    /* 3) Wrap the resolved offscreen surface as a SurfacePattern (NOT installed).
     *    Ownership of the surface TRANSFERS into the pattern (its destroy
     *    releases the surface), so we must not also destroy it here. */
    cm_pattern_t *pat = NULL;
    if (group_surface) {
        pat = cm_pattern_create_for_surface(group_surface);
        if (pat) {
            /* The offscreen surface was created with one reference (held by this
             * group node).  cm_pattern_create_for_surface took its OWN reference
             * (the surface is now refcounted), so drop the node's creation
             * reference here -- the pattern becomes the SOLE owner and freeing the
             * pattern frees the surface (cairo: pop_group transfers the group into
             * the returned pattern).  Without this drop the offscreen surface would
             * leak (count stuck at 1 after the pattern is destroyed). */
            cm_surface_destroy(group_surface);
            g->target = NULL;   /* node no longer owns the surface */
            /* Device-origin matrix: place the group back where it was drawn.
             * The surface-pattern matrix maps user -> pattern(texture) space;
             * translate(-ex,-ey) lands the group at device origin (ex,ey), the
             * same convention cm_set_source_surface uses.  Identity when the
             * extents origin is (0,0) (the common unclipped case). */
            cm_matrix_init_translate(&pat->matrix, -ex, -ey);
        } else {
            /* Pattern alloc failed: we still own the surface -> free it so it
             * does not leak (cm_state_free only frees targets still on the
             * group stack, and this node is already detached). */
            cm_surface_destroy(group_surface);
            g->target = NULL;
            if (ctx->status == CM_STATUS_SUCCESS)
                ctx->status = CM_STATUS_NO_MEMORY;
        }
    }

    /* Defensive: if the node somehow still owns a target (group_surface was
     * NULL), release it before freeing the node. */
    if (g->target) cm_surface_destroy(g->target);
    free(g);

    return pat;
}

/* ==========================================================================
 * Public API
 * ========================================================================== */
void cm_push_group(cm_context_t *ctx)
{
    /* cairo_push_group defaults the content to the target's content, narrowed to
     * COLOR_ALPHA so the group can hold partial coverage for later compositing
     * (cairo uses CAIRO_CONTENT_COLOR_ALPHA unless the target is alpha-only).
     * COLOR_ALPHA is the safe superset and matches manim's usage. */
    cm_push_group_with_content(ctx, CM_CONTENT_COLOR_ALPHA);
}

void cm_push_group_with_content(cm_context_t *ctx, cm_content_t content)
{
    if (!ctx) return;
    cm_status_t st = cm_group_push(ctx, content);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;
}

cm_pattern_t *cm_pop_group(cm_context_t *ctx)
{
    return cm_group_pop(ctx);
}

void cm_pop_group_to_source(cm_context_t *ctx)
{
    cm_pattern_t *pat = cm_group_pop(ctx);
    if (pat) {
        cm_set_source(ctx, pat);     /* installs + takes its own reference */
        cm_pattern_destroy(pat);     /* drop our reference; the context holds one */
    }
    /* pat == NULL means INVALID_POP_GROUP was already flagged by cm_group_pop. */
}

/* cairo_get_target: the ORIGINAL (outermost) surface, NOT the current group
 * target.  ctx->target is pinned to the surface the context was created with and
 * is never moved by a push/pop, so it is the stable answer even mid-group (when
 * ctx->surface points at a group's offscreen target). */
cm_surface_t *cm_context_get_target(cm_context_t *ctx)
{
    if (!ctx) return NULL;
    return ctx->target ? ctx->target : ctx->surface;
}

/* cairo_get_group_target: the current (innermost) group target, or the original
 * target when no group is active. */
cm_surface_t *cm_context_get_group_target(cm_context_t *ctx)
{
    if (!ctx) return NULL;
    if (ctx->group_target) return ctx->group_target;
    return ctx->target ? ctx->target : ctx->surface;
}
