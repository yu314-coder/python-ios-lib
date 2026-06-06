/*
 * cm_font.c  --  CairoMetal FontOptions / FontFace / ScaledFont + font state
 * ============================================================================
 *
 * Owns the value types + refcounted handles that need no Objective-C:
 *   - cm_font_options_t (create/copy/destroy/status/merge/equal/hash + set/get)
 *   - cm_font_face_t base lifecycle + ToyFontFace family/slant/weight storage
 *   - cm_scaled_font_t struct skeleton + get_* accessors
 *   - the context font-state block (select_font_face / set_font_size /
 *     set+get_font_matrix / options / face / scaled_font) with lazy resolve +
 *     invalidation on every font-state OR CTM change.
 *
 * This file is PURE C.  Everything CoreText-dependent (resolving a face to a
 * CTFontRef, glyph outlines, shaping, glyph/text/font metrics) lives in
 * cm_text.m; this file calls DOWN into it through the opaque `void *native`
 * handle declared in cm_internal.h (cm_text_resolve_native / _release_native /
 * _shape / _glyph_extents / _font_extents).  Because the cm_scaled_font struct
 * is private to THIS translation unit, cm_text.m cannot cache the CTFontRef
 * inside it; instead cm_text_resolve_native() is a pure FACTORY (it reads the
 * scaled font's face + matrices through the public accessors and returns a
 * freshly-retained CTFontRef, or NULL), and THIS file owns the cache: the
 * native handle is built at most once per scaled font, stored in sf->native,
 * and released exactly once in cm_scaled_font_destroy.  A no-text / nil-device
 * build leaves native == NULL and every metric returns the zeroed default.
 *
 * Ownership rules (must match cm_state.c, which retains/copies these into its
 * gstate snapshots):
 *   - cm_font_face_t is refcounted (reference/destroy);
 *   - cm_font_options_t is value-copied (copy/destroy) -- never shared;
 *   - cm_scaled_font_t is refcounted and OWNS a reference on its face plus an
 *     owned copy of its options plus (lazily) one native CTFontRef.
 * ============================================================================
 */

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Internal struct layouts (private to this translation unit)
 * ========================================================================== */

struct cm_font_face {
    int               refcount;
    cm_font_type_t    type;
    cm_status_t       status;
    /* toy face */
    char             *family;
    cm_font_slant_t   slant;
    cm_font_weight_t  weight;
    /* FT face (guarded; stored as an opaque FT_Face void*) */
    void             *ft_face;        /* FT_Face as void*                     */
    int               ft_load_flags;
    /* File-loaded face (cm_ft_font_face_create_for_path): the OWNED native font
     * handle (a CTFontRef stored as void*).  Released in destroy via
     * cm_text_release_native.  NULL for toy / FT-face-pointer faces. */
    void             *native_font;
};

struct cm_font_options {
    cm_status_t         status;
    cm_antialias_t      antialias;
    cm_subpixel_order_t subpixel_order;
    cm_hint_style_t     hint_style;
    cm_hint_metrics_t   hint_metrics;
    char               *variations;   /* owned NUL-terminated copy, or NULL    */
};

struct cm_scaled_font {
    int                refcount;
    cm_status_t        status;
    cm_font_face_t    *face;          /* retained (+1)                        */
    cm_matrix_t        font_matrix;
    cm_matrix_t        ctm;
    cm_font_options_t *options;       /* owned copy                           */
    void              *native;        /* cached CTFontRef (cm_text.m), or NULL */
    bool               native_tried;  /* resolve attempted (cache valid)      */
};

/* ==========================================================================
 * Small owned-string helper
 * ========================================================================== */

/* Duplicate a NUL-terminated string into a fresh malloc'd buffer (NULL-safe;
 * returns NULL for a NULL input, which all callers treat as "unset"). */
