/*
 * cm_clip.m  --  CairoMetal clip plane (A8 coverage) + CPU clip geometry
 * ============================================================================
 *
 * MODULE OWNER of cm_internal.h "MODULE: cm_clip.m".
 *
 * Owns the clip plane (DESIGN domain (b): per-context A8 clip-coverage texture):
 *
 *   - A per-clip A8 (MTLPixelFormatR8Unorm) coverage MTLTexture rendered by the
 *     classic STENCIL-THEN-COVER of the clip path with the current fill rule --
 *     the SAME technique cm_fill.m uses for colour fills, but the cover pass
 *     writes COVERAGE (1.0) into a single-channel R8 target instead of paint.
 *     4x MSAA on the coverage + stencil attachments gives cairo-quality
 *     antialiased clip edges, resolved into the single-sample R8 texture at
 *     store, exactly as cm_surface.m resolves colour MSAA into the IOSurface.
 *   - Nested clip() INTERSECTS (min) with the current clip: the new clip's
 *     cover fragment samples the PARENT mask and multiplies, so the resulting
 *     coverage is new_path_coverage * parent_coverage (cairo intersection
 *     semantics).  reset_clip() drops to "unclipped" (full coverage).
 *   - Every fill/stroke/paint/mask cover fragment is meant to sample this mask
 *     and multiply its coverage; cm_clip_bind(enc,clip) binds the A8 texture +
 *     a clamp sampler to the cover fragment stage for that.  (The cover shaders
 *     that consume it are owned by cm_fill.m / cm_compose.m; binding is the
 *     cross-module seam -- see the note at the end of this file.)
 *   - clip()/fill()/stroke() CONSUME the path; clip_preserve() does not, exactly
 *     like cairo (and like cm_fill_preserve vs cm_fill).
 *   - CPU clip geometry, independent of the GPU mask so it is always correct
 *     even if the mask could not be built: clip_extents (device AABB -> inverse
 *     CTM -> user, via cm_matrix_invert), in_clip (point-in-clip over the stored
 *     device-space contours, cm_point_in_contours), and
 *     copy_clip_rectangle_list (single axis-aligned rect, else
 *     CLIP_NOT_REPRESENTABLE).
 *
 * LIFECYCLE / OWNERSHIP: the clip is a refcounted cm_clip_state (cm_internal.h).
 * The live ctx->clip holds one reference; cm_save snapshots it with
 * cm_clip_retain and cm_restore restores it with the snapshot's ownership (see
 * cm_state.c).  reset_clip must therefore still be undone by a later restore --
 * which it is, because restore just reinstalls the saved clip pointer.  The A8
 * texture is retained by the cm_clip_state and released (CFRelease) when the
 * last reference drops.
 *
 * PIPELINE STATES: the cover-into-R8 pass needs render-pipeline-states whose
 * colour attachment format is R8Unorm, which differ from cm_device.m's shipping
 * BGRA8 fill pipelines, so this file builds its own two pipelines (stencil +
 * cover-coverage) ONCE per device from a tiny embedded Metal source -- mirroring
 * cm_device.m's own runtime newLibraryWithSource: fallback.  The DEPTH-STENCIL
 * states are pixel-format-independent, so we REUSE cm_device's persistent ones
 * (CM_DSS_STENCIL_WRITE_* / CM_DSS_COVER_TEST_*) verbatim, matching cm_fill.m.
 * ============================================================================
 */

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#include "cm_internal.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

/* Strongly-typed device handle (declared/owned by cm_device.m).  cm_device_mtl()
 * already returns the id<MTLDevice> as void*; we use that.  The command queue is
 * reached through cm_device.m's strongly-typed accessor (also used by
 * cm_surface.m) so the clip pass can submit its own one-shot command buffer. */
extern id<MTLCommandQueue> cm_device_queue_id(cm_device *dev);

/* Sticky first-error setter on the context, matching cairo_metal.m's policy
 * (that file's cm_ctx_set_status is static, so we keep a private equivalent here
 * rather than edit another module; see the BUILD-PHASE SEAM note at EOF). */
static inline void cm_ctx_set_status_clip(cm_context_t *ctx, cm_status_t st)
{
    if (ctx && st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS)
        ctx->status = st;
}

/* ---------------------------------------------------------------------------
 * Binding indices for the A8 cover pass -- local to this file's embedded
 * shaders; they need not match fill.metal because this is a separate library.
 * ------------------------------------------------------------------------- */
#define CM_CLIP_BUF_VERTS    0   /* device const cm_vec2f* device-space verts  */
#define CM_CLIP_BUF_UNIFORMS 1   /* constant clip-cover uniforms               */
#define CM_CLIP_TEX_PARENT   0   /* parent A8 mask (R8) for nested intersection*/
#define CM_CLIP_SMP_PARENT   0   /* parent-mask sampler                        */

#define CM_CLIP_COVER_QUAD_VERTS 4

/* Uniform block fed to the embedded clip shaders.  Kept tiny + self-contained
 * (NOT cm_uniforms): device px -> clip space, plus the parent-sample controls.
 *   to_clip   = (sx, sy, tx, ty)  device px -> Metal clip (y flipped via -sy)
 *   inv_size  = (1/W, 1/H, _, _)  device px -> parent-mask uv
 *   has_parent= 1 when the parent mask is bound (nested intersection)          */
typedef struct {
    float to_clip[4];
    float inv_size[4];
    int   has_parent;
    int   _pad[3];
} cm_clip_uniforms;

