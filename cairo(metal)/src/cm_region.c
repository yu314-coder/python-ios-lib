/*
 * cm_region.c  --  CairoMetal cairo_region_t (integer rectangle-set algebra)
 * ============================================================================
 *
 * A refcounted cm_region_t holding a growable, CANONICAL "YX-banded" array of
 * cm_rectangle_int_t.  No Metal, no other-domain dependencies beyond the public
 * header (this is a pure-C translation unit, like cm_matrix.c / cm_query.c).
 *
 * ----------------------------------------------------------------------------
 * CANONICAL FORM (matches cairo/pixman so iteration order is bit-for-bit equal)
 * ----------------------------------------------------------------------------
 * cairo_region_t is backed by pixman_region32, whose rectangle list is kept in
 * a strict canonical "banded" form.  cm_region_t mirrors it exactly so that a
 * caller iterating cm_region_num_rectangles()/cm_region_get_rectangle() sees the
 * SAME rectangles in the SAME order cairo would produce:
 *
 *   1. The list is partitioned into horizontal BANDS.  All rectangles in a band
 *      share the same `y` (top) and the same `height` (so they span the same
 *      half-open vertical range [y, y+height)).
 *   2. Bands appear top-to-bottom (ascending `y`); they never vertically
 *      overlap and never touch-and-merge (see rule 4).
 *   3. Within a band the rectangles are sorted left-to-right (ascending `x`),
 *      are pairwise non-overlapping, and NO two adjacent rectangles abut
 *      (x_i + w_i == x_{i+1}): such a pair is always merged into one wider
 *      rectangle ("horizontal coalesce").
 *   4. Two vertically-adjacent bands (band B starts exactly where band A ends:
 *      A.y + A.height == B.y) whose rectangle x-spans are IDENTICAL (same count,
 *      same x and width for every rectangle, in order) are merged into one
 *      taller band ("vertical coalesce").
 *
 * After EVERY mutating operation the region is re-normalised to this form, so it
 * is an invariant the queries (equal / contains / extents) can rely on:
 *   - cm_region_equal is a plain element-wise array compare (canonical form
 *     makes equal regions byte-identical);
 *   - cm_region_get_extents is the AABB of the (sorted) rectangle list;
 *   - contains_point / contains_rectangle exploit the banding for an exact test.
 *
 * ----------------------------------------------------------------------------
 * SET ALGEBRA (union / intersect / subtract / xor, in place)
 * ----------------------------------------------------------------------------
 * The boolean ops use the classic SCANLINE band-decomposition that pixman uses:
 * the union of the two operands' horizontal edges (distinct y values) cuts the
 * plane into strips of uniform height; in each strip each operand contributes a
 * sorted set of non-overlapping X-intervals; the 1-D interval operation
 * (union/intersect/subtract) is applied to those two interval sets to yield the
 * strip's rectangles; strips are emitted top-to-bottom (already YX-sorted) and
 * then run through the same normaliser, which performs the vertical coalesce.
 * Because the per-strip interval ops already produce horizontally-coalesced,
 * sorted, non-overlapping intervals, the result is canonical.
 *
 *   xor(a,b) = union(subtract(a,b), subtract(b,a))           (cairo's identity)
 *
 * Every op mutates `dst` in place and re-coalesces; the `_rectangle` variants
 * are the same op against a temporary one-rectangle region.
 *
 * All public symbols here are declared in include/cairo_metal.h; the empty
 * region is the well-defined "0 rectangles" state, and a freshly created region
 * has status CM_STATUS_SUCCESS (CM_STATUS_NO_MEMORY is reported on allocation
 * failure via the region's sticky status + cm_set_last_status for creators).
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <limits.h>

/* ==========================================================================
 * The region object
 * --------------------------------------------------------------------------
 * `rects` is the canonical YX-banded rectangle array (see the file banner).
 * `count`/`cap` are the live length / allocated capacity.  `status` is sticky:
 * once it goes non-SUCCESS (only NO_MEMORY is possible here) it stays, matching
 * cairo's "a region in an error state stays in that state".
 * ========================================================================== */
struct cm_region {
    int                 refcount;
    cm_rectangle_int_t *rects;
    int                 count, cap;
    cm_status_t         status;
};

/* ==========================================================================
 * Rectangle scalar helpers
 * ========================================================================== */

/* A rectangle is empty (contributes nothing to a region) iff it has no area. */
static int cm_rect_empty(const cm_rectangle_int_t *r)
{
    return r->width <= 0 || r->height <= 0;
}

static int cm_imin(int a, int b) { return a < b ? a : b; }
static int cm_imax(int a, int b) { return a > b ? a : b; }