static char *cm_str_dup(const char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *d = (char *)malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

/* ==========================================================================
 * Font face
 * --------------------------------------------------------------------------
 * cm_font_face_t is reference counted (cairo_font_face_t semantics): create
 * returns a face with refcount 1; reference bumps it; destroy decrements and
 * frees the payload on the last release.  A toy face owns its family string; an
 * FT face owns nothing (the FT_Face is the caller's).
 * ========================================================================== */

cm_font_face_t *cm_toy_font_face_create(const char *family,
                                        cm_font_slant_t slant,
                                        cm_font_weight_t weight)
{
    cm_font_face_t *f = (cm_font_face_t *)calloc(1, sizeof(*f));
    if (!f) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }

    f->refcount = 1;
    f->type     = CM_FONT_TYPE_TOY;
    f->status   = CM_STATUS_SUCCESS;
    f->slant    = slant;
    f->weight   = weight;
    f->family   = cm_str_dup(family);   /* NULL family => empty (cairo "")     */
    return f;
}

const char *cm_toy_font_face_get_family(cm_font_face_t *font_face)
{
    /* cairo_toy_font_face_get_family never returns NULL; a non-toy face yields
     * the empty string. */
    if (!font_face || font_face->type != CM_FONT_TYPE_TOY) return "";
    return font_face->family ? font_face->family : "";
}

cm_font_slant_t cm_toy_font_face_get_slant(cm_font_face_t *font_face)
{
    return font_face ? font_face->slant : CM_FONT_SLANT_NORMAL;
}

cm_font_weight_t cm_toy_font_face_get_weight(cm_font_face_t *font_face)
{
    return font_face ? font_face->weight : CM_FONT_WEIGHT_NORMAL;
}

cm_font_face_t *cm_font_face_reference(cm_font_face_t *font_face)
{
    if (font_face && font_face->refcount > 0) font_face->refcount++;
    return font_face;
}

void cm_font_face_destroy(cm_font_face_t *font_face)
{
    if (!font_face) return;
    if (font_face->refcount > 0 && --font_face->refcount > 0) return;
    /* Release the owned native font handle (a file-loaded face's CTFontRef).
     * cm_text_release_native CFReleases it; NULL-safe for toy / FT faces. */
    if (font_face->native_font) cm_text_release_native(font_face->native_font);
    free(font_face->family);
    free(font_face);
}

cm_status_t cm_font_face_status(cm_font_face_t *font_face)
{
    return font_face ? font_face->status : CM_STATUS_NO_MEMORY;
}

cm_font_type_t cm_font_face_get_type(cm_font_face_t *font_face)
{
    return font_face ? font_face->type : CM_FONT_TYPE_TOY;
}

/* INTERNAL accessor used by cm_text.m / cm_ft.c (declared via extern there).
 * Returns the stored FT_Face (or NULL) and, if requested, its load flags.  The
 * face owns neither -- it only records the void* + flags the caller passed to
 * cm_ft_font_face_create_for_ft_face. */
void *cm_font_face_ft_face(cm_font_face_t *face, int *out_load_flags)
{
    if (!face) {
        if (out_load_flags) *out_load_flags = 0;
        return NULL;
    }
    if (out_load_flags) *out_load_flags = face->ft_load_flags;
    return face->ft_face;
}

/* ==========================================================================
 * FreeType font face constructor
 * --------------------------------------------------------------------------
 * Always defined (it needs no FreeType headers -- it only stores the opaque
 * FT_Face void* + load flags).  The outline/metric emission for FT lives in
 * cm_ft.c behind CM_ENABLE_FREETYPE; the public lock/unlock accessors live
 * there too.
 * ========================================================================== */

cm_font_face_t *cm_ft_font_face_create_for_ft_face(void *ft_face, int load_flags)
{
    cm_font_face_t *f = (cm_font_face_t *)calloc(1, sizeof(*f));
    if (!f) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }

    f->refcount      = 1;
    f->type          = CM_FONT_TYPE_FT;
    f->status        = CM_STATUS_SUCCESS;
    f->ft_face       = ft_face;
    f->ft_load_flags = load_flags;
    return f;
}

/* A face's owned native font handle (CTFontRef as void*), or NULL.  Read by
 * cm_text_resolve_toy_face so a file-loaded face renders its own glyphs. */
