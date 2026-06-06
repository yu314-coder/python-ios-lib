/*
 * cm_device.m  --  CairoMetal Metal backbone (device, states, ring, frames)
 * ============================================================================
 *
 * MODULE OWNER of cm_internal.h "MODULE: cm_device.m".  This is the GPU
 * backbone every other module sits on; it is the ONLY place that:
 *
 *   - owns the process MTLDevice + a single MTLCommandQueue;
 *   - builds ALL persistent MTLRenderPipelineState (CM_PIPE_*) and
 *     MTLDepthStencilState (CM_DSS_*) objects EXACTLY ONCE in cm_device_create
 *     (DESIGN.md §4.1 -- nothing is compiled or created per-frame/per-draw);
 *   - owns a CM_FRAMES_IN_FLIGHT-deep triple-buffered ring of dynamic vertex +
 *     uniform MTLBuffers, gated by a dispatch_semaphore so the CPU never writes
 *     a slice the GPU is still reading (DESIGN.md §4.3 + §4.5);
 *   - drives the per-frame lifecycle: cm_frame_begin builds the ONE command
 *     buffer + render command encoder for the whole frame (MSAA color + stencil
 *     attachments, load-clear), cm_frame_alloc_* bump-allocate from the ring
 *     with NO per-draw malloc, and cm_frame_end resolves MSAA -> the
 *     IOSurface-backed color texture, commits, and signals the semaphore in the
 *     completion handler (DESIGN.md §4.2 + §4.4).
 *
 * SHADER CONTRACT (shaders/fill.metal -- the shipping cover path binds a LUT at
 * texture(0) with NO sampler binding, which matches fill.metal's constexpr
 * sampler; the SURFACE/MASK frags add a runtime sampler(0)).  The pipelines wire
 * to these exact entry points:
 *
 *   cm_pipe_id                vertex fn          fragment fn
 *   ------------------------  -----------------  --------------------
 *   CM_PIPE_STENCIL_NONZERO   cm_vs_stencil      cm_fs_stencil
 *   CM_PIPE_STENCIL_EVENODD   cm_vs_stencil      cm_fs_stencil
 *   CM_PIPE_COVER_SOLID       cm_vs_cover        cm_fs_cover_solid
 *   CM_PIPE_COVER_LINEAR      cm_vs_cover        cm_fs_cover_linear
 *   CM_PIPE_COVER_RADIAL      cm_vs_cover        cm_fs_cover_radial
 *   CM_PIPE_COVER_SURFACE     cm_vs_cover        cm_fs_cover_surface
 *   CM_PIPE_COVER_GOURAUD     cm_vs_cover_color  cm_fs_cover_gouraud
 *   CM_PIPE_COVER_MASK        cm_vs_cover        cm_fs_mask
 *   CM_PIPE_COVER_SOLID_A8    cm_vs_cover        cm_fs_cover_solid_a8 (R8 target)
 *
 * Attachment formats (must match cm_surface.m):
 *   color   : the SURFACE's concrete colour format (BGRA8 for ARGB32/RGB24, R8
 *             for A8, B5G6R5 for 565); sampleCount = CM_MSAA_SAMPLE_COUNT (or 1
 *             for the ANTIALIAS_NONE variant); PREMULTIPLIED OVER (or a per-
 *             operator Porter-Duff blend) on the cover pipelines.
 *   stencil : MTLPixelFormatStencil8,   sampleCount matches the colour.
 *
 * COVER-PIPELINE VARIANT TABLE (cm_device_cover_pipeline):
 *   The shipping four pipelines above are built eagerly + kept byte-for-byte.
 *   Every other cover need is served lazily from a variant table keyed by
 *   (operator, aa-MSAA-or-not, clip-on/off, paint_kind):
 *     - ops 0..13  : fixed-function Porter-Duff -> a per-operator
 *                    MTLRenderPipelineColorAttachment blend state.
 *     - ops 14..28 : separable / non-separable blend modes that require
 *                    framebuffer-fetch the shipping fragments do not yet expose;
 *                    the device builds them with OVER blend on the same
 *                    programmable fragment and the fragment reads the `operator`
 *                    uniform once fill.metal grows the [[color(0)]] input (see the
 *                    BUILD seam at the bottom).
 *     - paint_kind : selects the fragment family (solid/linear/radial/surface/
 *                    gouraud/mask).
 *     - aa_none    : selects sampleCount==1 (no MSAA) for ANTIALIAS_NONE.
 *     - the A8 target variant (CM_PIPE_COVER_SOLID_A8) is its own R8 entry.
 *   Variants are cached so nothing is compiled per-draw after the first use.
 *
 * SAMPLER CACHE (cm_device_sampler):
 *   constexpr samplers in the shader cannot encode a runtime filter/extend, so
 *   the SURFACE/MASK cover frags bind a real MTLSamplerState.  A lazy 6x4 table
 *   keyed by (cm_filter_t, cm_extend_t) is built on demand and reused.
 * ============================================================================
 */

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* Surface attachment accessors implemented in cm_surface.m. */
extern void *cm_surface_color_texture (cm_surface_t *s); /* id<MTLTexture> IOSurface BGRA8 */
extern void *cm_surface_msaa_color_tex(cm_surface_t *s); /* id<MTLTexture> MSAA BGRA8       */
extern void *cm_surface_stencil_tex   (cm_surface_t *s); /* id<MTLTexture> MSAA stencil8    */

/* Format -> MTLPixelFormat enum value (ABI-stable int), from cm_surface_format.c.
 * cm_frame_begin uses it to build the colour attachment in the SURFACE's concrete
 * format so a pipeline whose colour format matches can render into it (Metal
 * requires the render-pass colour format to equal the pipeline's colour format).
 * The same int->MTLPixelFormat decode lives in cm_surface.m; mirrored here. */
extern int cm_format_mtl_pixelfmt(cm_format_t fmt);

/* ==========================================================================
 * NEW device seams owned here (forward declarations).
 * --------------------------------------------------------------------------
 * These extend the device's public-to-the-other-modules surface but are NOT in
 * the frozen cm_internal.h yet (the scaffold wired only the four shipping
 * pipelines + the cover/sampler stubs).  Declaring them here keeps this TU
 * warning-clean under -Wmissing-prototypes and documents exactly what the Build
 * phase should add to cm_internal.h so cm_clip.m / cm_compose.m / cm_path.m can
 * link against them.  Until then a caller reaches them with a matching extern
 * (the same pattern cm_surface.m uses for cm_device_mtl_id / cm_device_queue_id).
 * ========================================================================== */
void  *cm_device_cover_pipeline_a8(cm_device *dev, cm_operator_t op,
                                   bool aa_none, bool clip, cm_paint_kind paint_kind);
void  *cm_device_cover_pipeline_mask(cm_device *dev, cm_operator_t op,
                                     bool aa_none, bool clip);
void   cm_device_set_tolerance(cm_device *dev, double tolerance);
double cm_device_tolerance(cm_device *dev);

/* ANTIALIAS_NONE single-sample path (BUG 7).  cm_frame_begin_single opens a
 * 1-sample render pass that draws DIRECTLY into the surface's resolved colour
 * texture (no MSAA, no resolve), so coverage is a hard per-pixel 0/1 and a fully
 * covered interior is opaque (255) instead of 1-of-4 samples (~64).  The stencil
 * pass uses the 1-sample stencil pipeline returned here; the cover pass uses the
 * variant table's aa_none cells.  cm_frame_is_single_sample lets the fill encode
 * select the matching 1-sample stencil pipeline. */
cm_frame *cm_frame_begin_single(cm_surface_t *surface);
bool      cm_frame_is_single_sample(cm_frame *f);
void     *cm_device_stencil_pipeline_aa_none(cm_device *dev, bool evenodd);

/* ==========================================================================
 * Ring buffer slot + per-frame state
 * --------------------------------------------------------------------------
 * One slot per in-flight frame.  Each slot owns a vertex arena and a uniform
 * arena (persistent MTLBuffers, allocated once); per frame we just reset the
 * bump cursors -- no allocation.  The frame's transient Objective-C objects
 * (command buffer + encoder) live here too and are reused slot-by-slot.
 * ========================================================================== */
typedef struct cm_frame {
    cm_device *dev;                     /* back-pointer for cm_frame_device     */
    int        slot;                    /* ring index [0, CM_FRAMES_IN_FLIGHT)  */
    bool       active;                  /* begun and not yet ended              */
    bool       in_flight;               /* committed; GPU still reading buffers  */
    bool       single_sample;           /* ANTIALIAS_NONE 1-sample pass (no MSAA)*/

    /* Persistent per-slot dynamic arenas (created once in cm_device_create). */
    id<MTLBuffer> vbuf;                 /* CM_VTX_RING_BYTES                    */
    id<MTLBuffer> ubuf;                 /* CM_UNI_RING_BYTES                    */
    uint8_t      *vbase, *ubase;        /* CPU-mapped bases (Shared storage)    */
    size_t        vcur,  ucur;          /* bump cursors, reset every begin      */

    /* Transient per-frame objects (set in begin, cleared in end). */
    id<MTLCommandBuffer>        cmd;
    id<MTLRenderCommandEncoder> enc;
    cm_surface_t               *surface;
} cm_frame;

/* ==========================================================================
 * Cover-pipeline VARIANT cache dimensions
 * --------------------------------------------------------------------------
 * The variant table is keyed by (paint_kind, operator, aa_none, clip, A8).  We
 * keep the eager four shipping pipelines in `pipelines[]` (untouched) and store
 * every lazily-built cover VARIANT in a separate `cover_variants[]` table so the
 * shipping byte-for-byte states are never reindexed.
 *
 * The full key product is large, but only a handful of cells are ever touched
 * (manim uses OVER + a few blend modes, MSAA on, no clip).  We therefore index a
 * dense small table and build cells on first use; an unbuilt cell is nil.
 * ========================================================================== */
#define CM_CV_PAINT_KINDS   6   /* SOLID/LINEAR/RADIAL/SURFACE/MESH + MASK     */
#define CM_CV_OPS          29   /* cairo operators 0..28                       */

/* The mask cover (source * mask-pattern-alpha) is its own fragment family that is
 * NOT one of the cm_paint_kind source kinds, so it gets a dedicated variant-table
 * row past CM_PAINT_MESH.  cm_compose.m requests it via cm_device_cover_pipeline
 * with this pseudo-kind so cairo_mask() / cairo_mask_surface() select cm_fs_mask
 * (which modulates the CURRENT SOURCE COLOUR by the mask's coverage) instead of
 * the surface-cover fragment (which would sample the mask AS the colour). */
#define CM_CV_PAINT_MASK    5   /* pseudo-kind: cm_fs_mask (source*maskA) row   */
#define CM_CV_AA            2   /* MSAA (0) vs no-MSAA / ANTIALIAS_NONE (1)    */
#define CM_CV_CLIP          2   /* clip off (0) vs on (1)                      */
#define CM_CV_A8            2   /* BGRA/565 colour (0) vs A8/R8 target (1)     */

/* Sampler cache: 6 filters x 4 extends (constexpr samplers can't carry runtime
 * filter/extend, so SURFACE/MASK cover frags bind one of these). */
