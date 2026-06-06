/*
 * cm_stroke.m  --  CairoMetal CPU stroke expansion
 * ============================================================================
 *
 * MODULE OWNER of cm_stroke_expand() AND cm_dash_apply() (cm_internal.h).
 *
 * Turns an already-flattened, device-space path (`src`) into a *fillable
 * outline polygon* (`dst`) honoring line width, line join (miter/round/bevel
 * with miter limit) and line cap (butt/round/square).  The result is then run
 * through the SAME stencil-then-cover NONZERO fill as cm_fill_preserve, so
 * overlapping stroke pieces (consecutive segment quads, joins, caps) composite
 * exactly once -- matching cairo's stroke semantics.  No analytic stroke
 * rasterizer.
 *
 * ----------------------------------------------------------------------------
 * DASHING  (cm_dash_apply, runs BEFORE cm_stroke_expand)
 * ----------------------------------------------------------------------------
 * DESIGN.md's manim subset noted "manim pre-splits dashed paths upstream", so
 * the shipping fast path can skip dashing entirely.  The FULL cairo contract
 * (cairo_set_dash) requires the library to chop the path itself: cm_dash_apply
 * walks each already-flattened, device-space contour of `src`, advances through
 * the gstate dash pattern (+ offset), and writes only the "on" sub-segments
 * into `dst` as INDEPENDENT OPEN contours (closed == false).  The caller then
 * feeds `dst` straight into cm_stroke_expand, which -- because every on-piece is
 * an open contour -- caps BOTH ends of every dash with the current line cap and
 * joins only WITHIN an on-piece, exactly matching cairo's dashed-stroke result.
 * When dashing is disabled (n == 0) the caller skips cm_dash_apply and strokes
 * `src` directly, so the un-dashed path is byte-for-byte the prior behaviour.
 *
 * ----------------------------------------------------------------------------
 * REPRESENTATION CONTRACT WITH cm_fill / cm_path
 * ----------------------------------------------------------------------------
 * The fill encoder consumes a path's *flattened cache* (`pts` + `contours`)
 * directly: cm_path_emit_fan() emits, per contour, a triangle FAN about the
 * contour's first point, and the NONZERO stencil resolves coverage.  A fan is
 * only a valid cover of a CONVEX, consistently-wound polygon, so we emit each
 * stroke piece -- every segment quad, every join wedge, every cap -- as its own
 * small CONVEX contour:
 *
 *     segment quad   -> 4-point contour
 *     bevel / miter  -> 3- or 4-point contour
 *     round arc      -> (center + arc samples) fan-shaped contour
 *
 * Because the whole soup is filled with NONZERO winding, the many overlapping
 * convex pieces union into the single stroke outline with the inner overlaps
 * counted once (cairo behaviour).  We therefore write straight into dst's
 * DEVICE-SPACE flattened cache and mark it already-flattened (dst->dirty =
 * false) so a downstream cm_path_flatten(dst, identity) is a no-op and does not
 * re-transform our device-space geometry.
 *
 * ----------------------------------------------------------------------------
 * UNITS
 * ----------------------------------------------------------------------------
 * cairo's line width is in USER space; cm_stroke_expand receives an ALREADY
 * device-space-flattened `src` and therefore expects `line_width` ALREADY
 * converted to device units by the caller (cm_context.c) via the CTM's scale
 * (cm_matrix_max_scale).  manim's CTM is isotropic in magnitude (xx = -yy,
 * xy = yx = 0), so a single scalar device width is exact for manim; the
 * isotropic-width assumption is documented here and at the call site.
 *
 * cm_dash_apply has the IDENTICAL units contract: cairo dash lengths are USER
 * space (like line width), but cm_dash_apply chops the DEVICE-space flattened
 * `src`, so the caller (cm_context.c) must pre-scale each dash length and the
 * dash offset by the same cm_matrix_max_scale(CTM) it applies to line_width.
 * Under manim's isotropic CTM this single scalar is exact; the assumption is
 * documented here and must be honoured at the call site.
 *
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ==========================================================================
 * Small 2D vector helpers (double precision for stable geometry; the result
 * is narrowed to cm_vec2f float on emit, matching the device-space cache).
 * ========================================================================== */
typedef struct { double x, y; } cm_dvec2;

static inline cm_dvec2 dv(double x, double y)        { cm_dvec2 r = { x, y }; return r; }
static inline cm_dvec2 dv_add(cm_dvec2 a, cm_dvec2 b){ return dv(a.x + b.x, a.y + b.y); }
static inline cm_dvec2 dv_sub(cm_dvec2 a, cm_dvec2 b){ return dv(a.x - b.x, a.y - b.y); }
static inline cm_dvec2 dv_scale(cm_dvec2 a, double s){ return dv(a.x * s, a.y * s); }
static inline double   dv_dot(cm_dvec2 a, cm_dvec2 b){ return a.x * b.x + a.y * b.y; }
/* z component of the 2D cross product a x b (signed parallelogram area). */
static inline double   dv_cross(cm_dvec2 a, cm_dvec2 b){ return a.x * b.y - a.y * b.x; }
static inline double   dv_len(cm_dvec2 a)            { return sqrt(a.x * a.x + a.y * a.y); }

