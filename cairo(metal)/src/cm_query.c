/*
 * cm_query.c  --  CairoMetal Query domain: extents + point-in tests (pure C)
 * ============================================================================
 *
 * MODULE OWNER of cm_internal.h "MODULE: cm_query.c".
 *
 * Resolves the Enums/Query domain's extents + in_* ops, kept OUT of
 * cairo_metal.m so the one-concern-per-file split holds.  Pure CPU: the only
 * dependency on the "GPU" side of the library is calling the existing
 * cm_path / cm_stroke CPU helpers (adaptive flatten + stroke expansion); nothing
 * here touches Metal or Objective-C, so the file is plain C.
 *
 * ----------------------------------------------------------------------------
 * WHAT THIS FILE OWNS
 * ----------------------------------------------------------------------------
 *   - cm_point_in_contours()  (INTERNAL, declared in cm_internal.h)
 *         The SHARED point-in-polygon over a path's DEVICE-space flattened
 *         contours, with WINDING (nonzero winding number) and EVEN_ODD (parity)
 *         rules.  Used by cm_in_fill / cm_in_stroke HERE and by cm_in_clip in
 *         cm_clip.m (cm_clip.m calls it on the clip's stored device contours --
 *         see the cross-module seam note at EOF).
 *   - cm_fill_extents()   (cairo_fill_extents)   -- tight user-space fill box.
 *   - cm_stroke_extents() (cairo_stroke_extents) -- tight user-space stroke box.
 *   - cm_in_fill()        (cairo_in_fill)        -- point-in-fill hit test.
 *   - cm_in_stroke()      (cairo_in_stroke)      -- point-in-stroke hit test.
 *
 * The PUBLIC cm_path_extents() (cairo_path_extents) is NOT defined here: its
 * body lives with the path recorder in cm_path.m (it needs the user-space
 * flatten / recorded-verb arena that module owns).  Defining it here too would
 * be a duplicate symbol.  This file shares the SAME conceptual pipeline as
 * fill_extents below, just sourced differently.
 *
 * ----------------------------------------------------------------------------
 * THE EXTENTS PIPELINE  (shared by all three extents ops)
 * ----------------------------------------------------------------------------
 *   1. FLATTEN the geometry to DEVICE space (CTM applied CPU-side at flatten
 *      time, exactly like the fill/stroke draw path -- cm_path_flatten for the
 *      fill case; cm_stroke_expand already emits device-space outline geometry
 *      for the stroke case).
 *   2. TIGHT DEVICE BOUNDS of the flattened polyline (cm_tight_dev_bounds) --
 *      the exact polyline extent with NO MSAA cover-quad guard band (that pad is
 *      a rasterization detail and must never leak into a reported extent).
 *   3. INVERSE CTM -> USER AABB: map the device AABB's four corners back through
 *      the inverse CTM and take their bounding box (cm_matrix_transform_bbox),
 *      yielding the user-space extents cairo reports.
 *
 * This mirrors cm_clip_extents_user() in cm_clip.m verbatim (device AABB ->
 * cm_matrix_invert -> cm_matrix_transform_bbox).  For manim's axis-aligned CTM
 * (xx, yy only; xy = yx = 0) the round trip is EXACT.  Under a rotated/sheared
 * CTM the inverse image of an axis-aligned device box is a rotated quad whose
 * user-space AABB is a conservative SUPERSET of the true user extents -- the
 * same (acceptable) looseness cairo's own bbox-of-flattened approach and this
 * library's clip extents already have.
 *
 * ----------------------------------------------------------------------------
 * UNITS / CLIP  (match cairo exactly)
 * ----------------------------------------------------------------------------
 * Line width is in USER space; like cm_stroke_preserve in cairo_metal.m we scale
 * it to device units by the CTM's max singular value (cm_matrix_max_scale) before
 * handing it to cm_stroke_expand, which consumes a device-space width.  manim's
 * CTM is isotropic in magnitude so the scalar device width is exact.
 *
 * cairo's in_fill / in_stroke / fill_extents / stroke_extents do NOT consult the
 * clip or the surface bounds -- they describe the path's own filled/stroked
 * geometry.  We therefore deliberately do not intersect ctx->clip here (that is
 * cm_in_clip / cm_clip_extents in cm_clip.m).
 * ============================================================================
 */

#include "cm_internal.h"

#include <math.h>