#define CM_SAMP_FILTERS     6   /* cm_filter_t  FAST..GAUSSIAN                 */
#define CM_SAMP_EXTENDS     4   /* cm_extend_t  NONE/REPEAT/REFLECT/PAD        */

/* ==========================================================================
 * Device wrapper
 * ========================================================================== */
struct cm_device {
    id<MTLDevice>              mtl;
    id<MTLCommandQueue>        queue;
    id<MTLLibrary>             library;

    id<MTLRenderPipelineState> pipelines[CM_PIPE_COUNT];
    id<MTLDepthStencilState>   dss[CM_DSS_COUNT];

    /* Single-sample (ANTIALIAS_NONE) stencil pipelines.  The shipping stencil
     * pipelines in pipelines[] are 4x MSAA; the AA-none path renders into a
     * 1-sample pass (directly to the surface colour texture, no MSAA resolve) so
     * coverage is a hard per-pixel 0/1 with no sample averaging.  Index 0 ==
     * nonzero, 1 == even-odd.  The matching 1-sample COVER pipelines come from the
     * variant table's aa_none cells (cm_device_cover_pipeline(..., aa_none=true)).
     * The depth-stencil STATES (dss[]) are sample-count-independent and reused. */
    id<MTLRenderPipelineState> stencil_aa_none[2];

    /* Lazily-built cover-pipeline VARIANT table (see cm_device_cover_pipeline).
     * Flattened multi-dim index; nil == not yet built. */
    id<MTLRenderPipelineState> cover_variants[CM_CV_PAINT_KINDS]
                                             [CM_CV_OPS]
                                             [CM_CV_AA]
                                             [CM_CV_CLIP]
                                             [CM_CV_A8];

    /* Lazy 6x4 MTLSamplerState cache keyed by (filter, extend). */
    id<MTLSamplerState>        samplers[CM_SAMP_FILTERS][CM_SAMP_EXTENDS];

    /* Triple-buffered ring + the gate. */
    dispatch_semaphore_t       sem;     /* count = CM_FRAMES_IN_FLIGHT          */
    cm_frame                   frames[CM_FRAMES_IN_FLIGHT];
    uint64_t                   frame_seq;/* monotonically increasing; slot=seq%N*/

    /* Runtime flatten tolerance (device px).  Defaults to CM_FLATTEN_TOLERANCE.
     * The flatten/stroke encode reads it through cm_device_tolerance(); see the
     * tolerance seam note where cm_frame_begin's siblings are declared. */
    double                     flatten_tolerance;

    /* Serialises lazy variant/sampler builds across context threads (the cache
     * is process-shared via cm_surface.m's single device). */
    pthread_mutex_t            lazy_mtx;
};

/* Alignment for ring sub-allocations: 16 bytes is enough for cm_uniforms
 * (float4-aligned fields) and cm_vec2f, and matches Metal's preferred buffer
 * offset alignment for non-texture buffers on Apple GPUs. */
#define CM_RING_ALIGN 16u

static inline size_t cm_align_up(size_t v, size_t a)
{
    return (v + (a - 1)) & ~(a - 1);
}

/* ==========================================================================
 * Metal library loading
 * --------------------------------------------------------------------------
 * Resolution order (first that works wins):
 *   1. $CM_METALLIB  -- absolute path to a prebuilt default.metallib
 *      (the Makefile's `make run` sets this for the CLI/demo path).
 *   2. [device newDefaultLibrary] -- the app/main-bundle default.metallib
 *      (Xcode's Metal build phase produced it when fill.metal is in the app
 *      target).
 *   3. compile shaders/fill.metal at runtime from source -- located via
 *      $CM_METAL_SRC, the SwiftPM resource bundle next to the executable, or a
 *      few source-tree-relative candidates.  Only fill.metal is needed: it
 *      defines every cm_* entry point this module references.
 * Returns a +0 (autoreleased) id<MTLLibrary> or nil.
 * ========================================================================== */

static id<MTLLibrary> cm_try_metallib_path(id<MTLDevice> mtl, NSString *path)
{
    if (path.length == 0) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSError *err = nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    id<MTLLibrary> lib = [mtl newLibraryWithURL:url error:&err];
    return lib;   /* nil on failure */
}

static id<MTLLibrary> cm_try_compile_source(id<MTLDevice> mtl, NSString *path)
{
    if (path.length == 0) return nil;
    NSError *err = nil;
    NSString *src = [NSString stringWithContentsOfFile:path
                                              encoding:NSUTF8StringEncoding
                                                 error:&err];
    if (!src) return nil;
    MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
    id<MTLLibrary> lib = [mtl newLibraryWithSource:src options:opts error:&err];
    if (!lib) {
        NSLog(@"CairoMetal: failed to compile %@: %@", path, err);
    }
    return lib;
}

/* Candidate filesystem locations for the fill.metal source. */
static NSArray<NSString *> *cm_metal_source_candidates(void)
{
    NSMutableArray *out = [NSMutableArray array];

    /* Explicit override. */
    const char *env = getenv("CM_METAL_SRC");
    if (env && *env) [out addObject:[NSString stringWithUTF8String:env]];

    /* SwiftPM copies declared resources into a bundle named
     * "<Package>_<Target>.bundle" next to the built product. */
    NSString *exeDir = [[[NSBundle mainBundle] executablePath]
                            stringByDeletingLastPathComponent];
    NSArray *bundleNames = @[ @"CairoMetal_CairoMetal.bundle",
                              @"CairoMetal.bundle" ];
    for (NSString *bn in bundleNames) {
        if (exeDir) {
            NSString *p = [[exeDir stringByAppendingPathComponent:bn]
                              stringByAppendingPathComponent:@"shaders/fill.metal"];
            [out addObject:p];
            /* Resources may be flattened (no shaders/ prefix). */
            [out addObject:[[exeDir stringByAppendingPathComponent:bn]
                              stringByAppendingPathComponent:@"fill.metal"]];
        }
    }

    /* Main-bundle resource lookup (iOS app bundle). */
    NSString *res = [[NSBundle mainBundle] pathForResource:@"fill"
                                                    ofType:@"metal"];
    if (res) [out addObject:res];

    /* Source-tree-relative fallbacks (running from build/ or the repo root). */
    if (exeDir) {
        [out addObject:[exeDir stringByAppendingPathComponent:@"../shaders/fill.metal"]];
        [out addObject:[exeDir stringByAppendingPathComponent:@"shaders/fill.metal"]];
    }

    return out;
}

static id<MTLLibrary> cm_load_library(id<MTLDevice> mtl)
{
    /* 1. Prebuilt metallib via env. */
    const char *env = getenv("CM_METALLIB");
    if (env && *env) {
        id<MTLLibrary> lib = cm_try_metallib_path(mtl,
                                  [NSString stringWithUTF8String:env]);
        if (lib) return lib;
    }

    /* 2. App / main-bundle default.metallib. */
    {
        NSError *err = nil;
        id<MTLLibrary> lib = [mtl newDefaultLibraryWithBundle:[NSBundle mainBundle]
                                                        error:&err];
        if (lib) return lib;
        lib = [mtl newDefaultLibrary];
        if (lib) return lib;
    }

    /* 3. Compile fill.metal from source. */
    for (NSString *cand in cm_metal_source_candidates()) {
        id<MTLLibrary> lib = cm_try_compile_source(mtl, cand);
        if (lib) return lib;
    }
    return nil;
}

/* ==========================================================================
 * Pipeline-state construction (built once)
 * ========================================================================== */

/* Common color-attachment configuration: BGRA8, MSAA, premultiplied OVER blend.
 * `write_color` masks color writes off for the stencil pass (only the stencil
 * op matters there). */
static void cm_configure_color_attachment(MTLRenderPipelineColorAttachmentDescriptor *ca,
                                          bool write_color)
{
    ca.pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (write_color) {
        ca.writeMask           = MTLColorWriteMaskAll;
        ca.blendingEnabled     = YES;
        /* PREMULTIPLIED OVER: src is already premultiplied in the fragment. */
        ca.rgbBlendOperation   = MTLBlendOperationAdd;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
        ca.sourceRGBBlendFactor        = MTLBlendFactorOne;
        ca.sourceAlphaBlendFactor      = MTLBlendFactorOne;
        ca.destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
        ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    } else {
        ca.writeMask       = MTLColorWriteMaskNone;
        ca.blendingEnabled = NO;
    }
}

static id<MTLRenderPipelineState>
cm_build_pipeline(cm_device *dev, NSString *vfn, NSString *ffn,
                  bool write_color, NSError **err)
{
    id<MTLFunction> vs = [dev->library newFunctionWithName:vfn];
    id<MTLFunction> fs = [dev->library newFunctionWithName:ffn];
    if (!vs || !fs) {
        if (err) {
            *err = [NSError errorWithDomain:@"CairoMetal" code:1
                     userInfo:@{ NSLocalizedDescriptionKey:
                       [NSString stringWithFormat:
                         @"missing shader function %@ / %@", vfn, ffn] }];
        }
        return nil;
    }

    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction   = vs;
    pd.fragmentFunction = fs;
    pd.rasterSampleCount = CM_MSAA_SAMPLE_COUNT;     /* MSAA */
    cm_configure_color_attachment(pd.colorAttachments[0], write_color);
    pd.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;
    /* No depth attachment (2D). No vertex descriptor: shaders index buffer(0)
     * by [[vertex_id]] directly (see fill.metal). */

    return [dev->mtl newRenderPipelineStateWithDescriptor:pd error:err];
}

/* Build a SINGLE-sample stencil pipeline (cm_vs_stencil / cm_fs_stencil, colour
 * writes masked off) for the ANTIALIAS_NONE 1-sample pass.  Its colour attachment
 * is BGRA8 (the ARGB32/RGB24 AA-none target -- the dominant case; an A8/565 AA-none
 * fill is rare and falls back to the MSAA path if this format mismatches).  The
 * stencil op lives in the depth-stencil STATE (reused from dss[], sample-count
 * independent), so only the rasterSampleCount + colour format differ from the
 * shipping MSAA stencil pipeline. */
static id<MTLRenderPipelineState>
cm_build_stencil_aa_none(cm_device *dev, NSError **err)
{
    id<MTLFunction> vs = [dev->library newFunctionWithName:@"cm_vs_stencil"];
    id<MTLFunction> fs = [dev->library newFunctionWithName:@"cm_fs_stencil"];
    if (!vs || !fs) {
        if (err) *err = [NSError errorWithDomain:@"CairoMetal" code:1
                          userInfo:@{ NSLocalizedDescriptionKey:
                            @"missing cm_vs_stencil / cm_fs_stencil" }];
        return nil;
    }
    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction    = vs;
    pd.fragmentFunction  = fs;
    pd.rasterSampleCount  = 1u;                         /* NO MSAA: hard edges    */
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pd.colorAttachments[0].writeMask   = MTLColorWriteMaskNone;
    pd.colorAttachments[0].blendingEnabled = NO;
    pd.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;
    return [dev->mtl newRenderPipelineStateWithDescriptor:pd error:err];
}

