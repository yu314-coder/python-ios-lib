/*
 * cairo_metal.h  --  CairoMetal public C API
 * ============================================================================
 *
 * A Metal-GPU implementation of the cairo 2D graphics API.  The library began
 * as the *exact* subset manim's iOS Cairo renderer (manim/camera/camera.py)
 * calls; it now declares the FULL cairo-compatible contract (surfaces, context
 * state, transforms, paths, patterns, regions, text/fonts, queries) so a
 * pycairo-compatible shim can forward the whole class graph.  Each declaration
 * is implemented by exactly one owner module (see src/cm_internal.h's module
 * map); functions whose bodies are still stubs return safe defaults.
 *
 * The original raison d'etre stands: manim's `Camera` draws every frame into a
 * `cairo.ImageSurface.create_for_data(...)` ARGB32 buffer on the CPU, then that
 * buffer is uploaded to the H.264 encoder.  On iOS that round trip (CPU
 * rasterize -> copy -> upload to VideoToolbox) is the bottleneck.  CairoMetal
 * renders the same vector paths on the GPU into an *IOSurface-backed*
 * MTLTexture so the rendered frame can be handed to `h264_videotoolbox` with
 * ZERO copies (the IOSurface IS the encoder's input pixel buffer).
 *
 * ----------------------------------------------------------------------------
 * PIXEL FORMAT CONTRACT  (do not "fix" this -- it matches cairo + manim)
 * ----------------------------------------------------------------------------
 * cairo FORMAT_ARGB32 is a 32-bit *native-endian* pixel: on little-endian
 * arm64 the bytes in memory are  B, G, R, A  with **premultiplied** alpha.
 * The backing MTLTexture therefore uses MTLPixelFormatBGRA8Unorm.
 *
 * manim already pre-swaps colours into B,G,R order before handing them to
 * cairo (see camera.py: `ctx.set_source_rgba(*rgbas[0][2::-1], rgbas[0][3])`
 * and `pat.add_color_stop_rgba(offset, *rgba[2::-1], rgba[3])`).  Because our
 * target has the identical BGRA byte layout, the CairoMetal drop-in keeps the
 * SAME argument order: callers pass (r, g, b, a) exactly as they pass them to
 * cairo, i.e. already B,G,R,A from manim's point of view.  We do not re-swap.
 * We DO premultiply on the GPU, matching cairo's premultiplied surface.
 *
 * ----------------------------------------------------------------------------
 * THREADING / OWNERSHIP
 * ----------------------------------------------------------------------------
 * - All cm_* calls for a given cm_context_t must come from one thread (same as
 *   a cairo_t).  This mirrors manim, which drives one context per pixel array.
 * - Objects are reference-managed by explicit create/destroy or reference/
 *   destroy.  A context retains its surface; destroying the context does NOT
 *   destroy the surface.
 * - cm_pattern_t handed to cm_set_source is retained by the context until the
 *   next set_source / set_source_rgba; the caller may destroy its own ref.
 *
 * ============================================================================
 */
#ifndef CAIRO_METAL_H
#define CAIRO_METAL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#  define CM_PUBLIC __attribute__((visibility("default")))
#else
#  define CM_PUBLIC
#endif

/* ==========================================================================
 * Version
 * ========================================================================== */
#define CM_CAIRO_VERSION_MAJOR  1
#define CM_CAIRO_VERSION_MINOR  18
#define CM_CAIRO_VERSION_MICRO  0
#define CM_CAIRO_VERSION_STRING "1.18.0"
/* cairo encodes version as major*10000 + minor*100 + micro. */
#define CM_CAIRO_VERSION        11800

CM_PUBLIC int          cm_version(void);
CM_PUBLIC const char  *cm_version_string(void);

/* ==========================================================================
 * Opaque types  (mirror cairo_surface_t / cairo_t / cairo_pattern_t / ...)
 * ========================================================================== */

/** Render target: a raster backed (for GPU-renderable formats) by an
 *  IOSurface-backed MTLTexture.  Mirrors cairo_surface_t. */
typedef struct cm_surface  cm_surface_t;

/** Drawing context bound to one surface.  Mirrors cairo_t. */
typedef struct cm_context  cm_context_t;

/** A paint source (solid / gradient / surface / mesh / raster).
 *  Mirrors cairo_pattern_t. */
typedef struct cm_pattern  cm_pattern_t;

/** A set of integer rectangles.  Mirrors cairo_region_t. */
typedef struct cm_region        cm_region_t;
/** A font face (toy / FT / user).  Mirrors cairo_font_face_t. */
typedef struct cm_font_face     cm_font_face_t;
/** A font scaled to a particular size + CTM.  Mirrors cairo_scaled_font_t. */
typedef struct cm_scaled_font   cm_scaled_font_t;
/** Rendering options for a scaled font.  Mirrors cairo_font_options_t. */
typedef struct cm_font_options  cm_font_options_t;

/* ==========================================================================
 * Enums  (numerically identical to the cairo enums so int maps transfer)
 * ========================================================================== */

/** Mirrors cairo_status_t (subset + extensions).  CM_STATUS_SUCCESS == 0.
 *  The first 7 values are STABLE (woven through every internal signature);
 *  the rest are appended for the full public surface.  The public,
 *  cairo-numbered status is produced by cm_to_cairo_status(). */
typedef enum {
    CM_STATUS_SUCCESS = 0,
    CM_STATUS_NO_MEMORY,            /* allocation / buffer pool exhausted     */
    CM_STATUS_NO_METAL_DEVICE,      /* MTLCreateSystemDefaultDevice == nil    */
    CM_STATUS_INVALID_FORMAT,       /* unsupported width/height/format        */
    CM_STATUS_SURFACE_TYPE_MISMATCH,/* op needs an IOSurface target           */
    CM_STATUS_INVALID_MATRIX,       /* non-invertible CTM passed              */
    CM_STATUS_DEVICE_ERROR,         /* command buffer / pipeline build failed */
    /* --- appended (full contract) --- */
    CM_STATUS_INVALID_RESTORE,      /* cm_restore without matching cm_save    */
    CM_STATUS_INVALID_POP_GROUP,    /* pop_group without matching push_group  */
    CM_STATUS_NO_CURRENT_POINT,     /* rel_* / op needs a current point       */
    CM_STATUS_INVALID_DASH,         /* negative / all-zero dash pattern       */
    CM_STATUS_CLIP_NOT_REPRESENTABLE,/* copy_clip_rectangle_list non-rect     */
    CM_STATUS_INVALID_INDEX,        /* out-of-range region/glyph index        */
    CM_STATUS_PATTERN_TYPE_MISMATCH,/* op needs a different pattern type       */
    CM_STATUS_SURFACE_FINISHED,     /* op on a finished surface               */
    CM_STATUS_FONT_TYPE_MISMATCH    /* op needs a different font type         */
} cm_status_t;

/** Mirrors cairo_fill_rule_t exactly (same values). */
typedef enum {
    CM_FILL_RULE_WINDING  = 0,      /* cairo CAIRO_FILL_RULE_WINDING  (NONZERO)*/
    CM_FILL_RULE_EVEN_ODD = 1       /* cairo CAIRO_FILL_RULE_EVEN_ODD          */
} cm_fill_rule_t;

/** Mirrors cairo_line_cap_t exactly (same values). */
typedef enum {
    CM_LINE_CAP_BUTT   = 0,
    CM_LINE_CAP_ROUND  = 1,
    CM_LINE_CAP_SQUARE = 2
} cm_line_cap_t;

/** Mirrors cairo_line_join_t exactly (same values). */
typedef enum {
    CM_LINE_JOIN_MITER = 0,
    CM_LINE_JOIN_ROUND = 1,
    CM_LINE_JOIN_BEVEL = 2
} cm_line_join_t;

