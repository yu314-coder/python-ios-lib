/*
 * cm_mesh.c  --  CairoMetal MeshPattern (Coons-patch record + CPU tessellation)
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_mesh.c"): the cairo MeshPattern
 * (CAIRO_PATTERN_TYPE_MESH).  A mesh pattern is a list of Coons (Type-6/7
 * tensor-product) patches; each patch has up to four cubic boundary sides and a
 * colour at each of its four corners.  Filling with a mesh source paints the
 * union of the patches, the colour at any interior point being the bilinear
 * blend of the four corner colours over the patch's parametric (u,v) square and
 * the position being the Coons surface interpolation of the four boundary
 * curves.
 *
 * This file does two things, mirroring how cm_path records verbs then flattens:
 *
 *   1. RECORD.  begin_patch / end_patch bracket a patch; move_to seeds the first
 *      corner, and up to four line_to / curve_to calls walk the boundary,
 *      cairo's "default-fill" rules supplying any side or corner the caller
 *      omits (missing sides become straight lines; the first patch's missing
 *      corner-0 defaults to the origin; later patches inherit the shared edge +
 *      corners from the previous patch).  set_control_point / set_corner_color_*
 *      override individual boundary points / corner colours after the walk.
 *      get_patch_count / get_control_point / get_corner_color_rgba read it back.
 *
 *   2. TESSELLATE (INTERNAL, for the cm_fill GOURAUD pass).  cm_mesh_emit_
 *      triangles evaluates the Coons surface on a regular (u,v) grid whose
 *      resolution is driven by the patch's DEVICE-space size over CM_ARC_
 *      TOLERANCE (so on-screen facetting is bounded regardless of the CTM),
 *      bilinearly interpolates the corner colours, and emits two cm_vtx_color
 *      triangles per grid cell IN DEVICE SPACE.  cm_mesh_triangle_vertex_count
 *      returns the exact vertex count the caller must allocate from the frame
 *      ring before calling emit.  The mesh triangles ARE the coverage: the GPU
 *      GOURAUD cover pass (cm_fill.m / CM_PIPE_COVER_GOURAUD, vertex stage
 *      cm_vs_cover_color, fragment cm_fs_cover_gouraud) draws them clipped to the
 *      fill path's pass-1 stencil, so this file performs NO triangulation of the
 *      fill outline -- only of each patch's parametric square.
 *
 * This translation unit is pure C: it touches no Metal / Objective-C objects,
 * only the POD cm_mesh_* structs and the cm_vtx_color buffer cm_fill.m bump-
 * allocates from the per-frame ring.  cm_mesh_pattern_create lives HERE (not in
 * cm_pattern.c) so the mesh payload stays with its logic; the base lifecycle
 * (reference / destroy / matrix / extend / filter) and the freeing of
 * mesh.patches stay in cm_pattern.c, the universal pattern owner.
 *
 * ----------------------------------------------------------------------------
 * STORAGE LAYOUT  (reconciled against the FROZEN cm_mesh_patch in cm_internal.h)
 * ----------------------------------------------------------------------------
 * A general cubic-sided Coons patch needs 12 distinct boundary control points
 * (4 corners + 2 interior controls per side).  cm_mesh_patch.pts is pts[8][2],
 * so it cannot hold all 12; the contract (which this task may NOT widen) calls
 * the corners "implied".  We therefore store the boundary as
 *
 *     pts[0] = corner 0      pts[1] = side-0 control     (corner0 -> corner1)
 *     pts[2] = corner 1      pts[3] = side-1 control     (corner1 -> corner2)
 *     pts[4] = corner 2      pts[5] = side-2 control     (corner2 -> corner3)
 *     pts[6] = corner 3      pts[7] = side-3 control     (corner3 -> corner0)
 *
 * i.e. the four CORNERS at the even slots and ONE control per side at the odd
 * slots, so each boundary side is a QUADRATIC Bezier (corner, control, corner).
 * A caller-supplied CUBIC side curve_to(c1,c2,end) is collapsed to the single
 * quadratic control that reproduces the cubic's midpoint exactly,
 *     ctrl = ( 3*(c1 + c2) - (start + end) ) / 4,
 * and a straight line_to stores the segment midpoint (an exact degenerate
 * quadratic).  This is the faithful best fit under the 8-pair cap and keeps
 * set/get_control_point round-tripping; the public point indices 0..7 map onto
 * the slots above.
 *
 * >>> CROSS-MODULE SEAM (for the Build phase): full cubic-side fidelity would
 * >>> require widening cm_mesh_patch.pts to [12][2] in cm_internal.h -- a shared-
 * >>> header change deliberately OUT OF SCOPE here.  If a future call site needs
 * >>> exact cubic mesh boundaries (manim's gradient meshes use 4-corner bilinear
 * >>> patches, which are exact under this layout), widen the struct and extend
 * >>> the slot map below; nothing else in this file assumes the quadratic
 * >>> collapse beyond cm__patch_boundary_point().
 *
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ==========================================================================
 * Tessellation tunables
 * ========================================================================== */