/* ==========================================================================
 * dst output buffer management
 * --------------------------------------------------------------------------
 * We append directly into dst->pts / dst->contours.  These arrays are part of
 * the cm_path flattened cache; per the design they grow amortized and are
 * RESET (not freed) between frames by the owner of the scratch path.  Growth
 * happens here on the (cold relative to per-draw) stroke-expand path; the hot
 * per-frame geometry still comes from the device ring downstream.
 * ========================================================================== */

/* Ensure dst->pts can hold at least `need` total points; amortized doubling. */
static bool cm_pts_reserve(cm_path *dst, uint32_t need)
{
    if (need <= dst->pts_cap) return true;
    uint32_t cap = dst->pts_cap ? dst->pts_cap : 64;
    while (cap < need) {
        uint32_t next = cap << 1;
        if (next < cap) return false;          /* overflow guard */
        cap = next;
    }
    cm_vec2f *np = (cm_vec2f *)realloc(dst->pts, (size_t)cap * sizeof(cm_vec2f));
    if (!np) return false;
    dst->pts = np;
    dst->pts_cap = cap;
    return true;
}

/* Ensure dst->contours can hold at least `need` total contours. */
static bool cm_contours_reserve(cm_path *dst, uint32_t need)
{
    if (need <= dst->contour_cap) return true;
    uint32_t cap = dst->contour_cap ? dst->contour_cap : 32;
    while (cap < need) {
        uint32_t next = cap << 1;
        if (next < cap) return false;
        cap = next;
    }
    cm_contour *nc = (cm_contour *)realloc(dst->contours,
                                           (size_t)cap * sizeof(cm_contour));
    if (!nc) return false;
    dst->contours = nc;
    dst->contour_cap = cap;
    return true;
}

/*
 * Emit one CONVEX polygon (a stroke piece) as a new closed contour in dst.
 * `n` >= 3.  Returns false on allocation failure (caller maps to NO_MEMORY).
 * The polygon is stored as-is; cm_path_emit_fan fans it about pts[first] and
 * the NONZERO stencil handles winding sign, so vertex order need not be
 * normalized -- but we keep pieces small and convex so the fan is exact.
 */
static bool cm_emit_poly(cm_path *dst, const cm_dvec2 *poly, uint32_t n)
{
    if (n < 3) return true;                    /* nothing fillable */
    if (!cm_pts_reserve(dst, dst->pts_count + n)) return false;
    if (!cm_contours_reserve(dst, dst->contour_count + 1)) return false;

    uint32_t first = dst->pts_count;
    for (uint32_t i = 0; i < n; ++i) {
        dst->pts[first + i].x = (float)poly[i].x;
        dst->pts[first + i].y = (float)poly[i].y;
    }
    dst->pts_count += n;

    cm_contour *c = &dst->contours[dst->contour_count++];
    c->first_point = first;
    c->point_count = n;
    c->closed      = true;
    c->has_current = false;
    return true;
}

/* Convenience for quads (the common case: one per segment). */
static bool cm_emit_quad(cm_path *dst, cm_dvec2 a, cm_dvec2 b,
                                       cm_dvec2 c, cm_dvec2 d)
{
    cm_dvec2 q[4] = { a, b, c, d };
    return cm_emit_poly(dst, q, 4);
}

static bool cm_emit_tri(cm_path *dst, cm_dvec2 a, cm_dvec2 b, cm_dvec2 c)
{
    cm_dvec2 t[3] = { a, b, c };
    return cm_emit_poly(dst, t, 3);
}

/* ==========================================================================
 * Arc tessellation
 * --------------------------------------------------------------------------
 * Emit a circular wedge of radius `r` about `center`, sweeping from unit
 * direction `from` to unit direction `to` along the SHORT way determined by
 * sign(orient): orient > 0 sweeps counter-clockwise, orient < 0 clockwise.
 * Used for round joins (outer corner) and round caps (semicircle).  Segment
 * count is driven by CM_ARC_TOLERANCE in device pixels so on-screen curvature
 * error is bounded (radius is already device-space here).
 * ========================================================================== */
static bool cm_emit_arc(cm_path *dst, cm_dvec2 center, double r,
                        double a_from, double a_to, double orient,
                        double tolerance)
{
    if (r <= 0.0) return true;
    if (!(tolerance > 0.0)) tolerance = CM_ARC_TOLERANCE;

    /* Normalize the sweep to a positive magnitude in the chosen direction. */
    double sweep = a_to - a_from;
    if (orient >= 0.0) {                        /* CCW: want sweep in (0, 2pi] */
        while (sweep <= 0.0)      sweep += 2.0 * M_PI;
        while (sweep > 2.0 * M_PI) sweep -= 2.0 * M_PI;
    } else {                                    /* CW: want sweep in [-2pi, 0) */
        while (sweep >= 0.0)       sweep -= 2.0 * M_PI;
        while (sweep < -2.0 * M_PI) sweep += 2.0 * M_PI;
    }
    if (sweep == 0.0) return true;

    /* segments from the max-angle-per-step that keeps sagitta <= tolerance:
     *   tol = r * (1 - cos(dtheta/2))  =>  dtheta = 2*acos(1 - tol/r)        */
    double dmax;
    double ratio = 1.0 - (tolerance / r);
    if (ratio <= -1.0) {
        dmax = M_PI;                            /* tiny radius: coarse is fine */
    } else if (ratio >= 1.0) {
        dmax = 2.0 * M_PI;
    } else {
        dmax = 2.0 * acos(ratio);
        if (dmax <= 0.0) dmax = M_PI;
    }
    uint32_t segs = (uint32_t)ceil(fabs(sweep) / dmax);
    if (segs < 1) segs = 1;

    /* Build the wedge as a single convex fan: center + (segs+1) rim points. */
    uint32_t n = segs + 2;
    /* Stack buffer for the common small case; heap only for very long arcs. */
    cm_dvec2 small[66];
    cm_dvec2 *poly = small;
    cm_dvec2 *heap = NULL;
    if (n > (uint32_t)(sizeof(small) / sizeof(small[0]))) {
        heap = (cm_dvec2 *)malloc((size_t)n * sizeof(cm_dvec2));
        if (!heap) return false;
        poly = heap;
    }

    poly[0] = center;
    double step = sweep / (double)segs;
    for (uint32_t i = 0; i <= segs; ++i) {
        double a = a_from + step * (double)i;
        poly[1 + i] = dv(center.x + r * cos(a), center.y + r * sin(a));
    }
    bool ok = cm_emit_poly(dst, poly, n);
    free(heap);
    return ok;
}