/** Pixel format of a surface.  Mirrors cairo_format_t exactly.
 *  ARGB32/RGB24 -> BGRA8; A8 -> R8; A1 -> 1bpp cpu_backing; RGB16_565 ->
 *  B5G6R5; RGB30 -> unsupported (INVALID). */
typedef enum {
    CM_FORMAT_INVALID   = -1,
    CM_FORMAT_ARGB32    = 0,
    CM_FORMAT_RGB24     = 1,
    CM_FORMAT_A8        = 2,
    CM_FORMAT_A1        = 3,
    CM_FORMAT_RGB16_565 = 4,
    CM_FORMAT_RGB30     = 5
} cm_format_t;

/** Mirrors cairo_content_t (BIT FLAGS, not 0/1/2). */
typedef enum {
    CM_CONTENT_COLOR       = 0x1000,
    CM_CONTENT_ALPHA       = 0x2000,
    CM_CONTENT_COLOR_ALPHA = 0x3000
} cm_content_t;

/** Mirrors cairo_surface_type_t (subset). */
typedef enum {
    CM_SURFACE_TYPE_IMAGE      = 0,
    CM_SURFACE_TYPE_RECORDING  = 7,
    CM_SURFACE_TYPE_SUBSURFACE = 11
} cm_surface_type_t;

/** Mirrors cairo_operator_t exactly (0..28 contiguous). */
typedef enum {
    CM_OPERATOR_CLEAR = 0,
    CM_OPERATOR_SOURCE,
    CM_OPERATOR_OVER,
    CM_OPERATOR_IN,
    CM_OPERATOR_OUT,
    CM_OPERATOR_ATOP,
    CM_OPERATOR_DEST,
    CM_OPERATOR_DEST_OVER,
    CM_OPERATOR_DEST_IN,
    CM_OPERATOR_DEST_OUT,
    CM_OPERATOR_DEST_ATOP,
    CM_OPERATOR_XOR,
    CM_OPERATOR_ADD,
    CM_OPERATOR_SATURATE,
    CM_OPERATOR_MULTIPLY,
    CM_OPERATOR_SCREEN,
    CM_OPERATOR_OVERLAY,
    CM_OPERATOR_DARKEN,
    CM_OPERATOR_LIGHTEN,
    CM_OPERATOR_COLOR_DODGE,
    CM_OPERATOR_COLOR_BURN,
    CM_OPERATOR_HARD_LIGHT,
    CM_OPERATOR_SOFT_LIGHT,
    CM_OPERATOR_DIFFERENCE,
    CM_OPERATOR_EXCLUSION,
    CM_OPERATOR_HSL_HUE,
    CM_OPERATOR_HSL_SATURATION,
    CM_OPERATOR_HSL_COLOR,
    CM_OPERATOR_HSL_LUMINOSITY
} cm_operator_t;

/** Mirrors cairo_antialias_t exactly. */
typedef enum {
    CM_ANTIALIAS_DEFAULT  = 0,
    CM_ANTIALIAS_NONE,
    CM_ANTIALIAS_GRAY,
    CM_ANTIALIAS_SUBPIXEL,
    CM_ANTIALIAS_FAST,
    CM_ANTIALIAS_GOOD,
    CM_ANTIALIAS_BEST
} cm_antialias_t;

/** Mirrors cairo_extend_t exactly. */
typedef enum {
    CM_EXTEND_NONE = 0,
    CM_EXTEND_REPEAT,
    CM_EXTEND_REFLECT,
    CM_EXTEND_PAD
} cm_extend_t;

/** Mirrors cairo_filter_t exactly. */
typedef enum {
    CM_FILTER_FAST = 0,
    CM_FILTER_GOOD,
    CM_FILTER_BEST,
    CM_FILTER_NEAREST,
    CM_FILTER_BILINEAR,
    CM_FILTER_GAUSSIAN
} cm_filter_t;

/** Mirrors cairo_pattern_type_t exactly. */
typedef enum {
    CM_PATTERN_TYPE_SOLID = 0,
    CM_PATTERN_TYPE_SURFACE,
    CM_PATTERN_TYPE_LINEAR,
    CM_PATTERN_TYPE_RADIAL,
    CM_PATTERN_TYPE_MESH,
    CM_PATTERN_TYPE_RASTER_SOURCE
} cm_pattern_type_t;

/** Mirrors cairo_path_data_type_t exactly.  DISTINCT from the internal
 *  cm_path_verb enum -- do not conflate. */
typedef enum {
    CM_PATH_MOVE_TO = 0,
    CM_PATH_LINE_TO,
    CM_PATH_CURVE_TO,
    CM_PATH_CLOSE_PATH
} cm_path_data_type_t;

/** Mirrors cairo_region_overlap_t exactly. */
typedef enum {
    CM_REGION_OVERLAP_IN = 0,
    CM_REGION_OVERLAP_OUT,
    CM_REGION_OVERLAP_PART
} cm_region_overlap_t;

/** Mirrors cairo_font_slant_t exactly. */
typedef enum {
    CM_FONT_SLANT_NORMAL = 0,
    CM_FONT_SLANT_ITALIC,
    CM_FONT_SLANT_OBLIQUE
} cm_font_slant_t;

/** Mirrors cairo_font_weight_t exactly. */
typedef enum {
    CM_FONT_WEIGHT_NORMAL = 0,
    CM_FONT_WEIGHT_BOLD
} cm_font_weight_t;

/** Mirrors cairo_font_type_t (subset). */
typedef enum {
    CM_FONT_TYPE_TOY = 0,
    CM_FONT_TYPE_FT,
    CM_FONT_TYPE_USER
} cm_font_type_t;

/** Mirrors cairo_subpixel_order_t exactly. */
typedef enum {
    CM_SUBPIXEL_ORDER_DEFAULT = 0,
    CM_SUBPIXEL_ORDER_RGB,
    CM_SUBPIXEL_ORDER_BGR,
    CM_SUBPIXEL_ORDER_VRGB,
    CM_SUBPIXEL_ORDER_VBGR
} cm_subpixel_order_t;

/** Mirrors cairo_hint_style_t exactly. */
typedef enum {
    CM_HINT_STYLE_DEFAULT = 0,
    CM_HINT_STYLE_NONE,
    CM_HINT_STYLE_SLIGHT,
    CM_HINT_STYLE_MEDIUM,
    CM_HINT_STYLE_FULL
} cm_hint_style_t;

/** Mirrors cairo_hint_metrics_t exactly. */
typedef enum {
    CM_HINT_METRICS_DEFAULT = 0,
    CM_HINT_METRICS_OFF,
    CM_HINT_METRICS_ON
} cm_hint_metrics_t;

/** Mirrors cairo_text_cluster_flags_t exactly. */
typedef enum {
    CM_TEXT_CLUSTER_FLAG_BACKWARD = 0x00000001
} cm_text_cluster_flags_t;

/* ==========================================================================
 * Public status mapping (cairo-numbered)
 * --------------------------------------------------------------------------
 * cm_status_t values are STABLE internal codes; the public API reports the
 * cairo-exact integer status (e.g. INVALID_MATRIX -> 5, INVALID_FORMAT -> 16,
 * NO_METAL_DEVICE -> DEVICE_ERROR == 35).  cm_to_cairo_status maps a cm code to
 * the cairo number; cm_cairo_status_to_string returns the cairo message for a
 * cairo-numbered status.  (cm_status_to_string remains for device messages.)
 * ========================================================================== */
CM_PUBLIC int          cm_to_cairo_status(cm_status_t status);
CM_PUBLIC const char  *cm_cairo_status_to_string(int cairo_status);

/* ==========================================================================
 * Value structs  (binary-compatible with the matching cairo structs)
 * ========================================================================== */

/** Affine transform; binary-compatible with cairo_matrix_t.
 *   x_new = xx*x + xy*y + x0 ;  y_new = yx*x + yy*y + y0
 *  Field order is IDENTICAL to cairo_matrix_t: a cairo.Matrix(a,b,c,d,e,f) maps
 *  a=xx, b=yx, c=xy, d=yy, e=x0, f=y0. */
