/*
 * examples/demo.m  --  CairoMetal smoke test
 * ============================================================================
 * Renders five shapes through the *public* CairoMetal C API
 * (include/cairo_metal.h) into an IOSurface-backed ARGB32 surface, then writes
 * the result to a PNG so the output can be eyeballed:
 *
 *   1. A filled cubic-Bezier path WITH A HOLE
 *      (outer ring CCW, inner ring CW; default NONZERO winding => donut).
 *   2. A linear-gradient fill (LinearGradient + two colour stops).
 *   3. A stroked path with ROUND joins (set_line_join ROUND, stroke_preserve).
 *   4. A DASHED stroke (set_dash): one straight line drawn as separate,
 *      round-capped on-pieces (exercises cm_dash_apply in the stroke path).
 *   5. A DASHED stroke via the NON-PRESERVE cm_stroke() (vs stroke_preserve in
 *      #4): exercises the consolidated stroke path -- cm_stroke delegates to the
 *      dash-aware cm_stroke_preserve + new_path -- and that it CONSUMES the path.
 *
 * Every shape is built only from the cm_* calls manim's camera.py uses:
 * move_to / line_to / curve_to / close_path, fill_preserve / stroke_preserve,
 * set_source_rgba / LinearGradient, set_line_width / set_line_join.
 *
 * PIXEL CONTRACT: the surface is cairo FORMAT_ARGB32 == native-endian
 * premultiplied B,G,R,A. We read it back with cm_surface_map_argb32() and hand
 * those exact bytes to CoreGraphics as
 *   kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
 * which IS premultiplied BGRA on little-endian arm64 -- no swizzle, matching
 * the library's contract. Colours below are passed (r,g,b,a) exactly as a
 * cairo caller would; we are NOT emulating manim's B,G,R pre-swap here (this is
 * a direct cairo-style client), so the written PNG shows colours in the natural
 * sense for a standalone test.
 *
 * Build:  make demo   (or `make run` to build + render build/demo.png)
 * Run:    ./build/demo [out.png]      (defaults to demo.png in the CWD)
 *
 * Metal library: the device module (cm_device.m) loads the compiled shaders.
 * `make` produces build/default.metallib and `make run` exports
 * CM_METALLIB=<abs path> so the device module can find it even when this demo
 * is launched outside an app bundle.
 * ============================================================================
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "cairo_metal.h"

/* ----------------------------------------------------------------------------
 * Geometry helpers (cubic-Bezier circle/arc construction)
 * ------------------------------------------------------------------------- */

/* 4/3 * (sqrt(2) - 1): control-point distance for a 90-degree cubic arc. */
static const double kArc = 0.5522847498307936;

/*
 * Append a full circle to the current path as four cubic Beziers.
 *   ccw != 0  -> counter-clockwise winding
 *   ccw == 0  -> clockwise winding
 * Using opposite windings for an outer and inner circle produces a HOLE under
 * the default NONZERO (winding) fill rule.
 */
static void circle_cubic(cm_context_t *ctx, double cx, double cy, double r,
                         int ccw)
{
    const double k = kArc * r;
    if (ccw) {
        /* start at east point, go CCW: E -> N -> W -> S -> E */
        cm_move_to (ctx, cx + r, cy);
        cm_curve_to(ctx, cx + r, cy + k,  cx + k, cy + r,  cx,     cy + r); /* E->N */
        cm_curve_to(ctx, cx - k, cy + r,  cx - r, cy + k,  cx - r, cy);     /* N->W */
        cm_curve_to(ctx, cx - r, cy - k,  cx - k, cy - r,  cx,     cy - r); /* W->S */
        cm_curve_to(ctx, cx + k, cy - r,  cx + r, cy - k,  cx + r, cy);     /* S->E */
    } else {
        /* start at east point, go CW: E -> S -> W -> N -> E */
        cm_move_to (ctx, cx + r, cy);
        cm_curve_to(ctx, cx + r, cy - k,  cx + k, cy - r,  cx,     cy - r); /* E->S */
        cm_curve_to(ctx, cx - k, cy - r,  cx - r, cy - k,  cx - r, cy);     /* S->W */
        cm_curve_to(ctx, cx - r, cy + k,  cx - k, cy + r,  cx,     cy + r); /* W->N */
        cm_curve_to(ctx, cx + k, cy + r,  cx + r, cy + k,  cx + r, cy);     /* N->E */
    }
    cm_close_path(ctx);
}

