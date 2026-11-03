//
// cm_fill.m  --  CairoMetal stencil-then-cover FILL encode (SOLE fill owner)
// ============================================================================
//
// Implements cm_fill_encode() from cm_internal.h: it encodes a complete fill of
// a (pre-flattened) path with the current paint into the frame's single render
// command encoder, using the classic two-pass STENCIL-THEN-COVER technique so
// arbitrary self-intersecting paths with holes render correctly with no CPU
// triangulation.  Strokes reach here too -- cm_stroke_expand() turns an outline
// into a fillable polygon that this same NONZERO fill rasterizes.
//
// This translation unit is the ONLY fill code that talks to Metal; it does so
// purely through the opaque void* handles vended by cm_device.m / cm_surface.m
// (pipeline states, depth-stencil states, the per-frame command encoder, and
// the bump-allocated vertex/uniform ring).  It builds NOTHING per draw beyond
// ring sub-allocations: every MTLRenderPipelineState and MTLDepthStencilState
// was created once in cm_device_create (or is built lazily + cached by
// cm_device_cover_pipeline) and is fetched O(1) here.
//
// Pass 1 STENCIL  (CM_PIPE_STENCIL_{NONZERO|EVENODD} + matching DSS):
//   draw a triangle fan per contour (cm_path_emit_fan) with colour writes
//   masked off (mask lives in the pipeline); the two-sided incr/decr-wrap
//   (nonzero) or invert (even-odd) stencil op accumulates winding/parity.
// Pass 2 COVER  (operator-selected cover pipeline + cover DSS):
//   for SOLID / LINEAR / RADIAL / SURFACE, draw the path's device-space bounding
//   quad; the cover DSS passes where the stencil indicates inside (!=0 nonzero,
//   &1 even-odd) AND zeroes the touched samples in the SAME op, so the stencil is
//   clean for the next batched path (no per-path clear).  For MESH the Gouraud
//   triangles ARE the coverage (cm_mesh_emit_triangles): there is NO bounding
//   quad -- the patch triangles are drawn directly, still gated by the pass-1
//   stencil, so the mesh paints only inside the fill path.  The fragment stage
//   resolves the paint per kind (solid colour / gradient LUT / source texture /
//   per-vertex Gouraud colour) and premultiplies; 4x MSAA gives the antialiased
//   edges, resolved at frame end.
//
// UPGRADES over the original solid/linear shipping path (which is KEPT
// byte-for-byte as the default OVER, unclipped, BGRA path):
//   - OPERATOR : the cover pipeline is selected through the single front-door
//     hook cm_compose_operator_pipeline() -> cm_device_cover_pipeline(op, ...),
//     so cm_set_operator is honored (fixed-function Porter-Duff blends for ops
//     0..13, programmable-blend cover frags for 14..28).
//   - CLIP     : cm_clip_bind() binds the active A8 clip mask + sampler to the
//     cover fragment stage (texture(1)/sampler(1)); the cover frags multiply
//     their coverage by the sampled mask.  A NULL / unbuilt clip binds nothing.
//   - PAINT    : the cover dispatch fans out by cm_pattern_type_t -- LINEAR /
//     RADIAL bind the gradient LUT (texture(0)); SURFACE / RASTER flush the
//     source surface first then bind its colour texture (texture(0)) + a runtime
//     sampler (sampler(0)) WITHOUT double-premultiplying; MESH streams Gouraud
//     triangles as the coverage.
//   - A8 TARGET: when the fill target is an A8 (R8) surface, the SOLID cover uses
//     the CM_PIPE_COVER_SOLID_A8 variant so coverage lands in the single alpha
//     channel.
//
// Non-preserve cm_fill() / cm_stroke() (= the preserve encode + cm_path_reset)
// also live here, matching cairo.  Both just delegate to their _preserve form and
// then cm_new_path; the operator, clip, and -- for stroke -- the gstate dash are
// all honored inside that preserve encode (cm_stroke_preserve runs the dash
// pre-pass before cm_stroke_expand).
//
// See shaders/fill.metal for the matching programmable stages and the
// buffer/texture binding contract mirrored by the CM_BUF_*/CM_TEX_* defines.
// ============================================================================

#import <Metal/Metal.h>

#include "cm_internal.h"
#include <string.h>
#include <math.h>

/* ANTIALIAS_NONE single-sample path (BUG 7): when the encode runs in a 1-sample
 * frame (cm_frame_begin_single), the stencil pass must use the matching 1-sample
 * stencil pipeline (the shipping CM_PIPE_STENCIL_* are 4x MSAA and would mismatch
 * the 1-sample pass).  Declared here until promoted to cm_internal.h. */
extern bool  cm_frame_is_single_sample(cm_frame *f);
extern void *cm_device_stencil_pipeline_aa_none(cm_device *dev, bool evenodd);

// ---------------------------------------------------------------------------
// Binding indices -- MUST match shaders/fill.metal (and cm_compose.m's mirror).
// ---------------------------------------------------------------------------
#define CM_BUF_VERTS      0    /* device const cm_vec2f / cm_vtx_color*  [[buffer(0)]] */
#define CM_BUF_UNIFORMS   1    /* constant cm_uniforms&  uniforms        [[buffer(1)]] */
#define CM_TEX_GRAD_LUT   0    /* texture2d<float> gradient LUT (lin/rad) [[texture(0)]] */
#define CM_TEX_SOURCE     0    /* surface-pattern colour texture          [[texture(0)]] */
#define CM_SAMPLER_SOURCE 0    /* runtime sampler (surface)               [[sampler(0)]] */
/* The clip A8 mask binds at texture(1)/sampler(1) -- owned by cm_clip_bind(). */

// A cover quad is a 4-vertex triangle strip spanning the path's device bounds.
#define CM_COVER_QUAD_VERTS 4

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/** Fill the to_clip uniform from the surface dimensions: device px -> Metal clip
 *  space with the y-flip baked into a negative sy.  For a WxH target:
 *    clip.x = px * (2/W) - 1
 *    clip.y = 1 - py*(2/H) = py*(-2/H) + 1
 *  => to_clip = (2/W, -2/H, -1, +1). */
static inline void cm_fill_set_to_clip(cm_uniforms *u, int w, int h) {
    float fw = (w > 0) ? (float)w : 1.0f;
    float fh = (h > 0) ? (float)h : 1.0f;
    u->to_clip[0] =  2.0f / fw;   /* sx */
    u->to_clip[1] = -2.0f / fh;   /* sy (y flipped) */
    u->to_clip[2] = -1.0f;        /* tx */
    u->to_clip[3] =  1.0f;        /* ty */
}

