/*
 * cm_path.m  --  CairoMetal path module
 * ============================================================================
 *
 * Owner module for the `cm_path` half of the internal contract
 * (src/cm_internal.h, "MODULE: cm_path.c"):
 *
 *   - path RECORDING in USER space (new_path / new_sub_path / move_to /
 *     line_to / curve_to / close_path) into the cm_path verb+xy arrays;
 *   - adaptive CUBIC-Bezier FLATTENING to line segments, with the flatness
 *     test performed in DEVICE space (CTM applied CPU-side at flatten time)
 *     so on-screen deviation is bounded by CM_FLATTEN_TOLERANCE regardless of
 *     the CTM scale;
 *   - TESSELLATION PREP for the stencil-then-cover pipeline: triangle-fan
 *     vertices about each contour's first point, the fan vertex count for a
 *     single ring allocation, and the device-space bounding box for the cover
 *     quad.
 *
 * This translation unit is pure C (it touches no Metal / Objective-C objects;
 * it only fills POD arrays in cm_path and the cm_vec2f buffer that cm_fill.c
 * bump-allocates from the per-frame ring).  It is compiled as `.m` purely to
 * match the assigned file name in the module map; nothing here needs the
 * Objective-C runtime.
 *
 * PERFORMANCE CONTRACT (see DESIGN.md §4.5 "zero per-draw heap allocation"):
 * the recorded-control and flattened-cache arrays grow AMORTIZED (geometric
 * doubling) and are RESET, NOT FREED, between frames.  cm_path_reset keeps the
 * capacity so the steady-state per-frame path build does no malloc; only
 * cm_path_free releases the storage, and growth past the high-water mark is
 * the only time the hot path can allocate.
 *
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ==========================================================================
 * Tunables local to flattening
 * ========================================================================== */

/* Hard cap on de Casteljau recursion depth.  At depth D a cubic is split into
 * 2^D segments; 18 -> up to 262144 segments, which is far more than any sane
 * on-screen curve needs and bounds worst-case work / stack use even for a
 * pathological (near-cusp or hugely scaled) curve where the flatness metric
 * converges slowly.  Adaptive subdivision normally stops *long* before this. */
#define CM_FLATTEN_MAX_DEPTH    18

/* Initial capacities for the amortized-growth arrays.  Chosen so a typical
 * VMobject contour (a few dozen cubics) builds without reallocating after the
 * first frame, while keeping idle paths small. */
#define CM_PATH_INIT_VERBS      64u
#define CM_PATH_INIT_XY         256u    /* doubles (= 128 user-space points)   */
#define CM_PATH_INIT_PTS        256u    /* flattened cm_vec2f points           */
#define CM_PATH_INIT_CONTOURS   8u

/* ==========================================================================
 * Small amortized-growth helpers
 * --------------------------------------------------------------------------
 * Each returns true on success, false if realloc failed (caller maps that to
 * CM_STATUS_NO_MEMORY).  Capacity grows geometrically (x2) so N appends cost
 * O(N) amortized and the steady state never reallocates.
 * ========================================================================== */

static bool cm__ensure_verbs(cm_path *p, uint32_t need_extra)
{
    uint32_t need = p->verb_count + need_extra;
    if (need <= p->verb_cap) return true;
    uint32_t cap = p->verb_cap ? p->verb_cap : CM_PATH_INIT_VERBS;
    while (cap < need) cap <<= 1;
    uint8_t *nv = (uint8_t *)realloc(p->verbs, (size_t)cap * sizeof(uint8_t));
    if (!nv) return false;
    p->verbs = nv;
    p->verb_cap = cap;
    return true;
}

/* need_extra is a count of DOUBLES (2 per point). */
static bool cm__ensure_xy(cm_path *p, uint32_t need_extra)
{
    uint32_t need = p->xy_count + need_extra;
    if (need <= p->xy_cap) return true;
    uint32_t cap = p->xy_cap ? p->xy_cap : CM_PATH_INIT_XY;
    while (cap < need) cap <<= 1;
    double *nx = (double *)realloc(p->verbs_xy, (size_t)cap * sizeof(double));
    if (!nx) return false;
    p->verbs_xy = nx;
    p->xy_cap = cap;
    return true;
}

static bool cm__ensure_pts(cm_path *p, uint32_t need_extra)
{
    uint32_t need = p->pts_count + need_extra;
    if (need <= p->pts_cap) return true;
    uint32_t cap = p->pts_cap ? p->pts_cap : CM_PATH_INIT_PTS;
    while (cap < need) cap <<= 1;
    cm_vec2f *np = (cm_vec2f *)realloc(p->pts, (size_t)cap * sizeof(cm_vec2f));
    if (!np) return false;
    p->pts = np;
    p->pts_cap = cap;
    return true;
}

static bool cm__ensure_contours(cm_path *p, uint32_t need_extra)
{
    uint32_t need = p->contour_count + need_extra;
    if (need <= p->contour_cap) return true;
    uint32_t cap = p->contour_cap ? p->contour_cap : CM_PATH_INIT_CONTOURS;
    while (cap < need) cap <<= 1;
    cm_contour *nc = (cm_contour *)realloc(p->contours,
                                           (size_t)cap * sizeof(cm_contour));
    if (!nc) return false;
    p->contours = nc;
    p->contour_cap = cap;
    return true;
}

/* Record one verb + (optionally) its interleaved point args.  npts points are
 * read from `xy` (length 2*npts doubles).  On OOM the path is left consistent
 * (nothing appended) and the edit is dropped; the next flatten still works on
 * what was recorded so far.  Recording never reports status directly (cairo's
 * path-build calls are void); a failed flatten surfaces NO_MEMORY instead. */
