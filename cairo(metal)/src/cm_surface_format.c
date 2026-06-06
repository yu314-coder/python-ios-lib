/*
 * cm_surface_format.c  --  CairoMetal format metadata table (pure C)
 * ============================================================================
 *
 * The ONE source of truth for per-format backing metadata, consulted by every
 * surface/device file (cm_surface.m, cm_surface_similar.c, cm_recording.m,
 * cm_device.m).  Pixel-format codes are returned as plain ints (the Metal /
 * IOSurface enum values) so this translation unit stays PURE C with no Metal /
 * Foundation dependency; the .m files map the int back to MTLPixelFormat / the
 * IOSurface FourCC at the point of use.
 *
 * FORMAT -> BACKING table (cairo-exact):
 *
 *   cm_format_t      | MTLPixelFormat   | IOSurface FourCC | bytes/px | content
 *   -----------------+------------------+------------------+----------+--------
 *   ARGB32           | BGRA8Unorm (80)  | 'BGRA'           | 4        | C+A
 *   RGB24            | BGRA8Unorm (80)  | 'BGRA'           | 4 (X=A)  | C
 *   A8               | R8Unorm    (10)  | 'L008'           | 1        | A
 *   RGB16_565        | B5G6R5Unorm(40)  | '565 '           | 2        | C
 *   A1               | INVALID    (0)   | 0 (cpu backing)  | 0 (sub)  | A
 *   RGB30            | INVALID    (0)   | 0                | 0        | (rej)
 *
 *   - ARGB32/RGB24 share the 32-bit BGRA8 backing: on little-endian arm64 a
 *     cairo native-endian 0xAARRGGBB pixel is the byte sequence B,G,R,A, which
 *     is exactly MTLPixelFormatBGRA8Unorm + the 'BGRA' IOSurface code, so the
 *     rendered frame feeds VideoToolbox with zero swizzle.  RGB24 stores the
 *     same 32 bits with the alpha byte ignored (cairo keeps RGB24 32-bit too).
 *   - A8 is a single-channel coverage surface; R8Unorm + 'L008' (8-bit
 *     luminance) is its zero-copy backing.
 *   - RGB16_565 is the 16-bit packed colour surface (B5G6R5Unorm + '565 ').
 *   - A1 is sub-byte (1 bit/px): NOT GPU-renderable, NOT IOSurface-backed; it
 *     uses a malloc'd CPU backing whose stride is align((w+7)/8, 4).  Its
 *     bytes-per-pixel is reported as 0 (sub-byte; callers must use the stride).
 *   - RGB30 is unsupported and reported INVALID everywhere (cm_image_surface_
 *     create rejects it with CM_STATUS_INVALID_FORMAT).
 *
 * Stride uses cairo's exact rule: stride = align((bits_per_pixel*width + 7)/8,
 * CAIRO_STRIDE_ALIGNMENT) with CAIRO_STRIDE_ALIGNMENT == sizeof(uint32_t) == 4,
 * and cairo's overflow guard (return -1 for a width that would overflow int32).
 * Computing from bits-per-pixel (RGB24 counts as 32) makes the A1 sub-byte case
 * fall out of the same formula as the byte formats -- there is no special case.
 * ============================================================================
 */

#include "cm_internal.h"

#include <limits.h>

/* --------------------------------------------------------------------------
 * MTLPixelFormat enum values (stable Metal ABI).  Mirrored here as ints so the
 * .c stays pure; cm_surface.m / cm_device.m cast the int to MTLPixelFormat.
 * -------------------------------------------------------------------------- */
#define CM_MTLPF_INVALID      0    /* MTLPixelFormatInvalid     */
#define CM_MTLPF_R8UNORM      10   /* MTLPixelFormatR8Unorm     */
#define CM_MTLPF_B5G6R5UNORM  40   /* MTLPixelFormatB5G6R5Unorm */
#define CM_MTLPF_BGRA8UNORM   80   /* MTLPixelFormatBGRA8Unorm  */

/* --------------------------------------------------------------------------
 * IOSurface / CoreVideo FourCC pixel codes.  The multi-character constant packs
 * the first character into the most-significant byte (e.g. 'BGRA' == 0x42475241),
 * matching how cm_surface.m tags the IOSurface (kIOSurfacePixelFormat:@((unsigned)
 * 'BGRA')) and how CoreVideo reads a FourCC.  '565 ' is the bare RGB16_565 tag.
 * -------------------------------------------------------------------------- */
#define CM_IOSF_BGRA  ((uint32_t)'BGRA')   /* 32-bit BGRA (== kCVPixelFormatType_32BGRA) */
#define CM_IOSF_L008  ((uint32_t)'L008')   /* 8-bit luminance, used to back A8            */
#define CM_IOSF_565   ((uint32_t)'565 ')   /* 16-bit 5-6-5 packed colour                  */