/** Carry the CTM into the uniform's two float4 rows (for completeness; the
 *  shipping path pre-transforms on the CPU, so the GPU does not re-apply this).
 *    row0 = (xx, xy, x0, _)   row1 = (yx, yy, y0, _). */
static inline void cm_fill_set_ctm_rows(cm_uniforms *u, const cm_matrix_t *m) {
    u->ctm_row0[0] = (float)m->xx; u->ctm_row0[1] = (float)m->xy;
    u->ctm_row0[2] = (float)m->x0; u->ctm_row0[3] = 0.0f;
    u->ctm_row1[0] = (float)m->yx; u->ctm_row1[1] = (float)m->yy;
    u->ctm_row1[2] = (float)m->y0; u->ctm_row1[3] = 0.0f;
}

/** Write the 4 triangle-strip corners of the device-space bounding box into
 *  `quad`.  Strip order matches cm_compose.m / the original cover quad:
 *  (minx,miny) (maxx,miny) (minx,maxy) (maxx,maxy). */
static inline void cm_fill_fill_quad(cm_vec2f *quad,
                                     float minx, float miny,
                                     float maxx, float maxy) {
    quad[0].x = minx; quad[0].y = miny;
    quad[1].x = maxx; quad[1].y = miny;
    quad[2].x = minx; quad[2].y = maxy;
    quad[3].x = maxx; quad[3].y = maxy;
}

/** True when the fill target is an alpha-only surface (A8 -> R8 texture), so the
 *  SOLID cover must route through the A8 cover pipeline (coverage into .r). */
static inline bool cm_fill_target_is_a8(const cm_context_t *ctx) {
    return ctx && ctx->surface && ctx->surface->format == CM_FORMAT_A8;
}

// ===========================================================================
// Analytic coverage (cairo's area antialiasing, for the common draws)
// ===========================================================================
//
// The stencil-then-cover path antialiases with the frame's 4x MSAA: an edge
// pixel can only be 0, 1/4, 1/2, 3/4 or 1 covered, up to ~60 levels away from
// what cairo's image backend gives it (cairo measures the covered AREA).  For
// the draws manim makes -- OVER, unclipped, default antialias, solid or
// gradient paint, an ARGB32/RGB24 target -- this path measures the coverage
// instead: the path's edges, binned by pixel row, go to the cm_fs_acov_* cover
// fragments (shaders/fill.metal).  Anything else, or a pathological path
// (more than CM_ACOV_MAX_ROW edges crossing one pixel row), keeps the stencil
// path.  Which antialias settings take it: cm_fill_analytic_wanted.

typedef struct {             // mirrors cm_acov_params in fill.metal (192 bytes)
    int32_t row0, nrows, evenodd, nstops;
    float   solid[4];        // premultiplied as cairo rounds it, /255
    float   stop_x[8];
    float   stop_c[8][4];
} cm_acov_params;
_Static_assert(sizeof(cm_acov_params) == 192, "cm_acov_params layout");

/* cairo's colour -> pixman: a double channel becomes a 16-bit short,
 * d * 65535 + 0.5 truncated (_cairo_color_double_to_short). */
static inline uint32_t cm_acov_short(double d)
{
    if (d <= 0.0) return 0;
    if (d >= 1.0) return 65535;
    return (uint32_t)(d * 65535.0 + 0.5);
}

/* The solid source as pixman composites it: premultiplied shorts, then the
 * top byte of each (a solid pixman image is a8r8g8b8). */
static void cm_acov_solid(const cm_rgba *c, float out[4])
{
    double a = c->a;
    out[0] = (float)(cm_acov_short(c->r * a) >> 8) / 255.0f;
    out[1] = (float)(cm_acov_short(c->g * a) >> 8) / 255.0f;
    out[2] = (float)(cm_acov_short(c->b * a) >> 8) / 255.0f;
    out[3] = (float)(cm_acov_short(a) >> 8) / 255.0f;
}

/* A linear gradient's stops as pixman gets them: sorted (stable), offsets
 * clamped to [0,1], colours as unpremultiplied shorts.  0 stops (more than
 * the shader takes) leaves the gradient on the LUT. */
static int cm_acov_stops(const cm_pattern_t *pat, cm_acov_params *P)
{
    uint32_t n = pat->stop_count;
    if (n == 0 || n > 8) return 0;
    cm_grad_stop st[8];
    for (uint32_t i = 0; i < n; ++i) {
        st[i] = pat->stops[i];
        if (st[i].offset < 0.0) st[i].offset = 0.0;
        if (st[i].offset > 1.0) st[i].offset = 1.0;
    }
    for (uint32_t i = 1; i < n; ++i) {
        cm_grad_stop k = st[i];
        int32_t j = (int32_t)i - 1;
        while (j >= 0 && st[j].offset > k.offset) { st[j + 1] = st[j]; --j; }
        st[j + 1] = k;
    }
    for (uint32_t i = 0; i < n; ++i) {
        P->stop_x[i] = (float)st[i].offset;
        P->stop_c[i][0] = cm_acov_short(st[i].color.r) / 65535.0f;
        P->stop_c[i][1] = cm_acov_short(st[i].color.g) / 65535.0f;
        P->stop_c[i][2] = cm_acov_short(st[i].color.b) / 65535.0f;
        P->stop_c[i][3] = cm_acov_short(st[i].color.a) / 65535.0f;
    }
    return (int)n;
}

#define CM_ACOV_MAX_ROW 256

/* Which draws measure their coverage.  It costs GPU time: on manim scenes a
 * frame's GPU work grows ~4-7 ms at 1080p, which leaves a render about as
 * fast as software cairo, where the stencil path is 1.5-4x faster.  So it is
 * what cairo's antialias setting asks for: GOOD and BEST measure, DEFAULT and
 * FAST take the 4x MSAA stencil path.  CM_ANALYTIC_AA=1 in the environment
 * measures every draw (an app that wants cairo's pixels everywhere), =0 none.
 *   g_cm_analytic: -1 unread, 0 none, 1 GOOD/BEST only, 2 every draw. */
static int g_cm_analytic = -1;

static int cm_fill_analytic_mode(void)
{
    if (g_cm_analytic < 0) {
        const char *e = getenv("CM_ANALYTIC_AA");
        g_cm_analytic = (e && e[0] == '0') ? 0 : (e && e[0] == '1') ? 2 : 1;
    }
    return g_cm_analytic;
}