/* True iff point (x,y) is inside the half-open rect [x,x+w) x [y,y+h). */
static int cm_rect_contains_point(const cm_rectangle_int_t *r, int x, int y)
{
    return x >= r->x && x < r->x + r->width &&
           y >= r->y && y < r->y + r->height;
}

/* Intersection of two rects -> out; returns 0 (and leaves out untouched) if the
 * overlap is empty.  Uses the half-open [lo,hi) convention throughout. */
static int cm_rect_intersect(const cm_rectangle_int_t *a,
                             const cm_rectangle_int_t *b,
                             cm_rectangle_int_t *out)
{
    int x1 = cm_imax(a->x, b->x);
    int y1 = cm_imax(a->y, b->y);
    int x2 = cm_imin(a->x + a->width,  b->x + b->width);
    int y2 = cm_imin(a->y + a->height, b->y + b->height);
    if (x2 <= x1 || y2 <= y1) return 0;
    out->x = x1; out->y = y1; out->width = x2 - x1; out->height = y2 - y1;
    return 1;
}

/* ==========================================================================
 * Growable rectangle array (amortised O(1) append, like the cm_path arrays)
 * ========================================================================== */

static int cm_region_reserve(cm_region_t *r, int need)
{
    if (need <= r->cap) return 1;
    int cap = r->cap ? r->cap : 8;
    while (cap < need) cap *= 2;
    cm_rectangle_int_t *nr = (cm_rectangle_int_t *)realloc(
        r->rects, (size_t)cap * sizeof(cm_rectangle_int_t));
    if (!nr) { r->status = CM_STATUS_NO_MEMORY; return 0; }
    r->rects = nr;
    r->cap   = cap;
    return 1;
}

/* Append one (assumed already-canonical-position) rectangle.  Empty rects are
 * silently dropped (they are not part of the set). */
static int cm_region_append(cm_region_t *r, const cm_rectangle_int_t *rect)
{
    if (cm_rect_empty(rect)) return 1;
    if (!cm_region_reserve(r, r->count + 1)) return 0;
    r->rects[r->count++] = *rect;
    return 1;
}

/* ==========================================================================
 * 1-D X-interval band buffer
 * --------------------------------------------------------------------------
 * Inside a single scanline strip a region's footprint is a sorted set of
 * disjoint half-open X intervals [x1,x2).  We keep them as a flat array of
 * (x1,x2) pairs.  The boolean ops below consume two such interval sets and
 * produce a third; the producers always emit sorted, disjoint, coalesced
 * intervals (no two adjacent intervals abut), which is what makes the emitted
 * rectangles horizontally-canonical.
 * ========================================================================== */
typedef struct { int x1, x2; } cm_xspan;

typedef struct {
    cm_xspan *spans;
    int       count, cap;
    int       oom;          /* sticky out-of-memory flag                      */
} cm_xband;

static void cm_xband_init(cm_xband *b)
{
    b->spans = NULL; b->count = 0; b->cap = 0; b->oom = 0;
}

static void cm_xband_free(cm_xband *b)
{
    free(b->spans);
    b->spans = NULL; b->count = 0; b->cap = 0;
}

static void cm_xband_clear(cm_xband *b) { b->count = 0; }

static int cm_xband_reserve(cm_xband *b, int need)
{
    if (need <= b->cap) return 1;
    int cap = b->cap ? b->cap : 8;
    while (cap < need) cap *= 2;
    cm_xspan *ns = (cm_xspan *)realloc(b->spans, (size_t)cap * sizeof(cm_xspan));
    if (!ns) { b->oom = 1; return 0; }
    b->spans = ns;
    b->cap   = cap;
    return 1;
}

/* Append [x1,x2), merging with the previous span if they abut or overlap so the
 * buffer always stays sorted, disjoint and coalesced.  Callers feed spans in
 * ascending x1 order (guaranteed by the band-extract + op producers). */
static int cm_xband_push(cm_xband *b, int x1, int x2)
{
    if (x2 <= x1) return 1;                 /* empty interval: ignore           */
    if (b->count > 0 && x1 <= b->spans[b->count - 1].x2) {
        /* Overlaps or touches the last span: extend it (coalesce). */
        if (x2 > b->spans[b->count - 1].x2) b->spans[b->count - 1].x2 = x2;
        return 1;
    }
    if (!cm_xband_reserve(b, b->count + 1)) return 0;
    b->spans[b->count].x1 = x1;
    b->spans[b->count].x2 = x2;
    b->count++;
    return 1;
}