typedef struct {
    double xx; double yx;
    double xy; double yy;
    double x0; double y0;
} cm_matrix_t;

/** Double rectangle (cairo's general rect: e.g. clip/path extents results). */
typedef struct { double x, y, width, height; } cm_rect_t;

/** Float rectangle; binary-compatible with cairo_rectangle_t. */
typedef struct { double x, y, width, height; } cm_rectangle_t;

/** Integer rectangle; binary-compatible with cairo_rectangle_int_t. */
typedef struct { int x, y, width, height; } cm_rectangle_int_t;

/** A positioned glyph; binary-compatible with cairo_glyph_t. */
typedef struct { unsigned long index; double x, y; } cm_glyph_t;

/** A text cluster mapping; binary-compatible with cairo_text_cluster_t. */
typedef struct { int num_bytes; int num_glyphs; } cm_text_cluster_t;

/** One element of a copied path (cm_copy_path / cm_copy_path_flat).
 *  `type` selects how many of `points[]` are meaningful, mirroring cairo's
 *  cairo_path_data_t header+point grouping but flattened into ONE struct:
 *    CM_PATH_MOVE_TO   -> points[0..1]  = (x,  y)
 *    CM_PATH_LINE_TO   -> points[0..1]  = (x,  y)
 *    CM_PATH_CURVE_TO  -> points[0..5]  = (x1, y1, x2, y2, x3, y3)
 *    CM_PATH_CLOSE_PATH-> (no points)
 *  Coordinates are in USER space, exactly like cairo_copy_path. */
typedef struct {
    cm_path_data_type_t type;
    double              points[6];
} cm_path_element_t;

/** A copied path: a heap array of elements + a status, returned by
 *  cm_copy_path / cm_copy_path_flat and consumed by cm_append_path.  Mirrors
 *  the role of cairo_path_t (which exposes `status`, `data`, `num_data`); here
 *  `num_elements` counts cm_path_element_t entries (cairo's num_data counts
 *  cairo_path_data_t headers+points, a different unit, so this is NOT binary
 *  compatible -- the pycairo binding iterates it and yields cairo-shaped
 *  tuples).  Always release with cm_path_data_destroy().  On allocation failure
 *  the returned struct has status != CM_STATUS_SUCCESS, elements == NULL and
 *  num_elements == 0 (still safe to pass to cm_path_data_destroy). */
typedef struct {
    cm_status_t        status;
    cm_path_element_t *elements;
    int                num_elements;
} cm_path_data_t;

/** Text extents; binary-compatible with cairo_text_extents_t. */
typedef struct {
    double x_bearing, y_bearing, width, height, x_advance, y_advance;
} cm_text_extents_t;

/** Font extents; binary-compatible with cairo_font_extents_t. */
typedef struct {
    double ascent, descent, height, max_x_advance, max_y_advance;
} cm_font_extents_t;

/* ==========================================================================
 * Matrix algebra  (binary-compatible with cairo_matrix_* ; pycairo Matrix maps
 * straight onto these)
 * ========================================================================== */
CM_PUBLIC void cm_matrix_init(cm_matrix_t *m, double xx, double yx,
                              double xy, double yy, double x0, double y0);
CM_PUBLIC void cm_matrix_init_identity(cm_matrix_t *m);
CM_PUBLIC void cm_matrix_init_translate(cm_matrix_t *m, double tx, double ty);
CM_PUBLIC void cm_matrix_init_scale(cm_matrix_t *m, double sx, double sy);
CM_PUBLIC void cm_matrix_init_rotate(cm_matrix_t *m, double radians);
CM_PUBLIC void cm_matrix_translate(cm_matrix_t *m, double tx, double ty);
CM_PUBLIC void cm_matrix_scale(cm_matrix_t *m, double sx, double sy);
CM_PUBLIC void cm_matrix_rotate(cm_matrix_t *m, double radians);
/** result = apply `a` FIRST then `b` (cairo_matrix_multiply; alias-safe). */
CM_PUBLIC void cm_matrix_multiply(cm_matrix_t *result, const cm_matrix_t *a,
                                  const cm_matrix_t *b);
/** Invert in place; CM_STATUS_INVALID_MATRIX if singular. */
CM_PUBLIC cm_status_t cm_matrix_invert(cm_matrix_t *m);
CM_PUBLIC void cm_matrix_transform_point(const cm_matrix_t *m, double *x, double *y);
CM_PUBLIC void cm_matrix_transform_distance(const cm_matrix_t *m, double *dx, double *dy);
/** Transform the 4 corners of (x1,y1)-(x2,y2) and return the AABB. */
CM_PUBLIC void cm_matrix_transform_bbox(const cm_matrix_t *m,
                                        double x1, double y1, double x2, double y2,
                                        double *ox1, double *oy1,
                                        double *ox2, double *oy2);

/** RasterSourcePattern acquire/release callback signatures (opaque surface). */
typedef cm_surface_t *(*cm_raster_acquire_func_t)(cm_pattern_t *pattern,
                                                  void *callback_data,
                                                  cm_surface_t *target,
                                                  const cm_rectangle_int_t *extents);
typedef void (*cm_raster_release_func_t)(cm_pattern_t *pattern,
                                         void *callback_data,
                                         cm_surface_t *surface);

/* ==========================================================================
 * Surface API   (cairo image-surface subset, IOSurface-backed where possible)
 * ========================================================================== */

/** Create a format-general image surface.  ARGB32/RGB24/A8/RGB16_565 are
 *  IOSurface-backed (GPU renderable); A1 uses CPU backing; RGB30 is rejected
 *  (INVALID_FORMAT).  Mirrors cairo_image_surface_create(). */
CM_PUBLIC cm_surface_t *
cm_image_surface_create(cm_format_t format, int width, int height);

/** Deprecated ARGB32 alias of cm_image_surface_create (kept for the manim
 *  subset).  Maps to cairo.ImageSurface.create_for_data ARGB32 path. */
CM_PUBLIC cm_surface_t *
cm_image_surface_create_argb32(cm_format_t format, int width, int height);

/** Create an image surface that records an EXTERNAL pixel buffer's stride.
 *  Mirrors cairo_image_surface_create_for_data(). The explicit `stride` is
 *  honored (must be >= cm_format_stride_for_width(format,width)). */
CM_PUBLIC cm_surface_t *
cm_image_surface_create_for_data(unsigned char *data, cm_format_t format,
                                 int width, int height, int stride);

/** Create a surface compatible with `other` for the given content + size.
 *  Mirrors cairo_surface_create_similar(). */
CM_PUBLIC cm_surface_t *
cm_surface_create_similar(cm_surface_t *other, cm_content_t content,
                          int width, int height);

/** Create an image surface of the given format + size, device-compatible with
 *  `other`.  Mirrors cairo_surface_create_similar_image(). */
CM_PUBLIC cm_surface_t *
cm_surface_create_similar_image(cm_surface_t *other, cm_format_t format,
                                int width, int height);

/** Create a subsurface view (x,y,w,h) onto `target`.  Mirrors
 *  cairo_surface_create_for_rectangle(). */
CM_PUBLIC cm_surface_t *
cm_surface_create_for_rectangle(cm_surface_t *target,
                                double x, double y, double width, double height);

/** Create a recording surface (op-log; no pixels).  `extents` may be NULL for
 *  unbounded.  Mirrors cairo_recording_surface_create(). */
CM_PUBLIC cm_surface_t *
cm_recording_surface_create(cm_content_t content, const cm_rect_t *extents);

/** Recording-surface ink/recorded extents.  Mirror cairo's recording-surface
 *  ink_extents / get_extents. */
CM_PUBLIC void
cm_recording_surface_ink_extents(cm_surface_t *surface, cm_rect_t *out_extents);
CM_PUBLIC int
cm_recording_surface_get_extents(cm_surface_t *surface, cm_rect_t *out_extents);