static bool cm_fill_analytic_wanted(cm_antialias_t aa)
{
    int mode = cm_fill_analytic_mode();
    if (mode == 2) return aa != CM_ANTIALIAS_NONE;
    if (mode == 1) return aa == CM_ANTIALIAS_GOOD || aa == CM_ANTIALIAS_BEST;
    return false;
}

/* Diagnostics (cairo_metal._set_analytic_aa): 0 none, 1 GOOD/BEST, 2 every
 * draw -- so a benchmark can alternate the paths in one process. */
void cm_debug_set_analytic_aa(int mode) { g_cm_analytic = mode < 0 ? 0 : mode > 2 ? 2 : mode; }

/** Encode `path` with analytic coverage.  Returns false, having encoded
 *  nothing, when the draw is not one this path takes (the caller then runs
 *  the stencil path); true when it was handled (drawn, or nothing visible).
 *
 *  Three draws: the usual stencil fans (winding per sample); the EDGE SPANS
 *  -- in each pixel row, the runs of pixels some edge passes through --
 *  measured by cm_fs_acov_* and zeroing the stencil under them; then the
 *  usual stencil-tested cover quad, at full coverage, for the pixels left
 *  (wholly inside: no edge passes through them, so every sample agrees).  Only
 *  edge pixels pay for the measurement; measuring every pixel of the path made
 *  a frame's GPU time 2-4x the stencil path's. */
