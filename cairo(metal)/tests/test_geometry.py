#!/usr/bin/env python3
"""
Rigorous correctness tests for CairoMetal — GEOMETRY area.

Run:
  CM_METALLIB="/Volumes/D/OfflinAi/cairo(metal)/build/default.metallib" \
  PYTHONPATH="/Volumes/D/OfflinAi/cairo(metal)/python" \
  python3 '/Volumes/D/OfflinAi/cairo(metal)/tests/test_geometry.py'

Every check compares a SPECIFIC pixel or returned numeric value against a
hand-computed expected value. No smoke checks. Goal: FIND BUGS.

FORMAT facts relied upon (verified):
  ImageSurface(FORMAT_ARGB32,w,h): get_data() raw bytes, get_stride() row stride.
  Memory order per pixel = B,G,R,A (premultiplied). For pixel (x,y):
    o = y*stride + x*4  ->  data[o]=B data[o+1]=G data[o+2]=R data[o+3]=A
  set_source_rgba(r,g,b,a): r is RED. Solid (1,0,0,1) reads bytes [0,0,255,255].
  Extents getters return CORNER form (x0,y0,x1,y1), NOT (x,y,w,h).
  Region rects/extents are (x,y,w,h) int tuples.
"""

import math
import sys
import struct

import cairo_metal as cairo

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------
_PASS = 0
_FAIL = 0
_FAILURES = []


def check(cond, feature, expected, actual, note=""):
    global _PASS, _FAIL
    if cond:
        _PASS += 1
    else:
        _FAIL += 1
        _FAILURES.append((feature, expected, actual, note))
        msg = "  FAIL [%s] expected=%s actual=%s" % (feature, expected, actual)
        if note:
            msg += "  (%s)" % note
        print(msg)


def approx(a, b, tol):
    return abs(a - b) <= tol


def vapprox(seq_a, seq_b, tol):
    return len(seq_a) == len(seq_b) and all(approx(x, y, tol) for x, y in zip(seq_a, seq_b))


# ---------------------------------------------------------------------------
# Pixel helpers
# ---------------------------------------------------------------------------
def new_surface(w, h):
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surf)
    return surf, ctx


def real_stride(surf):
    """The ACTUAL byte stride of the get_data() buffer.

    NOTE: get_stride() is BUGGY on CairoMetal (reports a GPU-texture-aligned
    value that does not match the tightly-packed CPU buffer). The true buffer
    stride equals format_stride_for_width(format, width) == len(data)//height.
    We use the true stride for all pixel access so geometry is tested against
    the data that actually exists. The get_stride() defect is asserted
    separately in test_get_stride_contract().
    """
    surf.flush()
    h = surf.get_height()
    return len(bytes(surf.get_data())) // h


def px(surf, x, y):
    """Return (R,G,B,A) at device pixel (x,y), un-swizzling B,G,R,A storage."""
    surf.flush()
    data = bytes(surf.get_data())
    stride = real_stride(surf)
    o = y * stride + x * 4
    b, g, r, a = data[o], data[o + 1], data[o + 2], data[o + 3]
    return (r, g, b, a)


def is_filled(surf, x, y, thresh=128):
    """Heuristic: alpha above threshold means something was painted there."""
    return px(surf, x, y)[3] >= thresh


def is_background(surf, x, y, thresh=8):
    """Untouched ARGB32 surface starts cleared to all zeros (transparent)."""
    return px(surf, x, y)[3] <= thresh


# ===========================================================================
# 0. SURFACE DATA CONTRACT (stride must match the get_data() buffer)
# ===========================================================================
def test_get_stride_contract():
    # pycairo contract: rows of get_data() are EXACTLY get_stride() bytes apart,
    # and get_stride() == format_stride_for_width(format, width).
    for w, h in [(4, 4), (10, 10), (100, 100), (33, 10), (50, 50)]:
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        surf.flush()
        data = bytes(surf.get_data())
        reported = surf.get_stride()
        fsw = cairo.ImageSurface.format_stride_for_width(cairo.FORMAT_ARGB32, w)
        actual_buf_stride = len(data) // h
        # 1) buffer length must be a whole number of reported-stride rows
        check(len(data) == reported * h,
              "get_data length == get_stride*height (w=%d,h=%d)" % (w, h),
              reported * h, len(data),
              "buffer is %d bytes = %d-byte rows, not %d-byte rows" % (len(data), actual_buf_stride, reported))
        # 2) get_stride must equal format_stride_for_width
        check(reported == fsw,
              "get_stride == format_stride_for_width (w=%d)" % w, fsw, reported,
              "actual packed buffer stride is %d" % actual_buf_stride)


# ===========================================================================
# 1. TRANSFORMS
# ===========================================================================
def test_translate():
    surf, ctx = new_surface(100, 100)
    ctx.translate(30, 20)
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.rectangle(0, 0, 10, 10)
    ctx.fill()
    # Center of the translated rect: user(5,5) -> device(35,25)
    r, g, b, a = px(surf, 35, 25)
    check(a >= 250 and r >= 250 and g <= 4 and b <= 4,
          "translate: filled center px(35,25)", "(255,0,0,255)", (r, g, b, a))
    # Just inside corners
    check(is_filled(surf, 30, 20), "translate: top-left corner device(30,20) filled", "filled", px(surf, 30, 20))
    check(is_filled(surf, 39, 29), "translate: bottom-right device(39,29) filled", "filled", px(surf, 39, 29))
    # Outside: original (5,5) must be background
    check(is_background(surf, 5, 5), "translate: original (5,5) untouched", "bg", px(surf, 5, 5))
    # Device x just past the rect (x=40) should be background
    check(is_background(surf, 45, 25), "translate: device(45,25) outside untouched", "bg", px(surf, 45, 25))


def test_scale():
    surf, ctx = new_surface(100, 100)
    ctx.scale(2, 2)
    ctx.set_source_rgba(0, 1, 0, 1)
    ctx.rectangle(0, 0, 10, 10)  # user 0..10 -> device 0..20
    ctx.fill()
    # device (10,10) is center -> filled green
    r, g, b, a = px(surf, 10, 10)
    check(a >= 250 and g >= 250 and r <= 4 and b <= 4,
          "scale: filled center px(10,10)", "(0,255,0,255)", (r, g, b, a))
    check(is_filled(surf, 18, 18), "scale: device(18,18) inside 0..20 filled", "filled", px(surf, 18, 18))
    # device (25,25) is past 20 -> background
    check(is_background(surf, 25, 25), "scale: device(25,25) outside untouched", "bg", px(surf, 25, 25))
    check(is_background(surf, 5, 50), "scale: device(5,50) outside untouched", "bg", px(surf, 5, 50))