/* out = a UNION b  (both sorted/disjoint; out stays sorted/disjoint/coalesced) */
static int cm_xband_union(const cm_xband *a, const cm_xband *b, cm_xband *out)
{
    cm_xband_clear(out);
    int i = 0, j = 0;
    while (i < a->count && j < b->count) {
        if (a->spans[i].x1 <= b->spans[j].x1) {
            if (!cm_xband_push(out, a->spans[i].x1, a->spans[i].x2)) return 0;
            i++;
        } else {
            if (!cm_xband_push(out, b->spans[j].x1, b->spans[j].x2)) return 0;
            j++;
        }
    }
    for (; i < a->count; ++i)
        if (!cm_xband_push(out, a->spans[i].x1, a->spans[i].x2)) return 0;
    for (; j < b->count; ++j)
        if (!cm_xband_push(out, b->spans[j].x1, b->spans[j].x2)) return 0;
    return 1;
}

/* out = a INTERSECT b */
static int cm_xband_intersect(const cm_xband *a, const cm_xband *b, cm_xband *out)
{
    cm_xband_clear(out);
    int i = 0, j = 0;
    while (i < a->count && j < b->count) {
        int x1 = cm_imax(a->spans[i].x1, b->spans[j].x1);
        int x2 = cm_imin(a->spans[i].x2, b->spans[j].x2);
        if (x1 < x2)
            if (!cm_xband_push(out, x1, x2)) return 0;
        /* Advance whichever span ends first. */
        if (a->spans[i].x2 < b->spans[j].x2) i++;
        else                                 j++;
    }
    return 1;
}

/* out = a MINUS b */
static int cm_xband_subtract(const cm_xband *a, const cm_xband *b, cm_xband *out)
{
    cm_xband_clear(out);
    int j = 0;
    for (int i = 0; i < a->count; ++i) {
        int cur = a->spans[i].x1;            /* uncovered cursor within span i  */
        int end = a->spans[i].x2;
        /* Skip b-spans entirely left of this a-span. */
        while (j < b->count && b->spans[j].x2 <= cur) j++;
        int k = j;
        while (k < b->count && b->spans[k].x1 < end) {
            if (b->spans[k].x1 > cur) {
                if (!cm_xband_push(out, cur, cm_imin(b->spans[k].x1, end)))
                    return 0;
            }
            if (b->spans[k].x2 > cur) cur = b->spans[k].x2;
            if (cur >= end) break;
            k++;
        }
        if (cur < end)
            if (!cm_xband_push(out, cur, end)) return 0;
    }
    return 1;
}

/* ==========================================================================
 * Canonicalisation
 * --------------------------------------------------------------------------
 * cm_region_normalize() takes an arbitrary (possibly overlapping, unsorted)
 * rectangle list and rebuilds it into the canonical YX-banded form via the
 * scanline algorithm: distinct Y edges -> strips; per-strip X-union of the
 * covering rectangles -> the strip's spans; emit; then vertical-coalesce equal
 * adjacent bands.  This is the single funnel every mutating op passes through.
 *
 * Complexity is O(R * S) for R rectangles and S strips (<= 2R+1), which is the
 * same quadratic-in-the-worst-case behaviour pixman has for its general path;
 * region rectangle counts are tiny in practice (clip stacks, damage rects).
 * ========================================================================== */

/* qsort comparator: ascending, distinct caller dedups. */
static int cm_int_cmp(const void *pa, const void *pb)
{
    int a = *(const int *)pa, b = *(const int *)pb;
    return (a > b) - (a < b);
}

/* Rebuild `src` rectangles (in `work`) into canonical form, writing the result
 * back into `dst` (which may be the same region as the rectangles came from).
 * Returns CM_STATUS_SUCCESS or CM_STATUS_NO_MEMORY. */
