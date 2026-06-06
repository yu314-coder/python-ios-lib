/*
 * cm_text.m  --  CairoMetal CoreText glyph-outline source + shaping + metrics
 * ============================================================================
 *
 * MODULE OWNER of the rendered-text path (cm_internal.h, "MODULE: cm_text.m").
 *
 * The WHOLE rendered-text path routes through GLYPH-OUTLINE -> the EXISTING
 * cm_fill_encode (NONZERO).  There is NO new shader, NO new pipeline / DSS, and
 * NOTHING is added to cm_device.m: a glyph is just a closed sub-path soup that
 * the stencil-then-cover fill already rasterizes correctly.
 *
 *   glyph -> CTFontCreatePathForGlyph -> CGPathRef -> CGPathApply -> cm_path
 *
 * The CGPathApply walker (cm__glyph_apply) lowers CoreText path elements into
 * the cm_path recorder, ELEVATING quadratics to cubics with the standard rule
 *   c1 = p0 + 2/3 (q - p0)      c2 = p3 + 2/3 (q - p3)
 * and flipping CoreText's up-y em space into cairo's down-y user space.
 *
 * COORDINATE / TRANSFORM MODEL  (matches the cairo-quartz backend)
 * ----------------------------------------------------------------------------
 * cairo's font_matrix maps GLYPH (em) space -> USER space.  We build the CTFont
 * at a UNIT point size (1.0) so its glyph outlines + metrics come out in em
 * units (1 em == 1.0), then apply the full font_matrix ourselves.  CoreText em
 * space is y-UP; cairo user space is y-DOWN, so the glyph->user transform is
 *
 *     M = translate(pen_x, pen_y) . font_matrix . flipY      (flipY = diag(1,-1))
 *
 * expressed as a CGAffineTransform and handed to CTFontCreatePathForGlyph, which
 * "reflects the font point size, matrix, and transform parameter, in that
 * order" -- so the points delivered to the applier are ALREADY in user space,
 * cairo down-y, offset to the pen.  We therefore append outlines in USER space
 * (NOT device space): the CTM is applied later by cm_path_flatten at fill time,
 * exactly like every other path, so a gradient/surface source used as the text
 * paint projects through the CTM correctly (DESIGN: append in user space).
 *
 * Metrics (text_extents / glyph_extents / font_extents) come from
 * CTFontGetAdvancesForGlyphs / CTFontGetBoundingRectsForGlyphs / Ascent /
 * Descent / Leading on the unit-size font, then transformed by font_matrix into
 * user space (with the y-flip so a CoreText y-up bbox becomes a cairo y-down
 * bearing).  Shaping (text_to_glyphs) uses CTFontGetGlyphsForCharacters over
 * the UTF-8 -> UTF-16 decode and lays glyphs out left-to-right by advance.
 *
 * OWNERSHIP / THREADING
 * ----------------------------------------------------------------------------
 * The native handle is a CTFontRef stored as void*.  cm_text_resolve_native /
 * cm_text_resolve_toy_face RETURN A RETAINED CTFontRef the caller must release
 * with cm_text_release_native (CFRelease).  The public context entry points
 * resolve the context's scaled font, use it, and release it within the call;
 * the cm_scaled_font cache slot (sf->native) is owned by cm_font.c and released
 * in cm_scaled_font_destroy via cm_text_release_native.  All internal helpers
 * are NULL-tolerant: a NULL native_font falls back to a default system font so
 * a metric query never returns garbage even if a cache slot was never primed.
 *
 * ASCII-clean (project rule).  Links CoreText + CoreGraphics.
 * ============================================================================
 */

#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ==========================================================================
 * cm_matrix_t <-> CGAffineTransform
 * --------------------------------------------------------------------------
 * cairo_matrix_t is (xx,yx, xy,yy, x0,y0):  x' = xx*x + xy*y + x0,
 *                                           y' = yx*x + yy*y + y0.
 * CGAffineTransform is (a,b, c,d, tx,ty):   x' = a*x + c*y + tx,
 *                                           y' = b*x + d*y + ty.
 * The field mapping is therefore a=xx, b=yx, c=xy, d=yy, tx=x0, ty=y0.
 * ========================================================================== */
static inline CGAffineTransform cm__cg_from_matrix(const cm_matrix_t *m)
{
    return CGAffineTransformMake((CGFloat)m->xx, (CGFloat)m->yx,
                                 (CGFloat)m->xy, (CGFloat)m->yy,
                                 (CGFloat)m->x0, (CGFloat)m->y0);
}

/* Transform a distance/vector (no translation) by a cm_matrix_t. */
static inline void cm__matrix_xform_dist(const cm_matrix_t *m,
                                         double x, double y,
                                         double *ox, double *oy)
{
    *ox = m->xx * x + m->xy * y;
    *oy = m->yx * x + m->yy * y;
}

/* ==========================================================================
 * Toy-face family -> CTFontRef resolution
 * --------------------------------------------------------------------------
 * Build a unit-size (1.0 pt) CTFont for the toy face's family + slant + weight.
 * Slant/weight are applied as symbolic traits via a CTFontDescriptor so a plain
 * family name like "sans-serif" still gets bold / italic when asked.  The
 * common CSS-ish generic families are mapped to a concrete system family so
 * CoreText resolves them (it does not understand "sans-serif").
 * ========================================================================== */

