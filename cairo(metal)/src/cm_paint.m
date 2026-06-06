/*
 * cm_paint.m  --  CairoMetal paint sources: uniform packing + gradient LUT bake
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_paint.m"):
 *   - cm_paint_fill_uniforms(): pack a context's paint source into cm_uniforms.
 *     Owns the cairo affine matrix as the vertex-transform uniform, the gradient
 *     axis / radial circle DEVICE-space packing (with the pattern matrix folded
 *     in), the inverse pattern->device rows for the surface/mesh cover frags, and
 *     the appended operator / global_alpha / mask fields.  Handles every
 *     paint kind: SOLID / LINEAR / RADIAL / SURFACE / MESH.
 *   - cm_paint_gradient_lut(): bake a gradient's sorted stops into a 256x1 BGRA8
 *     MTLTexture (the 1D LUT the cover-gradient fragment shaders sample), cached
 *     per-pattern + per-device and rebuilt only when the stops change.  KEPT
 *     gradient-kind-agnostic: it reads stops[] only, so the SAME bake serves both
 *     linear and radial (the shaders differ only in how they map a fragment to t).
 *   - the cm_uniforms _Static_assert ABI lock (below): pins the C-side offsets in
 *     LOCK-STEP with the shaders/fill.metal `cm_uniforms` mirror.
 *
 * Although the module is named ".c" in the contract's prose, baking the LUT
 * creates an MTLTexture (id<MTLTexture>, returned as void*) and folding the
 * pattern matrix needs no Objective-C, but the file is Objective-C (.m) for the
 * texture work.  The pure-C callers (cm_fill.m, cm_compose.m, cairo_metal.m) only
 * ever see the contract's C signatures + opaque void* handles, so nothing leaks.
 *
 * Shader pairing (cm_device.m wires these):
 *     CM_PIPE_COVER_LINEAR   : cm_vs_cover / cm_fs_cover_linear   (samples LUT)
 *     CM_PIPE_COVER_RADIAL   : cm_vs_cover / cm_fs_cover_radial   (samples LUT)
 *     CM_PIPE_COVER_SURFACE  : cm_vs_cover / cm_fs_cover_surface  (samples source)
 *     CM_PIPE_COVER_GOURAUD  : cm_vs_cover_color / cm_fs_cover_gouraud (mesh)
 *     CM_PIPE_COVER_MASK     : cm_vs_cover / cm_fs_mask           (source*maskA)
 *
 * ----------------------------------------------------------------------------
 * COORDINATE FOLD (why the gradient axis is transformed the way it is)
 * ----------------------------------------------------------------------------
 * cairo evaluates a gradient/surface in PATTERN space.  The pattern matrix maps
 *   pattern_matrix : user -> pattern
 * and the CTM maps  user -> device.  A cover fragment arrives in DEVICE space.
 *
 *   - The LINEAR / RADIAL frags project the DEVICE fragment directly against a
 *     DEVICE-space axis/circle (grad_axis).  To get that axis we take the
 *     pattern-space geometry the pattern stores (gradient endpoints / circles are
 *     defined in pattern space) and walk it FORWARD to device:
 *         pattern_space --inv(pattern_matrix)--> user --CTM--> device
 *     i.e. we apply M = CTM * inv(pattern_matrix) to the endpoints/centres and
 *     scale radii by M's max singular value.  Working in pattern space first is
 *     exactly "fold the pattern matrix before the CTM".
 *
 *   - The SURFACE / MASK frags instead sample a texture indexed in PATTERN
 *     (== texel) space, so they need the REVERSE map device -> pattern:
 *         pat_inv = inv(CTM * pattern_matrix)
 *     packed into pat_inv_row0/1 (a 2x3 affine inverse) and applied by the
 *     shader's cm_to_pattern().
 *
 * Both folds guard the pattern-matrix inverse with cm_matrix_invert (a singular
 * pattern matrix flags CM_STATUS_INVALID_MATRIX via cm_set_last_status and we
 * fall back to an identity fold so we never divide by a singular transform).
 *
 * ----------------------------------------------------------------------------
 * PIXEL / PREMULTIPLY CONTRACT (do NOT "fix" -- matches cairo + manim + shaders)
 * ----------------------------------------------------------------------------
 *   The LUT is BGRA8Unorm and is written in the SAME B,G,R,A order manim hands
 *   us (it pre-swaps RGB->BGR before calling add_color_stop_rgba; cm_pattern
 *   stores those bytes verbatim in cm_rgba{r,g,b,a}).  Stops + the solid colour
 *   are stored NON-premultiplied; the cover-{solid,linear,radial,mask} fragment
 *   shaders premultiply after sampling (rgb*=a).  Therefore we interpolate stop
 *   colours in non-premultiplied space and store non-premultiplied texels -- NO
 *   re-swap, NO premultiply here.  SURFACE texels are the EXCEPTION: a cairo
 *   ARGB32 source is ALREADY premultiplied, so cm_fs_cover_surface does NOT
 *   premultiply -- and this file does nothing to the source texels either.
 *
 * ============================================================================
 */