/* cairo CAIRO_STRIDE_ALIGNMENT is sizeof(uint32_t) == 4. */
#define CM_STRIDE_ALIGN 4

/* --------------------------------------------------------------------------
 * cm_format_bits_per_pixel -- cairo's _cairo_format_bits_per_pixel.  This is the
 * BIT depth of the in-memory pixel, which is the table backbone for the stride
 * arithmetic.  Note RGB24 is 32 bits (cairo stores it in a 32-bit slot with the
 * alpha byte ignored), and A1 is 1 bit.  RGB30 (30 bits in cairo) is reported as
 * 0 here because CairoMetal treats it as INVALID rather than allocating it.
 * Internal-only (not in the public/internal contract); file-local.
 * -------------------------------------------------------------------------- */
static int cm_format_bits_per_pixel(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:    return 32;
        case CM_FORMAT_RGB24:     return 32;   /* 32-bit slot, alpha byte unused */
        case CM_FORMAT_RGB16_565: return 16;
        case CM_FORMAT_A8:        return 8;
        case CM_FORMAT_A1:        return 1;     /* sub-byte                       */
        case CM_FORMAT_RGB30:     return 0;     /* unsupported -> INVALID         */
        case CM_FORMAT_INVALID:
        default:                  return 0;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_bytes_per_pixel -- whole BYTES per pixel for the byte-addressable
 * formats; 0 for the sub-byte A1 format (its addressing is bit-packed, so
 * callers must use cm_format_stride_for_width, not a per-pixel byte count).
 * Mirrors a cairo bytes-per-pixel helper.
 * -------------------------------------------------------------------------- */
int cm_format_bytes_per_pixel(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:    return 4;
        case CM_FORMAT_RGB24:     return 4;   /* stored as 32-bit (X in alpha)   */
        case CM_FORMAT_RGB16_565: return 2;
        case CM_FORMAT_A8:        return 1;
        case CM_FORMAT_A1:        return 0;   /* sub-byte: use the stride         */
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return 0;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_stride_for_width -- cairo_format_stride_for_width, exactly.
 *
 *   stride = ((bpp*width + 7)/8 + (ALIGN-1)) & -ALIGN,   ALIGN = 4
 *
 * computed from BITS-per-pixel so the A1 sub-byte case ((1*w+7)/8 == (w+7)/8)
 * uses the same formula as the byte formats.  Returns:
 *   -1  if the width would overflow a 32-bit stride (cairo's guard), so the
 *       create-for-data caller rejects it (it tests `min_stride <= 0`);
 *    0  for a non-positive width, or for a format with no defined backing here
 *       (RGB30 / INVALID), matching the rest of the codebase that treats those
 *       as unsupported.  A1 itself has a real stride (align((w+7)/8, 4)).
 * For every supported format (ARGB32/RGB24/A8/A1/RGB16_565) the result is
 * identical to the per-format `align(width*bytes, 4)` rounding, with the added
 * overflow guard.
 * -------------------------------------------------------------------------- */
int cm_format_stride_for_width(cm_format_t fmt, int width)
{
    if (width <= 0) return 0;

    int bpp = cm_format_bits_per_pixel(fmt);
    if (bpp <= 0) return 0;   /* RGB30 / INVALID: no defined backing -> 0        */

    /* cairo's overflow guard: reject a width whose bit count + rounding slack
     * would not fit in a positive int32.  Mirrors:
     *   if ((unsigned)width >= (INT32_MAX - 7) / (unsigned)bpp) return -1; */
    if ((uint32_t)width >= (uint32_t)((INT_MAX - 7) / bpp))
        return -1;

    /* (bpp*width + 7) / 8 bytes, then round up to the 4-byte stride alignment.
     * The product fits in int after the guard above; use the bit formula so A1
     * needs no special case. */
    int bytes = (bpp * width + 7) / 8;
    return (bytes + (CM_STRIDE_ALIGN - 1)) & -CM_STRIDE_ALIGN;
}

/* --------------------------------------------------------------------------
 * cm_format_iosurface_code -- the IOSurface/CoreVideo FourCC backing a format,
 * or 0 when the format has NO IOSurface backing (A1 is CPU-backed; RGB30/
 * INVALID are unsupported).  Returned as uint32_t; cm_surface.m feeds it to
 * kIOSurfacePixelFormat.
 * -------------------------------------------------------------------------- */
uint32_t cm_format_iosurface_code(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:
        case CM_FORMAT_RGB24:     return CM_IOSF_BGRA;
        case CM_FORMAT_A8:        return CM_IOSF_L008;
        case CM_FORMAT_RGB16_565: return CM_IOSF_565;
        case CM_FORMAT_A1:        /* CPU backing, no IOSurface                   */
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return 0;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_mtl_pixelfmt -- the MTLPixelFormat (as int) for a format's texture
 * backing, or MTLPixelFormatInvalid (0) for non-GPU / unsupported formats.
 * cm_surface.m / cm_device.m cast the result to MTLPixelFormat.
 * -------------------------------------------------------------------------- */
int cm_format_mtl_pixelfmt(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:
        case CM_FORMAT_RGB24:     return CM_MTLPF_BGRA8UNORM;
        case CM_FORMAT_A8:        return CM_MTLPF_R8UNORM;
        case CM_FORMAT_RGB16_565: return CM_MTLPF_B5G6R5UNORM;
        case CM_FORMAT_A1:        /* sub-byte: no Metal texture format           */
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return CM_MTLPF_INVALID;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_is_gpu_renderable -- true for the formats with an IOSurface-backed
 * MTLTexture target (ARGB32/RGB24/A8/RGB16_565); FALSE for A1 (sub-byte, CPU
 * backing) and RGB30/INVALID (unsupported).  The encode path uses this to pick
 * the IOSurface target vs. the CPU-backing path.
 * -------------------------------------------------------------------------- */
int cm_format_is_gpu_renderable(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:
        case CM_FORMAT_RGB24:
        case CM_FORMAT_A8:
        case CM_FORMAT_RGB16_565: return 1;
        case CM_FORMAT_A1:        /* CPU backing only                            */
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return 0;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_has_alpha -- does the format carry an alpha channel?  ARGB32 (BGRA),
 * A8, and A1 do; RGB24 and RGB16_565 are opaque colour-only (RGB24's high byte
 * is ignored, not alpha).  RGB30/INVALID report no alpha.
 * -------------------------------------------------------------------------- */
int cm_format_has_alpha(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_ARGB32:
        case CM_FORMAT_A8:
        case CM_FORMAT_A1:        return 1;
        case CM_FORMAT_RGB24:     /* opaque: high byte is X, not A               */
        case CM_FORMAT_RGB16_565: /* opaque                                      */
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return 0;
    }
}

/* --------------------------------------------------------------------------
 * cm_content_for_format -- the cairo_content_t (COLOR / ALPHA / COLOR_ALPHA bit
 * flags) implied by a pixel format.  A8/A1 are pure ALPHA; RGB24/RGB16_565 are
 * pure COLOR; ARGB32 is COLOR_ALPHA.  Unsupported formats default to
 * COLOR_ALPHA (the safe superset).  Mirrors cairo_surface_get_content.
 * -------------------------------------------------------------------------- */
cm_content_t cm_content_for_format(cm_format_t fmt)
{
    switch (fmt) {
        case CM_FORMAT_A8:
        case CM_FORMAT_A1:        return CM_CONTENT_ALPHA;
        case CM_FORMAT_RGB24:
        case CM_FORMAT_RGB16_565: return CM_CONTENT_COLOR;
        case CM_FORMAT_ARGB32:    return CM_CONTENT_COLOR_ALPHA;
        case CM_FORMAT_RGB30:
        case CM_FORMAT_INVALID:
        default:                  return CM_CONTENT_COLOR_ALPHA;
    }
}

/* --------------------------------------------------------------------------
 * cm_format_for_content -- the concrete pixel format chosen for a content type
 * (the inverse of cm_content_for_format, matching cairo's _cairo_format_from_
 * content): COLOR -> RGB24, ALPHA -> A8, COLOR_ALPHA -> ARGB32.  Used by
 * create_similar / recording-surface / offscreen-group allocation to turn a
 * requested content into a backing format.  Unknown content defaults to the
 * full ARGB32.
 * -------------------------------------------------------------------------- */
cm_format_t cm_format_for_content(cm_content_t content)
{
    switch (content) {
        case CM_CONTENT_COLOR:       return CM_FORMAT_RGB24;
        case CM_CONTENT_ALPHA:       return CM_FORMAT_A8;
        case CM_CONTENT_COLOR_ALPHA: return CM_FORMAT_ARGB32;
        default:                     return CM_FORMAT_ARGB32;
    }
}

/* --------------------------------------------------------------------------
 * Enum -> string helpers (diagnostics; mirror cairo's debug surface-type /
 * content names).  Returned strings are static and must NOT be freed.
 * -------------------------------------------------------------------------- */
const char *cm_surface_type_string(cm_surface_type_t type)
{
    switch (type) {
        case CM_SURFACE_TYPE_IMAGE:      return "image";
        case CM_SURFACE_TYPE_RECORDING:  return "recording";
        case CM_SURFACE_TYPE_SUBSURFACE: return "subsurface";
        default:                         return "unknown";
    }
}

const char *cm_content_string(cm_content_t content)
{
    switch (content) {
        case CM_CONTENT_COLOR:       return "color";
        case CM_CONTENT_ALPHA:       return "alpha";
        case CM_CONTENT_COLOR_ALPHA: return "color-alpha";
        default:                     return "unknown";
    }
}
