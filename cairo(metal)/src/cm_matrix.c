/*
 * cm_matrix.c  --  CairoMetal affine-matrix math helpers
 * ============================================================================
 *
 * Implements the small shared math contract declared in cm_internal.h
 * ("Shared math helpers (cm_matrix.c)").  cm_matrix_t is binary-compatible with
 * cairo_matrix_t:
 *
 *     x' = xx * x + xy * y + x0;
 *     y' = yx * x + yy * y + y0;
 *
 * Pure C, no dependencies beyond <math.h>; every other module (path flatten,
 * paint axis transform, stroke width scaling, the public transform glue) calls
 * down into these so the affine semantics live in exactly one place.
 * ============================================================================
 */

#include "cm_internal.h"

#include <math.h>

/* --------------------------------------------------------------------------
 * cm_matrix_identity -- set m to the identity transform.
 * -------------------------------------------------------------------------- */
void cm_matrix_identity(cm_matrix_t *m)
{
    if (!m) return;
    m->xx = 1.0; m->yx = 0.0;
    m->xy = 0.0; m->yy = 1.0;
    m->x0 = 0.0; m->y0 = 0.0;
}

/* --------------------------------------------------------------------------
 * cm_matrix_apply -- transform user-space (x,y) -> (*ox,*oy) by the full
 * affine (rotation/scale/shear in the 2x2 part PLUS the translation).
 * -------------------------------------------------------------------------- */
void cm_matrix_apply(const cm_matrix_t *m, double x, double y,
                     double *ox, double *oy)
{
    if (!m) {
        if (ox) *ox = x;
        if (oy) *oy = y;
        return;
    }
    /* x' = xx*x + xy*y + x0 ; y' = yx*x + yy*y + y0 (cairo convention). */
    if (ox) *ox = m->xx * x + m->xy * y + m->x0;
    if (oy) *oy = m->yx * x + m->yy * y + m->y0;
}

/* --------------------------------------------------------------------------
 * cm_matrix_mul_scale -- POST-multiply m by scale(sx,sy): m = m * scale.
 *
 * This matches cairo_scale()/ctx.scale(): the new scale is applied in the
 * matrix's *current* coordinate system, i.e. it composes on the right.  For an
 * affine M and S = diag(sx,sy) the product M*S scales the basis columns:
 *     (M*S).xx = M.xx*sx   (M*S).xy = M.xy*sy
 *     (M*S).yx = M.yx*sx   (M*S).yy = M.yy*sy
 * Translation (x0,y0) is unchanged because S has no translation component.
 * -------------------------------------------------------------------------- */
void cm_matrix_mul_scale(cm_matrix_t *m, double sx, double sy)
{
    if (!m) return;
    m->xx *= sx;
    m->yx *= sx;
    m->xy *= sy;
    m->yy *= sy;
    /* x0, y0 unchanged: scale has no translation. */
}

/* --------------------------------------------------------------------------
 * cm_matrix_is_invertible -- true iff the 2x2 linear part has a non-vanishing
 * determinant (and is finite).  A non-invertible CTM collapses geometry to a
 * line/point; cairo flags that as CAIRO_STATUS_INVALID_MATRIX, and the path
 * flatten / gradient code rely on this guard.
 * -------------------------------------------------------------------------- */
bool cm_matrix_is_invertible(const cm_matrix_t *m)
{
    if (!m) return false;
    double det = m->xx * m->yy - m->xy * m->yx;
    if (!isfinite(det)) return false;
    /* Reject dets that are exactly zero or denormally tiny: such a CTM is
     * singular for all practical raster purposes. */
    return fabs(det) > 1e-12;
}