/* ===========================================================================
 * Embedded Metal source for the coverage (A8) stencil-then-cover pass.
 * ---------------------------------------------------------------------------
 * Vertex positions arrive ALREADY in device pixels (the CTM was applied on the
 * CPU at flatten time, exactly like cm_path/cm_fill), so the vertex stages only
 * map device px -> Metal clip space with to_clip.  The cover fragment writes
 * coverage into R8 (.r); when a parent mask is bound it multiplies by the
 * parent's sampled coverage to realise clip intersection (min via product on
 * [0,1] coverage).  Stencil pass colour is masked off by the pipeline (writeMask
 * none), so its fragment is trivial.
 * =========================================================================== */
static NSString *const kCmClipShaderSource = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct cm_vec2f { float x; float y; };\n"
"struct ClipUniforms {\n"
"  float to_clip[4];\n"
"  float inv_size[4];\n"
"  int   has_parent;\n"
"  int   _pad[3];\n"
"};\n"
"static inline float4 clip_to_clip(float2 p, constant ClipUniforms &u) {\n"
"  float2 s = float2(u.to_clip[0], u.to_clip[1]);\n"
"  float2 t = float2(u.to_clip[2], u.to_clip[3]);\n"
"  return float4(p * s + t, 0.0, 1.0);\n"
"}\n"
"vertex float4 cmclip_vs_stencil(uint vid [[vertex_id]],\n"
"                                device const cm_vec2f *verts [[buffer(0)]],\n"
"                                constant ClipUniforms &u [[buffer(1)]]) {\n"
"  cm_vec2f p = verts[vid];\n"
"  return clip_to_clip(float2(p.x, p.y), u);\n"
"}\n"
"fragment float4 cmclip_fs_stencil() { return float4(0.0); }\n"
"struct ClipCoverIO { float4 position [[position]]; float2 dev; };\n"
"vertex ClipCoverIO cmclip_vs_cover(uint vid [[vertex_id]],\n"
"                                   device const cm_vec2f *verts [[buffer(0)]],\n"
"                                   constant ClipUniforms &u [[buffer(1)]]) {\n"
"  cm_vec2f p = verts[vid];\n"
"  ClipCoverIO o;\n"
"  o.dev = float2(p.x, p.y);\n"
"  o.position = clip_to_clip(o.dev, u);\n"
"  return o;\n"
"}\n"
"fragment float4 cmclip_fs_cover(ClipCoverIO in [[stage_in]],\n"
"                                constant ClipUniforms &u [[buffer(1)]],\n"
"                                texture2d<float> parent [[texture(0)]],\n"
"                                sampler psamp [[sampler(0)]]) {\n"
"  float cov = 1.0;\n"
"  if (u.has_parent != 0) {\n"
"    float2 uv = in.dev * float2(u.inv_size[0], u.inv_size[1]);\n"
"    cov = parent.sample(psamp, uv).r;\n"
"  }\n"
"  return float4(cov, 0.0, 0.0, cov);\n"
"}\n";

/* ===========================================================================
 * Per-device pipeline + sampler cache for the A8 coverage pass.
 * ---------------------------------------------------------------------------
 * Built ONCE per device (a tiny side table keyed by the cm_device pointer),
 * mirroring cm_paint.m's per-pattern LUT cache pattern.  manim uses a single
 * process device, so this table effectively holds one live entry; the small cap
 * only bounds worst case.  All access is mutex-guarded because clips may be
 * applied from different context threads.
 * =========================================================================== */
#define CM_CLIP_DEV_CACHE_CAP 4

typedef struct {
    cm_device *dev;              /* identity key                               */
    void      *ps_stencil;       /* id<MTLRenderPipelineState> (R8 stencil)    */
    void      *ps_cover;         /* id<MTLRenderPipelineState> (R8 cover)      */
    void      *sampler;          /* id<MTLSamplerState> (clamp, linear)        */
    bool       tried;            /* build attempted (success OR failure)       */
    bool       ok;               /* build succeeded                            */
} cm_clip_dev_states;

static cm_clip_dev_states g_clip_states[CM_CLIP_DEV_CACHE_CAP];
static pthread_mutex_t    g_clip_mtx = PTHREAD_MUTEX_INITIALIZER;

/* Build the two R8-target pipelines + the parent sampler for `dev`.  Returns
 * the (cached) states entry, or NULL if the device is missing.  On build
 * failure the entry is marked tried-but-not-ok so we never re-attempt every
 * call yet still fall back to a CPU-only (mask_tex==NULL) clip. */
