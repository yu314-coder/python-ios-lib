/*
 * cm_pattern.c  --  CairoMetal universal pattern base (pure C)
 * ============================================================================
 *
 * The single home for the widened cm_pattern lifecycle + CPU-side queries,
 * leaving cm_paint.m responsible ONLY for the GPU gradient-LUT bake + uniform
 * packing (the .c-vs-.m discipline: nothing in this file touches Metal / ObjC).
 *
 * Owns:
 *   - create / reference / destroy with a REAL reference count
 *     (cm_pattern_destroy is a refcount DECREMENT; the payload is torn down only
 *     on the last release) for solid / surface / linear / radial / mesh / raster;
 *   - the base accessors: get_type / status / set+get_extend / set+get_filter /
 *     set+get_matrix, with cairo's DEFAULT extend per type (PAD for gradients,
 *     NONE for surfaces);
 *   - colour-stop add_rgb / add_rgba / get_color_stop_count / get_color_stop_rgba.
 *     Stops preserve INSERTION ORDER and RAW values (no sort, no clamp) because
 *     the LUT bake in cm_paint.m sorts + clamps a COPY.  The contract's fixed
 *     stops[CM_MAX_STOPS] inline array cannot grow (its layout is frozen and the
 *     bake reads it directly), so for cairo-correctness past 32 stops the
 *     overflow is kept in a pattern-keyed side table (same idiom cm_paint.m uses
 *     for the per-pattern LUT cache, because struct cm_pattern must not change).
 *     stop_count counts ALL stops; the bake still consumes the first
 *     CM_MAX_STOPS, which is a correct truncation (the LUT is 256-wide and >32
 *     stops is vanishingly rare), while the CPU query API reports every stop;
 *   - solid get_rgba; linear get_points; radial get_circles;
 *   - surface retain + get_surface + set_source_surface (matrix = translate
 *     (-x,-y));
 *   - cm_get_source (returns a retained pattern, or synthesizes a SolidPattern
 *     from the current solid colour) and cm_set_source (accepts ANY pattern
 *     type); cm_pattern_surface_texture() (INTERNAL, for cm_compose / cm_fill).
 *
 * The cm_linear_gradient_create + cm_pattern_add_color_stop_rgba + cm_set_source
 * bodies were MOVED here out of cairo_metal.m so each public symbol is defined
 * exactly once.
 *
 * SURFACE OWNERSHIP NOTE: there is no surface reference count in the shared
 * surface API (cm_surface_t has only cm_surface_destroy, which fully frees), and
 * cm_pattern_destroy must free a surface pattern's surface because cm_group_pop
 * TRANSFERS a freshly-allocated offscreen surface into the pattern and relies on
 * that.  To make this consistent and multi-pattern-safe without growing the
 * struct or editing other modules, a surface pattern OWNS one reference to its
 * surface tracked in a pattern-side surface-refcount side table here: create
 * retains, destroy releases, and the last release calls cm_surface_destroy().
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* ==========================================================================
 * Surface lifetime
 * --------------------------------------------------------------------------
 * A surface pattern keeps its source surface alive for the pattern's lifetime via
 * the surface's OWN reference count (cm_surface_reference / cm_surface_destroy in
 * cm_surface.m), so the surface survives while EITHER its creating owner or any
 * wrapping pattern holds a reference -- the cairo model.  This replaced an earlier
 * pointer-keyed side table that unconditionally freed the surface on the last
 * PATTERN reference, which destroyed a still-user-owned surface when a temporary
 * SurfacePattern wrapping it was released (the BUG-5 A8-mask-reuse crash).  See
 * cm_pattern_create_for_surface + cm_pattern_destroy below.
 * ========================================================================== */

