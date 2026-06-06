/*
 * cm_internal.h  --  CairoMetal internal contract
 * ============================================================================
 *
 * Shared, NON-public interface between the implementation modules.  The public
 * glue calls down into these; the module owners implement them.  This file is
 * the coordination point that fixes the concrete struct layouts and function
 * names every module agrees on, so the modules compile against a FROZEN
 * contract.
 *
 * Module map (one owner each):
 *   cm_device.m         -- Metal device/queue, persistent pipeline +
 *                          depth-stencil states, ring, semaphore, frames.
 *   cm_surface.m        -- format-general IOSurface-backed target, MSAA,
 *                          flush/resolve/map, offscreen group targets.
 *   cm_surface_format.c -- format metadata table (bpp / stride / pixel codes).
 *   cm_surface_similar.c-- create_similar / similar_image / for_rectangle glue.
 *   cm_surface_png.m    -- PNG encode/decode via ImageIO.
 *   cm_recording.m      -- RecordingSurface op-log record + replay.
 *   cm_matrix.c         -- full affine algebra.
 *   cm_state.c          -- gstate stack + non-GPU getters/setters + dash.
 *   cm_clip.m           -- GPU A8 clip-mask + CPU clip geometry.
 *   cm_group.m          -- push/pop_group offscreen targets -> SurfacePattern.
 *   cm_compose.m        -- operator + paint + mask + paint_with_alpha encode.
 *   cm_pattern.c        -- universal pattern base + CPU queries.
 *   cm_mesh.c           -- MeshPattern Coons record + CPU tessellation.
 *   cm_raster.c         -- RasterSourcePattern callback marshalling.
 *   cm_paint.m          -- uniform packing + gradient LUT bake + ABI lock.
 *   cm_path.m           -- record / flatten / tessellate + arc/rel/introspect.
 *   cm_query.c          -- fill/stroke/path extents + in_fill/in_stroke.
 *   cm_region.c         -- cairo_region_t band algebra.
 *   cm_font.c           -- FontOptions/FontFace/ScaledFont PODs + font state.
 *   cm_text.m           -- CoreText glyph-outline source + shaping + metrics.
 *   cm_ft.c             -- optional FreeType outline source (guarded).
 *   cm_fill.m           -- stencil-then-cover fill encode + non-preserve.
 *   cm_stroke.m         -- CPU stroke expansion (caps/joins/miter) + dash.
 *   cairo_metal.m       -- public context glue + per-frame driver.
 *
 * Anything Objective-C (MTL*, IOSurface) is hidden behind opaque handles or
 * lives only in the .m translation units, so the .c modules stay pure C.
 *
 * ============================================================================
 */
#ifndef CM_INTERNAL_H
#define CM_INTERNAL_H

#include "cairo_metal.h"
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * Tunables
 * ========================================================================== */
#define CM_FRAMES_IN_FLIGHT     3       /* triple buffering                   */
#define CM_MSAA_SAMPLE_COUNT    4       /* MSAA for anti-aliasing             */
#define CM_FLATTEN_TOLERANCE    0.10    /* px: max deviation when flattening  */
#define CM_ARC_TOLERANCE        0.10    /* px: round join/cap segmentation    */
#define CM_VTX_RING_BYTES   (16u<<20)   /* per-frame dynamic vertex arena      */
#define CM_UNI_RING_BYTES   (256u<<10)  /* per-frame dynamic uniform arena     */

/* ==========================================================================
 * Plain-old-data geometry types (shared CPU<->GPU; must match shaders)
 * ========================================================================== */

/** A device-space (post-CTM) 2D position fed to the vertex stage. */
typedef struct { float x, y; } cm_vec2f;

/** RGBA float colour, NON-premultiplied as stored; the fragment stage
 *  premultiplies on output to match cairo's premultiplied ARGB32 surface. */
typedef struct { float r, g, b, a; } cm_rgba;

/** Per-vertex coloured position for the Gouraud (mesh) cover path. */
typedef struct { float x, y; cm_rgba color; } cm_vtx_color;

/**
 * Per-draw uniforms (std140-friendly layout; keep 16-byte aligned).
 *
 * Layout is APPEND-ONLY after `solid` so the on-wire ABI the shader memcpy
 * relies on never shifts.  The matching _Static_assert offsets + the Metal
 * struct mirror are owned by cm_paint.m and shaders/fill.metal IN LOCK-STEP.
 *   ctm_row0  @0   ctm_row1 @16  to_clip @32  paint_kind @48  grad_axis @52
 *   solid     @68
 *   pat_inv_row0 @84  pat_inv_row1 @100  operator @116  global_alpha @120
 *   mask_axis @124  mask_kind @140
 */