#import <Metal/Metal.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

#include "cm_internal.h"

/* ==========================================================================
 * ABI lock: the Metal `cm_uniforms` struct in shaders/fill.metal mirrors this
 * C `cm_uniforms` field-for-field using scalar arrays (NOT float4) so the byte
 * layout is identical.  These asserts pin the C-side offsets so any future edit
 * to cm_uniforms that would break the shader memcpy fails to compile here.
 *
 * The appended-field offsets are pinned IN LOCK-STEP with the shaders/fill.metal
 * struct mirror (which documents "solid @68, pat rows @84"): solid ends at 84,
 * so pat_inv_row0 starts at 84.  Note the C field is named `operator` while the
 * Metal mirror names it `op` -- both are a 4-byte int at offset 116, so the wire
 * layout is identical; only the source-level identifier differs.
 * ========================================================================== */
_Static_assert(offsetof(cm_uniforms, ctm_row0)   ==  0, "cm_uniforms.ctm_row0");
_Static_assert(offsetof(cm_uniforms, ctm_row1)   == 16, "cm_uniforms.ctm_row1");
_Static_assert(offsetof(cm_uniforms, to_clip)    == 32, "cm_uniforms.to_clip");
_Static_assert(offsetof(cm_uniforms, paint_kind) == 48, "cm_uniforms.paint_kind");
_Static_assert(offsetof(cm_uniforms, grad_axis)  == 52, "cm_uniforms.grad_axis");
_Static_assert(offsetof(cm_uniforms, solid)      == 68, "cm_uniforms.solid");
/* Appended fields (full contract); pinned in LOCK-STEP with the shaders/fill.metal
 * struct mirror.  solid ends at 84, so the new rows start at 84. */
_Static_assert(offsetof(cm_uniforms, pat_inv_row0) ==  84, "cm_uniforms.pat_inv_row0");
_Static_assert(offsetof(cm_uniforms, pat_inv_row1) == 100, "cm_uniforms.pat_inv_row1");
_Static_assert(offsetof(cm_uniforms, operator)     == 116, "cm_uniforms.operator");
_Static_assert(offsetof(cm_uniforms, global_alpha) == 120, "cm_uniforms.global_alpha");
_Static_assert(offsetof(cm_uniforms, mask_axis)    == 124, "cm_uniforms.mask_axis");
_Static_assert(offsetof(cm_uniforms, mask_kind)    == 140, "cm_uniforms.mask_kind");
_Static_assert(sizeof(cm_rgba) == 16, "cm_rgba must be 4 tightly-packed floats");

/* ==========================================================================
 * Coordinate-fold helpers (pure C; no Metal)
 * ========================================================================== */

/* Pack a cairo 2x3 affine into two cm_uniforms float4 rows:
 *   row0 = (xx, xy, x0, 0)   row1 = (yx, yy, y0, 0).
 * This is the layout the shader's cm_to_pattern() / vertex transform expect. */
static inline void
cm_pack_affine_rows(const cm_matrix_t *m, float row0[4], float row1[4])
{
    row0[0] = (float)m->xx; row0[1] = (float)m->xy; row0[2] = (float)m->x0; row0[3] = 0.0f;
    row1[0] = (float)m->yx; row1[1] = (float)m->yy; row1[2] = (float)m->y0; row1[3] = 0.0f;
}

static inline void
cm_pack_identity_rows(float row0[4], float row1[4])
{
    row0[0] = 1.0f; row0[1] = 0.0f; row0[2] = 0.0f; row0[3] = 0.0f;
    row1[0] = 0.0f; row1[1] = 1.0f; row1[2] = 0.0f; row1[3] = 0.0f;
}