/* ==========================================================================
 * Grown colour-stop overflow (stops past the inline CM_MAX_STOPS array)
 * --------------------------------------------------------------------------
 * struct cm_pattern carries a fixed stops[CM_MAX_STOPS] inline array whose
 * layout is frozen (cm_paint.m's LUT bake reads it directly).  Stops 0..31 stay
 * there so the common case is zero-overhead and the bake is unchanged.  For
 * cairo-correctness, stops at index >= CM_MAX_STOPS are appended to a growable
 * side array keyed by the pattern pointer; stop_count counts ALL stops.  Both
 * preserve insertion order and raw (un-clamped) values.
 *
 * The query API (count / get_color_stop_rgba) reads inline for index <
 * CM_MAX_STOPS and the side array for index >= CM_MAX_STOPS, so callers see the
 * full, cairo-correct stop list.  The overflow is freed in cm_pattern_destroy.
 * ========================================================================== */

#define CM_STOP_OVERFLOW_CAP 64

typedef struct {
    const cm_pattern_t *pat;     /* key; NULL == empty slot                    */
    cm_grad_stop       *stops;   /* malloc'd overflow stops (index >= 32)      */
    uint32_t            count;   /* number of overflow stops stored            */
    uint32_t            cap;     /* capacity of the overflow array             */
} cm_stop_overflow;

static cm_stop_overflow g_stop_overflow[CM_STOP_OVERFLOW_CAP];
static pthread_mutex_t  g_stop_overflow_mtx = PTHREAD_MUTEX_INITIALIZER;

/* Append one overflow stop for `pat` (index >= CM_MAX_STOPS).  Returns true on
 * success; false if the side table is full or allocation fails. */
static bool cm_stop_overflow_append(const cm_pattern_t *pat, const cm_grad_stop *s)
{
    bool ok = false;
    pthread_mutex_lock(&g_stop_overflow_mtx);

    cm_stop_overflow *slot = NULL;
    cm_stop_overflow *free_slot = NULL;
    for (int i = 0; i < CM_STOP_OVERFLOW_CAP; ++i) {
        if (g_stop_overflow[i].pat == pat) { slot = &g_stop_overflow[i]; break; }
        if (!free_slot && g_stop_overflow[i].pat == NULL) free_slot = &g_stop_overflow[i];
    }
    if (!slot) {
        if (!free_slot) goto out;       /* table full: drop (bounds memory)     */
        slot = free_slot;
        slot->pat   = pat;
        slot->stops = NULL;
        slot->count = 0;
        slot->cap   = 0;
    }
    if (slot->count == slot->cap) {
        uint32_t ncap = slot->cap ? slot->cap * 2u : 16u;
        cm_grad_stop *ns = (cm_grad_stop *)realloc(slot->stops, ncap * sizeof(*ns));
        if (!ns) {
            /* Leave the slot intact (its existing stops are still valid). */
            if (slot->count == 0) { slot->pat = NULL; }   /* release a fresh slot */
            goto out;
        }
        slot->stops = ns;
        slot->cap   = ncap;
    }
    slot->stops[slot->count++] = *s;
    ok = true;

out:
    pthread_mutex_unlock(&g_stop_overflow_mtx);
    return ok;
}

/* Read overflow stop `ovf_index` (0-based into the overflow array, i.e.
 * absolute_index - CM_MAX_STOPS) for `pat` into *out.  Returns true if present. */
static bool cm_stop_overflow_get(const cm_pattern_t *pat, uint32_t ovf_index,
                                 cm_grad_stop *out)
{
    bool ok = false;
    pthread_mutex_lock(&g_stop_overflow_mtx);
    for (int i = 0; i < CM_STOP_OVERFLOW_CAP; ++i) {
        if (g_stop_overflow[i].pat == pat) {
            if (ovf_index < g_stop_overflow[i].count) {
                if (out) *out = g_stop_overflow[i].stops[ovf_index];
                ok = true;
            }
            break;
        }
    }
    pthread_mutex_unlock(&g_stop_overflow_mtx);
    return ok;
}