/* ==========================================================================
 * Joins
 * --------------------------------------------------------------------------
 * At vertex `p` between an incoming segment (dir d0, unit) and an outgoing
 * segment (dir d1, unit), with half-width `hw`.  The segment quads already
 * cover the rectangles up to `p` on both sides; the join only needs to fill
 * the wedge on the OUTER side of the corner (the side that opens up).  We
 * always emit the bevel triangle there to guarantee no gap, then optionally
 * add the miter tip or the round arc.
 * ========================================================================== */
static bool cm_emit_join(cm_path *dst, cm_dvec2 p, cm_dvec2 d0, cm_dvec2 d1,
                         double hw, cm_line_join_t join, double miter_limit,
                         double tolerance)
{
    /* Left normals (rotate dir +90deg in math convention): n = (-dy, dx).
     * Device space is y-down, but join logic is sign-agnostic: we pick the
     * outer side from the turn direction (cross product) directly. */
    cm_dvec2 n0 = dv(-d0.y, d0.x);
    cm_dvec2 n1 = dv(-d1.y, d1.x);

    double turn = dv_cross(d0, d1);            /* >0 left turn, <0 right turn  */

    /* Nearly collinear: no visible corner, skip (avoids degenerate miters). */
    if (fabs(turn) < 1e-9) return true;

    /* Outer side: the side where the two segment edges leave a gap.  For a
     * left turn (turn>0) the outer corner is on the right (-normal); for a
     * right turn it is on the left (+normal). */
    double s = (turn > 0.0) ? -1.0 : 1.0;
    cm_dvec2 a = dv_add(p, dv_scale(n0, s * hw));  /* outer end of incoming    */
    cm_dvec2 b = dv_add(p, dv_scale(n1, s * hw));  /* outer start of outgoing  */

    /* Base bevel triangle (always) closes the gap p-a-b. */
    if (!cm_emit_tri(dst, p, a, b)) return false;

    if (join == CM_LINE_JOIN_BEVEL) return true;

    if (join == CM_LINE_JOIN_ROUND) {
        /* Outer arc from a to b about p, swept the short way over the corner. */
        double a_from = atan2(a.y - p.y, a.x - p.x);
        double a_to   = atan2(b.y - p.y, b.x - p.x);
        /* Sweep direction follows the outer corner: opposite the path turn. */
        double orient = (turn > 0.0) ? +1.0 : -1.0;
        return cm_emit_arc(dst, p, hw, a_from, a_to, orient, tolerance);
    }

    /* MITER: extend the two outer edges until they meet at the miter tip.
     * Cairo's miter-limit test (cairo_set_miter_limit docs):
     *     miter_length / line_width = 1 / sin(theta/2)
     * where theta is the INTERIOR angle between the two segments.  With dir
     * vectors d0,d1 the DEVIATION angle is phi = acos(dot(d0,d1)) (0 when the
     * path goes straight, pi for a full fold-back), and theta = pi - phi, so
     *     sin(theta/2) = sin((pi-phi)/2) = cos(phi/2),
     * giving miter_ratio = 1 / cos(phi/2).  Straight join -> ratio 1 (small
     * miter); sharp fold-back -> ratio -> infinity (huge miter -> bevel). */
    {
        double cosphi = dv_dot(d0, d1);        /* d0,d1 are unit vectors       */
        if (cosphi >  1.0) cosphi =  1.0;
        if (cosphi < -1.0) cosphi = -1.0;
        double phi = acos(cosphi);             /* deviation angle in [0, pi]   */
        double coshalf = cos(0.5 * phi);
        if (coshalf < 1e-6) return true;       /* near fold-back -> bevel      */

        double miter_ratio = 1.0 / coshalf;
        if (miter_ratio > miter_limit) {
            /* Exceeds limit -> cairo falls back to bevel (already emitted). */
            return true;
        }

        /* Miter tip = intersection of the two outer offset edges.
         * Outer edge 0 passes through `a` with direction d0.
         * Outer edge 1 passes through `b` with direction d1.
         * Solve a + t*d0 = b + u*d1. */
        cm_dvec2 diff = dv_sub(b, a);
        double denom = dv_cross(d0, d1);       /* == turn, nonzero here       */
        double t = dv_cross(diff, d1) / denom;
        cm_dvec2 tip = dv_add(a, dv_scale(d0, t));

        /* Fill the miter as two triangles p-a-tip and p-tip-b so the wedge is
         * covered regardless of tip distance (still one NONZERO union). */
        if (!cm_emit_tri(dst, p, a, tip)) return false;
        if (!cm_emit_tri(dst, p, tip, b)) return false;
        return true;
    }
}