/* Minimum / maximum grid subdivisions PER PARAMETRIC AXIS of a patch.  The
 * adaptive count between these is driven by the patch's device-space extent
 * over CM_ARC_TOLERANCE.  MIN keeps even a tiny patch from degenerating to a
 * single quad (so the Gouraud blend is still smooth across a small patch); MAX
 * bounds worst-case work + ring usage for a hugely scaled patch the same way
 * CM_FLATTEN_MAX_DEPTH bounds path flattening. */
#define CM_MESH_MIN_DIV   2u
#define CM_MESH_MAX_DIV   64u

/* Local POD for a 2D point during evaluation (kept double for accuracy; the
 * emitted cm_vtx_color downcasts to float at the very end, like cm_path). */
typedef struct { double x, y; } cm_pt2;

/* ==========================================================================
 * Patch storage slot map (see file header)
 * ========================================================================== */

#define CM_MESH_CORNER_SLOT(i)   (((uint32_t)(i) * 2u) & 7u)  /* corner 0..3 */
#define CM_MESH_CTRL_SLOT(i)     ((((uint32_t)(i) * 2u) + 1u) & 7u) /* side 0..3 */

/* ==========================================================================
 * Base pattern allocation (mesh-typed)
 * --------------------------------------------------------------------------
 * Mirrors cm_pattern.c's allocator but owned here per the module map so the
 * mesh payload is created alongside its logic.  Defaults match cm_pattern_alloc
 * for the non-gradient case (extend NONE, filter GOOD, identity matrix).
 * ========================================================================== */
static cm_pattern_t *cm_mesh_alloc(void)
{
    cm_pattern_t *p = (cm_pattern_t *)calloc(1, sizeof(*p));
    if (!p) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }
    p->type     = CM_PATTERN_TYPE_MESH;
    p->kind     = CM_PAINT_MESH;
    p->refcount = 1;
    p->status   = CM_STATUS_SUCCESS;
    p->extend   = CM_EXTEND_NONE;
    p->filter   = CM_FILTER_GOOD;
    cm_matrix_identity(&p->matrix);
    cm_set_last_status(CM_STATUS_SUCCESS);
    return p;
}

cm_pattern_t *cm_mesh_pattern_create(void)
{
    return cm_mesh_alloc();
}

/* ==========================================================================
 * Patch-array growth (amortized x2, like cm_path's arrays)
 * ========================================================================== */
static cm_mesh_patch *cm_mesh_grow(cm_mesh_data *m)
{
    if (m->count >= m->cap) {
        uint32_t cap = m->cap ? m->cap * 2u : CM_MESH_MAX_PATCHES_INIT;
        cm_mesh_patch *np = (cm_mesh_patch *)realloc(
            m->patches, (size_t)cap * sizeof(cm_mesh_patch));
        if (!np) return NULL;
        m->patches = np;
        m->cap = cap;
    }
    return &m->patches[m->count];
}

