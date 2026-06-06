/*
 * cm_surface.m  --  CairoMetal format-general IOSurface-backed render target
 * ============================================================================
 *
 * MODULE OWNER of (cm_internal.h "MODULE: cm_surface.m"):
 *   - The render target: an IOSurface-backed MTLTexture whose pixels live in
 *     GPU-accessible IOSurface memory, so the finished frame is handed to
 *     h264_videotoolbox with ZERO copies (cm_surface_get_iosurface).  ARGB32 /
 *     RGB24 -> BGRA8; A8 -> R8; RGB16_565 -> B5G6R5; the concrete backing comes
 *     from cm_surface_format.c (cm_format_mtl_pixelfmt / _iosurface_code /
 *     _bytes_per_pixel) -- this file no longer hardcodes ARGB32.
 *   - A1 is sub-byte and NOT GPU-renderable: a malloc'd cpu_backing, no
 *     IOSurface.  RGB30 is rejected (INVALID_FORMAT).
 *   - The per-format MSAA colour + stencil attachments and the resolve into the
 *     IOSurface (or, for an offscreen group target, a private) colour texture.
 *     The resolve itself is encoded by cm_device.m's render pass via
 *     StoreActionMultisampleResolve; this file allocates the attachments, sized
 *     and pixel-formatted from s->format so cm_frame_begin can read them back.
 *   - The full cairo image-surface subset: create / create_for_data / destroy /
 *     finish / flush / introspection / device-offset / map(_argb32) /
 *     map_to_image / unmap_image / get_iosurface / get_width / get_height.
 *   - The INTERNAL non-IOSurface offscreen MSAA+resolve target for push_group
 *     (cm_offscreen_surface_create), consumed by cm_group.m.
 *
 * These public surface functions live here (rather than in cairo_metal.m)
 * because they are inseparable from the Objective-C IOSurface/MTLTexture
 * internals that only this translation unit can touch; cairo_metal.m owns the
 * context/path/paint/fill/stroke public glue.  The cm_surface struct itself is
 * defined in cm_internal.h (non-opaque), so these are thin wrappers over it.
 *
 * Backing per format (the ONE source of truth is cm_surface_format.c):
 *   ARGB32 / RGB24  : MTLPixelFormatBGRA8Unorm  + 'BGRA' + 4 bpe
 *                     (cairo FORMAT_ARGB32 native-endian, premultiplied B,G,R,A
 *                      on little-endian arm64 -- fed to VideoToolbox directly)
 *   A8              : MTLPixelFormatR8Unorm     + 'L008' + 1 bpe
 *   RGB16_565       : MTLPixelFormatB5G6R5Unorm + '565 ' + 2 bpe
 *   A1              : CPU backing (no IOSurface, no GPU textures)
 *   RGB30           : unsupported (INVALID_FORMAT)
 *   stencil         : MTLPixelFormatStencil8, MSAA, transient (memoryless)
 *   MSAA            : CM_MSAA_SAMPLE_COUNT (4x), resolved into the single-sample
 *                     colour texture at end-of-pass.
 * ============================================================================
 */

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
/* IOSurface umbrella header differs by platform: macOS ships
 * <IOSurface/IOSurface.h>; iOS only exposes <IOSurface/IOSurfaceRef.h>. */
#if __has_include(<IOSurface/IOSurface.h>)
#  import <IOSurface/IOSurface.h>
#else
#  import <IOSurface/IOSurfaceRef.h>
#endif

#include "cm_internal.h"

/* From cm_device.m: device wrapper + queue, and the frame end driver. */
extern id<MTLDevice>       cm_device_mtl_id  (cm_device *dev);
extern id<MTLCommandQueue> cm_device_queue_id(cm_device *dev);

/* The process-wide device.  cm_device_create builds every persistent pipeline /
 * depth-stencil state and the triple-buffered ring exactly once; all surfaces
 * share it.  Guarded by a once-token so concurrent first surfaces are safe. */
static cm_device         *g_device       = NULL;
static cm_status_t        g_device_status = CM_STATUS_SUCCESS;
static dispatch_once_t    g_device_once;

/* Thread-local status for global/surface-creation ops (mirrors cairo's notion).
 * This file is the single owner of that storage; the context glue in
 * cairo_metal.m writes it through cm_set_last_status(). */
static _Thread_local cm_status_t g_last_status = CM_STATUS_SUCCESS;

cm_status_t cm_last_status(void)        { return g_last_status; }
void        cm_set_last_status(cm_status_t st) { g_last_status = st; }