/* ==========================================================================
 * Cover-pipeline VARIANT builder
 * --------------------------------------------------------------------------
 * One richer descriptor builder backs every cell of the variant table.  It is a
 * superset of cm_build_pipeline (which stays byte-for-byte for the shipping
 * four): it additionally selects the colour pixel format (BGRA8 vs R8 for the A8
 * target), the sample count (MSAA vs 1 for ANTIALIAS_NONE), and a per-operator
 * Porter-Duff blend state.
 * ========================================================================== */

/* True for the cairo operators (14..28: MULTIPLY..HSL_LUMINOSITY) that are the
 * PDF/SVG separable + non-separable blend modes.  These are NOT expressible as a
 * fixed-function MTLRenderPipelineColorAttachment blend, so their cover pipelines
 * use the programmable-blend fragments (cm_fs_blend_*) which read the destination
 * via [[color(0)]] framebuffer fetch and composite OVER in-shader.  Operators
 * 0..13 stay fixed-function (a per-operator blend STATE on the plain cover frag). */
static inline bool cm_op_is_blend(cm_operator_t op)
{
    return (int)op >= (int)CM_OPERATOR_MULTIPLY &&
           (int)op <= (int)CM_OPERATOR_HSL_LUMINOSITY;
}

/* Map a (paint kind, operator, clip) to its (vertex, fragment) shader entry-point
 * pair.  GOURAUD (mesh) uses the per-vertex-colour vertex stage; everyone else
 * uses cm_vs_cover.  For a blend-mode operator (14..28) the PROGRAMMABLE-blend
 * fragment of the kind (cm_fs_blend_*) is selected instead of the plain cover
 * fragment, so the per-mode blend math runs in-shader against the framebuffer-
 * fetched dest.  The CM_CV_PAINT_MASK pseudo-kind selects the source*mask-alpha
 * fragment.
 *
 * CLIP: when `clip` is true, select the *_clip variant of the chosen fragment.
 * The _clip fragments are byte-identical to the base ones except they sample the
 * A8 clip-coverage plane bound at texture(1)/sampler(1) (cm_clip_bind) and
 * multiply the premultiplied output by that coverage, so pixels OUTSIDE the clip
 * SHAPE are not written (the scissor only bounds the AABB; per-pixel clipping of a
 * non-rectangular clip path lives here).  This applies to BOTH the fixed-function
 * operators 0..13 (whose blend lives in the pipeline STATE, clip in the fragment)
 * and the programmable-blend operators 14..28 (cm_fs_blend_*_clip lerp toward the
 * untouched dest by coverage).  The A8 (R8) target has no _clip variant (an A8
 * clip plane is itself rendered by cm_clip.m's own pass), so it never takes clip.
 * Returns false for a kind that has no cover fragment. */
static bool cm_cover_shader_names(int kind, cm_operator_t op, bool a8, bool clip,
                                  NSString **out_vfn, NSString **out_ffn)
{
    NSString *vfn   = @"cm_vs_cover";
    bool      blend = cm_op_is_blend(op);
    /* The A8 target is its own coverage-only write with no clip-aware variant, so
     * a clipped draw INTO an A8 surface falls back to the non-clip A8 fragment. */
    bool      cl    = clip && !a8;
    NSString *ffn   = nil;

    switch (kind) {
        case CM_PAINT_SOLID:
            ffn = blend ? (cl ? @"cm_fs_blend_solid_clip"   : @"cm_fs_blend_solid")
                        : (cl ? @"cm_fs_cover_solid_clip"   : @"cm_fs_cover_solid");
            break;
        case CM_PAINT_LINEAR:
            ffn = blend ? (cl ? @"cm_fs_blend_linear_clip"  : @"cm_fs_blend_linear")
                        : (cl ? @"cm_fs_cover_linear_clip"  : @"cm_fs_cover_linear");
            break;
        case CM_PAINT_RADIAL:
            ffn = blend ? (cl ? @"cm_fs_blend_radial_clip"  : @"cm_fs_blend_radial")
                        : (cl ? @"cm_fs_cover_radial_clip"  : @"cm_fs_cover_radial");
            break;
        case CM_PAINT_SURFACE:
            ffn = blend ? (cl ? @"cm_fs_blend_surface_clip" : @"cm_fs_blend_surface")
                        : (cl ? @"cm_fs_cover_surface_clip" : @"cm_fs_cover_surface");
            break;
        case CM_PAINT_MESH:
            vfn = @"cm_vs_cover_color";
            ffn = blend ? (cl ? @"cm_fs_blend_gouraud_clip" : @"cm_fs_blend_gouraud")
                        : (cl ? @"cm_fs_cover_gouraud_clip" : @"cm_fs_cover_gouraud");
            break;
        case CM_CV_PAINT_MASK:
            /* source * mask-pattern-alpha.  The blend-mode variant for a masked
             * draw is not exercised (cairo_mask uses OVER-family ops); ship the
             * plain mask fragment, which honours the operator's fixed-function
             * blend STATE like the other 0..13 covers.  The _clip variant adds the
             * clip-coverage multiply so a masked draw inside a non-rect clip is
             * also confined to the clip shape. */
            ffn = cl ? @"cm_fs_mask_clip" : @"cm_fs_mask"; break;
        default: return false;
    }
    /* The A8 target is an ALPHA/COVERAGE-only write (R8Unorm takes the fragment's
     * .r).  Use the dedicated A8 solid cover, which emits the source's COVERAGE
     * ALPHA in .r -- NOT the premultiplied blue of the BGRA solid fragment (which
     * stored luminance, making opaque black/green read 0 instead of 255).  An A8
     * target is only ever the SOLID-coverage write, so it overrides any kind/op. */
    if (a8) { vfn = @"cm_vs_cover"; ffn = @"cm_fs_cover_solid_a8"; }
    if (out_vfn) *out_vfn = vfn;
    if (out_ffn) *out_ffn = ffn;
    return true;
}

/*
 * Configure the colour attachment's BLEND state for a cairo operator.
 *
 * The cover fragments output PREMULTIPLIED colour, so the Porter-Duff factors are
 * the premultiplied forms.  cairo operators 0..13 are the Porter-Duff /
 * arithmetic set that map cleanly onto fixed-function MTLBlend* state:
 *
 *   CLEAR     : (0, 0)                      -> zero everything
 *   SOURCE    : (One, Zero)                 -> replace
 *   OVER      : (One, 1-srcA)               -> src over dst (the shipping blend)
 *   IN        : (dstA, 0)                   -> src shaped by dst alpha
 *   OUT       : (1-dstA, 0)
 *   ATOP      : (dstA, 1-srcA)
 *   DEST      : (0, One)                    -> keep dst
 *   DEST_OVER : (1-dstA, One)
 *   DEST_IN   : (0, srcA)
 *   DEST_OUT  : (0, 1-srcA)
 *   DEST_ATOP : (1-dstA, srcA)
 *   XOR       : (1-dstA, 1-srcA)
 *   ADD       : (One, One)                  -> additive
 *   SATURATE  : (min(srcA,1-dstA) via SourceAlphaSaturated, One)
 *
 * Operators 14..28 are the separable / non-separable blend modes (MULTIPLY,
 * SCREEN, ... HSL_LUMINOSITY).  Those need the DESTINATION colour as a shader
 * input (framebuffer fetch) which the shipping fragments do not expose yet, so we
 * fall back to OVER blending here -- a deterministic, correct-for-opaque result
 * -- and the fragment will read the `operator` uniform to do the blend math once
 * fill.metal grows the [[color(0)]] input (see the BUILD seam at file end).
 * Returns true if the operator is a fixed-function blend (0..13), false if it is
 * a programmable-blend fallback (14..28) -- purely informational for the caller.
 */
static bool cm_configure_blend_for_operator(MTLRenderPipelineColorAttachmentDescriptor *ca,
                                            cm_operator_t op)
{
    ca.blendingEnabled     = YES;
    ca.rgbBlendOperation   = MTLBlendOperationAdd;
    ca.alphaBlendOperation = MTLBlendOperationAdd;

    MTLBlendFactor sRGB = MTLBlendFactorOne;
    MTLBlendFactor dRGB = MTLBlendFactorOneMinusSourceAlpha;
    MTLBlendFactor sA   = MTLBlendFactorOne;
    MTLBlendFactor dA   = MTLBlendFactorOneMinusSourceAlpha;
    bool fixed = true;

    switch (op) {
        case CM_OPERATOR_CLEAR:
            sRGB = MTLBlendFactorZero; dRGB = MTLBlendFactorZero;
            sA   = MTLBlendFactorZero; dA   = MTLBlendFactorZero; break;
        case CM_OPERATOR_SOURCE:
            sRGB = MTLBlendFactorOne;  dRGB = MTLBlendFactorZero;
            sA   = MTLBlendFactorOne;  dA   = MTLBlendFactorZero; break;
        case CM_OPERATOR_OVER:
            /* defaults (the shipping OVER blend) */ break;
        case CM_OPERATOR_IN:
            sRGB = MTLBlendFactorDestinationAlpha; dRGB = MTLBlendFactorZero;
            sA   = MTLBlendFactorDestinationAlpha; dA   = MTLBlendFactorZero; break;
        case CM_OPERATOR_OUT:
            sRGB = MTLBlendFactorOneMinusDestinationAlpha; dRGB = MTLBlendFactorZero;
            sA   = MTLBlendFactorOneMinusDestinationAlpha; dA   = MTLBlendFactorZero; break;
        case CM_OPERATOR_ATOP:
            sRGB = MTLBlendFactorDestinationAlpha; dRGB = MTLBlendFactorOneMinusSourceAlpha;
            sA   = MTLBlendFactorDestinationAlpha; dA   = MTLBlendFactorOneMinusSourceAlpha; break;
        case CM_OPERATOR_DEST:
            sRGB = MTLBlendFactorZero; dRGB = MTLBlendFactorOne;
            sA   = MTLBlendFactorZero; dA   = MTLBlendFactorOne; break;
        case CM_OPERATOR_DEST_OVER:
            sRGB = MTLBlendFactorOneMinusDestinationAlpha; dRGB = MTLBlendFactorOne;
            sA   = MTLBlendFactorOneMinusDestinationAlpha; dA   = MTLBlendFactorOne; break;
        case CM_OPERATOR_DEST_IN:
            sRGB = MTLBlendFactorZero; dRGB = MTLBlendFactorSourceAlpha;
            sA   = MTLBlendFactorZero; dA   = MTLBlendFactorSourceAlpha; break;
        case CM_OPERATOR_DEST_OUT:
            sRGB = MTLBlendFactorZero; dRGB = MTLBlendFactorOneMinusSourceAlpha;
            sA   = MTLBlendFactorZero; dA   = MTLBlendFactorOneMinusSourceAlpha; break;
        case CM_OPERATOR_DEST_ATOP:
            sRGB = MTLBlendFactorOneMinusDestinationAlpha; dRGB = MTLBlendFactorSourceAlpha;
            sA   = MTLBlendFactorOneMinusDestinationAlpha; dA   = MTLBlendFactorSourceAlpha; break;
        case CM_OPERATOR_XOR:
            sRGB = MTLBlendFactorOneMinusDestinationAlpha; dRGB = MTLBlendFactorOneMinusSourceAlpha;
            sA   = MTLBlendFactorOneMinusDestinationAlpha; dA   = MTLBlendFactorOneMinusSourceAlpha; break;
        case CM_OPERATOR_ADD:
            sRGB = MTLBlendFactorOne;  dRGB = MTLBlendFactorOne;
            sA   = MTLBlendFactorOne;  dA   = MTLBlendFactorOne; break;
        case CM_OPERATOR_SATURATE:
            /* cairo SATURATE: src coverage clamped by remaining dst space.  The
             * closest fixed-function form weights src by SourceAlphaSaturated. */
            sRGB = MTLBlendFactorSourceAlphaSaturated; dRGB = MTLBlendFactorOne;
            sA   = MTLBlendFactorOne;                  dA   = MTLBlendFactorOne; break;
        default:
            /* 14..28 separable / non-separable blend modes: OVER fallback until
             * the framebuffer-fetch fragment lands.  Keep the OVER defaults. */
            fixed = false; break;
    }

    ca.sourceRGBBlendFactor        = sRGB;
    ca.destinationRGBBlendFactor   = dRGB;
    ca.sourceAlphaBlendFactor      = sA;
    ca.destinationAlphaBlendFactor = dA;
    ca.writeMask                   = MTLColorWriteMaskAll;
    return fixed;
}