def test_rotate():
    # Rotate +90deg about origin maps user (x,y) -> device (-y, x).
    # To keep things on-surface, translate to a pivot first.
    # Pivot (50,50). rotate(pi/2). Then a rectangle at user (0,0,20,2)
    # (a thin horizontal bar extending +x) becomes a vertical bar extending +y
    # in device space from the pivot.
    surf, ctx = new_surface(100, 100)
    ctx.translate(50, 50)
    ctx.rotate(math.pi / 2)
    ctx.set_source_rgba(0, 0, 1, 1)
    ctx.rectangle(0, 0, 30, 4)  # user-space thin bar along +x
    ctx.fill()
    # user point (15,2) (middle of bar). device = pivot + R*(15,2).
    # R(pi/2): (x,y)->(x*cos - y*sin, x*sin + y*cos) = (-y, x) = (-2, 15)
    # device = (50-2, 50+15) = (48, 65)
    r, g, b, a = px(surf, 48, 65)
    check(a >= 250 and b >= 250 and r <= 4 and g <= 4,
          "rotate(pi/2): user(15,2)->device(48,65) blue", "(0,0,255,255)", (r, g, b, a))
    # The UN-rotated location (where bar would be without rotation), device (65,52),
    # must be background (bar is NOT there anymore).
    check(is_background(surf, 65, 52), "rotate: pre-rotation spot device(65,52) untouched", "bg", px(surf, 65, 52))
    # Sanity: a point well off the rotated bar
    check(is_background(surf, 20, 20), "rotate: far point device(20,20) untouched", "bg", px(surf, 20, 20))


def test_user_device_roundtrip():
    surf, ctx = new_surface(100, 100)
    ctx.translate(13.5, 17.25)
    ctx.scale(2.0, 3.0)
    ctx.rotate(0.5)
    for (ux, uy) in [(7, 9), (0, 0), (-3.5, 11.25), (100, -50)]:
        dx, dy = ctx.user_to_device(ux, uy)
        bx, by = ctx.device_to_user(dx, dy)
        check(approx(bx, ux, 1e-6) and approx(by, uy, 1e-6),
              "user<->device roundtrip (%s,%s)" % (ux, uy), (ux, uy), (bx, by))
    # distance variants ignore translation
    for (dxu, dyu) in [(10, 0), (0, 5), (3, 4)]:
        ddx, ddy = ctx.user_to_device_distance(dxu, dyu)
        bdx, bdy = ctx.device_to_user_distance(ddx, ddy)
        check(approx(bdx, dxu, 1e-6) and approx(bdy, dyu, 1e-6),
              "user<->device distance roundtrip (%s,%s)" % (dxu, dyu), (dxu, dyu), (bdx, bdy))


def test_matrix_algebra():
    # Matrix(xx, yx, xy, yy, x0, y0) per pycairo. Mapping:
    #   x' = xx*x + xy*y + x0
    #   y' = yx*x + yy*y + y0
    # init_rotate(theta): [cos, sin, -sin, cos, 0, 0]
    th = math.pi / 6  # 30 deg
    mr = cairo.Matrix.init_rotate(th)
    xt = mr.as_tuple()
    expect = (math.cos(th), math.sin(th), -math.sin(th), math.cos(th), 0.0, 0.0)
    check(vapprox(xt, expect, 1e-9), "Matrix.init_rotate(30deg) entries", expect, xt)

    # transform_point with rotation: (1,0) -> (cos, sin)
    pxp = mr.transform_point(1, 0)
    check(vapprox(pxp, (math.cos(th), math.sin(th)), 1e-9),
          "rotate.transform_point(1,0)", (math.cos(th), math.sin(th)), pxp)
    # (0,1) -> (-sin, cos)
    pxp2 = mr.transform_point(0, 1)
    check(vapprox(pxp2, (-math.sin(th), math.cos(th)), 1e-9),
          "rotate.transform_point(0,1)", (-math.sin(th), math.cos(th)), pxp2)

    # Affine general transform_point and transform_distance
    M = cairo.Matrix(2, 0, 0, 3, 10, 20)  # scale(2,3)+translate(10,20)
    check(M.transform_point(3, 4) == (16.0, 32.0),
          "Matrix(2,0,0,3,10,20).transform_point(3,4)", (16.0, 32.0), M.transform_point(3, 4))
    check(M.transform_distance(3, 4) == (6.0, 12.0),
          "transform_distance ignores translation", (6.0, 12.0), M.transform_distance(3, 4))

    # Shear matrix to test off-diagonal: xy=1 -> x' = x + 1*y
    S = cairo.Matrix(1, 0, 1, 1, 0, 0)
    check(S.transform_point(2, 5) == (7.0, 5.0),
          "shear xy=1 transform_point(2,5)", (7.0, 5.0), S.transform_point(2, 5))

    # invert: in-place. inverse of scale(2,3)+trans(10,20):
    #   x = (x'-10)/2, y=(y'-20)/3 -> matrix (0.5,0,0,1/3, -5, -20/3)
    Mi = cairo.Matrix(2, 0, 0, 3, 10, 20)
    ret = Mi.invert()
    check(ret is None, "Matrix.invert returns None (in-place)", None, ret)
    inv_expect = (0.5, 0.0, 0.0, 1.0 / 3.0, -5.0, -20.0 / 3.0)
    check(vapprox(Mi.as_tuple(), inv_expect, 1e-9), "invert(scale2,3+trans)", inv_expect, Mi.as_tuple())
    # M * M^-1 == identity
    Morig = cairo.Matrix(2, 0, 0, 3, 10, 20)
    prod = Morig.multiply(Mi)
    check(vapprox(prod.as_tuple(), (1, 0, 0, 1, 0, 0), 1e-9),
          "M * M^-1 == identity", (1, 0, 0, 1, 0, 0), prod.as_tuple())

    # multiply order. In cairo, C = A.multiply(B) means apply A first then B:
    #   transform_point(C, p) == transform_point(B, transform_point(A, p))
    A = cairo.Matrix.init_rotate(math.pi / 2)        # rotate 90
    B = cairo.Matrix(1, 0, 0, 1, 100, 0)              # translate +100x
    C = A.multiply(B)
    p = (10, 0)
    via_C = C.transform_point(*p)
    via_seq = B.transform_point(*A.transform_point(*p))
    check(vapprox(via_C, via_seq, 1e-9),
          "multiply(A,B): apply A then B", via_seq, via_C)
    # concretely: rotate90 of (10,0)=(0,10); +100x ->(100,10)
    check(vapprox(via_C, (100.0, 10.0), 1e-9),
          "multiply order concrete (rot90 then +100x)", (100.0, 10.0), via_C)
    # and that the reverse order differs (sanity that order is respected)
    D = B.multiply(A)
    via_D = D.transform_point(*p)
    # +100x of (10,0)=(110,0); rotate90 ->(0,110)
    check(vapprox(via_D, (0.0, 110.0), 1e-9),
          "multiply reverse order (B then A)", (0.0, 110.0), via_D)

    # Matrix.scale / translate / rotate as in-place builders matching pycairo.
    Mb = cairo.Matrix()  # identity
    Mb.translate(10, 20)
    Mb.scale(2, 3)
    # Equivalent to cairo.Matrix(2,0,0,3,10,20)
    check(vapprox(Mb.as_tuple(), (2, 0, 0, 3, 10, 20), 1e-9),
          "Matrix identity.translate.scale builder", (2, 0, 0, 3, 10, 20), Mb.as_tuple())
    # transform a point through builder == hand matrix
    check(vapprox(Mb.transform_point(1, 1), (12.0, 23.0), 1e-9),
          "builder transform_point(1,1)", (12.0, 23.0), Mb.transform_point(1, 1))


