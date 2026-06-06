/*
 * cm_ft.c  --  CairoMetal optional FreeType outline source (guarded)
 * ============================================================================
 *
 * Compiled into every build, but the FreeType-dependent body is wrapped in
 * #if CM_ENABLE_FREETYPE so a no-FreeType build still links (the file is a
 * valid, non-empty translation unit either way).  When enabled, it wraps an
 * external FT_Face as a cm_font_face_t of type FT and emits outlines via
 * FT_Load_Glyph(NO_SCALE|NO_HINTING) + FT_Outline_Decompose into the SAME
 * cm_path recorder cm_text.m feeds (conic/quad elevation).  CoreText is the
 * default outline source; FT is the exactness/portability fallback.
 *
 * ----------------------------------------------------------------------------
 * COORDINATE / SCALE CONTRACT  (matches cm_text.m's CoreText source exactly)
 * ----------------------------------------------------------------------------
 * The internal sink contract (cm_internal.h, cm_text_append_glyph_outline) is
 * "append one glyph's outline in USER space, cairo down-y, into `path`".  Like
 * CoreText's CTFontCreatePathForGlyph -- which yields a path already scaled to
 * the font's nominal EM box and in y-up -- the cm_ft_* emitters produce an
 * EM-NORMALIZED outline: glyph font units are divided by units_per_EM so the
 * design EM maps to 1.0, independent of any point size.  The caller (the font
 * dispatch in cm_text.m / cairo_metal.m) then applies the font matrix + CTM, so
 * the FT and CoreText sources are interchangeable behind the same sink.
 *
 * FreeType outlines are y-UP (design space); cairo user space is y-DOWN, so the
 * y coordinate is negated as part of the same normalize step (matching the
 * up-y -> down-y flip cm_text.m does for CoreText).  The pen origin (x,y) is
 * added AFTER normalization, in the same EM-normalized user space.
 *
 * Metrics (cm_ft_glyph_extents / cm_ft_font_extents) are reported in the SAME
 * EM-normalized space (font units / units_per_EM), so glyph/font extents line
 * up with the emitted outline and with cairo's font-space metric convention
 * (caller scales by the font matrix).  Advances come from FT_Get_Advance with
 * FT_LOAD_NO_SCALE (font units) divided by units_per_EM.
 *
 * The public lock/unlock face accessors are ALWAYS defined here (they return
 * the stored FT_Face or NULL), so the public symbol exists regardless of the
 * guard.  The create-for-ft-face constructor lives in cm_font.c (it needs no
 * FreeType headers -- it only stores the void* FT_Face).
 *
 * ASCII-clean (project rule).  Pure C; touches no Metal / Objective-C.
 * ============================================================================
 */

#include "cm_internal.h"

/* INTERNAL accessor implemented in cm_font.c: returns the stored FT_Face (as
 * void*) for a font face and, optionally, its load flags. */
extern void *cm_font_face_ft_face(cm_font_face_t *face, int *out_load_flags);

/* Forward to the stored FT_Face for the scaled font's face (or NULL).
 *
 * cairo_ft_scaled_font_lock_face() conceptually takes the global FT mutex and
 * sizes the FT_Face to the scaled font before returning it.  Here the FT_Face
 * is caller-supplied and caller-owned (cm_ft_font_face_create_for_ft_face only
 * stores the pointer), the cm_* contract is single-threaded per context (see
 * cairo_metal.h "THREADING / OWNERSHIP"), and FreeType holds no library handle
 * on our side -- so locking degenerates to handing back the stored FT_Face and
 * unlocking is a no-op.  Defined unconditionally so the symbol exists in a
 * no-FreeType build too. */
void *cm_ft_scaled_font_lock_face(cm_scaled_font_t *scaled_font)
{
    cm_font_face_t *face = scaled_font ? cm_scaled_font_get_font_face(scaled_font) : NULL;
    if (!face) return NULL;
    return cm_font_face_ft_face(face, NULL);
}