/** Destroy a surface: drop ONE lifetime reference and release its backing on the
 *  LAST reference.  Safe on NULL.  A surface must outlive every context bound to
 *  it.  Mirrors cairo_surface_destroy() (which is a reference decrement). */
CM_PUBLIC void
cm_surface_destroy(cm_surface_t *surface);

/** Take one lifetime reference on a surface (refcount++); returns `surface`.  The
 *  matching drop is cm_surface_destroy().  Mirrors cairo_surface_reference().
 *  A SurfacePattern wrapping a surface, and any code that must keep a surface
 *  alive past the creating wrapper, takes a reference here. */
CM_PUBLIC cm_surface_t *
cm_surface_reference(cm_surface_t *surface);

/** Flush pending GPU drawing and make pixels coherent for CPU reads / a
 *  downstream VideoToolbox encode.  Mirrors cairo_surface_flush(). */
CM_PUBLIC void
cm_surface_flush(cm_surface_t *surface);

/** Finish a surface (flush + release backing; accessors still valid, drawing
 *  becomes an error).  Mirrors cairo_surface_finish(). */
CM_PUBLIC void
cm_surface_finish(cm_surface_t *surface);

/** Mark the whole / a rectangle of the surface dirty (coherence hint; a no-op
 *  on shared storage).  Mirror cairo_surface_mark_dirty(_rectangle). */
CM_PUBLIC void cm_surface_mark_dirty(cm_surface_t *surface);
CM_PUBLIC void cm_surface_mark_dirty_rectangle(cm_surface_t *surface,
                                               int x, int y, int width, int height);

/** Device-offset get/set (shifts where drawing lands).  Mirror
 *  cairo_surface_set/get_device_offset(). */
CM_PUBLIC void cm_surface_set_device_offset(cm_surface_t *surface,
                                            double x_offset, double y_offset);
CM_PUBLIC void cm_surface_get_device_offset(cm_surface_t *surface,
                                            double *x_offset, double *y_offset);

/** Introspection.  Mirror cairo_image_surface_get_format/stride,
 *  cairo_surface_get_content/get_type, cairo_surface_status. */
CM_PUBLIC cm_format_t       cm_surface_get_format (cm_surface_t *surface);
CM_PUBLIC int               cm_surface_get_stride (cm_surface_t *surface);
CM_PUBLIC cm_content_t      cm_surface_get_content(cm_surface_t *surface);
CM_PUBLIC cm_surface_type_t cm_surface_get_type   (cm_surface_t *surface);
CM_PUBLIC cm_status_t       cm_surface_status     (cm_surface_t *surface);

/** Map a (sub)region of the surface to a fresh image surface aliasing the
 *  pixels; unmap writes back and releases.  Mirror cairo_surface_map_to_image /
 *  cairo_surface_unmap_image. `extents` NULL maps the whole surface. */
CM_PUBLIC cm_surface_t *
cm_surface_map_to_image(cm_surface_t *surface, const cm_rectangle_int_t *extents);
CM_PUBLIC void
cm_surface_unmap_image(cm_surface_t *surface, cm_surface_t *image);

/** Map the surface pixels for CPU access in cairo's native row layout for its
 *  format (premultiplied B,G,R,A for ARGB32).  Mirrors the data pointer of a
 *  cairo image surface. `out_stride` receives the row stride in bytes. */
CM_PUBLIC void *
cm_surface_map(cm_surface_t *surface, size_t *out_stride);

/** ARGB32 alias of cm_surface_map (kept for the manim subset). */
CM_PUBLIC void *
cm_surface_map_argb32(cm_surface_t *surface, size_t *out_stride);

/** PNG encode/decode.  Mirror cairo_surface_write_to_png(_stream) and
 *  cairo_image_surface_create_from_png(_stream).  The data variants allocate
 *  `*out_data` (caller frees with free()). */
CM_PUBLIC cm_status_t cm_surface_write_to_png_path(cm_surface_t *surface,
                                                   const char *path);
CM_PUBLIC cm_status_t cm_surface_write_to_png_data(cm_surface_t *surface,
                                                   unsigned char **out_data,
                                                   size_t *out_len);
CM_PUBLIC cm_surface_t *cm_image_surface_create_from_png_path(const char *path);
CM_PUBLIC cm_surface_t *cm_image_surface_create_from_png_data(const unsigned char *data,
                                                              size_t len);

/** Return the IOSurfaceRef backing this surface (void* == IOSurfaceRef) for
 *  zero-copy handoff to VideoToolbox, or NULL for non-IOSurface surfaces.  The
 *  handle is owned by the surface; do NOT release it.  Call flush first. */
CM_PUBLIC void *
cm_surface_get_iosurface(cm_surface_t *surface);

/** Width/height in pixels.  Mirror cairo_image_surface_get_width/height. */
CM_PUBLIC int cm_surface_get_width (const cm_surface_t *surface);
CM_PUBLIC int cm_surface_get_height(const cm_surface_t *surface);

/** Format metadata.  Mirror cairo_format_stride_for_width and a bytes-per-pixel
 *  helper. */
CM_PUBLIC int cm_format_stride_for_width(cm_format_t format, int width);
CM_PUBLIC int cm_format_bytes_per_pixel(cm_format_t format);

/* ==========================================================================
 * Context API
 * ========================================================================== */

/** Create a drawing context bound to a surface.  Mirrors cairo_create().  The
 *  context retains the surface.  Initial state matches cairo defaults. */
CM_PUBLIC cm_context_t *
cm_context_create(cm_surface_t *surface);

/** Destroy a context (does not destroy its surface).  Safe on NULL. */
CM_PUBLIC void
cm_context_destroy(cm_context_t *ctx);

/** The context's target surface / current group target.  Mirror
 *  cairo_get_target / cairo_get_group_target. */
CM_PUBLIC cm_surface_t *cm_context_get_target(cm_context_t *ctx);
CM_PUBLIC cm_surface_t *cm_context_get_group_target(cm_context_t *ctx);

/* ---- state stack -------------------------------------------------------- */

/** Save / restore the graphics state (CTM, source, fill rule, line params,
 *  operator, antialias, tolerance, dash, clip).  The current PATH is NOT part
 *  of the saved state (cairo semantics).  Mirror cairo_save / cairo_restore.
 *  restore without a matching save sets CM_STATUS_INVALID_RESTORE. */
CM_PUBLIC void cm_save(cm_context_t *ctx);
CM_PUBLIC void cm_restore(cm_context_t *ctx);

/* ---- compositing state -------------------------------------------------- */

CM_PUBLIC void          cm_set_operator(cm_context_t *ctx, cm_operator_t op);
CM_PUBLIC cm_operator_t cm_get_operator(cm_context_t *ctx);
CM_PUBLIC void          cm_set_antialias(cm_context_t *ctx, cm_antialias_t aa);
CM_PUBLIC cm_antialias_t cm_get_antialias(cm_context_t *ctx);
CM_PUBLIC void          cm_set_tolerance(cm_context_t *ctx, double tolerance);
CM_PUBLIC double        cm_get_tolerance(cm_context_t *ctx);

/** Dash pattern.  `num_dashes==0` disables dashing; a negative or all-zero
 *  pattern sets CM_STATUS_INVALID_DASH.  Mirror cairo_set_dash / cairo_get_dash
 *  / cairo_get_dash_count. */
CM_PUBLIC void cm_set_dash(cm_context_t *ctx, const double *dashes,
                           int num_dashes, double offset);
CM_PUBLIC int  cm_get_dash_count(cm_context_t *ctx);
CM_PUBLIC void cm_get_dash(cm_context_t *ctx, double *dashes, double *offset);

/* ---- transform ---------------------------------------------------------- */