def test_ctm_matches_matrix():
    # ctx.get_matrix() after translate+scale must equal hand matrix, and
    # transform a point identically.
    surf, ctx = new_surface(100, 100)
    ctx.translate(30, 20)
    ctx.scale(2, 4)
    m = ctx.get_matrix()
    check(vapprox(m.as_tuple(), (2, 0, 0, 4, 30, 20), 1e-9),
          "get_matrix after translate(30,20).scale(2,4)", (2, 0, 0, 4, 30, 20), m.as_tuple())
    # user_to_device must agree with matrix.transform_point
    dx, dy = ctx.user_to_device(5, 6)
    mxp = m.transform_point(5, 6)
    check(vapprox((dx, dy), mxp, 1e-9), "user_to_device == matrix.transform_point", mxp, (dx, dy))
    check(vapprox((dx, dy), (40.0, 44.0), 1e-9), "user_to_device(5,6) concrete", (40.0, 44.0), (dx, dy))
    # set_matrix then identity_matrix resets
    ctx.identity_matrix()
    check(vapprox(ctx.get_matrix().as_tuple(), (1, 0, 0, 1, 0, 0), 1e-12),
          "identity_matrix resets CTM", (1, 0, 0, 1, 0, 0), ctx.get_matrix().as_tuple())


# ===========================================================================
# 2. PATHS
# ===========================================================================
def test_arc_fill():
    surf, ctx = new_surface(100, 100)
    cx, cy, r = 50, 50, 30
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    ctx.fill()
    # center filled
    check(is_filled(surf, cx, cy), "arc fill: center filled", "filled", px(surf, cx, cy))
    # well outside (cx+r+5, cy) background
    check(is_background(surf, cx + r + 5, cy), "arc fill: (cx+r+5,cy) background", "bg", px(surf, cx + r + 5, cy))
    check(is_background(surf, cx, cy + r + 5), "arc fill: (cx,cy+r+5) background", "bg", px(surf, cx, cy + r + 5))
    # boundary at 45deg: point at radius r*0.85 should be inside (filled),
    # point at radius r*1.15 should be outside (bg). Avoids AA edge band.
    a = math.pi / 4
    ix, iy = int(round(cx + r * 0.85 * math.cos(a))), int(round(cy + r * 0.85 * math.sin(a)))
    ox, oy = int(round(cx + r * 1.15 * math.cos(a))), int(round(cy + r * 1.15 * math.sin(a)))
    check(is_filled(surf, ix, iy), "arc fill: inside-boundary 45deg filled", "filled", px(surf, ix, iy))
    check(is_background(surf, ox, oy), "arc fill: outside-boundary 45deg bg", "bg", px(surf, ox, oy))
    # corner of bounding box (well outside disc) must be background
    check(is_background(surf, 5, 5), "arc fill: bbox corner (5,5) bg", "bg", px(surf, 5, 5))


def test_arc_stroke_quarter():
    surf, ctx = new_surface(100, 100)
    cx, cy, r = 50, 50, 30
    ctx.set_line_width(4)
    ctx.set_source_rgba(0, 0, 1, 1)
    ctx.arc(cx, cy, r, 0, math.pi / 2)  # quarter arc, angles 0..90 (device: +x down to +y)
    ctx.stroke()
    # A point ON the quarter-arc at 45deg: (cx + r cos45, cy + r sin45)
    a = math.pi / 4
    onx, ony = int(round(cx + r * math.cos(a))), int(round(cy + r * math.sin(a)))
    check(is_filled(surf, onx, ony), "arc stroke quarter: point on arc (45deg) colored",
          "colored", px(surf, onx, ony))
    # The reflected point across the arc, at 45deg but radius r on the OPPOSITE
    # side (angle 45+180=225deg): definitely not on the 0..90 arc.
    rx, ry = int(round(cx + r * math.cos(a + math.pi))), int(round(cy + r * math.sin(a + math.pi)))
    check(is_background(surf, rx, ry), "arc stroke quarter: reflected point (225deg) bg",
          "bg", px(surf, rx, ry))
    # Angle 135deg is also outside the 0..90 sweep
    a2 = 3 * math.pi / 4
    qx, qy = int(round(cx + r * math.cos(a2))), int(round(cy + r * math.sin(a2)))
    check(is_background(surf, qx, qy), "arc stroke quarter: 135deg point bg", "bg", px(surf, qx, qy))
    # Center is NOT on a stroked (unfilled) arc
    check(is_background(surf, cx, cy), "arc stroke quarter: center is empty", "bg", px(surf, cx, cy))