static cm_clip_dev_states *cm_clip_states_for(cm_device *dev)
{
    if (!dev) return NULL;

    cm_clip_dev_states *slot = NULL;
    for (int i = 0; i < CM_CLIP_DEV_CACHE_CAP; ++i) {
        if (g_clip_states[i].dev == dev) { slot = &g_clip_states[i]; break; }
    }
    if (!slot) {
        for (int i = 0; i < CM_CLIP_DEV_CACHE_CAP; ++i) {
            if (g_clip_states[i].dev == NULL) { slot = &g_clip_states[i]; break; }
        }
        if (!slot) slot = &g_clip_states[0];   /* evict slot 0 (effectively never hit) */
    }

    if (slot->tried) return slot;
    slot->tried = true;
    slot->dev   = dev;
    slot->ok    = false;

    @autoreleasepool {
        id<MTLDevice> mtl = (__bridge id<MTLDevice>)cm_device_mtl(dev);
        if (!mtl) return slot;

        NSError *err = nil;
        MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
        id<MTLLibrary> lib = [mtl newLibraryWithSource:kCmClipShaderSource
                                               options:opts
                                                 error:&err];
        if (!lib) {
            NSLog(@"CairoMetal: clip shader compile failed: %@", err);
            return slot;
        }

        id<MTLFunction> vs_st = [lib newFunctionWithName:@"cmclip_vs_stencil"];
        id<MTLFunction> fs_st = [lib newFunctionWithName:@"cmclip_fs_stencil"];
        id<MTLFunction> vs_cv = [lib newFunctionWithName:@"cmclip_vs_cover"];
        id<MTLFunction> fs_cv = [lib newFunctionWithName:@"cmclip_fs_cover"];
        if (!vs_st || !fs_st || !vs_cv || !fs_cv) return slot;

        /* Stencil pipeline: R8 colour attachment, MSAA, colour writes OFF (only
         * the stencil op matters), matching cm_device.m's BGRA stencil pipeline
         * but with the coverage target's format. */
        MTLRenderPipelineDescriptor *pd_st = [[MTLRenderPipelineDescriptor alloc] init];
        pd_st.vertexFunction    = vs_st;
        pd_st.fragmentFunction  = fs_st;
        pd_st.rasterSampleCount = CM_MSAA_SAMPLE_COUNT;
        pd_st.colorAttachments[0].pixelFormat = MTLPixelFormatR8Unorm;
        pd_st.colorAttachments[0].writeMask   = MTLColorWriteMaskNone;
        pd_st.colorAttachments[0].blendingEnabled = NO;
        pd_st.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;
        id<MTLRenderPipelineState> ps_st =
            [mtl newRenderPipelineStateWithDescriptor:pd_st error:&err];
        if (!ps_st) { NSLog(@"CairoMetal: clip stencil pipeline failed: %@", err); return slot; }

        /* Cover pipeline: write coverage into R8.  Blending OFF -- the cover DSS
         * passes only inside the path and we want the coverage value written
         * verbatim (the target was cleared to 0, so outside-path stays 0). */
        MTLRenderPipelineDescriptor *pd_cv = [[MTLRenderPipelineDescriptor alloc] init];
        pd_cv.vertexFunction    = vs_cv;
        pd_cv.fragmentFunction  = fs_cv;
        pd_cv.rasterSampleCount = CM_MSAA_SAMPLE_COUNT;
        pd_cv.colorAttachments[0].pixelFormat = MTLPixelFormatR8Unorm;
        pd_cv.colorAttachments[0].writeMask   = MTLColorWriteMaskAll;
        pd_cv.colorAttachments[0].blendingEnabled = NO;
        pd_cv.stencilAttachmentPixelFormat = MTLPixelFormatStencil8;
        id<MTLRenderPipelineState> ps_cv =
            [mtl newRenderPipelineStateWithDescriptor:pd_cv error:&err];
        if (!ps_cv) { NSLog(@"CairoMetal: clip cover pipeline failed: %@", err); return slot; }

        MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
        sd.minFilter    = MTLSamplerMinMagFilterLinear;
        sd.magFilter    = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        id<MTLSamplerState> samp = [mtl newSamplerStateWithDescriptor:sd];
        if (!samp) return slot;

        slot->ps_stencil = (void *)CFBridgingRetain(ps_st);
        slot->ps_cover   = (void *)CFBridgingRetain(ps_cv);
        slot->sampler    = (void *)CFBridgingRetain(samp);
        slot->ok         = true;
    }
    return slot;
}

/* ===========================================================================
 * Clip-state lifecycle
 * =========================================================================== */
cm_clip_state *cm_clip_retain(cm_clip_state *clip)
{
    if (clip) clip->refcount++;
    return clip;
}

void cm_clip_release(cm_clip_state *clip)
{
    if (!clip) return;
    if (--clip->refcount > 0) return;
    if (clip->contours) { cm_path_free(clip->contours); free(clip->contours); }
    if (clip->mask_tex) {
        /* Balance the CFBridgingRetain taken when the A8 texture was created. */
        CFRelease(clip->mask_tex);
        clip->mask_tex = NULL;
    }
    free(clip);
}

/* Allocate a zeroed clip-state with one reference. */
static cm_clip_state *cm_clip_state_new(void)
{
    cm_clip_state *c = (cm_clip_state *)calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->refcount = 1;
    return c;
}

/* ===========================================================================
 * CPU clip geometry helpers
 * =========================================================================== */

/* Deep-copy the *device-space flattened* contours of `flat` into a freshly
 * allocated cm_path stored on the clip-state (used by in_clip / extents and as
 * the source for the GPU stencil pass).  Only the flattened cache (pts +
 * contours) is copied -- the recorded verb stream is irrelevant once flattened.
 * Returns the new cm_path*, or NULL on OOM. */
static cm_path *cm_clip_copy_contours(const cm_path *flat)
{
    if (!flat || flat->pts_count == 0 || flat->contour_count == 0) return NULL;

    cm_path *dst = (cm_path *)malloc(sizeof(*dst));
    if (!dst) return NULL;
    cm_path_init(dst);

    dst->pts = (cm_vec2f *)malloc((size_t)flat->pts_count * sizeof(cm_vec2f));
    dst->contours = (cm_contour *)malloc((size_t)flat->contour_count * sizeof(cm_contour));
    if (!dst->pts || !dst->contours) {
        cm_path_free(dst);
        free(dst);
        return NULL;
    }
    memcpy(dst->pts, flat->pts, (size_t)flat->pts_count * sizeof(cm_vec2f));
    memcpy(dst->contours, flat->contours,
           (size_t)flat->contour_count * sizeof(cm_contour));
    dst->pts_count = dst->pts_cap = flat->pts_count;
    dst->contour_count = dst->contour_cap = flat->contour_count;
    dst->dirty = false;     /* already flattened (device space) */
    return dst;
}