typedef struct {
    float ctm_row0[4];
    float ctm_row1[4];
    float to_clip[4];   /* (sx, sy, tx, ty): clip = pos*sxsy + txty        */
    /* paint */
    int   paint_kind;   /* cm_paint_kind                                    */
    float grad_axis[4]; /* (x0,y0,x1,y1) device space for linear gradient   */
    cm_rgba solid;      /* solid colour when paint_kind == CM_PAINT_SOLID   */
    /* --- appended (full contract); see lock-step asserts in cm_paint.m --- */
    float pat_inv_row0[4]; /* inverse pattern->device rows (surface/radial)  */
    float pat_inv_row1[4];
    int   operator;     /* cm_operator_t for programmable-blend frags        */
    float global_alpha; /* paint_with_alpha / group opacity                  */
    float mask_axis[4]; /* mask gradient axis (device space)                 */
    int   mask_kind;    /* cm_paint_kind of the mask pattern                 */
} cm_uniforms;

/* ==========================================================================
 * Path model
 * ==========================================================================
 * A path is a list of sub-paths (contours).  Each contour is a flat run of
 * points produced by flattening; `closed` marks contours that the fill must
 * implicitly close (fill always closes; this flag matters for stroking).
 */
typedef struct {
    uint32_t first_point;   /* index into cm_path.pts                        */
    uint32_t point_count;
    bool     closed;        /* cm_close_path was called on this contour      */
    bool     has_current;   /* contour has a current point (move issued)     */
} cm_contour;

/** Recorded path verbs/points in USER space, plus the flattened cache. */
typedef struct cm_path {
    /* recorded control geometry (user space) */
    double   *verbs_xy;     /* interleaved x,y for each verb arg            */
    uint8_t  *verbs;        /* cm_path_verb                                  */
    uint32_t  verb_count, verb_cap;
    uint32_t  xy_count,    xy_cap;
    double    cur_x, cur_y; /* current point (user space)                    */
    double    sub_x, sub_y; /* sub-path start (for close_path)               */
    bool      has_current;
    bool      dirty;        /* set on edit; clears after flatten             */

    /* flattened cache (DEVICE space after CTM applied at flatten time) */
    cm_vec2f *pts;          /* flattened polyline points                     */
    uint32_t  pts_count, pts_cap;
    cm_contour *contours;
    uint32_t  contour_count, contour_cap;
} cm_path;

typedef enum {
    CM_VERB_MOVE = 0,       /* 1 point  */
    CM_VERB_LINE,           /* 1 point  */
    CM_VERB_CURVE,          /* 3 points */
    CM_VERB_CLOSE,          /* 0 points */
    CM_VERB_NEW_SUB         /* 0 points */
} cm_path_verb;

/* ==========================================================================
 * Paint / pattern
 * ==========================================================================
 * cm_paint_kind is APPEND-ONLY: 0/1 (SOLID/LINEAR) must never renumber because
 * the uniforms on-wire value + cm_fill pipeline-selection depend on them.
 * RASTER routes through SURFACE.
 */
typedef enum {
    CM_PAINT_SOLID   = 0,
    CM_PAINT_LINEAR  = 1,
    CM_PAINT_RADIAL  = 2,
    CM_PAINT_SURFACE = 3,
    CM_PAINT_MESH    = 4
} cm_paint_kind;

#define CM_MAX_STOPS 32
#define CM_GRAD_LUT_SIZE 256
#define CM_MESH_MAX_PATCHES_INIT 4

typedef struct { double offset; cm_rgba color; } cm_grad_stop;

/** Two-circle radial gradient geometry (USER space). */
typedef struct { double cx0, cy0, r0, cx1, cy1, r1; } cm_radial_data;

/** Surface-pattern payload: the (retained) source surface. */
typedef struct { cm_surface_t *surface; } cm_surface_data;

/** One Coons patch: up to 4 cubic sides (12 control points as pts[8] edge
 *  controls + the 4 implied corners) + 4 corner colours.  Stored as 8 boundary
 *  control points per side-walk plus corner colours, cairo default-fill rules
 *  applied by cm_mesh.c. */
typedef struct {
    double   pts[8][2];     /* boundary control points (mesh build order)    */
    cm_rgba  color[4];      /* corner colours                                */
    uint32_t side_count;    /* sides specified so far (0..4)                 */
    bool     have_color[4]; /* which corners had a colour set                */
} cm_mesh_patch;

/** Mesh-pattern payload: a growable array of Coons patches + build cursor. */
typedef struct {
    cm_mesh_patch *patches;
    uint32_t       count, cap;
    cm_mesh_patch  cur;     /* patch under construction (begin/end_patch)    */
    bool           in_patch;
} cm_mesh_data;

/** RasterSourcePattern payload: callbacks + user data + nominal size. */
typedef struct {
    void                    *user_data;
    cm_content_t             content;
    int                      width, height;
    cm_raster_acquire_func_t acquire;
    cm_raster_release_func_t release;
} cm_raster_data;