def test_arc_negative():
    # arc vs arc_negative sweep different sides. Use a half turn.
    # arc(0 -> pi) sweeps the lower half (device y>cy). arc_negative(0 -> pi)
    # sweeps the upper half (device y<cy). Fill each and check a probe point.
    cx, cy, r = 50, 50, 30
    # positive arc 0..pi filled with new_sub_path so it closes chord
    surf, ctx = new_surface(100, 100)
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.arc(cx, cy, r, 0, math.pi)
    ctx.close_path()
    ctx.fill()
    check(is_filled(surf, cx, cy + 15), "arc(0..pi) fills lower half", "filled", px(surf, cx, cy + 15))
    check(is_background(surf, cx, cy - 15), "arc(0..pi) upper half empty", "bg", px(surf, cx, cy - 15))

    surf2, ctx2 = new_surface(100, 100)
    ctx2.set_source_rgba(1, 0, 0, 1)
    ctx2.arc_negative(cx, cy, r, 0, math.pi)
    ctx2.close_path()
    ctx2.fill()
    check(is_filled(surf2, cx, cy - 15), "arc_negative(0..pi) fills upper half", "filled", px(surf2, cx, cy - 15))
    check(is_background(surf2, cx, cy + 15), "arc_negative(0..pi) lower half empty", "bg", px(surf2, cx, cy + 15))


def test_rectangle_bounds():
    surf, ctx = new_surface(100, 100)
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.rectangle(20, 30, 25, 15)  # x:20..45, y:30..45
    ctx.fill()
    # Interior corners filled
    check(is_filled(surf, 20, 30), "rect: TL (20,30) filled", "filled", px(surf, 20, 30))
    check(is_filled(surf, 44, 44), "rect: BR-inside (44,44) filled", "filled", px(surf, 44, 44))
    check(is_filled(surf, 32, 37), "rect: center filled", "filled", px(surf, 32, 37))
    # Just outside on each side must be background (pixel coverage [20,45)x[30,45))
    check(is_background(surf, 19, 37), "rect: x=19 outside-left bg", "bg", px(surf, 19, 37))
    check(is_background(surf, 45, 37), "rect: x=45 outside-right bg", "bg", px(surf, 45, 37))
    check(is_background(surf, 32, 29), "rect: y=29 outside-top bg", "bg", px(surf, 32, 29))
    check(is_background(surf, 32, 45), "rect: y=45 outside-bottom bg", "bg", px(surf, 32, 45))
    # path_extents exact corner form
    surf2, ctx2 = new_surface(100, 100)
    ctx2.rectangle(20, 30, 25, 15)
    pe = ctx2.path_extents()
    check(vapprox(pe, (20, 30, 45, 45), 1e-9), "rect path_extents", (20, 30, 45, 45), pe)


def test_relative_path_equivalence():
    # Build an open polyline two ways: absolute and relative. Stroke both,
    # compare full pixel buffers for exact equality.
    def draw_abs(ctx):
        ctx.move_to(10, 10)
        ctx.line_to(40, 10)
        ctx.line_to(40, 40)
        ctx.curve_to(60, 40, 60, 70, 40, 70)

    def draw_rel(ctx):
        ctx.move_to(10, 10)
        ctx.rel_line_to(30, 0)      # ->(40,10)
        ctx.rel_line_to(0, 30)      # ->(40,40)
        ctx.rel_curve_to(20, 0, 20, 30, 0, 30)  # ctrl (60,40)(60,70) end (40,70)

    surf_a, ctx_a = new_surface(100, 100)
    ctx_a.set_line_width(3)
    ctx_a.set_source_rgba(0, 0, 0, 1)
    draw_abs(ctx_a)
    ctx_a.stroke()

    surf_b, ctx_b = new_surface(100, 100)
    ctx_b.set_line_width(3)
    ctx_b.set_source_rgba(0, 0, 0, 1)
    draw_rel(ctx_b)
    ctx_b.stroke()

    surf_a.flush(); surf_b.flush()
    da = bytes(surf_a.get_data()); db = bytes(surf_b.get_data())
    check(da == db, "rel path == abs path (identical pixels)", "identical buffers",
          "differ in %d bytes" % sum(1 for i in range(len(da)) if da[i] != db[i]))

    # Also verify rel_move_to math against current point
    surf_c, ctx_c = new_surface(100, 100)
    ctx_c.move_to(15, 25)
    ctx_c.rel_move_to(5, -10)
    cp = ctx_c.get_current_point()
    check(vapprox(cp, (20.0, 15.0), 1e-9), "rel_move_to current point", (20.0, 15.0), cp)
    ctx_c.rel_line_to(10, 0)
    cp2 = ctx_c.get_current_point()
    check(vapprox(cp2, (30.0, 15.0), 1e-9), "rel_line_to current point", (30.0, 15.0), cp2)


def test_path_extents_and_current_point():
    surf, ctx = new_surface(100, 100)
    # Triangle path
    ctx.move_to(10, 80)
    ctx.line_to(50, 20)
    ctx.line_to(90, 80)
    ctx.close_path()
    pe = ctx.path_extents()
    check(vapprox(pe, (10, 20, 90, 80), 1e-6), "triangle path_extents", (10, 20, 90, 80), pe)

    # has_current_point / get_current_point after move_to
    surf2, ctx2 = new_surface(100, 100)
    check(ctx2.has_current_point() is False, "fresh ctx has no current point", False, ctx2.has_current_point())
    ctx2.move_to(33, 44)
    check(ctx2.has_current_point() is True, "after move_to has current point", True, ctx2.has_current_point())
    check(vapprox(ctx2.get_current_point(), (33.0, 44.0), 1e-9),
          "current point == move_to target", (33.0, 44.0), ctx2.get_current_point())
    ctx2.new_path()
    check(ctx2.has_current_point() is False, "after new_path no current point", False, ctx2.has_current_point())
    # path_extents of empty path is degenerate (all zeros)
    pe_empty = ctx2.path_extents()
    check(vapprox(pe_empty, (0, 0, 0, 0), 1e-9), "empty path_extents all-zero", (0, 0, 0, 0), pe_empty)

    # new_sub_path clears current point but keeps prior subpaths in extents
    surf3, ctx3 = new_surface(100, 100)
    ctx3.move_to(10, 10)
    ctx3.line_to(20, 20)
    ctx3.new_sub_path()
    check(ctx3.has_current_point() is False, "new_sub_path clears current point", False, ctx3.has_current_point())
    ctx3.move_to(60, 60)
    ctx3.line_to(70, 75)
    pe3 = ctx3.path_extents()
    check(vapprox(pe3, (10, 10, 70, 75), 1e-6), "extents span both subpaths", (10, 10, 70, 75), pe3)