/*
 * Build one cover-pipeline VARIANT.  `kind` chooses the fragment family; `op`
 * chooses the blend; `aa_none` selects sampleCount 1 (no MSAA); `clip` is carried
 * for key completeness (the clip multiply is a fragment/sampler concern wired in
 * cm_compose.m + cm_clip.m, not a distinct pipeline state today, so it does not
 * change the descriptor -- but a future clip-discard variant keys off it here);
 * `a8` selects the R8 colour format for an A8 target.
 *
 * Returns a +0 (autoreleased) pipeline or nil; on nil *err carries the reason.
 */
static id<MTLRenderPipelineState>
cm_build_cover_variant(cm_device *dev, int kind, cm_operator_t op,
                       bool aa_none, bool clip, bool a8, NSError **err)
{
    NSString *vfn = nil, *ffn = nil;
    if (!cm_cover_shader_names(kind, op, a8, clip, &vfn, &ffn)) {
        if (err) *err = [NSError errorWithDomain:@"CairoMetal" code:2
                          userInfo:@{ NSLocalizedDescriptionKey:
                            @"no cover fragment for paint kind" }];
        return nil;
    }

    id<MTLFunction> vs = [dev->library newFunctionWithName:vfn];
    id<MTLFunction> fs = [dev->library newFunctionWithName:ffn];
    if (!vs || !fs) {
        if (err) *err = [NSError errorWithDomain:@"CairoMetal" code:1
                          userInfo:@{ NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:
                              @"missing shader function %@ / %@", vfn, ffn] }];
        return nil;
    }

    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction    = vs;
    pd.fragmentFunction  = fs;
    pd.rasterSampleCount = aa_none ? 1u : (NSUInteger)CM_MSAA_SAMPLE_COUNT;
    pd.colorAttachments[0].pixelFormat =
        a8 ? MTLPixelFormatR8Unorm : MTLPixelFormatBGRA8Unorm;
    /* Only the programmable-blend FRAGMENTS (cm_fs_blend_*) composite OVER
     * internally and need the opaque pass-through state.  The MASK pseudo-kind
     * keeps the plain cm_fs_mask fragment even under a blend op, so it must retain
     * the operator's fixed-function blend STATE -- exclude it here. */
    if (cm_op_is_blend(op) && !a8 && kind != CM_CV_PAINT_MASK) {
        /* Programmable-blend (PDF/SVG) operators 14..28: the cm_fs_blend_*
         * fragment reads the destination via [[color(0)]] and composites the
         * full Porter-Duff "B(cb,cs) over" result in-shader, so the value it
         * returns IS the final pixel.  The colour attachment must therefore be
         * OPAQUE pass-through (src=One, dst=Zero, blending OFF) -- a hardware
         * OVER blend here would double-composite over the dest.  (An A8 target
         * never takes a blend op: it routes to the solid-coverage write above.) */
        MTLRenderPipelineColorAttachmentDescriptor *ca = pd.colorAttachments[0];
        ca.blendingEnabled             = NO;
        ca.sourceRGBBlendFactor        = MTLBlendFactorOne;
        ca.sourceAlphaBlendFactor      = MTLBlendFactorOne;
        ca.destinationRGBBlendFactor   = MTLBlendFactorZero;
        ca.destinationAlphaBlendFactor = MTLBlendFactorZero;
        ca.writeMask                   = MTLColorWriteMaskAll;
    } else {
        cm_configure_blend_for_operator(pd.colorAttachments[0], op);
    }
    pd.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;

    return [dev->mtl newRenderPipelineStateWithDescriptor:pd error:err];
}

/* Index of the cover-variant cell that corresponds to a SHIPPING pipeline: the
 * OVER operator, MSAA on, clip off, BGRA8 colour.  Pre-warming these cells makes
 * cm_device_cover_pipeline return the byte-for-byte shipping object for the
 * common path (rather than compiling a duplicate on first use), so the variant
 * table is a strict SUPERSET that never regresses the shipping states. */
static void cm_prewarm_shipping_variants(cm_device *dev)
{
    const int aa = 0, clip = 0, a8 = 0;   /* MSAA, no-clip, BGRA8 */
    dev->cover_variants[CM_PAINT_SOLID ][CM_OPERATOR_OVER][aa][clip][a8] =
        dev->pipelines[CM_PIPE_COVER_SOLID];
    dev->cover_variants[CM_PAINT_LINEAR][CM_OPERATOR_OVER][aa][clip][a8] =
        dev->pipelines[CM_PIPE_COVER_LINEAR];
}

static bool cm_build_all_pipelines(cm_device *dev, cm_status_t *out)
{
    NSError *err = nil;

    dev->pipelines[CM_PIPE_STENCIL_NONZERO] =
        cm_build_pipeline(dev, @"cm_vs_stencil", @"cm_fs_stencil", false, &err);
    dev->pipelines[CM_PIPE_STENCIL_EVENODD] =
        cm_build_pipeline(dev, @"cm_vs_stencil", @"cm_fs_stencil", false, &err);
    dev->pipelines[CM_PIPE_COVER_SOLID] =
        cm_build_pipeline(dev, @"cm_vs_cover", @"cm_fs_cover_solid", true, &err);
    dev->pipelines[CM_PIPE_COVER_LINEAR] =
        cm_build_pipeline(dev, @"cm_vs_cover", @"cm_fs_cover_linear", true, &err);

    /* The four SHIPPING pipelines are REQUIRED at create time (kept byte-for-byte
     * via cm_build_pipeline).  Validate only [0, CM_PIPE_COVER_LINEAR] -- the rest
     * of the CM_PIPE_* enum (RADIAL/SURFACE/GOURAUD/MASK/SOLID_A8) are the OLD
     * fixed slots; we no longer populate pipelines[] for them (the variant table
     * owns every non-shipping cover pipeline now), so an unbuilt slot there is not
     * an error and cm_device_pipeline simply returns NULL for it. */
    for (int i = 0; i <= CM_PIPE_COVER_LINEAR; ++i) {
        if (!dev->pipelines[i]) {
            NSLog(@"CairoMetal: pipeline %d build failed: %@", i, err);
            if (out) *out = CM_STATUS_DEVICE_ERROR;
            return false;
        }
    }

    /* Single-sample stencil pipelines for the ANTIALIAS_NONE 1-sample pass.  Both
     * the nonzero and even-odd variants share cm_vs_stencil/cm_fs_stencil (the rule
     * lives in the depth-stencil state), so they are the same pipeline object built
     * once; stored at both indices for symmetry with the MSAA pair.  Best-effort:
     * a nil here just makes the AA-none fast path unavailable (the encode falls back
     * to the MSAA frame), never an error. */
    {
        NSError *serr = nil;
        id<MTLRenderPipelineState> s1 = cm_build_stencil_aa_none(dev, &serr);
        if (s1) {
            dev->stencil_aa_none[0] = s1;
            dev->stencil_aa_none[1] = s1;
        } else {
            NSLog(@"CairoMetal: single-sample stencil pipeline not built "
                  @"(ANTIALIAS_NONE will use MSAA): %@", serr);
        }
    }

    /* Build the REMAINING shipping cover fragments (radial / surface / gouraud /
     * mask / A8) eagerly so the metallib's full entry-point set is validated at
     * create time and the common (OVER, MSAA, no-clip) cells are warm.  These are
     * best-effort: a metallib that is missing an appended fragment must not abort
     * device creation (the shipping four already passed), so a nil here is logged
     * and left for a lazy retry.  Each is parked in its natural variant cell. */
    {
        const int aa = 0, clip = 0;
        struct { cm_paint_kind kind; bool a8; } warm[] = {
            { CM_PAINT_RADIAL,  false },
            { CM_PAINT_SURFACE, false },
            { CM_PAINT_MESH,    false },
            { CM_PAINT_SOLID,   true  },   /* CM_PIPE_COVER_SOLID_A8 */
        };
        for (size_t w = 0; w < sizeof(warm) / sizeof(warm[0]); ++w) {
            NSError *werr = nil;
            id<MTLRenderPipelineState> ps =
                cm_build_cover_variant(dev, warm[w].kind, CM_OPERATOR_OVER,
                                       aa != 0, clip != 0, warm[w].a8, &werr);
            if (ps) {
                dev->cover_variants[warm[w].kind][CM_OPERATOR_OVER][aa][clip][warm[w].a8 ? 1 : 0] = ps;
            } else {
                NSLog(@"CairoMetal: optional cover variant (kind=%d a8=%d) not "
                      @"built: %@", (int)warm[w].kind, (int)warm[w].a8, werr);
            }
        }
    }

    cm_prewarm_shipping_variants(dev);
    return true;
}

/* ==========================================================================
 * Depth-stencil-state construction (built once)
 * ========================================================================== */

static id<MTLDepthStencilState>
cm_build_dss_stencil_nonzero(cm_device *dev)
{
    /* Two-sided incr/decr-wrap, compare Always, no color (handled by pipeline).
     * Front/back assignment is sign-agnostic: the cover test is NotEqual(0). */
    MTLStencilDescriptor *front = [[MTLStencilDescriptor alloc] init];
    front.stencilCompareFunction    = MTLCompareFunctionAlways;
    front.stencilFailureOperation   = MTLStencilOperationKeep;
    front.depthFailureOperation     = MTLStencilOperationKeep;
    front.depthStencilPassOperation = MTLStencilOperationIncrementWrap;
    front.readMask  = 0xFF;
    front.writeMask = 0xFF;

    MTLStencilDescriptor *back = [[MTLStencilDescriptor alloc] init];
    back.stencilCompareFunction    = MTLCompareFunctionAlways;
    back.stencilFailureOperation   = MTLStencilOperationKeep;
    back.depthFailureOperation     = MTLStencilOperationKeep;
    back.depthStencilPassOperation = MTLStencilOperationDecrementWrap;
    back.readMask  = 0xFF;
    back.writeMask = 0xFF;

    MTLDepthStencilDescriptor *dsd = [[MTLDepthStencilDescriptor alloc] init];
    dsd.depthCompareFunction = MTLCompareFunctionAlways;
    dsd.depthWriteEnabled    = NO;
    dsd.frontFaceStencil     = front;
    dsd.backFaceStencil      = back;
    return [dev->mtl newDepthStencilStateWithDescriptor:dsd];
}