void *cm_font_face_native_font(cm_font_face_t *face)
{
    return face ? face->native_font : NULL;
}

/* Create a font face from a font FILE on disk.  The file is loaded to a native
 * CTFontRef via cm_text.m (CoreText, no FreeType dependency); the face OWNS that
 * handle and reports type FT (it is, semantically, a face backed by a real font
 * file rather than a toy family name).  Returns NULL with cm_last_status set if
 * the file cannot be loaded as a font. */
cm_font_face_t *cm_ft_font_face_create_for_path(const char *path, int index)
{
    void *native = cm_text_ctfont_from_path(path, index);
    if (!native) {
        /* No such file / not a font.  There is no FILE_NOT_FOUND in the cm status
         * set; report FONT_TYPE_MISMATCH (closest "this is not a usable font")
         * and return NULL -- the Python binding raises a precise message. */
        cm_set_last_status(CM_STATUS_FONT_TYPE_MISMATCH);
        return NULL;
    }
    cm_font_face_t *f = (cm_font_face_t *)calloc(1, sizeof(*f));
    if (!f) {
        cm_text_release_native(native);
        cm_set_last_status(CM_STATUS_NO_MEMORY);
        return NULL;
    }
    f->refcount     = 1;
    f->type         = CM_FONT_TYPE_FT;
    f->status       = CM_STATUS_SUCCESS;
    f->native_font  = native;   /* OWNED; released in cm_font_face_destroy */
    cm_set_last_status(CM_STATUS_SUCCESS);
    return f;
}

/* ==========================================================================
 * Font options
 * --------------------------------------------------------------------------
 * cm_font_options_t is a value type: it is COPIED (never shared / refcounted),
 * matching cairo_font_options_t.  create yields the all-DEFAULT options; copy
 * duplicates every field (including the owned variations string).
 * ========================================================================== */

/* Copy ALL fields of `src` onto `dst` (a full assignment, NOT the asymmetric
 * cairo "merge").  Used by copy + by the get_font_options accessors, which must
 * return EVERY field faithfully (a merge would skip DEFAULT-valued fields).
 * The owned variations string is reallocated; on OOM `dst->variations` is left
 * NULL (the rest of the copy is still applied). */
static void cm_font_options_assign(cm_font_options_t *dst,
                                   const cm_font_options_t *src)
{
    if (!dst || !src || dst == src) return;
    dst->antialias      = src->antialias;
    dst->subpixel_order = src->subpixel_order;
    dst->hint_style     = src->hint_style;
    dst->hint_metrics   = src->hint_metrics;
    free(dst->variations);
    dst->variations = cm_str_dup(src->variations);
}

cm_font_options_t *cm_font_options_create(void)
{
    cm_font_options_t *o = (cm_font_options_t *)calloc(1, sizeof(*o));
    if (!o) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }

    o->status         = CM_STATUS_SUCCESS;
    o->antialias      = CM_ANTIALIAS_DEFAULT;
    o->subpixel_order = CM_SUBPIXEL_ORDER_DEFAULT;
    o->hint_style     = CM_HINT_STYLE_DEFAULT;
    o->hint_metrics   = CM_HINT_METRICS_DEFAULT;
    o->variations     = NULL;
    return o;
}

cm_font_options_t *cm_font_options_copy(const cm_font_options_t *original)
{
    cm_font_options_t *o = cm_font_options_create();
    if (!o) return NULL;
    if (original) cm_font_options_assign(o, original);
    return o;
}

void cm_font_options_destroy(cm_font_options_t *options)
{
    if (!options) return;
    free(options->variations);
    free(options);
}

cm_status_t cm_font_options_status(cm_font_options_t *options)
{
    return options ? options->status : CM_STATUS_NO_MEMORY;
}

/* cairo_font_options_merge: for every field, if `other`'s value is NON-default,
 * it overrides `options`; DEFAULT-valued fields of `other` leave `options`
 * untouched.  The variations string, when present on `other`, replaces. */