# ===========================================================================
# 3. CLIP
# ===========================================================================
def test_clip_rectangle_paint():
    surf, ctx = new_surface(100, 100)
    ctx.rectangle(20, 20, 40, 40)  # clip region [20,60)x[20,60)
    ctx.clip()
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.paint()
    # Inside painted
    check(is_filled(surf, 40, 40), "clip rect: center inside painted", "filled", px(surf, 40, 40))
    check(is_filled(surf, 20, 20), "clip rect: TL inside painted", "filled", px(surf, 20, 20))
    check(is_filled(surf, 59, 59), "clip rect: BR-inside painted", "filled", px(surf, 59, 59))
    # Outside untouched
    check(is_background(surf, 10, 10), "clip rect: outside (10,10) untouched", "bg", px(surf, 10, 10))
    check(is_background(surf, 70, 40), "clip rect: outside-right (70,40) untouched", "bg", px(surf, 70, 40))
    check(is_background(surf, 19, 40), "clip rect: just-left (19,40) untouched", "bg", px(surf, 19, 40))
    check(is_background(surf, 60, 40), "clip rect: just-right (60,40) untouched", "bg", px(surf, 60, 40))
    # clip_extents
    ce = ctx.clip_extents()
    check(vapprox(ce, (20, 20, 60, 60), 1e-6), "clip_extents after rect clip", (20, 20, 60, 60), ce)
    # in_clip
    check(ctx.in_clip(40, 40) is True, "in_clip inside True", True, ctx.in_clip(40, 40))
    check(ctx.in_clip(10, 10) is False, "in_clip outside False", False, ctx.in_clip(10, 10))


def test_clip_intersection():
    surf, ctx = new_surface(100, 100)
    ctx.rectangle(20, 20, 40, 40)   # [20,60)
    ctx.clip()
    ctx.rectangle(40, 40, 40, 40)   # [40,80) -> intersection [40,60)x[40,60)
    ctx.clip()
    ctx.set_source_rgba(0, 1, 0, 1)
    ctx.paint()
    # In intersection
    check(is_filled(surf, 50, 50), "two clips: intersection (50,50) painted", "filled", px(surf, 50, 50))
    # In first only, not second (e.g. (25,25))
    check(is_background(surf, 25, 25), "two clips: first-only (25,25) untouched", "bg", px(surf, 25, 25))
    # In second only, not first (e.g. (70,70))
    check(is_background(surf, 70, 70), "two clips: second-only (70,70) untouched", "bg", px(surf, 70, 70))
    ce = ctx.clip_extents()
    check(vapprox(ce, (40, 40, 60, 60), 1e-6), "clip_extents after intersect", (40, 40, 60, 60), ce)


def test_reset_clip():
    surf, ctx = new_surface(100, 100)
    ctx.rectangle(20, 20, 10, 10)
    ctx.clip()
    ctx.reset_clip()
    ctx.set_source_rgba(0, 0, 1, 1)
    ctx.paint()
    # Now whole surface painted
    check(is_filled(surf, 5, 5), "reset_clip: corner (5,5) painted", "filled", px(surf, 5, 5))
    check(is_filled(surf, 95, 95), "reset_clip: far corner (95,95) painted", "filled", px(surf, 95, 95))
    ce = ctx.clip_extents()
    check(vapprox(ce, (0, 0, 100, 100), 1e-6), "clip_extents restored full", (0, 0, 100, 100), ce)


def test_clip_circle_corner():
    # Clip to a circle, paint, check bbox corner NOT painted but center is.
    surf, ctx = new_surface(100, 100)
    cx, cy, r = 50, 50, 30
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    ctx.clip()
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.paint()
    check(is_filled(surf, 50, 50), "circle clip: center painted", "filled", px(surf, 50, 50))
    # Corner of bbox (cx-r, cy-r)=(20,20) is OUTSIDE the disc (dist~42 > r=30)
    #  -> must NOT be painted if clip honors the curved path.
    check(is_background(surf, 21, 21), "circle clip: bbox corner (21,21) untouched", "bg", px(surf, 21, 21))
    # A point just outside radius along the diagonal: (cx-r*0.78, cy-r*0.78) is
    # at dist ~33 > 30, outside -> untouched.
    check(is_background(surf, 27, 27), "circle clip: just-outside disc (27,27) untouched",
          "bg", px(surf, 27, 27))
    # Painted-area count: an honest circular clip paints ~pi*r^2 (~2827) pixels,
    # NOT the full bounding box (2r)^2 = 3600. Allow generous AA slack.
    surf.flush()
    d = bytes(surf.get_data())
    st = real_stride(surf)
    painted = sum(1 for i in range(3, len(d), 4) if d[i] > 128)
    disc_area = math.pi * r * r
    bbox_area = (2 * r) * (2 * r)
    check(approx(painted, disc_area, 0.08 * disc_area),
          "circle clip: painted area ~= disc area (not bbox)", int(disc_area), painted,
          "bbox area would be %d; painting bbox => clip ignores curve" % bbox_area)
    # clip_extents of circle == bounding box
    ce = ctx.clip_extents()
    check(vapprox(ce, (20, 20, 80, 80), 1.5), "circle clip_extents == bbox", (20, 20, 80, 80), ce)
    # in_clip respects non-rect shape
    check(ctx.in_clip(50, 50) is True, "circle in_clip center True", True, ctx.in_clip(50, 50))
    check(ctx.in_clip(22, 22) is False, "circle in_clip corner False", False, ctx.in_clip(22, 22))


# ===========================================================================
# 4. REGIONS
# ===========================================================================
def test_region_basic():
    r = cairo.Region((10, 20, 30, 40))  # x,y,w,h -> covers x:10..40, y:20..60
    check(r.num_rectangles() == 1, "region single rect count", 1, r.num_rectangles())
    check(r.get_extents() == (10, 20, 30, 40), "region extents", (10, 20, 30, 40), r.get_extents())
    check(r.contains_point(15, 25) is True, "region contains (15,25)", True, r.contains_point(15, 25))
    check(r.contains_point(39, 59) is True, "region contains (39,59)", True, r.contains_point(39, 59))
    check(r.contains_point(40, 30) is False, "region excludes x=40 (half-open)", False, r.contains_point(40, 30))
    check(r.contains_point(5, 5) is False, "region excludes (5,5)", False, r.contains_point(5, 5))
    check(r.is_empty() is False, "non-empty region", False, r.is_empty())