/* ==========================================================================
 * Caps  (open-contour ends only)
 * --------------------------------------------------------------------------
 * `p` is the endpoint, `dir` is the unit direction the stroke is HEADING at
 * that end pointing OUTWARD (away from the path body), `hw` the half-width.
 * The segment quad already reaches `p`; the cap adds geometry beyond it.
 * ========================================================================== */
static bool cm_emit_cap(cm_path *dst, cm_dvec2 p, cm_dvec2 dir,
                        double hw, cm_line_cap_t cap, double tolerance)
{
    if (cap == CM_LINE_CAP_BUTT) return true;  /* flush end, nothing to add   */

    cm_dvec2 n = dv(-dir.y, dir.x);            /* left normal of outward dir  */
    cm_dvec2 left  = dv_add(p, dv_scale(n,  hw));
    cm_dvec2 right = dv_add(p, dv_scale(n, -hw));

    if (cap == CM_LINE_CAP_SQUARE) {
        /* Extend half-width outward: a rectangle past the endpoint. */
        cm_dvec2 ext = dv_scale(dir, hw);
        cm_dvec2 l2 = dv_add(left,  ext);
        cm_dvec2 r2 = dv_add(right, ext);
        return cm_emit_quad(dst, left, l2, r2, right);
    }

    /* ROUND: a semicircle of radius hw centered at p, from `left` to `right`
     * bulging OUTWARD (in the +dir direction). */
    double a_from = atan2(left.y  - p.y, left.x  - p.x);
    double a_to   = atan2(right.y - p.y, right.x - p.x);
    /* Choose the sweep that bulges along +dir: midpoint direction must have a
     * positive dot with `dir`.  Try CCW; flip if it bulges inward. */
    double orient = +1.0;
    {
        double sweep = a_to - a_from;
        while (sweep <= 0.0)       sweep += 2.0 * M_PI;
        double amid = a_from + 0.5 * sweep;
        cm_dvec2 mid = dv(cos(amid), sin(amid));
        if (dv_dot(mid, dir) < 0.0) orient = -1.0;
    }
    return cm_emit_arc(dst, p, hw, a_from, a_to, orient, tolerance);
}

/* ==========================================================================
 * Degenerate dot
 * --------------------------------------------------------------------------
 * cairo draws a dot for a zero-length sub-path when the cap is ROUND (a full
 * disc) or SQUARE (an axis... actually a hw-square); BUTT draws nothing.  This
 * matches manim drawing isolated points / closed single-vertex sub-paths.
 * ========================================================================== */
static bool cm_emit_dot(cm_path *dst, cm_dvec2 p, double hw, cm_line_cap_t cap,
                        double tolerance)
{
    if (cap == CM_LINE_CAP_BUTT) return true;

    if (cap == CM_LINE_CAP_ROUND) {
        /* Full circle as one convex fan. */
        return cm_emit_arc(dst, p, hw, 0.0, 2.0 * M_PI, +1.0, tolerance);
    }
    /* SQUARE: axis-aligned square of side line_width centered at p.  cairo
     * orients the cap square to the (undefined) direction; with no direction
     * an axis-aligned square is the conventional result. */
    cm_dvec2 q[4] = {
        dv(p.x - hw, p.y - hw),
        dv(p.x + hw, p.y - hw),
        dv(p.x + hw, p.y + hw),
        dv(p.x - hw, p.y + hw),
    };
    return cm_emit_poly(dst, q, 4);
}

/* ==========================================================================
 * Per-contour stroking
 * ========================================================================== */

/*
 * Copy a contour's points, dropping consecutive duplicates (zero-length
 * segments carry no direction and would corrupt normals/joins).  For a closed
 * contour also drop a final point coincident with the first (the implicit
 * closing segment is added separately).  Writes into the caller-provided
 * scratch array `out` (capacity >= contour point_count) and returns the count.
 */
static uint32_t cm_dedup_contour(const cm_path *src, const cm_contour *c,
                                 cm_dvec2 *out)
{
    const cm_vec2f *sp = src->pts + c->first_point;
    uint32_t in = c->point_count;
    if (in == 0) return 0;

    uint32_t m = 0;
    out[m++] = dv(sp[0].x, sp[0].y);
    const double eps2 = 1e-12;                  /* squared coincidence epsilon */
    for (uint32_t i = 1; i < in; ++i) {
        cm_dvec2 p = dv(sp[i].x, sp[i].y);
        cm_dvec2 d = dv_sub(p, out[m - 1]);
        if (dv_dot(d, d) > eps2) out[m++] = p;
    }
    /* For closed contours, a trailing point equal to the first is redundant. */
    if (c->closed && m > 1) {
        cm_dvec2 d = dv_sub(out[m - 1], out[0]);
        if (dv_dot(d, d) <= eps2) m--;
    }
    return m;
}