static CFStringRef cm__family_to_cf(const char *family)
{
    /* Map the CSS generic families manim/cairo toy faces use to concrete
     * system families CoreText resolves; pass anything else through verbatim. */
    const char *name = (family && family[0]) ? family : "sans-serif";
    if (strcmp(name, "sans-serif") == 0 || strcmp(name, "sans") == 0)
        name = "Helvetica";
    else if (strcmp(name, "serif") == 0)
        name = "Times New Roman";
    else if (strcmp(name, "monospace") == 0 || strcmp(name, "mono") == 0)
        name = "Courier New";
    else if (strcmp(name, "cursive") == 0)
        name = "Snell Roundhand";
    else if (strcmp(name, "fantasy") == 0)
        name = "Papyrus";
    return CFStringCreateWithCString(kCFAllocatorDefault, name,
                                     kCFStringEncodingUTF8);
}

/* Create a unit-size CTFontRef for (family, slant, weight).  Retained; the
 * caller releases via cm_text_release_native.  Returns NULL only on hard
 * allocation failure (CFStringCreate / descriptor build). */
static CTFontRef cm__ctfont_for_toy(const char *family,
                                    cm_font_slant_t slant,
                                    cm_font_weight_t weight)
{
    CFStringRef cf_family = cm__family_to_cf(family);
    if (!cf_family) return NULL;

    /* Desired symbolic traits from slant + weight. */
    CTFontSymbolicTraits want = 0;
    if (slant == CM_FONT_SLANT_ITALIC || slant == CM_FONT_SLANT_OBLIQUE)
        want |= kCTFontTraitItalic;
    if (weight == CM_FONT_WEIGHT_BOLD)
        want |= kCTFontTraitBold;

    /* Base font at unit size, no matrix (we apply font_matrix ourselves). */
    CTFontRef base = CTFontCreateWithName(cf_family, 1.0, NULL);
    CFRelease(cf_family);
    if (!base) {
        /* Last resort: the system font so text still renders. */
        return CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 1.0, NULL);
    }
    if (want == 0)
        return base;   /* no traits requested -> base is exactly right */

    /* Ask CoreText for a sibling that adds the requested traits.  If the family
     * has no such variant CTFontCreateCopyWithSymbolicTraits returns NULL and we
     * keep the base face (cairo's toy font face is best-effort about styling). */
    CTFontRef styled = CTFontCreateCopyWithSymbolicTraits(base, 1.0, NULL,
                                                          want, want);
    if (styled) { CFRelease(base); return styled; }
    return base;
}

/* ==========================================================================
 * Native resolution entry points (cm_internal.h contract)
 * ========================================================================== */

void *cm_text_resolve_toy_face(cm_font_face_t *face,
                               const cm_matrix_t *font_matrix,
                               const cm_matrix_t *ctm)
{
    /* The font_matrix / ctm carry the scale; we bake them into the OUTLINE
     * transform at draw time (cm_text_append_glyph_outline), so the CTFont
     * itself is built at unit size here.  Only the family + style select the
     * face.  (font_matrix/ctm are accepted to satisfy the contract and to allow
     * a future hinting path that needs the device scale.) */
    (void)font_matrix; (void)ctm;

    /* A file-loaded face (cm_ft_font_face_create_for_path) carries its OWN native
     * CTFontRef built from the font file: return a retained copy so its real
     * glyphs render through this same CoreText path (the toy resolution below is
     * only for toy faces).  Retain because the caller releases via
     * cm_text_release_native and the face keeps its own reference. */
    if (face) {
        CTFontRef stored = (CTFontRef)cm_font_face_native_font(face);
        if (stored) { CFRetain(stored); return (void *)stored; }
    }

    const char     *family = NULL;
    cm_font_slant_t  slant = CM_FONT_SLANT_NORMAL;
    cm_font_weight_t weight = CM_FONT_WEIGHT_NORMAL;

    if (face && cm_font_face_get_type(face) == CM_FONT_TYPE_TOY) {
        family = cm_toy_font_face_get_family(face);
        slant  = cm_toy_font_face_get_slant(face);
        weight = cm_toy_font_face_get_weight(face);
    }
    return (void *)cm__ctfont_for_toy(family, slant, weight);
}

/* Load a unit-size CTFontRef from a font FILE on disk (TTF/OTF/TTC/...).  Uses
 * CoreText's font-descriptor-from-URL loader so it needs no FreeType: the file's
 * real glyph outlines + metrics then flow through the SAME CoreText path as toy
 * faces.  `index` selects a face within a collection; out-of-range falls back to
 * the first descriptor.  Returns a RETAINED CTFontRef (release via
 * cm_text_release_native) or NULL if the file is missing / not a font. */