static id<MTLDepthStencilState>
cm_build_dss_stencil_evenodd(cm_device *dev)
{
    /* Invert the low bit on every covered sample (parity), both faces. */
    MTLStencilDescriptor *s = [[MTLStencilDescriptor alloc] init];
    s.stencilCompareFunction    = MTLCompareFunctionAlways;
    s.stencilFailureOperation   = MTLStencilOperationKeep;
    s.depthFailureOperation     = MTLStencilOperationKeep;
    s.depthStencilPassOperation = MTLStencilOperationInvert;
    s.readMask  = 0xFF;
    s.writeMask = 0xFF;

    MTLDepthStencilDescriptor *dsd = [[MTLDepthStencilDescriptor alloc] init];
    dsd.depthCompareFunction = MTLCompareFunctionAlways;
    dsd.depthWriteEnabled    = NO;
    dsd.frontFaceStencil     = s;
    dsd.backFaceStencil      = s;
    return [dev->mtl newDepthStencilStateWithDescriptor:dsd];
}

/* Cover test: pass where stencil != ref(0), and on pass ZERO the touched
 * samples so the buffer is clean for the next batched path (no per-path clear).
 * readMask selects nonzero (0xFF) vs even-odd parity (0x01). */
static id<MTLDepthStencilState>
cm_build_dss_cover(cm_device *dev, uint32_t read_mask)
{
    MTLStencilDescriptor *s = [[MTLStencilDescriptor alloc] init];
    s.stencilCompareFunction    = MTLCompareFunctionNotEqual;  /* != ref(0) */
    s.stencilFailureOperation   = MTLStencilOperationKeep;
    s.depthFailureOperation     = MTLStencilOperationKeep;
    s.depthStencilPassOperation = MTLStencilOperationZero;     /* reset to 0 */
    s.readMask  = read_mask;
    s.writeMask = 0xFF;

    MTLDepthStencilDescriptor *dsd = [[MTLDepthStencilDescriptor alloc] init];
    dsd.depthCompareFunction = MTLCompareFunctionAlways;
    dsd.depthWriteEnabled    = NO;
    dsd.frontFaceStencil     = s;
    dsd.backFaceStencil      = s;
    return [dev->mtl newDepthStencilStateWithDescriptor:dsd];
}

static bool cm_build_all_dss(cm_device *dev, cm_status_t *out)
{
    dev->dss[CM_DSS_STENCIL_WRITE_NONZERO] = cm_build_dss_stencil_nonzero(dev);
    dev->dss[CM_DSS_STENCIL_WRITE_EVENODD] = cm_build_dss_stencil_evenodd(dev);
    dev->dss[CM_DSS_COVER_TEST_NONZERO]    = cm_build_dss_cover(dev, 0xFF);
    dev->dss[CM_DSS_COVER_TEST_EVENODD]    = cm_build_dss_cover(dev, 0x01);

    for (int i = 0; i < CM_DSS_COUNT; ++i) {
        if (!dev->dss[i]) {
            if (out) *out = CM_STATUS_DEVICE_ERROR;
            return false;
        }
    }
    return true;
}

/* ==========================================================================
 * Triple-buffered ring construction (built once)
 * ========================================================================== */
static bool cm_build_ring(cm_device *dev, cm_status_t *out)
{
    for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i) {
        cm_frame *f = &dev->frames[i];
        /* dev was calloc'd, so the ARC __strong object fields (vbuf/ubuf/cmd/
         * enc) are already nil; do NOT memset over them (that would bypass ARC).
         * Initialize the POD fields explicitly. */
        f->dev     = dev;
        f->slot    = i;
        f->active  = false;
        f->in_flight = false;
        f->vbase   = NULL;
        f->ubase   = NULL;
        f->vcur    = 0;
        f->ucur    = 0;
        f->surface = NULL;

        f->vbuf = [dev->mtl newBufferWithLength:CM_VTX_RING_BYTES
                                        options:MTLResourceStorageModeShared];
        f->ubuf = [dev->mtl newBufferWithLength:CM_UNI_RING_BYTES
                                        options:MTLResourceStorageModeShared];
        if (!f->vbuf || !f->ubuf) {
            if (out) *out = CM_STATUS_NO_MEMORY;
            return false;
        }
        f->vbase = (uint8_t *)f->vbuf.contents;
        f->ubase = (uint8_t *)f->ubuf.contents;
        f->vcur = f->ucur = 0;
    }
    return true;
}

/* ==========================================================================
 * Create / destroy
 * ========================================================================== */
cm_device *cm_device_create(cm_status_t *out_status)
{
    if (out_status) *out_status = CM_STATUS_SUCCESS;

    @autoreleasepool {
        id<MTLDevice> mtl = MTLCreateSystemDefaultDevice();
        if (!mtl) {
            if (out_status) *out_status = CM_STATUS_NO_METAL_DEVICE;
            return NULL;
        }

        cm_device *dev = (cm_device *)calloc(1, sizeof(*dev));
        if (!dev) {
            if (out_status) *out_status = CM_STATUS_NO_MEMORY;
            return NULL;
        }

        /* Guards the lazy variant/sampler caches (process-shared device).  Init it
         * FIRST so every cm_device_destroy early-out below has a valid mutex to
         * destroy, and so cm_build_all_pipelines (which seeds variant cells) and
         * any concurrent first-surface lazy build are safe. */
        pthread_mutex_init(&dev->lazy_mtx, NULL);

        /* Runtime flatten tolerance defaults to the library tolerance; a consumer
         * may dial it via cm_device_set_tolerance for coarser/finer curves. */
        dev->flatten_tolerance = CM_FLATTEN_TOLERANCE;

        /* Retain the ObjC objects we stash in the malloc'd struct.  Under ARC a
         * struct field of object type is __strong, so direct assignment retains;
         * but to be explicit and avoid any ambiguity with C-struct storage we
         * assign through the strong-typed fields (ARC inserts the retain). */
        dev->mtl   = mtl;
        dev->queue = [mtl newCommandQueue];
        if (!dev->queue) {
            if (out_status) *out_status = CM_STATUS_DEVICE_ERROR;
            cm_device_destroy(dev);
            return NULL;
        }

        dev->library = cm_load_library(mtl);
        if (!dev->library) {
            NSLog(@"CairoMetal: no Metal library (set CM_METALLIB, add "
                  @"fill.metal to the app's Metal build phase, or ship "
                  @"shaders/fill.metal as a resource).");
            if (out_status) *out_status = CM_STATUS_DEVICE_ERROR;
            cm_device_destroy(dev);
            return NULL;
        }

        cm_status_t st = CM_STATUS_SUCCESS;
        if (!cm_build_all_pipelines(dev, &st) ||
            !cm_build_all_dss(dev, &st) ||
            !cm_build_ring(dev, &st)) {
            if (out_status) *out_status = st;
            cm_device_destroy(dev);
            return NULL;
        }

        dev->sem = dispatch_semaphore_create(CM_FRAMES_IN_FLIGHT);
        dev->frame_seq = 0;

        if (out_status) *out_status = CM_STATUS_SUCCESS;
        return dev;
    }
}

void cm_device_destroy(cm_device *dev)
{
    if (!dev) return;
    @autoreleasepool {
        /* Drain any in-flight frames so no completion handler touches freed
         * memory: acquire all permits, then release them. */
        if (dev->sem) {
            for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i)
                dispatch_semaphore_wait(dev->sem, DISPATCH_TIME_FOREVER);
            for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i)
                dispatch_semaphore_signal(dev->sem);
        }

        /* Release the cached gradient LUT textures owned by cm_paint.m, if that
         * module is linked (weak so a build without it still links). */
        extern void cm_paint_cache_shutdown(void) __attribute__((weak));
        if (cm_paint_cache_shutdown) cm_paint_cache_shutdown();

        /* ARC releases the __strong object fields when we nil them. */
        for (int i = 0; i < CM_PIPE_COUNT; ++i) dev->pipelines[i] = nil;
        for (int i = 0; i < CM_DSS_COUNT;  ++i) dev->dss[i]       = nil;
        dev->stencil_aa_none[0] = nil;
        dev->stencil_aa_none[1] = nil;

        /* Lazy cover-variant table.  Some cells alias a shipping pipelines[] object
         * (pre-warm) which we already nil'd above; niling the cell here just drops
         * this strong reference (ARC ref-counts, so the alias is fine). */
        for (int k = 0; k < CM_CV_PAINT_KINDS; ++k)
         for (int o = 0; o < CM_CV_OPS; ++o)
          for (int a = 0; a < CM_CV_AA; ++a)
           for (int c = 0; c < CM_CV_CLIP; ++c)
            for (int e = 0; e < CM_CV_A8; ++e)
                dev->cover_variants[k][o][a][c][e] = nil;

        /* Lazy sampler cache. */
        for (int fi = 0; fi < CM_SAMP_FILTERS; ++fi)
            for (int ei = 0; ei < CM_SAMP_EXTENDS; ++ei)
                dev->samplers[fi][ei] = nil;

        for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i) {
            dev->frames[i].vbuf    = nil;
            dev->frames[i].ubuf    = nil;
            dev->frames[i].cmd     = nil;
            dev->frames[i].enc     = nil;
            dev->frames[i].surface = NULL;
        }
        dev->library = nil;
        dev->queue   = nil;
        dev->mtl     = nil;
        dev->sem     = nil;
    }
    pthread_mutex_destroy(&dev->lazy_mtx);
    free(dev);
}

/* ==========================================================================
 * Persistent-state + handle accessors (O(1), no allocation)
 * ========================================================================== */
void *cm_device_pipeline(cm_device *dev, cm_pipe_id id)
{
    if (!dev || id < 0 || id >= CM_PIPE_COUNT) return NULL;
    return (__bridge void *)dev->pipelines[id];
}

void *cm_device_depthstencil(cm_device *dev, cm_dss_id id)
{
    if (!dev || id < 0 || id >= CM_DSS_COUNT) return NULL;
    return (__bridge void *)dev->dss[id];
}

void *cm_device_mtl(cm_device *dev)
{
    return dev ? (__bridge void *)dev->mtl : NULL;
}