/* Tight device-space AABB of a flattened path (no MSAA guard band). */
static bool cm_clip_dev_bounds(const cm_path *flat,
                               float *minx, float *miny,
                               float *maxx, float *maxy)
{
    if (!flat || flat->pts_count == 0) return false;
    float lo_x = flat->pts[0].x, hi_x = flat->pts[0].x;
    float lo_y = flat->pts[0].y, hi_y = flat->pts[0].y;
    for (uint32_t i = 1; i < flat->pts_count; ++i) {
        float x = flat->pts[i].x, y = flat->pts[i].y;
        if (x < lo_x) lo_x = x; else if (x > hi_x) hi_x = x;
        if (y < lo_y) lo_y = y; else if (y > hi_y) hi_y = y;
    }
    *minx = lo_x; *miny = lo_y; *maxx = hi_x; *maxy = hi_y;
    return true;
}

/* Is the flattened path a single axis-aligned rectangle in DEVICE space?  We
 * accept exactly one contour of 4 distinct corners (or 5 with a closing repeat)
 * whose four edges are each horizontal or vertical and whose corner set matches
 * the AABB.  This is the representable case for copy_clip_rectangle_list (an
 * axis-aligned device rect under manim's axis-aligned CTM maps to an
 * axis-aligned user rect); anything else reports CLIP_NOT_REPRESENTABLE. */
static bool cm_clip_is_axis_rect(const cm_path *flat)
{
    if (!flat || flat->contour_count != 1) return false;
    const cm_contour *c = &flat->contours[0];
    uint32_t n = c->point_count;
    const cm_vec2f *p = &flat->pts[c->first_point];

    /* Drop a trailing point that duplicates the first (explicit close). */
    if (n >= 2 &&
        fabsf(p[n - 1].x - p[0].x) < 1e-3f &&
        fabsf(p[n - 1].y - p[0].y) < 1e-3f) {
        n -= 1;
    }
    if (n != 4) return false;

    float minx, miny, maxx, maxy;
    if (!cm_clip_dev_bounds(flat, &minx, &miny, &maxx, &maxy)) return false;
    if (!(maxx > minx) || !(maxy > miny)) return false;   /* degenerate */

    const float eps = 1e-3f;
    /* Every vertex must sit on an AABB corner, and consecutive edges must be
     * axis-aligned (one coordinate shared with the next vertex). */
    for (uint32_t i = 0; i < 4; ++i) {
        bool on_x = (fabsf(p[i].x - minx) < eps) || (fabsf(p[i].x - maxx) < eps);
        bool on_y = (fabsf(p[i].y - miny) < eps) || (fabsf(p[i].y - maxy) < eps);
        if (!on_x || !on_y) return false;
        const cm_vec2f *q = &p[(i + 1) % 4];
        bool h_edge = fabsf(p[i].y - q->y) < eps;   /* shared y -> horizontal */
        bool v_edge = fabsf(p[i].x - q->x) < eps;   /* shared x -> vertical   */
        if (!h_edge && !v_edge) return false;
    }
    return true;
}

/* ===========================================================================
 * GPU: render the clip path's coverage into a fresh A8 (R8) MTLTexture.
 * ---------------------------------------------------------------------------
 * Self-contained render pass (its own command buffer, NOT the surface frame --
 * the clip mask is a different render target than the IOSurface BGRA colour).
 * Stencil-then-cover, reusing cm_device's persistent depth-stencil states; the
 * cover pass writes coverage into R8 and, when `parent_mask` is non-NULL,
 * multiplies by the parent's sampled coverage (clip intersection).  MSAA is
 * resolved into the single-sample R8 texture at store, like cm_surface.m.
 *
 * Returns a +1 CFBridgingRetain'd id<MTLTexture> as void* (caller stores it on
 * the clip-state, released in cm_clip_release), or NULL on any failure -- in
 * which case the clip degrades to CPU-only (still correct for in_clip/extents).
 * =========================================================================== */