void *cm_text_ctfont_from_path(const char *path, int index)
{
    if (!path || !path[0]) return NULL;
    @autoreleasepool {
        CFStringRef cf = CFStringCreateWithCString(kCFAllocatorDefault, path,
                                                   kCFStringEncodingUTF8);
        if (!cf) return NULL;
        CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cf,
                                                     kCFURLPOSIXPathStyle, false);
        CFRelease(cf);
        if (!url) return NULL;

        CFArrayRef descs = CTFontManagerCreateFontDescriptorsFromURL(url);
        CFRelease(url);
        if (!descs) return NULL;
        CFIndex n = CFArrayGetCount(descs);
        if (n <= 0) { CFRelease(descs); return NULL; }

        CFIndex pick = (index >= 0 && index < n) ? (CFIndex)index : 0;
        CTFontDescriptorRef desc =
            (CTFontDescriptorRef)CFArrayGetValueAtIndex(descs, pick);
        /* Unit size, no matrix (the font_matrix is applied to outlines/metrics by
         * the callers, exactly as for toy faces). */
        CTFontRef font = desc ? CTFontCreateWithFontDescriptor(desc, 1.0, NULL)
                              : NULL;
        CFRelease(descs);
        return (void *)font;   /* retained (+1) or NULL */
    }
}

void *cm_text_resolve_native(cm_scaled_font_t *scaled_font)
{
    if (!scaled_font) return NULL;
    /* Resolve from the scaled font's PUBLIC getters (the struct body lives in
     * cm_font.c and is opaque here).  The CTFont is unit-size; the font_matrix
     * is applied to outlines/metrics by the callers. */
    cm_font_face_t *face = cm_scaled_font_get_font_face(scaled_font);
    cm_matrix_t fm, ctm;
    cm_scaled_font_get_font_matrix(scaled_font, &fm);
    cm_scaled_font_get_ctm(scaled_font, &ctm);
    return cm_text_resolve_toy_face(face, &fm, &ctm);
}

void cm_text_release_native(void *native_font)
{
    if (native_font) CFRelease((CTFontRef)native_font);
}

/* Ensure we have SOME CTFontRef to query.  If `native` is non-NULL it is
 * borrowed (NOT retained, NOT released by us).  If it is NULL we create a
 * unit-size system font and set *owned=true so the caller releases it.  Returns
 * NULL only if even the fallback could not be created. */
static CTFontRef cm__borrow_or_default(void *native, bool *owned)
{
    *owned = false;
    if (native) return (CTFontRef)native;
    CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 1.0, NULL);
    if (f) *owned = true;
    return f;
}

/* ==========================================================================
 * Glyph outline walk:  CGPath -> cm_path  (quad->cubic, points already in
 * USER space + cairo down-y because the outline transform was baked into
 * CTFontCreatePathForGlyph's matrix argument).
 * ========================================================================== */

typedef struct {
    cm_path *path;       /* destination recorder                          */
    bool     open;       /* a sub-path is currently open (needs close)    */
} cm__glyph_sink;

/* CGPathApply callback.  CoreText delivers points already transformed by the
 * matrix we passed, so they are in cm user space (down-y); append verbatim. */
static void cm__glyph_apply(void *info, const CGPathElement *e)
{
    cm__glyph_sink *s = (cm__glyph_sink *)info;
    const CGPoint  *p = e->points;

    switch (e->type) {
    case kCGPathElementMoveToPoint:
        /* A new contour: close the previous one first so each glyph contour is
         * an independent closed loop (fill always closes; closing also keeps
         * the recorded stream matching cairo's glyph_path). */
        if (s->open) cm_path_close(s->path);
        cm_path_move_to(s->path, p[0].x, p[0].y);
        s->open = true;
        break;

    case kCGPathElementAddLineToPoint:
        cm_path_line_to(s->path, p[0].x, p[0].y);
        break;

    case kCGPathElementAddQuadCurveToPoint: {
        /* Quadratic (control q = p[0], end p3 = p[1]) elevated to a cubic.
         * The cubic that exactly represents the quadratic uses
         *   c1 = p0 + 2/3 (q - p0)      c2 = p3 + 2/3 (q - p3).
         * p0 is the current point of the recorder. */
        double p0x, p0y;
        cm_path_get_current_point(s->path, &p0x, &p0y);
        double qx = p[0].x, qy = p[0].y;     /* quad control */
        double p3x = p[1].x, p3y = p[1].y;   /* quad end     */
        double c1x = p0x + (2.0 / 3.0) * (qx - p0x);
        double c1y = p0y + (2.0 / 3.0) * (qy - p0y);
        double c2x = p3x + (2.0 / 3.0) * (qx - p3x);
        double c2y = p3y + (2.0 / 3.0) * (qy - p3y);
        cm_path_curve_to(s->path, c1x, c1y, c2x, c2y, p3x, p3y);
        break;
    }

    case kCGPathElementAddCurveToPoint:
        /* Already cubic: control1 = p[0], control2 = p[1], end = p[2]. */
        cm_path_curve_to(s->path, p[0].x, p[0].y, p[1].x, p[1].y,
                                  p[2].x, p[2].y);
        break;

    case kCGPathElementCloseSubpath:
        cm_path_close(s->path);
        s->open = false;
        break;

    default:
        break;
    }
}