static bool cm_fill_encode_analytic(cm_context_t *ctx, cm_frame *frame,
                                    const cm_path *path, cm_fill_rule_t rule,
                                    cm_device *dev, id<MTLRenderCommandEncoder> enc,
                                    cm_status_t *out_status)
{
    *out_status = CM_STATUS_SUCCESS;
    if (!cm_fill_analytic_wanted(ctx->antialias)) return false;
    if (cm_frame_is_single_sample(frame)) return false;
    if (ctx->op != CM_OPERATOR_OVER || ctx->clip != NULL) return false;
    if (!ctx->surface) return false;
    // Plain image surfaces only: a subsurface draws into its parent's backing
    // through a scissored window, and a device offset shifts the pixels -- the
    // stencil path keeps those.
    if (ctx->surface->kind != CM_SURFACE_TYPE_IMAGE ||
        ctx->surface->dev_off_x != 0.0 || ctx->surface->dev_off_y != 0.0) return false;
    cm_format_t fmt = ctx->surface->format;
    if (fmt != CM_FORMAT_ARGB32 && fmt != CM_FORMAT_RGB24) return false;
    cm_paint_kind kind = ctx->source.kind;
    if (kind != CM_PAINT_SOLID && kind != CM_PAINT_LINEAR && kind != CM_PAINT_RADIAL)
        return false;
    if (kind != CM_PAINT_SOLID && !ctx->source.pattern) return false;

    id<MTLRenderPipelineState> ps_edge =
        (__bridge id<MTLRenderPipelineState>)cm_device_acov_pipeline(dev, kind, false);
    id<MTLRenderPipelineState> ps_full =
        (__bridge id<MTLRenderPipelineState>)cm_device_acov_pipeline(dev, kind, true);
    id<MTLRenderPipelineState> ps_stencil = (__bridge id<MTLRenderPipelineState>)
        cm_device_pipeline(dev, rule == CM_FILL_RULE_EVEN_ODD ? CM_PIPE_STENCIL_EVENODD
                                                               : CM_PIPE_STENCIL_NONZERO);
    id<MTLDepthStencilState> ds_zero = (__bridge id<MTLDepthStencilState>)cm_device_dss_none(dev);
    id<MTLDepthStencilState> ds_stencil = (__bridge id<MTLDepthStencilState>)
        cm_device_depthstencil(dev, rule == CM_FILL_RULE_EVEN_ODD ? CM_DSS_STENCIL_WRITE_EVENODD
                                                                   : CM_DSS_STENCIL_WRITE_NONZERO);
    id<MTLDepthStencilState> ds_cover = (__bridge id<MTLDepthStencilState>)
        cm_device_depthstencil(dev, rule == CM_FILL_RULE_EVEN_ODD ? CM_DSS_COVER_TEST_EVENODD
                                                                   : CM_DSS_COVER_TEST_NONZERO);
    if (!ps_edge || !ps_full || !ps_stencil || !ds_zero || !ds_stencil || !ds_cover) return false;

    // ---- the visible rows / columns of the path's bounds -------------------
    int W = ctx->surface->width, H = ctx->surface->height;
    float minx, miny, maxx, maxy;
    cm_path_bounds(path, &minx, &miny, &maxx, &maxy);
    if (!(maxx > minx) || !(maxy > miny)) return true;          // no area
    int row0 = (int)floorf(miny), row1 = (int)ceilf(maxy);
    int col0 = (int)floorf(minx), col1 = (int)ceilf(maxx);
    if (row0 < 0) row0 = 0;
    if (col0 < 0) col0 = 0;
    if (row1 > H) row1 = H;
    if (col1 > W) col1 = W;
    if (row1 <= row0 || col1 <= col0) return true;              // off-surface
    if (col1 > 0xffff) return false;                            // span x packs in 16 bits
    int nrows = row1 - row0;

    uint32_t fan_vtx = cm_path_fan_vertex_count(path);
    if (fan_vtx == 0) return true;

    // ---- each row's edges, as packed float4s (fill.metal) ------------------
    // A horizontal edge is listed in the row it lies in (unless it lies on a
    // row boundary) so the pixels it crosses count as edge pixels; it never
    // winds.
    uint32_t *start = (uint32_t *)malloc((size_t)(nrows + 1) * sizeof(uint32_t));
    if (!start) { *out_status = CM_STATUS_NO_MEMORY; return true; }
    memset(start, 0, (size_t)(nrows + 1) * sizeof(uint32_t));
    size_t total = 0;
#define CM_ACOV_EACH_EDGE(...)                                                    \
    for (uint32_t ci = 0; ci < path->contour_count; ++ci) {                       \
        uint32_t n = path->contours[ci].point_count;                              \
        if (n < 2) continue;                                                      \
        const cm_vec2f *pt = path->pts + path->contours[ci].first_point;          \
        for (uint32_t i = 0; i < n; ++i) {                                        \
            cm_vec2f a = pt[i], b = pt[(i + 1) % n];   /* fills close contours */ \
            if (a.x == b.x && a.y == b.y) continue;                               \
            cm_vec2f t = a.y < b.y ? a : b, u = a.y < b.y ? b : a;                \
            int ra, rb;                                                           \
            if (a.y == b.y) {                                                     \
                if (a.y == floorf(a.y)) continue;      /* on a row boundary */    \
                ra = (int)floorf(a.y) - row0; rb = ra + 1;                        \
            } else {                                                              \
                ra = (int)floorf(t.y) - row0; rb = (int)ceilf(u.y) - row0;        \
            }                                                                     \
            if (ra < 0) ra = 0;                                                   \
            if (rb > nrows) rb = nrows;                                           \
            if (rb <= ra) continue;                                               \
            __VA_ARGS__                                                           \
        }                                                                         \
    }
    CM_ACOV_EACH_EDGE({ for (int r = ra; r < rb; ++r) start[r + 1]++; total += (size_t)(rb - ra); })
    if (total == 0) { free(start); return true; }
    for (int r = 0; r < nrows; ++r)
        if (start[r + 1] > CM_ACOV_MAX_ROW) { free(start); return false; }  // stencil path
    for (int r = 0; r < nrows; ++r) start[r + 1] += start[r];

    void *edge_buf = NULL; uint32_t edge_off = 0;
    float *edges = (float *)cm_frame_alloc_verts(frame, total * 4 * sizeof(float),
                                                 &edge_buf, &edge_off);
    // Each entry's pixel extent in its row, for the spans.
    int32_t *ext = (int32_t *)malloc(total * 2 * sizeof(int32_t));
    if (!edges || !ext) { free(start); free(ext); *out_status = CM_STATUS_NO_MEMORY; return true; }
    // start[r] serves as row r's write cursor, then is shifted back.
    CM_ACOV_EACH_EDGE({
        bool flat = (a.y == b.y);
        float lx = fminf(a.x, b.x);
        float dxdy = flat ? fabsf(b.x - a.x) : (u.x - t.x) / (u.y - t.y);
        for (int r = ra; r < rb; ++r) {
            size_t k = start[r]++;
            float *e = edges + 4 * k;
            e[0] = flat ? lx : t.x; e[1] = a.y; e[2] = b.y; e[3] = dxdy;
            float xa, xb;
            if (flat) { xa = lx; xb = lx + dxdy; }
            else {
                float y0 = fmaxf(t.y, (float)(row0 + r)), y1 = fminf(u.y, (float)(row0 + r + 1));
                xa = t.x + (y0 - t.y) * dxdy; xb = t.x + (y1 - t.y) * dxdy;
            }
            ext[2 * k]     = (int32_t)floorf(fminf(xa, xb));
            ext[2 * k + 1] = (int32_t)ceilf(fmaxf(xa, xb));
        }
    })
#undef CM_ACOV_EACH_EDGE
    for (int r = nrows; r > 0; --r) start[r] = start[r - 1];
    start[0] = 0;

    // ---- edge spans: each row's edge extents, sorted and merged ------------
    // Per row (first edge, count, first span, span count); spans packed x0 |
    // x1 << 16.
    void *rows_buf = NULL, *span_buf = NULL; uint32_t rows_off = 0, span_off = 0;
    uint32_t *rows  = (uint32_t *)cm_frame_alloc_verts(frame, (size_t)nrows * 4 * sizeof(uint32_t),
                                                       &rows_buf, &rows_off);
    uint32_t *spans = (uint32_t *)cm_frame_alloc_verts(frame, total * sizeof(uint32_t),
                                                       &span_buf, &span_off);
    if (!rows || !spans) { free(start); free(ext); *out_status = CM_STATUS_NO_MEMORY; return true; }
    uint32_t nspans = 0;
    for (int r = 0; r < nrows; ++r) {
        uint32_t b = start[r], e = start[r + 1];
        rows[4 * r + 0] = b; rows[4 * r + 1] = e - b; rows[4 * r + 2] = nspans;
        // insertion sort of the row's extents by their start
        for (uint32_t i = b + 1; i < e; ++i) {
            int32_t k0 = ext[2 * i], k1 = ext[2 * i + 1];
            uint32_t j = i;
            while (j > b && ext[2 * (j - 1)] > k0) {
                ext[2 * j] = ext[2 * (j - 1)]; ext[2 * j + 1] = ext[2 * (j - 1) + 1]; --j;
            }
            ext[2 * j] = k0; ext[2 * j + 1] = k1;
        }
        int32_t cx0 = 0, cx1 = -1;
        for (uint32_t i = b; i <= e; ++i) {
            bool flush = (i == e) || (ext[2 * i] > cx1);
            if (flush && cx1 > cx0) {
                int32_t x0 = cx0 < col0 ? col0 : cx0, x1 = cx1 > col1 ? col1 : cx1;
                if (x1 > x0) spans[nspans++] = (uint32_t)x0 | ((uint32_t)x1 << 16);
            }
            if (i == e) break;
            if (flush) { cx0 = ext[2 * i]; cx1 = ext[2 * i + 1]; }
            else if (ext[2 * i + 1] > cx1) cx1 = ext[2 * i + 1];
        }
        rows[4 * r + 3] = nspans - rows[4 * r + 2];
    }
    free(start); free(ext);

    // ---- uniforms + paint ---------------------------------------------------
    void *uni_buf = NULL; uint32_t uni_off = 0;
    cm_uniforms *uf = (cm_uniforms *)cm_frame_alloc_uniforms(frame, sizeof(cm_uniforms),
                                                             &uni_buf, &uni_off);
    if (!uf) { *out_status = CM_STATUS_NO_MEMORY; return true; }
    memset(uf, 0, sizeof(*uf));
    cm_paint_fill_uniforms(&ctx->source, &ctx->ctm, uf);
    cm_fill_set_to_clip(uf, W, H);
    cm_fill_set_ctm_rows(uf, &ctx->ctm);
    uf->operator = (int)ctx->op;

    id<MTLTexture> lut = nil;
    if (kind != CM_PAINT_SOLID) {
        lut = (__bridge id<MTLTexture>)cm_paint_gradient_lut(dev, ctx->source.pattern);
        if (!lut) return false;     // let the stencil path apply its fallback
    }
    cm_acov_params P;
    memset(&P, 0, sizeof(P));
    P.row0 = row0; P.nrows = nrows; P.evenodd = (rule == CM_FILL_RULE_EVEN_ODD) ? 1 : 0;
    if (kind == CM_PAINT_SOLID) cm_acov_solid(&ctx->source.solid, P.solid);
    else if (kind == CM_PAINT_LINEAR) P.nstops = cm_acov_stops(ctx->source.pattern, &P);

    // ---- geometry: the fans and the interior cover's quad -------------------
    void *fan_buf = NULL; uint32_t fan_off = 0;
    cm_vec2f *fan = (cm_vec2f *)cm_frame_alloc_verts(frame, (size_t)fan_vtx * sizeof(cm_vec2f),
                                                     &fan_buf, &fan_off);
    void *quad_buf = NULL; uint32_t quad_off = 0;
    cm_vec2f *quad = (cm_vec2f *)cm_frame_alloc_verts(frame, CM_COVER_QUAD_VERTS * sizeof(cm_vec2f),
                                                      &quad_buf, &quad_off);
    if (!fan || !quad) { *out_status = CM_STATUS_NO_MEMORY; return true; }
    uint32_t written = 0;
    for (uint32_t ci = 0; ci < path->contour_count; ++ci)
        written += cm_path_emit_fan(path, ci, fan + written);
    if (written > fan_vtx) { *out_status = CM_STATUS_NO_MEMORY; return true; }
    cm_fill_fill_quad(quad, (float)col0, (float)row0, (float)col1, (float)row1);

    // ---- 1: fans -> winding per sample (no colour) ---------------------------
    [enc setCullMode:MTLCullModeNone];
    [enc setFrontFacingWinding:MTLWindingCounterClockwise];
    [enc setStencilReferenceValue:0];
    [enc setRenderPipelineState:ps_stencil];
    [enc setDepthStencilState:ds_stencil];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)fan_buf offset:fan_off atIndex:CM_BUF_VERTS];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_buf offset:uni_off atIndex:CM_BUF_UNIFORMS];
    if (written) [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:written];

    // ---- 2: edge pixels measured (the quad, spans looked up per pixel); the
    //         stencil under them zeroed --------------------------------------
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)quad_buf offset:quad_off atIndex:CM_BUF_VERTS];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)uni_buf offset:uni_off atIndex:CM_BUF_UNIFORMS];
    [enc setFragmentBytes:&P length:sizeof(P) atIndex:5];
    if (lut) [enc setFragmentTexture:lut atIndex:CM_TEX_GRAD_LUT];
    if (nspans) {
        [enc setRenderPipelineState:ps_edge];
        [enc setDepthStencilState:ds_zero];
        [enc setFragmentBuffer:(__bridge id<MTLBuffer>)edge_buf offset:edge_off atIndex:2];
        [enc setFragmentBuffer:(__bridge id<MTLBuffer>)rows_buf offset:rows_off atIndex:3];
        [enc setFragmentBuffer:(__bridge id<MTLBuffer>)span_buf offset:span_off atIndex:4];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0
                vertexCount:CM_COVER_QUAD_VERTS];
    }

    // ---- 3: the interior, through the stencil, at full coverage -------------
    [enc setRenderPipelineState:ps_full];
    [enc setDepthStencilState:ds_cover];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0
            vertexCount:CM_COVER_QUAD_VERTS];

    ctx->last_pipeline_group = kind;
    ctx->status = CM_STATUS_SUCCESS;
    return true;
}