void cm_font_options_merge(cm_font_options_t *options,
                           const cm_font_options_t *other)
{
    if (!options || !other) return;

    if (other->antialias      != CM_ANTIALIAS_DEFAULT)
        options->antialias = other->antialias;
    if (other->subpixel_order != CM_SUBPIXEL_ORDER_DEFAULT)
        options->subpixel_order = other->subpixel_order;
    if (other->hint_style     != CM_HINT_STYLE_DEFAULT)
        options->hint_style = other->hint_style;
    if (other->hint_metrics   != CM_HINT_METRICS_DEFAULT)
        options->hint_metrics = other->hint_metrics;
    if (other->variations) {
        char *dup = cm_str_dup(other->variations);
        free(options->variations);
        options->variations = dup;
    }
}

int cm_font_options_equal(const cm_font_options_t *a, const cm_font_options_t *b)
{
    if (a == b) return 1;
    if (!a || !b) return 0;
    if (a->antialias      != b->antialias)      return 0;
    if (a->subpixel_order != b->subpixel_order) return 0;
    if (a->hint_style     != b->hint_style)     return 0;
    if (a->hint_metrics   != b->hint_metrics)   return 0;
    const char *va = a->variations ? a->variations : "";
    const char *vb = b->variations ? b->variations : "";
    return strcmp(va, vb) == 0;
}

unsigned long cm_font_options_hash(const cm_font_options_t *options)
{
    /* FNV-1a over the option fields; order-independent of the variations
     * string's content beyond byte order.  Two options that compare equal under
     * cm_font_options_equal MUST hash identically (cairo contract): equal fields
     * + equal variations bytes => identical mix here. */
    if (!options) return 0;

    unsigned long h = 1469598103934665603UL;          /* FNV offset basis      */
    const unsigned long P = 1099511628211UL;           /* FNV prime             */
    h = (h ^ (unsigned long)options->antialias)      * P;
    h = (h ^ (unsigned long)options->subpixel_order) * P;
    h = (h ^ (unsigned long)options->hint_style)     * P;
    h = (h ^ (unsigned long)options->hint_metrics)   * P;
    if (options->variations)
        for (const char *p = options->variations; *p; ++p)
            h = (h ^ (unsigned char)*p) * P;
    return h;
}

void cm_font_options_set_antialias(cm_font_options_t *o, cm_antialias_t v)
{
    if (o) o->antialias = v;
}
cm_antialias_t cm_font_options_get_antialias(const cm_font_options_t *o)
{
    return o ? o->antialias : CM_ANTIALIAS_DEFAULT;
}

void cm_font_options_set_subpixel_order(cm_font_options_t *o, cm_subpixel_order_t v)
{
    if (o) o->subpixel_order = v;
}
cm_subpixel_order_t cm_font_options_get_subpixel_order(const cm_font_options_t *o)
{
    return o ? o->subpixel_order : CM_SUBPIXEL_ORDER_DEFAULT;
}

void cm_font_options_set_hint_style(cm_font_options_t *o, cm_hint_style_t v)
{
    if (o) o->hint_style = v;
}
cm_hint_style_t cm_font_options_get_hint_style(const cm_font_options_t *o)
{
    return o ? o->hint_style : CM_HINT_STYLE_DEFAULT;
}

void cm_font_options_set_hint_metrics(cm_font_options_t *o, cm_hint_metrics_t v)
{
    if (o) o->hint_metrics = v;
}
cm_hint_metrics_t cm_font_options_get_hint_metrics(const cm_font_options_t *o)
{
    return o ? o->hint_metrics : CM_HINT_METRICS_DEFAULT;
}

void cm_font_options_set_variations(cm_font_options_t *o, const char *variations)
{
    if (!o) return;
    char *dup = cm_str_dup(variations);   /* NULL clears                        */
    free(o->variations);
    o->variations = dup;
}

const char *cm_font_options_get_variations(cm_font_options_t *o)
{
    /* cairo returns NULL when no variations are set; mirror that (a NULL here
     * is the documented "unset" sentinel, distinct from "" which is a real,
     * empty axis string the caller explicitly installed). */
    return o ? o->variations : NULL;
}