static cm_status_t cm_region_normalize_from(cm_region_t *dst,
                                            const cm_rectangle_int_t *in,
                                            int n)
{
    /* Empty input -> empty region. */
    if (n <= 0) {
        dst->count = 0;
        return CM_STATUS_SUCCESS;
    }

    cm_status_t result = CM_STATUS_SUCCESS;

    /* ---- 1. Collect distinct Y edges (top + bottom of every rect). -------- */
    int *ys = (int *)malloc((size_t)(2 * n) * sizeof(int));
    if (!ys) return CM_STATUS_NO_MEMORY;
    int ny = 0;
    for (int i = 0; i < n; ++i) {
        if (cm_rect_empty(&in[i])) continue;
        ys[ny++] = in[i].y;
        ys[ny++] = in[i].y + in[i].height;
    }
    if (ny == 0) { free(ys); dst->count = 0; return CM_STATUS_SUCCESS; }

    qsort(ys, (size_t)ny, sizeof(int), cm_int_cmp);
    /* Dedup in place. */
    int nedges = 0;
    for (int i = 0; i < ny; ++i)
        if (nedges == 0 || ys[i] != ys[nedges - 1]) ys[nedges++] = ys[i];

    /* ---- 2. Scratch interval buffers + an output band staging region. ----- */
    cm_xband band, scratch;     /* band = current strip's spans; scratch reused */
    cm_xband_init(&band);
    cm_xband_init(&scratch);

    /* Staging holds emitted strip rectangles in YX order BEFORE vertical
     * coalesce; we coalesce on the fly against the previous band. */
    cm_region_t out = { 0 };
    out.status = CM_STATUS_SUCCESS;

    /* Track the previous emitted band's strip range + its index range in `out`
     * so we can vertically coalesce identical adjacent bands. */
    int prev_band_start = -1;   /* index into out.rects of prev band's first rect */
    int prev_band_count = 0;
    int prev_band_y2    = INT_MIN;  /* bottom of prev band (== its y+h)           */

    for (int s = 0; s + 1 < nedges; ++s) {
        int y1 = ys[s];
        int y2 = ys[s + 1];
        if (y2 <= y1) continue;              /* paranoia                         */

        /* Build this strip's X-union from every rect that fully covers [y1,y2).
         * A rect covers the strip iff rect.y <= y1 && rect.y+height >= y2 (the
         * strips are cut at every rect edge, so coverage is all-or-nothing). */
        cm_xband_clear(&band);
        cm_xband_clear(&scratch);
        int any = 0;
        for (int i = 0; i < n; ++i) {
            if (cm_rect_empty(&in[i])) continue;
            if (in[i].y <= y1 && in[i].y + in[i].height >= y2) {
                /* Union this rect's x-interval into the strip.  Spans may arrive
                 * unsorted (input rects are arbitrary), so union into a fresh
                 * scratch then swap; cheaper here: push into `band` keeping it
                 * merged requires sorted input, so we OR via cm_xband_union of a
                 * singleton.  Build a tiny singleton on the stack. */
                cm_xspan one = { in[i].x, in[i].x + in[i].width };
                cm_xband single;
                single.spans = &one; single.count = 1; single.cap = 1; single.oom = 0;
                if (!cm_xband_union(&band, &single, &scratch)) { result = CM_STATUS_NO_MEMORY; goto cleanup; }
                /* swap band <-> scratch */
                cm_xband tmp = band; band = scratch; scratch = tmp;
                any = 1;
            }
        }
        if (!any || band.count == 0) {
            /* Empty strip: it breaks vertical adjacency, so reset the coalesce
             * tracker (a gap means the next band cannot merge upward). */
            prev_band_start = -1;
            prev_band_count = 0;
            continue;
        }

        /* ---- 3a. Try to vertically coalesce with the previous band. ------- */
        int can_merge = 0;
        if (prev_band_start >= 0 && prev_band_y2 == y1 &&
            prev_band_count == band.count) {
            can_merge = 1;
            for (int k = 0; k < band.count; ++k) {
                const cm_rectangle_int_t *pr = &out.rects[prev_band_start + k];
                if (pr->x != band.spans[k].x1 ||
                    pr->x + pr->width != band.spans[k].x2) { can_merge = 0; break; }
            }
        }

        if (can_merge) {
            /* Extend every rect of the previous band downward to y2. */
            for (int k = 0; k < prev_band_count; ++k)
                out.rects[prev_band_start + k].height = y2 - out.rects[prev_band_start + k].y;
            prev_band_y2 = y2;
            continue;
        }

        /* ---- 3b. Emit a fresh band. --------------------------------------- */
        int band_start = out.count;
        for (int k = 0; k < band.count; ++k) {
            cm_rectangle_int_t rc;
            rc.x = band.spans[k].x1;
            rc.y = y1;
            rc.width  = band.spans[k].x2 - band.spans[k].x1;
            rc.height = y2 - y1;
            if (!cm_region_append(&out, &rc)) { result = CM_STATUS_NO_MEMORY; goto cleanup; }
        }
        prev_band_start = band_start;
        prev_band_count = band.count;
        prev_band_y2    = y2;
    }

    /* ---- 4. Move the staged canonical list into dst. ---------------------- */
    free(dst->rects);
    dst->rects = out.rects;
    dst->count = out.count;
    dst->cap   = out.cap;
    out.rects = NULL;            /* ownership transferred                        */

cleanup:
    if (result != CM_STATUS_SUCCESS) {
        free(out.rects);
        if (dst->status == CM_STATUS_SUCCESS) dst->status = result;
    }
    cm_xband_free(&band);
    cm_xband_free(&scratch);
    free(ys);
    return result;
}

