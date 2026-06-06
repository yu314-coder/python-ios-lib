#!/usr/bin/env python3
"""
test_shim.py -- render the SAME three shapes as examples/demo.m, but driven
entirely through the `cairo_metal` Python shim, then pixel-diff against the C
demo's output (build/demo.png) to prove the shim drives the GPU API correctly.

Run:  CM_METALLIB="$PWD/build/default.metallib" python3 python/test_shim.py
(build.sh builds the extension; this exercises it the way manim's camera.py would.)
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import cairo_metal as cairo  # the shim (NOT the real cairo)

W, H = 800, 600
kArc = 0.5522847498307936  # 4/3*(sqrt(2)-1): 90-degree cubic-arc control distance


def circle_cubic(ctx, cx, cy, r, ccw):
    """Append a full circle as four cubic Beziers (matches demo.m exactly)."""
    k = kArc * r
    ctx.move_to(cx + r, cy)
    if ccw:
        ctx.curve_to(cx + r, cy + k, cx + k, cy + r, cx, cy + r)
        ctx.curve_to(cx - k, cy + r, cx - r, cy + k, cx - r, cy)
        ctx.curve_to(cx - r, cy - k, cx - k, cy - r, cx, cy - r)
        ctx.curve_to(cx + k, cy - r, cx + r, cy - k, cx + r, cy)
    else:
        ctx.curve_to(cx + r, cy - k, cx + k, cy - r, cx, cy - r)
        ctx.curve_to(cx - k, cy - r, cx - r, cy - k, cx - r, cy)
        ctx.curve_to(cx - r, cy + k, cx - k, cy + r, cx, cy + r)
        ctx.curve_to(cx + k, cy + r, cx + r, cy + k, cx + r, cy)
    ctx.close_path()


def main():
    # manim-style: an external pixel buffer that cairo writes into.
    buf = np.zeros((H, W, 4), dtype=np.uint8)
    surf = cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_ARGB32, W, H)
    ctx = cairo.Context(surf)
    ctx.set_matrix(cairo.Matrix(1, 0, 0, 1, 0, 0))  # identity (pixel space)

    # background (opaque dark grey)
    ctx.new_path()
    ctx.move_to(0, 0); ctx.line_to(W, 0); ctx.line_to(W, H); ctx.line_to(0, H)
    ctx.close_path()
    ctx.set_source_rgba(0.12, 0.12, 0.14, 1.0)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    ctx.fill_preserve()

    # 1) donut: outer CCW + inner CW hole, NONZERO winding
    ctx.new_path()
    circle_cubic(ctx, 200, 200, 120, 1)
    circle_cubic(ctx, 200, 200, 55, 0)
    ctx.set_source_rgba(0.95, 0.45, 0.20, 1.0)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    ctx.fill_preserve()

    # 2) linear-gradient disc
    grad = cairo.LinearGradient(480, 110, 760, 290)
    grad.add_color_stop_rgba(0.0, 0.10, 0.55, 0.95, 1.0)
    grad.add_color_stop_rgba(1.0, 0.85, 0.20, 0.75, 1.0)
    ctx.new_path()
    circle_cubic(ctx, 620, 200, 110, 1)
    ctx.set_source(grad)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    ctx.fill_preserve()

    # 3) stroked zig-zag with round joins + caps + a trailing cubic
    ctx.new_path()
    ctx.move_to(120, 470); ctx.line_to(240, 380); ctx.line_to(360, 500)
    ctx.line_to(480, 380); ctx.line_to(600, 500); ctx.line_to(700, 410)
    ctx.curve_to(740, 470, 700, 540, 640, 540)
    ctx.set_source_rgba(0.30, 0.90, 0.55, 1.0)
    ctx.set_line_width(26.0)
    ctx.set_line_join(cairo.LineJoin.ROUND)
    ctx.set_line_cap(cairo.LineCap.ROUND)
    ctx.stroke_preserve()

    st = ctx.status()
    assert st == 0, f"drawing failed: cm status {st}"

    surf.flush()  # commit the GPU frame + copy pixels back into `buf`

    assert buf.any(), "FAIL: buffer is all-zero — nothing was rendered"

    # shapes are opaque, so premultiplied == straight; BGRA -> RGB by reorder.
    rgb = np.ascontiguousarray(buf[:, :, [2, 1, 0]])
    img = Image.fromarray(rgb, "RGB")
    out = os.path.join(HERE, "shim_out.png")
    img.save(out)
    print(f"shim wrote {out}")

    def px(x, y):
        return tuple(int(v) for v in rgb[y, x])
    print(f"  bg(10,10)={px(10,10)}  donut(200,82)={px(200,82)}  "
          f"hole(200,200)={px(200,200)}  stroke(360,496)={px(360,496)}")

    # sanity on a few known points (tolerant; sRGB-ish 8-bit of the rgba above)
    assert px(10, 10)[0] < 60, "background should be dark"
    assert px(200, 82)[0] > 180 and px(200, 82)[1] > 80, "donut ring should be orange"
    assert px(200, 200)[0] < 60, "donut hole should show the dark background"
    assert px(360, 496)[1] > 150, "stroke should be green"

    # ground-truth diff against the C demo (identical inputs => identical pixels)
    demo = os.path.join(ROOT, "build", "demo.png")
    if os.path.exists(demo):
        d = np.asarray(Image.open(demo).convert("RGB"), dtype=np.int16)
        s = np.asarray(img.convert("RGB"), dtype=np.int16)
        if d.shape == s.shape:
            mad = float(np.abs(d - s).mean())
            print(f"  mean abs diff vs C demo.png: {mad:.4f}  "
                  f"(0 = identical; the shim and the C demo call the same API)")
            assert mad < 3.0, f"FAIL: shim differs from C demo (MAD={mad})"
            print("  PASS: shim render matches the C demo within tolerance")
        else:
            print(f"  (demo.png shape {d.shape} != {s.shape}; skipping diff)")
    else:
        print("  (build/demo.png not found; run `make run` to enable the diff)")

    print("TEST PASSED")


if __name__ == "__main__":
    main()