/* --------------------------------------------------------------------------
 * cm_matrix_max_scale -- largest singular value of the 2x2 part: the maximum
 * device-pixels-per-user-unit the transform produces in any direction.  Used to
 * (a) convert a USER-space line width to device units for stroke expansion, and
 * (b) reason about flattening/arc segmentation in device space.
 *
 * For a 2x2 matrix A = [[xx, xy],[yx, yy]] the singular values are the square
 * roots of the eigenvalues of A^T A.  With
 *     a = xx, b = xy, c = yx, d = yy
 *     E = a^2 + b^2 + c^2 + d^2            (= trace(A^T A))
 *     F = (xx*yy - xy*yx)^2 = det^2        (= det(A^T A))
 * the larger eigenvalue of A^T A is  (E + sqrt(E^2 - 4F)) / 2, so the maximum
 * singular value is sqrt of that.  This is exact (not an approximation) and
 * reduces to |scale| for a pure scale and to the larger axis scale for an
 * anisotropic scale.
 * -------------------------------------------------------------------------- */
double cm_matrix_max_scale(const cm_matrix_t *m)
{
    if (!m) return 1.0;

    double a = m->xx, b = m->xy, c = m->yx, d = m->yy;
    double E   = a * a + b * b + c * c + d * d;
    double det = a * d - b * c;
    double F   = det * det;

    /* disc = E^2 - 4F = (s1^2 - s2^2)^2 >= 0 mathematically; clamp tiny
     * negative round-off to zero before the sqrt. */
    double disc = E * E - 4.0 * F;
    if (disc < 0.0) disc = 0.0;

    double lambda_max = 0.5 * (E + sqrt(disc));   /* larger eigenvalue of A^T A */
    if (lambda_max <= 0.0) return 0.0;

    double s = sqrt(lambda_max);
    if (!isfinite(s)) return 0.0;
    return s;
}

/* ==========================================================================
 * Full affine algebra
 * --------------------------------------------------------------------------
 * cairo_matrix_t convention (binary-compatible):
 *     x' = xx*x + xy*y + x0 ;  y' = yx*x + yy*y + y0.
 * cairo_matrix_multiply(result,a,b) applies `a` FIRST then `b`; result may
 * alias a/b (we compute into locals).  cm_matrix_*_init build a fresh matrix;
 * cm_matrix_translate/scale/rotate POST-compose a delta in place.
 * ========================================================================== */

void cm_matrix_init(cm_matrix_t *m, double xx, double yx, double xy, double yy,
                    double x0, double y0)
{
    if (!m) return;
    m->xx = xx; m->yx = yx;
    m->xy = xy; m->yy = yy;
    m->x0 = x0; m->y0 = y0;
}

void cm_matrix_init_identity(cm_matrix_t *m)
{
    cm_matrix_identity(m);
}

void cm_matrix_init_translate(cm_matrix_t *m, double tx, double ty)
{
    cm_matrix_init(m, 1.0, 0.0, 0.0, 1.0, tx, ty);
}

void cm_matrix_init_scale(cm_matrix_t *m, double sx, double sy)
{
    cm_matrix_init(m, sx, 0.0, 0.0, sy, 0.0, 0.0);
}

void cm_matrix_init_rotate(cm_matrix_t *m, double radians)
{
    /* cairo: xx=cos, yx=sin, xy=-sin, yy=cos.  +X rotates toward +Y. */
    double c = cos(radians);
    double s = sin(radians);
    cm_matrix_init(m, c, s, -s, c, 0.0, 0.0);
}

/* result = a then b, with x' = M*x.  In cairo's row-vector convention the
 * combined map is (apply a, then b); the explicit element form below is the
 * standard cairo_matrix_multiply.  Computed into locals so result may alias. */
void cm_matrix_multiply(cm_matrix_t *result, const cm_matrix_t *a,
                        const cm_matrix_t *b)
{
    if (!result || !a || !b) return;
    double xx = a->xx * b->xx + a->yx * b->xy;
    double yx = a->xx * b->yx + a->yx * b->yy;
    double xy = a->xy * b->xx + a->yy * b->xy;
    double yy = a->xy * b->yx + a->yy * b->yy;
    double x0 = a->x0 * b->xx + a->y0 * b->xy + b->x0;
    double y0 = a->x0 * b->yx + a->y0 * b->yy + b->y0;
    result->xx = xx; result->yx = yx;
    result->xy = xy; result->yy = yy;
    result->x0 = x0; result->y0 = y0;
}