/* Re-normalise a region in place (rebuild its own rectangle list). */
static cm_status_t cm_region_normalize(cm_region_t *r)
{
    /* Normalising from its own buffer: snapshot the pointer/count, build into a
     * temp, then swap.  cm_region_normalize_from reads `in` while writing a
     * fresh `out` buffer, so passing the live buffer is safe (it frees the old
     * dst->rects only at the very end, after reading is done). */
    return cm_region_normalize_from(r, r->rects, r->count);
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */
cm_region_t *cm_region_create(void)
{
    cm_region_t *r = (cm_region_t *)calloc(1, sizeof(*r));
    if (!r) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }
    r->refcount = 1;
    r->status   = CM_STATUS_SUCCESS;
    cm_set_last_status(CM_STATUS_SUCCESS);
    return r;
}

cm_region_t *cm_region_create_rectangle(const cm_rectangle_int_t *rectangle)
{
    cm_region_t *r = cm_region_create();
    if (!r) return NULL;
    /* A single non-empty rectangle is already canonical (one band, one span). */
    if (rectangle && !cm_rect_empty(rectangle)) {
        if (!cm_region_append(r, rectangle)) { /* sticky status set by append */ }
    }
    return r;
}

cm_region_t *cm_region_create_rectangles(const cm_rectangle_int_t *rects, int count)
{
    cm_region_t *r = cm_region_create();
    if (!r) return NULL;
    if (rects && count > 0) {
        /* Stage every rectangle, then canonicalise once (cheaper + correct vs.
         * folding union one-at-a-time, and matches cairo_region_create_rectangles
         * which builds the whole set then bands it). */
        for (int i = 0; i < count; ++i)
            if (!cm_region_append(r, &rects[i])) return r;   /* OOM: sticky set  */
        cm_region_normalize(r);
    }
    return r;
}

cm_region_t *cm_region_copy(const cm_region_t *original)
{
    cm_region_t *r = cm_region_create();
    if (!r) return NULL;
    if (original && original->count > 0) {
        if (!cm_region_reserve(r, original->count)) { cm_region_destroy(r); return NULL; }
        memcpy(r->rects, original->rects,
               (size_t)original->count * sizeof(cm_rectangle_int_t));
        r->count = original->count;
        /* `original` is canonical (invariant), so the copy is too: no re-band. */
    }
    if (original) r->status = original->status;
    return r;
}

cm_region_t *cm_region_reference(cm_region_t *region)
{
    if (region) region->refcount++;
    return region;
}

void cm_region_destroy(cm_region_t *region)
{
    if (!region) return;
    if (--region->refcount > 0) return;
    free(region->rects);
    free(region);
}

cm_status_t cm_region_status(const cm_region_t *region)
{
    return region ? region->status : CM_STATUS_NO_MEMORY;
}

/* ==========================================================================
 * Queries
 * ========================================================================== */
int cm_region_is_empty(const cm_region_t *region)
{
    return !region || region->count == 0;
}

int cm_region_num_rectangles(const cm_region_t *region)
{
    return region ? region->count : 0;
}

void cm_region_get_rectangle(const cm_region_t *region, int nth,
                             cm_rectangle_int_t *rectangle)
{
    if (!rectangle) return;
    if (!region || nth < 0 || nth >= region->count) {
        rectangle->x = rectangle->y = rectangle->width = rectangle->height = 0;
        return;
    }
    *rectangle = region->rects[nth];
}

void cm_region_get_extents(const cm_region_t *region, cm_rectangle_int_t *extents)
{
    if (!extents) return;
    if (!region || region->count == 0) {
        extents->x = extents->y = extents->width = extents->height = 0;
        return;
    }
    /* The first rect's top is the min Y (band order), the last rect's bottom is
     * the max Y; X bounds need a scan since bands vary in width.  A simple full
     * scan is clearest and cheap. */
    int x1 = region->rects[0].x;
    int y1 = region->rects[0].y;
    int x2 = x1 + region->rects[0].width;
    int y2 = y1 + region->rects[0].height;
    for (int i = 1; i < region->count; ++i) {
        const cm_rectangle_int_t *r = &region->rects[i];
        if (r->x < x1) x1 = r->x;
        if (r->y < y1) y1 = r->y;
        if (r->x + r->width  > x2) x2 = r->x + r->width;
        if (r->y + r->height > y2) y2 = r->y + r->height;
    }
    extents->x = x1; extents->y = y1;
    extents->width = x2 - x1; extents->height = y2 - y1;
}