/**
 * Universal pattern base.  A single struct services every pattern type; the
 * union members are selected by `type`.  `stops`/`x0..y1` stay first so the
 * cm_paint.m LUT bake (which reads stops[]+axis) keeps working unchanged.
 */
struct cm_pattern {
    /* base (cairo_pattern_t common state) */
    cm_paint_kind     kind;     /* derived paint kind (SOLID/LINEAR/...)     */
    cm_pattern_type_t type;     /* public pattern type                       */
    cm_extend_t       extend;
    cm_filter_t       filter;
    cm_matrix_t       matrix;   /* pattern matrix (user->pattern space)      */
    int               refcount;
    cm_status_t       status;

    /* solid */
    cm_rgba           solid;

    /* linear gradient axis (USER space) + shared gradient stops */
    double            x0, y0, x1, y1;
    cm_grad_stop      stops[CM_MAX_STOPS];
    uint32_t          stop_count;

    /* per-type payloads */
    cm_radial_data    radial;
    cm_surface_data   surf;
    cm_mesh_data      mesh;
    cm_raster_data    raster;
};

/** Current source on a context: a solid colour or a retained pattern.  `kind`
 *  is derived from the pattern type at encode time.  Layout/field names kept
 *  STABLE (read by cairo_metal.m / cm_fill.m / cm_paint.m). */
typedef struct {
    cm_paint_kind kind;             /* CM_PAINT_SOLID or pattern-derived     */
    cm_rgba       solid;            /* when kind == CM_PAINT_SOLID           */
    cm_pattern_t *pattern;          /* retained when kind != CM_PAINT_SOLID  */
} cm_source;

/* ==========================================================================
 * Opaque device/surface handles (defined in the .m files)
 * ========================================================================== */
typedef struct cm_device cm_device;     /* Metal device + persistent states  */

/* ==========================================================================
 * Graphics-state stack + clip + groups
 * ==========================================================================
 * cm_save/cm_restore push/pop a cm_gstate snapshot of the COMPOSITE state
 * (NOT the current path -- cairo does not save/restore the path).  The clip is
 * a refcounted A8-coverage object snapshotted by value-pointer.
 */

/** A clip plane: an A8 coverage texture (NULL == unclipped), its device AABB,
 *  and the CPU contours + rule used to build it (for in_clip / extents). */
typedef struct cm_clip_state {
    int       refcount;
    void     *mask_tex;     /* id<MTLTexture> A8, NULL == unclipped          */
    float     dev_x1, dev_y1, dev_x2, dev_y2; /* device AABB                 */
    cm_path  *contours;     /* clip path contours (device space), or NULL    */
    cm_fill_rule_t rule;
    bool      is_rectangle; /* clip is a single axis-aligned rect            */
} cm_clip_state;

/** A saved graphics state node (cairo gstate).  Owns a retained source
 *  pattern (if any), an owned dash copy, and a clip snapshot pointer. */
typedef struct cm_gstate {
    cm_matrix_t      ctm;
    cm_source        source;        /* retained pattern if non-solid         */
    cm_fill_rule_t   fill_rule;
    double           line_width;
    cm_line_join_t   line_join;
    cm_line_cap_t    line_cap;
    double           miter_limit;
    cm_operator_t    op;
    cm_antialias_t   antialias;
    double           tolerance;
    double          *dash;          /* owned copy                            */
    int              dash_count;
    double           dash_offset;
    double           global_alpha;
    cm_clip_state   *clip;          /* snapshot (retained)                   */
    /* font state */
    cm_font_face_t  *font_face;     /* retained                              */
    cm_matrix_t      font_matrix;
    cm_font_options_t *font_options;/* owned copy                            */
    struct cm_gstate *next;
} cm_gstate;

/** A push_group target: an offscreen surface + the gstate saved at push. */
typedef struct cm_group {
    cm_surface_t    *target;        /* offscreen MSAA+resolve target         */
    cm_content_t     content;
    struct cm_group *next;
} cm_group;

/* ==========================================================================
 * Public struct definitions
 * ========================================================================== */
struct cm_surface {
    cm_device        *dev;
    cm_surface_type_t kind;          /* IMAGE / RECORDING / SUBSURFACE        */
    cm_format_t       format;        /* concrete pixel format                 */
    int               width, height;
    /* Lifetime reference count (cairo surfaces are refcounted).  Each independent
     * owner holds one reference: the creator (e.g. the Python wrapper, or a group-
     * pop pattern), and every SurfacePattern that wraps it.  cm_surface_destroy is
     * a DECREMENT; the real teardown happens on the last reference.  Set to 1 by
     * every creator.  APPENDED here (struct is heap-allocated via calloc + sizeof,
     * never serialized or size-asserted), so adding it shifts nothing on-wire. */
    int               refcount;
    size_t            stride;        /* bytes-per-row                         */
    double            dev_off_x, dev_off_y; /* surface device offset          */
    bool              finished;      /* cm_surface_finish was called          */