void cm_text_append_glyph_outline(void *native_font, unsigned long glyph,
                                  double x, double y, cm_path *path)
{
    if (!path) return;

    bool owned = false;
    CTFontRef font = cm__borrow_or_default(native_font, &owned);
    if (!font) return;

    /* This bare-native entry receives only the CTFont + a pen offset, with NO
     * font_matrix, so it bakes the em-magnitude itself: the CTFont's own point
     * size already scales the path (cm_text_resolve_* build it at unit size, so
     * em == 1 user unit here), and we apply only flipY (CoreText y-up em ->
     * cairo y-down) + the pen translation.  The PUBLIC draw/path paths do NOT
     * funnel through here; they call cm__append_glyph_xform with the real
     * translate . font_matrix . flipY composite so a non-unit font size / shear
     * is honored.  This helper exists to satisfy the cm_internal.h contract and
     * for callers that pre-sized the CTFont themselves. */

    /* flipY then pen translate (em magnitude carried by the CTFont's size). */
    CGAffineTransform M = CGAffineTransformMake(1.0, 0.0, 0.0, -1.0,
                                                (CGFloat)x, (CGFloat)y);

    CGPathRef gp = CTFontCreatePathForGlyph(font, (CGGlyph)glyph, &M);
    if (gp) {
        cm__glyph_sink sink = { path, false };
        CGPathApply(gp, &sink, cm__glyph_apply);
        if (sink.open) cm_path_close(path);
        CFRelease(gp);
    }
    if (owned) CFRelease(font);
}

/* Internal variant that bakes a full glyph->user transform (font_matrix +
 * flipY + pen offset) into the outline, used by the public draw/path paths so a
 * non-default font size / shear is honored.  `glyph_to_user` already includes
 * the y-flip and the pen translation. */
static void cm__append_glyph_xform(CTFontRef font, CGGlyph glyph,
                                   const CGAffineTransform *glyph_to_user,
                                   cm_path *path)
{
    if (!font || !path) return;
    CGPathRef gp = CTFontCreatePathForGlyph(font, glyph, glyph_to_user);
    if (!gp) return;
    cm__glyph_sink sink = { path, false };
    CGPathApply(gp, &sink, cm__glyph_apply);
    if (sink.open) cm_path_close(path);
    CFRelease(gp);
}

/* ==========================================================================
 * Shaping:  UTF-8 -> glyphs  (CoreText)
 * ==========================================================================
 * cairo_scaled_font_text_to_glyphs / show_text need the glyph IDs + positions.
 * We decode UTF-8 -> UTF-16 (NSString), map characters to glyphs with
 * CTFontGetGlyphsForCharacters, and lay them out left-to-right starting at
 * (x,y) using per-glyph advances transformed by font_matrix into user space.
 *
 * This is NOT full complex shaping (no ligatures/kerning via CTLine); it is the
 * 1:1 char->glyph layout cairo's toy-font text path uses, which is what manim's
 * Text/MathTex (already shaped upstream into glyph runs) and simple show_text
 * need.  Surrogate pairs collapse to a single glyph slot at the lead position.
 * ========================================================================== */

/* Build a UTF-16 buffer from a UTF-8 (possibly non-terminated) input.  Returns
 * a malloc'd UniChar array + its length, or NULL.  `utf8_len` < 0 means NUL-
 * terminated. */
static UniChar *cm__utf8_to_utf16(const char *utf8, int utf8_len, CFIndex *out_n)
{
    *out_n = 0;
    if (!utf8) return NULL;
    CFStringRef s;
    if (utf8_len < 0) {
        s = CFStringCreateWithCString(kCFAllocatorDefault, utf8,
                                      kCFStringEncodingUTF8);
    } else {
        s = CFStringCreateWithBytes(kCFAllocatorDefault,
                                    (const UInt8 *)utf8, (CFIndex)utf8_len,
                                    kCFStringEncodingUTF8, false);
    }
    if (!s) return NULL;
    CFIndex n = CFStringGetLength(s);
    UniChar *buf = NULL;
    if (n > 0) {
        buf = (UniChar *)malloc((size_t)n * sizeof(UniChar));
        if (buf) CFStringGetCharacters(s, CFRangeMake(0, n), buf);
        else n = 0;
    }
    CFRelease(s);
    *out_n = buf ? n : 0;
    return buf;
}

/* Core shaping shared by cm_text_shape (native ptr) and the context path.
 * `font_matrix` maps em -> user; advances come back in em from the unit font
 * and are transformed into user space here (with the y-flip so a positive em
 * y-advance, rare, becomes cairo down-y).  Glyphs are positioned from (x,y). */