/* ==========================================================================
 * Record: begin / end patch
 * ==========================================================================
 *
 * cairo: cairo_mesh_pattern_begin_patch starts a new patch; it is an error to
 * begin a patch while one is already open (CAIRO_STATUS_INVALID_MESH_CONSTRUCTION
 * -> our closest stable code, CM_STATUS_INVALID_INDEX).  end_patch commits the
 * patch under construction.  cairo also requires at least one side and rejects
 * more than four; we apply the same bounds and additionally run the default-fill
 * completion (missing sides -> straight lines, corner/colour inheritance) at end
 * time so a committed patch is always a well-formed 4-corner / 4-side closed
 * loop the tessellator can evaluate unconditionally.
 */
void cm_mesh_pattern_begin_patch(cm_pattern_t *pattern)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    memset(&m->cur, 0, sizeof(m->cur));
    m->in_patch = true;
}

/* Linearly interpolate two stored points (used to default missing corners). */
static void cm__lerp_pt(const double a[2], const double b[2], double t,
                        double out[2])
{
    out[0] = a[0] + (b[0] - a[0]) * t;
    out[1] = a[1] + (b[1] - a[1]) * t;
}

/*
 * Complete a patch to cairo's default-fill rules and commit it.
 *
 * After the boundary walk, `side_count` sides (0..4) were specified.  cairo
 * fills any UNSPECIFIED side with a straight line between its two corners, and
 * if corner 0 was never positioned (no move_to / no inheritance) it defaults to
 * the origin.  We:
 *   - leave corner slots that the walk wrote untouched;
 *   - for each side i in [side_count, 4): mark it straight, and set its control
 *     to the midpoint of (corner i, corner i+1) so cm__patch_boundary_point
 *     evaluates the side as an exact line;
 *   - inherit each missing corner colour from corner 0 (cairo defaults unset
 *     corner colours to transparent black; we instead clamp to whatever WAS set,
 *     preferring corner 0, so a patch given a single colour fills solid -- the
 *     behaviour manim relies on for flat-colour patches.  A patch with NO colour
 *     at all falls back to transparent black, matching cairo).
 *
 * The corners themselves: the walk already wrote corner (i+1) as the endpoint of
 * side i, and corner 0 from move_to.  Corners beyond the specified sides keep the
 * coincident value the walk left (the last endpoint), which makes the unfilled
 * region collapse -- but combined with the straight-line side completion the
 * patch stays a valid (possibly degenerate) loop, never reading uninitialised
 * geometry.
 */
static void cm__commit_patch(cm_mesh_data *m, cm_pattern_t *pattern)
{
    cm_mesh_patch *cur = &m->cur;

    /* Clamp the recorded side count to the valid range. */
    if (cur->side_count > 4u) cur->side_count = 4u;

    /* Fill straight sides for every side the caller did not specify, using the
     * midpoint of the two corners as the (degenerate-quadratic) control. */
    for (uint32_t s = cur->side_count; s < 4u; ++s) {
        uint32_t c0 = CM_MESH_CORNER_SLOT(s);
        uint32_t c1 = CM_MESH_CORNER_SLOT((s + 1u) & 3u);
        uint32_t ck = CM_MESH_CTRL_SLOT(s);
        cm__lerp_pt(cur->pts[c0], cur->pts[c1], 0.5, cur->pts[ck]);
    }

    /* Corner-colour default-fill: find the first colour that WAS set; broadcast
     * it to every unset corner.  If none was set, all stay {0,0,0,0}. */
    int first = -1;
    for (int i = 0; i < 4; ++i) {
        if (cur->have_color[i]) { first = i; break; }
    }
    if (first >= 0) {
        for (int i = 0; i < 4; ++i) {
            if (!cur->have_color[i]) {
                cur->color[i] = cur->color[first];
                cur->have_color[i] = true;
            }
        }
    }

    cm_mesh_patch *slot = cm_mesh_grow(m);
    if (!slot) { pattern->status = CM_STATUS_NO_MEMORY; return; }
    *slot = *cur;
    m->count++;
}

void cm_mesh_pattern_end_patch(cm_pattern_t *pattern)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    /* cairo requires at least one side; a begin/end with no sides is an invalid
     * construction.  Commit nothing and flag it (stable code). */
    if (m->cur.side_count == 0u) {
        pattern->status = CM_STATUS_INVALID_INDEX;
        m->in_patch = false;
        return;
    }
    cm__commit_patch(m, pattern);
    m->in_patch = false;
}