int cm_region_contains_point(const cm_region_t *region, int x, int y)
{
    if (!region) return 0;
    for (int i = 0; i < region->count; ++i)
        if (cm_rect_contains_point(&region->rects[i], x, y)) return 1;
    return 0;
}

cm_region_overlap_t cm_region_contains_rectangle(const cm_region_t *region,
                                                 const cm_rectangle_int_t *rectangle)
{
    if (!region || !rectangle || cm_rect_empty(rectangle))
        return CM_REGION_OVERLAP_OUT;

    /* Sum the overlap area against every (non-overlapping, canonical) region
     * rectangle.  IN if the whole query rect is covered; OUT if nothing
     * overlaps; PART otherwise.  Region rects are pairwise disjoint (invariant),
     * so summed overlap area is exact and never double-counts. */
    long want = (long)rectangle->width * (long)rectangle->height;
    long got  = 0;
    int  any  = 0;
    for (int i = 0; i < region->count; ++i) {
        cm_rectangle_int_t inter;
        if (cm_rect_intersect(&region->rects[i], rectangle, &inter)) {
            got += (long)inter.width * (long)inter.height;
            any = 1;
        }
    }
    if (!any)         return CM_REGION_OVERLAP_OUT;
    if (got >= want)  return CM_REGION_OVERLAP_IN;
    return CM_REGION_OVERLAP_PART;
}

void cm_region_translate(cm_region_t *region, int dx, int dy)
{
    if (!region) return;
    /* A uniform translate preserves canonical banding (relative geometry is
     * unchanged), so no re-normalise is needed. */
    for (int i = 0; i < region->count; ++i) {
        region->rects[i].x += dx;
        region->rects[i].y += dy;
    }
}

int cm_region_equal(const cm_region_t *a, const cm_region_t *b)
{
    if (a == b) return 1;
    if (!a || !b) return 0;
    if (a->count != b->count) return 0;
    /* Both operands are in canonical form (the class invariant), so equal sets
     * have byte-identical rectangle arrays: a flat compare is exact. */
    return memcmp(a->rects, b->rects,
                  (size_t)a->count * sizeof(cm_rectangle_int_t)) == 0;
}

/* ==========================================================================
 * Set algebra
 * --------------------------------------------------------------------------
 * The generic two-operand engine: scanline over the combined Y edges of `dst`
 * and `other`, apply the per-strip 1-D interval op, stage the result, then
 * canonicalise (which performs the vertical coalesce + a final sanity re-band).
 *
 * `op` selects the interval combiner:
 *   CM_OP_UNION / CM_OP_INTERSECT / CM_OP_SUBTRACT
 * (xor is composed from two subtracts + a union, below).
 * ========================================================================== */
typedef enum { CM_OP_UNION, CM_OP_INTERSECT, CM_OP_SUBTRACT } cm_set_op;

/* Forward decl: replace dst's rectangle list with a copy of src (defined below;
 * used by cm_region_setop's union fast path). */
static cm_status_t cm_region_copy_into(cm_region_t *dst, const cm_region_t *src);

/* Extract the X-interval set of `reg` for the strip [y1,y2) into `out` (sorted,
 * disjoint, coalesced).  Region rects are canonical, so within a band they are
 * already sorted by x; across bands a rect covers the strip all-or-nothing. */
static int cm_region_strip_spans(const cm_region_t *reg, int y1, int y2,
                                 cm_xband *out, cm_xband *scratch)
{
    cm_xband_clear(out);
    for (int i = 0; i < reg->count; ++i) {
        const cm_rectangle_int_t *r = &reg->rects[i];
        if (r->y <= y1 && r->y + r->height >= y2) {
            cm_xspan one = { r->x, r->x + r->width };
            cm_xband single;
            single.spans = &one; single.count = 1; single.cap = 1; single.oom = 0;
            if (!cm_xband_union(out, &single, scratch)) return 0;
            cm_xband tmp = *out; *out = *scratch; *scratch = tmp;
        }
    }
    return 1;
}