/*
 * Build M = ctm * inv(pattern_matrix): the PATTERN-space -> DEVICE-space map for
 * the gradient axis/circle fold.  "fold the pattern matrix BEFORE the CTM" means
 * we undo the pattern matrix (pattern->user) and then apply the CTM (user->dev).
 *
 * cm_matrix_multiply(result, a, b) applies `a` FIRST then `b`, so the composed
 * map (apply inv(pattern), THEN ctm) is multiply(out, inv_pat, ctm).
 *
 * Returns true on success.  If the pattern matrix is singular it flags
 * CM_STATUS_INVALID_MATRIX (the task's "singular -> INVALID_MATRIX" guard) and
 * returns `*out = ctm` (identity fold) so callers still produce a finite axis.
 */
static bool
cm_fold_pattern_to_device(const cm_matrix_t *ctm, const cm_matrix_t *pat_matrix,
                          cm_matrix_t *out)
{
    cm_matrix_t ident;
    if (!ctm) { cm_matrix_identity(&ident); ctm = &ident; }

    if (!pat_matrix) { *out = *ctm; return true; }

    cm_matrix_t inv_pat = *pat_matrix;
    if (cm_matrix_invert(&inv_pat) != CM_STATUS_SUCCESS) {
        cm_set_last_status(CM_STATUS_INVALID_MATRIX);
        *out = *ctm;                 /* identity fold: ignore the singular matrix */
        return false;
    }
    cm_matrix_multiply(out, &inv_pat, ctm);   /* apply inv(pat) first, then ctm */
    return true;
}

/*
 * Build the inverse pattern->device rows for the SURFACE / MASK frags, which
 * index a texture in PATTERN/texel space and therefore need the DEVICE->PATTERN
 * map.  Spelled as compositions (unambiguous; "f then g" = apply f, then g):
 *
 *   pattern_matrix : user    -> pattern        (P)
 *   ctm            : user    -> device         (C)
 *   forward fold   : pattern -> device  =  (P^-1 then C)   == M, the axis fold
 *   pat_inv (here) : device  -> pattern =  (C^-1 then P)   == inv(M)
 *
 * So pat_inv == inv(forward fold).  We reuse cm_fold_pattern_to_device() to build
 * M and then invert it, so there is ONE consistent definition of "pattern space"
 * shared with the gradient-axis fold above.
 *
 * Singular pattern matrix -> cm_fold_pattern_to_device already flagged
 * INVALID_MATRIX and returned M = ctm; if that residual M is itself singular
 * (singular CTM) we flag again and pack identity rows so the shader never divides
 * by a singular transform.
 */
static void
cm_pack_pattern_inverse_rows(const cm_matrix_t *ctm, const cm_matrix_t *pat_matrix,
                             float row0[4], float row1[4])
{
    cm_matrix_t fwd;
    cm_fold_pattern_to_device(ctm, pat_matrix, &fwd);  /* M = ctm*inv(pat) */

    cm_matrix_t inv = fwd;
    if (cm_matrix_invert(&inv) != CM_STATUS_SUCCESS) {
        cm_set_last_status(CM_STATUS_INVALID_MATRIX);
        cm_pack_identity_rows(row0, row1);
        return;
    }
    cm_pack_affine_rows(&inv, row0, row1);
}

/*
 * t-fold for the gradient EXTEND modes (cairo_extend_t).  The cover-gradient
 * shaders project a fragment to a raw parameter t and then clamp to [0,1] with a
 * clamp-to-edge LUT sampler -- which is EXACTLY cairo EXTEND_PAD.  This helper is
 * the single C-side owner of the other modes' wrapping, gradient-kind-agnostic
 * (it folds a scalar t and never looks at stops or axis), so the radial and
 * linear paths share it.  It maps a raw t in (-inf,inf) into the [0,1] LUT
 * domain per the extend mode:
 *
 *     PAD     : clamp(t, 0, 1)                         (already the shader default)
 *     REPEAT  : t - floor(t)                           (saw wave)
 *     REFLECT : triangle wave, period 2                (mirror at each integer)
 *     NONE    : clamp here (the transparent border the true NONE mode paints is
 *               an alpha=0 ring the shader cannot express with a clamp-only
 *               sampler; folding to PAD is the conservative shipping behaviour
 *               until a bordered sampler/quad-discard variant lands -- see the
 *               cross-module seam note at the bottom of this file).
 *
 * Provided for the appended REPEAT/REFLECT cover variants; the SHIPPING
 * cm_fs_cover_linear hard-clamps (PAD), so calling this for PAD is a no-op match.
 * Marked `unused` because no shipping encode path calls it yet (the
 * REPEAT/REFLECT cover variants are appended, not yet wired -- see the seam note
 * at the bottom of this file); the attribute keeps -Werror=unused-function quiet
 * without a runtime constructor or an exported symbol.
 */