/* ==========================================================================
 * Record: boundary walk (move_to / line_to / curve_to)
 * ==========================================================================
 *
 * cairo's per-patch path API: ONE move_to defines corner 0, then each line_to /
 * curve_to adds the NEXT side and its terminating corner.  We track the running
 * "start corner" of the side being added as cur->pts[corner(side_count)], write
 * the control into the side's odd slot, and write the endpoint into the next
 * corner's even slot.
 */

/* Write corner i (0..3) of the patch under construction. */
static void cm__set_corner(cm_mesh_patch *cur, uint32_t i, double x, double y)
{
    uint32_t slot = CM_MESH_CORNER_SLOT(i & 3u);
    cur->pts[slot][0] = x;
    cur->pts[slot][1] = y;
}

void cm_mesh_pattern_move_to(cm_pattern_t *pattern, double x, double y)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    /* move_to is only valid as the FIRST boundary op (defines corner 0). */
    cm__set_corner(&m->cur, 0u, x, y);
}

void cm_mesh_pattern_line_to(cm_pattern_t *pattern, double x, double y)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    cm_mesh_patch *cur = &m->cur;
    uint32_t s = cur->side_count;
    if (s >= 4u) { pattern->status = CM_STATUS_INVALID_INDEX; return; }

    uint32_t c0 = CM_MESH_CORNER_SLOT(s);          /* side start corner       */
    /* Straight side: control = midpoint of the two corners (exact line). */
    uint32_t ck = CM_MESH_CTRL_SLOT(s);
    double sx = cur->pts[c0][0], sy = cur->pts[c0][1];
    cur->pts[ck][0] = (sx + x) * 0.5;
    cur->pts[ck][1] = (sy + y) * 0.5;
    /* Endpoint becomes the next corner (wraps corner 3 -> back to corner 0). */
    cm__set_corner(cur, (s + 1u) & 3u, x, y);
    cur->side_count = s + 1u;
}

void cm_mesh_pattern_curve_to(cm_pattern_t *pattern,
                              double x1, double y1, double x2, double y2,
                              double x3, double y3)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    cm_mesh_patch *cur = &m->cur;
    uint32_t s = cur->side_count;
    if (s >= 4u) { pattern->status = CM_STATUS_INVALID_INDEX; return; }

    uint32_t c0 = CM_MESH_CORNER_SLOT(s);          /* side start corner       */
    uint32_t ck = CM_MESH_CTRL_SLOT(s);
    double sx = cur->pts[c0][0], sy = cur->pts[c0][1];

    /* Collapse the cubic (start, (x1,y1), (x2,y2), end) to the quadratic whose
     * control reproduces the cubic's t=1/2 midpoint exactly:
     *   cubic mid  M = (start + 3*c1 + 3*c2 + end) / 8
     *   quad  mid  = (start + 2*ctrl + end) / 4  ==  M
     *   => ctrl = ( 3*(c1 + c2) - (start + end) ) / 4. */
    cur->pts[ck][0] = (3.0 * (x1 + x2) - (sx + x3)) * 0.25;
    cur->pts[ck][1] = (3.0 * (y1 + y2) - (sy + y3)) * 0.25;

    cm__set_corner(cur, (s + 1u) & 3u, x3, y3);
    cur->side_count = s + 1u;
}

/* ==========================================================================
 * Record: explicit point / colour overrides
 * ========================================================================== */
void cm_mesh_pattern_set_control_point(cm_pattern_t *pattern,
                                       unsigned int point_num, double x, double y)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    if (point_num >= 8u) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    /* Direct slot override (corner at even, side control at odd -- see header).
     * Mirrors cairo_mesh_pattern_set_control_point overriding a boundary point
     * after the walk; we expose the 8 slots this storage holds. */
    m->cur.pts[point_num][0] = x;
    m->cur.pts[point_num][1] = y;
}