/* The active per-frame command buffer for a surface is owned by cairo_metal.m's
 * draw driver; flush/destroy here commit it through this exported hook so the
 * surface public API and the context draw path share one frame lifecycle. */
extern void cm_glue_end_frame_for_surface(cm_surface_t *surface, bool wait);

static cm_device *cm_shared_device(cm_status_t *out)
{
    dispatch_once(&g_device_once, ^{
        g_device = cm_device_create(&g_device_status);
    });
    if (out) *out = g_device_status;
    return g_device;
}

/* ==========================================================================
 * Format -> Metal/IOSurface mapping (the int codes come from the pure-C
 * cm_surface_format.c table; this .m turns them back into the ObjC enums).
 * ========================================================================== */

/* Map the cm_surface_format.c int (MTLPixelFormat enum value, ABI-stable) back
 * to the typed MTLPixelFormat.  Returns MTLPixelFormatInvalid for unsupported. */
static MTLPixelFormat cm_mtl_pixelformat_for(cm_format_t fmt)
{
    switch (cm_format_mtl_pixelfmt(fmt)) {
        case 80: return MTLPixelFormatBGRA8Unorm;   /* ARGB32 / RGB24 */
        case 10: return MTLPixelFormatR8Unorm;      /* A8             */
        case 40: return MTLPixelFormatB5G6R5Unorm;  /* RGB16_565      */
        default: return MTLPixelFormatInvalid;      /* A1 / RGB30     */
    }
}

/* ==========================================================================
 * GPU resource allocation (format-general)
 * ========================================================================== */

/* Create the IOSurface + its IOSurface-backed single-sample colour texture in
 * the surface's concrete pixel format.  The IOSurface FourCC + bytes-per-element
 * come from the format table so the same memory feeds VideoToolbox (BGRA) or a
 * single-channel/16-bit consumer without a re-pack.  Leaves s->stride as the
 * cairo packed CPU-buffer stride (cm_format_stride_for_width); the IOSurface's
 * own bytes-per-row (which may exceed the cairo minimum for alignment) is read
 * back directly via IOSurfaceGetBytesPerRow at map time, never stored here.
 */
static bool cm_surface_alloc_iosurface(cm_surface_t *s, id<MTLDevice> mtl)
{
    MTLPixelFormat pf = cm_mtl_pixelformat_for(s->format);
    if (pf == MTLPixelFormatInvalid) return false;

    uint32_t fourcc = cm_format_iosurface_code(s->format);
    int      bpe    = cm_format_bytes_per_pixel(s->format);
    if (fourcc == 0 || bpe <= 0) return false;

    NSDictionary *props = @{
        (id)kIOSurfaceWidth:           @(s->width),
        (id)kIOSurfaceHeight:          @(s->height),
        (id)kIOSurfaceBytesPerElement: @(bpe),
        /* FourCC selects the IOSurface's pixel layout: 'BGRA' (==
         * kCVPixelFormatType_32BGRA, feeds VideoToolbox directly), 'L008'
         * (8-bit luminance, used as A8), or '565 ' (16-bit). */
        (id)kIOSurfacePixelFormat:     @((unsigned)fourcc),
    };
    IOSurfaceRef io = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!io) return false;

    s->iosurface = (void *)io;                 /* owns one ref; freed on destroy*/
    /* NOTE: s->stride is the CAIRO/pycairo CPU-buffer row stride
     * (== cm_format_stride_for_width(format,width)), the value get_stride() must
     * report and the value get_data() packs to.  It is NOT the IOSurface's
     * GPU-aligned bytes-per-row: IOSurfaceGetBytesPerRow(io) may exceed the cairo
     * minimum for hardware alignment (e.g. 128 for a 17px ARGB32 row), but
     * get_data() always returns a TIGHTLY-PACKED cairo buffer.  The readback path
     * (cm_surface_map / cm_surface_map_argb32) reads the IOSurface's own
     * bytes-per-row directly via IOSurfaceGetBytesPerRow, so the GPU stride is
     * never lost; we just must not clobber the cairo stride with it here.
     * (Caller set s->stride = cm_format_stride_for_width(...) before this.) */

    MTLTextureDescriptor *cd =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                           width:s->width
                                                          height:s->height
                                                       mipmapped:NO];
    cd.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    cd.storageMode = MTLStorageModeShared;     /* IOSurface memory is shared    */

    id<MTLTexture> color =
        [mtl newTextureWithDescriptor:cd iosurface:io plane:0];
    if (!color) return false;
    s->color_tex = (__bridge_retained void *)color;  /* manual retain; CFRelease on destroy */
    return true;
}

