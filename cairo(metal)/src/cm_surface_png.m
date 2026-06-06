/*
 * cm_surface_png.m  --  CairoMetal PNG encode/decode via ImageIO (Obj-C)
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_surface_png.m"):
 *   PNG encode/decode, factored out of the inline writer that lived in
 *   examples/demo.m into the four reusable library entry points:
 *
 *     cm_surface_write_to_png_path(s, path)
 *     cm_surface_write_to_png_data(s, &out, &len)   [caller free()s *out]
 *     cm_image_surface_create_from_png_path(path)
 *     cm_image_surface_create_from_png_data(bytes, len)
 *
 * These mirror cairo_surface_write_to_png(_stream) /
 * cairo_image_surface_create_from_png(_stream).
 *
 * ----------------------------------------------------------------------------
 * ENCODE (write_to_png)
 * ----------------------------------------------------------------------------
 * cairo's PNG output is *straight* (un-premultiplied) RGBA, not the
 * premultiplied B,G,R,A that our ARGB32 IOSurface stores.  So unlike the demo's
 * old writer (which let CoreGraphics re-interpret the premultiplied bytes), this
 * library writer flushes + maps the surface and produces a CGImage whose backing
 * is *straight* pixels in the natural channel order, so the PNG on disk is
 * byte-faithful to what cairo would have written:
 *
 *   ARGB32 -> read premultiplied B,G,R,A; UN-premultiply to straight R,G,B,A8
 *             (kCGImageAlphaLast, byte order RGBA).
 *   RGB24  -> read the BGRA storage; emit opaque straight R,G,B (drop the unused
 *             X byte; kCGImageAlphaNoneSkipLast is NOT used -- we pack tight RGB).
 *   A8     -> read the single-channel coverage; emit a grayscale image whose
 *             *alpha* is the coverage (kCGImageAlphaOnly), matching cairo's
 *             FORMAT_A8 -> PNG (a greyscale-alpha / alpha-only PNG).
 *
 * We do the channel marshalling on the CPU into a freshly allocated straight
 * buffer, wrap it in a CGImage, and hand that to CGImageDestination + UTTypePNG.
 *
 * ----------------------------------------------------------------------------
 * DECODE (create_from_png)
 * ----------------------------------------------------------------------------
 * Decode through CGImageSource and draw into a CGBitmapContext configured for
 * kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, which on
 * little-endian arm64 IS premultiplied B,G,R,A -- exactly our ARGB32 storage.
 * The decoded rows are then uploaded into a fresh ARGB32 cm surface (allocate
 * via cm_image_surface_create, map its IOSurface base, copy row by row honoring
 * both strides).  cairo always materialises an ARGB32 surface from a PNG, so we
 * do too regardless of the file's own colour type.
 *
 * Links ImageIO / CoreGraphics / UniformTypeIdentifiers (wired in
 * Package.swift + Makefile).
 * ============================================================================
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
/* IOSurface umbrella header differs by platform (see cm_surface.m): macOS ships
 * <IOSurface/IOSurface.h>; iOS only exposes <IOSurface/IOSurfaceRef.h>.  We do
 * not lock the surface here (cm_surface_map_* already fences coherence), but the
 * include keeps the type visible if a future direct path needs it. */
#if __has_include(<IOSurface/IOSurface.h>)
#  import <IOSurface/IOSurface.h>
#else
#  import <IOSurface/IOSurfaceRef.h>
#endif

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Shared helpers
 * ========================================================================== */

/* CGDataProvider release callback: free the straight-pixel buffer we malloc'd
 * for the encode CGImage.  A plain C function (not a block) so it casts cleanly
 * to CGDataProviderReleaseDataCallback under ARC. */
static void cm_png_free_provider_data(void *info, const void *data, size_t size)
{
    (void)info; (void)size;
    free((void *)data);
}

/* Map the surface for CPU reads in its native row layout (premultiplied B,G,R,A
 * for ARGB32; single-channel for A8; BGRA storage for RGB24).  This flushes the
 * GPU frame first (cm_surface_map handles the coherence fence), so the bytes are
 * the finished render.  Returns NULL on failure. */
static const unsigned char *cm_png_map_read(cm_surface_t *s, size_t *out_stride)
{
    return (const unsigned char *)cm_surface_map(s, out_stride);
}

/* Finalise a CGImage into a PNG via a CGImageDestination targeting either a
 * file URL (when `url` != NULL) or an in-memory CFMutableData (`mdata`).  Returns
 * true on success.  Does NOT release `img` (caller owns it). */