void cm_ft_scaled_font_unlock_face(cm_scaled_font_t *scaled_font)
{
    (void)scaled_font;   /* no lock held: caller owns the FT_Face (see above)   */
}

#if CM_ENABLE_FREETYPE

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_ADVANCES_H

/* The exactness/portability load mode: raw integer font-unit outlines with no
 * grid-fitting, so the emitted curves are size-independent and unhinted (the
 * GPU MSAA path is the AA, not the FT hinter).  NO_BITMAP keeps bitmap strikes
 * from satisfying a scalable-glyph request. */
#define CM_FT_LOAD_FLAGS  (FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)

/* ==========================================================================
 * Decompose walker -> cm_path recorder
 * --------------------------------------------------------------------------
 * FT_Outline_Decompose invokes these per outline segment.  Coordinates arrive
 * in the glyph's font units (NO_SCALE), y-up.  We normalize to the EM box
 * (divide by units_per_EM), flip y (up -> down for cairo user space), add the
 * pen origin, elevate conics to cubics, and feed the SAME recorder cm_text.m
 * uses (cm_path_move_to / line_to / curve_to / close).  Returning non-zero from
 * any callback aborts the decompose; we always return 0 (cm_path recording is
 * void / cannot fail mid-segment -- on OOM it simply drops the edit and the
 * subsequent flatten reports NO_MEMORY).
 * ========================================================================== */

typedef struct {
    cm_path *path;        /* sink (the context's current path)                 */
    double   scale;       /* 1.0 / units_per_EM  (EM-normalize)                */
    double   ox, oy;      /* pen origin in EM-normalized user space            */
    double   cx, cy;      /* current point in EM-normalized user space         */
    bool     open;        /* a contour is currently open (needs a close)       */
} cm_ft_walk;

/* Map a font-unit FT_Vector to EM-normalized, y-flipped, pen-translated user
 * space. */
static inline void cm_ft__map(const cm_ft_walk *w, const FT_Vector *v,
                              double *ox, double *oy)
{
    *ox = w->ox + (double)v->x * w->scale;
    *oy = w->oy - (double)v->y * w->scale;   /* y-up (FT) -> y-down (cairo)     */
}

static int cm_ft__move_to(const FT_Vector *to, void *user)
{
    cm_ft_walk *w = (cm_ft_walk *)user;
    /* A move starts a new contour; close the previous one first so each glyph
     * contour is an independent closed sub-path (FT contours are closed loops,
     * matching cm_path_append_contours' "always closed" behaviour). */
    if (w->open) cm_path_close(w->path);
    double x, y;
    cm_ft__map(w, to, &x, &y);
    cm_path_move_to(w->path, x, y);
    w->cx = x; w->cy = y;
    w->open = true;
    return 0;
}

static int cm_ft__line_to(const FT_Vector *to, void *user)
{
    cm_ft_walk *w = (cm_ft_walk *)user;
    double x, y;
    cm_ft__map(w, to, &x, &y);
    cm_path_line_to(w->path, x, y);
    w->cx = x; w->cy = y;
    return 0;
}

/* Quadratic (conic) -> cubic elevation.  Given the current point P0, the conic
 * control C and the end point P1, the equivalent cubic control points are
 *   C1 = P0 + (2/3)(C - P0),  C2 = P1 + (2/3)(C - P1).
 * This is exact (a quadratic is a degenerate cubic), so the emitted curve is
 * geometrically identical to the FT conic -- preserving the "exactness" goal. */
static int cm_ft__conic_to(const FT_Vector *control, const FT_Vector *to, void *user)
{
    cm_ft_walk *w = (cm_ft_walk *)user;
    double ctrlx, ctrly, tox, toy;
    cm_ft__map(w, control, &ctrlx, &ctrly);
    cm_ft__map(w, to, &tox, &toy);

    const double k = 2.0 / 3.0;
    double c1x = w->cx + k * (ctrlx - w->cx);
    double c1y = w->cy + k * (ctrly - w->cy);
    double c2x = tox + k * (ctrlx - tox);
    double c2y = toy + k * (ctrly - toy);

    cm_path_curve_to(w->path, c1x, c1y, c2x, c2y, tox, toy);
    w->cx = tox; w->cy = toy;
    return 0;
}