/* Create a private (non-IOSurface) single-sample colour texture as the MSAA
 * resolve target.  Used by the offscreen group target, which must NOT allocate
 * an IOSurface (it is sampled back as a SurfacePattern, never handed to
 * VideoToolbox) but still needs a resolve destination for cm_frame_begin. */
static bool cm_surface_alloc_private_color(cm_surface_t *s, id<MTLDevice> mtl)
{
    MTLPixelFormat pf = cm_mtl_pixelformat_for(s->format);
    if (pf == MTLPixelFormatInvalid) return false;

    MTLTextureDescriptor *cd =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                           width:s->width
                                                          height:s->height
                                                       mipmapped:NO];
    cd.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    cd.storageMode = MTLStorageModePrivate;    /* GPU-only; group source        */

    id<MTLTexture> color = [mtl newTextureWithDescriptor:cd];
    if (!color) return false;
    s->color_tex = (__bridge_retained void *)color;
    return true;
}

/* Create the transient MSAA colour + stencil attachments (tile memory), in the
 * surface's concrete colour format so the resolve into the single-sample texture
 * is valid (Metal requires the MSAA + resolve textures share a pixel format). */
static bool cm_surface_alloc_msaa(cm_surface_t *s, id<MTLDevice> mtl)
{
    MTLPixelFormat pf = cm_mtl_pixelformat_for(s->format);
    if (pf == MTLPixelFormatInvalid) return false;

    MTLTextureDescriptor *md =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                           width:s->width
                                                          height:s->height
                                                       mipmapped:NO];
    md.textureType = MTLTextureType2DMultisample;
    md.sampleCount = CM_MSAA_SAMPLE_COUNT;
    md.usage       = MTLTextureUsageRenderTarget;
    /* Memoryless: samples live only in tile memory and are resolved at store;
     * never CPU-visible, never read back. */
    md.storageMode = MTLStorageModeMemoryless;
    id<MTLTexture> msaa = [mtl newTextureWithDescriptor:md];
    if (!msaa) return false;
    s->msaa_color_tex = (__bridge_retained void *)msaa;

    MTLTextureDescriptor *sd =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8
                                                           width:s->width
                                                          height:s->height
                                                       mipmapped:NO];
    sd.textureType = MTLTextureType2DMultisample;
    sd.sampleCount = CM_MSAA_SAMPLE_COUNT;
    sd.usage       = MTLTextureUsageRenderTarget;
    sd.storageMode = MTLStorageModeMemoryless;   /* transient coverage only     */
    id<MTLTexture> st = [mtl newTextureWithDescriptor:sd];
    if (!st) return false;
    s->stencil_tex = (__bridge_retained void *)st;
    return true;
}

/* ==========================================================================
 * Public: create / destroy
 * ========================================================================== */
/*
 * cm_image_surface_create -- format-general image surface.
 *
 * ARGB32/RGB24 are IOSurface-backed BGRA8 (the zero-copy path, byte-for-byte);
 * A8 is IOSurface-backed R8; RGB16_565 is IOSurface-backed B5G6R5.  All three
 * GPU-renderable formats build per-format MSAA colour + stencil attachments so
 * cm_device.m's cm_frame_begin reads s->format-derived textures.  A1 gets a CPU
 * backing (no IOSurface).  RGB30 is rejected INVALID.
 */
cm_surface_t *cm_image_surface_create(cm_format_t format, int width, int height)
{
    if (width <= 0 || height <= 0) {
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }
    /* RGB30 has no Metal/IOSurface backing here; INVALID is the cairo-exact
     * answer (cm_surface_format.c: not GPU-renderable, no FourCC). */
    if (format == CM_FORMAT_RGB30 || format == CM_FORMAT_INVALID) {
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }
    int min_stride = cm_format_stride_for_width(format, width);
    if (min_stride <= 0) {   /* unknown format slipped through */
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }

    cm_status_t dst = CM_STATUS_SUCCESS;
    cm_device *dev = cm_shared_device(&dst);
    if (!dev) { g_last_status = dst; return NULL; }

    cm_surface_t *s = (cm_surface_t *)calloc(1, sizeof(*s));
    if (!s) { g_last_status = CM_STATUS_NO_MEMORY; return NULL; }
    s->dev    = dev;
    s->kind   = CM_SURFACE_TYPE_IMAGE;
    s->format = format;
    s->width  = width;
    s->height = height;
    s->stride = (size_t)min_stride;     /* IOSurface alloc may widen this below  */
    s->status = CM_STATUS_SUCCESS;
    s->refcount = 1;                    /* creator holds the first reference     */

    /* A1 is sub-byte and not GPU-renderable: CPU backing only, no IOSurface. */
    if (format == CM_FORMAT_A1) {
        s->cpu_backing = calloc((size_t)s->stride * (size_t)height, 1);
        if (!s->cpu_backing) { g_last_status = CM_STATUS_NO_MEMORY; cm_surface_destroy(s); return NULL; }
        g_last_status = CM_STATUS_SUCCESS;
        return s;
    }

    @autoreleasepool {
        id<MTLDevice> mtl = cm_device_mtl_id(dev);
        if (!cm_surface_alloc_iosurface(s, mtl) ||
            !cm_surface_alloc_msaa(s, mtl)) {
            g_last_status = CM_STATUS_NO_MEMORY;
            cm_surface_destroy(s);
            return NULL;
        }
    }

    g_last_status = CM_STATUS_SUCCESS;
    return s;
}