def test_region_union():
    a = cairo.Region((0, 0, 20, 20))
    b = cairo.Region((30, 0, 20, 20))  # disjoint horizontally
    a.union(b)
    check(a.num_rectangles() == 2, "union disjoint -> 2 rects", 2, a.num_rectangles())
    # extents bound both: x 0..50, y 0..20 -> (0,0,50,20)
    check(a.get_extents() == (0, 0, 50, 20), "union extents", (0, 0, 50, 20), a.get_extents())
    check(a.contains_point(10, 10) and a.contains_point(40, 10), "union contains both halves",
          True, (a.contains_point(10, 10), a.contains_point(40, 10)))
    check(a.contains_point(25, 10) is False, "union gap not contained", False, a.contains_point(25, 10))

    # Adjacent union should coalesce to 1 rectangle
    c = cairo.Region((0, 0, 20, 20))
    d = cairo.Region((20, 0, 20, 20))  # touches at x=20
    c.union(d)
    check(c.num_rectangles() == 1, "adjacent union coalesces -> 1 rect", 1, c.num_rectangles())
    check(c.get_extents() == (0, 0, 40, 20), "adjacent union extents", (0, 0, 40, 20), c.get_extents())


def test_region_intersect():
    a = cairo.Region((0, 0, 40, 40))
    b = cairo.Region((20, 20, 40, 40))
    a.intersect(b)
    check(a.num_rectangles() == 1, "intersect -> 1 rect", 1, a.num_rectangles())
    check(a.get_extents() == (20, 20, 20, 20), "intersect extents [20,40)x[20,40)",
          (20, 20, 20, 20), a.get_extents())
    check(a.contains_point(30, 30) is True, "intersect contains (30,30)", True, a.contains_point(30, 30))
    check(a.contains_point(10, 10) is False, "intersect excludes (10,10)", False, a.contains_point(10, 10))
    check(a.contains_point(50, 50) is False, "intersect excludes (50,50)", False, a.contains_point(50, 50))

    # Disjoint intersection -> empty
    c = cairo.Region((0, 0, 10, 10))
    d = cairo.Region((50, 50, 10, 10))
    c.intersect(d)
    check(c.is_empty() is True, "disjoint intersect empty", True, c.is_empty())


def test_region_subtract():
    # Big square minus a middle horizontal slab. Subtract a band that spans the
    # full width so the result is clean top + bottom rects.
    a = cairo.Region((0, 0, 40, 40))
    b = cairo.Region((0, 10, 40, 20))  # remove y:10..30 full width
    a.subtract(b)
    # Result: top y:0..10 and bottom y:30..40, both full width -> 2 rects
    check(a.num_rectangles() == 2, "subtract slab -> 2 rects", 2, a.num_rectangles())
    check(a.get_extents() == (0, 0, 40, 40), "subtract keeps outer extents", (0, 0, 40, 40), a.get_extents())
    check(a.contains_point(20, 5) is True, "subtract: top band kept", True, a.contains_point(20, 5))
    check(a.contains_point(20, 35) is True, "subtract: bottom band kept", True, a.contains_point(20, 35))
    check(a.contains_point(20, 20) is False, "subtract: middle removed", False, a.contains_point(20, 20))


def test_region_xor():
    # Two overlapping squares; xor removes the overlap.
    a = cairo.Region((0, 0, 40, 40))
    b = cairo.Region((20, 0, 40, 40))  # overlap x:20..40 full height
    a.xor_(b)
    # Result = symmetric difference: x:0..20 and x:40..60 (full height) -> 2 rects
    check(a.num_rectangles() == 2, "xor overlap -> 2 rects", 2, a.num_rectangles())
    check(a.get_extents() == (0, 0, 60, 40), "xor extents 0..60", (0, 0, 60, 40), a.get_extents())
    check(a.contains_point(10, 20) is True, "xor: left-only present", True, a.contains_point(10, 20))
    check(a.contains_point(50, 20) is True, "xor: right-only present", True, a.contains_point(50, 20))
    check(a.contains_point(30, 20) is False, "xor: overlap removed", False, a.contains_point(30, 20))


def test_region_translate():
    r = cairo.Region((10, 10, 20, 20))
    r.translate(5, -3)
    check(r.get_extents() == (15, 7, 20, 20), "region translate extents", (15, 7, 20, 20), r.get_extents())
    check(r.contains_point(15, 7) is True, "translated region contains new TL", True, r.contains_point(15, 7))
    check(r.contains_point(10, 10) is False, "translated region excludes old TL", False, r.contains_point(10, 10))


def test_region_contains_rectangle():
    r = cairo.Region((0, 0, 100, 100))
    inside = r.contains_rectangle((10, 10, 20, 20))
    check(inside == cairo.REGION_OVERLAP_IN, "contains_rectangle fully IN", cairo.REGION_OVERLAP_IN, inside)
    outside = r.contains_rectangle((200, 200, 10, 10))
    check(outside == cairo.REGION_OVERLAP_OUT, "contains_rectangle fully OUT", cairo.REGION_OVERLAP_OUT, outside)
    partial = r.contains_rectangle((90, 90, 20, 20))
    check(partial == cairo.REGION_OVERLAP_PART, "contains_rectangle PART", cairo.REGION_OVERLAP_PART, partial)