/* ==========================================================================
 * Scaled font
 * --------------------------------------------------------------------------
 * A scaled font binds a face + font matrix + CTM + options.  It is refcounted
 * and OWNS: one reference on its face, one owned copy of its options, and
 * (lazily) one native CTFontRef resolved through cm_text.m.
 * ========================================================================== */

/* Resolve (once) and cache the native CTFontRef for `sf`.  cm_text.m's factory
 * reads the face + matrices through the public accessors and returns a +1
 * CTFontRef (or NULL on a nil device / unsupported face / no-text build); we
 * cache the result so the resolve happens at most once and is released exactly
 * once in destroy.  Returns the (possibly NULL) native handle. */
static void *cm_scaled_font_ensure_native(cm_scaled_font_t *sf)
{
    if (!sf) return NULL;
    if (!sf->native_tried) {
        sf->native       = cm_text_resolve_native(sf);
        sf->native_tried = true;
    }
    return sf->native;
}

cm_scaled_font_t *cm_scaled_font_create(cm_font_face_t *font_face,
                                        const cm_matrix_t *font_matrix,
                                        const cm_matrix_t *ctm,
                                        const cm_font_options_t *options)
{
    cm_scaled_font_t *sf = (cm_scaled_font_t *)calloc(1, sizeof(*sf));
    if (!sf) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }

    sf->refcount = 1;
    sf->status   = CM_STATUS_SUCCESS;
    sf->face     = font_face ? cm_font_face_reference(font_face) : NULL;

    if (font_matrix) sf->font_matrix = *font_matrix;
    else             cm_matrix_init_scale(&sf->font_matrix, 10.0, 10.0);

    if (ctm) sf->ctm = *ctm;
    else     cm_matrix_identity(&sf->ctm);

    /* Options are value-copied so the scaled font is independent of the
     * caller's object (which cairo lets the caller mutate/destroy afterwards). */
    sf->options      = options ? cm_font_options_copy(options)
                               : cm_font_options_create();
    sf->native       = NULL;
    sf->native_tried = false;
    return sf;
}

cm_scaled_font_t *cm_scaled_font_reference(cm_scaled_font_t *scaled_font)
{
    if (scaled_font && scaled_font->refcount > 0) scaled_font->refcount++;
    return scaled_font;
}

void cm_scaled_font_destroy(cm_scaled_font_t *scaled_font)
{
    if (!scaled_font) return;
    if (scaled_font->refcount > 0 && --scaled_font->refcount > 0) return;

    if (scaled_font->native)  cm_text_release_native(scaled_font->native);
    if (scaled_font->face)    cm_font_face_destroy(scaled_font->face);
    if (scaled_font->options) cm_font_options_destroy(scaled_font->options);
    free(scaled_font);
}

cm_status_t cm_scaled_font_status(cm_scaled_font_t *scaled_font)
{
    return scaled_font ? scaled_font->status : CM_STATUS_NO_MEMORY;
}

cm_font_type_t cm_scaled_font_get_type(cm_scaled_font_t *scaled_font)
{
    /* The scaled-font type is its face's type (cairo: TOY/FT/USER). */
    if (scaled_font && scaled_font->face) return scaled_font->face->type;
    return CM_FONT_TYPE_TOY;
}

cm_font_face_t *cm_scaled_font_get_font_face(cm_scaled_font_t *scaled_font)
{
    /* Returns the face WITHOUT adding a reference (cairo_scaled_font_get_font_face
     * returns a borrowed handle owned by the scaled font). */
    return scaled_font ? scaled_font->face : NULL;
}

void cm_scaled_font_get_font_matrix(cm_scaled_font_t *sf, cm_matrix_t *out)
{
    if (!out) return;
    if (sf) *out = sf->font_matrix; else cm_matrix_identity(out);
}

void cm_scaled_font_get_ctm(cm_scaled_font_t *sf, cm_matrix_t *out)
{
    if (!out) return;
    if (sf) *out = sf->ctm; else cm_matrix_identity(out);
}