static void *cm_clip_render_mask(cm_device *dev, const cm_path *flat,
                                 cm_fill_rule_t rule, int width, int height,
                                 void *parent_mask /* id<MTLTexture> or NULL */)
{
    if (!dev || !flat || width <= 0 || height <= 0) return NULL;

    uint32_t fan_vtx = cm_path_fan_vertex_count(flat);
    if (fan_vtx == 0) return NULL;   /* no fillable area -> empty clip handled by caller */

    cm_clip_dev_states *st = cm_clip_states_for(dev);
    if (!st || !st->ok) return NULL;

    void *result = NULL;

    @autoreleasepool {
        id<MTLDevice> mtl = (__bridge id<MTLDevice>)cm_device_mtl(dev);
        if (!mtl) return NULL;

        /* --- Single-sample resolve target: the persistent A8 clip mask. ---
         * Shared storage so it is GPU-renderable AND shader-readable in the
         * later colour pass without a blit. */
        MTLTextureDescriptor *rd =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                               width:(NSUInteger)width
                                                              height:(NSUInteger)height
                                                           mipmapped:NO];
        rd.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        rd.storageMode = MTLStorageModeShared;
        id<MTLTexture> resolve = [mtl newTextureWithDescriptor:rd];
        if (!resolve) return NULL;

        /* --- Transient MSAA coverage + stencil (tile memory). --- */
        MTLTextureDescriptor *md =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                               width:(NSUInteger)width
                                                              height:(NSUInteger)height
                                                           mipmapped:NO];
        md.textureType = MTLTextureType2DMultisample;
        md.sampleCount = CM_MSAA_SAMPLE_COUNT;
        md.usage       = MTLTextureUsageRenderTarget;
        md.storageMode = MTLStorageModeMemoryless;
        id<MTLTexture> msaa = [mtl newTextureWithDescriptor:md];

        MTLTextureDescriptor *sdsc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatStencil8
                                                               width:(NSUInteger)width
                                                              height:(NSUInteger)height
                                                           mipmapped:NO];
        sdsc.textureType = MTLTextureType2DMultisample;
        sdsc.sampleCount = CM_MSAA_SAMPLE_COUNT;
        sdsc.usage       = MTLTextureUsageRenderTarget;
        sdsc.storageMode = MTLStorageModeMemoryless;
        id<MTLTexture> stencil = [mtl newTextureWithDescriptor:sdsc];
        if (!msaa || !stencil) return NULL;

        /* --- Render pass: clear coverage to 0, resolve into `resolve`. --- */
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture        = msaa;
        rp.colorAttachments[0].resolveTexture = resolve;
        rp.colorAttachments[0].loadAction     = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction    = MTLStoreActionMultisampleResolve;
        rp.colorAttachments[0].clearColor     = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        rp.stencilAttachment.texture      = stencil;
        rp.stencilAttachment.loadAction   = MTLLoadActionClear;
        rp.stencilAttachment.storeAction  = MTLStoreActionDontCare;
        rp.stencilAttachment.clearStencil = 0;

        id<MTLCommandQueue> queue = cm_device_queue_id(dev);
        if (!queue) return NULL;

        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rp];
        if (!cmd || !enc) return NULL;

        /* --- Bump the fan + cover-quad vertices into a transient buffer. ---
         * The clip pass is cold relative to per-draw fills, so a one-shot shared
         * MTLBuffer here is fine (the per-frame ring belongs to the surface
         * frame, which this pass deliberately does not touch). */
        size_t verts_n = (size_t)fan_vtx + CM_CLIP_COVER_QUAD_VERTS;
        id<MTLBuffer> vbuf =
            [mtl newBufferWithLength:verts_n * sizeof(cm_vec2f)
                             options:MTLResourceStorageModeShared];
        if (!vbuf) { [enc endEncoding]; return NULL; }
        cm_vec2f *vptr = (cm_vec2f *)vbuf.contents;

        uint32_t written = 0;
        for (uint32_t ci = 0; ci < flat->contour_count; ++ci)
            written += cm_path_emit_fan(flat, ci, vptr + written);
        if (written == 0 || written > fan_vtx) { [enc endEncoding]; return NULL; }

        /* Cover quad = device-space bounding box (matches cm_fill cover quad). */
        float bminx, bminy, bmaxx, bmaxy;
        cm_path_bounds(flat, &bminx, &bminy, &bmaxx, &bmaxy);
        cm_vec2f *quad = vptr + fan_vtx;   /* fixed slot after the fan region   */
        quad[0].x = bminx; quad[0].y = bminy;
        quad[1].x = bmaxx; quad[1].y = bminy;
        quad[2].x = bminx; quad[2].y = bmaxy;
        quad[3].x = bmaxx; quad[3].y = bmaxy;

        /* --- Uniforms: device px -> clip space (y flipped) + parent controls. */
        cm_clip_uniforms u;
        memset(&u, 0, sizeof(u));
        u.to_clip[0] =  2.0f / (float)width;
        u.to_clip[1] = -2.0f / (float)height;
        u.to_clip[2] = -1.0f;
        u.to_clip[3] =  1.0f;
        u.inv_size[0] = 1.0f / (float)width;
        u.inv_size[1] = 1.0f / (float)height;
        u.has_parent  = parent_mask ? 1 : 0;

        id<MTLRenderPipelineState> ps_stencil =
            (__bridge id<MTLRenderPipelineState>)st->ps_stencil;
        id<MTLRenderPipelineState> ps_cover   =
            (__bridge id<MTLRenderPipelineState>)st->ps_cover;
        /* Reuse cm_device's persistent, format-independent depth-stencil states
         * exactly as cm_fill.m does (incr/decr-wrap or invert for the stencil
         * pass; NotEqual(0)+zero for the cover pass). */
        cm_dss_id stencil_dss = (rule == CM_FILL_RULE_EVEN_ODD)
            ? CM_DSS_STENCIL_WRITE_EVENODD : CM_DSS_STENCIL_WRITE_NONZERO;
        cm_dss_id cover_dss   = (rule == CM_FILL_RULE_EVEN_ODD)
            ? CM_DSS_COVER_TEST_EVENODD : CM_DSS_COVER_TEST_NONZERO;
        id<MTLDepthStencilState> ds_stencil =
            (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, stencil_dss);
        id<MTLDepthStencilState> ds_cover =
            (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, cover_dss);
        if (!ds_stencil || !ds_cover) { [enc endEncoding]; return NULL; }

        [enc setCullMode:MTLCullModeNone];
        [enc setFrontFacingWinding:MTLWindingCounterClockwise];
        [enc setVertexBytes:&u length:sizeof(u) atIndex:CM_CLIP_BUF_UNIFORMS];
        [enc setFragmentBytes:&u length:sizeof(u) atIndex:CM_CLIP_BUF_UNIFORMS];

        /* PASS 1 -- STENCIL (winding/parity; colour masked off by pipeline). */
        [enc setRenderPipelineState:ps_stencil];
        [enc setDepthStencilState:ds_stencil];
        [enc setStencilReferenceValue:0];
        [enc setVertexBuffer:vbuf offset:0 atIndex:CM_CLIP_BUF_VERTS];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:written];

        /* PASS 2 -- COVER (test stencil + zero it; write coverage into R8). */
        [enc setRenderPipelineState:ps_cover];
        [enc setDepthStencilState:ds_cover];
        if (parent_mask) {
            [enc setFragmentTexture:(__bridge id<MTLTexture>)parent_mask
                            atIndex:CM_CLIP_TEX_PARENT];
            [enc setFragmentSamplerState:(__bridge id<MTLSamplerState>)st->sampler
                                 atIndex:CM_CLIP_SMP_PARENT];
        }
        [enc setVertexBuffer:vbuf
                      offset:(NSUInteger)fan_vtx * sizeof(cm_vec2f)
                     atIndex:CM_CLIP_BUF_VERTS];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:CM_CLIP_COVER_QUAD_VERTS];

        [enc endEncoding];
        [cmd commit];
        /* Block so the resolved R8 mask is valid before a downstream colour pass
         * binds it (the clip is set up once, then many draws sample it). */
        [cmd waitUntilCompleted];

        result = (void *)CFBridgingRetain(resolve);
    }
    return result;
}