__attribute__((unused)) static inline float
cm_extend_fold_t(float t, cm_extend_t extend)
{
    switch (extend) {
        case CM_EXTEND_REPEAT: {
            float f = t - floorf(t);
            return f;
        }
        case CM_EXTEND_REFLECT: {
            float m = fmodf(fabsf(t), 2.0f);   /* [0,2) */
            return (m > 1.0f) ? (2.0f - m) : m;
        }
        case CM_EXTEND_NONE:
        case CM_EXTEND_PAD:
        default:
            if (t <= 0.0f) return 0.0f;
            if (t >= 1.0f) return 1.0f;
            return t;
    }
}

/* ==========================================================================
 * cm_paint_fill_uniforms
 * --------------------------------------------------------------------------
 * Fill the PAINT-related fields of `out` from a context source.  We own + write:
 *   - ctm_row0 / ctm_row1 : the cairo 2x3 affine, packed as the vertex-transform
 *                           uniform.
 *   - paint_kind          : CM_PAINT_SOLID / LINEAR / RADIAL / SURFACE / MESH.
 *   - solid               : solid colour (B,G,R,A, non-premultiplied); also the
 *                           SOURCE colour the mask frag multiplies by mask-alpha.
 *   - grad_axis           : LINEAR -> device endpoints (ax,ay,bx,by);
 *                           RADIAL -> device outer circle (cx1,cy1,r1,_).
 *   - pat_inv_row0/1      : inv(ctm*pattern_matrix) for SURFACE/MASK device->pat.
 *   - operator            : default CM_OPERATOR_OVER (the encode path that honors
 *                           set_operator overwrites this; see the seam note).
 *   - global_alpha        : default 1.0 (paint_with_alpha / group opacity is
 *                           applied by the compose path which overwrites this).
 *   - mask_axis / mask_kind: zeroed / SOLID by default (cm_compose_mask fills
 *                           these when compositing through a mask pattern).
 *
 * We do NOT touch `out->to_clip`: that maps device px -> clip space and is a
 * function of the SURFACE size, not the paint source, so the fill/frame encoder
 * owns it (and may set it before OR after this call without us clobbering it).
 *
 * `operator` / `global_alpha` / `mask_*` are likewise NOT derivable from `src`
 * (they live on the context gstate, not the source), so we write deterministic
 * DEFAULTS and leave the owning encoder (cm_compose.m / cm_fill.m) free to
 * overwrite them after this call -- the exact same "caller owns it" arrangement
 * as to_clip.
 * ========================================================================== */