static cm_status_t cm__shape(CTFontRef font, const cm_matrix_t *font_matrix,
                             double x, double y,
                             const char *utf8, int utf8_len,
                             cm_glyph_t **out_glyphs, int *out_n)
{
    if (out_glyphs) *out_glyphs = NULL;
    if (out_n) *out_n = 0;
    if (!font) return CM_STATUS_FONT_TYPE_MISMATCH;

    CFIndex n16 = 0;
    UniChar *u16 = cm__utf8_to_utf16(utf8, utf8_len, &n16);
    if (!u16 || n16 == 0) { free(u16); return CM_STATUS_SUCCESS; }

    CGGlyph *cgg = (CGGlyph *)malloc((size_t)n16 * sizeof(CGGlyph));
    if (!cgg) { free(u16); return CM_STATUS_NO_MEMORY; }
    /* Maps each UTF-16 unit to a glyph; returns false if ANY char had no glyph,
     * but the array is still filled (0 for the missing ones), which matches the
     * "missing glyph" slot semantics we want. */
    (void)CTFontGetGlyphsForCharacters(font, u16, cgg, n16);

    /* Per-glyph em advances from the unit-size font. */
    CGSize *adv = (CGSize *)malloc((size_t)n16 * sizeof(CGSize));
    if (!adv) { free(cgg); free(u16); return CM_STATUS_NO_MEMORY; }
    (void)CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
                                     cgg, adv, n16);

    /* A UTF-16 unit that is the low half of a surrogate pair maps to glyph 0 in
     * `cgg` (the lead unit carries the real glyph).  We keep ONE glyph per
     * non-trailing-surrogate unit so positions line up with characters. */
    cm_glyph_t *glyphs = (cm_glyph_t *)malloc((size_t)n16 * sizeof(cm_glyph_t));
    if (!glyphs) { free(adv); free(cgg); free(u16); return CM_STATUS_NO_MEMORY; }

    int    count = 0;
    double penx = x, peny = y;
    for (CFIndex i = 0; i < n16; ++i) {
        /* Skip a trailing surrogate (0xDC00..0xDFFF): its advance/glyph belongs
         * to the preceding lead unit. */
        if (u16[i] >= 0xDC00 && u16[i] <= 0xDFFF) continue;

        glyphs[count].index = (unsigned long)cgg[i];
        glyphs[count].x = penx;
        glyphs[count].y = peny;
        count++;

        /* Advance the pen in user space: font_matrix . (em advance). */
        double dux, duy;
        cm__matrix_xform_dist(font_matrix, (double)adv[i].width,
                              (double)adv[i].height, &dux, &duy);
        penx += dux;
        peny += duy;
    }

    free(adv); free(cgg); free(u16);

    if (count == 0) { free(glyphs); return CM_STATUS_SUCCESS; }
    if (out_glyphs) *out_glyphs = glyphs; else free(glyphs);
    if (out_n) *out_n = count;
    return CM_STATUS_SUCCESS;
}

cm_status_t cm_text_shape(void *native_font, double x, double y,
                          const char *utf8, int utf8_len,
                          cm_glyph_t **glyphs, int *num_glyphs)
{
    if (glyphs) *glyphs = NULL;
    if (num_glyphs) *num_glyphs = 0;

    bool owned = false;
    CTFontRef font = cm__borrow_or_default(native_font, &owned);
    if (!font) return CM_STATUS_FONT_TYPE_MISMATCH;

    /* The bare-native entry has no font_matrix; the unit font's em == user, so
     * identity is correct for this path (the context paths below pass the real
     * font_matrix through cm__shape directly). */
    cm_matrix_t identity;
    cm_matrix_identity(&identity);
    cm_status_t st = cm__shape(font, &identity, x, y, utf8, utf8_len,
                               glyphs, num_glyphs);
    if (owned) CFRelease(font);
    return st;
}

/* ==========================================================================
 * Metrics:  glyph / text / font extents
 * --------------------------------------------------------------------------
 * Bounding rects + advances come from the unit-size CTFont in em units, y-UP.
 * We map them into cairo user space via font_matrix and flip y so a CoreText
 * y-up box becomes a cairo y-down extent:
 *   - x_advance / y_advance:  font_matrix . (sum_adv, 0/...)  (y negated)
 *   - x_bearing:              fm . left edge  (x)
 *   - y_bearing:              top of the y-up box -> -(maxY) in user space
 *   - width / height:         fm-scaled box size (abs)
 * For an axis-aligned font_matrix = scale(s,s) (the common manim/toy case) this
 * reduces to the familiar cairo result; for a sheared matrix the box is the
 * AABB of the transformed corners.
 * ========================================================================== */

/* Transform the four corners of a CoreText (y-up) rect `r` by `fm` WITH the
 * y-flip baked in, returning the cairo-space AABB + the user-space top-left
 * bearing origin. */
static void cm__rect_to_user(const cm_matrix_t *fm, CGRect r,
                             double *out_x_bearing, double *out_y_bearing,
                             double *out_width, double *out_height)
{
    /* y-flip: a CoreText point (px,py) maps to user (px,-py) before fm. */
    double xs[4] = { r.origin.x,               r.origin.x + r.size.width,
                     r.origin.x,               r.origin.x + r.size.width };
    double ys[4] = { r.origin.y,               r.origin.y,
                     r.origin.y + r.size.height, r.origin.y + r.size.height };

    double minx = 0, miny = 0, maxx = 0, maxy = 0;
    for (int i = 0; i < 4; ++i) {
        /* flipY then fm (linear part only; extents are origin-relative). */
        double fx, fy;
        cm__matrix_xform_dist(fm, xs[i], -ys[i], &fx, &fy);
        if (i == 0) { minx = maxx = fx; miny = maxy = fy; }
        else {
            if (fx < minx) minx = fx; if (fx > maxx) maxx = fx;
            if (fy < miny) miny = fy; if (fy > maxy) maxy = fy;
        }
    }
    if (out_x_bearing) *out_x_bearing = minx;
    if (out_y_bearing) *out_y_bearing = miny;   /* top edge in y-down space */
    if (out_width)     *out_width  = maxx - minx;
    if (out_height)    *out_height = maxy - miny;
}