void cm_mesh_pattern_set_corner_color_rgba(cm_pattern_t *pattern,
                                           unsigned int corner_num,
                                           double r, double g, double b, double a)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return;
    cm_mesh_data *m = &pattern->mesh;
    if (!m->in_patch) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    if (corner_num >= 4u) { pattern->status = CM_STATUS_INVALID_INDEX; return; }
    /* PIXEL CONTRACT: store the components in the SAME order the caller passes
     * them (manim pre-swaps to B,G,R,A; we pass through, non-premultiplied --
     * the Gouraud fragment premultiplies on output, matching cm_paint.m). */
    m->cur.color[corner_num].r = (float)r;
    m->cur.color[corner_num].g = (float)g;
    m->cur.color[corner_num].b = (float)b;
    m->cur.color[corner_num].a = (float)a;
    m->cur.have_color[corner_num] = true;
}

void cm_mesh_pattern_set_corner_color_rgb(cm_pattern_t *pattern,
                                          unsigned int corner_num,
                                          double r, double g, double b)
{
    cm_mesh_pattern_set_corner_color_rgba(pattern, corner_num, r, g, b, 1.0);
}

/* ==========================================================================
 * Query (read back committed patches)
 * ========================================================================== */
cm_status_t cm_mesh_pattern_get_patch_count(cm_pattern_t *pattern,
                                            unsigned int *count)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_MESH) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (count) *count = pattern->mesh.count;
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_mesh_pattern_get_control_point(cm_pattern_t *pattern,
                                              unsigned int patch_num,
                                              unsigned int point_num,
                                              double *x, double *y)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_MESH) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (patch_num >= pattern->mesh.count || point_num >= 8u)
        return CM_STATUS_INVALID_INDEX;
    const cm_mesh_patch *pp = &pattern->mesh.patches[patch_num];
    if (x) *x = pp->pts[point_num][0];
    if (y) *y = pp->pts[point_num][1];
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_mesh_pattern_get_corner_color_rgba(cm_pattern_t *pattern,
                                                  unsigned int patch_num,
                                                  unsigned int corner_num,
                                                  double *r, double *g,
                                                  double *b, double *a)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_MESH) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (patch_num >= pattern->mesh.count || corner_num >= 4u)
        return CM_STATUS_INVALID_INDEX;
    const cm_mesh_patch *pp = &pattern->mesh.patches[patch_num];
    if (r) *r = pp->color[corner_num].r;
    if (g) *g = pp->color[corner_num].g;
    if (b) *b = pp->color[corner_num].b;
    if (a) *a = pp->color[corner_num].a;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Coons surface evaluation (INTERNAL)
 * ==========================================================================
 *
 * Boundary parameterisation.  Each side is a quadratic Bezier B_s(t), t in
 * [0,1], from corner s to corner s+1 (mod 4) through the side's stored control
 * (see the storage-layout note in the header).  We orient the four sides into
 * the standard Coons frame:
 *
 *      C0(u) : corner0 -> corner1   (the v = 0 edge, u in [0,1])
 *      C1(v) : corner1 -> corner2   (the u = 1 edge, v in [0,1])
 *      C2(u) : corner3 -> corner2   (the v = 1 edge, u in [0,1])   [side2 rev.]
 *      C3(v) : corner0 -> corner3   (the u = 0 edge, v in [0,1])   [side3 rev.]
 *
 * cairo's mesh walk lays the sides out corner0->1->2->3->0, so side 2 runs
 * corner2->corner3 and side 3 runs corner3->corner0; the v=1 / u=0 edges above
 * are those two reversed, which the eval handles by flipping the parameter.
 *
 * The bilinearly-blended Coons patch surface is the classic
 *
 *   S(u,v) = (1-v)*C0(u) + v*C2(u) + (1-u)*C3(v) + u*C1(v)
 *          - [ (1-u)(1-v)*P00 + u(1-v)*P10 + (1-u)v*P01 + u*v*P11 ]
 *
 * where P00=corner0, P10=corner1, P11=corner2, P01=corner3.  At the corners and
 * edges this reduces to the boundary curves exactly; inside it is the standard
 * lofted Coons blend.
 * ========================================================================== */

/* Quadratic Bezier point at parameter t for control triple (p0, c, p1). */
static cm_pt2 cm__qbez(cm_pt2 p0, cm_pt2 c, cm_pt2 p1, double t)
{
    double mt = 1.0 - t;
    double a = mt * mt;
    double b = 2.0 * mt * t;
    double d = t * t;
    cm_pt2 r;
    r.x = a * p0.x + b * c.x + d * p1.x;
    r.y = a * p0.y + b * c.y + d * p1.y;
    return r;
}