void
cm_paint_fill_uniforms(const cm_source *src, const cm_matrix_t *ctm,
                       cm_uniforms *out)
{
    if (!out) return;

    /* --- cairo affine -> vertex transform uniform (2x3, two float4 rows) --- */
    if (ctm) {
        cm_pack_affine_rows(ctm, out->ctm_row0, out->ctm_row1);
    } else {
        cm_pack_identity_rows(out->ctm_row0, out->ctm_row1);
    }

    /* --- appended scalar defaults (caller may overwrite; see header) --- */
    out->operator     = CM_OPERATOR_OVER;
    out->global_alpha = 1.0f;
    out->mask_kind    = CM_PAINT_SOLID;
    out->mask_axis[0] = out->mask_axis[1] = 0.0f;
    out->mask_axis[2] = out->mask_axis[3] = 0.0f;

    /* Defaults for the gradient/surface fields; specialised below per kind. */
    out->grad_axis[0] = out->grad_axis[1] = 0.0f;
    out->grad_axis[2] = out->grad_axis[3] = 0.0f;
    cm_pack_identity_rows(out->pat_inv_row0, out->pat_inv_row1);

    if (!src) {
        /* cairo default source: opaque black, solid. */
        out->paint_kind = CM_PAINT_SOLID;
        out->solid.r = 0.0f; out->solid.g = 0.0f;
        out->solid.b = 0.0f; out->solid.a = 1.0f;
        return;
    }

    /* ----------------------------------------------------------------------
     * LINEAR gradient: project a DEVICE fragment onto a DEVICE-space axis.
     * Fold the pattern matrix (work in pattern space), then the CTM:
     *     device_endpoint = (ctm * inv(pattern_matrix)) * pattern_endpoint
     * ---------------------------------------------------------------------- */
    if (src->kind == CM_PAINT_LINEAR && src->pattern) {
        const cm_pattern_t *pat = src->pattern;
        out->paint_kind = CM_PAINT_LINEAR;

        cm_matrix_t fold;
        cm_fold_pattern_to_device(ctm, &pat->matrix, &fold);   /* ctm*inv(pat) */

        double ax, ay, bx, by;
        cm_matrix_apply(&fold, pat->x0, pat->y0, &ax, &ay);
        cm_matrix_apply(&fold, pat->x1, pat->y1, &bx, &by);
        out->grad_axis[0] = (float)ax;
        out->grad_axis[1] = (float)ay;
        out->grad_axis[2] = (float)bx;
        out->grad_axis[3] = (float)by;

        /* pat_inv (device->pattern) is unused by the linear frag but kept
         * consistent so a future linear-in-pattern-space variant or a debug
         * read is well-defined rather than identity-by-accident. */
        cm_pack_pattern_inverse_rows(ctm, &pat->matrix,
                                     out->pat_inv_row0, out->pat_inv_row1);

        /* solid unused for gradients; zero it for determinism. */
        out->solid.r = out->solid.g = out->solid.b = out->solid.a = 0.0f;
        return;
    }

    /* ----------------------------------------------------------------------
     * RADIAL gradient: the scaffold cm_fs_cover_radial samples the LUT by
     *     d = clamp(length(dev - c1) / r1, 0, 1)
     * so grad_axis carries the DEVICE-space OUTER circle (cx1, cy1, r1, _).
     * Fold the pattern matrix on the circle: the centre transforms as a point,
     * the radius scales by the device-per-pattern max scale of the fold.
     * ---------------------------------------------------------------------- */
    if (src->kind == CM_PAINT_RADIAL && src->pattern) {
        const cm_pattern_t *pat = src->pattern;
        out->paint_kind = CM_PAINT_RADIAL;

        cm_matrix_t fold;
        cm_fold_pattern_to_device(ctm, &pat->matrix, &fold);   /* ctm*inv(pat) */

        double cx1, cy1;
        cm_matrix_apply(&fold, pat->radial.cx1, pat->radial.cy1, &cx1, &cy1);
        double rscale = cm_matrix_max_scale(&fold);
        double r1 = pat->radial.r1 * rscale;

        out->grad_axis[0] = (float)cx1;
        out->grad_axis[1] = (float)cy1;
        out->grad_axis[2] = (float)r1;
        out->grad_axis[3] = 0.0f;

        cm_pack_pattern_inverse_rows(ctm, &pat->matrix,
                                     out->pat_inv_row0, out->pat_inv_row1);

        out->solid.r = out->solid.g = out->solid.b = out->solid.a = 0.0f;
        return;
    }

    /* ----------------------------------------------------------------------
     * SURFACE (and RASTER, which routes through SURFACE): the cover-surface
     * frag samples a texture indexed in PATTERN/texel space, so pack the
     * device->pattern inverse rows.  Texels are ALREADY premultiplied, so we
     * deliberately leave `solid` untouched-as-zero (the shader never reads it)
     * and do NOTHING that would imply a non-premultiplied source.
     * ---------------------------------------------------------------------- */
    if (src->kind == CM_PAINT_SURFACE && src->pattern) {
        const cm_pattern_t *pat = src->pattern;
        out->paint_kind = CM_PAINT_SURFACE;

        cm_pack_pattern_inverse_rows(ctm, &pat->matrix,
                                     out->pat_inv_row0, out->pat_inv_row1);

        /* solid is unused (premultiplied texels); zero for determinism. */
        out->solid.r = out->solid.g = out->solid.b = out->solid.a = 0.0f;
        return;
    }

    /* ----------------------------------------------------------------------
     * MESH: colour comes from the per-vertex Gouraud stream (cm_mesh.c emits
     * cm_vtx_color through cm_vs_cover_color / cm_fs_cover_gouraud), NOT from
     * these uniforms.  We still report the kind and pass inv(CTM) as the
     * pattern inverse (mesh control points are authored in pattern space; for a
     * mesh the pattern matrix folds the same way -- the Gouraud verts are
     * already pre-transformed CPU-side, so this is purely informational).
     * ---------------------------------------------------------------------- */
    if (src->kind == CM_PAINT_MESH && src->pattern) {
        const cm_pattern_t *pat = src->pattern;
        out->paint_kind = CM_PAINT_MESH;

        cm_pack_pattern_inverse_rows(ctm, &pat->matrix,
                                     out->pat_inv_row0, out->pat_inv_row1);

        out->solid.r = out->solid.g = out->solid.b = out->solid.a = 0.0f;
        return;
    }

    /* ----------------------------------------------------------------------
     * Solid source (CM_PAINT_SOLID, or a pattern kind with a NULL pattern).
     * Passthrough B,G,R,A non-premultiplied; the shader premultiplies.
     * ---------------------------------------------------------------------- */
    out->paint_kind = CM_PAINT_SOLID;
    out->solid = src->solid;
}