/* ==========================================================================
 * Cover-pipeline VARIANT selector  (lazy table; the SINGLE pipeline front door)
 * --------------------------------------------------------------------------
 * Returns the cover MTLRenderPipelineState for (operator, aa-none, clip-on,
 * paint_kind), building + caching it on first use.  cm_compose.m routes every
 * encode site (fill/stroke/paint/mask) through cm_compose_operator_pipeline,
 * which calls straight into here, so the whole library selects pipelines through
 * ONE table.
 *
 * Notes on the key:
 *   - operator    : clamped to the cairo range; 0..13 bake a fixed-function
 *                   blend, 14..28 an OVER fallback (see cm_configure_blend_*).
 *   - aa_none     : true => sampleCount 1 (ANTIALIAS_NONE); false => 4x MSAA.
 *   - clip        : carried for cache identity (a future clip-discard variant
 *                   keys off it); does not change the descriptor today.
 *   - paint_kind  : selects the fragment family; an out-of-range kind falls back
 *                   to SOLID so a bogus key can never miss the table.
 *   - A8 target   : NOT part of this signature; the BGRA8/565 colour variant is
 *                   returned here, and the dedicated A8 (R8) cover pipeline is
 *                   reached via cm_device_cover_pipeline_a8() below (the encode
 *                   path picks it when the target is A8).  This keeps the public
 *                   selector signature byte-for-byte with the contract.
 * ========================================================================== */

/* Shared core: build/fetch the cover variant for a fully-resolved key (including
 * the A8 colour-format bit).  Caches under dev->lazy_mtx. */
static id<MTLRenderPipelineState>
cm_cover_variant_locked(cm_device *dev, int kind, cm_operator_t op,
                        bool aa_none, bool clip, bool a8)
{
    /* Normalise the key into the table's bounds.  `kind` may be the CM_CV_PAINT_MASK
     * pseudo-kind (past CM_PAINT_MESH), which is in-bounds now (CM_CV_PAINT_KINDS). */
    if (kind < 0 || kind >= CM_CV_PAINT_KINDS) kind = CM_PAINT_SOLID;
    if ((int)op   < 0 || (int)op   >= CM_CV_OPS)          op   = CM_OPERATOR_OVER;
    int ai = aa_none ? 1 : 0;
    int ci = clip    ? 1 : 0;
    int ei = a8      ? 1 : 0;

    id<MTLRenderPipelineState> ps = dev->cover_variants[kind][op][ai][ci][ei];
    if (ps) return ps;

    /* Build into the cache cell INSIDE a pool: assigning to the __strong struct
     * field retains the pipeline, so it survives the pool drain that releases the
     * transient descriptor / NSString / NSError this build autoreleases.  (This
     * lazy path can run from a draw with no enclosing pool, unlike the eager
     * cm_build_all_pipelines which is wrapped by cm_device_create's pool.) */
    bool built = false;
    @autoreleasepool {
        NSError *err = nil;
        id<MTLRenderPipelineState> made =
            cm_build_cover_variant(dev, kind, op, aa_none, clip, a8, &err);
        if (made) {
            dev->cover_variants[kind][op][ai][ci][ei] = made;
            built = true;
        } else {
            NSLog(@"CairoMetal: cover variant (kind=%d op=%d aa_none=%d clip=%d "
                  @"a8=%d) build failed: %@", (int)kind, (int)op, (int)aa_none,
                  (int)clip, (int)a8, err);
        }
    }
    if (built) return dev->cover_variants[kind][op][ai][ci][ei];

    /* The requested (kind,op,...) failed to compile (e.g. a metallib missing an
     * appended fragment, or an unsupported blend on this GPU).  Degrade to the
     * always-built SOLID/OVER/MSAA/no-clip/BGRA cell so the caller still gets a
     * usable pipeline rather than nil (which would drop the draw).  That cell is
     * guaranteed live (built eagerly in cm_build_all_pipelines).
     *
     * BUT only for a BGRA8/565 (non-A8) request: substituting a BGRA8 pipeline
     * into an A8 (R8) render pass would MISMATCH the colour format and Metal
     * would reject the draw, so an A8 failure returns nil and the caller decides
     * (e.g. skip the clip-mask write) rather than crash. */
    if (a8) return nil;

    ps = dev->cover_variants[CM_PAINT_SOLID][CM_OPERATOR_OVER][0][0][0];
    /* Memoise the (format-compatible) fallback in the requested cell so we don't
     * retry the failed compile on every draw (idempotent + cheap). */
    dev->cover_variants[kind][op][ai][ci][ei] = ps;
    return ps;
}

void *cm_device_cover_pipeline(cm_device *dev, cm_operator_t op,
                               bool aa_none, bool clip, cm_paint_kind paint_kind)
{
    if (!dev) return NULL;
    pthread_mutex_lock(&dev->lazy_mtx);
    id<MTLRenderPipelineState> ps =
        cm_cover_variant_locked(dev, paint_kind, op, aa_none, clip, /*a8=*/false);
    pthread_mutex_unlock(&dev->lazy_mtx);
    return (__bridge void *)ps;
}

/* A8-target cover variant: the R8 colour-format pipeline an A8 render target
 * needs (the BGRA8 cover pipeline would mismatch the render pass).  cm_clip.m /
 * an A8 group target select this; the fragment is the solid-coverage write whose
 * premultiplied output drives the single R8 alpha channel.  Keyed the same way
 * as the colour selector but with the A8 bit set. */
void *cm_device_cover_pipeline_a8(cm_device *dev, cm_operator_t op,
                                  bool aa_none, bool clip, cm_paint_kind paint_kind)
{
    if (!dev) return NULL;
    pthread_mutex_lock(&dev->lazy_mtx);
    id<MTLRenderPipelineState> ps =
        cm_cover_variant_locked(dev, paint_kind, op, aa_none, clip, /*a8=*/true);
    pthread_mutex_unlock(&dev->lazy_mtx);
    return (__bridge void *)ps;
}

/* Mask cover variant: the source*mask-alpha fragment (cm_fs_mask) cairo_mask() /
 * cairo_mask_surface() need.  It is its own fragment family (NOT a cm_paint_kind
 * source kind), so it lives in the CM_CV_PAINT_MASK pseudo-kind row of the variant
 * table.  Keyed by the operator (its fixed-function blend STATE is honoured) + aa
 * + clip, BGRA8 colour.  cm_compose.m selects this for the mask cover draw so the
 * mask modulates the CURRENT SOURCE COLOUR by coverage instead of being sampled as
 * the colour itself (the surface-cover fragment's behaviour). */
void *cm_device_cover_pipeline_mask(cm_device *dev, cm_operator_t op,
                                    bool aa_none, bool clip)
{
    if (!dev) return NULL;
    pthread_mutex_lock(&dev->lazy_mtx);
    id<MTLRenderPipelineState> ps =
        cm_cover_variant_locked(dev, CM_CV_PAINT_MASK, op, aa_none, clip, /*a8=*/false);
    pthread_mutex_unlock(&dev->lazy_mtx);
    return (__bridge void *)ps;
}

/* ==========================================================================
 * Lazy 6x4 MTLSamplerState cache  (cm_device_sampler)
 * --------------------------------------------------------------------------
 * constexpr samplers in fill.metal cannot encode a runtime filter/extend, so the
 * SURFACE / MASK cover fragments (which take a sampler(0)) bind one of these.  We
 * build each (filter, extend) cell on first use and reuse it forever.  The
 * shipping solid/linear path uses the shader's constexpr sampler and never calls
 * this, so the table stays empty unless a surface/mask source is drawn.
 * ========================================================================== */

/* cairo filter -> Metal min/mag filter.  NEAREST/FAST map to nearest; everything
 * else (GOOD/BEST/BILINEAR/GAUSSIAN) maps to linear (we do not implement a
 * separable Gaussian; linear is the cairo-compatible "good" default). */
static MTLSamplerMinMagFilter cm_mtl_minmag_filter(cm_filter_t f)
{
    switch (f) {
        case CM_FILTER_FAST:
        case CM_FILTER_NEAREST: return MTLSamplerMinMagFilterNearest;
        case CM_FILTER_GOOD:
        case CM_FILTER_BEST:
        case CM_FILTER_BILINEAR:
        case CM_FILTER_GAUSSIAN:
        default:                return MTLSamplerMinMagFilterLinear;
    }
}

/* cairo extend -> Metal address mode.  NONE has no exact fixed-function analogue
 * (cairo paints a transparent border); clamp-to-zero is the closest mode that
 * yields transparent outside the source, matching the conservative PAD-vs-NONE
 * note in cm_paint.m. */
static MTLSamplerAddressMode cm_mtl_address_mode(cm_extend_t e)
{
    switch (e) {
        case CM_EXTEND_REPEAT:  return MTLSamplerAddressModeRepeat;
        case CM_EXTEND_REFLECT: return MTLSamplerAddressModeMirrorRepeat;
        case CM_EXTEND_PAD:     return MTLSamplerAddressModeClampToEdge;
        case CM_EXTEND_NONE:
        default:                return MTLSamplerAddressModeClampToZero;
    }
}

void *cm_device_sampler(cm_device *dev, cm_filter_t filter, cm_extend_t extend)
{
    if (!dev) return NULL;

    /* Clamp the key into the 6x4 table; an out-of-range enum can never index OOB. */
    int fi = (int)filter;
    int ei = (int)extend;
    if (fi < 0 || fi >= CM_SAMP_FILTERS) fi = (int)CM_FILTER_GOOD;
    if (ei < 0 || ei >= CM_SAMP_EXTENDS) ei = (int)CM_EXTEND_NONE;

    pthread_mutex_lock(&dev->lazy_mtx);
    id<MTLSamplerState> s = dev->samplers[fi][ei];
    if (!s) {
        @autoreleasepool {
            MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
            sd.minFilter    = cm_mtl_minmag_filter((cm_filter_t)fi);
            sd.magFilter    = cm_mtl_minmag_filter((cm_filter_t)fi);
            sd.mipFilter    = MTLSamplerMipFilterNotMipmapped;
            sd.sAddressMode = cm_mtl_address_mode((cm_extend_t)ei);
            sd.tAddressMode = cm_mtl_address_mode((cm_extend_t)ei);
            sd.normalizedCoordinates = YES;
            s = [dev->mtl newSamplerStateWithDescriptor:sd];
        }
        dev->samplers[fi][ei] = s;   /* nil on failure -> retried next call */
    }
    pthread_mutex_unlock(&dev->lazy_mtx);
    return (__bridge void *)s;
}

/* ==========================================================================
 * Runtime flatten tolerance  (the tolerance seam)
 * --------------------------------------------------------------------------
 * cm_path_flatten / cm_stroke_expand bake curves to a device-pixel tolerance.
 * The contract froze cm_path_flatten's signature (no tolerance arg), so the
 * runtime tolerance lives on the device and is read THROUGH here by the encode
 * path -- the single place a consumer can thread a coarser/finer tolerance
 * without touching the frozen flatten signature.  Defaults to
 * CM_FLATTEN_TOLERANCE; values <= 0 reset to the default.  See the BUILD seam at
 * file end for how cm_path.m consumes it.
 * ========================================================================== */
void cm_device_set_tolerance(cm_device *dev, double tolerance)
{
    if (!dev) return;
    dev->flatten_tolerance = (tolerance > 0.0) ? tolerance : CM_FLATTEN_TOLERANCE;
}

double cm_device_tolerance(cm_device *dev)
{
    if (!dev) return CM_FLATTEN_TOLERANCE;
    double t = dev->flatten_tolerance;
    return (t > 0.0) ? t : CM_FLATTEN_TOLERANCE;
}