static cm_status_t cm_stroke_contour(const cm_path *src, const cm_contour *c,
                                     cm_path *dst, double hw,
                                     cm_line_join_t join, cm_line_cap_t cap,
                                     double miter_limit, double tolerance)
{
    if (c->point_count == 0) return CM_STATUS_SUCCESS;

    /* Dedup into a scratch buffer; small-on-stack with heap fallback. */
    cm_dvec2  stackpts[256];
    cm_dvec2 *p = stackpts;
    cm_dvec2 *heap = NULL;
    if (c->point_count > (uint32_t)(sizeof(stackpts) / sizeof(stackpts[0]))) {
        heap = (cm_dvec2 *)malloc((size_t)c->point_count * sizeof(cm_dvec2));
        if (!heap) return CM_STATUS_NO_MEMORY;
        p = heap;
    }
    uint32_t n = cm_dedup_contour(src, c, p);

    cm_status_t st = CM_STATUS_SUCCESS;

    /* Degenerate: a single distinct point -> dot (round/square caps draw it). */
    if (n < 2) {
        if (n == 1) {
            if (!cm_emit_dot(dst, p[0], hw, cap, tolerance)) st = CM_STATUS_NO_MEMORY;
        }
        free(heap);
        return st;
    }

    bool closed = c->closed;

    /* Number of straight segments. */
    uint32_t seg_count = closed ? n : (n - 1);

    /* --- segment quads --------------------------------------------------- */
    for (uint32_t i = 0; i < seg_count; ++i) {
        cm_dvec2 a = p[i];
        cm_dvec2 b = p[(i + 1) % n];           /* wrap for the closing segment */
        cm_dvec2 e = dv_sub(b, a);
        double L = dv_len(e);
        if (L < 1e-9) continue;                /* already deduped, be safe     */
        cm_dvec2 dir = dv_scale(e, 1.0 / L);
        cm_dvec2 nrm = dv(-dir.y, dir.x);      /* left normal                  */
        cm_dvec2 off = dv_scale(nrm, hw);
        cm_dvec2 a0 = dv_add(a, off), a1 = dv_sub(a, off);
        cm_dvec2 b0 = dv_add(b, off), b1 = dv_sub(b, off);
        /* Quad ordered around the rectangle (a0,b0,b1,a1). */
        if (!cm_emit_quad(dst, a0, b0, b1, a1)) { st = CM_STATUS_NO_MEMORY; goto done; }
    }

    /* --- joins ----------------------------------------------------------- */
    /* Join vertices: closed -> every vertex k in [0, n-1] (including the wrap
     * join at p[0] between the closing segment and the first segment); open ->
     * interior vertices k in [1, n-2] only (the two ends get caps, not joins).
     * A 2-point open contour has no interior vertex -> the loop runs zero times. */
    {
        /* Half-open [k_lo, k_hi): closed -> [0, n); open -> [1, n-1). */
        uint32_t k_lo = closed ? 0u : 1u;
        uint32_t k_hi = closed ? n : (n >= 1 ? n - 1 : 0u);
        for (uint32_t k = k_lo; k < k_hi; ++k) {
            uint32_t kp = (k == 0) ? (n - 1) : (k - 1);   /* previous vertex   */
            uint32_t kn = (k + 1) % n;                     /* next vertex      */

            cm_dvec2 ein = dv_sub(p[k],  p[kp]);
            cm_dvec2 eout = dv_sub(p[kn], p[k]);
            double Li = dv_len(ein), Lo = dv_len(eout);
            if (Li < 1e-9 || Lo < 1e-9) continue;
            cm_dvec2 d0 = dv_scale(ein,  1.0 / Li);
            cm_dvec2 d1 = dv_scale(eout, 1.0 / Lo);
            if (!cm_emit_join(dst, p[k], d0, d1, hw, join, miter_limit, tolerance)) {
                st = CM_STATUS_NO_MEMORY; goto done;
            }
        }
    }

    /* --- caps (open contours only) --------------------------------------- */
    if (!closed) {
        /* Start cap: outward direction points back from p[0] (i.e. -first seg). */
        cm_dvec2 e0 = dv_sub(p[1], p[0]);
        double L0 = dv_len(e0);
        if (L0 >= 1e-9) {
            cm_dvec2 out_start = dv_scale(e0, -1.0 / L0);
            if (!cm_emit_cap(dst, p[0], out_start, hw, cap, tolerance)) {
                st = CM_STATUS_NO_MEMORY; goto done;
            }
        }
        /* End cap: outward direction is the last segment's forward direction. */
        cm_dvec2 e1 = dv_sub(p[n - 1], p[n - 2]);
        double L1 = dv_len(e1);
        if (L1 >= 1e-9) {
            cm_dvec2 out_end = dv_scale(e1, 1.0 / L1);
            if (!cm_emit_cap(dst, p[n - 1], out_end, hw, cap, tolerance)) {
                st = CM_STATUS_NO_MEMORY; goto done;
            }
        }
    }

done:
    free(heap);
    return st;
}

/* ==========================================================================
 * Public (internal-contract) entry point
 * ========================================================================== */