/* ===========================================================================
 * Internal apply / reset
 * ===========================================================================
 * cm_clip_apply intersects the current clip with `path` (current fill rule):
 *   1. flatten the path to device space (CTM applied CPU-side, like fills);
 *   2. build a new clip-state holding the device-space contours + rule + the
 *      INTERSECTED device AABB + the is_rectangle flag;
 *   3. render the A8 coverage mask (stencil-then-cover), multiplying by the
 *      parent mask for nested intersection;
 *   4. swap it in as ctx->clip (releasing the old live reference).
 * The path is consumed/preserved by the PUBLIC cm_clip / cm_clip_preserve glue,
 * not here (so this internal entry is reusable by cm_recording.m's replay).
 * =========================================================================== */
cm_status_t cm_clip_apply(cm_context_t *ctx, const cm_path *path,
                          cm_fill_rule_t rule, bool preserve)
{
    (void)preserve;   /* path consume/preserve is the caller's concern */
    if (!ctx) return CM_STATUS_NO_MEMORY;

    /* An empty clip path clips EVERYTHING out in cairo.  We model that as an
     * empty clip-state (no contours, zero-area AABB, mask stays NULL); in_clip
     * then returns 0 and extents collapse to empty. */
    cm_path *flat_local = NULL;
    const cm_path *flat = NULL;
    if (path && path->verb_count > 0) {
        /* Flatten a COPY so we never disturb the caller's recorded path / its
         * device cache (cairo_metal.m may reuse ctx->path for a following draw).
         * We flatten via a scratch cm_path seeded from the recorded verbs. */
        if (path == &ctx->path) {
            /* The live context path: flatten it in place (its device cache is
             * recomputed anyway on the next draw if the CTM changes). */
            cm_status_t st = cm_path_flatten((cm_path *)path, &ctx->ctm);
            if (st != CM_STATUS_SUCCESS) { cm_ctx_set_status_clip(ctx, st); return st; }
            flat = path;
        } else {
            /* External path (e.g. replay): copy verbs into a scratch, flatten. */
            flat_local = (cm_path *)malloc(sizeof(*flat_local));
            if (!flat_local) return CM_STATUS_NO_MEMORY;
            cm_path_init(flat_local);
            for (uint32_t i = 0; i < path->verb_count; ++i) {
                cm_path_data_type_t t; double pts[6];
                int npt = cm_path_get_verb(path, i, &t, pts);
                switch (t) {
                    case CM_PATH_MOVE_TO:  cm_path_move_to(flat_local, pts[0], pts[1]); break;
                    case CM_PATH_LINE_TO:  cm_path_line_to(flat_local, pts[0], pts[1]); break;
                    case CM_PATH_CURVE_TO: cm_path_curve_to(flat_local, pts[0], pts[1],
                                                            pts[2], pts[3], pts[4], pts[5]); break;
                    case CM_PATH_CLOSE_PATH: cm_path_close(flat_local); break;
                    default: break;
                }
                (void)npt;
            }
            cm_status_t st = cm_path_flatten(flat_local, &ctx->ctm);
            if (st != CM_STATUS_SUCCESS) {
                cm_path_free(flat_local); free(flat_local);
                cm_ctx_set_status_clip(ctx, st);
                return st;
            }
            flat = flat_local;
        }
    }

    cm_clip_state *nc = cm_clip_state_new();
    if (!nc) {
        if (flat_local) { cm_path_free(flat_local); free(flat_local); }
        return CM_STATUS_NO_MEMORY;
    }
    nc->rule = rule;

    cm_clip_state *old = ctx->clip;   /* current live clip (parent), or NULL */

    if (flat && flat->pts_count > 0 && flat->contour_count > 0) {
        /* Device-space contours of the new clip path (for in_clip / extents and
         * as the stencil source). */
        nc->contours = cm_clip_copy_contours(flat);

        /* New path's device AABB, intersected with the parent's AABB. */
        float nx1, ny1, nx2, ny2;
        if (cm_clip_dev_bounds(flat, &nx1, &ny1, &nx2, &ny2)) {
            if (old) {
                nx1 = (nx1 > old->dev_x1) ? nx1 : old->dev_x1;
                ny1 = (ny1 > old->dev_y1) ? ny1 : old->dev_y1;
                nx2 = (nx2 < old->dev_x2) ? nx2 : old->dev_x2;
                ny2 = (ny2 < old->dev_y2) ? ny2 : old->dev_y2;
            }
            /* Empty intersection collapses to a zero-area box (clips all out). */
            if (nx2 < nx1) nx2 = nx1;
            if (ny2 < ny1) ny2 = ny1;
            nc->dev_x1 = nx1; nc->dev_y1 = ny1;
            nc->dev_x2 = nx2; nc->dev_y2 = ny2;
        }

        /* A clip is a single rect iff the new path is an axis-aligned device
         * rect AND the parent (if any) is also a rect -- the intersection of two
         * axis-aligned rects is an axis-aligned rect. */
        nc->is_rectangle = cm_clip_is_axis_rect(flat) &&
                           (!old || old->is_rectangle);

        /* GPU A8 coverage mask (best effort; NULL -> CPU-only clip). */
        nc->mask_tex = cm_clip_render_mask(ctx->surface ? ctx->surface->dev : NULL,
                                           flat, rule,
                                           ctx->surface ? ctx->surface->width  : 0,
                                           ctx->surface ? ctx->surface->height : 0,
                                           old ? old->mask_tex : NULL);
    } else {
        /* Empty clip path: clip everything out.  Zero-area AABB; no mask.  Mark
         * is_rectangle so copy_clip_rectangle_list returns an (empty) rect list
         * rather than NOT_REPRESENTABLE, matching cairo's empty-clip behaviour. */
        nc->is_rectangle = true;
        nc->dev_x1 = nc->dev_y1 = nc->dev_x2 = nc->dev_y2 = 0.0f;
        /* Intersection with a parent is still empty; nothing to copy. */
    }

    /* Swap in the new clip; release the old live reference (the gstate stack
     * keeps its own retained snapshots, so a saved clip is unaffected). */
    ctx->clip = nc;
    if (old) cm_clip_release(old);

    if (flat_local) { cm_path_free(flat_local); free(flat_local); }
    return CM_STATUS_SUCCESS;
}