/* ----------------------------------------------------------------------------
 * PNG writer: read the premultiplied-BGRA surface and encode via ImageIO.
 * ------------------------------------------------------------------------- */
static int write_surface_png(cm_surface_t *surface, const char *path)
{
    cm_surface_flush(surface);

    int w = cm_surface_get_width(surface);
    int h = cm_surface_get_height(surface);
    if (w <= 0 || h <= 0) {
        fprintf(stderr, "demo: bad surface dimensions %dx%d\n", w, h);
        return -1;
    }

    size_t stride = 0;
    void *pixels = cm_surface_map_argb32(surface, &stride);
    if (!pixels || stride == 0) {
        fprintf(stderr, "demo: cm_surface_map_argb32 failed (status=%s)\n",
                cm_status_to_string(cm_last_status()));
        return -1;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) { fprintf(stderr, "demo: CGColorSpaceCreateDeviceRGB failed\n"); return -1; }

    /* Premultiplied BGRA, little-endian == cairo FORMAT_ARGB32 byte order. */
    CGBitmapInfo bmp = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst |
                       (CGBitmapInfo)kCGBitmapByteOrder32Little;

    CGContextRef cg = CGBitmapContextCreate(pixels, (size_t)w, (size_t)h,
                                            8, stride, cs, bmp);
    CGColorSpaceRelease(cs);
    if (!cg) {
        fprintf(stderr, "demo: CGBitmapContextCreate failed\n");
        return -1;
    }

    CGImageRef img = CGBitmapContextCreateImage(cg);
    CGContextRelease(cg);
    if (!img) {
        fprintf(stderr, "demo: CGBitmapContextCreateImage failed\n");
        return -1;
    }

    int rc = 0;
    @autoreleasepool {
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        CFStringRef pngType = (__bridge CFStringRef)UTTypePNG.identifier;
        CGImageDestinationRef dst =
            CGImageDestinationCreateWithURL((__bridge CFURLRef)url, pngType, 1, NULL);
        if (!dst) {
            fprintf(stderr, "demo: CGImageDestinationCreateWithURL failed\n");
            rc = -1;
        } else {
            CGImageDestinationAddImage(dst, img, NULL);
            if (!CGImageDestinationFinalize(dst)) {
                fprintf(stderr, "demo: CGImageDestinationFinalize failed\n");
                rc = -1;
            }
            CFRelease(dst);
        }
    }
    CGImageRelease(img);
    return rc;
}

/* ----------------------------------------------------------------------------
 * main
 * ------------------------------------------------------------------------- */