cm_status_t cm_stroke_expand(const cm_path *src, cm_path *dst,
                             double line_width,
                             cm_line_join_t join, cm_line_cap_t cap,
                             double miter_limit, double tolerance)
{
    if (!src || !dst) return CM_STATUS_NO_MEMORY;
    if (!(tolerance > 0.0)) tolerance = CM_ARC_TOLERANCE;

    /* Reset dst's flattened cache in place (keep capacity for amortized reuse;
     * the scratch path is reused across frames per the design). */
    dst->pts_count     = 0;
    dst->contour_count = 0;

    /* Degenerate width: cairo draws nothing for width <= 0. */
    if (!(line_width > 0.0)) {
        dst->dirty = false;
        return CM_STATUS_SUCCESS;
    }

    double hw = 0.5 * line_width;
    double ml = (miter_limit > 0.0) ? miter_limit : 10.0;

    cm_status_t st = CM_STATUS_SUCCESS;
    for (uint32_t ci = 0; ci < src->contour_count; ++ci) {
        st = cm_stroke_contour(src, &src->contours[ci], dst, hw,
                               join, cap, ml, tolerance);
        if (st != CM_STATUS_SUCCESS) break;
    }

    /*
     * dst now holds device-space outline geometry in its FLATTENED cache.
     * Mark it not-dirty so a downstream cm_path_flatten(dst, identity) is a
     * no-op and does NOT re-transform / re-flatten our geometry.  We do not
     * populate the recorded verb arrays: dst is consumed only by the fill
     * encoder, which reads pts/contours directly.
     */
    dst->dirty = false;

    return st;
}

/* ==========================================================================
 * Dash chopping  (cm_dash_apply)
 * ==========================================================================
 *
 * Runs BEFORE cm_stroke_expand.  Reads `src`'s DEVICE-space flattened cache
 * (the same representation cm_stroke_expand consumes) and writes the "on"
 * sub-segments into `dst`'s DEVICE-space flattened cache as INDEPENDENT OPEN
 * contours, so a following cm_stroke_expand(dst, ...) caps both ends of every
 * dash and never joins across an "off" gap.  `dst` is consumed only by the fill
 * encoder / cm_stroke_expand, which read pts/contours directly, so -- exactly
 * like cm_stroke_expand -- we write straight into the flattened cache and set
 * dst->dirty = false so a downstream cm_path_flatten(dst, identity) is a no-op.
 *
 * Units: `dashes` and `offset` are DEVICE-space lengths (the caller pre-scaled
 * the user-space cairo dash by cm_matrix_max_scale(CTM); see the file header).
 *
 * Pattern semantics (cairo-exact, _cairo_path_fixed_dash):
 *   - the pattern is a cycle of `n` lengths; index 0 is "on", then it alternates
 *     on/off by parity of the running index (i % 2 == 0 -> on).  For an ODD `n`
 *     the on/off roles therefore swap on every pass through the array, which is
 *     cairo's documented "odd dash array doubles the period" behaviour, produced
 *     automatically by cycling the index 0,1,..,n-1,0,1,...  and testing parity.
 *   - `offset` advances the starting phase; it is reduced modulo the pattern
 *     period (the sum of the lengths) so any offset is well-defined.
 *   - every sub-path (contour) RESTARTS the dash phase from `offset`, matching
 *     cairo (the dash is not carried across move_to).
 * ========================================================================== */

/* Per-contour dash cursor: which dash index we are in and how much of it is
 * left to consume, plus whether that index is "on". */
typedef struct {
    const double *dashes;
    int           n;
    double        period;       /* sum of all dash lengths (> 0)              */
    int           idx;          /* current dash index in [0, n)               */
    double        remain;       /* length left in the current dash            */
    bool          on;           /* current dash is "on" (drawn)               */
    bool          piece_open;   /* an on-piece contour is currently open      */
} cm_dash_state;

/* Reset the dash cursor to the start phase for a new sub-path: seek `offset`
 * (already reduced into [0, period), period > 0) into the pattern.  Leaves the
 * cursor on the dash entry the offset falls within, with `remain` the unconsumed
 * tail of that entry (>= 0).  Bounded: zero-length entries are skipped without
 * spinning because the index walk is capped at one full pattern traversal. */
static void cm_dash_state_reset(cm_dash_state *s, double offset)
{
    s->idx = 0;
    s->on  = true;             /* index 0 is "on" */
    s->piece_open = false;

    double left = offset;
    /* Advance past whole entries while the offset still covers the current one.
     * `left < period` on entry, so at most n steps land us inside an entry; the
     * `guard` cap is belt-and-suspenders against a zero-length entry chain. */
    uint32_t guard = 0;
    while (left >= s->dashes[s->idx] && guard < (uint32_t)s->n) {
        left -= s->dashes[s->idx];
        s->idx = (s->idx + 1) % s->n;
        s->on  = !s->on;
        guard++;
    }
    s->remain = s->dashes[s->idx] - left;
    if (s->remain < 0.0) s->remain = 0.0;
}

/* Begin a new OPEN on-piece contour in `dst`, seeding it with `p`.  Returns
 * false on OOM. */
static bool cm_dash_open_begin(cm_path *dst, cm_dvec2 p)
{
    if (!cm_pts_reserve(dst, dst->pts_count + 1)) return false;
    if (!cm_contours_reserve(dst, dst->contour_count + 1)) return false;
    uint32_t first = dst->pts_count;
    dst->pts[first].x = (float)p.x;
    dst->pts[first].y = (float)p.y;
    dst->pts_count++;

    cm_contour *c = &dst->contours[dst->contour_count++];
    c->first_point = first;
    c->point_count = 1;
    c->closed      = false;     /* OPEN: cm_stroke_expand caps both ends       */
    c->has_current = false;
    return true;
}