/* GPU-toggle confirmation: the system Metal device's name (e.g. "Apple M5 GPU"
 * / "Apple A17 Pro GPU"). Returns "" when no Metal device exists. Because this
 * name comes straight from a live MTLDevice, a non-empty result is a reliable
 * "the GPU path is really active" signal for the manim toggle. */
const char *cm_metal_device_name(void)
{
    static char buf[256];
    buf[0] = '\0';
    @autoreleasepool {
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        if (d && d.name) {
            [d.name getCString:buf maxLength:sizeof(buf)
                      encoding:NSUTF8StringEncoding];
        }
    }
    return buf;
}

/* Strongly-typed variants used by cm_surface.m (declared extern there). */
id<MTLDevice> cm_device_mtl_id(cm_device *dev)
{
    return dev ? dev->mtl : nil;
}

id<MTLCommandQueue> cm_device_queue_id(cm_device *dev)
{
    return dev ? dev->queue : nil;
}

/* ==========================================================================
 * Frame lifecycle
 * ==========================================================================
 *
 * cm_frame_begin builds the ONE command buffer + render command encoder for the
 * whole frame and binds the surface's attachments:
 *
 *   - The colour / MSAA / stencil textures come from the surface's OWN accessors
 *     for an image or offscreen-group target, but from surface->parent for a
 *     SUBSURFACE (which owns no GPU memory -- see cm_surface_similar.c seam #1).
 *     The attachments are already in the surface's CONCRETE pixel format (BGRA8 /
 *     R8 / B5G6R5), built from s->format by cm_surface.m, so reading them back is
 *     format-correct; the pipeline the encode path binds must carry the matching
 *     colour format (the variant table's A8 bit handles the R8 case).
 *
 *   - The MSAA samples RESOLVE at store into the single-sample colour texture.
 *     For a normal image surface that texture is IOSurface-backed (zero-copy to
 *     VideoToolbox); for an OFFSCREEN GROUP target it is a PRIVATE MTLTexture
 *     (no IOSurface) -- the resolve still happens, it just lands in private GPU
 *     memory that is sampled back as a SurfacePattern, never handed to the
 *     encoder.  Both are the same code path here (we resolve into whatever
 *     cm_surface_color_texture returns).
 *
 *   - dev_off_x/y + sub_rect are applied as a SCISSOR rect so drawing into a
 *     subsurface (or a device-offset surface) is confined to its window of the
 *     backing, clamped to the backing's bounds.
 * ========================================================================== */

/* Resolve which surface actually OWNS the GPU textures for `surface`: a
 * subsurface borrows its (already-flattened) parent's backing; everyone else is
 * its own backing.  cm_surface_similar.c guarantees ->parent points at a real
 * IOSurface-/private-backed root for a subsurface. */
static cm_surface_t *cm_frame_backing_surface(cm_surface_t *surface)
{
    if (surface->kind == CM_SURFACE_TYPE_SUBSURFACE && surface->parent)
        return surface->parent;
    return surface;
}

/* Compute the device-space scissor rect for `surface` against its `backing`
 * texture, from the surface's device offset + (for a subsurface) sub-rect, then
 * clamp to [0, backing_w] x [0, backing_h].  Returns false if the clamped rect is
 * empty (nothing to draw).  Metal requires x+width <= texture width (and same for
 * height), so the clamp is mandatory, not cosmetic. */
static bool cm_frame_scissor_rect(cm_surface_t *surface,
                                  NSUInteger backing_w, NSUInteger backing_h,
                                  MTLScissorRect *out)
{
    double ox = surface->dev_off_x;
    double oy = surface->dev_off_y;

    /* The window the surface occupies in the backing.  A subsurface records its
     * absolute window in sub_rect (== dev_off + own w/h); a plain surface covers
     * its own w/h shifted by any device offset. */
    double rx, ry, rw, rh;
    if (surface->kind == CM_SURFACE_TYPE_SUBSURFACE) {
        rx = surface->sub_rect.x;
        ry = surface->sub_rect.y;
        rw = surface->sub_rect.width;
        rh = surface->sub_rect.height;
    } else {
        rx = ox;
        ry = oy;
        rw = (double)surface->width;
        rh = (double)surface->height;
    }

    /* Clamp the rect to the backing bounds (drop any portion outside it). */
    double x1 = rx, y1 = ry, x2 = rx + rw, y2 = ry + rh;
    if (x1 < 0.0) x1 = 0.0;
    if (y1 < 0.0) y1 = 0.0;
    if (x2 > (double)backing_w) x2 = (double)backing_w;
    if (y2 > (double)backing_h) y2 = (double)backing_h;
    if (!(x2 > x1) || !(y2 > y1)) return false;

    out->x      = (NSUInteger)x1;
    out->y      = (NSUInteger)y1;
    out->width  = (NSUInteger)(x2 - x1);
    out->height = (NSUInteger)(y2 - y1);
    return true;
}

cm_frame *cm_frame_begin(cm_surface_t *surface)
{
    if (!surface || !surface->dev) return NULL;
    cm_device *dev = surface->dev;

    /* Gate on the ring depth: block until a slot the GPU has finished with is
     * available, so we never overwrite a buffer still being read. */
    dispatch_semaphore_wait(dev->sem, DISPATCH_TIME_FOREVER);

    /* Pick a slot that is neither mid-encode (active) nor still being read by the
     * GPU (in_flight).  Do NOT key the slot purely off frame_seq % N: a per-surface
     * frame can stay OPEN (active, never flushed) across many OTHER surfaces'
     * frames -- e.g. blitting a series of SurfacePatterns into one reused
     * destination context, where the dst frame is begun once and only ends at
     * flush/destroy.  frame_seq would then eventually wrap back onto that
     * still-active slot and (under the old hard `if (f->active)` guard) fail with
     * DEVICE_ERROR.  The semaphore we just acquired guarantees at least one slot
     * is free here (a frame holds a permit from begin until its completion handler,
     * i.e. exactly while active||in_flight), so scan for it.  frame_seq is kept
     * only as a rotating start offset so independent sequential frames still cycle
     * through the ring (preserving the triple-buffering behaviour). */
    cm_frame *f = NULL;
    for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i) {
        int slot = (int)((dev->frame_seq + (uint64_t)i) % CM_FRAMES_IN_FLIGHT);
        cm_frame *cand = &dev->frames[slot];
        if (!cand->active && !cand->in_flight) { f = cand; break; }
    }
    dev->frame_seq++;

    /* Unreachable while the semaphore invariant holds, but never proceed onto a
     * busy slot: return the permit and report the error rather than corrupt a
     * slice the GPU is still reading. */
    if (!f) {
        dispatch_semaphore_signal(dev->sem);
        surface->status = CM_STATUS_DEVICE_ERROR;
        return NULL;
    }

    @autoreleasepool {
        /* A subsurface owns no textures: bind its parent's backing (resolved to a
         * real IOSurface-/private-backed root by cm_surface_similar.c). */
        cm_surface_t *backing = cm_frame_backing_surface(surface);

        /* Read the backing's CONCRETE pixel format (MSAA colour format).  The
         * attachment textures were built from this by cm_surface.m; a format that
         * has no MTLPixelFormat (A1 sub-byte / RGB30) is not GPU-renderable, so
         * reject it here with the cairo-exact status rather than binding a texture
         * that cannot exist. */
        if (cm_format_mtl_pixelfmt(backing->format) == 0 /* MTLPixelFormatInvalid */) {
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_SURFACE_TYPE_MISMATCH;
            return NULL;
        }

        id<MTLTexture> msaa    = (__bridge id<MTLTexture>)cm_surface_msaa_color_tex(backing);
        id<MTLTexture> resolve = (__bridge id<MTLTexture>)cm_surface_color_texture(backing);
        id<MTLTexture> stencil = (__bridge id<MTLTexture>)cm_surface_stencil_tex(backing);
        if (!msaa || !resolve || !stencil) {
            /* No GPU backing (A1 CPU-only, recording, finished, or an unresolved
             * subsurface): drawing is not representable on the GPU here. */
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_SURFACE_TYPE_MISMATCH;
            return NULL;
        }

        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        /* Colour: clear to transparent, render MSAA in the surface's concrete
         * format, RESOLVE into the single-sample texture at store.  That texture
         * is IOSurface-backed for a normal surface (zero-copy) and a PRIVATE
         * texture for an offscreen group target (no IOSurface, no resolve-to-
         * IOSurface) -- same store action, different storage. */
        rp.colorAttachments[0].texture        = msaa;
        rp.colorAttachments[0].resolveTexture = resolve;
        rp.colorAttachments[0].loadAction     = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction    = MTLStoreActionMultisampleResolve;
        rp.colorAttachments[0].clearColor     = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        /* Stencil: clear to 0; samples are transient (memoryless), DontCare. */
        rp.stencilAttachment.texture     = stencil;
        rp.stencilAttachment.loadAction  = MTLLoadActionClear;
        rp.stencilAttachment.storeAction = MTLStoreActionDontCare;
        rp.stencilAttachment.clearStencil = 0;

        id<MTLCommandBuffer> cmd = [dev->queue commandBuffer];
        id<MTLRenderCommandEncoder> enc =
            [cmd renderCommandEncoderWithDescriptor:rp];
        if (!cmd || !enc) {
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_DEVICE_ERROR;
            return NULL;
        }

        /* Confine drawing to the surface's window of the backing (subsurface
         * sub-rect, or a device-offset surface).  When the window is the whole
         * backing this is a full-target scissor (a no-op clip).  An empty clamped
         * window means there is nothing on-screen to draw: leave the default
         * (full-attachment) scissor so the frame is still valid but the encode
         * path's geometry simply falls outside it.  resolve.width/height are the
         * single-sample backing dimensions (== msaa dimensions). */
        MTLScissorRect sc;
        if (cm_frame_scissor_rect(surface, resolve.width, resolve.height, &sc)) {
            [enc setScissorRect:sc];
        }

        f->cmd     = cmd;
        f->enc     = enc;
        f->surface = surface;
        f->vcur    = 0;
        f->ucur    = 0;
        f->active  = true;
        f->single_sample = false;       /* this is the MSAA path                 */
    }
    return f;
}

/* ==========================================================================
 * ANTIALIAS_NONE single-sample frame (BUG 7)
 * --------------------------------------------------------------------------
 * Open a 1-sample render pass that draws DIRECTLY into the surface's RESOLVED
 * colour texture (the IOSurface-backed single-sample texture), with loadAction
 * Load so it composites OVER whatever the surface already holds, and storeAction
 * Store so the result lands straight in the colour texture -- there is NO MSAA
 * attachment and NO resolve, so the rasterizer samples once per pixel and a fully
 * covered interior writes full coverage (opaque), while edges are a hard 0/1 step
 * (no sample averaging).  A fresh 1-sample stencil texture (memoryless) carries
 * the winding/parity for the stencil-then-cover passes.
 *
 * Only BGRA8 (ARGB32 / RGB24) targets take this path; an A8/565 AA-none fill is
 * rare and the caller keeps it on the MSAA path (this returns NULL for them so the
 * caller falls back).  Uses the same ring slot + semaphore protocol as
 * cm_frame_begin, so cm_frame_end commits + recycles it identically.
 * ========================================================================== */