int main(int argc, const char *argv[])
{
    const char *out = (argc > 1) ? argv[1] : "demo.png";
    const int   W = 800, H = 600;

    @autoreleasepool {
        /* ---- create the IOSurface-backed ARGB32 target -------------------- */
        cm_surface_t *surface = cm_image_surface_create_argb32(CM_FORMAT_ARGB32, W, H);
        if (!surface) {
            fprintf(stderr,
                    "demo: cm_image_surface_create_argb32 failed: %s\n"
                    "      (need a Metal device + the compiled shaders; run via "
                    "`make run`, which sets CM_METALLIB).\n",
                    cm_status_to_string(cm_last_status()));
            return 1;
        }

        cm_context_t *ctx = cm_context_create(surface);
        if (!ctx) {
            fprintf(stderr, "demo: cm_context_create failed: %s\n",
                    cm_status_to_string(cm_last_status()));
            cm_surface_destroy(surface);
            return 1;
        }

        /* Pixel-space CTM (identity): coordinates below are in device pixels,
         * y-down, which matches how we read the buffer back for the PNG. */
        cm_matrix_t m = { 1, 0, 0, 1, 0, 0 };
        cm_set_matrix(ctx, &m);

        /* Opaque dark-grey background: fill the whole canvas. */
        cm_new_path(ctx);
        cm_move_to(ctx, 0, 0);
        cm_line_to(ctx, W, 0);
        cm_line_to(ctx, W, H);
        cm_line_to(ctx, 0, H);
        cm_close_path(ctx);
        cm_set_source_rgba(ctx, 0.12, 0.12, 0.14, 1.0);
        cm_set_fill_rule(ctx, CM_FILL_RULE_WINDING);
        cm_fill_preserve(ctx);

        /* ============================================================== *
         * Shape 1: filled cubic-Bezier DONUT (outer CCW + inner CW hole)  *
         * ============================================================== */
        cm_new_path(ctx);
        circle_cubic(ctx, 200, 200, 120, /*ccw=*/1);   /* outer ring */
        circle_cubic(ctx, 200, 200,  55, /*ccw=*/0);   /* inner hole (opposite winding) */
        cm_set_source_rgba(ctx, 0.95, 0.45, 0.20, 1.0);
        cm_set_fill_rule(ctx, CM_FILL_RULE_WINDING);   /* NONZERO -> hole appears */
        cm_fill_preserve(ctx);

        /* ============================================================== *
         * Shape 2: linear-gradient filled rounded blob                    *
         * ============================================================== */
        cm_pattern_t *grad = cm_linear_gradient_create(480, 110, 760, 290);
        if (!grad) {
            fprintf(stderr, "demo: cm_linear_gradient_create failed: %s\n",
                    cm_status_to_string(cm_last_status()));
            cm_context_destroy(ctx);
            cm_surface_destroy(surface);
            return 1;
        }
        cm_pattern_add_color_stop_rgba(grad, 0.0, 0.10, 0.55, 0.95, 1.0); /* blue  */
        cm_pattern_add_color_stop_rgba(grad, 1.0, 0.85, 0.20, 0.75, 1.0); /* pink  */

        cm_new_path(ctx);
        circle_cubic(ctx, 620, 200, 110, /*ccw=*/1);   /* a filled disc, gradient-painted */
        cm_set_source(ctx, grad);
        cm_set_fill_rule(ctx, CM_FILL_RULE_WINDING);
        cm_fill_preserve(ctx);
        cm_pattern_destroy(grad);   /* context retained its own ref for the fill */

        /* ============================================================== *
         * Shape 3: stroked zig-zag path with ROUND joins + round caps     *
         * ============================================================== */
        cm_new_path(ctx);
        cm_move_to(ctx, 120, 470);
        cm_line_to(ctx, 240, 380);
        cm_line_to(ctx, 360, 500);
        cm_line_to(ctx, 480, 380);
        cm_line_to(ctx, 600, 500);
        cm_line_to(ctx, 700, 410);
        /* a trailing cubic flourish so curve_to is exercised in the stroke too */
        cm_curve_to(ctx, 740, 470, 700, 540, 640, 540);

        cm_set_source_rgba(ctx, 0.30, 0.90, 0.55, 1.0);
        cm_set_line_width(ctx, 26.0);
        cm_set_line_join(ctx, CM_LINE_JOIN_ROUND);  /* round joins (the headline) */
        cm_set_line_cap (ctx, CM_LINE_CAP_ROUND);   /* round caps for good measure */
        cm_stroke_preserve(ctx);

        /* ============================================================== *
         * Shape 4: DASHED stroke (cm_set_dash)                            *
         * -------------------------------------------------------------- *
         * A straight line that must render as SEPARATE, individually      *
         * round-capped segments -- proving cm_dash_apply is now wired     *
         * into the stroke path.  Shape 3 above has no dash set, so it     *
         * stays one solid stroke (the un-dashed path is unchanged).       *
         * ============================================================== */
        cm_new_path(ctx);
        cm_move_to(ctx,  60, 345);
        cm_line_to(ctx, 740, 345);

        /* {on, off} lengths in USER space (offset 0).  The stroke path scales
         * the pattern to device space and chops the line into capped on-pieces. */
        const double dashes[] = { 36.0, 24.0 };
        cm_set_dash(ctx, dashes, 2, 0.0);

        cm_set_source_rgba(ctx, 1.00, 0.85, 0.15, 1.0);  /* yellow */
        cm_set_line_width(ctx, 14.0);
        cm_set_line_cap (ctx, CM_LINE_CAP_ROUND);  /* each dash gets two round caps */
        cm_stroke_preserve(ctx);

        /* ---- SITE 2 check: the QUERY path must honor the dash too -------- *
         * cm_in_stroke now runs the SAME dash pre-pass as the draw, so with the
         * dash still set a point inside an "on" piece hits and a point in an
         * "off" gap misses; disabling the dash then makes that SAME gap point a
         * hit on the solid stroke.  Line is y=345, dash {36 on, 24 off} from
         * x=60: x=78 is mid on-piece, x=108 is mid gap (clear of the round caps).
         */
        int hit_on    = cm_in_stroke(ctx,  78.0, 345.0);  /* expect 1           */
        int hit_gap   = cm_in_stroke(ctx, 108.0, 345.0);  /* expect 0 (dashed)  */
        cm_set_dash(ctx, NULL, 0, 0.0);                    /* disable dashing    */
        int hit_solid = cm_in_stroke(ctx, 108.0, 345.0);  /* expect 1 (solid)   */
        bool site2_ok = (hit_on == 1 && hit_gap == 0 && hit_solid == 1);
        fprintf(stderr,
                "demo: [site2] in_stroke on=%d gap=%d solid_gap=%d -> %s\n",
                hit_on, hit_gap, hit_solid, site2_ok ? "PASS" : "FAIL");

        /* ============================================================== *
         * Shape 5: DASHED stroke via the NON-PRESERVE cm_stroke()         *
         * -------------------------------------------------------------- *
         * Exercises the CONSOLIDATED stroke path: cm_stroke() now ALWAYS  *
         * delegates to cm_stroke_preserve (which honors the dash through   *
         * cm_dash_prepass) + cm_new_path -- there is no separate dashed    *
         * fork any more.  A short cyan line in the gap between the two top  *
         * shapes is drawn as round-capped on-pieces, AND the path must be   *
         * CONSUMED (cairo: stroke == stroke_preserve + new_path).          *
         * ============================================================== */
        cm_new_path(ctx);
        cm_move_to(ctx, 345, 250);
        cm_line_to(ctx, 485, 250);

        const double dashes2[] = { 30.0, 18.0 };   /* {on, off} USER space */
        cm_set_dash(ctx, dashes2, 2, 0.0);

        /* Before the non-preserve stroke the dashed path is live: a point on the
         * first on-piece (x in [345,375]) hits via the SAME dash pre-pass. */
        int s3_before = cm_in_stroke(ctx, 348.0, 250.0);   /* expect 1 (on-piece) */

        cm_set_source_rgba(ctx, 0.55, 0.95, 1.00, 1.0);    /* cyan */
        cm_set_line_width(ctx, 12.0);
        cm_set_line_cap (ctx, CM_LINE_CAP_ROUND);          /* each dash: two round caps */
        cm_stroke(ctx);   /* NON-PRESERVE: dashed draw, THEN cm_new_path consumes it */

        /* After cm_stroke() the path is consumed, so the SAME point now misses
         * (cm_in_stroke reports 0 for an empty path) -- proving the consolidated
         * cm_stroke() drew the dashed line AND cleared the path. */
        int s3_after = cm_in_stroke(ctx, 348.0, 250.0);    /* expect 0 (consumed) */
        cm_set_dash(ctx, NULL, 0, 0.0);                    /* leave dashing disabled */
        bool site3_ok = (s3_before == 1 && s3_after == 0);
        fprintf(stderr,
                "demo: [site3] in_stroke before=%d after_consume=%d -> %s\n",
                s3_before, s3_after, site3_ok ? "PASS" : "FAIL");

        /* ---- finish: check status, flush, write PNG ---------------------- */
        cm_status_t st = cm_context_status(ctx);
        if (st != CM_STATUS_SUCCESS) {
            fprintf(stderr, "demo: drawing failed: %s\n", cm_status_to_string(st));
            cm_context_destroy(ctx);
            cm_surface_destroy(surface);
            return 1;
        }

        int rc = write_surface_png(surface, out);

        cm_context_destroy(ctx);
        cm_surface_destroy(surface);

        if (rc != 0) {
            fprintf(stderr, "demo: failed to write %s\n", out);
            return 1;
        }
        printf("demo: wrote %s (%dx%d): donut + gradient + round-join stroke "
               "+ dashed stroke (preserve + non-preserve)\n", out, W, H);

        if (!site2_ok) {
            fprintf(stderr,
                    "demo: [site2] dashed-stroke hit test FAILED "
                    "(query path did not honor the dash)\n");
            return 1;
        }
        if (!site3_ok) {
            fprintf(stderr,
                    "demo: [site3] non-preserve cm_stroke() dashed test FAILED "
                    "(consolidated stroke path did not draw + consume)\n");
            return 1;
        }
    }
    return 0;
}