static bool cm_png_encode_image(CGImageRef img, CFURLRef url, CFMutableDataRef mdata)
{
    CFStringRef pngType = (__bridge CFStringRef)UTTypePNG.identifier;
    CGImageDestinationRef dst = NULL;
    if (url) {
        dst = CGImageDestinationCreateWithURL(url, pngType, 1, NULL);
    } else if (mdata) {
        dst = CGImageDestinationCreateWithData(mdata, pngType, 1, NULL);
    }
    if (!dst) return false;

    CGImageDestinationAddImage(dst, img, NULL);
    bool ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    return ok;
}

/* Build a straight (un-premultiplied) CGImage from a mapped cm surface.
 *
 * Allocates a fresh tightly-packed straight-alpha buffer, marshals per format,
 * and returns a CGImage that OWNS that buffer (released when the image's data
 * provider is released).  Returns NULL on failure (and frees any temp buffer).
 *
 * `src` / `src_stride` come from cm_surface_map; `w`/`h`/`fmt` from the surface.
 */
static CGImageRef cm_png_make_straight_image(const unsigned char *src,
                                             size_t src_stride,
                                             int w, int h, cm_format_t fmt)
{
    if (!src || w <= 0 || h <= 0) return NULL;

    size_t width  = (size_t)w;
    size_t height = (size_t)h;

    int            out_bpp;          /* bytes per pixel in the packed buffer    */
    size_t         out_bits_per_comp = 8;
    CGColorSpaceRef cs               = NULL;
    CGBitmapInfo   bmp;

    switch (fmt) {
        case CM_FORMAT_ARGB32:
            out_bpp = 4;
            cs  = CGColorSpaceCreateDeviceRGB();
            /* Straight RGBA8, R first in memory (host byte order, no swap). */
            bmp = (CGBitmapInfo)kCGImageAlphaLast |
                  (CGBitmapInfo)kCGBitmapByteOrderDefault;
            break;
        case CM_FORMAT_RGB24:
            out_bpp = 3;             /* tight R,G,B (opaque)                    */
            cs  = CGColorSpaceCreateDeviceRGB();
            bmp = (CGBitmapInfo)kCGImageAlphaNone |
                  (CGBitmapInfo)kCGBitmapByteOrderDefault;
            break;
        case CM_FORMAT_A8:
            out_bpp = 1;             /* coverage as alpha-only                  */
            cs  = NULL;              /* alpha-only images carry no colour space */
            bmp = (CGBitmapInfo)kCGImageAlphaOnly;
            break;
        default:
            /* A1 / RGB16_565 / RGB30 are not part of the PNG contract here.    */
            return NULL;
    }
    if (fmt != CM_FORMAT_A8 && !cs) return NULL;

    size_t out_stride = width * (size_t)out_bpp;
    unsigned char *out = (unsigned char *)malloc(out_stride * height);
    if (!out) { if (cs) CGColorSpaceRelease(cs); return NULL; }

    for (size_t y = 0; y < height; ++y) {
        const unsigned char *srow = src + y * src_stride;
        unsigned char       *drow = out + y * out_stride;

        if (fmt == CM_FORMAT_ARGB32) {
            /* in : premultiplied B,G,R,A (little-endian ARGB32)
             * out: straight R,G,B,A  (un-premultiply by alpha)               */
            for (size_t x = 0; x < width; ++x) {
                unsigned int b = srow[x * 4 + 0];
                unsigned int g = srow[x * 4 + 1];
                unsigned int r = srow[x * 4 + 2];
                unsigned int a = srow[x * 4 + 3];
                if (a == 0) {
                    drow[x * 4 + 0] = 0;
                    drow[x * 4 + 1] = 0;
                    drow[x * 4 + 2] = 0;
                    drow[x * 4 + 3] = 0;
                } else if (a == 255) {
                    drow[x * 4 + 0] = (unsigned char)r;
                    drow[x * 4 + 1] = (unsigned char)g;
                    drow[x * 4 + 2] = (unsigned char)b;
                    drow[x * 4 + 3] = 255;
                } else {
                    /* straight = premultiplied * 255 / alpha, rounded, clamped */
                    unsigned int ur = (r * 255u + a / 2u) / a;
                    unsigned int ug = (g * 255u + a / 2u) / a;
                    unsigned int ub = (b * 255u + a / 2u) / a;
                    drow[x * 4 + 0] = (unsigned char)(ur > 255u ? 255u : ur);
                    drow[x * 4 + 1] = (unsigned char)(ug > 255u ? 255u : ug);
                    drow[x * 4 + 2] = (unsigned char)(ub > 255u ? 255u : ub);
                    drow[x * 4 + 3] = (unsigned char)a;
                }
            }
        } else if (fmt == CM_FORMAT_RGB24) {
            /* in : B,G,R,X storage (opaque); out: tight R,G,B               */
            for (size_t x = 0; x < width; ++x) {
                unsigned char b = srow[x * 4 + 0];
                unsigned char g = srow[x * 4 + 1];
                unsigned char r = srow[x * 4 + 2];
                drow[x * 3 + 0] = r;
                drow[x * 3 + 1] = g;
                drow[x * 3 + 2] = b;
            }
        } else { /* CM_FORMAT_A8 */
            /* in : single-channel coverage; out: alpha-only (1:1 copy)       */
            memcpy(drow, srow, width);
        }
    }

    CGDataProviderRef prov =
        CGDataProviderCreateWithData(NULL, out, out_stride * height,
                                     /* release callback: free our malloc      */
                                     cm_png_free_provider_data);
    if (!prov) { free(out); if (cs) CGColorSpaceRelease(cs); return NULL; }

    CGImageRef img = CGImageCreate(width, height,
                                   out_bits_per_comp,
                                   (size_t)out_bpp * 8,
                                   out_stride,
                                   cs,                 /* NULL for alpha-only   */
                                   bmp,
                                   prov,
                                   NULL,               /* no decode array       */
                                   false,              /* no interpolation hint */
                                   kCGRenderingIntentDefault);

    CGDataProviderRelease(prov);   /* img retains it (and thus the buffer)      */
    if (cs) CGColorSpaceRelease(cs);
    /* `out` is now owned by `prov`/`img`; freed by the provider release cb.    */
    return img;
}