void cm_scaled_font_get_scale_matrix(cm_scaled_font_t *sf, cm_matrix_t *out)
{
    if (!out) return;
    if (sf) {
        /* The scale matrix is the font matrix composed with the CTM: apply the
         * font matrix FIRST, then the CTM (cairo_matrix_multiply(scale, font,
         * ctm)).  cm_matrix_multiply(result, a, b) applies `a` then `b`. */
        cm_matrix_multiply(out, &sf->font_matrix, &sf->ctm);
    } else {
        cm_matrix_identity(out);
    }
}

void cm_scaled_font_get_font_options(cm_scaled_font_t *sf, cm_font_options_t *out)
{
    if (!out) return;
    /* Copy EVERY field faithfully (a full assign, not a merge): cairo's
     * get_font_options reproduces the scaled font's options exactly. */
    if (sf && sf->options) cm_font_options_assign(out, sf->options);
}

/* ---- metrics (route through cm_text.m via the cached native font) -------- */

void cm_scaled_font_extents(cm_scaled_font_t *sf, cm_font_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (sf) cm_text_font_extents(cm_scaled_font_ensure_native(sf), extents);
}

void cm_scaled_font_text_extents(cm_scaled_font_t *sf, const char *utf8,
                                 cm_text_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (!sf || !utf8 || !*utf8) return;

    /* Shape the UTF-8 to glyphs, accumulate their extents, then free the
     * shaped run.  Origin (0,0): text_extents is relative to the text origin. */
    void *native = cm_scaled_font_ensure_native(sf);
    cm_glyph_t *glyphs = NULL;
    int n = 0;
    if (cm_text_shape(native, 0.0, 0.0, utf8, -1, &glyphs, &n) == CM_STATUS_SUCCESS
        && glyphs && n > 0) {
        cm_text_glyph_extents(native, glyphs, n, extents);
    }
    free(glyphs);
}

void cm_scaled_font_glyph_extents(cm_scaled_font_t *sf, const cm_glyph_t *glyphs,
                                  int num_glyphs, cm_text_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (sf && glyphs && num_glyphs > 0)
        cm_text_glyph_extents(cm_scaled_font_ensure_native(sf),
                              glyphs, num_glyphs, extents);
}

cm_status_t cm_scaled_font_text_to_glyphs(cm_scaled_font_t *sf,
                                          double x, double y,
                                          const char *utf8, int utf8_len,
                                          cm_glyph_t **glyphs, int *num_glyphs,
                                          cm_text_cluster_t **clusters,
                                          int *num_clusters,
                                          cm_text_cluster_flags_t *cluster_flags)
{
    /* Initialise every out-param to the empty result first so a caller that
     * ignores the status never reads an uninitialised pointer/count. */
    if (glyphs)        *glyphs = NULL;
    if (num_glyphs)    *num_glyphs = 0;
    if (clusters)      *clusters = NULL;
    if (num_clusters)  *num_clusters = 0;
    if (cluster_flags) *cluster_flags = (cm_text_cluster_flags_t)0;

    if (!sf) return CM_STATUS_NO_MEMORY;

    /* Shape through cm_text.m.  Clusters are optional (cairo allows NULL); this
     * path returns glyphs only, which is a valid cairo result when the caller
     * did not request the back-mapping. */
    return cm_text_shape(cm_scaled_font_ensure_native(sf), x, y,
                         utf8, utf8_len, glyphs, num_glyphs);
}

/* Free glyph / cluster arrays handed back by the shaping API.  cm_text.m
 * allocates them with malloc/calloc, so plain free() is the matching release
 * (mirrors cairo_glyph_free / cairo_text_cluster_free). */
void cm_glyph_free(cm_glyph_t *glyphs)            { free(glyphs); }
void cm_text_cluster_free(cm_text_cluster_t *clusters) { free(clusters); }