    /* GPU resources are opaque to C; held as void* and cast in cm_surface.m */
    void      *iosurface;       /* IOSurfaceRef (NULL for A1/recording/sub)  */
    void      *color_tex;       /* id<MTLTexture>, IOSurface-backed          */
    void      *msaa_color_tex;  /* id<MTLTexture> MSAA                        */
    void      *stencil_tex;     /* id<MTLTexture> MSAA stencil8 (or d32s8)    */

    /* CPU backing for A1 / copyback formats (malloc'd, NOT IOSurface).      */
    void      *cpu_backing;

    /* create_for_data: external buffer + its stride (we record, may copyback)*/
    void      *ext_data;
    size_t     ext_stride;

    /* subsurface: parent + sub-rect (no own IOSurface).                     */
    cm_surface_t *parent;
    cm_rect_t     sub_rect;

    /* map_to_image: the parent surface + mapped rect (alias of base).       */
    cm_surface_t *mapped_parent;
    cm_rect_t     mapped_rect;

    /* recording surface op-log (opaque cm_recording*).                      */
    void      *record;

    cm_status_t status;
};

struct cm_context {
    cm_surface_t  *surface;     /* retained == target                        */

    /* ---- CURRENT graphics-state values (the live gstate) ---- */
    cm_matrix_t    ctm;         /* current transformation matrix             */
    cm_source      source;      /* current paint source                      */
    cm_fill_rule_t fill_rule;
    double         line_width;
    cm_line_join_t line_join;
    cm_line_cap_t  line_cap;
    double         miter_limit;
    cm_operator_t  op;
    cm_antialias_t antialias;
    double         tolerance;
    double        *dash;        /* owned copy; NULL == no dash               */
    int            dash_count;
    double         dash_offset;
    double         global_alpha;

    /* ---- gstate stack + clip + groups ---- */
    cm_gstate     *stack;       /* save/restore stack (top == most recent)   */
    cm_clip_state *clip;        /* current clip (NULL == unclipped)          */
    cm_surface_t  *target;      /* current draw target (== surface or group) */
    cm_surface_t  *group_target;/* innermost push_group target, or NULL      */
    cm_group      *groups;      /* group stack                               */

    /* ---- font state ---- */
    cm_font_face_t   *font_face;
    cm_matrix_t       font_matrix;
    cm_font_options_t *font_options;
    cm_scaled_font_t *scaled_font;
    bool              scaled_font_dirty;

    /* ---- current PATH (OUTSIDE the gstate; cairo does not save it) ---- */
    cm_path        path;

    /* ---- per-frame encoding state ---- */
    void          *frame;       /* opaque cm_frame* (command buffer + ring)  */
    cm_paint_kind  last_pipeline_group;
    cm_status_t    status;
};

/* ==========================================================================
 * MODULE: cm_device.m  -- device, persistent state objects, frames
 * ========================================================================== */

cm_device  *cm_device_create(cm_status_t *out_status);
void        cm_device_destroy(cm_device *dev);

/** Pipeline-state selector keys.  The first four are the SHIPPING pipelines
 *  (kept byte-for-byte); the rest are appended for the full contract. */
typedef enum {
    CM_PIPE_STENCIL_NONZERO = 0,/* stencil pass, increment/decrement wrap    */
    CM_PIPE_STENCIL_EVENODD,    /* stencil pass, invert                      */
    CM_PIPE_COVER_SOLID,        /* cover pass, solid fragment                */
    CM_PIPE_COVER_LINEAR,       /* cover pass, linear-gradient fragment      */
    /* --- appended cover variants --- */
    CM_PIPE_COVER_RADIAL,       /* cover pass, radial-gradient fragment      */
    CM_PIPE_COVER_SURFACE,      /* cover pass, surface-texture fragment      */
    CM_PIPE_COVER_GOURAUD,      /* cover pass, per-vertex colour (mesh)      */
    CM_PIPE_COVER_MASK,         /* cover pass, source*mask-alpha             */
    CM_PIPE_COVER_SOLID_A8,     /* cover pass into an A8 target              */
    CM_PIPE_COUNT
} cm_pipe_id;

typedef enum {
    CM_DSS_STENCIL_WRITE_NONZERO = 0,/* incr/decr wrap, always               */
    CM_DSS_STENCIL_WRITE_EVENODD,    /* invert low bit                       */
    CM_DSS_COVER_TEST_NONZERO,       /* pass where stencil != 0, then zero   */
    CM_DSS_COVER_TEST_EVENODD,       /* pass where stencil&1, then zero       */
    CM_DSS_COUNT
} cm_dss_id;

void *cm_device_pipeline(cm_device *dev, cm_pipe_id id);
void *cm_device_depthstencil(cm_device *dev, cm_dss_id id);
void *cm_device_mtl(cm_device *dev);   /* id<MTLDevice>                      */