/* Free any overflow stops held for `pat` (called from cm_pattern_destroy). */
static void cm_stop_overflow_free(const cm_pattern_t *pat)
{
    pthread_mutex_lock(&g_stop_overflow_mtx);
    for (int i = 0; i < CM_STOP_OVERFLOW_CAP; ++i) {
        if (g_stop_overflow[i].pat == pat) {
            free(g_stop_overflow[i].stops);
            g_stop_overflow[i].stops = NULL;
            g_stop_overflow[i].pat   = NULL;
            g_stop_overflow[i].count = 0;
            g_stop_overflow[i].cap   = 0;
            break;
        }
    }
    pthread_mutex_unlock(&g_stop_overflow_mtx);
}

/* ==========================================================================
 * Allocation + default initialisation
 * ========================================================================== */

static cm_pattern_t *cm_pattern_alloc(cm_pattern_type_t type, cm_paint_kind kind)
{
    cm_pattern_t *p = (cm_pattern_t *)calloc(1, sizeof(*p));
    if (!p) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }
    p->type     = type;
    p->kind     = kind;
    p->refcount = 1;                       /* create returns one reference       */
    p->status   = CM_STATUS_SUCCESS;
    cm_matrix_identity(&p->matrix);
    p->filter   = CM_FILTER_GOOD;          /* cairo default filter               */
    /* cairo DEFAULT extend differs by type: PAD for gradients (linear/radial),
     * NONE for surface patterns (and the rest). */
    p->extend   = (type == CM_PATTERN_TYPE_LINEAR ||
                   type == CM_PATTERN_TYPE_RADIAL) ? CM_EXTEND_PAD : CM_EXTEND_NONE;
    cm_set_last_status(CM_STATUS_SUCCESS);
    return p;
}

/* ==========================================================================
 * Lifecycle  (REAL refcount; cm_pattern_destroy == refcount decrement)
 * ========================================================================== */
cm_pattern_t *cm_pattern_reference(cm_pattern_t *pattern)
{
    if (pattern) pattern->refcount++;
    return pattern;
}

void cm_pattern_destroy(cm_pattern_t *pattern)
{
    if (!pattern) return;
    if (pattern->refcount > 0 && --pattern->refcount > 0)
        return;                            /* still referenced: keep the payload */

    /* Last reference dropped: tear the payload down. */

    /* Surface pattern: drop our reference on the source surface (the surface's own
     * refcount frees it on the last reference -- see cm_pattern_create_for_surface). */
    if (pattern->type == CM_PATTERN_TYPE_SURFACE && pattern->surf.surface) {
        cm_surface_destroy(pattern->surf.surface);
        pattern->surf.surface = NULL;
    }

    /* Gradient: drop any grown (>32) colour-stop overflow. */
    if (pattern->type == CM_PATTERN_TYPE_LINEAR ||
        pattern->type == CM_PATTERN_TYPE_RADIAL) {
        if (pattern->stop_count > CM_MAX_STOPS)
            cm_stop_overflow_free(pattern);
    }

    /* Mesh: free the patch array owned by cm_mesh.c's builder. */
    if (pattern->mesh.patches) {
        free(pattern->mesh.patches);
        pattern->mesh.patches = NULL;
    }

    free(pattern);
}

cm_pattern_type_t cm_pattern_get_type(cm_pattern_t *pattern)
{
    return pattern ? pattern->type : CM_PATTERN_TYPE_SOLID;
}

cm_status_t cm_pattern_status(cm_pattern_t *pattern)
{
    return pattern ? pattern->status : CM_STATUS_NO_MEMORY;
}

/* ==========================================================================
 * Base accessors  (extend / filter / matrix)
 * ========================================================================== */