/* ==========================================================================
 * Public: encode (write)
 * ========================================================================== */
cm_status_t cm_surface_write_to_png_path(cm_surface_t *surface, const char *path)
{
    if (!surface || !path) return CM_STATUS_SURFACE_TYPE_MISMATCH;

    int w = cm_surface_get_width(surface);
    int h = cm_surface_get_height(surface);
    if (w <= 0 || h <= 0) return CM_STATUS_INVALID_FORMAT;

    cm_format_t fmt = cm_surface_get_format(surface);
    if (fmt != CM_FORMAT_ARGB32 && fmt != CM_FORMAT_RGB24 && fmt != CM_FORMAT_A8)
        return CM_STATUS_INVALID_FORMAT;

    size_t stride = 0;
    const unsigned char *px = cm_png_map_read(surface, &stride);
    if (!px || stride == 0) return CM_STATUS_DEVICE_ERROR;

    cm_status_t rc = CM_STATUS_SUCCESS;
    @autoreleasepool {
        CGImageRef img = cm_png_make_straight_image(px, stride, w, h, fmt);
        if (!img) {
            rc = CM_STATUS_DEVICE_ERROR;
        } else {
            NSURL *nsurl = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
            bool ok = (nsurl != nil) &&
                      cm_png_encode_image(img, (__bridge CFURLRef)nsurl, NULL);
            CGImageRelease(img);
            rc = ok ? CM_STATUS_SUCCESS : CM_STATUS_DEVICE_ERROR;
        }
    }
    return rc;
}

cm_status_t cm_surface_write_to_png_data(cm_surface_t *surface,
                                         unsigned char **out_data, size_t *out_len)
{
    if (out_data) *out_data = NULL;
    if (out_len)  *out_len  = 0;
    if (!surface) return CM_STATUS_SURFACE_TYPE_MISMATCH;

    int w = cm_surface_get_width(surface);
    int h = cm_surface_get_height(surface);
    if (w <= 0 || h <= 0) return CM_STATUS_INVALID_FORMAT;

    cm_format_t fmt = cm_surface_get_format(surface);
    if (fmt != CM_FORMAT_ARGB32 && fmt != CM_FORMAT_RGB24 && fmt != CM_FORMAT_A8)
        return CM_STATUS_INVALID_FORMAT;

    size_t stride = 0;
    const unsigned char *px = cm_png_map_read(surface, &stride);
    if (!px || stride == 0) return CM_STATUS_DEVICE_ERROR;

    cm_status_t rc = CM_STATUS_SUCCESS;
    @autoreleasepool {
        CGImageRef img = cm_png_make_straight_image(px, stride, w, h, fmt);
        if (!img) {
            rc = CM_STATUS_DEVICE_ERROR;
        } else {
            CFMutableDataRef mdata = CFDataCreateMutable(kCFAllocatorDefault, 0);
            if (!mdata) {
                rc = CM_STATUS_NO_MEMORY;
            } else {
                bool ok = cm_png_encode_image(img, NULL, mdata);
                if (ok) {
                    CFIndex len = CFDataGetLength(mdata);
                    unsigned char *buf = (unsigned char *)malloc((size_t)len);
                    if (!buf) {
                        rc = CM_STATUS_NO_MEMORY;
                    } else {
                        /* Copy out so the caller can free() with plain free(),
                         * decoupled from the CoreFoundation allocator. */
                        CFDataGetBytes(mdata, CFRangeMake(0, len), buf);
                        if (out_data) *out_data = buf;
                        if (out_len)  *out_len  = (size_t)len;
                    }
                } else {
                    rc = CM_STATUS_DEVICE_ERROR;
                }
                CFRelease(mdata);
            }
            CGImageRelease(img);
        }
    }
    return rc;
}