/* ==========================================================================
 * Shared point-in-polygon over a path's flattened contours (DEVICE space)
 * --------------------------------------------------------------------------
 * Classic ray-crossing (Jordan curve) test: cast a ray from the query point in
 * the +x direction and count how the path's edges cross it.  Every contour is
 * IMPLICITLY CLOSED (edge from the last point back to the first), matching the
 * fill semantics cairo uses -- a fill always closes open sub-paths.
 *
 *   - WINDING (nonzero): accumulate a SIGNED winding number (+1 for an edge
 *     crossing upward through the ray, -1 downward); the point is inside iff the
 *     total winding != 0.
 *   - EVEN_ODD: count crossings mod 2 (parity); inside iff an odd number cross.
 *
 * The half-open crossing predicate `(ay > y) != (by > y)` counts a vertex that
 * lies exactly on the ray for only ONE of its two incident edges, which avoids
 * the classic double-count at shared vertices and makes the test watertight for
 * polygons.  Because the predicate guarantees ay != by on a counted edge, the
 * parametric x of the crossing never divides by zero.
 *
 * Returns strictly 0 (outside) or 1 (inside).  Consumed by cm_in_fill /
 * cm_in_stroke (below) and by cm_in_clip (cm_clip.m); the (dx,dy) point and the
 * contours are BOTH in device space at the call sites.
 * ========================================================================== */
int cm_point_in_contours(const cm_path *path, double dx, double dy,
                         cm_fill_rule_t rule)
{
    if (!path || path->contour_count == 0 || path->pts_count == 0)
        return 0;

    int winding = 0;   /* signed crossing count  (WINDING / nonzero) */
    int parity  = 0;   /* crossing parity         (EVEN_ODD)         */

    for (uint32_t ci = 0; ci < path->contour_count; ++ci) {
        const cm_contour *c = &path->contours[ci];
        uint32_t n = c->point_count;
        if (n < 2) continue;                 /* <2 points enclose no area */
        const cm_vec2f *pts = &path->pts[c->first_point];

        for (uint32_t i = 0; i < n; ++i) {
            const cm_vec2f *a = &pts[i];
            const cm_vec2f *b = &pts[(i + 1u) % n];   /* implicit close edge */
            double ay = (double)a->y, by = (double)b->y;

            /* Half-open vertical span test: does the +x ray at y=dy cross the
             * edge a->b?  True for exactly one of the two edges meeting at a
             * vertex that sits on the ray, so shared vertices count once. */
            if ((ay > dy) != (by > dy)) {
                double ax = (double)a->x, bx = (double)b->x;
                /* x-coordinate where edge a->b crosses the ray (by != ay here). */
                double t  = (dy - ay) / (by - ay);
                double xc = ax + t * (bx - ax);
                if (xc > dx) {
                    parity ^= 1;
                    winding += (by > ay) ? 1 : -1;
                }
            }
        }
    }

    if (rule == CM_FILL_RULE_EVEN_ODD)
        return parity != 0;
    return winding != 0;
}

/* ==========================================================================
 * Extents helpers
 * ========================================================================== */

/* TIGHT device-space AABB of a FLATTENED path (its pts cache); NO MSAA guard
 * band -- the exact polyline extent.  This is the query-side counterpart of
 * cm_path's cover-quad bounds (which pad by half a pixel for MSAA): an extent
 * must report the true geometry, not the rasterizer's padded cover quad.
 * Returns 1 and fills the box when the cache has points, else 0 (box untouched).
 * Mirrors cm_clip_dev_bounds in cm_clip.m. */
static int cm_tight_dev_bounds(const cm_path *p,
                               double *minx, double *miny,
                               double *maxx, double *maxy)
{
    if (!p || p->pts_count == 0) return 0;

    double lo_x = (double)p->pts[0].x, hi_x = lo_x;
    double lo_y = (double)p->pts[0].y, hi_y = lo_y;
    for (uint32_t i = 1; i < p->pts_count; ++i) {
        double x = (double)p->pts[i].x, y = (double)p->pts[i].y;
        if (x < lo_x) lo_x = x; else if (x > hi_x) hi_x = x;
        if (y < lo_y) lo_y = y; else if (y > hi_y) hi_y = y;
    }
    *minx = lo_x; *miny = lo_y; *maxx = hi_x; *maxy = hi_y;
    return 1;
}

/* Map a flattened path's TIGHT device bounds back to USER space via the inverse
 * CTM and write the user-space AABB (step 2 + step 3 of the extents pipeline).
 * Writes a degenerate (0,0,0,0) box when `flat` has no geometry.  A singular CTM
 * (no device->user map) falls back to reporting the device box unmapped, which
 * is the best available answer and keeps callers from reading uninitialized
 * memory -- consistent with cm_clip_extents_user's singular-CTM fallback. */