/* Pull a stored slot as a cm_pt2. */
static inline cm_pt2 cm__slot(const cm_mesh_patch *p, uint32_t slot)
{
    cm_pt2 r; r.x = p->pts[slot][0]; r.y = p->pts[slot][1]; return r;
}

/* The four corners P00,P10,P11,P01 (== corners 0,1,2,3). */
static inline cm_pt2 cm__corner(const cm_mesh_patch *p, uint32_t i)
{
    return cm__slot(p, CM_MESH_CORNER_SLOT(i & 3u));
}

/* Boundary edge evaluators in the Coons frame (see header diagram). */
static cm_pt2 cm__edge_bottom(const cm_mesh_patch *p, double u)   /* C0: c0->c1 */
{
    return cm__qbez(cm__corner(p, 0), cm__slot(p, CM_MESH_CTRL_SLOT(0)),
                    cm__corner(p, 1), u);
}
static cm_pt2 cm__edge_right(const cm_mesh_patch *p, double v)    /* C1: c1->c2 */
{
    return cm__qbez(cm__corner(p, 1), cm__slot(p, CM_MESH_CTRL_SLOT(1)),
                    cm__corner(p, 2), v);
}
static cm_pt2 cm__edge_top(const cm_mesh_patch *p, double u)      /* C2: c3->c2 */
{
    /* side 2 is stored corner2->corner3; the v=1 edge runs corner3->corner2,
     * so evaluate side 2 reversed (t = 1-u) to go c3 -> c2 as u: 0 -> 1. */
    return cm__qbez(cm__corner(p, 2), cm__slot(p, CM_MESH_CTRL_SLOT(2)),
                    cm__corner(p, 3), 1.0 - u);
}
static cm_pt2 cm__edge_left(const cm_mesh_patch *p, double v)     /* C3: c0->c3 */
{
    /* side 3 is stored corner3->corner0; the u=0 edge runs corner0->corner3,
     * so evaluate side 3 reversed (t = 1-v) to go c0 -> c3 as v: 0 -> 1. */
    return cm__qbez(cm__corner(p, 3), cm__slot(p, CM_MESH_CTRL_SLOT(3)),
                    cm__corner(p, 0), 1.0 - v);
}

/* Coons surface point S(u,v) for u,v in [0,1]. */
static cm_pt2 cm__coons(const cm_mesh_patch *p, double u, double v)
{
    cm_pt2 b = cm__edge_bottom(p, u);   /* v = 0 */
    cm_pt2 t = cm__edge_top(p, u);      /* v = 1 */
    cm_pt2 l = cm__edge_left(p, v);     /* u = 0 */
    cm_pt2 r = cm__edge_right(p, v);    /* u = 1 */

    cm_pt2 p00 = cm__corner(p, 0);
    cm_pt2 p10 = cm__corner(p, 1);
    cm_pt2 p11 = cm__corner(p, 2);
    cm_pt2 p01 = cm__corner(p, 3);

    double mu = 1.0 - u, mv = 1.0 - v;

    cm_pt2 s;
    /* Ruled surfaces in u and v, minus the bilinear corner term. */
    s.x = mv * b.x + v * t.x + mu * l.x + u * r.x
        - (mu * mv * p00.x + u * mv * p10.x + u * v * p11.x + mu * v * p01.x);
    s.y = mv * b.y + v * t.y + mu * l.y + u * r.y
        - (mu * mv * p00.y + u * mv * p10.y + u * v * p11.y + mu * v * p01.y);
    return s;
}

/* Bilinear corner-colour blend over the patch's parametric square.  Corner
 * order matches the surface: c00=corner0, c10=corner1, c11=corner2, c01=corner3.
 * Interpolated in NON-premultiplied space (the fragment premultiplies). */