cm_frame *cm_frame_begin_single(cm_surface_t *surface)
{
    if (!surface || !surface->dev) return NULL;
    cm_device *dev = surface->dev;

    /* Single-sample stencil pipeline must be available, else fall back. */
    if (!dev->stencil_aa_none[0]) return NULL;

    /* Only a BGRA8 (ARGB32/RGB24) colour target is supported by the 1-sample
     * stencil pipeline's colour format; reject others so the caller falls back to
     * the MSAA path rather than hitting a format mismatch. */
    cm_surface_t *backing = cm_frame_backing_surface(surface);
    if (cm_format_mtl_pixelfmt(backing->format) != 80 /* MTLPixelFormatBGRA8Unorm */)
        return NULL;

    /* Gate on the ring depth exactly like cm_frame_begin so we never overwrite a
     * slice the GPU is still reading. */
    dispatch_semaphore_wait(dev->sem, DISPATCH_TIME_FOREVER);

    cm_frame *f = NULL;
    for (int i = 0; i < CM_FRAMES_IN_FLIGHT; ++i) {
        int slot = (int)((dev->frame_seq + (uint64_t)i) % CM_FRAMES_IN_FLIGHT);
        cm_frame *cand = &dev->frames[slot];
        if (!cand->active && !cand->in_flight) { f = cand; break; }
    }
    dev->frame_seq++;
    if (!f) {
        dispatch_semaphore_signal(dev->sem);
        surface->status = CM_STATUS_DEVICE_ERROR;
        return NULL;
    }

    @autoreleasepool {
        id<MTLDevice> mtl = dev->mtl;
        id<MTLTexture> resolve = (__bridge id<MTLTexture>)cm_surface_color_texture(backing);
        if (!resolve) {
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_SURFACE_TYPE_MISMATCH;
            return NULL;
        }

        /* Fresh 1-sample stencil (transient, memoryless) sized to the backing. */
        MTLTextureDescriptor *sd =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8
                                                               width:resolve.width
                                                              height:resolve.height
                                                           mipmapped:NO];
        sd.textureType = MTLTextureType2D;          /* 1 sample */
        sd.usage       = MTLTextureUsageRenderTarget;
        sd.storageMode = MTLStorageModeMemoryless;
        id<MTLTexture> stencil = [mtl newTextureWithDescriptor:sd];
        if (!stencil) {
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_NO_MEMORY;
            return NULL;
        }

        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        /* Colour: LOAD the existing resolved pixels (composite over them), render
         * single-sample, STORE back into the same texture -- no resolve. */
        rp.colorAttachments[0].texture     = resolve;
        rp.colorAttachments[0].loadAction  = MTLLoadActionLoad;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.stencilAttachment.texture      = stencil;
        rp.stencilAttachment.loadAction   = MTLLoadActionClear;
        rp.stencilAttachment.storeAction  = MTLStoreActionDontCare;
        rp.stencilAttachment.clearStencil = 0;

        id<MTLCommandBuffer> cmd = [dev->queue commandBuffer];
        id<MTLRenderCommandEncoder> enc =
            [cmd renderCommandEncoderWithDescriptor:rp];
        if (!cmd || !enc) {
            dispatch_semaphore_signal(dev->sem);
            surface->status = CM_STATUS_DEVICE_ERROR;
            return NULL;
        }

        MTLScissorRect sc;
        if (cm_frame_scissor_rect(surface, resolve.width, resolve.height, &sc))
            [enc setScissorRect:sc];

        f->cmd     = cmd;
        f->enc     = enc;
        f->surface = surface;
        f->vcur    = 0;
        f->ucur    = 0;
        f->active  = true;
        f->single_sample = true;
    }
    return f;
}

bool cm_frame_is_single_sample(cm_frame *f)
{
    return (f && f->active) ? f->single_sample : false;
}

void *cm_device_stencil_pipeline_aa_none(cm_device *dev, bool evenodd)
{
    if (!dev) return NULL;
    return (__bridge void *)dev->stencil_aa_none[evenodd ? 1 : 0];
}

/* Internal bump-allocator shared by the vertex + uniform arenas. */
static void *cm_frame_alloc(cm_frame *f, uint8_t *base, id<MTLBuffer> buf,
                            size_t *cur, size_t cap, size_t bytes,
                            void **out_mtlbuffer, uint32_t *out_offset)
{
    if (!f || !f->active || bytes == 0 || !base || !buf) return NULL;
    size_t off = cm_align_up(*cur, CM_RING_ALIGN);
    if (off + bytes > cap) {
        /* Per-frame arena exhausted. */
        return NULL;
    }
    *cur = off + bytes;
    if (out_mtlbuffer) *out_mtlbuffer = (__bridge void *)buf;
    if (out_offset)    *out_offset    = (uint32_t)off;
    return base + off;
}

void *cm_frame_alloc_verts(cm_frame *f, size_t bytes,
                           void **out_mtlbuffer, uint32_t *out_offset)
{
    if (!f) return NULL;
    return cm_frame_alloc(f, f->vbase, f->vbuf, &f->vcur, CM_VTX_RING_BYTES,
                          bytes, out_mtlbuffer, out_offset);
}

void *cm_frame_alloc_uniforms(cm_frame *f, size_t bytes,
                              void **out_mtlbuffer, uint32_t *out_offset)
{
    if (!f) return NULL;
    return cm_frame_alloc(f, f->ubase, f->ubuf, &f->ucur, CM_UNI_RING_BYTES,
                          bytes, out_mtlbuffer, out_offset);
}

void *cm_frame_encoder(cm_frame *f)
{
    return (f && f->active) ? (__bridge void *)f->enc : NULL;
}

cm_device *cm_frame_device(cm_frame *f)
{
    return f ? f->dev : NULL;
}

void cm_frame_end(cm_frame *f, bool wait)
{
    if (!f || !f->active) return;
    cm_device *dev = f->dev;

    @autoreleasepool {
        [f->enc endEncoding];
        f->enc = nil;

        /* Encoding is done, but the GPU still reads this slot's vertex/uniform
         * buffers until the command buffer COMPLETES.  Mark it in_flight (and no
         * longer active) so cm_frame_begin's slot scan keeps skipping it until the
         * completion handler clears it: `active` alone would free the slot the
         * instant we stop encoding -- before the GPU has finished -- so a reused
         * slot could overwrite a slice still in flight. */
        f->active    = false;
        f->in_flight = true;

        /* Signal the ring gate when the GPU finishes reading this slot's buffers /
         * writing the resolve.  Capture the frame (stable: &dev->frames[slot],
         * lives with the process-shared device) so the handler can clear in_flight.
         * That is safe despite the "slot may be reused" caveat: a slot is reused
         * only after its permit returns, which is THIS signal, so no later frame
         * occupies the slot until the handler has run. */
        dispatch_semaphore_t sem = dev->sem;
        cm_surface_t *surface = f->surface;
        cm_frame *frame = f;
        [f->cmd addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull cb) {
            (void)cb;
            /* Clear in_flight BEFORE signalling so a cm_frame_begin that wakes on
             * the returned permit already sees this slot free. */
            frame->in_flight = false;
            dispatch_semaphore_signal(sem);
        }];

        [f->cmd commit];

        /* Drop transient objects BEFORE any blocking wait so we are not holding
         * the encoder/cmd longer than needed.  (active/in_flight already set.) */
        f->surface = NULL;

        id<MTLCommandBuffer> cmd = f->cmd;
        f->cmd = nil;

        if (wait) {
            [cmd waitUntilCompleted];
            /* The resolved IOSurface now holds fresh pixels. */
            extern void cm_surface_did_render(cm_surface_t *s) __attribute__((weak));
            if (surface && cm_surface_did_render) cm_surface_did_render(surface);
        }
    }
}

/* ===========================================================================
 * BUILD NOTES (cross-module seams to reconcile)
 * ---------------------------------------------------------------------------
 * Everything below is self-contained in THIS translation unit and compiles as
 * the device backbone; the items here are the seams other modules need the Build
 * phase to wire so the new capability is reachable end-to-end.
 *
 * 1. NEW device-API declarations.  cm_internal.h "MODULE: cm_device.m" presently
 *    declares only cm_device_cover_pipeline + cm_device_sampler (the stubs this
 *    file now fully implements).  Three NEW symbols are defined here and need a
 *    one-line prototype each added to that block so callers can link without a
 *    local `extern`:
 *        void  *cm_device_cover_pipeline_a8(cm_device*, cm_operator_t,
 *                                           bool aa_none, bool clip, cm_paint_kind);
 *        void   cm_device_set_tolerance(cm_device*, double);
 *        double cm_device_tolerance(cm_device*);
 *    They are forward-declared at the top of this file so the TU is warning-clean
 *    in the meantime.
 *
 * 2. A8 (R8) cover target.  cm_fill.m currently fetches CM_PIPE_COVER_SOLID /
 *    _LINEAR via cm_device_pipeline (always BGRA8).  Drawing a fill into an A8
 *    surface (R8 colour) mismatches the render-pass colour format.  The fix is
 *    for the encode path (cm_fill.m / cm_compose.m), when ctx->surface->format ==
 *    CM_FORMAT_A8, to select cm_device_cover_pipeline_a8(...) instead.  This file
 *    builds and caches that R8 variant; only the selection at the call site is
 *    missing.  (The clip A8 plane in cm_clip.m, which renders into its own R8
 *    target, is the first consumer.)
 *
 * 3. Subsurface geometry offset.  cm_frame_begin now binds surface->parent's
 *    textures for a SUBSURFACE and scissors to its sub-rect (the data is all on
 *    the struct; see cm_surface_similar.c seam #1).  But the device-space->clip
 *    mapping (to_clip) in cm_fill.m / cm_compose.m is computed from
 *    ctx->surface->width/height and applies NO device offset, so geometry drawn
 *    into a subsurface currently maps as if the subsurface were at the backing
 *    origin.  To finish subsurface drawing the encode path must (a) compute
 *    to_clip from the BACKING dimensions (surface->parent->width/height) and
 *    (b) add surface->dev_off_x/y to device-space vertices (or fold it into the
 *    CTM at flatten time).  cm_frame_begin's scissor already clips the result to
 *    the right window, so the visible effect today is "draws into the parent
 *    origin, clipped to the sub-rect band" -- correct only when dev_off == 0.
 *    This file deliberately does not reach into the encode path.
 *
 * 4. Runtime flatten tolerance.  cm_device_tolerance() exposes the device's
 *    flatten tolerance (default CM_FLATTEN_TOLERANCE).  cm_path_flatten's frozen
 *    signature has no tolerance arg and hardcodes CM_FLATTEN_TOLERANCE, so to
 *    honor a runtime tolerance the flatten owner (cm_path.m) should read
 *    cm_device_tolerance(dev) where it currently uses the CM_FLATTEN_TOLERANCE
 *    macro (the device is reachable via the surface at every flatten call site in
 *    cairo_metal.m / cm_clip.m).  cm_stroke_expand already takes a tolerance
 *    argument; cairo_metal.m can pass cm_device_tolerance(ctx->surface->dev)
 *    there in place of CM_ARC_TOLERANCE.  Until wired, the default tolerance is
 *    in force and behaviour is unchanged.
 * =========================================================================== */