# ===========================================================================
# 5. QUERY (in_fill / in_stroke / fill_extents / stroke_extents)
# ===========================================================================
def test_in_fill():
    surf, ctx = new_surface(100, 100)
    ctx.rectangle(20, 20, 40, 40)  # x:20..60, y:20..60
    check(ctx.in_fill(40, 40) is True, "in_fill center True", True, ctx.in_fill(40, 40))
    check(ctx.in_fill(21, 21) is True, "in_fill near corner True", True, ctx.in_fill(21, 21))
    check(ctx.in_fill(70, 40) is False, "in_fill outside-right False", False, ctx.in_fill(70, 40))
    check(ctx.in_fill(10, 10) is False, "in_fill outside False", False, ctx.in_fill(10, 10))
    # Edge: x=60 boundary is exclusive of interior fill in cairo? Cairo's in_fill
    # treats points strictly; (60,40) is on the right edge. We assert (59,40) IN.
    check(ctx.in_fill(59, 40) is True, "in_fill inner edge (59,40) True", True, ctx.in_fill(59, 40))

    # Circle in_fill
    surf2, ctx2 = new_surface(100, 100)
    ctx2.arc(50, 50, 30, 0, 2 * math.pi)
    check(ctx2.in_fill(50, 50) is True, "in_fill circle center True", True, ctx2.in_fill(50, 50))
    check(ctx2.in_fill(50, 50 - 29) is True, "in_fill circle near-top inside True", True,
          ctx2.in_fill(50, 50 - 29))
    check(ctx2.in_fill(50, 50 - 35) is False, "in_fill circle above-top outside False", False,
          ctx2.in_fill(50, 50 - 35))
    check(ctx2.in_fill(85, 85) is False, "in_fill circle bbox-corner False", False, ctx2.in_fill(85, 85))


def test_in_stroke():
    surf, ctx = new_surface(100, 100)
    ctx.set_line_width(10)
    ctx.move_to(20, 50)
    ctx.line_to(80, 50)  # horizontal line at y=50, half-width 5 -> y in [45,55]
    check(ctx.in_stroke(50, 50) is True, "in_stroke on centerline True", True, ctx.in_stroke(50, 50))
    check(ctx.in_stroke(50, 47) is True, "in_stroke within half-width True", True, ctx.in_stroke(50, 47))
    check(ctx.in_stroke(50, 40) is False, "in_stroke beyond half-width False", False, ctx.in_stroke(50, 40))
    check(ctx.in_stroke(50, 60) is False, "in_stroke below band False", False, ctx.in_stroke(50, 60))
    # Far past the line endpoints (butt cap default) at x=90 not in stroke
    check(ctx.in_stroke(90, 50) is False, "in_stroke past endpoint (butt) False", False, ctx.in_stroke(90, 50))


def test_fill_extents():
    surf, ctx = new_surface(100, 100)
    ctx.rectangle(15, 25, 30, 20)  # corners (15,25)-(45,45)
    fe = ctx.fill_extents()
    check(vapprox(fe, (15, 25, 45, 45), 1e-6), "fill_extents rect", (15, 25, 45, 45), fe)

    # Circle fill_extents == bbox
    surf2, ctx2 = new_surface(100, 100)
    ctx2.arc(50, 50, 20, 0, 2 * math.pi)
    fe2 = ctx2.fill_extents()
    check(vapprox(fe2, (30, 30, 70, 70), 1.0), "fill_extents circle bbox", (30, 30, 70, 70), fe2)


def test_stroke_extents():
    surf, ctx = new_surface(100, 100)
    ctx.set_line_width(6)  # half = 3
    ctx.rectangle(20, 20, 40, 40)  # path corners (20,20)-(60,60)
    se = ctx.stroke_extents()
    # Stroke extends out by half-width (3) plus miter at corners. For a closed
    # rectangle with default miter join, outer extents = path +/- half-width.
    check(vapprox(se, (17, 17, 63, 63), 0.5), "stroke_extents rect (miter)", (17, 17, 63, 63), se)

    # Open horizontal line, butt cap. Extents widen by half-width perpendicular,
    # and end exactly at endpoints along the line (butt cap, no extension).
    surf2, ctx2 = new_surface(100, 100)
    ctx2.set_line_width(8)  # half = 4
    ctx2.set_line_cap(cairo.LINE_CAP_BUTT)
    ctx2.move_to(30, 50)
    ctx2.line_to(70, 50)
    se2 = ctx2.stroke_extents()
    # x: 30..70 (butt, no extension), y: 50 +/- 4 -> 46..54
    check(vapprox(se2, (30, 46, 70, 54), 0.5), "stroke_extents line butt cap",
          (30, 46, 70, 54), se2)

    # Same line with square cap extends by half-width along the line.
    surf3, ctx3 = new_surface(100, 100)
    ctx3.set_line_width(8)
    ctx3.set_line_cap(cairo.LINE_CAP_SQUARE)
    ctx3.move_to(30, 50)
    ctx3.line_to(70, 50)
    se3 = ctx3.stroke_extents()
    # x: 26..74 (square cap +4 each end), y: 46..54
    check(vapprox(se3, (26, 46, 74, 54), 0.5), "stroke_extents line square cap",
          (26, 46, 74, 54), se3)

    # stroke_extents wider than fill_extents by ~line_width/2 each side
    surf4, ctx4 = new_surface(100, 100)
    ctx4.set_line_width(10)
    ctx4.rectangle(30, 30, 20, 20)
    fe = ctx4.fill_extents()
    se4 = ctx4.stroke_extents()
    dx0 = fe[0] - se4[0]
    check(approx(dx0, 5.0, 0.5), "stroke vs fill widened by half-width", 5.0, dx0)


# ===========================================================================
# 6. STATE (save/restore, push/pop group)
# ===========================================================================
def test_save_restore_line_width():
    surf, ctx = new_surface(10, 10)
    ctx.set_line_width(5)
    ctx.save()
    ctx.set_line_width(20)
    check(approx(ctx.get_line_width(), 20.0, 1e-9), "line_width after set 20", 20.0, ctx.get_line_width())
    ctx.restore()
    check(approx(ctx.get_line_width(), 5.0, 1e-9), "line_width restored to 5", 5.0, ctx.get_line_width())