/** Replace the CTM (does NOT compose).  Mirrors cairo_set_matrix(). */
CM_PUBLIC void cm_set_matrix(cm_context_t *ctx, const cm_matrix_t *matrix);
/** Read back the current CTM.  Mirror cairo_get_matrix(). */
CM_PUBLIC void cm_get_matrix(const cm_context_t *ctx, cm_matrix_t *out_matrix);
/** Reset the CTM to the identity (device == user).  Mirrors
 *  cairo_identity_matrix(). */
CM_PUBLIC void cm_identity_matrix(cm_context_t *ctx);

/** Post-multiply the CTM by scale / translate / rotate / an arbitrary matrix.
 *  Mirror cairo_scale / cairo_translate / cairo_rotate / cairo_transform. */
CM_PUBLIC void cm_scale(cm_context_t *ctx, double sx, double sy);
CM_PUBLIC void cm_translate(cm_context_t *ctx, double tx, double ty);
CM_PUBLIC void cm_rotate(cm_context_t *ctx, double radians);
CM_PUBLIC void cm_transform(cm_context_t *ctx, const cm_matrix_t *matrix);

/** Map user <-> device space.  Mirror cairo_user_to_device(_distance) /
 *  cairo_device_to_user(_distance). */
CM_PUBLIC void cm_user_to_device(cm_context_t *ctx, double *x, double *y);
CM_PUBLIC void cm_user_to_device_distance(cm_context_t *ctx, double *dx, double *dy);
CM_PUBLIC void cm_device_to_user(cm_context_t *ctx, double *x, double *y);
CM_PUBLIC void cm_device_to_user_distance(cm_context_t *ctx, double *dx, double *dy);

/* ---- path construction -------------------------------------------------- */
/* All coordinates are in USER space and are transformed by the CTM.         */

CM_PUBLIC void cm_new_path(cm_context_t *ctx);
CM_PUBLIC void cm_new_sub_path(cm_context_t *ctx);
CM_PUBLIC void cm_move_to(cm_context_t *ctx, double x, double y);
CM_PUBLIC void cm_line_to(cm_context_t *ctx, double x, double y);
CM_PUBLIC void cm_curve_to(cm_context_t *ctx,
                           double x1, double y1,
                           double x2, double y2,
                           double x3, double y3);
CM_PUBLIC void cm_close_path(cm_context_t *ctx);

/** Relative path ops (need a current point; otherwise CM_STATUS_NO_CURRENT_POINT).
 *  Mirror cairo_rel_move_to / cairo_rel_line_to / cairo_rel_curve_to. */
CM_PUBLIC void cm_rel_move_to(cm_context_t *ctx, double dx, double dy);
CM_PUBLIC void cm_rel_line_to(cm_context_t *ctx, double dx, double dy);
CM_PUBLIC void cm_rel_curve_to(cm_context_t *ctx,
                               double dx1, double dy1,
                               double dx2, double dy2,
                               double dx3, double dy3);

/** Axis-aligned rectangle sub-path.  Mirrors cairo_rectangle(). */
CM_PUBLIC void cm_rectangle(cm_context_t *ctx,
                            double x, double y, double width, double height);

/** Circular arcs (decomposed to cubics).  Mirror cairo_arc / cairo_arc_negative. */
CM_PUBLIC void cm_arc(cm_context_t *ctx, double xc, double yc, double radius,
                      double angle1, double angle2);
CM_PUBLIC void cm_arc_negative(cm_context_t *ctx, double xc, double yc, double radius,
                               double angle1, double angle2);

/** Current point queries.  Mirror cairo_has_current_point /
 *  cairo_get_current_point. */
CM_PUBLIC int  cm_has_current_point(cm_context_t *ctx);
CM_PUBLIC void cm_get_current_point(cm_context_t *ctx, double *x, double *y);

/** Tight user-space bounding box of the current path (no MSAA pad).  Mirrors
 *  cairo_path_extents. */
CM_PUBLIC void cm_path_extents(cm_context_t *ctx,
                               double *x1, double *y1, double *x2, double *y2);

/** Snapshot the current path as a heap array of (type, points) elements, in
 *  USER space.  Mirrors cairo_copy_path: the returned stream contains only
 *  MOVE_TO / LINE_TO / CURVE_TO / CLOSE_PATH, with a synthetic MOVE_TO emitted
 *  after each CLOSE_PATH (back to the closed sub-path's start) exactly like
 *  cairo.  The caller owns the result and MUST release it with
 *  cm_path_data_destroy().  Never returns NULL: on OOM the struct's `status`
 *  is non-SUCCESS and `elements` is NULL. */
CM_PUBLIC cm_path_data_t *cm_copy_path(cm_context_t *ctx);

/** Like cm_copy_path but with every CURVE_TO replaced by a run of LINE_TO
 *  segments (adaptive flattening, library tolerance), so the result contains
 *  only MOVE_TO / LINE_TO / CLOSE_PATH.  Mirrors cairo_copy_path_flat. */
CM_PUBLIC cm_path_data_t *cm_copy_path_flat(cm_context_t *ctx);

/** Replay a copied path onto the context's current path (does NOT clear it
 *  first; appends, like cairo_append_path).  A NULL or non-SUCCESS `path` is a
 *  no-op.  Coordinates are interpreted in the CURRENT user space (cairo applies
 *  the CTM at append time, matching cairo_append_path). */
CM_PUBLIC void cm_append_path(cm_context_t *ctx, const cm_path_data_t *path);

/** Release a cm_path_data_t returned by cm_copy_path / cm_copy_path_flat.
 *  Safe on NULL. */
CM_PUBLIC void cm_path_data_destroy(cm_path_data_t *path);

/* ---- source / paint ----------------------------------------------------- */

/** Solid colour source.  Components in [0,1].  Mirrors cairo_set_source_rgba.
 *  See the file header: manim passes pre-swapped B,G,R,A; pass through. */
CM_PUBLIC void
cm_set_source_rgba(cm_context_t *ctx, double r, double g, double b, double a);

/** Install a pattern (any type) as the source.  Mirrors cairo_set_source.
 *  The context retains the pattern until the next set_source/set_source_rgba. */
CM_PUBLIC void cm_set_source(cm_context_t *ctx, cm_pattern_t *pattern);

/** Install `surface` as a source at the given (user-space) origin.  Mirrors
 *  cairo_set_source_surface. */
CM_PUBLIC void cm_set_source_surface(cm_context_t *ctx, cm_surface_t *surface,
                                     double x, double y);

/** Return the current source as a (retained) pattern; a solid source is
 *  synthesized into a SolidPattern.  Mirrors cairo_get_source.  The caller owns
 *  a reference and must cm_pattern_destroy it. */
CM_PUBLIC cm_pattern_t *cm_get_source(cm_context_t *ctx);

/* ---- fill / stroke ------------------------------------------------------ */

CM_PUBLIC void cm_set_fill_rule(cm_context_t *ctx, cm_fill_rule_t fill_rule);
CM_PUBLIC cm_fill_rule_t cm_get_fill_rule(cm_context_t *ctx);

CM_PUBLIC void   cm_set_line_width(cm_context_t *ctx, double width);
CM_PUBLIC double cm_get_line_width(cm_context_t *ctx);
CM_PUBLIC void   cm_set_line_join(cm_context_t *ctx, cm_line_join_t join);
CM_PUBLIC cm_line_join_t cm_get_line_join(cm_context_t *ctx);
CM_PUBLIC void   cm_set_line_cap(cm_context_t *ctx, cm_line_cap_t cap);
CM_PUBLIC cm_line_cap_t  cm_get_line_cap(cm_context_t *ctx);
CM_PUBLIC void   cm_set_miter_limit(cm_context_t *ctx, double limit);
CM_PUBLIC double cm_get_miter_limit(cm_context_t *ctx);

/** Fill the current path PRESERVING it (NONZERO/EVEN-ODD per fill rule).
 *  Mirrors cairo_fill_preserve. */