/** Cover-pipeline variant selector keyed by (operator, aa-none, clip-on,
 *  paint kind).  Returns an id<MTLRenderPipelineState> as void*.  (Stub may
 *  fall back to the matching base CM_PIPE_COVER_* pipeline.) */
void *cm_device_cover_pipeline(cm_device *dev, cm_operator_t op,
                               bool aa_none, bool clip, cm_paint_kind paint_kind);
/** A8-target cover-pipeline variant (R8 colour attachment) keyed the same way.
 *  Returns the R8 cover pipeline an A8 render target needs (a BGRA8 pipeline
 *  would mismatch the render pass); nil if that variant cannot be built.  The
 *  paint/fill/clip encode paths select this when ctx->surface is FORMAT_A8. */
void *cm_device_cover_pipeline_a8(cm_device *dev, cm_operator_t op,
                                  bool aa_none, bool clip, cm_paint_kind paint_kind);
/** Mask cover-pipeline variant: the source*mask-alpha fragment (cm_fs_mask) used
 *  by cairo_mask() / cairo_mask_surface().  Its own fragment family (not a
 *  cm_paint_kind source kind), keyed by (operator, aa-none, clip-on); BGRA8.
 *  Selecting it makes the mask modulate the CURRENT SOURCE colour by coverage,
 *  rather than the mask texture being sampled AS the colour. */
void *cm_device_cover_pipeline_mask(cm_device *dev, cm_operator_t op,
                                    bool aa_none, bool clip);
/** Lazy MTLSamplerState cache keyed by (filter, extend).  Returns an
 *  id<MTLSamplerState> as void*. */
void *cm_device_sampler(cm_device *dev, cm_filter_t filter, cm_extend_t extend);

/* ---- frame lifecycle ---- */
typedef struct cm_frame cm_frame;       /* opaque: cmd buffer + ring slice   */

cm_frame   *cm_frame_begin(cm_surface_t *surface);
void       *cm_frame_alloc_verts(cm_frame *f, size_t bytes,
                                 void **out_mtlbuffer, uint32_t *out_offset);
void       *cm_frame_alloc_uniforms(cm_frame *f, size_t bytes,
                                    void **out_mtlbuffer, uint32_t *out_offset);
void       *cm_frame_encoder(cm_frame *f);
cm_device  *cm_frame_device(cm_frame *f);
void        cm_frame_end(cm_frame *f, bool wait);

/* ==========================================================================
 * MODULE: cm_surface.m  -- recording / surface internals
 * ========================================================================== */

/** Internal: a non-IOSurface offscreen MSAA+resolve target for push_group.
 *  Consumed by cm_group.m. */
cm_surface_t *cm_offscreen_surface_create(int width, int height, cm_content_t content);

/* Surface attachment accessors used by cm_device.m. */
void *cm_surface_color_texture (cm_surface_t *s);
void *cm_surface_msaa_color_tex(cm_surface_t *s);
void *cm_surface_stencil_tex   (cm_surface_t *s);
void  cm_surface_did_render    (cm_surface_t *s);

/** Attach a real GPU raster backing (IOSurface + MSAA/stencil, like a normal
 *  image surface) to an already-zeroed surface struct, KEEPING its current
 *  kind.  Used by cm_recording.m to make a bounded RecordingSurface drawable.
 *  Sets s->dev/format/width/height/stride on success; returns false (struct
 *  left clean) for a non-GPU-renderable format or on allocation failure. */
bool  cm_surface_attach_gpu_backing(cm_surface_t *s, cm_format_t format,
                                    int width, int height);

/** Fold a device-space box (the footprint of a fill/stroke/paint) into a
 *  RecordingSurface's live ink bounds, so cairo_recording_surface_ink_extents
 *  reflects raster draws onto the surface's GPU backing.  Owned by
 *  cm_recording.m; no-op for a non-recording surface.  Called by the public
 *  draw entry points (cairo_metal.m / cm_compose.m). */
void  cm_recording_note_ink_user(cm_surface_t *surface,
                                 double x1, double y1, double x2, double y2);

/** Internal status setter (storage owned by cm_surface.m). */
void  cm_set_last_status(cm_status_t st);

/** Take one lifetime reference on a surface (refcount++).  Returns `surface` for
 *  chaining.  The matching drop is cm_surface_destroy (a decrement that frees on
 *  the last reference).  Used by cm_pattern.c (surface patterns hold a reference)
 *  and the Python wrapper (the creating wrapper holds the initial reference). */
cm_surface_t *cm_surface_reference(cm_surface_t *surface);

/* End (commit) the active draw frame for a surface (owned by cairo_metal.m). */
void  cm_glue_end_frame_for_surface(cm_surface_t *surface, bool wait);

/* ==========================================================================
 * MODULE: cm_surface_format.c  -- format metadata (pure-C single source)
 * ========================================================================== */