/* ARGB32 alias of cm_image_surface_create (kept for the manim subset).  The
 * legacy entry only ever passed CM_FORMAT_ARGB32; honor whatever it is handed
 * (the general allocator validates it). */
cm_surface_t *cm_image_surface_create_argb32(cm_format_t format,
                                             int width, int height)
{
    return cm_image_surface_create(format, width, height);
}

/* ==========================================================================
 * Attach a GPU raster backing to an ALREADY-allocated surface struct.
 * --------------------------------------------------------------------------
 * Used by the RecordingSurface (cm_recording.m) to make a bounded recording
 * surface a real, drawable ARGB32/RGB24 GPU target while keeping its RECORDING
 * kind + op-log.  Runs the SAME IOSurface + MSAA/stencil allocation the normal
 * image-surface path uses (the two static helpers above) on `s`, so the result
 * is byte-for-byte the backing cm_frame_begin / cm_surface_color_texture read.
 *
 * `s` must be a freshly-zeroed struct with no GPU resources yet.  On success
 * `s->dev/format/width/height/stride` are set and the colour/MSAA/stencil
 * textures + IOSurface exist; returns true.  On failure any partial GPU state
 * is torn down (caller still owns the struct) and false is returned.  Only the
 * GPU-renderable formats (ARGB32/RGB24/A8/RGB16_565) are accepted; others (A1,
 * RGB30, INVALID) return false (no GPU raster backing possible).
 * ========================================================================== */
bool cm_surface_attach_gpu_backing(cm_surface_t *s, cm_format_t format,
                                   int width, int height)
{
    if (!s || width <= 0 || height <= 0) return false;
    if (format == CM_FORMAT_A1 || format == CM_FORMAT_RGB30 ||
        format == CM_FORMAT_INVALID)
        return false;

    int min_stride = cm_format_stride_for_width(format, width);
    if (min_stride <= 0) return false;

    cm_status_t dst = CM_STATUS_SUCCESS;
    cm_device *dev = cm_shared_device(&dst);
    if (!dev) return false;

    s->dev    = dev;
    s->format = format;
    s->width  = width;
    s->height = height;
    s->stride = (size_t)min_stride;

    bool ok = false;
    @autoreleasepool {
        id<MTLDevice> mtl = cm_device_mtl_id(dev);
        ok = cm_surface_alloc_iosurface(s, mtl) &&
             cm_surface_alloc_msaa(s, mtl);
    }
    if (!ok) {
        /* Release any partial GPU objects so the struct is clean again. */
        if (s->color_tex)      { CFRelease((CFTypeRef)s->color_tex);      s->color_tex = NULL; }
        if (s->msaa_color_tex) { CFRelease((CFTypeRef)s->msaa_color_tex); s->msaa_color_tex = NULL; }
        if (s->stencil_tex)    { CFRelease((CFTypeRef)s->stencil_tex);    s->stencil_tex = NULL; }
        if (s->iosurface)      { CFRelease((CFTypeRef)s->iosurface);      s->iosurface = NULL; }
        s->dev = NULL;
        return false;
    }
    return true;
}

/*
 * cm_image_surface_create_for_data -- record an external buffer + its stride.
 *
 * Allocates a GPU-renderable surface like create (so drawing works) and RECORDS
 * the external buffer + stride on the surface (ext_data/ext_stride) for the
 * shim's copy-back path.  The explicit stride is honored and must be >=
 * cm_format_stride_for_width(format,width) (cairo's contract).
 */