// ===========================================================================
// cm_fill_encode
// ===========================================================================
//
// Encode a full stencil-then-cover fill of `path` (already device-space
// flattened by the caller) with the context's current paint, operator, and
// clip into the frame's render command encoder.  Returns CM_STATUS_SUCCESS on
// success (a degenerate / empty path is a successful no-op).
//
// The structure is the SAME two passes for every paint kind; only the cover
// pass's pipeline + bound resources + (for MESH) cover geometry differ:
//
//   1) bump-allocate + fill the stencil fan vertices (path contours);
//   2) bump-allocate + build the per-draw uniforms (paint + operator + to_clip);
//   3) resolve the operator-selected cover pipeline + the per-kind GPU resources
//      (gradient LUT / source texture+sampler / Gouraud triangle stream);
//   4) PASS 1 stencil (winding/parity), PASS 2 cover (test stencil + paint),
//      binding the clip mask to the cover stage.
//
cm_status_t
cm_fill_encode(cm_context_t *ctx, cm_frame *frame,
               const cm_path *path, cm_fill_rule_t rule)
{
    if (!ctx || !frame || !path) {
        return CM_STATUS_DEVICE_ERROR;
    }

    // The path must already be flattened (device space) by the caller
    // (cairo_metal.m drives flatten -> fill).  Nothing to fill if it produced no
    // geometry -- a valid no-op, e.g. an empty or fully-degenerate path.
    if (path->pts_count == 0 || path->contour_count == 0) {
        return CM_STATUS_SUCCESS;
    }

    // ---- how many stencil-fan vertices does the whole path need? -----------
    uint32_t fan_vtx = cm_path_fan_vertex_count(path);
    if (fan_vtx == 0) {
        // Every contour was degenerate (<3 points): no fillable area.
        return CM_STATUS_SUCCESS;
    }

    cm_device *dev = cm_frame_device(frame);
    if (!dev) {
        return CM_STATUS_DEVICE_ERROR;
    }
    id<MTLRenderCommandEncoder> enc =
        (__bridge id<MTLRenderCommandEncoder>)cm_frame_encoder(frame);
    if (!enc) {
        return CM_STATUS_DEVICE_ERROR;
    }

    // The common draws take the analytic-coverage path (cairo's antialiasing).
    {
        cm_status_t ast = CM_STATUS_SUCCESS;
        if (cm_fill_encode_analytic(ctx, frame, path, rule, dev, enc, &ast)) {
            if (ast != CM_STATUS_SUCCESS) ctx->status = ast;
            return ast;
        }
    }

    // -----------------------------------------------------------------------
    // 1) Bump-allocate + fill the stencil-fan vertex buffer (no malloc).
    // -----------------------------------------------------------------------
    void    *fan_mtlbuf = NULL;
    uint32_t fan_offset = 0;
    cm_vec2f *fan_dst = (cm_vec2f *)cm_frame_alloc_verts(
        frame, (size_t)fan_vtx * sizeof(cm_vec2f), &fan_mtlbuf, &fan_offset);
    if (!fan_dst || !fan_mtlbuf) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }

    // Emit each contour's fan; cm_path_emit_fan returns the count it appended
    // (0 for a degenerate contour), so we advance the write cursor by it.  The
    // total is exactly fan_vtx, matching the allocation above.
    uint32_t written = 0;
    for (uint32_t ci = 0; ci < path->contour_count; ++ci) {
        uint32_t n = cm_path_emit_fan(path, ci, fan_dst + written);
        written += n;
    }
    // Defensive: never exceed the allocation (would corrupt the ring).
    if (written > fan_vtx) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }
    if (written == 0) {
        return CM_STATUS_SUCCESS;   // nothing fillable after all
    }

    // -----------------------------------------------------------------------
    // 2) Path device-space bounds (the cover quad for the quad-cover kinds).
    //    A zero-area bound is nothing to cover -- a valid no-op.
    // -----------------------------------------------------------------------
    float minx, miny, maxx, maxy;
    cm_path_bounds(path, &minx, &miny, &maxx, &maxy);
    if (!(maxx > minx) || !(maxy > miny)) {
        return CM_STATUS_SUCCESS;   // zero-area bounds: nothing to cover
    }

    // -----------------------------------------------------------------------
    // 3) Bump-allocate + build per-draw uniforms (shared by both passes).
    // -----------------------------------------------------------------------
    void    *uni_mtlbuf = NULL;
    uint32_t uni_offset = 0;
    cm_uniforms *u = (cm_uniforms *)cm_frame_alloc_uniforms(
        frame, sizeof(cm_uniforms), &uni_mtlbuf, &uni_offset);
    if (!u || !uni_mtlbuf) {
        ctx->status = CM_STATUS_NO_MEMORY;
        return CM_STATUS_NO_MEMORY;
    }
    memset(u, 0, sizeof(*u));
    // Paint fields (paint_kind / grad_axis in device space / solid / pat_inv /
    // operator default / global_alpha default) come from the source; we then
    // write to_clip + ctm rows + the live operator LAST so they survive
    // regardless of how much of the struct cm_paint_fill_uniforms touches.
    cm_paint_fill_uniforms(&ctx->source, &ctx->ctm, u);
    cm_fill_set_to_clip(u, ctx->surface ? ctx->surface->width  : 0,
                           ctx->surface ? ctx->surface->height : 0);
    cm_fill_set_ctm_rows(u, &ctx->ctm);
    // Honor set_operator: the programmable-blend cover frags read this, and it is
    // the key cm_device_cover_pipeline selects the fixed-function blend state by.
    u->operator = (int)ctx->op;

    // -----------------------------------------------------------------------
    // 4) Resolve the paint kind + its GPU resources.
    //
    // paint_kind is what cm_paint_fill_uniforms derived (SOLID / LINEAR /
    // RADIAL / SURFACE / MESH).  Each kind may DOWNGRADE to SOLID if its GPU
    // resource is unavailable (LUT bake failed / no source texture / empty mesh)
    // so we never issue a draw that samples a nil texture -- exactly the
    // deterministic fallback cm_compose.m uses.
    // -----------------------------------------------------------------------
    cm_paint_kind paint_kind = (cm_paint_kind)u->paint_kind;

    id<MTLTexture>      src_lut  = nil;   // gradient LUT (LINEAR / RADIAL)
    id<MTLTexture>      src_tex  = nil;   // surface-pattern colour texture
    id<MTLSamplerState> src_samp = nil;   // runtime sampler for the surface
    bool                is_mesh  = false; // MESH: triangles ARE the coverage

    if (paint_kind == CM_PAINT_LINEAR || paint_kind == CM_PAINT_RADIAL) {
        if (ctx->source.pattern)
            src_lut = (__bridge id<MTLTexture>)cm_paint_gradient_lut(dev,
                                                                     ctx->source.pattern);
        if (!src_lut) {
            // LUT bake failed; fall back to solid so we still composite
            // something deterministic rather than sampling a nil texture.
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    } else if (paint_kind == CM_PAINT_SURFACE) {
        cm_surface_t *ssurf = ctx->source.pattern
                            ? cm_pattern_surface_texture(ctx->source.pattern) : NULL;
        if (ssurf) {
            // FLUSH THE SOURCE FIRST: a surface pattern may itself be a draw
            // target with pending GPU work (e.g. a push_group result); resolve it
            // so the texture we sample is coherent.  flush() is a no-op when the
            // source has no in-flight frame.  We must NOT flush our OWN target
            // surface here (that would end the frame we are encoding into), so
            // only flush a DIFFERENT source surface.
            if (ssurf != ctx->surface && ssurf != ctx->target)
                cm_surface_flush(ssurf);
            src_tex = (__bridge id<MTLTexture>)cm_surface_color_texture(ssurf);
        }
        if (src_tex) {
            cm_filter_t f = ctx->source.pattern ? ctx->source.pattern->filter
                                                : CM_FILTER_GOOD;
            cm_extend_t e = ctx->source.pattern ? ctx->source.pattern->extend
                                                : CM_EXTEND_NONE;
            src_samp = (__bridge id<MTLSamplerState>)cm_device_sampler(dev, f, e);
            // Texels are ALREADY premultiplied (cairo ARGB32 source); the surface
            // cover fragment does NOT premultiply again -- nothing to do here.
        } else {
            // No usable source texture: deterministic solid fallback.
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    } else if (paint_kind == CM_PAINT_MESH) {
        // MESH: the per-vertex Gouraud triangles emitted by cm_mesh.c ARE the
        // cover geometry; there is no bounding quad.  We still run the stencil
        // pass so the mesh paints only inside the fill path.
        is_mesh = (ctx->source.pattern != NULL);
        if (!is_mesh) {
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
        }
    }

    // -----------------------------------------------------------------------
    // 5) Resolve the cover pipeline DEFINITIVELY (before allocating cover
    //    geometry), settling the final paint_kind / is_mesh.
    //
    // The operator front-door (cm_compose_operator_pipeline ->
    // cm_device_cover_pipeline) is the single source of truth for the
    // (operator x aa x clip x paint-kind) variant, so every encode site selects
    // pipelines identically and set_operator is honored.  For the default OVER /
    // unclipped / BGRA + SOLID|LINEAR case the device scaffold resolves this to
    // exactly CM_PIPE_COVER_SOLID / _LINEAR, so the shipping path is preserved
    // byte-for-byte.
    //
    // The appended cover variants (RADIAL / SURFACE / GOURAUD / SOLID_A8) are
    // built lazily by the device; until a variant exists the hook falls back to
    // the SOLID cover.  A solid-cover fallback is fine for the quad kinds (it
    // just composites a solid colour), but the GOURAUD cover takes a WIDER
    // cm_vtx_color vertex, so drawing the mesh stream through a non-Gouraud
    // pipeline would misread vertices.  We therefore detect that fallback (the
    // hook handed back CM_PIPE_COVER_SOLID for a non-solid kind) and, for MESH,
    // collapse to the solid quad path instead of streaming Gouraud verts.
    // -----------------------------------------------------------------------
    bool aa_none = (ctx->antialias == CM_ANTIALIAS_NONE);
    // GPU per-pixel clip: only when a NON-RECTANGULAR clip with a built A8 mask is
    // active.  A purely-rectangular clip stays on the fast path (its bounding box
    // already constrains the draw) so the common case pays no clip-sample cost, and
    // a clip whose GPU mask could not be built must NOT select a *_clip fragment
    // (which would sample an unbound texture(1)); it degrades to the CPU-query clip.
    bool clip_on = (ctx->clip != NULL) && !ctx->clip->is_rectangle &&
                   (ctx->clip->mask_tex != NULL);

    // A8 target: SOLID coverage must land in the single alpha channel (R8).  We
    // special-case only SOLID into A8 (the manim A8 use is a coverage/clip mask
    // filled solid); other kinds keep their BGRA cover.
    bool want_a8_solid = (paint_kind == CM_PAINT_SOLID) && cm_fill_target_is_a8(ctx);

    id<MTLRenderPipelineState> ps_solid =
        (__bridge id<MTLRenderPipelineState>)cm_device_pipeline(dev, CM_PIPE_COVER_SOLID);

    id<MTLRenderPipelineState> ps_cover =
        (__bridge id<MTLRenderPipelineState>)
            cm_compose_operator_pipeline(dev, ctx->op, aa_none, clip_on, paint_kind);

    // Did the hook fall back to the plain solid cover for a non-solid kind?
    // (Either the variant is not built yet, or the device genuinely maps this
    // op/kind to the solid pipeline.)  Treat that as "solid cover".
    bool got_solid_cover = (ps_cover == ps_solid) || (ps_cover == nil);

    if (paint_kind != CM_PAINT_SOLID && got_solid_cover) {
        // The kind-specific cover is unavailable.  For the quad kinds we keep the
        // solid fallback (deterministic), dropping the now-unusable source
        // texture/LUT.  For MESH we MUST switch to the quad path (we cannot draw
        // the Gouraud stream through the solid pipeline).
        paint_kind    = CM_PAINT_SOLID;
        u->paint_kind = CM_PAINT_SOLID;
        src_lut = nil; src_tex = nil; src_samp = nil;
        is_mesh = false;
        // Re-evaluate the A8-solid request now that we are solid.
        want_a8_solid = cm_fill_target_is_a8(ctx);
        ps_cover      = ps_solid;
    }

    if (want_a8_solid) {
        // Dedicated A8 (R8) solid cover: writes the source COVERAGE ALPHA into the
        // single channel via cm_fs_cover_solid_a8 -- NOT the BGRA solid fragment's
        // premultiplied colour byte, which would store luminance (opaque
        // black/green -> 0 instead of 255).  Built/cached lazily + operator-aware
        // by the device (cm_device_pipeline(CM_PIPE_COVER_SOLID_A8) is never
        // populated -- the variant table owns it).  Falls back to the BGRA solid
        // only if the R8 variant is unavailable.
        id<MTLRenderPipelineState> ps_a8 =
            (__bridge id<MTLRenderPipelineState>)
                cm_device_cover_pipeline_a8(dev, ctx->op, aa_none, clip_on, CM_PAINT_SOLID);
        if (ps_a8) ps_cover = ps_a8;
    }
    if (!ps_cover) ps_cover = ps_solid;   // never issue a nil-pipeline draw

    // -----------------------------------------------------------------------
    // 6) Bump-allocate the cover geometry now that the kind is settled.
    //    MESH streams the Gouraud triangles (cm_vtx_color, wider than cm_vec2f,
    //    so its own ring sub-allocation); every other kind draws the device-space
    //    bounding quad.
    // -----------------------------------------------------------------------
    void    *mesh_mtlbuf  = NULL;
    uint32_t mesh_offset  = 0;
    uint32_t mesh_vtx     = 0;
    void    *quad_mtlbuf  = NULL;
    uint32_t quad_offset  = 0;

    if (is_mesh) {
        uint32_t mverts = cm_mesh_triangle_vertex_count(ctx->source.pattern, &ctx->ctm);
        cm_vtx_color *mdst = (mverts > 0)
            ? (cm_vtx_color *)cm_frame_alloc_verts(
                  frame, (size_t)mverts * sizeof(cm_vtx_color),
                  &mesh_mtlbuf, &mesh_offset)
            : NULL;
        if (mverts > 0 && (!mdst || !mesh_mtlbuf)) {
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        mesh_vtx = (mdst != NULL)
            ? cm_mesh_emit_triangles(ctx->source.pattern, &ctx->ctm, mdst) : 0;
        if (mesh_vtx > mverts) {        // emit must not exceed the size it asked for
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        if (mesh_vtx == 0) {
            // Empty tessellation: collapse to a solid quad fill so the stencilled
            // path still composites the solid fallback deterministically.
            is_mesh       = false;
            paint_kind    = CM_PAINT_SOLID;
            u->paint_kind = CM_PAINT_SOLID;
            ps_cover      = ps_solid;
            if (cm_fill_target_is_a8(ctx)) {
                id<MTLRenderPipelineState> ps_a8 =
                    (__bridge id<MTLRenderPipelineState>)
                        cm_device_cover_pipeline_a8(dev, ctx->op, aa_none, clip_on,
                                                    CM_PAINT_SOLID);
                if (ps_a8) ps_cover = ps_a8;
            }
        }
    }
    if (!is_mesh) {
        cm_vec2f *quad = (cm_vec2f *)cm_frame_alloc_verts(
            frame, (size_t)CM_COVER_QUAD_VERTS * sizeof(cm_vec2f),
            &quad_mtlbuf, &quad_offset);
        if (!quad || !quad_mtlbuf) {
            ctx->status = CM_STATUS_NO_MEMORY;
            return CM_STATUS_NO_MEMORY;
        }
        cm_fill_fill_quad(quad, minx, miny, maxx, maxy);
    }

    // -----------------------------------------------------------------------
    // 7) Resolve the stencil pipeline + the two depth-stencil states (O(1)).
    // -----------------------------------------------------------------------
    cm_pipe_id stencil_pipe = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_PIPE_STENCIL_EVENODD : CM_PIPE_STENCIL_NONZERO;
    cm_dss_id  stencil_dss  = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_DSS_STENCIL_WRITE_EVENODD : CM_DSS_STENCIL_WRITE_NONZERO;
    cm_dss_id  cover_dss    = (rule == CM_FILL_RULE_EVEN_ODD)
        ? CM_DSS_COVER_TEST_EVENODD : CM_DSS_COVER_TEST_NONZERO;

    // ANTIALIAS_NONE renders into a 1-sample pass: use the 1-sample stencil
    // pipeline (the MSAA CM_PIPE_STENCIL_* would mismatch the pass's sample count).
    // The cover pipeline already came from the aa_none variant cells above, and the
    // depth-stencil STATES are sample-count-independent so they are reused.
    id<MTLRenderPipelineState> ps_stencil =
        cm_frame_is_single_sample(frame)
            ? (__bridge id<MTLRenderPipelineState>)
                  cm_device_stencil_pipeline_aa_none(dev, rule == CM_FILL_RULE_EVEN_ODD)
            : (__bridge id<MTLRenderPipelineState>)cm_device_pipeline(dev, stencil_pipe);
    id<MTLDepthStencilState>   ds_stencil =
        (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, stencil_dss);
    id<MTLDepthStencilState>   ds_cover =
        (__bridge id<MTLDepthStencilState>)cm_device_depthstencil(dev, cover_dss);
    if (!ps_stencil || !ds_stencil || !ps_cover || !ds_cover) {
        ctx->status = CM_STATUS_DEVICE_ERROR;
        return CM_STATUS_DEVICE_ERROR;
    }

    // Two-sided stencil (NONZERO) needs BOTH faces rasterized so the front/back
    // incr/decr-wrap ops can accumulate winding; never cull.  Front-facing =
    // CCW matches the "fans emitted CCW" convention in DESIGN.md (and the
    // cover-pass !=0 test is sign-agnostic, so the exact front/back->incr/decr
    // assignment in the DSS does not change the result).
    [enc setCullMode:MTLCullModeNone];
    [enc setFrontFacingWinding:MTLWindingCounterClockwise];

    // =======================================================================
    // PASS 1 -- STENCIL (no colour; pipeline masks colour writes off)
    // =======================================================================
    [enc setRenderPipelineState:ps_stencil];
    [enc setDepthStencilState:ds_stencil];
    // Reference 0: harmless for the write ops (incr/decr-wrap, invert ignore it)
    // and is what the cover pass compares against, so set it once consistently.
    [enc setStencilReferenceValue:0];

    [enc setVertexBuffer:(__bridge id<MTLBuffer>)fan_mtlbuf
                  offset:fan_offset
                 atIndex:CM_BUF_VERTS];
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                  offset:uni_offset
                 atIndex:CM_BUF_UNIFORMS];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle
            vertexStart:0
            vertexCount:written];

    // =======================================================================
    // PASS 2 -- COVER (test stencil + zero it; write premultiplied paint)
    // =======================================================================
    [enc setRenderPipelineState:ps_cover];
    [enc setDepthStencilState:ds_cover];
    // Stencil reference already 0 from the stencil pass; the cover DSS tests
    // NotEqual(ref=0) (nonzero) or NotEqual(ref=0, readMask=1) (even-odd).

    // Vertex buffer(0): the cover quad for quad kinds, or the Gouraud triangle
    // stream for MESH (cm_vs_cover_color reads cm_vtx_color from buffer(0)).
    if (is_mesh) {
        [enc setVertexBuffer:(__bridge id<MTLBuffer>)mesh_mtlbuf
                      offset:mesh_offset
                     atIndex:CM_BUF_VERTS];
    } else {
        [enc setVertexBuffer:(__bridge id<MTLBuffer>)quad_mtlbuf
                      offset:quad_offset
                     atIndex:CM_BUF_VERTS];
    }
    [enc setVertexBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                  offset:uni_offset
                 atIndex:CM_BUF_UNIFORMS];
    [enc setFragmentBuffer:(__bridge id<MTLBuffer>)uni_mtlbuf
                    offset:uni_offset
                   atIndex:CM_BUF_UNIFORMS];

    // Source texture / LUT at texture(0) (+ runtime sampler for SURFACE).  MESH
    // and SOLID bind no source texture (their colour is per-vertex / uniform).
    if (src_lut) {
        [enc setFragmentTexture:src_lut atIndex:CM_TEX_GRAD_LUT];
    } else if (src_tex) {
        [enc setFragmentTexture:src_tex atIndex:CM_TEX_SOURCE];
        if (src_samp) [enc setFragmentSamplerState:src_samp atIndex:CM_SAMPLER_SOURCE];
    }

    // Bind the active clip A8 coverage plane + its sampler to the cover fragment
    // stage (texture(1)/sampler(1)); the cover frags multiply their coverage by
    // the sampled mask.  No-op when unclipped or the GPU mask was not built.
    cm_clip_bind((__bridge void *)enc, ctx->clip);

    if (is_mesh) {
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:mesh_vtx];
    } else {
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:CM_COVER_QUAD_VERTS];
    }

    // Record the pipeline group of the draw we just finished so the batching
    // driver in cairo_metal.m can coalesce runs that share a cover pipeline
    // (e.g. many solid fills) and skip redundant state churn within the frame.
    ctx->last_pipeline_group = paint_kind;

    ctx->status = CM_STATUS_SUCCESS;
    return CM_STATUS_SUCCESS;
}