int          cm_format_is_gpu_renderable(cm_format_t fmt);
int          cm_format_has_alpha(cm_format_t fmt);
uint32_t     cm_format_iosurface_code(cm_format_t fmt);   /* 'BGRA'/'L008'/.. */
int          cm_format_mtl_pixelfmt(cm_format_t fmt);     /* MTLPixelFormat int*/
cm_content_t cm_content_for_format(cm_format_t fmt);
cm_format_t  cm_format_for_content(cm_content_t content);
const char  *cm_surface_type_string(cm_surface_type_t type);
const char  *cm_content_string(cm_content_t content);

/* ==========================================================================
 * MODULE: cm_state.c  -- gstate node lifecycle + dash validation
 * ========================================================================== */

void cm_state_init(cm_context_t *ctx);   /* initialise live gstate to defaults */
void cm_state_free(cm_context_t *ctx);   /* free stack + owned dash/clip refs  */
cm_status_t cm_state_push(cm_context_t *ctx);  /* deep-copy current -> stack   */
cm_status_t cm_state_pop(cm_context_t *ctx);   /* restore top -> current       */
/** Validate a dash pattern: negative -> INVALID_DASH; all-zero -> INVALID_DASH;
 *  empty (n==0) is OK and disables dashing. */
cm_status_t cm_dash_validate(const double *dashes, int n);

/* ==========================================================================
 * MODULE: cm_clip.m  -- clip plane (A8 coverage) + CPU clip geometry
 * ========================================================================== */

cm_status_t    cm_clip_apply(cm_context_t *ctx, const cm_path *path,
                             cm_fill_rule_t rule, bool preserve);
void           cm_clip_reset(cm_context_t *ctx);
cm_clip_state *cm_clip_retain(cm_clip_state *clip);
void           cm_clip_release(cm_clip_state *clip);
void           cm_clip_bind(void *encoder, cm_clip_state *clip); /* enc, A8+samp */
void           cm_clip_extents_dev(cm_clip_state *clip,
                                   float *x1, float *y1, float *x2, float *y2);
void           cm_clip_extents_user(cm_context_t *ctx,
                                    double *x1, double *y1, double *x2, double *y2);
int            cm_clip_contains(cm_context_t *ctx, double x, double y);

/* ==========================================================================
 * MODULE: cm_group.m  -- offscreen group targets
 * ========================================================================== */

cm_status_t   cm_group_push(cm_context_t *ctx, cm_content_t content);
cm_pattern_t *cm_group_pop(cm_context_t *ctx);   /* -> SurfacePattern         */

/* ==========================================================================
 * MODULE: cm_compose.m  -- operator/paint/mask encode
 * ========================================================================== */

cm_status_t cm_compose_paint(cm_context_t *ctx, cm_frame *frame, double global_alpha);
cm_status_t cm_compose_mask(cm_context_t *ctx, cm_frame *frame, cm_pattern_t *mask);
/** Lookup hook used by cm_fill/cm_stroke to honor set_operator (forwards to
 *  cm_device_cover_pipeline). */
void       *cm_compose_operator_pipeline(cm_device *dev, cm_operator_t op,
                                         bool aa_none, bool clip, cm_paint_kind kind);

/* ==========================================================================
 * MODULE: cm_pattern.c  -- universal pattern base + CPU queries
 * ========================================================================== */

/** Internal: the (retained) source surface backing a SURFACE/RASTER pattern,
 *  for the cover-surface path.  Returns NULL for non-surface patterns. */
cm_surface_t *cm_pattern_surface_texture(cm_pattern_t *pattern);

/* ==========================================================================
 * MODULE: cm_mesh.c  -- Coons-patch tessellation
 * ========================================================================== */

/** Emit Gouraud triangles for every patch into `dst` (CPU eval of the Coons
 *  surface + bilinear corner colour), transformed by `ctm`.  Returns the vertex
 *  count written.  `dst` is sized by cm_mesh_triangle_vertex_count. */
uint32_t cm_mesh_emit_triangles(cm_pattern_t *pattern, const cm_matrix_t *ctm,
                                cm_vtx_color *dst);
uint32_t cm_mesh_triangle_vertex_count(cm_pattern_t *pattern, const cm_matrix_t *ctm);

/* ==========================================================================
 * MODULE: cm_raster.c  -- raster-source acquire/release
 * ========================================================================== */

cm_surface_t *cm_raster_acquire(cm_pattern_t *pattern, cm_surface_t *target,
                                const cm_rectangle_int_t *extents);
void          cm_raster_release(cm_pattern_t *pattern, cm_surface_t *surface);

/* ==========================================================================
 * MODULE: cm_path.m  -- recording, flattening, tessellation, introspection
 * ========================================================================== */

void cm_path_init  (cm_path *p);
void cm_path_reset  (cm_path *p);   /* cm_new_path: clear verbs + cache       */
void cm_path_free  (cm_path *p);