cm_surface_t *cm_image_surface_create_for_data(unsigned char *data,
                                               cm_format_t format,
                                               int width, int height, int stride)
{
    if (!data || width <= 0 || height <= 0) {
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }
    int min_stride = cm_format_stride_for_width(format, width);
    if (min_stride <= 0 || stride < min_stride) {
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }
    cm_surface_t *s = cm_image_surface_create(format, width, height);
    if (!s) return NULL;
    s->ext_data   = data;
    s->ext_stride = (size_t)stride;     /* recorded external row stride          */
    return s;
}

/*
 * cm_offscreen_surface_create -- INTERNAL non-IOSurface MSAA+resolve target for
 * push_group (consumed by cm_group.m).  Unlike a normal image surface, the
 * resolve destination is a PRIVATE MTLTexture (no IOSurface): the group result
 * is sampled back as a SurfacePattern, never handed to VideoToolbox, so it must
 * not consume an IOSurface.  It still allocates per-format MSAA colour + stencil
 * so the same cm_frame_begin drives it.  The content selects the concrete
 * format (COLOR->RGB24, ALPHA->A8, COLOR_ALPHA->ARGB32).
 */
cm_surface_t *cm_offscreen_surface_create(int width, int height, cm_content_t content)
{
    if (width <= 0 || height <= 0) {
        g_last_status = CM_STATUS_INVALID_FORMAT;
        return NULL;
    }
    cm_format_t fmt = cm_format_for_content(content);
    int min_stride = cm_format_stride_for_width(fmt, width);
    if (min_stride <= 0) { g_last_status = CM_STATUS_INVALID_FORMAT; return NULL; }

    cm_status_t dst = CM_STATUS_SUCCESS;
    cm_device *dev = cm_shared_device(&dst);
    if (!dev) { g_last_status = dst; return NULL; }

    cm_surface_t *s = (cm_surface_t *)calloc(1, sizeof(*s));
    if (!s) { g_last_status = CM_STATUS_NO_MEMORY; return NULL; }
    s->dev    = dev;
    s->kind   = CM_SURFACE_TYPE_IMAGE;   /* an image surface; just non-IOSurface */
    s->format = fmt;
    s->width  = width;
    s->height = height;
    s->stride = (size_t)min_stride;
    s->status = CM_STATUS_SUCCESS;
    s->refcount = 1;                     /* creator holds the first reference     */

    @autoreleasepool {
        id<MTLDevice> mtl = cm_device_mtl_id(dev);
        /* Private resolve target (no IOSurface) + per-format MSAA + stencil. */
        if (!cm_surface_alloc_private_color(s, mtl) ||
            !cm_surface_alloc_msaa(s, mtl)) {
            g_last_status = CM_STATUS_NO_MEMORY;
            cm_surface_destroy(s);
            return NULL;
        }
    }

    g_last_status = CM_STATUS_SUCCESS;
    return s;
}

/* Take one lifetime reference (refcount++).  See cm_surface_destroy for the
 * matching drop.  A refcount of 0 (a surface that predates refcounting, e.g. a
 * map_to_image alias freed via the wrapper path) is treated as 1 by destroy, so a
 * reference here on such a surface still balances. */
cm_surface_t *cm_surface_reference(cm_surface_t *s)
{
    if (s) s->refcount++;
    return s;
}

void cm_surface_destroy(cm_surface_t *s)
{
    if (!s) return;
    /* Reference decrement: free the backing + struct only on the LAST reference.
     * A surface created before this field existed, or a lightweight alias wrapper
     * that never set it, has refcount 0/1 here -> this call frees it (the common
     * single-owner case).  Multiple owners (the Python wrapper + N SurfacePatterns,
     * or a group-pop pattern) each call destroy once; only the last frees. */
    if (s->refcount > 1) { s->refcount--; return; }
    /* Ensure no in-flight command buffer still references this surface's
     * textures before we release them: end + wait on any active draw frame. */
    cm_glue_end_frame_for_surface(s, /*wait=*/true);
    @autoreleasepool {
        /* Balance the __bridge_retained on each texture. */
        if (s->color_tex)      { CFRelease(s->color_tex);      s->color_tex = NULL; }
        if (s->msaa_color_tex) { CFRelease(s->msaa_color_tex); s->msaa_color_tex = NULL; }
        if (s->stencil_tex)    { CFRelease(s->stencil_tex);    s->stencil_tex = NULL; }
    }
    if (s->iosurface) { CFRelease((IOSurfaceRef)s->iosurface); s->iosurface = NULL; }
    /* CPU backing (A1) + recording op-log, if any. */
    if (s->cpu_backing) { free(s->cpu_backing); s->cpu_backing = NULL; }
    if (s->record)      { free(s->record);      s->record = NULL; }
    /* The device is process-shared; surfaces do not own it. */
    free(s);
}