/* ==========================================================================
 * Gradient 1D LUT bake + per-pattern cache  (gradient-kind-agnostic)
 * ==========================================================================
 *
 * cm_pattern (cm_internal.h) intentionally has NO slot for a cached texture
 * (its layout is shared with the other modules and must not change), so the
 * cache lives here as a small side table keyed by (pattern pointer, device).
 *
 * KEPT gradient-kind-agnostic: the bake reads stops[] + stop_count ONLY (never
 * the axis or circles), so a single 256x1 LUT serves BOTH linear and radial
 * patterns -- the cover shaders differ only in how they map a fragment to the
 * t coordinate they sample with.
 *
 * Invalidation: a 64-bit signature over (stop_count + every stop's offset and
 * colour) is stored alongside the texture.  cm_paint_gradient_lut rebuilds when
 * the signature OR the device differs, so edited stops always re-bake and a
 * reused pattern pointer with different contents never returns a stale LUT.
 *
 * Lifetime: there is no destroy hook on cm_pattern, so a freed pattern's slot
 * is reclaimed lazily -- when the table is full a new pattern overwrites the
 * oldest slot (releasing that slot's texture).  CM_PAINT_CACHE_CAP is far above
 * the handful of gradients manim creates, so eviction is effectively never hit
 * in practice; it only bounds worst-case memory.  All access is mutex-guarded
 * because patterns may be baked from different context threads.
 * ========================================================================== */

#define CM_PAINT_CACHE_CAP 64

typedef struct {
    const cm_pattern_t *pat;   /* identity key (pointer)                     */
    cm_device          *dev;   /* device the texture belongs to              */
    uint64_t            sig;    /* stop signature; 0 == empty slot           */
    uint64_t            seq;    /* insertion order, for oldest-slot eviction */
    void               *tex;    /* id<MTLTexture> (retained), 256x1 BGRA8     */
} cm_lut_entry;

static cm_lut_entry    g_lut_cache[CM_PAINT_CACHE_CAP];
static uint64_t        g_lut_seq = 1;
static pthread_mutex_t g_lut_mtx = PTHREAD_MUTEX_INITIALIZER;

/* FNV-1a over the stops, so any change to count/offset/colour re-bakes.
 * Never returns 0 (0 is the empty-slot sentinel). */
static uint64_t
cm_grad_signature(const cm_pattern_t *pat)
{
    uint64_t h = 1469598103934665603ULL;  /* FNV offset basis */
    const unsigned char *bytes;
    size_t n;

    uint32_t count = pat->stop_count;
    bytes = (const unsigned char *)&count;
    for (n = 0; n < sizeof(count); ++n) { h ^= bytes[n]; h *= 1099511628211ULL; }

    for (uint32_t i = 0; i < pat->stop_count && i < CM_MAX_STOPS; ++i) {
        const cm_grad_stop *s = &pat->stops[i];
        bytes = (const unsigned char *)&s->offset;
        for (n = 0; n < sizeof(s->offset); ++n) { h ^= bytes[n]; h *= 1099511628211ULL; }
        bytes = (const unsigned char *)&s->color;
        for (n = 0; n < sizeof(s->color); ++n) { h ^= bytes[n]; h *= 1099511628211ULL; }
    }
    return h ? h : 1ULL;
}

/* clamp a float colour component in [0,1] and quantize to 8-bit. */
static inline uint8_t
cm_unorm8(float v)
{
    if (v <= 0.0f) return 0;
    if (v >= 1.0f) return 255;
    return (uint8_t)(v * 255.0f + 0.5f);
}