void cm_pattern_set_extend(cm_pattern_t *pattern, cm_extend_t extend)
{
    if (pattern) pattern->extend = extend;
}
cm_extend_t cm_pattern_get_extend(cm_pattern_t *pattern)
{
    return pattern ? pattern->extend : CM_EXTEND_NONE;
}
void cm_pattern_set_filter(cm_pattern_t *pattern, cm_filter_t filter)
{
    if (pattern) pattern->filter = filter;
}
cm_filter_t cm_pattern_get_filter(cm_pattern_t *pattern)
{
    return pattern ? pattern->filter : CM_FILTER_GOOD;
}
void cm_pattern_set_matrix(cm_pattern_t *pattern, const cm_matrix_t *matrix)
{
    if (pattern && matrix) pattern->matrix = *matrix;
}
void cm_pattern_get_matrix(cm_pattern_t *pattern, cm_matrix_t *matrix)
{
    if (!matrix) return;
    if (pattern) *matrix = pattern->matrix; else cm_matrix_identity(matrix);
}

/* ==========================================================================
 * Solid pattern
 * ========================================================================== */
cm_pattern_t *cm_solid_pattern_create_rgba(double r, double g, double b, double a)
{
    cm_pattern_t *p = cm_pattern_alloc(CM_PATTERN_TYPE_SOLID, CM_PAINT_SOLID);
    if (!p) return NULL;
    /* PIXEL CONTRACT (see cairo_metal.h): components are passed through
     * unchanged (manim already hands us B,G,R,A); the GPU premultiplies later. */
    p->solid.r = (float)r; p->solid.g = (float)g;
    p->solid.b = (float)b; p->solid.a = (float)a;
    return p;
}

cm_status_t cm_solid_pattern_get_rgba(cm_pattern_t *pattern,
                                      double *r, double *g, double *b, double *a)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_SOLID) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (r) *r = pattern->solid.r;
    if (g) *g = pattern->solid.g;
    if (b) *b = pattern->solid.b;
    if (a) *a = pattern->solid.a;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Gradient stops (insertion order + RAW values preserved; the bake clamps a copy)
 * ========================================================================== */
void cm_pattern_add_color_stop_rgba(cm_pattern_t *pattern, double offset,
                                    double r, double g, double b, double a)
{
    if (!pattern) return;

    /* Store the RAW offset + colour (NO clamp / NO sort here): the LUT bake in
     * cm_paint.m sorts + clamps a COPY, and the CPU query API must report what
     * the caller added, in insertion order. */
    cm_grad_stop s;
    s.offset  = offset;
    s.color.r = (float)r;
    s.color.g = (float)g;
    s.color.b = (float)b;
    s.color.a = (float)a;

    if (pattern->stop_count < CM_MAX_STOPS) {
        /* Common case: fits in the frozen inline array the bake reads directly. */
        pattern->stops[pattern->stop_count++] = s;
        return;
    }
    /* Past 32 stops: keep going in the pattern-keyed overflow side table so the
     * stop list stays cairo-correct (count + raw values + order).  The bake
     * still consumes the first CM_MAX_STOPS, a correct truncation. */
    if (cm_stop_overflow_append(pattern, &s)) {
        pattern->stop_count++;
    } else if (pattern->status == CM_STATUS_SUCCESS) {
        pattern->status = CM_STATUS_NO_MEMORY;   /* could not grow the overflow */
    }
}

void cm_pattern_add_color_stop_rgb(cm_pattern_t *pattern, double offset,
                                   double r, double g, double b)
{
    /* cairo's _rgb variant is _rgba with alpha = 1.0. */
    cm_pattern_add_color_stop_rgba(pattern, offset, r, g, b, 1.0);
}