/* Append `p` to the on-piece contour currently open at the tail of `dst`.
 * Returns false on OOM. */
static bool cm_dash_open_push(cm_path *dst, cm_dvec2 p)
{
    if (!cm_pts_reserve(dst, dst->pts_count + 1)) return false;
    dst->pts[dst->pts_count].x = (float)p.x;
    dst->pts[dst->pts_count].y = (float)p.y;
    dst->pts_count++;
    dst->contours[dst->contour_count - 1].point_count++;
    return true;
}

/* Walk one straight segment a->b of length L (precomputed), chopping it against
 * the dash cursor and emitting on-pieces into `dst`.  `dir` is the unit a->b
 * direction.  Returns false on OOM. */
static bool cm_dash_segment(cm_path *dst, cm_dash_state *s,
                            cm_dvec2 a, cm_dvec2 dir, double L)
{
    double pos = 0.0;          /* distance consumed along this segment        */
    cm_dvec2 cur = a;

    /* If we are mid "on" piece carried from the previous segment, the open
     * contour already ends at `a`; otherwise nothing is open here. */
    while (pos < L) {
        double step = L - pos;             /* remaining length of this segment */
        if (s->remain < step) step = s->remain;

        cm_dvec2 next = dv_add(cur, dv_scale(dir, step));

        /* Only emit for a positive step.  A zero step happens when `remain`
         * arrived at 0 (offset landed exactly on a boundary); the boundary
         * advance below then flips on/off without producing a degenerate
         * (zero-length) on-piece. */
        if (s->on && step > 0.0) {
            if (!s->piece_open) {
                /* Open a new on-piece starting at the current point. */
                if (!cm_dash_open_begin(dst, cur)) return false;
                s->piece_open = true;
            }
            /* Extend the open piece to the step end. */
            if (!cm_dash_open_push(dst, next)) return false;
        }

        pos        += step;
        s->remain  -= step;
        cur         = next;

        /* Exhausted the current dash entry exactly -> advance to the next one. */
        if (s->remain <= 1e-9) {
            /* Close the current on-piece (if any) at a dash boundary: the next
             * dash is "off", so the piece must end here and get a cap. */
            if (s->on) s->piece_open = false;
            s->idx    = (s->idx + 1) % s->n;
            s->on     = !s->on;
            s->remain = s->dashes[s->idx];
            /* Skip zero-length dash entries so we never spin in place: a 0 entry
             * just flips on/off without consuming length. */
            uint32_t guard = 0;
            while (s->remain <= 0.0 && guard < (uint32_t)s->n) {
                if (s->on) s->piece_open = false;
                s->idx    = (s->idx + 1) % s->n;
                s->on     = !s->on;
                s->remain = s->dashes[s->idx];
                guard++;
            }
        }
    }
    return true;
}

/* Chop one contour of `src` into on-pieces.  `offset` is already reduced into
 * [0, period).  Returns false on OOM. */
static bool cm_dash_contour(const cm_path *src, const cm_contour *c,
                            cm_path *dst, cm_dash_state *s, double offset)
{
    if (c->point_count == 0) return true;

    /* Dedup into a scratch buffer (zero-length segments carry no direction and
     * would emit empty steps), mirroring cm_stroke_contour. */
    cm_dvec2  stackpts[256];
    cm_dvec2 *p = stackpts;
    cm_dvec2 *heap = NULL;
    if (c->point_count > (uint32_t)(sizeof(stackpts) / sizeof(stackpts[0]))) {
        heap = (cm_dvec2 *)malloc((size_t)c->point_count * sizeof(cm_dvec2));
        if (!heap) return false;
        p = heap;
    }
    uint32_t n = cm_dedup_contour(src, c, p);

    bool ok = true;
    if (n >= 2) {
        /* Fresh dash phase for this sub-path (cairo restarts at each move_to). */
        cm_dash_state_reset(s, offset);

        uint32_t seg_count = c->closed ? n : (n - 1);
        for (uint32_t i = 0; i < seg_count && ok; ++i) {
            cm_dvec2 a = p[i];
            cm_dvec2 b = p[(i + 1) % n];      /* wrap for the closing segment   */
            cm_dvec2 e = dv_sub(b, a);
            double   L = dv_len(e);
            if (L < 1e-9) continue;
            cm_dvec2 dir = dv_scale(e, 1.0 / L);
            ok = cm_dash_segment(dst, s, a, dir, L);
        }
        /* End of contour: an on-piece left open simply ends here (it gets a cap
         * from cm_stroke_expand because the emitted contour is OPEN).  For a
         * closed contour cairo does NOT fuse the wrap-around first/last dashes,
         * so we likewise leave them as two capped pieces -- nothing to merge. */
        s->piece_open = false;
    }
    /* n < 2: a single distinct point has zero length -> no on-piece (cairo draws
     * nothing for a degenerate dashed sub-path; cm_stroke_expand's dot path is
     * for UN-dashed zero-length sub-paths only). */

    free(heap);
    return ok;
}