/* Shared glyph-extents core over an explicit font_matrix. */
static void cm__glyph_extents(CTFontRef font, const cm_matrix_t *fm,
                              const cm_glyph_t *glyphs, int n,
                              cm_text_extents_t *out)
{
    memset(out, 0, sizeof(*out));
    if (!font || !glyphs || n <= 0) return;

    CGGlyph *cgg = (CGGlyph *)malloc((size_t)n * sizeof(CGGlyph));
    if (!cgg) return;
    for (int i = 0; i < n; ++i) cgg[i] = (CGGlyph)glyphs[i].index;

    /* Per-glyph advances (em) for x/y_advance (sum). */
    CGSize *adv = (CGSize *)malloc((size_t)n * sizeof(CGSize));
    double sum_em_w = 0.0, sum_em_h = 0.0;
    if (adv) {
        (void)CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
                                         cgg, adv, n);
        for (int i = 0; i < n; ++i) { sum_em_w += adv[i].width; sum_em_h += adv[i].height; }
        free(adv);
    }

    /* Ink box: union each glyph's bbox placed at its (x,y) origin RELATIVE to
     * the first glyph's origin, all in CoreText em / y-up, then map to user. */
    CGRect *boxes = (CGRect *)malloc((size_t)n * sizeof(CGRect));
    CGRect ink = CGRectNull;
    if (boxes) {
        (void)CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal,
                                              cgg, boxes, n);
        /* Glyph positions are in USER space; to union ink boxes (em space) we
         * need each glyph's pen offset expressed in em space.  Convert the
         * user-space (x,y) deltas back through fm^-1.  For the common axis
         * case this is exact; if fm is singular we fall back to glyph 0's box. */
        cm_matrix_t inv = *fm;
        bool invertible = (cm_matrix_invert(&inv) == CM_STATUS_SUCCESS);
        double ox = glyphs[0].x, oy = glyphs[0].y;
        for (int i = 0; i < n; ++i) {
            double emx = 0.0, emy = 0.0;
            if (invertible) {
                /* user delta -> em delta (linear part); flip y back to em y-up. */
                double dux = glyphs[i].x - ox, duy = glyphs[i].y - oy;
                double ex, ey;
                cm__matrix_xform_dist(&inv, dux, duy, &ex, &ey);
                emx = ex; emy = -ey;
            }
            CGRect b = boxes[i];
            b.origin.x += emx;
            b.origin.y += emy;
            ink = CGRectIsNull(ink) ? b : CGRectUnion(ink, b);
        }
        free(boxes);
    }
    free(cgg);

    if (!CGRectIsNull(ink) && !CGRectIsEmpty(ink)) {
        cm__rect_to_user(fm, ink, &out->x_bearing, &out->y_bearing,
                         &out->width, &out->height);
    }
    /* Advance in user space (sum em advance through fm, y negated for down-y). */
    double aux, auy;
    cm__matrix_xform_dist(fm, sum_em_w, sum_em_h, &aux, &auy);
    out->x_advance = aux;
    out->y_advance = -auy;
}

void cm_text_glyph_extents(void *native_font, const cm_glyph_t *glyphs, int n,
                           cm_text_extents_t *out)
{
    if (!out) return;
    bool owned = false;
    CTFontRef font = cm__borrow_or_default(native_font, &owned);
    cm_matrix_t identity; cm_matrix_identity(&identity);
    cm__glyph_extents(font, &identity, glyphs, n, out);
    if (owned && font) CFRelease(font);
}

/* Shared font-extents core over an explicit font_matrix. */
static void cm__font_extents(CTFontRef font, const cm_matrix_t *fm,
                             cm_font_extents_t *out)
{
    memset(out, 0, sizeof(*out));
    if (!font) return;

    /* CoreText ascent/descent/leading are POSITIVE magnitudes in em (unit font)
     * y-up.  cairo wants ascent (>0, distance above baseline) and descent (>0,
     * below).  Scale by the font_matrix's y magnitude into user space.  For an
     * axis-aligned fm = scale(sx,sy) the y scale is |sy|; for a general matrix
     * we use the length of the transformed unit-y vector (a conservative,
     * rotation-stable height scale matching cairo-quartz). */
    double ascent_em  = (double)CTFontGetAscent(font);
    double descent_em = (double)CTFontGetDescent(font);
    double leading_em = (double)CTFontGetLeading(font);

    double ux, uy;
    cm__matrix_xform_dist(fm, 0.0, 1.0, &ux, &uy);
    double yscale = sqrt(ux * ux + uy * uy);
    double vx, vy;
    cm__matrix_xform_dist(fm, 1.0, 0.0, &vx, &vy);
    double xscale = sqrt(vx * vx + vy * vy);

    out->ascent  = ascent_em  * yscale;
    out->descent = descent_em * yscale;
    out->height  = (ascent_em + descent_em + leading_em) * yscale;

    /* max advances: use the font's bounding box width as the max x advance
     * (a safe upper bound) scaled by the x magnitude; y advance is 0 for a
     * horizontal font. */
    CGRect bb = CTFontGetBoundingBox(font);
    out->max_x_advance = (double)bb.size.width * xscale;
    out->max_y_advance = 0.0;
}