static void cm_user_extents_of_flattened(const cm_context_t *ctx,
                                         const cm_path *flat,
                                         double *x1, double *y1,
                                         double *x2, double *y2)
{
    double dminx, dminy, dmaxx, dmaxy;
    if (!cm_tight_dev_bounds(flat, &dminx, &dminy, &dmaxx, &dmaxy)) {
        if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
        return;
    }

    cm_matrix_t inv = ctx->ctm;
    if (cm_matrix_invert(&inv) != CM_STATUS_SUCCESS) {
        if (x1) *x1 = dminx; if (y1) *y1 = dminy;
        if (x2) *x2 = dmaxx; if (y2) *y2 = dmaxy;
        return;
    }

    /* Transform the four device-box corners and take their bounding box; for an
     * axis-aligned CTM this is exact, otherwise a conservative superset. */
    cm_matrix_transform_bbox(&inv, dminx, dminy, dmaxx, dmaxy, x1, y1, x2, y2);
}

/* The device-space line width cm_stroke_expand consumes: the user-space width
 * scaled by the CTM's max singular value (device px per user unit).  Identical
 * to the conversion cm_stroke_preserve performs in cairo_metal.m, so the
 * reported stroke extents / hit test match the geometry that actually draws. */
static inline double cm_device_line_width(const cm_context_t *ctx)
{
    return ctx->line_width * cm_matrix_max_scale(&ctx->ctm);
}

/* The stroke-expansion arc tolerance, matching cairo_metal.m's stroke path:
 * the context tolerance when positive, else the library default. */
static inline double cm_stroke_tolerance(const cm_context_t *ctx)
{
    return (ctx->tolerance > 0.0) ? ctx->tolerance : CM_ARC_TOLERANCE;
}

/* Expand the (already device-space-flattened) current path into a fillable
 * outline polygon in `out`, reusing cm_stroke_expand VERBATIM with the same
 * width/join/cap/miter/tolerance the real stroke draw uses.  A dash pattern is
 * applied first (cm_dash_prepass), exactly as the draw path does, so reported
 * extents / hit tests match the dashed geometry that actually draws; with no
 * dash this is the same single cm_stroke_expand as before.  `out` must be a fresh
 * cm_path_init'd path owned by the caller (freed by it).  Returns the build
 * status (cm_dash_prepass or cm_stroke_expand).
 *
 * INVALID_DASH cannot normally fire here -- cm_set_dash validates the pattern at
 * set time -- so, like the flatten/OOM failures the query entry points already
 * swallow, a non-SUCCESS return just makes them report an empty box / not-inside
 * rather than mutating ctx status (these are pure, best-effort queries). */
static cm_status_t cm_build_stroke_outline(const cm_context_t *ctx, cm_path *out)
{
    /* Dash scratch (device-space on-pieces) lives across this call only.  When no
     * dash is set, src stays == &ctx->path and `dashed` is left empty. */
    cm_path dashed;
    cm_path_init(&dashed);
    const cm_path *src = &ctx->path;
    cm_status_t st = cm_dash_prepass(ctx, &ctx->path, &dashed, &src);
    if (st == CM_STATUS_SUCCESS)
        st = cm_stroke_expand(src, out, cm_device_line_width(ctx),
                              ctx->line_join, ctx->line_cap, ctx->miter_limit,
                              cm_stroke_tolerance(ctx));
    cm_path_free(&dashed);
    return st;
}

/* ==========================================================================
 * cm_fill_extents / cm_stroke_extents
 * ==========================================================================
 * Both flatten the current path with the CTM (CPU-side, like the draw path),
 * then report the tight user-space AABB of what a fill / stroke of that path
 * would cover.  An empty (no-verb) path reports an empty (0,0,0,0) box, matching
 * cairo (which collapses to x1=y1=x2=y2=0 for an empty path).
 * ========================================================================== */

void cm_fill_extents(cm_context_t *ctx,
                     double *x1, double *y1, double *x2, double *y2)
{
    if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
    if (!ctx) return;

    /* Empty path -> empty extents; don't touch the flattened cache. */
    if (ctx->path.verb_count == 0) return;

    /* Flatten the recorded path to device space using the current CTM.  This is
     * idempotent while the path is clean (cm_path_flatten), so it cheaply reuses
     * a cache left by a preceding fill/stroke of the same path. */
    if (cm_path_flatten(&ctx->path, &ctx->ctm) != CM_STATUS_SUCCESS)
        return;   /* singular CTM / OOM: leave the empty box */

    cm_user_extents_of_flattened(ctx, &ctx->path, x1, y1, x2, y2);
}