CM_PUBLIC void cm_fill_preserve(cm_context_t *ctx);
/** Fill the current path and CLEAR it.  Mirrors cairo_fill. */
CM_PUBLIC void cm_fill(cm_context_t *ctx);

/** Stroke the current path PRESERVING it.  Mirrors cairo_stroke_preserve. */
CM_PUBLIC void cm_stroke_preserve(cm_context_t *ctx);
/** Stroke the current path and CLEAR it.  Mirrors cairo_stroke. */
CM_PUBLIC void cm_stroke(cm_context_t *ctx);

/* ---- paint / mask ------------------------------------------------------- */

/** Paint the current source everywhere within the clip.  Mirrors cairo_paint. */
CM_PUBLIC void cm_paint(cm_context_t *ctx);
/** Paint with constant group alpha.  Mirrors cairo_paint_with_alpha. */
CM_PUBLIC void cm_paint_with_alpha(cm_context_t *ctx, double alpha);
/** Composite the source through a mask pattern's alpha.  Mirrors cairo_mask. */
CM_PUBLIC void cm_mask(cm_context_t *ctx, cm_pattern_t *pattern);
/** Composite the source through a surface (as a mask) at (x,y).  Mirrors
 *  cairo_mask_surface. */
CM_PUBLIC void cm_mask_surface(cm_context_t *ctx, cm_surface_t *surface,
                               double x, double y);

/* ---- clipping ----------------------------------------------------------- */

/** Intersect the clip with the current path (consumes / preserves the path).
 *  Mirror cairo_clip / cairo_clip_preserve / cairo_reset_clip. */
CM_PUBLIC void cm_clip(cm_context_t *ctx);
CM_PUBLIC void cm_clip_preserve(cm_context_t *ctx);
CM_PUBLIC void cm_reset_clip(cm_context_t *ctx);

/** Clip bounding box in user space.  Mirrors cairo_clip_extents. */
CM_PUBLIC void cm_clip_extents(cm_context_t *ctx,
                               double *x1, double *y1, double *x2, double *y2);
/** Point-in-clip test (user space).  Mirrors cairo_in_clip. */
CM_PUBLIC int cm_in_clip(cm_context_t *ctx, double x, double y);
/** Copy the clip as a rectangle list, or report CLIP_NOT_REPRESENTABLE.
 *  Returns CM_STATUS_SUCCESS and fills up to `max_rects`; `*out_count` receives
 *  the number of rectangles.  Mirrors cairo_copy_clip_rectangle_list. */
CM_PUBLIC cm_status_t cm_copy_clip_rectangle_list(cm_context_t *ctx,
                                                  cm_rectangle_t *out_rects,
                                                  int max_rects, int *out_count);

/* ---- groups ------------------------------------------------------------- */

/** Redirect rendering to an offscreen group target.  Mirror
 *  cairo_push_group / cairo_push_group_with_content. */
CM_PUBLIC void cm_push_group(cm_context_t *ctx);
CM_PUBLIC void cm_push_group_with_content(cm_context_t *ctx, cm_content_t content);
/** End the group; return it as a SurfacePattern (NOT installed).  Mirrors
 *  cairo_pop_group.  The caller owns a reference. */
CM_PUBLIC cm_pattern_t *cm_pop_group(cm_context_t *ctx);
/** End the group and install it as the source.  Mirrors cairo_pop_group_to_source. */
CM_PUBLIC void cm_pop_group_to_source(cm_context_t *ctx);

/* ==========================================================================
 * Pattern API
 * ========================================================================== */

/** Lifecycle.  Mirror cairo_pattern_reference / cairo_pattern_destroy
 *  (refcount) / cairo_pattern_get_type / cairo_pattern_status. */
CM_PUBLIC cm_pattern_t    *cm_pattern_reference(cm_pattern_t *pattern);
CM_PUBLIC void             cm_pattern_destroy(cm_pattern_t *pattern);
CM_PUBLIC cm_pattern_type_t cm_pattern_get_type(cm_pattern_t *pattern);
CM_PUBLIC cm_status_t      cm_pattern_status(cm_pattern_t *pattern);

/** Base accessors.  Mirror cairo_pattern_set/get_extend, set/get_filter,
 *  set/get_matrix. */
CM_PUBLIC void        cm_pattern_set_extend(cm_pattern_t *pattern, cm_extend_t extend);
CM_PUBLIC cm_extend_t cm_pattern_get_extend(cm_pattern_t *pattern);
CM_PUBLIC void        cm_pattern_set_filter(cm_pattern_t *pattern, cm_filter_t filter);
CM_PUBLIC cm_filter_t cm_pattern_get_filter(cm_pattern_t *pattern);
CM_PUBLIC void        cm_pattern_set_matrix(cm_pattern_t *pattern, const cm_matrix_t *matrix);
CM_PUBLIC void        cm_pattern_get_matrix(cm_pattern_t *pattern, cm_matrix_t *matrix);

/** Solid pattern.  Mirror cairo_pattern_create_rgba / get_rgba. */
CM_PUBLIC cm_pattern_t *cm_solid_pattern_create_rgba(double r, double g, double b, double a);
CM_PUBLIC cm_status_t   cm_solid_pattern_get_rgba(cm_pattern_t *pattern,
                                                  double *r, double *g, double *b, double *a);

/** Gradient stops.  Mirror cairo_pattern_add_color_stop_rgb/_rgba,
 *  cairo_pattern_get_color_stop_count / _rgba. */
CM_PUBLIC void cm_pattern_add_color_stop_rgb(cm_pattern_t *pattern, double offset,
                                             double r, double g, double b);
CM_PUBLIC void cm_pattern_add_color_stop_rgba(cm_pattern_t *pattern, double offset,
                                              double r, double g, double b, double a);
CM_PUBLIC cm_status_t cm_pattern_get_color_stop_count(cm_pattern_t *pattern, int *count);
CM_PUBLIC cm_status_t cm_pattern_get_color_stop_rgba(cm_pattern_t *pattern, int index,
                                                     double *offset, double *r,
                                                     double *g, double *b, double *a);

/** Linear gradient.  Mirror cairo_pattern_create_linear / get_linear_points. */
CM_PUBLIC cm_pattern_t *cm_linear_gradient_create(double x0, double y0,
                                                  double x1, double y1);
CM_PUBLIC cm_status_t   cm_linear_gradient_get_points(cm_pattern_t *pattern,
                                                      double *x0, double *y0,
                                                      double *x1, double *y1);

/** Radial gradient.  Mirror cairo_pattern_create_radial / get_radial_circles. */
CM_PUBLIC cm_pattern_t *cm_radial_gradient_create(double cx0, double cy0, double r0,
                                                  double cx1, double cy1, double r1);
CM_PUBLIC cm_status_t   cm_radial_gradient_get_circles(cm_pattern_t *pattern,
                                                       double *cx0, double *cy0, double *r0,
                                                       double *cx1, double *cy1, double *r1);

/** Surface pattern.  Mirror cairo_pattern_create_for_surface /
 *  cairo_pattern_get_surface. */
CM_PUBLIC cm_pattern_t *cm_pattern_create_for_surface(cm_surface_t *surface);
CM_PUBLIC cm_status_t   cm_surface_pattern_get_surface(cm_pattern_t *pattern,
                                                       cm_surface_t **out_surface);

/* ---- mesh pattern (Coons patches) --------------------------------------- */

CM_PUBLIC cm_pattern_t *cm_mesh_pattern_create(void);
CM_PUBLIC void cm_mesh_pattern_begin_patch(cm_pattern_t *pattern);
CM_PUBLIC void cm_mesh_pattern_end_patch(cm_pattern_t *pattern);
CM_PUBLIC void cm_mesh_pattern_move_to(cm_pattern_t *pattern, double x, double y);
CM_PUBLIC void cm_mesh_pattern_line_to(cm_pattern_t *pattern, double x, double y);
CM_PUBLIC void cm_mesh_pattern_curve_to(cm_pattern_t *pattern,
                                        double x1, double y1, double x2, double y2,
                                        double x3, double y3);