void cm_path_move_to   (cm_path *p, double x, double y);
void cm_path_line_to   (cm_path *p, double x, double y);
void cm_path_curve_to  (cm_path *p, double x1,double y1,
                                    double x2,double y2,
                                    double x3,double y3);
void cm_path_close     (cm_path *p);
void cm_path_new_sub   (cm_path *p);

/* construction helpers (decompose to move/line/curve verbs) */
void cm_path_arc(cm_path *p, double xc, double yc, double radius,
                 double angle1, double angle2, bool negative);
void cm_path_rectangle(cm_path *p, double x, double y, double w, double h);
cm_status_t cm_path_rel_move_to (cm_path *p, double dx, double dy);
cm_status_t cm_path_rel_line_to (cm_path *p, double dx, double dy);
cm_status_t cm_path_rel_curve_to(cm_path *p, double dx1, double dy1,
                                 double dx2, double dy2, double dx3, double dy3);

cm_status_t cm_path_flatten(cm_path *p, const cm_matrix_t *ctm);
/** User-space flatten (identity CTM; does NOT touch the device cache); used by
 *  copy_path_flat. */
cm_status_t cm_path_flatten_user(const cm_path *p, cm_path *out);

uint32_t cm_path_emit_fan(const cm_path *p, uint32_t contour_index, cm_vec2f *dst);
uint32_t cm_path_fan_vertex_count(const cm_path *p);
void     cm_path_bounds(const cm_path *p,
                        float *minx, float *miny, float *maxx, float *maxy);

/* introspection (user space) */
int  cm_path_has_current_point(const cm_path *p);
void cm_path_get_current_point(const cm_path *p, double *x, double *y);
/** Tight user-space extents (no MSAA guard band). */
void cm_path_extents_user(const cm_path *p, const cm_matrix_t *ctm,
                          double *x1, double *y1, double *x2, double *y2);

/* verb-stream read accessors (for the shim's copy_path) */
uint32_t cm_path_verb_count(const cm_path *p);
/** Read verb `i`: type into *type, up to 6 doubles into pts.  Returns the point
 *  count for the verb (MOVE/LINE=1, CURVE=3, CLOSE=0). */
int cm_path_get_verb(const cm_path *p, uint32_t i, cm_path_data_type_t *type, double *pts);
/** Append a stream of recorded verbs (for copy_path/append_path replay). */
void cm_path_append_stream(cm_path *p, const cm_path_data_type_t *types,
                           const double *pts, uint32_t verb_count);
/** Append already-flattened contours (glyph/text outline sink, USER space). */
void cm_path_append_contours(cm_path *p, const double *pts_xy, const uint32_t *contour_lens,
                             uint32_t contour_count);

/* ==========================================================================
 * MODULE: cm_stroke.m  -- CPU stroke expansion + dash chopping
 * ========================================================================== */

/** Chop each contour of `src` into on-pieces per the dash pattern, writing the
 *  result into `dst` (device-space flattened cache). */
cm_status_t cm_dash_apply(const cm_path *src, cm_path *dst,
                          const double *dashes, int n, double offset);

/** Dash pre-pass shared by the stroke DRAW path (cairo_metal.m) and the stroke
 *  QUERY path (cm_query.c), so both chop identically.  `src` MUST already be the
 *  DEVICE-space flattened cache (cm_path_flatten(src, ctm) first).
 *    - No dash pattern (ctx->dash_count == 0): a no-op -- reports `src` itself
 *      via *out (the un-dashed stroke stays byte-for-byte identical) and leaves
 *      `scratch` empty.
 *    - Dash pattern set: pre-scales the USER-space ctx->dash[] + ctx->dash_offset
 *      to DEVICE space by cm_matrix_max_scale(ctm) -- the SAME scalar the callers
 *      apply to line_width (isotropic-CTM assumption; see cm_stroke.m's header)
 *      -- chops `src` into `scratch` via cm_dash_apply, and reports `scratch`.
 *      A singular CTM (max scale <= 0) cannot map the pattern to device space, so
 *      it instead reports `src` unchanged (undashed fallback) and leaves status
 *      SUCCESS rather than returning INVALID_DASH.
 *  `scratch` MUST be a caller-owned cm_path_init'd path; the caller ALWAYS frees
 *  it (it is left empty when *out == src).  Returns the dash status (SUCCESS when
 *  no dash); on failure *out is set to NULL. */
cm_status_t cm_dash_prepass(const cm_context_t *ctx, const cm_path *src,
                            cm_path *scratch, const cm_path **out);

/** Expand a flattened path into a fillable outline polygon.  `tolerance` drives
 *  round-join/cap segmentation (default CM_ARC_TOLERANCE). */
cm_status_t cm_stroke_expand(const cm_path *src, cm_path *dst,
                             double line_width,
                             cm_line_join_t join, cm_line_cap_t cap,
                             double miter_limit, double tolerance);