void cm_stroke_extents(cm_context_t *ctx,
                       double *x1, double *y1, double *x2, double *y2)
{
    if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
    if (!ctx) return;

    /* Empty path or a degenerate (<=0) line width covers nothing -> empty box
     * (cairo: a zero-width stroke has empty extents). */
    if (ctx->path.verb_count == 0) return;
    if (!(ctx->line_width > 0.0)) return;

    if (cm_path_flatten(&ctx->path, &ctx->ctm) != CM_STATUS_SUCCESS)
        return;

    /* Expand to a device-space outline polygon, then bound + inverse-map.  The
     * outline already carries the half-width expansion in device space, so its
     * tight bounds are the stroke's device footprint. */
    cm_path outline;
    cm_path_init(&outline);
    if (cm_build_stroke_outline(ctx, &outline) == CM_STATUS_SUCCESS)
        cm_user_extents_of_flattened(ctx, &outline, x1, y1, x2, y2);
    cm_path_free(&outline);
}

/* ==========================================================================
 * cm_in_fill / cm_in_stroke
 * ==========================================================================
 * Transform the USER-space query point by the CTM to DEVICE space (where the
 * flattened cache / stroke outline live), then point-in-polygon.  cairo does NOT
 * take the clip or surface bounds into account for these tests, so neither do we.
 * ========================================================================== */

int cm_in_fill(cm_context_t *ctx, double x, double y)
{
    if (!ctx) return 0;
    if (ctx->path.verb_count == 0) return 0;

    if (cm_path_flatten(&ctx->path, &ctx->ctm) != CM_STATUS_SUCCESS)
        return 0;

    /* User -> device, matching the device-space flattened contours. */
    double dx = x, dy = y;
    cm_matrix_transform_point(&ctx->ctm, &dx, &dy);
    return cm_point_in_contours(&ctx->path, dx, dy, ctx->fill_rule);
}

int cm_in_stroke(cm_context_t *ctx, double x, double y)
{
    if (!ctx) return 0;
    if (ctx->path.verb_count == 0) return 0;
    if (!(ctx->line_width > 0.0)) return 0;   /* degenerate stroke contains nothing */

    if (cm_path_flatten(&ctx->path, &ctx->ctm) != CM_STATUS_SUCCESS)
        return 0;

    cm_path outline;
    cm_path_init(&outline);

    int inside = 0;
    if (cm_build_stroke_outline(ctx, &outline) == CM_STATUS_SUCCESS) {
        double dx = x, dy = y;
        cm_matrix_transform_point(&ctx->ctm, &dx, &dy);
        /* The stroke outline is a union of overlapping convex pieces filled with
         * NONZERO winding (cm_stroke_expand / cm_fill semantics), so the hit test
         * uses WINDING regardless of the context fill rule. */
        inside = cm_point_in_contours(&outline, dx, dy, CM_FILL_RULE_WINDING);
    }

    cm_path_free(&outline);
    return inside;
}

/* ==========================================================================
 * BUILD-PHASE SEAM (read this in the reconcile step)
 * --------------------------------------------------------------------------
 * 1. cm_point_in_contours() is the SHARED point-in-polygon owned by this file
 *    and declared in cm_internal.h.  cm_clip.m calls it (cm_in_clip ->
 *    cm_clip_contains) on the clip-state's stored DEVICE-space contours with the
 *    clip's fill rule.  Both call sites pass a DEVICE-space point + device-space
 *    contours; the contract (device space on both sides) must hold if either
 *    module's flatten space ever changes.  No other definition of this symbol
 *    exists (cm_query.c is the sole owner).
 *
 * 2. The PUBLIC cm_path_extents() is intentionally NOT defined here -- it is
 *    owned by cm_path.m (it consumes that module's user-space flatten +
 *    recorded-verb arena).  This file owns only cm_fill_extents /
 *    cm_stroke_extents / cm_in_fill / cm_in_stroke.  If a later refactor folds
 *    all extents into one place, move cm_path_extents here and share
 *    cm_user_extents_of_flattened; until then keep them split so each public
 *    symbol is defined exactly once.
 *
 * 3. Device line-width conversion (cm_device_line_width) duplicates the scalar
 *    ctx->line_width * cm_matrix_max_scale(ctm) computed in cm_stroke_preserve
 *    (cairo_metal.m).  Kept file-local so this module has no cross-module symbol
 *    dependency; if a shared helper is later exported from cm_internal.h, collapse
 *    both onto it.  Both assume an isotropic-magnitude CTM (exact for manim).
 * ========================================================================== */