CM_PUBLIC void cm_mesh_pattern_set_control_point(cm_pattern_t *pattern,
                                                 unsigned int point_num,
                                                 double x, double y);
CM_PUBLIC void cm_mesh_pattern_set_corner_color_rgb(cm_pattern_t *pattern,
                                                    unsigned int corner_num,
                                                    double r, double g, double b);
CM_PUBLIC void cm_mesh_pattern_set_corner_color_rgba(cm_pattern_t *pattern,
                                                     unsigned int corner_num,
                                                     double r, double g, double b, double a);
CM_PUBLIC cm_status_t cm_mesh_pattern_get_patch_count(cm_pattern_t *pattern,
                                                      unsigned int *count);
CM_PUBLIC cm_status_t cm_mesh_pattern_get_control_point(cm_pattern_t *pattern,
                                                        unsigned int patch_num,
                                                        unsigned int point_num,
                                                        double *x, double *y);
CM_PUBLIC cm_status_t cm_mesh_pattern_get_corner_color_rgba(cm_pattern_t *pattern,
                                                            unsigned int patch_num,
                                                            unsigned int corner_num,
                                                            double *r, double *g,
                                                            double *b, double *a);

/* ---- raster-source pattern ---------------------------------------------- */

CM_PUBLIC cm_pattern_t *cm_pattern_create_raster_source(void *user_data,
                                                        cm_content_t content,
                                                        int width, int height);
CM_PUBLIC void cm_raster_source_pattern_set_acquire(cm_pattern_t *pattern,
                                                    cm_raster_acquire_func_t acquire,
                                                    cm_raster_release_func_t release);
CM_PUBLIC void *cm_raster_source_pattern_get_user_data(cm_pattern_t *pattern);

/* ==========================================================================
 * Query API (extents + hit tests)
 * ========================================================================== */

/** Tight user-space bounding box that the current path would fill / stroke.
 *  Mirror cairo_fill_extents / cairo_stroke_extents. */
CM_PUBLIC void cm_fill_extents(cm_context_t *ctx,
                               double *x1, double *y1, double *x2, double *y2);
CM_PUBLIC void cm_stroke_extents(cm_context_t *ctx,
                                 double *x1, double *y1, double *x2, double *y2);
/** Point-in-fill / point-in-stroke tests (user space).  Mirror cairo_in_fill /
 *  cairo_in_stroke. */
CM_PUBLIC int cm_in_fill(cm_context_t *ctx, double x, double y);
CM_PUBLIC int cm_in_stroke(cm_context_t *ctx, double x, double y);

/* ==========================================================================
 * Region API  (cairo_region_t: integer rectangle-set algebra)
 * ========================================================================== */

CM_PUBLIC cm_region_t *cm_region_create(void);
CM_PUBLIC cm_region_t *cm_region_create_rectangle(const cm_rectangle_int_t *rectangle);
CM_PUBLIC cm_region_t *cm_region_create_rectangles(const cm_rectangle_int_t *rects,
                                                   int count);
CM_PUBLIC cm_region_t *cm_region_copy(const cm_region_t *original);
CM_PUBLIC cm_region_t *cm_region_reference(cm_region_t *region);
CM_PUBLIC void         cm_region_destroy(cm_region_t *region);
CM_PUBLIC cm_status_t  cm_region_status(const cm_region_t *region);

CM_PUBLIC int  cm_region_is_empty(const cm_region_t *region);
CM_PUBLIC int  cm_region_equal(const cm_region_t *a, const cm_region_t *b);
CM_PUBLIC void cm_region_get_extents(const cm_region_t *region,
                                     cm_rectangle_int_t *extents);
CM_PUBLIC int  cm_region_num_rectangles(const cm_region_t *region);
CM_PUBLIC void cm_region_get_rectangle(const cm_region_t *region, int nth,
                                       cm_rectangle_int_t *rectangle);
CM_PUBLIC cm_region_overlap_t cm_region_contains_rectangle(const cm_region_t *region,
                                                           const cm_rectangle_int_t *rectangle);
CM_PUBLIC int  cm_region_contains_point(const cm_region_t *region, int x, int y);
CM_PUBLIC void cm_region_translate(cm_region_t *region, int dx, int dy);

CM_PUBLIC cm_status_t cm_region_union(cm_region_t *dst, const cm_region_t *other);
CM_PUBLIC cm_status_t cm_region_union_rectangle(cm_region_t *dst,
                                                const cm_rectangle_int_t *rectangle);
CM_PUBLIC cm_status_t cm_region_intersect(cm_region_t *dst, const cm_region_t *other);
CM_PUBLIC cm_status_t cm_region_intersect_rectangle(cm_region_t *dst,
                                                    const cm_rectangle_int_t *rectangle);
CM_PUBLIC cm_status_t cm_region_subtract(cm_region_t *dst, const cm_region_t *other);
CM_PUBLIC cm_status_t cm_region_subtract_rectangle(cm_region_t *dst,
                                                   const cm_rectangle_int_t *rectangle);
CM_PUBLIC cm_status_t cm_region_xor(cm_region_t *dst, const cm_region_t *other);
CM_PUBLIC cm_status_t cm_region_xor_rectangle(cm_region_t *dst,
                                              const cm_rectangle_int_t *rectangle);

/* ==========================================================================
 * Font + text API
 * ========================================================================== */

/* ---- context font state ------------------------------------------------- */

/** Select a toy font face + size / matrix / options.  Mirror
 *  cairo_select_font_face / cairo_set_font_size / cairo_set/get_font_matrix /
 *  cairo_set/get_font_options / cairo_set/get_font_face /
 *  cairo_set/get_scaled_font. */
CM_PUBLIC void cm_select_font_face(cm_context_t *ctx, const char *family,
                                   cm_font_slant_t slant, cm_font_weight_t weight);
CM_PUBLIC void cm_set_font_size(cm_context_t *ctx, double size);
CM_PUBLIC void cm_set_font_matrix(cm_context_t *ctx, const cm_matrix_t *matrix);
CM_PUBLIC void cm_get_font_matrix(cm_context_t *ctx, cm_matrix_t *matrix);
CM_PUBLIC void cm_set_font_options(cm_context_t *ctx, const cm_font_options_t *options);
CM_PUBLIC void cm_get_font_options(cm_context_t *ctx, cm_font_options_t *options);
CM_PUBLIC void cm_set_font_face(cm_context_t *ctx, cm_font_face_t *font_face);
CM_PUBLIC cm_font_face_t   *cm_get_font_face(cm_context_t *ctx);
CM_PUBLIC void cm_set_scaled_font(cm_context_t *ctx, cm_scaled_font_t *scaled_font);
CM_PUBLIC cm_scaled_font_t *cm_get_scaled_font(cm_context_t *ctx);

/* ---- text drawing + metrics --------------------------------------------- */

CM_PUBLIC void cm_show_text(cm_context_t *ctx, const char *utf8);
CM_PUBLIC void cm_show_glyphs(cm_context_t *ctx, const cm_glyph_t *glyphs, int num_glyphs);
CM_PUBLIC void cm_show_text_glyphs(cm_context_t *ctx, const char *utf8, int utf8_len,
                                   const cm_glyph_t *glyphs, int num_glyphs,
                                   const cm_text_cluster_t *clusters, int num_clusters,
                                   cm_text_cluster_flags_t cluster_flags);
CM_PUBLIC void cm_text_path(cm_context_t *ctx, const char *utf8);
CM_PUBLIC void cm_glyph_path(cm_context_t *ctx, const cm_glyph_t *glyphs, int num_glyphs);
CM_PUBLIC void cm_text_extents(cm_context_t *ctx, const char *utf8,
                               cm_text_extents_t *extents);