/* ==========================================================================
 * Introspection + lifecycle (full contract)
 * ========================================================================== */
cm_format_t cm_surface_get_format(cm_surface_t *s)
{
    return s ? s->format : CM_FORMAT_INVALID;
}

int cm_surface_get_stride(cm_surface_t *s)
{
    return s ? (int)s->stride : 0;
}

cm_content_t cm_surface_get_content(cm_surface_t *s)
{
    return s ? cm_content_for_format(s->format) : CM_CONTENT_COLOR_ALPHA;
}

cm_surface_type_t cm_surface_get_type(cm_surface_t *s)
{
    return s ? s->kind : CM_SURFACE_TYPE_IMAGE;
}

cm_status_t cm_surface_status(cm_surface_t *s)
{
    return s ? s->status : CM_STATUS_NO_MEMORY;
}

/*
 * cm_surface_finish -- flush + release backing, mark finished.
 *
 * Commit + wait on any active frame (MSAA->colour resolve at its store action),
 * then release the GPU/CPU backing and mark the surface finished.  Per cairo
 * semantics, the introspection accessors (format/stride/content/type/width/
 * height/status) remain valid afterwards; further DRAWING is an error (the draw
 * path checks s->finished).  Releasing the backing here is what makes map() /
 * get_iosurface() return NULL on a finished surface, matching cairo (the pixel
 * data is gone once finished).
 */
void cm_surface_finish(cm_surface_t *s)
{
    if (!s) return;
    if (s->finished) return;            /* idempotent */

    /* Flush + commit any active frame so nothing in flight references the
     * textures we are about to release. */
    cm_glue_end_frame_for_surface(s, /*wait=*/true);

    @autoreleasepool {
        if (s->color_tex)      { CFRelease(s->color_tex);      s->color_tex = NULL; }
        if (s->msaa_color_tex) { CFRelease(s->msaa_color_tex); s->msaa_color_tex = NULL; }
        if (s->stencil_tex)    { CFRelease(s->stencil_tex);    s->stencil_tex = NULL; }
    }
    if (s->iosurface)   { CFRelease((IOSurfaceRef)s->iosurface); s->iosurface = NULL; }
    if (s->cpu_backing) { free(s->cpu_backing); s->cpu_backing = NULL; }

    s->finished = true;
    s->status   = CM_STATUS_SUCCESS;
}

void cm_surface_mark_dirty(cm_surface_t *s)
{
    (void)s;   /* coherence no-op on shared storage */
}

void cm_surface_mark_dirty_rectangle(cm_surface_t *s, int x, int y, int w, int h)
{
    (void)s; (void)x; (void)y; (void)w; (void)h;   /* coherence no-op */
}

void cm_surface_set_device_offset(cm_surface_t *s, double x_offset, double y_offset)
{
    if (!s) return;
    s->dev_off_x = x_offset;
    s->dev_off_y = y_offset;
}

void cm_surface_get_device_offset(cm_surface_t *s, double *x_offset, double *y_offset)
{
    if (x_offset) *x_offset = s ? s->dev_off_x : 0.0;
    if (y_offset) *y_offset = s ? s->dev_off_y : 0.0;
}

/* ==========================================================================
 * CPU map (format-aware) + ARGB32 alias
 * ========================================================================== */

/* Format-aware CPU map: A1 returns its malloc'd cpu_backing; every IOSurface-
 * backed format returns the IOSurface base in cairo's native row layout for that
 * format (premultiplied B,G,R,A for ARGB32, single-channel for A8, 16-bit for
 * 565).  out_stride receives the row stride in bytes (the IOSurface's own
 * bytes-per-row, which may exceed the cairo minimum). */
void *cm_surface_map(cm_surface_t *s, size_t *out_stride)
{
    if (!s) { if (out_stride) *out_stride = 0; return NULL; }
    /* A map_to_image alias owns no pixels: resolve through its parent and offset
     * to the mapped sub-rect (cm_surface_map_to_image records mapped_parent +
     * mapped_rect).  This is the CPU read path get_data() relies on. */
    if (s->mapped_parent) {
        size_t pstride = 0;
        unsigned char *pbase = (unsigned char *)cm_surface_map(s->mapped_parent, &pstride);
        if (!pbase) { if (out_stride) *out_stride = 0; return NULL; }
        if (out_stride) *out_stride = pstride;
        int bpp = cm_format_bytes_per_pixel(s->format);
        if (bpp <= 0) bpp = 4;
        return pbase + (size_t)s->mapped_rect.y * pstride
                     + (size_t)s->mapped_rect.x * (size_t)bpp;
    }
    if (s->cpu_backing) {
        if (out_stride) *out_stride = s->stride;
        return s->cpu_backing;
    }
    return cm_surface_map_argb32(s, out_stride);
}