/* ==========================================================================
 * MODULE: cm_paint.m  -- solid + gradient LUT bake, uniform packing
 * ========================================================================== */

/** Fill `out` (cm_uniforms) paint fields from a context source, packing the new
 *  pat_inv rows / operator / global_alpha / mask fields and handling
 *  SOLID/LINEAR/RADIAL/SURFACE/MESH kinds. */
void cm_paint_fill_uniforms(const cm_source *src, const cm_matrix_t *ctm,
                            cm_uniforms *out);
void *cm_paint_gradient_lut(cm_device *dev, cm_pattern_t *pat);
void  cm_paint_cache_shutdown(void);

/* ==========================================================================
 * MODULE: cm_fill.m  -- stencil-then-cover encode
 * ========================================================================== */

cm_status_t cm_fill_encode(cm_context_t *ctx, cm_frame *frame,
                           const cm_path *path, cm_fill_rule_t rule);

/* ==========================================================================
 * MODULE: cm_query.c  -- point-in-contours (shared with cm_clip)
 * ========================================================================== */

/** WINDING (nonzero) / EVEN-ODD (parity) point-in-polygon over a path's
 *  flattened contours (device space).  Used by in_fill/in_stroke/in_clip. */
int cm_point_in_contours(const cm_path *path, double dx, double dy,
                         cm_fill_rule_t rule);

/* ==========================================================================
 * MODULE: cm_text.m  -- CoreText glyph-outline source (internal helpers)
 * ========================================================================== */

/** Resolve a toy font face (+ font matrix) to a native CTFontRef (void*). */
void *cm_text_resolve_toy_face(cm_font_face_t *face, const cm_matrix_t *font_matrix,
                               const cm_matrix_t *ctm);
void *cm_text_resolve_native(cm_scaled_font_t *scaled_font);
void  cm_text_release_native(void *native_font);
/** Load a unit-size native CTFontRef from a font FILE on disk (TTF/OTF/...), or
 * NULL.  `index` selects a face within a collection (.ttc).  Returned RETAINED;
 * release via cm_text_release_native.  Backs cm_ft_font_face_create_for_path
 * (the file-loaded font face) using CoreText, so the file's real glyphs render
 * through the SAME CoreText outline/shape path as toy faces. */
void *cm_text_ctfont_from_path(const char *path, int index);
/** A face's stored native CTFontRef (void*), or NULL.  cm_text_resolve_native
 * returns this (retained) when set, so a file-loaded face renders its own
 * glyphs.  Implemented in cm_font.c (the struct lives there). */
void *cm_font_face_native_font(cm_font_face_t *face);
/** Append one glyph's outline (USER space, cairo down-y) into `path`. */
void  cm_text_append_glyph_outline(void *native_font, unsigned long glyph,
                                   double x, double y, cm_path *path);
/** Shape UTF-8 to glyphs (CoreText).  Caller frees with cm_glyph_free. */
cm_status_t cm_text_shape(void *native_font, double x, double y,
                          const char *utf8, int utf8_len,
                          cm_glyph_t **glyphs, int *num_glyphs);
void cm_text_glyph_extents(void *native_font, const cm_glyph_t *glyphs, int n,
                           cm_text_extents_t *out);
void cm_text_font_extents(void *native_font, cm_font_extents_t *out);

/* ==========================================================================
 * MODULE: cm_ft.c  -- optional FreeType outline source (guarded)
 * ========================================================================== */
#if CM_ENABLE_FREETYPE
void cm_ft_append_glyph_outline(cm_font_face_t *face, unsigned long glyph,
                                double x, double y, cm_path *path);
void cm_ft_glyph_extents(cm_font_face_t *face, const cm_glyph_t *glyphs, int n,
                         cm_text_extents_t *out);
void cm_ft_font_extents(cm_font_face_t *face, cm_font_extents_t *out);
#endif

/* ==========================================================================
 * Shared math helpers (cm_matrix.c)
 * --------------------------------------------------------------------------
 * cm_matrix_identity/apply/mul_scale/is_invertible/max_scale are INTERNAL-only
 * helpers used by the encode path.  The full affine algebra (cm_matrix_init*,
 * multiply, invert, transform_point/distance, transform_bbox) is declared in
 * the PUBLIC header (the pycairo shim forwards the Matrix class to it), so it is
 * not redeclared here.
 * ========================================================================== */
void   cm_matrix_identity (cm_matrix_t *m);
void   cm_matrix_mul_scale(cm_matrix_t *m, double sx, double sy); /* m*=scale */
void   cm_matrix_apply    (const cm_matrix_t *m, double x, double y,
                           double *ox, double *oy);
bool   cm_matrix_is_invertible(const cm_matrix_t *m);
double cm_matrix_max_scale(const cm_matrix_t *m);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* CM_INTERNAL_H */