CM_PUBLIC void cm_glyph_extents(cm_context_t *ctx, const cm_glyph_t *glyphs,
                                int num_glyphs, cm_text_extents_t *extents);
CM_PUBLIC void cm_font_extents(cm_context_t *ctx, cm_font_extents_t *extents);

/* ---- font face ---------------------------------------------------------- */

CM_PUBLIC cm_font_face_t *cm_toy_font_face_create(const char *family,
                                                  cm_font_slant_t slant,
                                                  cm_font_weight_t weight);
CM_PUBLIC const char     *cm_toy_font_face_get_family(cm_font_face_t *font_face);
CM_PUBLIC cm_font_slant_t  cm_toy_font_face_get_slant(cm_font_face_t *font_face);
CM_PUBLIC cm_font_weight_t cm_toy_font_face_get_weight(cm_font_face_t *font_face);

CM_PUBLIC cm_font_face_t *cm_font_face_reference(cm_font_face_t *font_face);
CM_PUBLIC void            cm_font_face_destroy(cm_font_face_t *font_face);
CM_PUBLIC cm_status_t     cm_font_face_status(cm_font_face_t *font_face);
CM_PUBLIC cm_font_type_t  cm_font_face_get_type(cm_font_face_t *font_face);

/* ---- font options ------------------------------------------------------- */

CM_PUBLIC cm_font_options_t *cm_font_options_create(void);
CM_PUBLIC cm_font_options_t *cm_font_options_copy(const cm_font_options_t *original);
CM_PUBLIC void               cm_font_options_destroy(cm_font_options_t *options);
CM_PUBLIC cm_status_t        cm_font_options_status(cm_font_options_t *options);
CM_PUBLIC void               cm_font_options_merge(cm_font_options_t *options,
                                                   const cm_font_options_t *other);
CM_PUBLIC int                cm_font_options_equal(const cm_font_options_t *a,
                                                   const cm_font_options_t *b);
CM_PUBLIC unsigned long      cm_font_options_hash(const cm_font_options_t *options);
CM_PUBLIC void cm_font_options_set_antialias(cm_font_options_t *options, cm_antialias_t antialias);
CM_PUBLIC cm_antialias_t cm_font_options_get_antialias(const cm_font_options_t *options);
CM_PUBLIC void cm_font_options_set_subpixel_order(cm_font_options_t *options, cm_subpixel_order_t order);
CM_PUBLIC cm_subpixel_order_t cm_font_options_get_subpixel_order(const cm_font_options_t *options);
CM_PUBLIC void cm_font_options_set_hint_style(cm_font_options_t *options, cm_hint_style_t hint_style);
CM_PUBLIC cm_hint_style_t cm_font_options_get_hint_style(const cm_font_options_t *options);
CM_PUBLIC void cm_font_options_set_hint_metrics(cm_font_options_t *options, cm_hint_metrics_t hint_metrics);
CM_PUBLIC cm_hint_metrics_t cm_font_options_get_hint_metrics(const cm_font_options_t *options);
CM_PUBLIC void cm_font_options_set_variations(cm_font_options_t *options, const char *variations);
CM_PUBLIC const char *cm_font_options_get_variations(cm_font_options_t *options);

/* ---- scaled font -------------------------------------------------------- */

CM_PUBLIC cm_scaled_font_t *cm_scaled_font_create(cm_font_face_t *font_face,
                                                  const cm_matrix_t *font_matrix,
                                                  const cm_matrix_t *ctm,
                                                  const cm_font_options_t *options);
CM_PUBLIC cm_scaled_font_t *cm_scaled_font_reference(cm_scaled_font_t *scaled_font);
CM_PUBLIC void              cm_scaled_font_destroy(cm_scaled_font_t *scaled_font);
CM_PUBLIC cm_status_t       cm_scaled_font_status(cm_scaled_font_t *scaled_font);
CM_PUBLIC cm_font_type_t    cm_scaled_font_get_type(cm_scaled_font_t *scaled_font);
CM_PUBLIC cm_font_face_t   *cm_scaled_font_get_font_face(cm_scaled_font_t *scaled_font);
CM_PUBLIC void cm_scaled_font_get_font_matrix(cm_scaled_font_t *scaled_font, cm_matrix_t *font_matrix);
CM_PUBLIC void cm_scaled_font_get_ctm(cm_scaled_font_t *scaled_font, cm_matrix_t *ctm);
CM_PUBLIC void cm_scaled_font_get_scale_matrix(cm_scaled_font_t *scaled_font, cm_matrix_t *scale_matrix);
CM_PUBLIC void cm_scaled_font_get_font_options(cm_scaled_font_t *scaled_font, cm_font_options_t *options);
CM_PUBLIC void cm_scaled_font_extents(cm_scaled_font_t *scaled_font, cm_font_extents_t *extents);
CM_PUBLIC void cm_scaled_font_text_extents(cm_scaled_font_t *scaled_font, const char *utf8,
                                           cm_text_extents_t *extents);
CM_PUBLIC void cm_scaled_font_glyph_extents(cm_scaled_font_t *scaled_font,
                                            const cm_glyph_t *glyphs, int num_glyphs,
                                            cm_text_extents_t *extents);
/** Shape UTF-8 to glyphs (caller frees the returned arrays via cm_glyph_free /
 *  cm_text_cluster_free).  Mirrors cairo_scaled_font_text_to_glyphs. */
CM_PUBLIC cm_status_t cm_scaled_font_text_to_glyphs(cm_scaled_font_t *scaled_font,
                                                    double x, double y,
                                                    const char *utf8, int utf8_len,
                                                    cm_glyph_t **glyphs, int *num_glyphs,
                                                    cm_text_cluster_t **clusters,
                                                    int *num_clusters,
                                                    cm_text_cluster_flags_t *cluster_flags);

/** Free glyph / cluster arrays returned by the shaping API.  Mirror
 *  cairo_glyph_free / cairo_text_cluster_free. */
CM_PUBLIC void cm_glyph_free(cm_glyph_t *glyphs);
CM_PUBLIC void cm_text_cluster_free(cm_text_cluster_t *clusters);

/* ---- optional FreeType font face (guarded) ------------------------------ */
/* These are always declared; the implementations are compiled only under
 * CM_ENABLE_FREETYPE and otherwise return safe defaults. `ft_face` is an
 * FT_Face passed as void* so this header has no FreeType dependency. */
CM_PUBLIC cm_font_face_t *cm_ft_font_face_create_for_ft_face(void *ft_face, int load_flags);
CM_PUBLIC void *cm_ft_scaled_font_lock_face(cm_scaled_font_t *scaled_font);
CM_PUBLIC void  cm_ft_scaled_font_unlock_face(cm_scaled_font_t *scaled_font);

/** Create a font face from a font FILE on disk (TTF/OTF/TTC/...); `index` picks a
 *  face within a collection.  Mirrors the role of cairo_ft_font_face_create (a
 *  face that renders a file's real glyphs) WITHOUT a build-time FreeType
 *  dependency: when CM_ENABLE_FREETYPE is off (the default, iOS-clean build) the
 *  file is loaded via CoreText and renders through the same CoreText outline path
 *  as toy faces.  Returns a face usable with cm_set_font_face, or NULL (with
 *  cm_last_status set) if the file cannot be loaded. The returned face owns its
 *  native font handle and is released by cm_font_face_destroy. */
CM_PUBLIC cm_font_face_t *cm_ft_font_face_create_for_path(const char *path, int index);

/* ==========================================================================
 * Diagnostics
 * ========================================================================== */

/** Status of the last operation on this context (mirror cairo_status()). */
CM_PUBLIC cm_status_t cm_context_status(const cm_context_t *ctx);

/** Status of the last global/surface-creation operation (thread-local). */
CM_PUBLIC cm_status_t cm_last_status(void);

/** Human-readable string for an internal cm status (device messages). */
CM_PUBLIC const char *cm_status_to_string(cm_status_t status);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* CAIRO_METAL_H */