/*
 * Bake the sorted stops into CM_GRAD_LUT_SIZE BGRA8 texels.
 *
 * The texel byte order is B,G,R,A to match BGRA8Unorm.  cm_rgba already holds
 * manim's pre-swapped channels: .r is the B byte, .g is G, .b is R, .a is A.
 * (See the file-header pixel contract.)  Colours are interpolated in
 * NON-premultiplied space and stored non-premultiplied; the cover-gradient
 * fragment shaders premultiply after sampling.
 *
 * Stop handling matches cairo's EXTEND_PAD default: offsets are sorted and
 * clamped to [0,1], samples below the first / above the last stop take the end
 * colour, and the LUT row maps t in [0,1] across the 256 texels (the shader's
 * clamp-to-edge sampler + clamp(t) reproduce PAD at the ends).  REPEAT/REFLECT
 * are a wrap of the SAMPLE coordinate t (cm_extend_fold_t), not of the bake, so
 * this routine stays extend-agnostic too.
 */
static void
cm_bake_lut_bgra(const cm_pattern_t *pat, uint8_t out[CM_GRAD_LUT_SIZE * 4])
{
    /* Copy + sort stops by offset (insertion sort; <=32 stops, stable enough).
     * Offsets are clamped into [0,1] like cairo before sorting. */
    cm_grad_stop stops[CM_MAX_STOPS];
    uint32_t ns = pat->stop_count;
    if (ns > CM_MAX_STOPS) ns = CM_MAX_STOPS;

    for (uint32_t i = 0; i < ns; ++i) {
        stops[i] = pat->stops[i];
        if (stops[i].offset < 0.0) stops[i].offset = 0.0;
        if (stops[i].offset > 1.0) stops[i].offset = 1.0;
    }
    for (uint32_t i = 1; i < ns; ++i) {
        cm_grad_stop key = stops[i];
        int32_t j = (int32_t)i - 1;
        while (j >= 0 && stops[j].offset > key.offset) {
            stops[j + 1] = stops[j];
            --j;
        }
        stops[j + 1] = key;
    }

    /* No stops -> cairo renders nothing for the pattern; produce transparent
     * black so the (premultiplied) result is fully transparent. */
    if (ns == 0) {
        memset(out, 0, CM_GRAD_LUT_SIZE * 4);
        return;
    }
    /* One stop -> constant colour across the whole LUT. */
    if (ns == 1) {
        uint8_t b = cm_unorm8(stops[0].color.r);
        uint8_t g = cm_unorm8(stops[0].color.g);
        uint8_t r = cm_unorm8(stops[0].color.b);
        uint8_t a = cm_unorm8(stops[0].color.a);
        for (uint32_t i = 0; i < CM_GRAD_LUT_SIZE; ++i) {
            out[i * 4 + 0] = b;
            out[i * 4 + 1] = g;
            out[i * 4 + 2] = r;
            out[i * 4 + 3] = a;
        }
        return;
    }

    /* Walk the texels, advancing a stop cursor; interpolate between bracketing
     * stops in non-premultiplied space. */
    uint32_t seg = 0;  /* current segment is [stops[seg], stops[seg+1]] */
    for (uint32_t i = 0; i < CM_GRAD_LUT_SIZE; ++i) {
        double t = (double)i / (double)(CM_GRAD_LUT_SIZE - 1);

        /* advance to the segment containing t */
        while (seg + 1 < ns - 1 && t > stops[seg + 1].offset) ++seg;

        const cm_grad_stop *s0 = &stops[seg];
        const cm_grad_stop *s1 = &stops[seg + 1];

        double fr;
        if (t <= s0->offset) {
            fr = 0.0;                       /* PAD below first / at left edge */
        } else if (t >= s1->offset) {
            fr = 1.0;                       /* PAD above last / at right edge */
        } else {
            double span = s1->offset - s0->offset;
            fr = (span > 1e-12) ? (t - s0->offset) / span : 0.0;
        }

        float cr = (float)(s0->color.r + (s1->color.r - s0->color.r) * fr);
        float cg = (float)(s0->color.g + (s1->color.g - s0->color.g) * fr);
        float cb = (float)(s0->color.b + (s1->color.b - s0->color.b) * fr);
        float ca = (float)(s0->color.a + (s1->color.a - s0->color.a) * fr);

        out[i * 4 + 0] = cm_unorm8(cr);   /* B */
        out[i * 4 + 1] = cm_unorm8(cg);   /* G */
        out[i * 4 + 2] = cm_unorm8(cb);   /* R */
        out[i * 4 + 3] = cm_unorm8(ca);   /* A */
    }
}

/* Create the 256x1 BGRA8 MTLTexture and upload `texels`. Returns a +1 retained
 * id<MTLTexture> as void*, or NULL on failure. */