void cm_text_font_extents(void *native_font, cm_font_extents_t *out)
{
    if (!out) return;
    bool owned = false;
    CTFontRef font = cm__borrow_or_default(native_font, &owned);
    cm_matrix_t identity; cm_matrix_identity(&identity);
    cm__font_extents(font, &identity, out);
    if (owned && font) CFRelease(font);
}

/* ==========================================================================
 * Context-level helpers
 * --------------------------------------------------------------------------
 * The public cm_show_* / cm_*_path / cm_*_extents take a cm_context_t.  Each
 * resolves the context's scaled font into a unit CTFont + the font_matrix, does
 * its work, then releases the CTFont.  We resolve directly from the context's
 * font state (font_face + font_matrix) rather than reusing sf->native because
 * that cache slot is owned by cm_font.c and is not primed on this path.
 * ========================================================================== */

/* Resolve the context's current font to a retained unit CTFont + its
 * font_matrix.  Returns NULL on failure (caller treats as a no-op). */
static CTFontRef cm__ctx_font(cm_context_t *ctx, cm_matrix_t *out_fm)
{
    cm_scaled_font_t *sf = cm_get_scaled_font(ctx);   /* builds/caches in cm_font.c */
    if (out_fm) {
        if (sf) cm_scaled_font_get_font_matrix(sf, out_fm);
        else    cm_matrix_init_scale(out_fm, 10.0, 10.0);
    }
    if (!sf) return NULL;
    return (CTFontRef)cm_text_resolve_native(sf);   /* retained */
}

/* Build the per-glyph outline transform: translate(gx,gy) . fm . flipY, as a
 * CGAffineTransform.  fm maps em->user (cairo y-down); flipY converts CoreText's
 * y-up em path; the translate places the glyph at its user-space origin. */
static CGAffineTransform cm__glyph_xform(const cm_matrix_t *fm,
                                         double gx, double gy)
{
    CGAffineTransform flip = CGAffineTransformMake(1.0, 0.0, 0.0, -1.0, 0.0, 0.0);
    CGAffineTransform M    = cm__cg_from_matrix(fm);   /* em(y-down) -> user */
    /* glyph(em,y-up) --flip--> (em,y-down) --M--> user */
    CGAffineTransform fm_flip = CGAffineTransformConcat(flip, M);
    /* then translate to the pen position in USER space */
    CGAffineTransform trans = CGAffineTransformMakeTranslation((CGFloat)gx, (CGFloat)gy);
    return CGAffineTransformConcat(fm_flip, trans);
}

/* Append a run of positioned glyphs' outlines into `path` (USER space). */
static void cm__append_glyph_run(cm_context_t *ctx,
                                 const cm_glyph_t *glyphs, int n,
                                 cm_path *path)
{
    if (!ctx || !glyphs || n <= 0 || !path) return;
    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;
    for (int i = 0; i < n; ++i) {
        CGAffineTransform M = cm__glyph_xform(&fm, glyphs[i].x, glyphs[i].y);
        cm__append_glyph_xform(font, (CGGlyph)glyphs[i].index, &M, path);
    }
    CFRelease(font);
}

/* Draw the appended outline soup with the current source into the context's
 * batched frame.
 *
 * We do NOT re-implement the flatten/begin-frame/encode driver (that logic, plus
 * the lazy per-surface command buffer, is owned by cm_fill_preserve in
 * cairo_metal.m and is reached only through file-static glue).  Instead we
 * TEMPORARILY swap the outline into the context's current-path slot and call the
 * public cm_fill_preserve, then swap the real path back -- so text fill reuses
 * the exact same batched-frame + stencil-then-cover path as every shape fill,
 * with zero new cross-module symbols.  cairo's show_text leaves the current path
 * untouched, which the save/restore guarantees.
 *
 * Glyph fills are NONZERO (CoreText outlines are wound for nonzero coverage:
 * accents/counters resolve by winding), so we force CM_FILL_RULE_WINDING for the
 * duration regardless of the context's fill rule, then restore it. */
static void cm__fill_outline(cm_context_t *ctx, cm_path *outline)
{
    if (!ctx || !ctx->surface || !outline) return;
    if (outline->verb_count == 0) return;

    /* Swap: stash the real current path + fill rule, install the outline. */
    cm_path        saved_path = ctx->path;
    cm_fill_rule_t saved_rule = ctx->fill_rule;

    ctx->path      = *outline;
    ctx->fill_rule = CM_FILL_RULE_WINDING;
    ctx->path.dirty = true;   /* force a flatten of the freshly-installed outline */

    cm_fill_preserve(ctx);    /* batched frame + stencil-then-cover, current src */

    /* The fill may have (re)built the outline's flattened cache in place; copy
     * the possibly-grown path state back so cm__fill_outline's caller frees the
     * right (current) allocations, then restore the real path + rule. */
    *outline       = ctx->path;
    ctx->path      = saved_path;
    ctx->fill_rule = saved_rule;
}