static cm_status_t cm_region_setop(cm_region_t *dst, const cm_region_t *other,
                                   cm_set_op op)
{
    if (!dst || !other) return CM_STATUS_NO_MEMORY;

    /* Fast exits that also keep canonical form trivially. */
    if (op == CM_OP_INTERSECT && (dst->count == 0 || other->count == 0)) {
        dst->count = 0;
        return CM_STATUS_SUCCESS;
    }
    if (op == CM_OP_SUBTRACT && (dst->count == 0 || other->count == 0)) {
        /* dst - {} == dst; {} - other == {} (already empty). */
        return CM_STATUS_SUCCESS;
    }
    if (op == CM_OP_UNION && other->count == 0) return CM_STATUS_SUCCESS;
    if (op == CM_OP_UNION && dst->count == 0)   return cm_region_copy_into(dst, other);

    cm_status_t result = CM_STATUS_SUCCESS;

    /* ---- Combined distinct Y edges of both operands. --------------------- */
    int total = dst->count + other->count;
    int *ys = (int *)malloc((size_t)(2 * total) * sizeof(int));
    if (!ys) return CM_STATUS_NO_MEMORY;
    int ny = 0;
    for (int i = 0; i < dst->count; ++i) {
        ys[ny++] = dst->rects[i].y;
        ys[ny++] = dst->rects[i].y + dst->rects[i].height;
    }
    for (int i = 0; i < other->count; ++i) {
        ys[ny++] = other->rects[i].y;
        ys[ny++] = other->rects[i].y + other->rects[i].height;
    }
    qsort(ys, (size_t)ny, sizeof(int), cm_int_cmp);
    int nedges = 0;
    for (int i = 0; i < ny; ++i)
        if (nedges == 0 || ys[i] != ys[nedges - 1]) ys[nedges++] = ys[i];

    /* ---- Scanline strips -> per-strip interval op -> staged rectangles. --- */
    cm_xband sa, sb, sr, scratch;
    cm_xband_init(&sa); cm_xband_init(&sb); cm_xband_init(&sr); cm_xband_init(&scratch);

    cm_region_t out = { 0 };
    out.status = CM_STATUS_SUCCESS;

    for (int s = 0; s + 1 < nedges; ++s) {
        int y1 = ys[s], y2 = ys[s + 1];
        if (y2 <= y1) continue;

        if (!cm_region_strip_spans(dst,   y1, y2, &sa, &scratch)) { result = CM_STATUS_NO_MEMORY; goto cleanup; }
        if (!cm_region_strip_spans(other, y1, y2, &sb, &scratch)) { result = CM_STATUS_NO_MEMORY; goto cleanup; }

        int ok = 1;
        switch (op) {
            case CM_OP_UNION:     ok = cm_xband_union(&sa, &sb, &sr);     break;
            case CM_OP_INTERSECT: ok = cm_xband_intersect(&sa, &sb, &sr); break;
            case CM_OP_SUBTRACT:  ok = cm_xband_subtract(&sa, &sb, &sr);  break;
        }
        if (!ok) { result = CM_STATUS_NO_MEMORY; goto cleanup; }

        for (int k = 0; k < sr.count; ++k) {
            cm_rectangle_int_t rc;
            rc.x = sr.spans[k].x1;
            rc.y = y1;
            rc.width  = sr.spans[k].x2 - sr.spans[k].x1;
            rc.height = y2 - y1;
            if (!cm_region_append(&out, &rc)) { result = CM_STATUS_NO_MEMORY; goto cleanup; }
        }
    }

    /* The staged list is YX-sorted, horizontally-coalesced, and band-uniform but
     * NOT yet vertically coalesced (adjacent equal strips are separate); the
     * normaliser performs that pass and yields the canonical form. */
    {
        cm_status_t ns = cm_region_normalize_from(dst, out.rects, out.count);
        if (ns != CM_STATUS_SUCCESS) result = ns;
    }

cleanup:
    if (result != CM_STATUS_SUCCESS && dst->status == CM_STATUS_SUCCESS)
        dst->status = result;
    free(out.rects);
    cm_xband_free(&sa); cm_xband_free(&sb); cm_xband_free(&sr); cm_xband_free(&scratch);
    free(ys);
    return result;
}

/* Replace dst's rectangle list with a copy of `src` (used by the union fast
 * path when dst starts empty).  Keeps dst's identity/refcount/status. */
static cm_status_t cm_region_copy_into(cm_region_t *dst, const cm_region_t *src)
{
    if (src->count == 0) { dst->count = 0; return CM_STATUS_SUCCESS; }
    if (!cm_region_reserve(dst, src->count)) return CM_STATUS_NO_MEMORY;
    memcpy(dst->rects, src->rects,
           (size_t)src->count * sizeof(cm_rectangle_int_t));
    dst->count = src->count;
    return CM_STATUS_SUCCESS;
}

/* ---- union -------------------------------------------------------------- */
cm_status_t cm_region_union(cm_region_t *dst, const cm_region_t *other)
{
    return cm_region_setop(dst, other, CM_OP_UNION);
}