/* ==========================================================================
 * Public: decode (create_from)
 * --------------------------------------------------------------------------
 * Shared core: given a CGImageSource, decode the first image into a fresh ARGB32
 * cm surface (premultiplied B,G,R,A storage).  Sets cm_last_status and returns
 * the surface, or NULL + a status on failure.
 * ========================================================================== */
static cm_surface_t *cm_png_decode_source(CGImageSourceRef src)
{
    if (!src) { cm_set_last_status(CM_STATUS_DEVICE_ERROR); return NULL; }

    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    if (!img) { cm_set_last_status(CM_STATUS_DEVICE_ERROR); return NULL; }

    int w = (int)CGImageGetWidth(img);
    int h = (int)CGImageGetHeight(img);
    if (w <= 0 || h <= 0) {
        CGImageRelease(img);
        cm_set_last_status(CM_STATUS_INVALID_FORMAT);
        return NULL;
    }

    /* Fresh ARGB32 target (IOSurface-backed) -- cairo always returns ARGB32. */
    cm_surface_t *surface = cm_image_surface_create(CM_FORMAT_ARGB32, w, h);
    if (!surface) {
        /* cm_image_surface_create already set cm_last_status. */
        CGImageRelease(img);
        return NULL;
    }

    size_t dst_stride = 0;
    unsigned char *dst = (unsigned char *)cm_surface_map_argb32(surface, &dst_stride);
    if (!dst || dst_stride == 0) {
        CGImageRelease(img);
        cm_surface_destroy(surface);
        cm_set_last_status(CM_STATUS_DEVICE_ERROR);
        return NULL;
    }

    bool ok = false;
    @autoreleasepool {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        if (cs) {
            /* premultiplied first + little-endian == premultiplied B,G,R,A,
             * exactly our ARGB32 storage -- CG decodes directly into it. */
            CGBitmapInfo bmp = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst |
                               (CGBitmapInfo)kCGBitmapByteOrder32Little;
            CGContextRef cg = CGBitmapContextCreate(dst, (size_t)w, (size_t)h,
                                                    8, dst_stride, cs, bmp);
            CGColorSpaceRelease(cs);
            if (cg) {
                /* The PNG may have any colour type / premultiplication; drawing
                 * it through this context normalises it into our layout.  We do
                 * not clear first: the draw fully covers (0,0,w,h). */
                CGContextSetBlendMode(cg, kCGBlendModeCopy);
                CGContextDrawImage(cg, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), img);
                CGContextFlush(cg);
                CGContextRelease(cg);
                ok = true;
            }
        }
    }
    CGImageRelease(img);

    if (!ok) {
        cm_surface_destroy(surface);
        cm_set_last_status(CM_STATUS_DEVICE_ERROR);
        return NULL;
    }

    /* The CPU just wrote the IOSurface base directly; let the surface know so a
     * subsequent map/encode handoff has the documented coherence signal. */
    cm_surface_mark_dirty(surface);
    cm_set_last_status(CM_STATUS_SUCCESS);
    return surface;
}

cm_surface_t *cm_image_surface_create_from_png_path(const char *path)
{
    if (!path) { cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH); return NULL; }

    cm_surface_t *surface = NULL;
    @autoreleasepool {
        NSURL *nsurl = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        if (!nsurl) { cm_set_last_status(CM_STATUS_DEVICE_ERROR); return NULL; }

        CGImageSourceRef src =
            CGImageSourceCreateWithURL((__bridge CFURLRef)nsurl, NULL);
        if (!src) { cm_set_last_status(CM_STATUS_DEVICE_ERROR); return NULL; }

        surface = cm_png_decode_source(src);
        CFRelease(src);
    }
    return surface;
}

cm_surface_t *cm_image_surface_create_from_png_data(const unsigned char *data, size_t len)
{
    if (!data || len == 0) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }

    cm_surface_t *surface = NULL;
    @autoreleasepool {
        /* Wrap the caller's bytes WITHOUT copying (no-copy CFData); the data must
         * outlive only this call, which it does (we fully decode synchronously). */
        CFDataRef cfdata = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
                                                       data, (CFIndex)len,
                                                       kCFAllocatorNull);
        if (!cfdata) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }

        CGImageSourceRef src = CGImageSourceCreateWithData(cfdata, NULL);
        if (!src) {
            CFRelease(cfdata);
            cm_set_last_status(CM_STATUS_DEVICE_ERROR);
            return NULL;
        }

        surface = cm_png_decode_source(src);
        CFRelease(src);
        CFRelease(cfdata);
    }
    return surface;
}