/* ==========================================================================
 * PUBLIC: text drawing
 * ========================================================================== */

void cm_show_glyphs(cm_context_t *ctx, const cm_glyph_t *glyphs, int num_glyphs)
{
    if (!ctx || !glyphs || num_glyphs <= 0) return;

    cm_path outline;
    cm_path_init(&outline);
    cm__append_glyph_run(ctx, glyphs, num_glyphs, &outline);
    cm__fill_outline(ctx, &outline);
    cm_path_free(&outline);

    /* cairo advances the current point to AFTER the last glyph's advance.
     * Compute the run end and set it so a following show_text continues. */
    /* (The run's final pen position is glyphs[n-1] + its advance.) */
    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (font) {
        CGGlyph last = (CGGlyph)glyphs[num_glyphs - 1].index;
        CGSize a; a.width = a.height = 0;
        (void)CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
                                         &last, &a, 1);
        double dux, duy;
        cm__matrix_xform_dist(&fm, (double)a.width, (double)a.height, &dux, &duy);
        cm_move_to(ctx,
                   glyphs[num_glyphs - 1].x + dux,
                   glyphs[num_glyphs - 1].y + duy);
        CFRelease(font);
    }
}

void cm_show_text(cm_context_t *ctx, const char *utf8)
{
    if (!ctx || !utf8) return;

    /* Pen starts at the current point (cairo); default to origin if none. */
    double px = 0.0, py = 0.0;
    if (cm_has_current_point(ctx)) cm_get_current_point(ctx, &px, &py);

    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;

    cm_glyph_t *glyphs = NULL;
    int n = 0;
    cm_status_t st = cm__shape(font, &fm, px, py, utf8, -1, &glyphs, &n);
    CFRelease(font);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;

    if (glyphs && n > 0) {
        cm_show_glyphs(ctx, glyphs, n);   /* fills + advances the point */
    }
    free(glyphs);
}

void cm_show_text_glyphs(cm_context_t *ctx, const char *utf8, int utf8_len,
                         const cm_glyph_t *glyphs, int num_glyphs,
                         const cm_text_cluster_t *clusters, int num_clusters,
                         cm_text_cluster_flags_t cluster_flags)
{
    /* The cluster map is byte<->glyph metadata for accessibility / copy; it does
     * not change the rendered result, so we draw the supplied glyph run exactly
     * like show_glyphs (cairo's image backend does the same). */
    (void)utf8; (void)utf8_len; (void)clusters; (void)num_clusters;
    (void)cluster_flags;
    cm_show_glyphs(ctx, glyphs, num_glyphs);
}

/* ==========================================================================
 * PUBLIC: text/glyph -> current path (append WITHOUT filling)
 * ========================================================================== */

void cm_glyph_path(cm_context_t *ctx, const cm_glyph_t *glyphs, int num_glyphs)
{
    if (!ctx || !glyphs || num_glyphs <= 0) return;
    /* Append straight into the context's CURRENT path (cairo_glyph_path adds to
     * the path under construction; it does NOT fill or clear). */
    cm__append_glyph_run(ctx, glyphs, num_glyphs, &ctx->path);
    ctx->path.dirty = true;
}

void cm_text_path(cm_context_t *ctx, const char *utf8)
{
    if (!ctx || !utf8) return;

    double px = 0.0, py = 0.0;
    if (cm_has_current_point(ctx)) cm_get_current_point(ctx, &px, &py);

    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;

    cm_glyph_t *glyphs = NULL;
    int n = 0;
    (void)cm__shape(font, &fm, px, py, utf8, -1, &glyphs, &n);
    CFRelease(font);

    if (glyphs && n > 0) {
        cm__append_glyph_run(ctx, glyphs, n, &ctx->path);
        ctx->path.dirty = true;
    }
    free(glyphs);
}

/* ==========================================================================
 * PUBLIC: metrics  (context-level)
 * ========================================================================== */

void cm_glyph_extents(cm_context_t *ctx, const cm_glyph_t *glyphs, int num_glyphs,
                      cm_text_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (!ctx || !glyphs || num_glyphs <= 0) return;

    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;
    cm__glyph_extents(font, &fm, glyphs, num_glyphs, extents);
    CFRelease(font);
}

void cm_text_extents(cm_context_t *ctx, const char *utf8, cm_text_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (!ctx || !utf8) return;

    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;

    /* Shape at origin, then measure the run.  The text-extents advance is the
     * run advance; the ink box is the union of glyph boxes at their positions. */
    cm_glyph_t *glyphs = NULL;
    int n = 0;
    (void)cm__shape(font, &fm, 0.0, 0.0, utf8, -1, &glyphs, &n);
    if (glyphs && n > 0)
        cm__glyph_extents(font, &fm, glyphs, n, extents);
    free(glyphs);
    CFRelease(font);
}

void cm_font_extents(cm_context_t *ctx, cm_font_extents_t *extents)
{
    if (!extents) return;
    memset(extents, 0, sizeof(*extents));
    if (!ctx) return;

    cm_matrix_t fm;
    CTFontRef font = cm__ctx_font(ctx, &fm);
    if (!font) return;
    cm__font_extents(font, &fm, extents);
    CFRelease(font);
}