static void cm__record(cm_path *p, cm_path_verb verb,
                       const double *xy, uint32_t npts)
{
    if (!cm__ensure_verbs(p, 1)) return;
    if (npts) {
        if (!cm__ensure_xy(p, npts * 2u)) return;
        memcpy(p->verbs_xy + p->xy_count, xy, (size_t)npts * 2u * sizeof(double));
        p->xy_count += npts * 2u;
    }
    p->verbs[p->verb_count++] = (uint8_t)verb;
    p->dirty = true;
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */

void cm_path_init(cm_path *p)
{
    if (!p) return;
    memset(p, 0, sizeof(*p));
    /* All pointers NULL, all counts/caps 0; first append lazily allocates.
     * has_current=false, dirty=false: an empty path flattens to nothing. */
}

/*
 * cm_new_path / cm_path_reset: clear the recorded verbs AND the flattened
 * cache, returning to the empty-path state, but KEEP the backing allocations
 * so the next frame's path build is malloc-free (DESIGN.md §4.5).  This is the
 * per-frame hot-path reset.
 */
void cm_path_reset(cm_path *p)
{
    if (!p) return;
    p->verb_count = 0;
    p->xy_count   = 0;
    p->pts_count  = 0;
    p->contour_count = 0;
    p->cur_x = p->cur_y = 0.0;
    p->sub_x = p->sub_y = 0.0;
    p->has_current = false;
    p->dirty = false;   /* empty path: nothing to flatten */
}

void cm_path_free(cm_path *p)
{
    if (!p) return;
    free(p->verbs_xy);
    free(p->verbs);
    free(p->pts);
    free(p->contours);
    memset(p, 0, sizeof(*p));
}

/* ==========================================================================
 * Recording (USER space)
 * --------------------------------------------------------------------------
 * Mirrors cairo's path-construction semantics exactly for the subset manim
 * uses.  Current-point / sub-path-start bookkeeping here is what gives the
 * later flatten an unambiguous, well-formed verb stream.
 * ========================================================================== */

void cm_path_move_to(cm_path *p, double x, double y)
{
    if (!p) return;
    double xy[2] = { x, y };
    cm__record(p, CM_VERB_MOVE, xy, 1);
    p->cur_x = x; p->cur_y = y;     /* current point          */
    p->sub_x = x; p->sub_y = y;     /* start of this sub-path */
    p->has_current = true;
}

void cm_path_line_to(cm_path *p, double x, double y)
{
    if (!p) return;
    /* cairo: line_to with no current point behaves like move_to. */
    if (!p->has_current) {
        cm_path_move_to(p, x, y);
        return;
    }
    double xy[2] = { x, y };
    cm__record(p, CM_VERB_LINE, xy, 1);
    p->cur_x = x; p->cur_y = y;
    /* has_current stays true; sub-path start unchanged */
}

void cm_path_curve_to(cm_path *p, double x1, double y1,
                                  double x2, double y2,
                                  double x3, double y3)
{
    if (!p) return;
    /* cairo: curve_to with no current point behaves as if move_to(x1,y1) was
     * issued first, so the curve has a defined start.  Record that move so the
     * flatten step has p0 available as the first control point. */
    if (!p->has_current) {
        cm_path_move_to(p, x1, y1);
    }
    double xy[6] = { x1, y1, x2, y2, x3, y3 };
    cm__record(p, CM_VERB_CURVE, xy, 3);
    p->cur_x = x3; p->cur_y = y3;
    /* has_current stays true; sub-path start unchanged */
}

void cm_path_close(cm_path *p)
{
    if (!p) return;
    /* close_path on an empty contour (no current point) is a no-op in cairo. */
    if (!p->has_current) return;
    cm__record(p, CM_VERB_CLOSE, NULL, 0);
    /* cairo: after close_path the current point becomes the sub-path start,
     * and a new sub-path implicitly begins there, so a following line_to/
     * curve_to continues from the start point. */
    p->cur_x = p->sub_x; p->cur_y = p->sub_y;
    p->has_current = true;
}

void cm_path_new_sub(cm_path *p)
{
    if (!p) return;
    /* cairo new_sub_path: begin a fresh contour with NO current point.  The
     * following move_to/line_to/curve_to establishes the new contour's start;
     * a close_path before that point exists affects only this empty contour. */
    cm__record(p, CM_VERB_NEW_SUB, NULL, 0);
    p->has_current = false;
    /* current point intentionally undefined until next move/line/curve */
}

/* ==========================================================================
 * Flattening (USER space cubics -> DEVICE space polylines)
 * ==========================================================================
 *
 * The CTM is applied HERE, point by point, via cm_matrix_apply, so the flatness
 * test runs entirely in device pixels and on-screen error is bounded by
 * CM_FLATTEN_TOLERANCE at any zoom (DESIGN.md §3, Pass 0).  Cubics are split by
 * adaptive recursive de Casteljau; lines pass through unchanged.
 */

/* Flatness metric for a device-space cubic (p0,p1,p2,p3): the maximum distance
 * of the two interior control points from the chord p0->p3.  This is the
 * standard conservative cubic flatness test — when both control points lie
 * within `tol` of the chord, the chord approximates the curve to within `tol`.
 * We compare squared distances against tol^2 to avoid sqrt in the hot loop.
 *
 * Returns true when the cubic is flat enough to emit as a single segment. */
static bool cm__cubic_is_flat(double p0x, double p0y,
                              double p1x, double p1y,
                              double p2x, double p2y,
                              double p3x, double p3y,
                              double tol2)
{
    double dx = p3x - p0x;
    double dy = p3y - p0y;
    double chord2 = dx * dx + dy * dy;

    if (chord2 < 1e-12) {
        /* Degenerate chord (p0 == p3): the chord has no direction, so fall
         * back to absolute distance of the control points from p0.  This also
         * catches tiny loops where the endpoints coincide but the controls
         * bulge out. */
        double d1x = p1x - p0x, d1y = p1y - p0y;
        double d2x = p2x - p0x, d2y = p2y - p0y;
        double m = d1x * d1x + d1y * d1y;
        double n = d2x * d2x + d2y * d2y;
        if (n > m) m = n;
        return m <= tol2;
    }

    /* Perpendicular distance^2 of a control point c from the infinite line
     * through p0 with direction (dx,dy) is cross(c-p0, d)^2 / |d|^2. */
    double c1 = (p1x - p0x) * dy - (p1y - p0y) * dx;   /* cross, scaled by |d| */
    double c2 = (p2x - p0x) * dy - (p2y - p0y) * dx;
    double d1_2 = (c1 * c1) / chord2;
    double d2_2 = (c2 * c2) / chord2;
    double maxd2 = (d1_2 > d2_2) ? d1_2 : d2_2;
    return maxd2 <= tol2;
}

/* Recursive de Casteljau subdivision of a DEVICE-space cubic.  Appends every
 * point EXCEPT p0 (the caller already emitted the start) up to and including
 * p3, in order, so concatenating across a contour yields a continuous
 * polyline.  Returns false on OOM. */
static bool cm__flatten_cubic_rec(cm_path *p,
                                  double p0x, double p0y,
                                  double p1x, double p1y,
                                  double p2x, double p2y,
                                  double p3x, double p3y,
                                  double tol2, int depth)
{
    if (depth >= CM_FLATTEN_MAX_DEPTH ||
        cm__cubic_is_flat(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y, tol2)) {
        if (!cm__ensure_pts(p, 1)) return false;
        p->pts[p->pts_count].x = (float)p3x;
        p->pts[p->pts_count].y = (float)p3y;
        p->pts_count++;
        return true;
    }

    /* Split at t = 0.5 (de Casteljau).  Subdivision is in device space so the
     * midpoints are computed where the flatness test lives. */
    double p01x = (p0x + p1x) * 0.5, p01y = (p0y + p1y) * 0.5;
    double p12x = (p1x + p2x) * 0.5, p12y = (p1y + p2y) * 0.5;
    double p23x = (p2x + p3x) * 0.5, p23y = (p2y + p3y) * 0.5;
    double p012x = (p01x + p12x) * 0.5, p012y = (p01y + p12y) * 0.5;
    double p123x = (p12x + p23x) * 0.5, p123y = (p12y + p23y) * 0.5;
    double mx = (p012x + p123x) * 0.5, my = (p012y + p123y) * 0.5;

    /* Left half: p0, p01, p012, m  — emits points up to and including m. */
    if (!cm__flatten_cubic_rec(p, p0x, p0y, p01x, p01y, p012x, p012y, mx, my,
                               tol2, depth + 1))
        return false;
    /* Right half: m, p123, p23, p3 — emits points after m up to p3. */
    if (!cm__flatten_cubic_rec(p, mx, my, p123x, p123y, p23x, p23y, p3x, p3y,
                               tol2, depth + 1))
        return false;
    return true;
}

/* Begin a new contour anchored at index pts_count.  has_point indicates
 * whether a starting point is already present (move_to) or pending (new_sub).
 * Returns the contour index or UINT32_MAX on OOM. */
static uint32_t cm__begin_contour(cm_path *p, bool has_point)
{
    if (!cm__ensure_contours(p, 1)) return UINT32_MAX;
    uint32_t ci = p->contour_count++;
    cm_contour *c = &p->contours[ci];
    c->first_point = p->pts_count;
    c->point_count = 0;
    c->closed = false;
    c->has_current = has_point;
    return ci;
}

/* Append one device-space point to the current contour `ci`. */
static bool cm__contour_push_point(cm_path *p, uint32_t ci, double dx, double dy)
{
    if (!cm__ensure_pts(p, 1)) return false;
    p->pts[p->pts_count].x = (float)dx;
    p->pts[p->pts_count].y = (float)dy;
    p->pts_count++;
    p->contours[ci].point_count++;
    return true;
}

cm_status_t cm_path_flatten(cm_path *p, const cm_matrix_t *ctm)
{
    if (!p || !ctm) return CM_STATUS_NO_MEMORY;

    /* A non-invertible CTM collapses geometry; cairo treats that as an error
     * (CAIRO_STATUS_INVALID_MATRIX).  Report it rather than emit garbage. */
    if (!cm_matrix_is_invertible(ctm))
        return CM_STATUS_INVALID_MATRIX;

    /* Idempotent while clean (DESIGN.md / contract): if nothing was edited
     * since the last flatten with the SAME geometry, the cache is still valid.
     * NOTE: cm_path stores no cached CTM, so the caller (cm_context.c) is
     * responsible for marking the path dirty if the CTM changes between draws
     * of the same recorded path.  Within a single VMobject draw the CTM is
     * fixed (camera.py sets it once per frame), so this is safe and matches the
     * "Idempotent while p->dirty is false" contract. */
    if (!p->dirty && p->contour_count > 0)
        return CM_STATUS_SUCCESS;

    /* Rebuild the flattened cache from scratch. */
    p->pts_count = 0;
    p->contour_count = 0;

    /* Tolerance lives in DEVICE pixels because we transform control points to
     * device space before testing.  cm_matrix_max_scale is therefore NOT used
     * to scale the tolerance (that would double-count); we keep the raw
     * device-space tolerance.  We still consult max_scale only as a guard for
     * the degenerate zero-scale case (already excluded by the invertibility
     * check above). */
    const double tol  = CM_FLATTEN_TOLERANCE;
    const double tol2 = tol * tol;

    uint32_t vi = 0;        /* verb cursor                       */
    uint32_t xi = 0;        /* xy (double) cursor                */
    uint32_t ci = UINT32_MAX; /* current contour index, or none  */

    /* Device-space current point, tracked across verbs for cubic starts. */
    double cdx = 0.0, cdy = 0.0;
    bool have_cur = false;

    for (vi = 0; vi < p->verb_count; vi++) {
        cm_path_verb verb = (cm_path_verb)p->verbs[vi];

        switch (verb) {

        case CM_VERB_MOVE: {
            double ux = p->verbs_xy[xi++];
            double uy = p->verbs_xy[xi++];
            double dx, dy;
            cm_matrix_apply(ctm, ux, uy, &dx, &dy);
            /* move starts a fresh contour with its first point present */
            ci = cm__begin_contour(p, true);
            if (ci == UINT32_MAX) return CM_STATUS_NO_MEMORY;
            if (!cm__contour_push_point(p, ci, dx, dy))
                return CM_STATUS_NO_MEMORY;
            cdx = dx; cdy = dy; have_cur = true;
            break;
        }

        case CM_VERB_LINE: {
            double ux = p->verbs_xy[xi++];
            double uy = p->verbs_xy[xi++];
            double dx, dy;
            cm_matrix_apply(ctm, ux, uy, &dx, &dy);
            if (ci == UINT32_MAX) {
                /* No open contour.  Two sub-cases (cairo semantics):           */
                ci = cm__begin_contour(p, true);
                if (ci == UINT32_MAX) return CM_STATUS_NO_MEMORY;
                if (have_cur) {
                    /* After close_path: a line_to begins a new sub-path that
                     * starts (implicit move_to) at the closed sub-path's start
                     * point — which is the device-space current point — then
                     * draws to the endpoint.  Seed the contour with it. */
                    if (!cm__contour_push_point(p, ci, cdx, cdy))
                        return CM_STATUS_NO_MEMORY;
                    if (!cm__contour_push_point(p, ci, dx, dy))
                        return CM_STATUS_NO_MEMORY;
                } else {
                    /* No current point (start of path / after new_sub_path):
                     * line_to behaves like move_to — the endpoint is the new
                     * contour's only point so far. */
                    if (!cm__contour_push_point(p, ci, dx, dy))
                        return CM_STATUS_NO_MEMORY;
                }
            } else {
                if (!cm__contour_push_point(p, ci, dx, dy))
                    return CM_STATUS_NO_MEMORY;
            }
            cdx = dx; cdy = dy; have_cur = true;
            break;
        }

        case CM_VERB_CURVE: {
            double u1x = p->verbs_xy[xi++], u1y = p->verbs_xy[xi++];
            double u2x = p->verbs_xy[xi++], u2y = p->verbs_xy[xi++];
            double u3x = p->verbs_xy[xi++], u3y = p->verbs_xy[xi++];
            double d1x, d1y, d2x, d2y, d3x, d3y;
            cm_matrix_apply(ctm, u1x, u1y, &d1x, &d1y);
            cm_matrix_apply(ctm, u2x, u2y, &d2x, &d2y);
            cm_matrix_apply(ctm, u3x, u3y, &d3x, &d3y);

            if (ci == UINT32_MAX) {
                /* No open contour (cairo semantics):                           */
                ci = cm__begin_contour(p, true);
                if (ci == UINT32_MAX) return CM_STATUS_NO_MEMORY;
                if (have_cur) {
                    /* After close_path: the curve begins a new sub-path whose
                     * start (implicit move_to) is the closed sub-path's start
                     * point — the current device point.  Seed the contour with
                     * it; the cubic is then flattened from (cdx,cdy). */
                    if (!cm__contour_push_point(p, ci, cdx, cdy))
                        return CM_STATUS_NO_MEMORY;
                } else {
                    /* No current point: start at the first control point (the
                     * recorder also inserts a MOVE for this case, but guard
                     * anyway).  Flatten from there. */
                    if (!cm__contour_push_point(p, ci, d1x, d1y))
                        return CM_STATUS_NO_MEMORY;
                    cdx = d1x; cdy = d1y; have_cur = true;
                }
            }

            /* Flatten the device-space cubic (cdx,cdy)->(d1)->(d2)->(d3).
             * cm__flatten_cubic_rec appends everything after the start point,
             * so the points belong to the current contour: bump its count by
             * the number of points appended. */
            uint32_t before = p->pts_count;
            if (!cm__flatten_cubic_rec(p, cdx, cdy, d1x, d1y, d2x, d2y,
                                       d3x, d3y, tol2, 0))
                return CM_STATUS_NO_MEMORY;
            p->contours[ci].point_count += (p->pts_count - before);

            cdx = d3x; cdy = d3y; have_cur = true;
            break;
        }

        case CM_VERB_CLOSE: {
            if (ci != UINT32_MAX) {
                p->contours[ci].closed = true;
                /* After close the current point returns to the contour start
                 * (cairo); device-space start is the contour's first point. */
                if (p->contours[ci].point_count > 0) {
                    cm_vec2f s = p->pts[p->contours[ci].first_point];
                    cdx = s.x; cdy = s.y; have_cur = true;
                }
                /* cairo: close_path implicitly begins a NEW sub-path at that
                 * start point, so a following line_to/curve_to opens a fresh
                 * contour (seeded from the current point above) rather than
                 * appending to the just-closed one.  Drop the open contour but
                 * KEEP have_cur/cdx/cdy as the seed. */
                ci = UINT32_MAX;
            }
            break;
        }

        case CM_VERB_NEW_SUB: {
            /* Begin a fresh contour with NO point yet; the next move/line/
             * curve fills it.  We do not allocate a contour now (an empty
             * contour would add a zero-point entry); instead drop the current
             * contour so the next point-producing verb opens a new one. */
            ci = UINT32_MAX;
            have_cur = false;
            break;
        }

        default:
            /* Unknown verb: skip defensively.  Should never happen. */
            break;
        }
    }

    p->dirty = false;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Tessellation prep for stencil-then-cover
 * ==========================================================================
 *
 * The stencil pass needs, per contour, a triangle FAN about the contour's
 * first vertex.  A contour with n points yields (n-2) triangles = 3*(n-2)
 * vertices.  Contours with fewer than 3 points enclose no area and contribute
 * nothing.  Overlapping fan triangles of a concave/self-intersecting contour
 * are resolved by the winding/even-odd stencil ops, so no real triangulation
 * is required (DESIGN.md §3, Pass 1).
 */

/* Per-contour fan vertex count: 3*(n-2) for n>=3, else 0. */
static inline uint32_t cm__contour_fan_verts(uint32_t n)
{
    return (n >= 3u) ? 3u * (n - 2u) : 0u;
}

uint32_t cm_path_fan_vertex_count(const cm_path *p)
{
    if (!p) return 0u;
    uint32_t total = 0u;
    for (uint32_t i = 0; i < p->contour_count; i++)
        total += cm__contour_fan_verts(p->contours[i].point_count);
    return total;
}

uint32_t cm_path_emit_fan(const cm_path *p, uint32_t contour_index,
                          cm_vec2f *dst)
{
    if (!p || !dst || contour_index >= p->contour_count) return 0u;

    const cm_contour *c = &p->contours[contour_index];
    uint32_t n = c->point_count;
    if (n < 3u) return 0u;          /* no area -> no stencil contribution */

    const cm_vec2f *src = &p->pts[c->first_point];
    const cm_vec2f anchor = src[0];

    /* Fan: (anchor, src[i], src[i+1]) for i = 1 .. n-2.  Vertex order follows
     * the contour's own orientation; the two-sided NONZERO stencil derives the
     * winding sign from that orientation (CCW vs CW), and EVEN-ODD only cares
     * about parity, so no explicit CCW reordering is needed here — this matches
     * "fans are emitted CCW and Metal's winding determines sign" in DESIGN. */
    uint32_t out = 0u;
    for (uint32_t i = 1u; i + 1u < n; i++) {
        dst[out++] = anchor;
        dst[out++] = src[i];
        dst[out++] = src[i + 1u];
    }
    return out;     /* == 3*(n-2) */
}

/* ==========================================================================
 * Device-space bounding box for the cover quad
 * ==========================================================================
 *
 * The cover pass draws the path's device-space bounding rectangle; the
 * depth-stencil test masks it to the stenciled coverage and resets the touched
 * stencil texels in the same op.  We expand the AABB by half a pixel on every
 * side so that MSAA-resolved edge samples just inside the geometric bound are
 * never clipped by the cover quad (the stencil still constrains coverage; this
 * only guarantees the quad fully contains the antialiased footprint).
 */

/* Shared core: tight device-space AABB of the FLATTENED cache (p->pts).  When
 * `guard` is true, expands the box by half a pixel on every side for the MSAA
 * cover quad; when false the box is exactly the polyline extent (TIGHT).  The
 * `tight` query path (cm_query / path_extents) passes guard=false so it never
 * inherits the cover-quad pad; the cover encode (cm_fill.m via cm_path_bounds)
 * passes guard=true.  Returns false (and a degenerate origin box) for an empty
 * flattened cache so callers read no uninitialized memory. */
static bool cm__bounds_core(const cm_path *p, bool guard,
                            float *minx, float *miny, float *maxx, float *maxy)
{
    float lo_x = 0.0f, lo_y = 0.0f, hi_x = 0.0f, hi_y = 0.0f;
    bool have = false;

    if (p && p->pts_count > 0) {
        lo_x = hi_x = p->pts[0].x;
        lo_y = hi_y = p->pts[0].y;
        for (uint32_t i = 1; i < p->pts_count; i++) {
            float x = p->pts[i].x, y = p->pts[i].y;
            if (x < lo_x) lo_x = x; else if (x > hi_x) hi_x = x;
            if (y < lo_y) lo_y = y; else if (y > hi_y) hi_y = y;
        }
        if (guard) {
            /* Half-pixel guard band for MSAA edge coverage (see header note). */
            lo_x -= 0.5f; lo_y -= 0.5f;
            hi_x += 0.5f; hi_y += 0.5f;
        }
        have = true;
    }

    if (minx) *minx = lo_x;
    if (miny) *miny = lo_y;
    if (maxx) *maxx = hi_x;
    if (maxy) *maxy = hi_y;
    return have;
}

/* Public (cover-quad) bounds: padded device AABB.  UNCHANGED behavior — cm_fill.m
 * relies on the half-pixel guard band so the cover quad fully contains the MSAA
 * antialiased footprint. */
void cm_path_bounds(const cm_path *p,
                    float *minx, float *miny, float *maxx, float *maxy)
{
    (void)cm__bounds_core(p, /*guard=*/true, minx, miny, maxx, maxy);
}

/* TIGHT device AABB of the flattened cache (NO MSAA guard band).  This is the
 * "tight-bounds variant" the query/extents path consumes: same flatten as
 * cm_path_bounds, but the EXACT polyline extent (guard=false).  Returns 0 for an
 * empty path (degenerate box).  Kept DISTINCT from cm_path_bounds so the
 * cover-quad half-pixel pad never leaks into a reported extent.
 *
 * SEAM (Build phase): this symbol is exported for cm_query.c to consume in place
 * of its file-local cm_tight_dev_bounds; add the prototype to cm_internal.h's
 * cm_path module block when wiring that.  Declared locally here so cm_path.m
 * compiles standalone without touching the shared header. */
int cm_path_bounds_tight(const cm_path *p,
                         float *minx, float *miny, float *maxx, float *maxy);
int cm_path_bounds_tight(const cm_path *p,
                         float *minx, float *miny, float *maxx, float *maxy)
{
    return cm__bounds_core(p, /*guard=*/false, minx, miny, maxx, maxy) ? 1 : 0;
}

/* ==========================================================================
 * Path construction helpers (decompose to existing move/line/curve verbs)
 * ==========================================================================
 * No new GPU work: arc/rectangle/rel_* lower to the existing recorder, so the
 * flatten/fill/stroke path is unchanged.
 */

/* Append one arc segment (<= ~PI/2 sweep) as a cubic Bezier approximation:
 * k = (4/3) tan(dtheta/4) * r controls the off-curve tangent length. */
static void cm__arc_segment(cm_path *p, double xc, double yc, double r,
                            double a0, double a1)
{
    double da = a1 - a0;
    double k = (4.0 / 3.0) * tan(da / 4.0);

    double c0 = cos(a0), s0 = sin(a0);
    double c1 = cos(a1), s1 = sin(a1);

    double x0 = xc + r * c0,           y0 = yc + r * s0;
    double x1 = xc + r * (c0 - k * s0), y1 = yc + r * (s0 + k * c0);
    double x2 = xc + r * (c1 + k * s1), y2 = yc + r * (s1 - k * c1);
    double x3 = xc + r * c1,           y3 = yc + r * s1;
    (void)x0; (void)y0;   /* start is the current point */
    cm_path_curve_to(p, x1, y1, x2, y2, x3, y3);
}

void cm_path_arc(cm_path *p, double xc, double yc, double radius,
                 double angle1, double angle2, bool negative)
{
    if (!p) return;

    /* Normalize the sweep direction (cairo: arc goes increasing angle, arc_neg
     * decreasing). */
    if (!negative) {
        while (angle2 < angle1) angle2 += 2.0 * M_PI;
    } else {
        while (angle2 > angle1) angle2 -= 2.0 * M_PI;
    }

    /* Connect-line rule: if there is a current point, draw a line to the arc
     * start; otherwise move there. */
    double sx = xc + radius * cos(angle1);
    double sy = yc + radius * sin(angle1);
    if (p->has_current) cm_path_line_to(p, sx, sy);
    else                cm_path_move_to(p, sx, sy);

    if (radius <= 0.0) return;

    /* Split into segments of at most ~PI/2 each. */
    double total = angle2 - angle1;
    double seg_max = M_PI / 2.0;
    int n = (int)ceil(fabs(total) / seg_max);
    if (n < 1) n = 1;
    double step = total / (double)n;
    double a = angle1;
    for (int i = 0; i < n; ++i) {
        cm__arc_segment(p, xc, yc, radius, a, a + step);
        a += step;
    }
}

void cm_path_rectangle(cm_path *p, double x, double y, double w, double h)
{
    if (!p) return;
    cm_path_move_to(p, x, y);
    cm_path_line_to(p, x + w, y);
    cm_path_line_to(p, x + w, y + h);
    cm_path_line_to(p, x, y + h);
    cm_path_close(p);
}

cm_status_t cm_path_rel_move_to(cm_path *p, double dx, double dy)
{
    if (!p) return CM_STATUS_NO_MEMORY;
    if (!p->has_current) return CM_STATUS_NO_CURRENT_POINT;
    cm_path_move_to(p, p->cur_x + dx, p->cur_y + dy);
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_path_rel_line_to(cm_path *p, double dx, double dy)
{
    if (!p) return CM_STATUS_NO_MEMORY;
    if (!p->has_current) return CM_STATUS_NO_CURRENT_POINT;
    cm_path_line_to(p, p->cur_x + dx, p->cur_y + dy);
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_path_rel_curve_to(cm_path *p, double dx1, double dy1,
                                 double dx2, double dy2, double dx3, double dy3)
{
    if (!p) return CM_STATUS_NO_MEMORY;
    if (!p->has_current) return CM_STATUS_NO_CURRENT_POINT;
    double cx = p->cur_x, cy = p->cur_y;
    cm_path_curve_to(p, cx + dx1, cy + dy1, cx + dx2, cy + dy2, cx + dx3, cy + dy3);
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Introspection (user space)
 * ========================================================================== */
int cm_path_has_current_point(const cm_path *p)
{
    return p ? (p->has_current ? 1 : 0) : 0;
}

void cm_path_get_current_point(const cm_path *p, double *x, double *y)
{
    if (p && p->has_current) {
        if (x) *x = p->cur_x;
        if (y) *y = p->cur_y;
    } else {
        if (x) *x = 0.0;
        if (y) *y = 0.0;
    }
}

/* Tight user-space extents: walk the recorded control points (curve control
 * points bound the curve), no MSAA guard band. */
void cm_path_extents_user(const cm_path *p, const cm_matrix_t *ctm,
                          double *x1, double *y1, double *x2, double *y2)
{
    (void)ctm;   /* recorded geometry is already user space */
    if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
    if (!p || p->xy_count < 2) return;

    double lo_x = p->verbs_xy[0], hi_x = p->verbs_xy[0];
    double lo_y = p->verbs_xy[1], hi_y = p->verbs_xy[1];
    for (uint32_t i = 0; i + 1 < p->xy_count; i += 2) {
        double vx = p->verbs_xy[i], vy = p->verbs_xy[i + 1];
        if (vx < lo_x) lo_x = vx; if (vx > hi_x) hi_x = vx;
        if (vy < lo_y) lo_y = vy; if (vy > hi_y) hi_y = vy;
    }
    if (x1) *x1 = lo_x; if (y1) *y1 = lo_y;
    if (x2) *x2 = hi_x; if (y2) *y2 = hi_y;
}

/* TIGHT user-space extents of the recorded path.
 * --------------------------------------------------------------------------
 * cairo_path_extents reports the box that fill/stroke would touch, in USER
 * space, with NO antialias guard band.  Unlike cm_path_extents_user (which
 * bounds the raw control points and therefore OVER-covers a cubic by its
 * off-curve handles), this flattens the cubics in user space first so the box
 * hugs the actual curve.  It does NOT touch p's device cache: the flatten goes
 * into a private scratch path.  An empty path yields a degenerate (0,0,0,0)
 * box, matching cairo (which returns all-zero extents for an empty path). */
static void cm__path_extents_tight(const cm_path *p,
                                   double *x1, double *y1,
                                   double *x2, double *y2)
{
    if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
    if (!p || p->verb_count == 0) return;

    cm_path flat;
    cm_path_init(&flat);
    if (cm_path_flatten_user(p, &flat) != CM_STATUS_SUCCESS) {
        cm_path_free(&flat);
        return;
    }

    /* The flattened scratch holds only move/line on-curve points in its
     * recorded xy arena (identity CTM, so user == "device" here). */
    if (flat.xy_count >= 2) {
        double lo_x = flat.verbs_xy[0], hi_x = flat.verbs_xy[0];
        double lo_y = flat.verbs_xy[1], hi_y = flat.verbs_xy[1];
        for (uint32_t i = 0; i + 1 < flat.xy_count; i += 2) {
            double vx = flat.verbs_xy[i], vy = flat.verbs_xy[i + 1];
            if (vx < lo_x) lo_x = vx; if (vx > hi_x) hi_x = vx;
            if (vy < lo_y) lo_y = vy; if (vy > hi_y) hi_y = vy;
        }
        if (x1) *x1 = lo_x; if (y1) *y1 = lo_y;
        if (x2) *x2 = hi_x; if (y2) *y2 = hi_y;
    }
    cm_path_free(&flat);
}

/* ==========================================================================
 * User-space flatten (for copy_path_flat)
 * --------------------------------------------------------------------------
 * cairo_copy_path_flat() returns a path whose cubics have been replaced by line
 * segments, in USER space (identity transform), and whose CLOSE verbs are kept.
 * We therefore decompose `p`'s recorded verb stream into `out`'s recorded verb
 * stream using move/line/close verbs only, splitting each cubic by the SAME
 * adaptive de Casteljau used for device flattening but with an IDENTITY CTM so
 * the flatness test runs in user units (cairo's copy_path_flat uses the context
 * tolerance in user space; we use CM_FLATTEN_TOLERANCE, the library tolerance).
 *
 * This does NOT touch `p`'s device-space flattened cache (p->pts / p->contours):
 * we read only the recorded control geometry (p->verbs / p->verbs_xy) and write
 * fresh recorded verbs into `out`, so a copy_path_flat never disturbs an
 * in-flight fill/stroke that is reusing p's device cache.  `out` is reset first
 * (its capacity is retained for amortized reuse).
 * ========================================================================== */

/* Recursive user-space cubic subdivision: append every point EXCEPT p0 (the
 * caller already issued a move/line to p0) as a line_to into `out`.  Identity
 * CTM => the flatness metric is in user space.  Returns false on OOM. */
static bool cm__flatten_cubic_user_rec(cm_path *out,
                                       double p0x, double p0y,
                                       double p1x, double p1y,
                                       double p2x, double p2y,
                                       double p3x, double p3y,
                                       double tol2, int depth)
{
    if (depth >= CM_FLATTEN_MAX_DEPTH ||
        cm__cubic_is_flat(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y, tol2)) {
        cm_path_line_to(out, p3x, p3y);
        return true;
    }
    double p01x = (p0x + p1x) * 0.5, p01y = (p0y + p1y) * 0.5;
    double p12x = (p1x + p2x) * 0.5, p12y = (p1y + p2y) * 0.5;
    double p23x = (p2x + p3x) * 0.5, p23y = (p2y + p3y) * 0.5;
    double p012x = (p01x + p12x) * 0.5, p012y = (p01y + p12y) * 0.5;
    double p123x = (p12x + p23x) * 0.5, p123y = (p12y + p23y) * 0.5;
    double mx = (p012x + p123x) * 0.5, my = (p012y + p123y) * 0.5;

    if (!cm__flatten_cubic_user_rec(out, p0x, p0y, p01x, p01y, p012x, p012y,
                                    mx, my, tol2, depth + 1))
        return false;
    if (!cm__flatten_cubic_user_rec(out, mx, my, p123x, p123y, p23x, p23y,
                                    p3x, p3y, tol2, depth + 1))
        return false;
    return true;
}

cm_status_t cm_path_flatten_user(const cm_path *p, cm_path *out)
{
    if (!p || !out) return CM_STATUS_NO_MEMORY;

    /* Start from an empty `out` (keep its backing allocations, like the
     * per-frame reset). */
    cm_path_reset(out);

    const double tol2 = CM_FLATTEN_TOLERANCE * CM_FLATTEN_TOLERANCE;

    uint32_t xi = 0;        /* xy (double) cursor into p->verbs_xy            */
    double   cx = 0.0, cy = 0.0;   /* user-space current point for cubic start */

    for (uint32_t vi = 0; vi < p->verb_count; ++vi) {
        switch ((cm_path_verb)p->verbs[vi]) {

        case CM_VERB_MOVE: {
            double x = p->verbs_xy[xi++], y = p->verbs_xy[xi++];
            cm_path_move_to(out, x, y);
            cx = x; cy = y;
            break;
        }
        case CM_VERB_LINE: {
            double x = p->verbs_xy[xi++], y = p->verbs_xy[xi++];
            cm_path_line_to(out, x, y);
            cx = x; cy = y;
            break;
        }
        case CM_VERB_CURVE: {
            double x1 = p->verbs_xy[xi++], y1 = p->verbs_xy[xi++];
            double x2 = p->verbs_xy[xi++], y2 = p->verbs_xy[xi++];
            double x3 = p->verbs_xy[xi++], y3 = p->verbs_xy[xi++];
            /* If the source had no current point cairo would have inserted a
             * move to (x1,y1); the recorder already does that, so `out` has a
             * current point here.  Flatten (cx,cy)->(x1,y1)->(x2,y2)->(x3,y3)
             * as line segments. */
            if (!cm__flatten_cubic_user_rec(out, cx, cy, x1, y1, x2, y2,
                                            x3, y3, tol2, 0))
                return CM_STATUS_NO_MEMORY;
            cx = x3; cy = y3;
            break;
        }
        case CM_VERB_CLOSE:
            cm_path_close(out);
            /* cairo: current point returns to the sub-path start; cm_path_close
             * already updates out->cur_*; mirror it for our local cursor. */
            cx = out->cur_x; cy = out->cur_y;
            break;

        case CM_VERB_NEW_SUB:
            cm_path_new_sub(out);
            break;

        default:
            break;
        }
    }
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Verb-stream read / append accessors (for copy_path / append_path)
 * --------------------------------------------------------------------------
 * The PUBLIC verb stream cairo's copy_path exposes is NOT our raw recorded
 * stream: cairo follows every CLOSE_PATH with a synthetic MOVE_TO to the closed
 * sub-path's start point (so a consumer that ignores CLOSE still continues from
 * the right place, and append_path re-opens a sub-path there).  We therefore
 * EXPOSE a virtual stream = recorded verbs with one extra MOVE_TO injected after
 * each CLOSE.  cm_path_verb_count reports the virtual length; cm_path_get_verb
 * resolves a virtual index.  CM_VERB_NEW_SUB is internal-only and is NOT
 * surfaced (cairo has no NEW_SUB path-data element); it is skipped here so the
 * virtual stream contains only MOVE/LINE/CURVE/CLOSE, exactly like cairo.
 *
 * Both functions walk the recorded stream (O(i)); the recorded path is small
 * (a VMobject contour) and copy_path is not on the per-frame hot path.
 * ========================================================================== */

/* Walk the recorded stream resolving the VIRTUAL element at index `i`.  On a
 * hit, sets out_type / out_pts (up to 6 doubles) and returns the verb's point
 * count (MOVE/LINE=1, CURVE=3, CLOSE=0).  Returns -1 when `i` is past the end;
 * out_total (if non-NULL) always receives the full virtual length. */
static int cm__virt_verb(const cm_path *p, uint32_t i,
                         cm_path_data_type_t *out_type, double *out_pts,
                         uint32_t *out_total)
{
    uint32_t virt = 0;      /* virtual index cursor                          */
    uint32_t xi   = 0;      /* xy (double) cursor                            */
    double   sx = 0.0, sy = 0.0;   /* current sub-path start (for synthetic move) */
    int      result = -1;

    for (uint32_t v = 0; v < p->verb_count; ++v) {
        cm_path_verb verb = (cm_path_verb)p->verbs[v];
        switch (verb) {

        case CM_VERB_MOVE:
            if (virt == i) {
                if (out_type) *out_type = CM_PATH_MOVE_TO;
                if (out_pts) { out_pts[0] = p->verbs_xy[xi]; out_pts[1] = p->verbs_xy[xi+1]; }
                result = 1;
            }
            sx = p->verbs_xy[xi]; sy = p->verbs_xy[xi+1];
            xi += 2; virt++;
            break;

        case CM_VERB_LINE:
            if (virt == i) {
                if (out_type) *out_type = CM_PATH_LINE_TO;
                if (out_pts) { out_pts[0] = p->verbs_xy[xi]; out_pts[1] = p->verbs_xy[xi+1]; }
                result = 1;
            }
            xi += 2; virt++;
            break;

        case CM_VERB_CURVE:
            if (virt == i) {
                if (out_type) *out_type = CM_PATH_CURVE_TO;
                if (out_pts) for (int k = 0; k < 6; ++k) out_pts[k] = p->verbs_xy[xi+k];
                result = 3;
            }
            xi += 6; virt++;
            break;

        case CM_VERB_CLOSE:
            /* (a) the CLOSE itself */
            if (virt == i) {
                if (out_type) *out_type = CM_PATH_CLOSE_PATH;
                result = 0;
            }
            virt++;
            /* (b) the synthetic MOVE_TO back to the sub-path start */
            if (virt == i) {
                if (out_type) *out_type = CM_PATH_MOVE_TO;
                if (out_pts) { out_pts[0] = sx; out_pts[1] = sy; }
                result = 1;
            }
            virt++;
            break;

        case CM_VERB_NEW_SUB:
        default:
            /* internal-only verb: not part of the public stream */
            break;
        }
    }

    if (out_total) *out_total = virt;
    return result;
}

uint32_t cm_path_verb_count(const cm_path *p)
{
    if (!p) return 0;
    uint32_t total = 0;
    /* Resolve nothing (i past the end); just collect the virtual length. */
    cm__virt_verb(p, UINT32_MAX, NULL, NULL, &total);
    return total;
}

int cm_path_get_verb(const cm_path *p, uint32_t i, cm_path_data_type_t *type,
                     double *pts)
{
    if (!p) { if (type) *type = CM_PATH_MOVE_TO; return 0; }
    int r = cm__virt_verb(p, i, type, pts, NULL);
    if (r < 0) { if (type) *type = CM_PATH_MOVE_TO; return 0; }
    return r;
}

void cm_path_append_stream(cm_path *p, const cm_path_data_type_t *types,
                           const double *pts, uint32_t verb_count)
{
    if (!p || !types || !pts) return;
    uint32_t xi = 0;
    for (uint32_t v = 0; v < verb_count; ++v) {
        switch (types[v]) {
            case CM_PATH_MOVE_TO:  cm_path_move_to(p, pts[xi], pts[xi+1]); xi += 2; break;
            case CM_PATH_LINE_TO:  cm_path_line_to(p, pts[xi], pts[xi+1]); xi += 2; break;
            case CM_PATH_CURVE_TO: cm_path_curve_to(p, pts[xi], pts[xi+1],
                                                       pts[xi+2], pts[xi+3],
                                                       pts[xi+4], pts[xi+5]); xi += 6; break;
            case CM_PATH_CLOSE_PATH: cm_path_close(p); break;
            default: break;
        }
    }
}

void cm_path_append_contours(cm_path *p, const double *pts_xy,
                             const uint32_t *contour_lens, uint32_t contour_count)
{
    if (!p || !pts_xy || !contour_lens) return;
    uint32_t xi = 0;
    for (uint32_t c = 0; c < contour_count; ++c) {
        uint32_t n = contour_lens[c];
        /* A degenerate (<1 point) contour contributes nothing; skip it so we do
         * not emit a stray close on an empty sub-path. */
        if (n == 0) continue;
        for (uint32_t i = 0; i < n; ++i) {
            double x = pts_xy[xi++], y = pts_xy[xi++];
            if (i == 0) cm_path_move_to(p, x, y);
            else        cm_path_line_to(p, x, y);
        }
        /* Glyph/text outline contours are always closed sub-paths (CoreText /
         * FreeType emit closed loops), so close each one — fill always closes
         * anyway, and closing makes the recorded stream match cairo's
         * glyph_path (a sequence of closed sub-paths). */
        cm_path_close(p);
    }
}

/* ==========================================================================
 * PUBLIC API  (cairo_metal.h) — context-level path construction + introspection
 * ==========================================================================
 * These thin wrappers bridge the public cm_context_t to the internal cm_path
 * recorder.  Every geometry mutation marks ctx->path.dirty so the device-space
 * flattened cache is rebuilt on the next fill/stroke (the same invariant
 * cm__record enforces on the cm_path it owns; we set it on the context's path
 * for symmetry and so a wrapper that lowers to several recorder calls is covered
 * even if a future recorder change stops setting it).  Relative ops with no
 * current point report CM_STATUS_NO_CURRENT_POINT through the sticky context
 * status (cairo_status semantics), matching cm_rel_* in cairo's public API.
 *
 * NOTE on CTM dirtiness (contract): cm_set_matrix / cm_translate / cm_rotate /
 * cm_transform / cm_identity_matrix / cm_scale all set ctx->path.dirty = true in
 * cairo_metal.m (the context-glue owner of the CTM), so a recorded path drawn
 * after a transform change re-flattens in the new device space.  That guarantee
 * lives with the CTM mutators, not here; these path builders only need to mark
 * dirty for the geometry they add.
 * ========================================================================== */

/* Sticky first-error onto the context, mirroring cairo_status (defined the same
 * way in cairo_metal.m; duplicated as a file-local static so cm_path.m has no
 * cross-module symbol dependency for status reporting). */
static inline void cm__path_ctx_status(cm_context_t *ctx, cm_status_t st)
{
    if (ctx && st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;
}

CM_PUBLIC void
cm_arc(cm_context_t *ctx, double xc, double yc, double radius,
       double angle1, double angle2)
{
    if (!ctx) return;
    cm_path_arc(&ctx->path, xc, yc, radius, angle1, angle2, /*negative=*/false);
    ctx->path.dirty = true;
}

CM_PUBLIC void
cm_arc_negative(cm_context_t *ctx, double xc, double yc, double radius,
                double angle1, double angle2)
{
    if (!ctx) return;
    cm_path_arc(&ctx->path, xc, yc, radius, angle1, angle2, /*negative=*/true);
    ctx->path.dirty = true;
}

CM_PUBLIC void
cm_rectangle(cm_context_t *ctx, double x, double y, double width, double height)
{
    if (!ctx) return;
    cm_path_rectangle(&ctx->path, x, y, width, height);
    ctx->path.dirty = true;
}

CM_PUBLIC void
cm_rel_move_to(cm_context_t *ctx, double dx, double dy)
{
    if (!ctx) return;
    cm_status_t st = cm_path_rel_move_to(&ctx->path, dx, dy);
    if (st != CM_STATUS_SUCCESS) { cm__path_ctx_status(ctx, st); return; }
    ctx->path.dirty = true;
}

CM_PUBLIC void
cm_rel_line_to(cm_context_t *ctx, double dx, double dy)
{
    if (!ctx) return;
    cm_status_t st = cm_path_rel_line_to(&ctx->path, dx, dy);
    if (st != CM_STATUS_SUCCESS) { cm__path_ctx_status(ctx, st); return; }
    ctx->path.dirty = true;
}

CM_PUBLIC void
cm_rel_curve_to(cm_context_t *ctx,
                double dx1, double dy1,
                double dx2, double dy2,
                double dx3, double dy3)
{
    if (!ctx) return;
    cm_status_t st = cm_path_rel_curve_to(&ctx->path, dx1, dy1, dx2, dy2, dx3, dy3);
    if (st != CM_STATUS_SUCCESS) { cm__path_ctx_status(ctx, st); return; }
    ctx->path.dirty = true;
}

CM_PUBLIC int
cm_has_current_point(cm_context_t *ctx)
{
    if (!ctx) return 0;
    return cm_path_has_current_point(&ctx->path);
}

CM_PUBLIC void
cm_get_current_point(cm_context_t *ctx, double *x, double *y)
{
    if (!ctx) { if (x) *x = 0.0; if (y) *y = 0.0; return; }
    cm_path_get_current_point(&ctx->path, x, y);
}

/* cairo_path_extents: TIGHT user-space box (no antialias guard band).  Does NOT
 * reuse cm_path_bounds (which is the padded DEVICE cover-quad box); uses the
 * tight user-space flatten so curve control points do not inflate the result. */
CM_PUBLIC void
cm_path_extents(cm_context_t *ctx,
                double *x1, double *y1, double *x2, double *y2)
{
    if (!ctx) {
        if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
        return;
    }
    cm__path_extents_tight(&ctx->path, x1, y1, x2, y2);
}

/* ==========================================================================
 * copy_path / copy_path_flat / append_path  (cairo_copy_path family)
 * --------------------------------------------------------------------------
 * Build a heap cm_path_data_t (array of {type, points[6]}) from a cm_path's
 * VIRTUAL verb stream (cm_path_verb_count / cm_path_get_verb -- which already
 * inject cairo's synthetic post-CLOSE MOVE_TO and hide the internal NEW_SUB).
 * copy_path snapshots the recorded path as-is; copy_path_flat first lowers the
 * cubics to line segments via cm_path_flatten_user into a private scratch path
 * and snapshots THAT.  append_path replays an element array onto ctx->path
 * through cm_path_append_stream.  None of these touch the device-space
 * flattened cache, so a copy_path during/after a fill is side-effect free.
 * ========================================================================== */

/* Allocate + fill a cm_path_data_t from `p`'s virtual stream.  On OOM returns a
 * struct with status=NO_MEMORY, elements=NULL, num_elements=0.  Never NULL. */
static cm_path_data_t *cm__copy_path_from(const cm_path *p)
{
    cm_path_data_t *out = (cm_path_data_t *)calloc(1, sizeof(*out));
    if (!out) return NULL;          /* caller maps NULL -> its own OOM struct */
    out->status       = CM_STATUS_SUCCESS;
    out->elements     = NULL;
    out->num_elements = 0;

    uint32_t n = cm_path_verb_count(p);     /* virtual element count */
    if (n == 0) return out;                  /* empty path: empty (valid) result */

    cm_path_element_t *els =
        (cm_path_element_t *)calloc((size_t)n, sizeof(cm_path_element_t));
    if (!els) { out->status = CM_STATUS_NO_MEMORY; return out; }

    for (uint32_t i = 0; i < n; ++i) {
        cm_path_data_type_t t = CM_PATH_MOVE_TO;
        double pts[6] = {0,0,0,0,0,0};
        (void)cm_path_get_verb(p, i, &t, pts);
        els[i].type = t;
        /* Copy the meaningful coordinate count per type; the rest stay 0. */
        int npairs = (t == CM_PATH_CURVE_TO) ? 3
                   : (t == CM_PATH_CLOSE_PATH) ? 0 : 1;
        for (int k = 0; k < npairs * 2; ++k) els[i].points[k] = pts[k];
    }
    out->elements     = els;
    out->num_elements = (int)n;
    return out;
}

/* Shared OOM sentinel: a heap struct reporting NO_MEMORY (so callers always get
 * a non-NULL, destroyable result even when the array/struct alloc fails). */
static cm_path_data_t *cm__path_data_oom(void)
{
    cm_path_data_t *out = (cm_path_data_t *)calloc(1, sizeof(*out));
    if (out) { out->status = CM_STATUS_NO_MEMORY; }
    return out;   /* may itself be NULL only under total allocator failure */
}

CM_PUBLIC cm_path_data_t *
cm_copy_path(cm_context_t *ctx)
{
    if (!ctx) return cm__path_data_oom();
    cm_path_data_t *out = cm__copy_path_from(&ctx->path);
    if (!out) return cm__path_data_oom();
    cm__path_ctx_status(ctx, out->status);
    return out;
}

CM_PUBLIC cm_path_data_t *
cm_copy_path_flat(cm_context_t *ctx)
{
    if (!ctx) return cm__path_data_oom();

    /* Flatten the recorded cubics to line segments in user space into a private
     * scratch path, then snapshot it.  cm_path_flatten_user resets the scratch
     * and writes only MOVE/LINE/CLOSE verbs, so the snapshot has no CURVE_TO. */
    cm_path flat;
    cm_path_init(&flat);
    cm_status_t fs = cm_path_flatten_user(&ctx->path, &flat);
    if (fs != CM_STATUS_SUCCESS) {
        cm_path_free(&flat);
        cm__path_ctx_status(ctx, fs);
        cm_path_data_t *oom = cm__path_data_oom();
        if (oom) oom->status = fs;
        return oom;
    }
    cm_path_data_t *out = cm__copy_path_from(&flat);
    cm_path_free(&flat);
    if (!out) return cm__path_data_oom();
    cm__path_ctx_status(ctx, out->status);
    return out;
}

CM_PUBLIC void
cm_append_path(cm_context_t *ctx, const cm_path_data_t *path)
{
    if (!ctx || !path) return;
    if (path->status != CM_STATUS_SUCCESS) {
        cm__path_ctx_status(ctx, path->status);
        return;
    }
    if (!path->elements || path->num_elements <= 0) return;

    /* Lower the element array to the (types[], pts[]) form cm_path_append_stream
     * consumes.  pts is tightly packed per-verb (MOVE/LINE: 2, CURVE: 6,
     * CLOSE: 0), matching cm_path_append_stream's cursor walk. */
    uint32_t nverb = (uint32_t)path->num_elements;
    cm_path_data_type_t *types =
        (cm_path_data_type_t *)malloc((size_t)nverb * sizeof(*types));
    /* Worst case every element is a CURVE_TO -> 6 doubles each. */
    double *pts = (double *)malloc((size_t)nverb * 6u * sizeof(double));
    if (!types || !pts) {
        free(types); free(pts);
        cm__path_ctx_status(ctx, CM_STATUS_NO_MEMORY);
        return;
    }

    uint32_t xi = 0;
    for (uint32_t i = 0; i < nverb; ++i) {
        cm_path_data_type_t t = path->elements[i].type;
        types[i] = t;
        int npairs = (t == CM_PATH_CURVE_TO) ? 3
                   : (t == CM_PATH_CLOSE_PATH) ? 0 : 1;
        for (int k = 0; k < npairs * 2; ++k)
            pts[xi++] = path->elements[i].points[k];
    }

    cm_path_append_stream(&ctx->path, types, pts, nverb);
    ctx->path.dirty = true;

    free(types);
    free(pts);
}

CM_PUBLIC void
cm_path_data_destroy(cm_path_data_t *path)
{
    if (!path) return;
    free(path->elements);
    free(path);
}
