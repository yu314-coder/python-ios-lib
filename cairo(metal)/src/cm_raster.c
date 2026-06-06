/*
 * cm_raster.c  --  CairoMetal RasterSourcePattern callback marshalling (pure C)
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_raster.c"):
 *   - cm_pattern_create_raster_source()        (public; payload lives here)
 *   - cm_raster_source_pattern_set_acquire()   (public)
 *   - cm_raster_source_pattern_get_user_data() (public)
 *   - cm_raster_acquire() / cm_raster_release() (INTERNAL trampolines)
 *
 * WHAT A RASTER-SOURCE PATTERN IS
 * -------------------------------------------------------------------------
 * cairo's cairo_pattern_create_raster_source() makes a pattern whose pixels are
 * produced ON DEMAND by a user callback rather than stored up front.  At paint
 * time cairo calls the pattern's `acquire` to obtain a concrete image surface
 * covering the requested device `extents`, samples it like an ordinary surface
 * pattern, then calls `release` to let the user free/recycle it.  This is the
 * hook image libraries use to stream tiles, decode lazily, or render procedural
 * content sized to the exact area being drawn.
 *
 * HOW WE ROUTE IT (hybrid: callback when present, fixed surface otherwise)
 * -------------------------------------------------------------------------
 * A raster-source pattern carries `kind == CM_PAINT_SURFACE` (see the allocator
 * below): for the GPU it is just a SurfacePattern whose source surface is not
 * known until acquire runs.  The encode path (cm_fill.m's CM_PIPE_COVER_SURFACE
 * branch / cairo_metal.m's fill driver) therefore drives a raster source as:
 *
 *     cm_surface_t *src = cm_raster_acquire(pat, target, &extents);
 *     ... wrap `src` as the surface texture, encode the surface cover pass ...
 *     cm_raster_release(pat, src);
 *
 * cm_raster_acquire is the SOLE producer of that transient source surface; it
 * has two modes:
 *
 *   1. CALLBACK mode -- a user `acquire` was installed: invoke it (with the
 *      stored user_data) and hand back whatever surface it returns.  The paired
 *      cm_raster_release forwards to the user `release` so the acquire/release
 *      pair stays balanced exactly as cairo specifies.
 *
 *   2. FALLBACK mode -- no user `acquire` is set: degenerate to a plain
 *      SurfacePattern by returning a FIXED surface captured at create time (a
 *      blank image surface of the pattern's content + nominal size).  This is
 *      the "minimal-correct" path: a raster source with no callbacks still has a
 *      well-defined, samplable source instead of failing the cover pass.  The
 *      fixed surface is OWNED by the pattern (not by the acquire/release pair),
 *      so the matching release is a NO-OP and the surface is freed once, by the
 *      pattern's destructor.
 *
 * OWNERSHIP (important -- cm_pattern.c owns the destructor, NOT this file)
 * -------------------------------------------------------------------------
 * cm_pattern_destroy() (in cm_pattern.c) unconditionally releases
 * `pattern->surf.surface`.  We therefore stash the fixed fallback surface in
 * exactly that field, so it is reclaimed by the existing destructor with no
 * change to any other module.  `surf` and `raster` are SEPARATE members of
 * struct cm_pattern (not a C union), so using surf.surface for the fallback
 * never disturbs the raster payload (callbacks + user_data + nominal size).
 *
 * This translation unit stays PURE C: it never touches MTL* / IOSurface types,
 * only the opaque cm_surface_t* handles vended by cm_surface.m + the C status
 * setter.
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>

/* ==========================================================================
 * Allocation
 * ==========================================================================
 * A raster-source pattern is a SurfacePattern as far as the GPU cover path is
 * concerned, so `kind == CM_PAINT_SURFACE` (RASTER routes through SURFACE, per
 * the cm_paint_kind contract in cm_internal.h).  Mirrors cm_pattern.c's
 * allocator defaults so a raster pattern behaves like every other pattern base
 * (refcount, status, identity matrix, NONE extend, GOOD filter).
 */
static cm_pattern_t *cm_raster_alloc(void)
{
    cm_pattern_t *p = (cm_pattern_t *)calloc(1, sizeof(*p));
    if (!p) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }
    p->type     = CM_PATTERN_TYPE_RASTER_SOURCE;
    /* RASTER routes through SURFACE for the GPU cover path. */
    p->kind     = CM_PAINT_SURFACE;
    p->refcount = 1;
    p->status   = CM_STATUS_SUCCESS;
    p->extend   = CM_EXTEND_NONE;
    p->filter   = CM_FILTER_GOOD;
    cm_matrix_identity(&p->matrix);
    cm_set_last_status(CM_STATUS_SUCCESS);
    return p;
}

/* ==========================================================================
 * Public: create / set_acquire / get_user_data
 * ========================================================================== */