static void *
cm_make_lut_texture(cm_device *dev, const uint8_t *texels)
{
    id<MTLDevice> mtl = (__bridge id<MTLDevice>)cm_device_mtl(dev);
    if (!mtl) return NULL;

    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:CM_GRAD_LUT_SIZE
                                    height:1
                                 mipmapped:NO];
    desc.usage         = MTLTextureUsageShaderRead;
    desc.storageMode   = MTLStorageModeShared;   /* CPU-uploaded, GPU-sampled */
    desc.textureType   = MTLTextureType2D;

    id<MTLTexture> tex = [mtl newTextureWithDescriptor:desc];
    if (!tex) return NULL;

    [tex replaceRegion:MTLRegionMake2D(0, 0, CM_GRAD_LUT_SIZE, 1)
           mipmapLevel:0
             withBytes:texels
           bytesPerRow:CM_GRAD_LUT_SIZE * 4];

    /* Hand back an owning reference (released in eviction / cm_paint_cache_shutdown).
     * CFBridgingRetain balances a CFRelease on the void* later. */
    return (void *)CFBridgingRetain(tex);
}

static void
cm_release_tex(void *tex)
{
    if (tex) CFRelease(tex);   /* balances CFBridgingRetain */
}

/* ==========================================================================
 * cm_paint_gradient_lut  (public to the other modules via cm_internal.h)
 * ========================================================================== */
void *
cm_paint_gradient_lut(cm_device *dev, cm_pattern_t *pat)
{
    if (!dev || !pat) return NULL;

    uint64_t sig = cm_grad_signature(pat);

    pthread_mutex_lock(&g_lut_mtx);

    /* 1) Look for a live entry for this pattern. */
    cm_lut_entry *slot = NULL;
    for (int i = 0; i < CM_PAINT_CACHE_CAP; ++i) {
        if (g_lut_cache[i].pat == pat && g_lut_cache[i].sig != 0) {
            slot = &g_lut_cache[i];
            break;
        }
    }

    if (slot) {
        if (slot->sig == sig && slot->dev == dev && slot->tex) {
            /* Cache hit, stops + device unchanged: reuse. Bump LRU sequence. */
            slot->seq = g_lut_seq++;
            void *tex = slot->tex;
            pthread_mutex_unlock(&g_lut_mtx);
            return tex;
        }
        /* Stale (stops edited or different device): drop the old texture and
         * rebuild into the same slot below. */
        cm_release_tex(slot->tex);
        slot->tex = NULL;
    } else {
        /* 2) No entry: take a free slot, else evict the oldest. */
        cm_lut_entry *oldest = &g_lut_cache[0];
        for (int i = 0; i < CM_PAINT_CACHE_CAP; ++i) {
            if (g_lut_cache[i].sig == 0) { slot = &g_lut_cache[i]; break; }
            if (g_lut_cache[i].seq < oldest->seq) oldest = &g_lut_cache[i];
        }
        if (!slot) {
            slot = oldest;
            cm_release_tex(slot->tex);   /* evict */
            slot->tex = NULL;
        }
    }

    /* 3) Bake + upload. */
    uint8_t texels[CM_GRAD_LUT_SIZE * 4];
    cm_bake_lut_bgra(pat, texels);

    void *tex = NULL;
    @autoreleasepool {
        tex = cm_make_lut_texture(dev, texels);
    }
    if (!tex) {
        /* Leave the slot empty on failure so a later call retries. */
        slot->pat = NULL;
        slot->sig = 0;
        slot->dev = NULL;
        slot->tex = NULL;
        pthread_mutex_unlock(&g_lut_mtx);
        return NULL;
    }

    slot->pat = pat;
    slot->dev = dev;
    slot->sig = sig;
    slot->seq = g_lut_seq++;
    slot->tex = tex;

    pthread_mutex_unlock(&g_lut_mtx);
    return tex;
}

/* Optional teardown: release every cached LUT texture.  Not in the public
 * contract; provided so a device/process teardown path (cm_device_destroy) can
 * avoid leaking the cached textures if it chooses to call it.  Safe to call
 * multiple times. */
void
cm_paint_cache_shutdown(void)
{
    pthread_mutex_lock(&g_lut_mtx);
    for (int i = 0; i < CM_PAINT_CACHE_CAP; ++i) {
        cm_release_tex(g_lut_cache[i].tex);
        g_lut_cache[i].tex = NULL;
        g_lut_cache[i].pat = NULL;
        g_lut_cache[i].dev = NULL;
        g_lut_cache[i].sig = 0;
        g_lut_cache[i].seq = 0;
    }
    pthread_mutex_unlock(&g_lut_mtx);
}