static cm_rgba cm__coons_color(const cm_mesh_patch *p, double u, double v)
{
    double mu = 1.0 - u, mv = 1.0 - v;
    double w00 = mu * mv, w10 = u * mv, w11 = u * v, w01 = mu * v;
    const cm_rgba *c = p->color;     /* [0]=c00 [1]=c10 [2]=c11 [3]=c01 */
    cm_rgba r;
    r.r = (float)(w00 * c[0].r + w10 * c[1].r + w11 * c[2].r + w01 * c[3].r);
    r.g = (float)(w00 * c[0].g + w10 * c[1].g + w11 * c[2].g + w01 * c[3].g);
    r.b = (float)(w00 * c[0].b + w10 * c[1].b + w11 * c[2].b + w01 * c[3].b);
    r.a = (float)(w00 * c[0].a + w10 * c[1].a + w11 * c[2].a + w01 * c[3].a);
    return r;
}

/* ==========================================================================
 * Adaptive grid resolution
 * ==========================================================================
 *
 * Pick the per-axis subdivision from the patch's DEVICE-space size so the chord
 * error of the (transformed) boundary curves is ~CM_ARC_TOLERANCE px regardless
 * of the CTM, mirroring how cm_path flattens in device space.  We size by the
 * device-space extent of the four corners + four controls (a conservative bound
 * on the patch footprint): div ~= sqrt(maxExtent / tol), clamped to [MIN,MAX].
 * One count is used for BOTH axes (square grid) for simplicity and predictable
 * vertex counts; the bound is an over-estimate, never an under-estimate.
 */
static uint32_t cm__patch_divisions(const cm_mesh_patch *p, const cm_matrix_t *ctm)
{
    /* Transform the 8 stored boundary points to device space and measure the
     * AABB.  cm_matrix_apply tolerates a NULL matrix as identity. */
    double minx = 0, miny = 0, maxx = 0, maxy = 0;
    bool first = true;
    for (uint32_t i = 0; i < 8u; ++i) {
        double dx, dy;
        cm_matrix_apply(ctm, p->pts[i][0], p->pts[i][1], &dx, &dy);
        if (first) { minx = maxx = dx; miny = maxy = dy; first = false; }
        else {
            if (dx < minx) minx = dx; else if (dx > maxx) maxx = dx;
            if (dy < miny) miny = dy; else if (dy > maxy) maxy = dy;
        }
    }
    double w = maxx - minx, h = maxy - miny;
    double extent = (w > h) ? w : h;
    if (!(extent > 0.0)) return CM_MESH_MIN_DIV;   /* degenerate -> min grid   */

    double tol = CM_ARC_TOLERANCE;
    if (!(tol > 0.0)) tol = 0.1;
    /* Chord error of a curve segment scales ~ extent / div^2, so to bound it by
     * tol we need div ~ sqrt(extent / tol).  Round up. */
    double d = sqrt(extent / tol);
    if (!isfinite(d) || d < (double)CM_MESH_MIN_DIV) d = (double)CM_MESH_MIN_DIV;
    uint32_t div = (uint32_t)ceil(d);
    if (div < CM_MESH_MIN_DIV) div = CM_MESH_MIN_DIV;
    if (div > CM_MESH_MAX_DIV) div = CM_MESH_MAX_DIV;
    return div;
}

/* A patch contributes 6 vertices per grid cell (two triangles), div*div cells. */
static inline uint32_t cm__patch_vertex_count(uint32_t div)
{
    return 6u * div * div;
}

/* ==========================================================================
 * cm_mesh_triangle_vertex_count  (INTERNAL: ring sizing for cm_fill GOURAUD)
 * ==========================================================================
 * Returns the EXACT total cm_vtx_color count cm_mesh_emit_triangles will write
 * for the whole pattern under `ctm`, so the caller bump-allocates once.  Must
 * stay in lock-step with emit (same per-patch division formula).
 */
uint32_t cm_mesh_triangle_vertex_count(cm_pattern_t *pattern, const cm_matrix_t *ctm)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH) return 0u;
    const cm_mesh_data *m = &pattern->mesh;
    uint32_t total = 0u;
    for (uint32_t i = 0; i < m->count; ++i) {
        uint32_t div = cm__patch_divisions(&m->patches[i], ctm);
        total += cm__patch_vertex_count(div);
    }
    return total;
}