/* ==========================================================================
 * Context font state (public bodies live here)
 * --------------------------------------------------------------------------
 * The live font state lives in struct cm_context: font_face (retained),
 * font_matrix, font_options (owned copy), scaled_font (retained/derived) and
 * the scaled_font_dirty flag.  Any change to the face, the font matrix, the
 * options, OR the CTM invalidates the cached scaled font so the next
 * cm_get_scaled_font re-derives it (and re-resolves its native CTFontRef).
 *
 * The CTM-change invalidation is driven from cairo_metal.m (cm_set_matrix /
 * cm_scale / cm_translate / cm_rotate / cm_transform / cm_identity_matrix set
 * ctx->scaled_font_dirty = true) and from cm_state.c (cm_restore), matching the
 * responsibility split; this file owns the FONT-state mutators below, each of
 * which also marks the cache dirty.
 * ========================================================================== */

/* Sticky first-error on the context (mirrors cairo_status(): the first non-
 * success status latches and later ones are ignored).  Same idiom cm_state.c
 * uses; cm_ctx_set_status in cairo_metal.m is file-private, so the .c modules
 * each apply this rule inline. */
static inline void cm_ctx_sticky_status(cm_context_t *ctx, cm_status_t st)
{
    if (ctx && st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;
}

/* Drop any cached scaled font and mark the cache dirty.  Called by every font-
 * state mutator (and usable from a CTM-change path) so the scaled font is
 * re-derived + re-resolved against the new state on next get. */
static void cm_font_state_invalidate(cm_context_t *ctx)
{
    if (!ctx) return;
    if (ctx->scaled_font) {
        cm_scaled_font_destroy(ctx->scaled_font);
        ctx->scaled_font = NULL;
    }
    ctx->scaled_font_dirty = true;
}

void cm_select_font_face(cm_context_t *ctx, const char *family,
                         cm_font_slant_t slant, cm_font_weight_t weight)
{
    if (!ctx) return;

    /* cairo_select_font_face replaces the font FACE with a fresh toy face but
     * leaves the font MATRIX (size) untouched.  Build the new face first so a
     * malloc failure leaves the previous face in place. */
    cm_font_face_t *face = cm_toy_font_face_create(family, slant, weight);
    if (!face) { cm_ctx_sticky_status(ctx, CM_STATUS_NO_MEMORY); return; }

    if (ctx->font_face) cm_font_face_destroy(ctx->font_face);
    ctx->font_face = face;             /* takes the create's +1 reference       */
    cm_font_state_invalidate(ctx);
}

void cm_set_font_size(cm_context_t *ctx, double size)
{
    if (!ctx) return;
    /* cairo_set_font_size sets the font matrix to scale(size, size). */
    cm_matrix_init_scale(&ctx->font_matrix, size, size);
    cm_font_state_invalidate(ctx);
}

void cm_set_font_matrix(cm_context_t *ctx, const cm_matrix_t *matrix)
{
    if (!ctx || !matrix) return;
    ctx->font_matrix = *matrix;
    cm_font_state_invalidate(ctx);
}

void cm_get_font_matrix(cm_context_t *ctx, cm_matrix_t *matrix)
{
    if (!matrix) return;
    /* Default font matrix (no context) is scale(10,10), cairo's default size. */
    if (ctx) *matrix = ctx->font_matrix;
    else     cm_matrix_init_scale(matrix, 10.0, 10.0);
}

void cm_set_font_options(cm_context_t *ctx, const cm_font_options_t *options)
{
    if (!ctx) return;
    /* Take an OWNED copy (the live state never shares the caller's object). */
    cm_font_options_t *copy = options ? cm_font_options_copy(options) : NULL;
    if (ctx->font_options) cm_font_options_destroy(ctx->font_options);
    ctx->font_options = copy;
    cm_font_state_invalidate(ctx);
}

void cm_get_font_options(cm_context_t *ctx, cm_font_options_t *options)
{
    if (!options) return;
    /* Copy EVERY field of the context's options onto the caller's object.  When
     * the context has no options set, the caller's object is left as-is (cairo
     * reports the all-default options, which is what a freshly created
     * cm_font_options_t already holds). */
    if (ctx && ctx->font_options) cm_font_options_assign(options, ctx->font_options);
}

void cm_set_font_face(cm_context_t *ctx, cm_font_face_t *font_face)
{
    if (!ctx) return;
    /* Passing NULL resets to the default (next get lazily creates the default
     * toy face), matching cairo_set_font_face(cr, NULL). */
    cm_font_face_t *ref = font_face ? cm_font_face_reference(font_face) : NULL;
    if (ctx->font_face) cm_font_face_destroy(ctx->font_face);
    ctx->font_face = ref;
    cm_font_state_invalidate(ctx);
}

cm_font_face_t *cm_get_font_face(cm_context_t *ctx)
{
    if (!ctx) return NULL;
    /* cairo_get_font_face never returns NULL: a context with no explicit face
     * exposes the default toy face ("sans-serif", normal, normal).  Materialise
     * + cache it so repeated calls return the same handle (and so the scaled
     * font derives from a stable face).  The returned handle is borrowed (owned
     * by the context); the caller must reference it to keep it. */
    if (!ctx->font_face) {
        ctx->font_face = cm_toy_font_face_create("sans-serif",
                                                 CM_FONT_SLANT_NORMAL,
                                                 CM_FONT_WEIGHT_NORMAL);
        /* If creation fails, return NULL; the next call retries.  No dirty flag
         * change is needed -- a NULL face means no scaled font can resolve. */
    }
    return ctx->font_face;
}

void cm_set_scaled_font(cm_context_t *ctx, cm_scaled_font_t *scaled_font)
{
    if (!ctx) return;

    /* cairo_set_scaled_font installs a fully-specified scaled font; it also
     * pulls the face / font matrix / options OUT of the scaled font so a later
     * get_font_face / get_font_matrix / get_font_options reflects it, and a
     * subsequent get_scaled_font returns this very object (cache it, NOT dirty). */
    cm_scaled_font_t *ref = scaled_font ? cm_scaled_font_reference(scaled_font)
                                        : NULL;
    if (ctx->scaled_font) cm_scaled_font_destroy(ctx->scaled_font);
    ctx->scaled_font = ref;

    if (ref) {
        /* Sync the discrete font-state fields from the scaled font so the
         * getters agree with it. */
        cm_font_face_t *face = ref->face;
        if (face) {
            cm_font_face_reference(face);
            if (ctx->font_face) cm_font_face_destroy(ctx->font_face);
            ctx->font_face = face;
        }
        ctx->font_matrix = ref->font_matrix;
        if (ref->options) {
            cm_font_options_t *copy = cm_font_options_copy(ref->options);
            if (copy) {
                if (ctx->font_options) cm_font_options_destroy(ctx->font_options);
                ctx->font_options = copy;
            }
        }
        ctx->scaled_font_dirty = false;   /* this scaled font IS current        */
    } else {
        /* Reset: the next get re-derives from face + matrix + options. */
        ctx->scaled_font_dirty = true;
    }
}

cm_scaled_font_t *cm_get_scaled_font(cm_context_t *ctx)
{
    if (!ctx) return NULL;

    /* Lazily (re)derive the scaled font whenever the cache is dirty or absent.
     * The cache is invalidated by any font-state change (above) OR any CTM
     * change (cairo_metal.m / cm_state.c set scaled_font_dirty), so the derived
     * scaled font always reflects the CURRENT face + font matrix + CTM +
     * options -- which is exactly what cairo_get_scaled_font guarantees. */
    if (ctx->scaled_font_dirty || !ctx->scaled_font) {
        if (ctx->scaled_font) {
            cm_scaled_font_destroy(ctx->scaled_font);
            ctx->scaled_font = NULL;
        }
        cm_font_face_t *face = cm_get_font_face(ctx);   /* never NULL on success */
        ctx->scaled_font = cm_scaled_font_create(face, &ctx->font_matrix,
                                                 &ctx->ctm, ctx->font_options);
        ctx->scaled_font_dirty = false;
    }

    /* Resolve (once) the native CTFontRef so metrics/outlines are ready; on a
     * nil-device / no-text build this is a NULL no-op and metrics stay zero. */
    if (ctx->scaled_font) cm_scaled_font_ensure_native(ctx->scaled_font);
    return ctx->scaled_font;
}