void cm_clip_reset(cm_context_t *ctx)
{
    if (!ctx) return;
    if (ctx->clip) { cm_clip_release(ctx->clip); ctx->clip = NULL; }
}

/* ===========================================================================
 * cm_clip_bind  (INTERNAL) -- bind the A8 mask + sampler to the cover frag.
 * ---------------------------------------------------------------------------
 * Called by the cover pass of cm_fill / cm_stroke / cm_compose (those modules
 * own the cover fragment that multiplies coverage by this mask).  A NULL clip,
 * or a clip whose GPU mask could not be built, binds nothing -- the cover frag
 * then renders unclipped (the CPU AABB still constrains queries; a hard
 * GPU clamp is only present when the mask exists).  The binding indices below
 * are the seam cm_fill / cm_compose must mirror in their cover shaders.
 * =========================================================================== */
#define CM_CLIP_BIND_TEX_INDEX  1   /* texture(1): A8 clip mask in cover frags  */
#define CM_CLIP_BIND_SMP_INDEX  1   /* sampler(1): clip-mask sampler            */

void cm_clip_bind(void *encoder, cm_clip_state *clip)
{
    if (!encoder || !clip || !clip->mask_tex) return;
    id<MTLRenderCommandEncoder> enc =
        (__bridge id<MTLRenderCommandEncoder>)encoder;
    id<MTLTexture> mask = (__bridge id<MTLTexture>)clip->mask_tex;
    [enc setFragmentTexture:mask atIndex:CM_CLIP_BIND_TEX_INDEX];

    /* The clip-mask sampler is owned per device; recover it from any built
     * states entry (they all use the same clamp/linear sampler).  If the entry
     * is missing we bind only the texture (the consumer's constexpr sampler, if
     * any, still works). */
    pthread_mutex_lock(&g_clip_mtx);
    void *samp = NULL;
    for (int i = 0; i < CM_CLIP_DEV_CACHE_CAP; ++i) {
        if (g_clip_states[i].ok && g_clip_states[i].sampler) {
            samp = g_clip_states[i].sampler; break;
        }
    }
    pthread_mutex_unlock(&g_clip_mtx);
    if (samp) {
        [enc setFragmentSamplerState:(__bridge id<MTLSamplerState>)samp
                             atIndex:CM_CLIP_BIND_SMP_INDEX];
    }
}

void cm_clip_extents_dev(cm_clip_state *clip,
                         float *x1, float *y1, float *x2, float *y2)
{
    if (!clip) {
        if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
        return;
    }
    if (x1) *x1 = clip->dev_x1; if (y1) *y1 = clip->dev_y1;
    if (x2) *x2 = clip->dev_x2; if (y2) *y2 = clip->dev_y2;
}

/* Clip extents in USER space: the surface bounds when unclipped, else the clip
 * device AABB mapped back through the inverse CTM (cm_matrix_invert). */
void cm_clip_extents_user(cm_context_t *ctx,
                          double *x1, double *y1, double *x2, double *y2)
{
    if (!ctx) {
        if (x1) *x1 = 0; if (y1) *y1 = 0; if (x2) *x2 = 0; if (y2) *y2 = 0;
        return;
    }
    double dx1, dy1, dx2, dy2;
    if (ctx->clip) {
        dx1 = ctx->clip->dev_x1; dy1 = ctx->clip->dev_y1;
        dx2 = ctx->clip->dev_x2; dy2 = ctx->clip->dev_y2;
    } else {
        dx1 = 0.0; dy1 = 0.0;
        dx2 = ctx->surface ? (double)ctx->surface->width  : 0.0;
        dy2 = ctx->surface ? (double)ctx->surface->height : 0.0;
    }
    cm_matrix_t inv = ctx->ctm;
    if (cm_matrix_invert(&inv) != CM_STATUS_SUCCESS) {
        if (x1) *x1 = dx1; if (y1) *y1 = dy1; if (x2) *x2 = dx2; if (y2) *y2 = dy2;
        return;
    }
    cm_matrix_transform_bbox(&inv, dx1, dy1, dx2, dy2, x1, y1, x2, y2);
}