cm_status_t cm_dash_apply(const cm_path *src, cm_path *dst,
                          const double *dashes, int n, double offset)
{
    if (!src || !dst) return CM_STATUS_NO_MEMORY;

    /* Reset dst's flattened cache in place (keep capacity for amortized reuse),
     * exactly like cm_stroke_expand. */
    dst->pts_count     = 0;
    dst->contour_count = 0;
    dst->dirty         = false;

    /* No (or invalid) dash pattern: nothing to chop.  The caller is expected to
     * skip dashing entirely and stroke `src` directly in that case; we still
     * leave dst empty + clean so a stray call is harmless. */
    if (!dashes || n <= 0) return CM_STATUS_SUCCESS;

    /* Pattern period; a non-positive total means an all-zero pattern (cairo
     * rejects this at set_dash time as INVALID_DASH, so we never expect it, but
     * guard so we cannot divide by zero / loop forever). */
    double period = 0.0;
    for (int i = 0; i < n; ++i) {
        if (!(dashes[i] >= 0.0)) return CM_STATUS_INVALID_DASH;  /* NaN / <0     */
        period += dashes[i];
    }
    if (!(period > 0.0)) return CM_STATUS_INVALID_DASH;

    /* Reduce the (possibly large or negative) offset into [0, period).  cairo
     * accepts any finite offset; fmod can return a negative for a negative
     * offset, so fold it back up. */
    double off = offset;
    if (isfinite(off)) {
        off = fmod(off, period);
        if (off < 0.0) off += period;
    } else {
        off = 0.0;
    }

    cm_dash_state st_state;
    st_state.dashes = dashes;
    st_state.n      = n;
    st_state.period = period;

    cm_status_t st = CM_STATUS_SUCCESS;
    for (uint32_t ci = 0; ci < src->contour_count; ++ci) {
        if (!cm_dash_contour(src, &src->contours[ci], dst, &st_state, off)) {
            st = CM_STATUS_NO_MEMORY;
            break;
        }
    }

    /* dst holds device-space on-piece polylines in its FLATTENED cache; mark it
     * already-flattened so a downstream identity flatten does not re-transform
     * it, matching cm_stroke_expand's contract. */
    dst->dirty = false;
    return st;
}

/* ==========================================================================
 * Dash pre-pass  (cm_dash_prepass)
 * --------------------------------------------------------------------------
 * Thin wrapper over cm_dash_apply that BOTH stroke entry points share -- the
 * draw path (cm_stroke_preserve in cairo_metal.m) and the extents/hit-test path
 * (cm_build_stroke_outline in cm_query.c) -- so the device-space dash SCALING
 * contract lives in exactly ONE place and the two sites can never drift.
 *
 * cairo dash lengths + offset are USER space (like line width); cm_dash_apply
 * chops the DEVICE-space flattened `src`, so we scale each length and the offset
 * by the same cm_matrix_max_scale(CTM) the callers already apply to line_width
 * (isotropic-CTM assumption -- see this file's header).  When no dash pattern is
 * set we hand back `src` unchanged so the un-dashed stroke is byte-for-byte the
 * prior behaviour.  A singular CTM (max scale <= 0) likewise hands back `src`
 * unchanged -- an undashed fallback -- rather than scaling the pattern to all-zero
 * (which cm_dash_apply would reject as INVALID_DASH); the device line width is
 * also zero under such a CTM, so nothing is drawn either way.
 * ========================================================================== */
cm_status_t cm_dash_prepass(const cm_context_t *ctx, const cm_path *src,
                            cm_path *scratch, const cm_path **out)
{
    if (out) *out = src;                       /* default: stroke src directly  */
    if (!ctx || !src || !scratch) return CM_STATUS_NO_MEMORY;

    /* No dash pattern: stroke the flattened src directly (identical output). */
    if (!ctx->dash || ctx->dash_count <= 0) return CM_STATUS_SUCCESS;

    int n = ctx->dash_count;

    /* A singular / non-scaling CTM (max scale <= 0) cannot map the USER-space dash
     * lengths into device space: scaling them all to zero would make cm_dash_apply
     * reject the (perfectly valid) pattern as INVALID_DASH.  Fall back to an
     * UNDASHED stroke of `src` -- `out` already points at `src`, and the device
     * line width the callers derive is likewise zero under such a CTM, so this
     * draws nothing either way while keeping the context status SUCCESS rather
     * than flagging a valid dash as invalid.  Living in this shared pre-pass, the
     * fallback applies identically to the stroke DRAW path (cm_stroke_preserve)
     * and the stroke QUERY path (cm_build_stroke_outline). */
    double scale = cm_matrix_max_scale(&ctx->ctm);
    if (!(scale > 0.0)) return CM_STATUS_SUCCESS;

    /* Pre-scale user-space dash lengths + offset to device space.  Small pattern
     * on the stack; heap only for an unusually long one. */
    double  stackbuf[32];
    double *scaled = stackbuf;
    double *heap   = NULL;
    if (n > (int)(sizeof(stackbuf) / sizeof(stackbuf[0]))) {
        heap = (double *)malloc((size_t)n * sizeof(double));
        if (!heap) return CM_STATUS_NO_MEMORY;
        scaled = heap;
    }
    for (int i = 0; i < n; ++i) scaled[i] = ctx->dash[i] * scale;
    double scaled_offset = ctx->dash_offset * scale;

    cm_status_t st = cm_dash_apply(src, scratch, scaled, n, scaled_offset);
    free(heap);

    if (st != CM_STATUS_SUCCESS) { if (out) *out = NULL; return st; }
    if (out) *out = scratch;                   /* stroke the dashed on-pieces   */
    return CM_STATUS_SUCCESS;
}