def test_save_restore_full_state():
    surf, ctx = new_surface(10, 10)
    ctx.set_line_width(3)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_BEVEL)
    ctx.set_miter_limit(7.0)
    ctx.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
    ctx.set_tolerance(0.25)
    ctx.translate(5, 5)
    ctx.save()
    # mutate everything
    ctx.set_line_width(99)
    ctx.set_line_cap(cairo.LINE_CAP_SQUARE)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_miter_limit(2.0)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    ctx.set_tolerance(5.0)
    ctx.scale(3, 3)
    ctx.restore()
    check(approx(ctx.get_line_width(), 3.0, 1e-9), "restore line_width", 3.0, ctx.get_line_width())
    check(ctx.get_line_cap() == cairo.LINE_CAP_ROUND, "restore line_cap", cairo.LINE_CAP_ROUND, ctx.get_line_cap())
    check(ctx.get_line_join() == cairo.LINE_JOIN_BEVEL, "restore line_join", cairo.LINE_JOIN_BEVEL, ctx.get_line_join())
    check(approx(ctx.get_miter_limit(), 7.0, 1e-9), "restore miter_limit", 7.0, ctx.get_miter_limit())
    check(ctx.get_fill_rule() == cairo.FILL_RULE_EVEN_ODD, "restore fill_rule",
          cairo.FILL_RULE_EVEN_ODD, ctx.get_fill_rule())
    check(approx(ctx.get_tolerance(), 0.25, 1e-9), "restore tolerance", 0.25, ctx.get_tolerance())
    check(vapprox(ctx.get_matrix().as_tuple(), (1, 0, 0, 1, 5, 5), 1e-9),
          "restore CTM (translate only)", (1, 0, 0, 1, 5, 5), ctx.get_matrix().as_tuple())


def test_push_pop_group_over():
    # Paint a half-alpha red group over an opaque blue background.
    # Expected OVER result: out = src + dst*(1-src_a).
    # src = red premultiplied at alpha 0.5 -> (0.5,0,0) premul, a=0.5
    # dst opaque blue (0,0,1) a=1.
    # out_a = 0.5 + 1*(0.5) = 1.0
    # out_r = 0.5 + 0*0.5 = 0.5   -> 128
    # out_g = 0
    # out_b = 0 + 1*0.5 = 0.5     -> 128
    surf, ctx = new_surface(50, 50)
    ctx.set_source_rgba(0, 0, 1, 1)
    ctx.paint()  # opaque blue background

    ctx.push_group()
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.rectangle(10, 10, 30, 30)
    ctx.fill()  # opaque red inside the group
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(0.5)  # composite group at 50%

    r, g, b, a = px(surf, 25, 25)
    check(approx(r, 128, 3), "group OVER red channel", 128, r)
    check(approx(g, 0, 3), "group OVER green channel", 0, g)
    check(approx(b, 128, 3), "group OVER blue channel", 128, b)
    check(approx(a, 255, 3), "group OVER alpha", 255, a)
    # Outside the group rect but inside surface: just the blue bg (group was
    # transparent there, 0.5*transparent over blue = blue). This isolates whether
    # the group TARGET preserved transparency (it does) vs whether
    # paint_with_alpha applied the 0.5 (it does not, for a pattern source).
    r2, g2, b2, a2 = px(surf, 2, 2)
    check(approx(r2, 0, 3) and approx(g2, 0, 3) and approx(b2, 255, 3),
          "group OVER outside rect = blue bg (group preserves transparency)",
          (0, 0, 255), (r2, g2, b2))

    # CONTROL: paint_with_alpha(0.5) with a SOLID source DOES blend correctly.
    # (Establishes that the defect above is specific to pattern/group sources.)
    s2, c2 = new_surface(20, 20)
    c2.set_source_rgba(0, 0, 1, 1)
    c2.paint()
    c2.set_source_rgba(1, 0, 0, 1)
    c2.paint_with_alpha(0.5)
    rc, gc, bc, ac = px(s2, 10, 10)
    check(approx(rc, 128, 3) and approx(bc, 128, 3),
          "control: paint_with_alpha(0.5) solid source blends", (128, 0, 128), (rc, gc, bc))


def test_push_group_isolation():
    # push_group should give a fresh transparent target; drawing into it then
    # popping as source and painting should equal direct draw for opaque content.
    surf, ctx = new_surface(40, 40)
    ctx.push_group()
    ctx.set_source_rgba(0, 1, 0, 1)
    ctx.rectangle(5, 5, 20, 20)
    ctx.fill()
    pat = ctx.pop_group()
    check(pat is not None, "pop_group returns a pattern", "pattern", type(pat).__name__)
    ctx.set_source(pat)
    ctx.paint()
    r, g, b, a = px(surf, 15, 15)
    check(approx(g, 255, 3) and approx(r, 0, 3) and approx(b, 0, 3) and approx(a, 255, 3),
          "pop_group pattern paints green rect", (0, 255, 0, 255), (r, g, b, a))
    check(is_background(surf, 35, 35), "pop_group outside rect transparent", "bg", px(surf, 35, 35))


# ===========================================================================
# Runner
# ===========================================================================
ALL_TESTS = [
    # surface data contract
    test_get_stride_contract,
    # transforms
    test_translate,
    test_scale,
    test_rotate,
    test_user_device_roundtrip,
    test_matrix_algebra,
    test_ctm_matches_matrix,
    # paths
    test_arc_fill,
    test_arc_stroke_quarter,
    test_arc_negative,
    test_rectangle_bounds,
    test_relative_path_equivalence,
    test_path_extents_and_current_point,
    # clip
    test_clip_rectangle_paint,
    test_clip_intersection,
    test_reset_clip,
    test_clip_circle_corner,
    # regions
    test_region_basic,
    test_region_union,
    test_region_intersect,
    test_region_subtract,
    test_region_xor,
    test_region_translate,
    test_region_contains_rectangle,
    # query
    test_in_fill,
    test_in_stroke,
    test_fill_extents,
    test_stroke_extents,
    # state
    test_save_restore_line_width,
    test_save_restore_full_state,
    test_push_pop_group_over,
    test_push_group_isolation,
]


def main():
    print("=" * 70)
    print("CairoMetal GEOMETRY rigorous test suite")
    print("device:", cairo.metal_device_name())
    print("=" * 70)
    for t in ALL_TESTS:
        try:
            t()
        except Exception as e:
            global _FAIL
            _FAIL += 1
            _FAILURES.append((t.__name__, "no exception", repr(e), "TEST RAISED"))
            print("  EXC  [%s] raised %r" % (t.__name__, e))
            import traceback
            traceback.print_exc()
    print("-" * 70)
    total = _PASS + _FAIL
    print("TOTAL CHECKS: %d   PASS: %d   FAIL: %d" % (total, _PASS, _FAIL))
    if _FAILURES:
        print("\nFAILURES:")
        for feat, exp, act, note in _FAILURES:
            print("  - %s | expected=%s | actual=%s | %s" % (feat, exp, act, note))
    return 0 if _FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