cm_status_t cm_pattern_get_color_stop_count(cm_pattern_t *pattern, int *count)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_LINEAR &&
        pattern->type != CM_PATTERN_TYPE_RADIAL)
        return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (count) *count = (int)pattern->stop_count;   /* ALL stops, incl. overflow */
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_pattern_get_color_stop_rgba(cm_pattern_t *pattern, int index,
                                           double *offset, double *r,
                                           double *g, double *b, double *a)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_LINEAR &&
        pattern->type != CM_PATTERN_TYPE_RADIAL)
        return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (index < 0 || index >= (int)pattern->stop_count)
        return CM_STATUS_INVALID_INDEX;

    cm_grad_stop s;
    if (index < (int)CM_MAX_STOPS) {
        s = pattern->stops[index];                   /* inline (insertion order) */
    } else if (!cm_stop_overflow_get(pattern,
                                     (uint32_t)index - CM_MAX_STOPS, &s)) {
        /* stop_count claims this index but the overflow entry is missing (e.g.
         * the side table was full when it was added): report it as out-of-range
         * rather than returning garbage. */
        return CM_STATUS_INVALID_INDEX;
    }

    if (offset) *offset = s.offset;
    if (r) *r = s.color.r;
    if (g) *g = s.color.g;
    if (b) *b = s.color.b;
    if (a) *a = s.color.a;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Linear gradient  (KEEP cm_linear_gradient_create; body MOVED here)
 * ========================================================================== */
cm_pattern_t *cm_linear_gradient_create(double x0, double y0, double x1, double y1)
{
    cm_pattern_t *p = cm_pattern_alloc(CM_PATTERN_TYPE_LINEAR, CM_PAINT_LINEAR);
    if (!p) return NULL;
    p->x0 = x0; p->y0 = y0; p->x1 = x1; p->y1 = y1;
    return p;
}

cm_status_t cm_linear_gradient_get_points(cm_pattern_t *pattern,
                                          double *x0, double *y0,
                                          double *x1, double *y1)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_LINEAR) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (x0) *x0 = pattern->x0;
    if (y0) *y0 = pattern->y0;
    if (x1) *x1 = pattern->x1;
    if (y1) *y1 = pattern->y1;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Radial gradient
 * ========================================================================== */
cm_pattern_t *cm_radial_gradient_create(double cx0, double cy0, double r0,
                                        double cx1, double cy1, double r1)
{
    cm_pattern_t *p = cm_pattern_alloc(CM_PATTERN_TYPE_RADIAL, CM_PAINT_RADIAL);
    if (!p) return NULL;
    p->radial.cx0 = cx0; p->radial.cy0 = cy0; p->radial.r0 = r0;
    p->radial.cx1 = cx1; p->radial.cy1 = cy1; p->radial.r1 = r1;
    return p;
}

cm_status_t cm_radial_gradient_get_circles(cm_pattern_t *pattern,
                                           double *cx0, double *cy0, double *r0,
                                           double *cx1, double *cy1, double *r1)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_RADIAL) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    if (cx0) *cx0 = pattern->radial.cx0;
    if (cy0) *cy0 = pattern->radial.cy0;
    if (r0)  *r0  = pattern->radial.r0;
    if (cx1) *cx1 = pattern->radial.cx1;
    if (cy1) *cy1 = pattern->radial.cy1;
    if (r1)  *r1  = pattern->radial.r1;
    return CM_STATUS_SUCCESS;
}

/* ==========================================================================
 * Surface pattern  (retains the source surface; see the header note above)
 * ========================================================================== */
cm_pattern_t *cm_pattern_create_for_surface(cm_surface_t *surface)
{
    cm_pattern_t *p = cm_pattern_alloc(CM_PATTERN_TYPE_SURFACE, CM_PAINT_SURFACE);
    if (!p) return NULL;
    /* Take ONE lifetime reference on the surface for the pattern's lifetime via the
     * surface's own refcount (cm_surface_reference); cm_pattern_destroy drops it
     * with cm_surface_destroy, which frees the surface only on its LAST reference.
     * This is the cairo model: a surface stays alive while EITHER its creating
     * owner (e.g. a user's ImageSurface wrapper) OR any wrapping SurfacePattern
     * holds a reference -- so a temporary pattern that wraps a still-owned surface
     * and is then destroyed does NOT free the surface out from under its owner
     * (the BUG-5 A8-mask-reuse crash).  A group-pop surface, whose creating
     * reference is handed to the pattern (cm_group_pop drops its own), is freed
     * when that sole pattern is destroyed.  cairo surface patterns default to
     * EXTEND_NONE (already set by cm_pattern_alloc). */
    p->surf.surface = surface ? cm_surface_reference(surface) : NULL;
    return p;
}