static int cm_ft__cubic_to(const FT_Vector *control1, const FT_Vector *control2,
                           const FT_Vector *to, void *user)
{
    cm_ft_walk *w = (cm_ft_walk *)user;
    double c1x, c1y, c2x, c2y, tox, toy;
    cm_ft__map(w, control1, &c1x, &c1y);
    cm_ft__map(w, control2, &c2x, &c2y);
    cm_ft__map(w, to, &tox, &toy);
    cm_path_curve_to(w->path, c1x, c1y, c2x, c2y, tox, toy);
    w->cx = tox; w->cy = toy;
    return 0;
}

/* The decompose dispatch table is the same for every glyph; shift/delta = 0 so
 * coordinates pass through unmodified (we do all scaling in the callbacks). */
static const FT_Outline_Funcs cm_ft__outline_funcs = {
    cm_ft__move_to,
    cm_ft__line_to,
    cm_ft__conic_to,
    cm_ft__cubic_to,
    0,    /* shift */
    0     /* delta */
};

/* Resolve the FT_Face + a non-zero units_per_EM for `face`, or return NULL.
 * A bitmap-only / zero-EM face has no usable normalization scale, so it is
 * treated as "no outline" (consistent with the FT scalable-glyph contract). */
static FT_Face cm_ft__face(cm_font_face_t *face, double *out_em_scale)
{
    if (!face) return NULL;
    FT_Face ft = (FT_Face)cm_font_face_ft_face(face, NULL);
    if (!ft) return NULL;
    FT_UShort upem = ft->units_per_EM;
    if (upem == 0) return NULL;     /* unscalable: nothing to normalize against */
    if (out_em_scale) *out_em_scale = 1.0 / (double)upem;
    return ft;
}

/* ==========================================================================
 * Outline emission
 * ========================================================================== */
void cm_ft_append_glyph_outline(cm_font_face_t *face, unsigned long glyph,
                                double x, double y, cm_path *path)
{
    if (!path) return;

    double em_scale;
    FT_Face ft = cm_ft__face(face, &em_scale);
    if (!ft) return;

    if (FT_Load_Glyph(ft, (FT_UInt)glyph, CM_FT_LOAD_FLAGS) != 0)
        return;

    FT_GlyphSlot slot = ft->glyph;
    /* Only outline glyphs decompose; a bitmap strike (despite NO_BITMAP) or an
     * empty glyph (e.g. space) yields nothing to append. */
    if (slot->format != FT_GLYPH_FORMAT_OUTLINE)
        return;
    if (slot->outline.n_points == 0 || slot->outline.n_contours == 0)
        return;

    cm_ft_walk w;
    w.path  = path;
    w.scale = em_scale;
    w.ox    = x;
    w.oy    = y;
    w.cx    = x;
    w.cy    = y;
    w.open  = false;

    if (FT_Outline_Decompose(&slot->outline, &cm_ft__outline_funcs, &w) != 0) {
        /* Partial decompose: still close whatever contour is open so the
         * recorded path is well-formed (no dangling sub-path). */
    }
    if (w.open) cm_path_close(w.path);
}

/* ==========================================================================
 * Metrics  (EM-normalized; caller applies the font matrix)
 * --------------------------------------------------------------------------
 * Matches cm_text_glyph_extents / cm_text_font_extents in shape and space:
 *   - x_bearing / y_bearing follow cairo's convention (y_bearing is the signed
 *     distance from the origin to the TOP of the ink box, negative-up in cairo
 *     user space, i.e. -horiBearingY);
 *   - advances are horizontal (vertical advance 0), from FT_Get_Advance.
 * All quantities are divided by units_per_EM.  For a multi-glyph run we sum the
 * advances and union the per-glyph ink boxes (each box offset by the running
 * pen), exactly as cairo accumulates a glyph string's extents.
 * ========================================================================== */