/* ARGB32 alias of cm_surface_map (kept for the manim subset).  BYTE-FOR-BYTE
 * the premultiplied B,G,R,A row layout of a cairo ARGB32 image surface: the
 * IOSurface is shared with the GPU texture, so its base address IS the memory
 * the renderer wrote (after the flush+resolve below). */
void *cm_surface_map_argb32(cm_surface_t *s, size_t *out_stride)
{
    /* A map_to_image alias borrows its parent's pixels: resolve through the
     * generic map (which follows mapped_parent + applies the sub-rect offset). */
    if (s && s->mapped_parent)
        return cm_surface_map(s, out_stride);
    if (!s || !s->iosurface) {
        if (out_stride) *out_stride = 0;
        return NULL;
    }
    IOSurfaceRef io = (IOSurfaceRef)s->iosurface;

    /* Make the latest GPU output coherent for CPU reads: end + wait on any
     * active draw frame (resolves MSAA into this IOSurface).  No-op if idle. */
    cm_surface_flush(s);

    /* Lock for CPU access; the IOSurface is shared with the GPU texture, so the
     * base address is the same memory the renderer wrote (after flush). We do
     * not hold the lock across calls (the GPU may render again), so this returns
     * the stable base address and the caller reads it directly. With shared
     * storage the lock is a coherence fence, not a copy. */
    IOSurfaceLock(io, kIOSurfaceLockReadOnly, NULL);
    void *base = IOSurfaceGetBaseAddress(io);
    if (out_stride) *out_stride = IOSurfaceGetBytesPerRow(io);
    IOSurfaceUnlock(io, kIOSurfaceLockReadOnly, NULL);
    return base;
}

/* ==========================================================================
 * map_to_image / unmap_image
 * --------------------------------------------------------------------------
 * cairo_surface_map_to_image returns a fresh image surface that ALIASES the
 * target's pixels for direct CPU access; unmap writes back (a no-op for us:
 * shared IOSurface storage) and releases it.  We alias by handing back a thin
 * image-surface wrapper whose pixel base IS the parent IOSurface's base address
 * (no copy), recording the parent (retained-by-pointer) + the mapped rect so
 * unmap can validate.  For a whole-surface map this is the zero-copy fast path
 * the manim/pycairo flow relies on; for a sub-rect the wrapper still aliases the
 * full base (callers index it with the rect offset + the parent stride).
 *
 * NOTE: the returned wrapper is NOT a standalone IOSurface-backed surface -- it
 * borrows the parent's IOSurface (mapped_parent), so destroying it must NOT
 * release that IOSurface.  cm_surface_unmap_image is the only correct way to
 * release a mapped image; it frees the wrapper without touching the parent.
 * ========================================================================== */
cm_surface_t *cm_surface_map_to_image(cm_surface_t *s, const cm_rectangle_int_t *extents)
{
    if (!s) { cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH); return NULL; }
    if (s->finished) { cm_set_last_status(CM_STATUS_SURFACE_FINISHED); return NULL; }
    /* Only IOSurface-backed (or CPU-backed) surfaces can be mapped to an image
     * that aliases real pixels; a subsurface/recording target cannot. */
    if (!s->iosurface && !s->cpu_backing) {
        cm_set_last_status(CM_STATUS_SURFACE_TYPE_MISMATCH);
        return NULL;
    }

    int rx = extents ? extents->x : 0;
    int ry = extents ? extents->y : 0;
    int rw = extents ? extents->width  : s->width;
    int rh = extents ? extents->height : s->height;
    /* Clamp the requested rect to the surface (cairo intersects with bounds). */
    if (rx < 0) { rw += rx; rx = 0; }
    if (ry < 0) { rh += ry; ry = 0; }
    if (rx > s->width)  rx = s->width;
    if (ry > s->height) ry = s->height;
    if (rx + rw > s->width)  rw = s->width  - rx;
    if (ry + rh > s->height) rh = s->height - ry;
    if (rw < 0) rw = 0;
    if (rh < 0) rh = 0;

    /* Make the parent's pixels coherent before aliasing them. */
    cm_surface_flush(s);

    cm_surface_t *img = (cm_surface_t *)calloc(1, sizeof(*img));
    if (!img) { cm_set_last_status(CM_STATUS_NO_MEMORY); return NULL; }
    img->dev    = s->dev;
    img->kind   = CM_SURFACE_TYPE_IMAGE;
    img->format = s->format;
    img->width  = rw;
    img->height = rh;
    img->stride = s->stride;            /* parent row stride (alias)             */
    img->status = CM_STATUS_SUCCESS;
    img->refcount = 1;                  /* alias wrapper holds its own reference  */

    /* Alias the parent base -- NO own IOSurface / textures.  The parent is
     * recorded so unmap can validate; we retain it by pointer (the caller must
     * keep the parent alive across the map, exactly as cairo requires). */
    img->mapped_parent      = s;
    img->mapped_rect.x      = rx;
    img->mapped_rect.y      = ry;
    img->mapped_rect.width  = rw;
    img->mapped_rect.height = rh;

    cm_set_last_status(CM_STATUS_SUCCESS);
    return img;
}