cm_status_t cm_surface_pattern_get_surface(cm_pattern_t *pattern,
                                           cm_surface_t **out_surface)
{
    if (!pattern) return CM_STATUS_NO_MEMORY;
    if (pattern->type != CM_PATTERN_TYPE_SURFACE) return CM_STATUS_PATTERN_TYPE_MISMATCH;
    /* cairo_pattern_get_surface returns a BORROWED reference (the pattern keeps
     * ownership); we hand back the same pointer without bumping the count. */
    if (out_surface) *out_surface = pattern->surf.surface;
    return CM_STATUS_SUCCESS;
}

/* INTERNAL (cm_internal.h): the retained source surface backing a SURFACE
 * pattern, for the cover-surface path in cm_compose / cm_fill.  NULL for every
 * other pattern type. */
cm_surface_t *cm_pattern_surface_texture(cm_pattern_t *pattern)
{
    if (!pattern) return NULL;
    if (pattern->type == CM_PATTERN_TYPE_SURFACE) return pattern->surf.surface;
    return NULL;
}

/* ==========================================================================
 * Source install / read  (cm_set_source body MOVED here; accepts ANY type)
 * ========================================================================== */
void cm_set_source(cm_context_t *ctx, cm_pattern_t *pattern)
{
    if (!ctx) return;
    if (!pattern) {
        /* cairo_set_source(cr, NULL) is an error and leaves the source
         * unchanged (CAIRO_STATUS_NULL_POINTER); we have no NULL_POINTER code,
         * so flag the nearest sticky error and keep the current source. */
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = CM_STATUS_INVALID_FORMAT;
        return;
    }

    /* Retain the new source BEFORE releasing the old, so set_source(cr, cur)
     * (re-installing the current source) cannot transiently free it. */
    cm_pattern_reference(pattern);
    if (ctx->source.kind != CM_PAINT_SOLID && ctx->source.pattern)
        cm_pattern_destroy(ctx->source.pattern);

    /* Derive the paint kind from the pattern type so the encode path (cm_fill /
     * cm_compose / cm_paint.m) selects the right cover pipeline. */
    ctx->source.kind    = pattern->kind;
    ctx->source.pattern = pattern;
}

void cm_set_source_surface(cm_context_t *ctx, cm_surface_t *surface,
                           double x, double y)
{
    if (!ctx) return;
    cm_pattern_t *p = cm_pattern_create_for_surface(surface);
    if (!p) {
        if (ctx->status == CM_STATUS_SUCCESS) ctx->status = cm_last_status();
        return;
    }
    /* cairo: set_source_surface installs the surface with pattern matrix
     * translate(-x,-y) so the surface's origin lands at user-space (x,y). */
    cm_matrix_init_translate(&p->matrix, -x, -y);
    cm_set_source(ctx, p);
    cm_pattern_destroy(p);   /* cm_set_source took its own reference            */
}

cm_pattern_t *cm_get_source(cm_context_t *ctx)
{
    if (!ctx) return NULL;
    /* Non-solid source: hand back a NEW reference the caller must destroy. */
    if (ctx->source.kind != CM_PAINT_SOLID && ctx->source.pattern)
        return cm_pattern_reference(ctx->source.pattern);
    /* Solid source: synthesize a SolidPattern for the current colour (cairo
     * returns a SolidPattern from cairo_get_source after set_source_rgba). */
    return cm_solid_pattern_create_rgba(ctx->source.solid.r, ctx->source.solid.g,
                                        ctx->source.solid.b, ctx->source.solid.a);
}