void cm_ft_glyph_extents(cm_font_face_t *face, const cm_glyph_t *glyphs, int n,
                         cm_text_extents_t *out)
{
    if (!out) return;
    out->x_bearing = out->y_bearing = out->width = out->height =
        out->x_advance = out->y_advance = 0.0;

    double em_scale;
    FT_Face ft = cm_ft__face(face, &em_scale);
    if (!ft || !glyphs || n <= 0) return;

    /* Metrics deliberately use the EM-normalized NO_SCALE load (not the face's
     * stored cairo load flags): the reported box/advance must be size- and
     * hint-independent so they line up with the emitted outline and cairo's
     * font-space metric convention (the caller scales by the font matrix). */
    bool   have_box = false;
    double min_x = 0.0, min_y = 0.0, max_x = 0.0, max_y = 0.0;
    double pen_x = 0.0, pen_y = 0.0;            /* running pen (EM-normalized)    */

    for (int i = 0; i < n; ++i) {
        FT_UInt gi = (FT_UInt)glyphs[i].index;

        /* Advance: prefer the unscaled-design advance from FT_Get_Advance; fall
         * back to the loaded slot's metrics if that fails. */
        double adv = 0.0;
        FT_Fixed fadv = 0;
        if (FT_Get_Advance(ft, gi, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING, &fadv) == 0)
            adv = (double)fadv * em_scale;

        if (FT_Load_Glyph(ft, gi, CM_FT_LOAD_FLAGS) == 0) {
            const FT_Glyph_Metrics *m = &ft->glyph->metrics;
            if (adv == 0.0) adv = (double)m->horiAdvance * em_scale;

            /* Per-glyph ink box in cairo user space (y-down), EM-normalized,
             * offset to the running pen.  cairo: x_bearing = horiBearingX,
             * y_bearing = -horiBearingY (top of ink, negative-up). */
            double gx0 = pen_x + (double)m->horiBearingX * em_scale;
            double gy0 = pen_y - (double)m->horiBearingY * em_scale;
            double gx1 = gx0 + (double)m->width  * em_scale;
            double gy1 = gy0 + (double)m->height * em_scale;

            if (m->width != 0 && m->height != 0) {
                if (!have_box) {
                    min_x = gx0; min_y = gy0; max_x = gx1; max_y = gy1;
                    have_box = true;
                } else {
                    if (gx0 < min_x) min_x = gx0;
                    if (gy0 < min_y) min_y = gy0;
                    if (gx1 > max_x) max_x = gx1;
                    if (gy1 > max_y) max_y = gy1;
                }
            }
        }

        pen_x += adv;   /* advance the pen for the next glyph's box offset       */
    }

    if (have_box) {
        out->x_bearing = min_x;
        out->y_bearing = min_y;
        out->width     = max_x - min_x;
        out->height    = max_y - min_y;
    }
    out->x_advance = pen_x;
    out->y_advance = pen_y;   /* horizontal layout: 0 */
}

void cm_ft_font_extents(cm_font_face_t *face, cm_font_extents_t *out)
{
    if (!out) return;
    out->ascent = out->descent = out->height =
        out->max_x_advance = out->max_y_advance = 0.0;

    double em_scale;
    FT_Face ft = cm_ft__face(face, &em_scale);
    if (!ft) return;

    /* The face's design metrics (font units) -> EM-normalized.  cairo's
     * font_extents are positive-down: ascent is the distance the font rises
     * ABOVE the baseline (FT ascender is positive-up, so it maps to +ascent);
     * descent is the distance BELOW the baseline (FT descender is negative-up,
     * so descent = -descender). */
    out->ascent        =  (double)ft->ascender  * em_scale;
    out->descent       = -(double)ft->descender * em_scale;
    out->height        =  (double)ft->height    * em_scale;
    out->max_x_advance =  (double)ft->max_advance_width * em_scale;
    out->max_y_advance =  0.0;
}

#endif /* CM_ENABLE_FREETYPE */