/* m = m * translate(tx,ty): the translation composes in m's current space. */
void cm_matrix_translate(cm_matrix_t *m, double tx, double ty)
{
    if (!m) return;
    cm_matrix_t t;
    cm_matrix_init_translate(&t, tx, ty);
    cm_matrix_multiply(m, &t, m);
}

void cm_matrix_scale(cm_matrix_t *m, double sx, double sy)
{
    /* Equivalent to cm_matrix_mul_scale but via the general composer. */
    if (!m) return;
    cm_matrix_t s;
    cm_matrix_init_scale(&s, sx, sy);
    cm_matrix_multiply(m, &s, m);
}

void cm_matrix_rotate(cm_matrix_t *m, double radians)
{
    if (!m) return;
    cm_matrix_t r;
    cm_matrix_init_rotate(&r, radians);
    cm_matrix_multiply(m, &r, m);
}

cm_status_t cm_matrix_invert(cm_matrix_t *m)
{
    if (!m) return CM_STATUS_INVALID_MATRIX;
    if (!cm_matrix_is_invertible(m)) return CM_STATUS_INVALID_MATRIX;

    double det = m->xx * m->yy - m->yx * m->xy;
    double inv_det = 1.0 / det;

    double xx =  m->yy * inv_det;
    double yx = -m->yx * inv_det;
    double xy = -m->xy * inv_det;
    double yy =  m->xx * inv_det;
    /* New translation: -(inv_linear) * (x0,y0). */
    double x0 = -(xx * m->x0 + xy * m->y0);
    double y0 = -(yx * m->x0 + yy * m->y0);

    m->xx = xx; m->yx = yx;
    m->xy = xy; m->yy = yy;
    m->x0 = x0; m->y0 = y0;
    return CM_STATUS_SUCCESS;
}

void cm_matrix_transform_point(const cm_matrix_t *m, double *x, double *y)
{
    if (!m || !x || !y) return;
    double ox, oy;
    cm_matrix_apply(m, *x, *y, &ox, &oy);
    *x = ox; *y = oy;
}

void cm_matrix_transform_distance(const cm_matrix_t *m, double *dx, double *dy)
{
    if (!m || !dx || !dy) return;
    /* Drop the translation: distances are unaffected by x0,y0. */
    double ox = m->xx * (*dx) + m->xy * (*dy);
    double oy = m->yx * (*dx) + m->yy * (*dy);
    *dx = ox; *dy = oy;
}

void cm_matrix_transform_bbox(const cm_matrix_t *m,
                              double x1, double y1, double x2, double y2,
                              double *ox1, double *oy1, double *ox2, double *oy2)
{
    if (!m) {
        if (ox1) *ox1 = x1; if (oy1) *oy1 = y1;
        if (ox2) *ox2 = x2; if (oy2) *oy2 = y2;
        return;
    }
    double cx[4] = { x1, x2, x1, x2 };
    double cy[4] = { y1, y1, y2, y2 };
    double lo_x = 0, lo_y = 0, hi_x = 0, hi_y = 0;
    for (int i = 0; i < 4; ++i) {
        double tx, ty;
        cm_matrix_apply(m, cx[i], cy[i], &tx, &ty);
        if (i == 0) { lo_x = hi_x = tx; lo_y = hi_y = ty; }
        else {
            if (tx < lo_x) lo_x = tx; if (tx > hi_x) hi_x = tx;
            if (ty < lo_y) lo_y = ty; if (ty > hi_y) hi_y = ty;
        }
    }
    if (ox1) *ox1 = lo_x; if (oy1) *oy1 = lo_y;
    if (ox2) *ox2 = hi_x; if (oy2) *oy2 = hi_y;
}