// ===========================================================================
// Non-preserve fill / stroke (= the preserve variant + clear the path)
// ===========================================================================
//
// cairo_fill / cairo_stroke are exactly the _preserve variant followed by an
// implicit new_path (the path is consumed).
//
//   cm_fill   : cm_fill_preserve already flattens + runs cm_fill_encode with the
//               current source + fill rule, and cm_fill_encode now honors the
//               operator + clip + per-kind paint dispatch (LINEAR/RADIAL/SURFACE/
//               MESH + A8), so the non-preserve form is just that + new_path.
//   cm_stroke : cm_stroke_preserve (cairo_metal.m) does the WHOLE stroke encode --
//               flatten -> dash pre-pass (cm_dash_prepass, honoring an active
//               cairo_set_dash by chopping BEFORE cm_stroke_expand) -> expand ->
//               NONZERO cm_fill_encode with the operator + clip -- so the
//               non-preserve form is just that + new_path, exactly cairo's
//               stroke == stroke_preserve + new_path with no separate dashed fork.

void cm_fill(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_fill_preserve(ctx);     // flatten + stencil-then-cover (operator + clip)
    cm_new_path(ctx);          // cairo_fill CONSUMES the path
}

void cm_stroke(cm_context_t *ctx)
{
    if (!ctx) return;
    cm_stroke_preserve(ctx);   // flatten -> dash pre-pass -> expand -> NONZERO fill
    cm_new_path(ctx);          // cairo_stroke CONSUMES the path
}