void cm_surface_unmap_image(cm_surface_t *s, cm_surface_t *image)
{
    if (!image) return;
    /* Write-back is a no-op on shared IOSurface storage (the mapped image
     * aliased the parent's pixels directly -- there is nothing to copy back).
     * Tear down the alias wrapper WITHOUT touching the parent: it never owned an
     * IOSurface or textures, so a plain free is correct (cm_surface_destroy
     * would also be safe since those fields are NULL, but this makes the "borrows
     * the parent" contract explicit and avoids ending a frame on the alias). */
    (void)s;
    if (image->mapped_parent) {
        image->mapped_parent = NULL;
        free(image);
        return;
    }
    /* Not one of ours (no recorded parent): fall back to a full destroy. */
    cm_surface_destroy(image);
}

/* ==========================================================================
 * Internal accessors used by cm_device.m to build the render pass
 * ========================================================================== */
void *cm_surface_color_texture (cm_surface_t *s) { return s ? s->color_tex      : NULL; }
void *cm_surface_msaa_color_tex(cm_surface_t *s) { return s ? s->msaa_color_tex : NULL; }
void *cm_surface_stencil_tex   (cm_surface_t *s) { return s ? s->stencil_tex    : NULL; }

/* Called by cm_frame_end after commit: the resolved colour texture now holds
 * fresh pixels.  With MTLStorageModeShared there is nothing to synchronize on
 * Apple Silicon, but keep the hook so cm_surface_map_argb32 / the encode handoff
 * have a single, documented "GPU just wrote this" signal. */
void cm_surface_did_render(cm_surface_t *s) { (void)s; }

/* ==========================================================================
 * Flush
 * --------------------------------------------------------------------------
 * Make all GPU drawing for this surface coherent for CPU read (map) and for a
 * downstream VideoToolbox encode of the IOSurface, blocking until complete.
 *
 * cm_device.m owns the per-frame command buffer (cm_frame), which the context
 * draw driver (cairo_metal.m) begins on the first draw of a frame.  Flush is the
 * frame boundary in manim's flow (camera draws all VMobjects, then calls
 * surface.flush()).  We end that active frame here with wait=true:
 * cm_frame_end commits the single command buffer (whose store action RESOLVES
 * the MSAA samples into this surface's colour texture) and blocks until the GPU
 * has completed, so the IOSurface is coherent for a CPU map and for a downstream
 * VideoToolbox encode.  If no drawing happened since the last flush there is no
 * active frame and this is a cheap no-op.
 * ========================================================================== */
void cm_surface_flush(cm_surface_t *s)
{
    if (!s) return;
    /* Commit + wait on this surface's active draw frame (MSAA->colour resolve
     * happens at its store action).  No-op if nothing was drawn. */
    cm_glue_end_frame_for_surface(s, /*wait=*/true);
    cm_surface_did_render(s);
}

/* ==========================================================================
 * Zero-copy handle for VideoToolbox
 * ========================================================================== */
void *cm_surface_get_iosurface(cm_surface_t *s)
{
    if (!s) return NULL;
    /* Owned by the surface; caller must NOT release.  Caller should have called
     * cm_surface_flush() first so the resolved pixels are valid.  NULL for A1 /
     * offscreen-private / finished surfaces (no IOSurface backing). */
    return s->iosurface;
}

int cm_surface_get_width (const cm_surface_t *s) { return s ? s->width  : 0; }
int cm_surface_get_height(const cm_surface_t *s) { return s ? s->height : 0; }