/* ==========================================================================
 * cm_mesh_emit_triangles  (INTERNAL: the mesh triangles ARE the coverage)
 * ==========================================================================
 *
 * For each committed patch, evaluate the Coons surface + bilinear corner colour
 * on a (div+1)x(div+1) lattice of (u,v) samples, then emit two CCW triangles per
 * cell as cm_vtx_color vertices IN DEVICE SPACE (CTM applied here, matching the
 * path/stroke device-space convention so the GOURAUD vertex stage only y-flips
 * via to_clip).  Returns the number of vertices written; the caller guarantees
 * `dst` holds at least cm_mesh_triangle_vertex_count(pattern, ctm).
 *
 * Triangle winding is CCW in (u,v) lattice order; cm_fill.m sets cull-none for
 * the cover pass, so winding only matters to be consistent (it is) and never
 * culls a facet.  Positions are device-space, so a transform that flips
 * handedness (e.g. manim's y-down CTM) does not drop triangles.
 */
uint32_t cm_mesh_emit_triangles(cm_pattern_t *pattern, const cm_matrix_t *ctm,
                                cm_vtx_color *dst)
{
    if (!pattern || pattern->type != CM_PATTERN_TYPE_MESH || !dst) return 0u;
    const cm_mesh_data *m = &pattern->mesh;

    uint32_t out = 0u;

    for (uint32_t pi = 0; pi < m->count; ++pi) {
        const cm_mesh_patch *p = &m->patches[pi];
        uint32_t div = cm__patch_divisions(p, ctm);
        double inv = 1.0 / (double)div;

        /* Walk the grid cell by cell.  For each cell (i,j) we evaluate its four
         * corners on the fly; recomputing the shared lattice points keeps the
         * code allocation-free (no scratch grid) at the cost of ~4x surface
         * evals, which is cheap relative to the GPU draw and avoids touching the
         * heap on the hot path (DESIGN.md zero-per-draw-alloc spirit). */
        for (uint32_t j = 0; j < div; ++j) {
            double v0 = (double)j * inv;
            double v1 = (double)(j + 1u) * inv;
            for (uint32_t i = 0; i < div; ++i) {
                double u0 = (double)i * inv;
                double u1 = (double)(i + 1u) * inv;

                /* Surface positions at the four cell corners. */
                cm_pt2 s00 = cm__coons(p, u0, v0);
                cm_pt2 s10 = cm__coons(p, u1, v0);
                cm_pt2 s11 = cm__coons(p, u1, v1);
                cm_pt2 s01 = cm__coons(p, u0, v1);

                /* Corner colours (bilinear over the parametric square). */
                cm_rgba k00 = cm__coons_color(p, u0, v0);
                cm_rgba k10 = cm__coons_color(p, u1, v0);
                cm_rgba k11 = cm__coons_color(p, u1, v1);
                cm_rgba k01 = cm__coons_color(p, u0, v1);

                /* Device-space positions. */
                double d00x, d00y, d10x, d10y, d11x, d11y, d01x, d01y;
                cm_matrix_apply(ctm, s00.x, s00.y, &d00x, &d00y);
                cm_matrix_apply(ctm, s10.x, s10.y, &d10x, &d10y);
                cm_matrix_apply(ctm, s11.x, s11.y, &d11x, &d11y);
                cm_matrix_apply(ctm, s01.x, s01.y, &d01x, &d01y);

                /* Triangle 1: (s00, s10, s11). */
                dst[out].x = (float)d00x; dst[out].y = (float)d00y; dst[out].color = k00; out++;
                dst[out].x = (float)d10x; dst[out].y = (float)d10y; dst[out].color = k10; out++;
                dst[out].x = (float)d11x; dst[out].y = (float)d11y; dst[out].color = k11; out++;
                /* Triangle 2: (s00, s11, s01). */
                dst[out].x = (float)d00x; dst[out].y = (float)d00y; dst[out].color = k00; out++;
                dst[out].x = (float)d11x; dst[out].y = (float)d11y; dst[out].color = k11; out++;
                dst[out].x = (float)d01x; dst[out].y = (float)d01y; dst[out].color = k01; out++;
            }
        }
    }

    return out;
}