/*
 * cm_pattern_create_raster_source -- mirrors cairo_pattern_create_raster_source.
 *
 * Records the user_data + nominal content/size and pre-captures the FIXED
 * fallback surface (a blank image surface of the content's natural format at the
 * nominal size) so a callback-less raster source still degenerates cleanly to a
 * SurfacePattern at paint time.  The fallback lands in surf.surface so the
 * shared destructor (cm_pattern.c) reclaims it.
 *
 * A non-positive width/height (cairo allows a 0x0 raster source as a no-op
 * placeholder) simply skips the fixed-surface capture: acquire then yields NULL
 * in fallback mode and the cover pass treats it as empty.  Failing to allocate
 * the fixed surface is likewise non-fatal -- the pattern is still valid; only
 * the fallback source is absent (callbacks, if later installed, are unaffected).
 */
cm_pattern_t *cm_pattern_create_raster_source(void *user_data,
                                              cm_content_t content,
                                              int width, int height)
{
    cm_pattern_t *p = cm_raster_alloc();
    if (!p) return NULL;

    p->raster.user_data = user_data;
    p->raster.content   = content;
    p->raster.width     = width;
    p->raster.height    = height;
    p->raster.acquire   = NULL;
    p->raster.release   = NULL;

    /* Pre-capture the fixed fallback surface (degenerate SurfacePattern source).
     * Stored in surf.surface so cm_pattern_destroy releases it for us. */
    if (width > 0 && height > 0) {
        cm_format_t fmt = cm_format_for_content(content);
        cm_surface_t *fixed = cm_image_surface_create(fmt, width, height);
        /* cm_image_surface_create sets last-status on failure; a NULL fixed
         * surface is tolerated (fallback acquire just yields NULL). Re-assert
         * SUCCESS so a tolerated capture failure does not leak into the caller's
         * cm_last_status() for an otherwise-valid pattern. */
        p->surf.surface = fixed;
        cm_set_last_status(CM_STATUS_SUCCESS);
    }

    return p;
}

/*
 * cm_raster_source_pattern_set_acquire -- mirrors
 * cairo_raster_source_pattern_set_acquire.  Installs (or clears, when both are
 * NULL) the acquire/release callback pair.  Type-checked: a no-op on a
 * non-raster pattern, matching cairo's defensive accessors.
 */
void cm_raster_source_pattern_set_acquire(cm_pattern_t *pattern,
                                          cm_raster_acquire_func_t acquire,
                                          cm_raster_release_func_t release)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_RASTER_SOURCE) return;
    pattern->raster.acquire = acquire;
    pattern->raster.release = release;
}

/*
 * cm_raster_source_pattern_get_user_data -- mirrors
 * cairo_raster_source_pattern_get_callback_data.  Returns the opaque user_data
 * recorded at create time (NULL on a non-raster pattern).
 */
void *cm_raster_source_pattern_get_user_data(cm_pattern_t *pattern)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_RASTER_SOURCE) return NULL;
    return pattern->raster.user_data;
}

/* ==========================================================================
 * INTERNAL: acquire / release the transient source surface for the SURFACE
 *           cover path (called by the fill/encode driver -- see file header).
 * ==========================================================================
 *
 * cm_raster_acquire returns the surface the cover-surface pass should sample for
 * this draw, covering `target`'s device `extents` (both forwarded verbatim to a
 * user callback; ignored by the fixed-surface fallback, whose pixels are sized
 * once at create time).  Returns NULL only when there is genuinely no source
 * (callback returned NULL, or fallback capture was absent/failed) -- the caller
 * treats that as an empty paint and skips the cover draw.
 */
cm_surface_t *cm_raster_acquire(cm_pattern_t *pattern, cm_surface_t *target,
                                const cm_rectangle_int_t *extents)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_RASTER_SOURCE) return NULL;

    /* CALLBACK mode: let the user produce a surface for this device region. */
    if (pattern->raster.acquire) {
        return pattern->raster.acquire(pattern, pattern->raster.user_data,
                                       target, extents);
    }

    /* FALLBACK mode: degenerate to a plain SurfacePattern over the fixed surface
     * captured at create time.  Owned by the pattern; the paired release is a
     * no-op (see below). */
    return pattern->surf.surface;
}

/*
 * cm_raster_release -- balance a prior cm_raster_acquire.
 *
 * CALLBACK mode: forward to the user `release` so their acquire/release stays
 * paired exactly as cairo specifies (their callback frees/recycles whatever
 * their acquire handed back).
 *
 * FALLBACK mode: NO-OP.  The surface acquire returned is the pattern-owned fixed
 * surface; it must outlive any number of acquire/release cycles and is freed
 * exactly once by cm_pattern_destroy.  Destroying it here would double-free.
 */
void cm_raster_release(cm_pattern_t *pattern, cm_surface_t *surface)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_RASTER_SOURCE) return;
    if (pattern->raster.release) {
        pattern->raster.release(pattern, pattern->raster.user_data, surface);
    }
    /* else: fixed-surface fallback -- owned by the pattern, nothing to release. */
}