int cm_clip_contains(cm_context_t *ctx, double x, double y)
{
    if (!ctx) return 0;
    if (!ctx->clip) return 1;            /* unclipped: everything is in-clip   */
    if (!ctx->clip->contours) return 0;  /* empty clip (all clipped out)       */
    double dx = x, dy = y;
    cm_matrix_transform_point(&ctx->ctm, &dx, &dy);
    /* Must lie inside the intersected device AABB AND the clip contours.  The
     * AABB check enforces the parent intersection (the stored contours are only
     * the most-recent clip path; nested intersection lives in the AABB + GPU
     * mask, and for the point test the AABB carries the parent constraint). */
    if (dx < ctx->clip->dev_x1 || dx > ctx->clip->dev_x2 ||
        dy < ctx->clip->dev_y1 || dy > ctx->clip->dev_y2)
        return 0;
    return cm_point_in_contours(ctx->clip->contours, dx, dy, ctx->clip->rule);
}

/* ===========================================================================
 * Public clip API
 * =========================================================================== */
void cm_clip(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_status_t st = cm_clip_apply(ctx, &ctx->path, ctx->fill_rule, false);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    cm_path_reset(&ctx->path);   /* clip() CONSUMES the path (cairo) */
}

void cm_clip_preserve(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_status_t st = cm_clip_apply(ctx, &ctx->path, ctx->fill_rule, true);
    if (st != CM_STATUS_SUCCESS && ctx->status == CM_STATUS_SUCCESS) ctx->status = st;
    /* PRESERVE: the path is intentionally NOT cleared. */
}

void cm_reset_clip(cm_context_t *ctx)
{
    /* Drop to unclipped.  This is still subject to save/restore: a prior
     * cm_save snapshotted (retained) the old clip, so a matching cm_restore
     * reinstalls it -- reset only clears the LIVE clip reference. */
    cm_clip_reset(ctx);
}

void cm_clip_extents(cm_context_t *ctx,
                     double *x1, double *y1, double *x2, double *y2)
{
    cm_clip_extents_user(ctx, x1, y1, x2, y2);
}

int cm_in_clip(cm_context_t *ctx, double x, double y)
{
    return cm_clip_contains(ctx, x, y);
}

cm_status_t cm_copy_clip_rectangle_list(cm_context_t *ctx,
                                        cm_rectangle_t *out_rects,
                                        int max_rects, int *out_count)
{
    if (out_count) *out_count = 0;
    if (!ctx) return CM_STATUS_NO_MEMORY;

    if (!ctx->clip) {
        /* Unclipped: a single rect covering the surface in user space. */
        if (max_rects >= 1 && out_rects) {
            double x1, y1, x2, y2;
            cm_clip_extents_user(ctx, &x1, &y1, &x2, &y2);
            out_rects[0].x = x1; out_rects[0].y = y1;
            out_rects[0].width = x2 - x1; out_rects[0].height = y2 - y1;
        }
        if (out_count) *out_count = 1;
        return CM_STATUS_SUCCESS;
    }

    /* A non-rectangular clip cannot be expressed as a rectangle list. */
    if (!ctx->clip->is_rectangle)
        return CM_STATUS_CLIP_NOT_REPRESENTABLE;

    /* Empty clip (all clipped out) is the representable empty list. */
    if (!ctx->clip->contours ||
        ctx->clip->dev_x2 <= ctx->clip->dev_x1 ||
        ctx->clip->dev_y2 <= ctx->clip->dev_y1) {
        if (out_count) *out_count = 0;   /* zero rectangles */
        return CM_STATUS_SUCCESS;
    }

    if (max_rects >= 1 && out_rects) {
        double x1, y1, x2, y2;
        cm_clip_extents_user(ctx, &x1, &y1, &x2, &y2);
        out_rects[0].x = x1; out_rects[0].y = y1;
        out_rects[0].width = x2 - x1; out_rects[0].height = y2 - y1;
    }
    if (out_count) *out_count = 1;
    return CM_STATUS_SUCCESS;
}

/* ===========================================================================
 * BUILD-PHASE SEAM (read this in the reconcile step)
 * ---------------------------------------------------------------------------
 * 1. cm_ctx_set_status_clip(): this file uses a sticky first-error setter on the
 *    context (same policy as cairo_metal.m's static cm_ctx_set_status).  That
 *    helper is static in cairo_metal.m, so it is re-declared+defined HERE with a
 *    distinct name to avoid touching cairo_metal.m.  If a shared non-static
 *    setter is later exported from cm_internal.h, collapse this onto it.
 *
 * 2. cm_clip_bind() binds the A8 mask at texture(1)/sampler(1) of the COVER
 *    fragment stage.  The cover shaders that SAMPLE it (cm_fs_cover_solid /
 *    _linear / _radial / _surface / _gouraud / _mask in shaders/fill.metal) and
 *    their encoders (cm_fill.m, cm_compose.m) are owned by other modules and do
 *    NOT yet sample a clip texture.  To finish wiring clip coverage into colour
 *    output, the Build phase must, in those cover frags, multiply the output by
 *    `clipmask.sample(clipsamp, dev * inv_size).r` (guarded by a uniform flag so
 *    unclipped draws skip it), and have cm_fill/cm_compose call cm_clip_bind(enc,
 *    ctx->clip) before the cover draw.  Until then, clipping is enforced on the
 *    CPU query side (in_clip / extents / copy_clip_rectangle_list) and the GPU
 *    mask is built + ready but not yet multiplied into colour.
 * =========================================================================== */