cm_status_t cm_region_union_rectangle(cm_region_t *dst,
                                      const cm_rectangle_int_t *rectangle)
{
    if (!dst || !rectangle) return CM_STATUS_NO_MEMORY;
    if (cm_rect_empty(rectangle)) return CM_STATUS_SUCCESS;
    cm_region_t tmp = { 0 };
    tmp.rects = (cm_rectangle_int_t *)rectangle;   /* borrow: 1 rect, read-only  */
    tmp.count = 1; tmp.cap = 1; tmp.status = CM_STATUS_SUCCESS;
    cm_status_t st = cm_region_setop(dst, &tmp, CM_OP_UNION);
    /* tmp.rects aliases the caller's rectangle; do NOT free it. */
    return st;
}

/* ---- intersect ---------------------------------------------------------- */
cm_status_t cm_region_intersect(cm_region_t *dst, const cm_region_t *other)
{
    return cm_region_setop(dst, other, CM_OP_INTERSECT);
}

cm_status_t cm_region_intersect_rectangle(cm_region_t *dst,
                                          const cm_rectangle_int_t *rectangle)
{
    if (!dst || !rectangle) return CM_STATUS_NO_MEMORY;
    if (cm_rect_empty(rectangle)) { dst->count = 0; return CM_STATUS_SUCCESS; }
    cm_region_t tmp = { 0 };
    tmp.rects = (cm_rectangle_int_t *)rectangle;
    tmp.count = 1; tmp.cap = 1; tmp.status = CM_STATUS_SUCCESS;
    return cm_region_setop(dst, &tmp, CM_OP_INTERSECT);
}

/* ---- subtract ----------------------------------------------------------- */
cm_status_t cm_region_subtract(cm_region_t *dst, const cm_region_t *other)
{
    return cm_region_setop(dst, other, CM_OP_SUBTRACT);
}

cm_status_t cm_region_subtract_rectangle(cm_region_t *dst,
                                         const cm_rectangle_int_t *rectangle)
{
    if (!dst || !rectangle) return CM_STATUS_NO_MEMORY;
    if (cm_rect_empty(rectangle)) return CM_STATUS_SUCCESS;   /* dst - {} == dst */
    cm_region_t tmp = { 0 };
    tmp.rects = (cm_rectangle_int_t *)rectangle;
    tmp.count = 1; tmp.cap = 1; tmp.status = CM_STATUS_SUCCESS;
    return cm_region_setop(dst, &tmp, CM_OP_SUBTRACT);
}

/* ---- xor = union(subtract(a,b), subtract(b,a)) -------------------------- */
cm_status_t cm_region_xor(cm_region_t *dst, const cm_region_t *other)
{
    if (!dst || !other) return CM_STATUS_NO_MEMORY;

    /* a_minus_b = dst - other  (compute into a copy of dst). */
    cm_region_t *a_minus_b = cm_region_copy(dst);
    /* b_minus_a = other - dst  (compute into a copy of other). */
    cm_region_t *b_minus_a = cm_region_copy(other);
    if (!a_minus_b || !b_minus_a) {
        cm_region_destroy(a_minus_b);
        cm_region_destroy(b_minus_a);
        return CM_STATUS_NO_MEMORY;
    }

    cm_status_t st = cm_region_subtract(a_minus_b, other);
    if (st == CM_STATUS_SUCCESS) st = cm_region_subtract(b_minus_a, dst);
    if (st == CM_STATUS_SUCCESS) {
        /* dst = a_minus_b, then union in b_minus_a.  Adopt a_minus_b's buffer
         * directly (avoids a copy), then union re-bands the result. */
        free(dst->rects);
        dst->rects = a_minus_b->rects;
        dst->count = a_minus_b->count;
        dst->cap   = a_minus_b->cap;
        a_minus_b->rects = NULL;
        a_minus_b->count = a_minus_b->cap = 0;
        st = cm_region_union(dst, b_minus_a);
    }
    if (st != CM_STATUS_SUCCESS && dst->status == CM_STATUS_SUCCESS)
        dst->status = st;

    cm_region_destroy(a_minus_b);
    cm_region_destroy(b_minus_a);
    return st;
}

cm_status_t cm_region_xor_rectangle(cm_region_t *dst,
                                    const cm_rectangle_int_t *rectangle)
{
    if (!dst || !rectangle) return CM_STATUS_NO_MEMORY;
    cm_region_t *other = cm_region_create_rectangle(rectangle);
    if (!other) return CM_STATUS_NO_MEMORY;
    cm_status_t st = cm_region_xor(dst, other);
    cm_region_destroy(other);
    return st;
}
