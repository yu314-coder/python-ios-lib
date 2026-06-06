#!/usr/bin/env python3
"""
test_full_shim.py -- smoke test for the FULL pycairo-compatible cairo_metal shim.

Exercises the required drawing path (move_to / curve_to / arc / rectangle,
set_source + gradient, fill + stroke, PNG write) AND the newly-exposed types
(SolidPattern, SurfacePattern, RadialGradient, MeshPattern, Region, Matrix
algebra, FontOptions / ToyFontFace / ScaledFont, RecordingSurface, enums).

Deliberately has NO numpy dependency (uses bytearray) so it runs anywhere the
extension imports.  PNG output is verified two ways: the C library's own
write_to_png() AND (if PIL is present) decode-back to confirm pixels are real.

Run:  CM_METALLIB="$PWD/build/default.metallib" python3 python/test_full_shim.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
os.environ.setdefault("CM_METALLIB", os.path.join(ROOT, "build", "default.metallib"))

import cairo_metal as cairo  # the shim (NOT real pycairo)

W, H = 400, 300
PASS = []


def ok(name, cond, extra=""):
    PASS.append(bool(cond))
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}{(' -- ' + extra) if extra else ''}")
    assert cond, f"{name} failed {extra}"


def test_enums():
    print("enums (cairo-exact integer values):")
    ok("OPERATOR_OVER == 2", cairo.OPERATOR_OVER == 2)
    ok("Operator.OVER == 2", int(cairo.Operator.OVER) == 2)
    ok("FORMAT_ARGB32 == 0", cairo.FORMAT_ARGB32 == 0)
    ok("FORMAT_A8 == 2", cairo.FORMAT_A8 == 2)
    ok("CONTENT_COLOR_ALPHA == 0x3000", cairo.CONTENT_COLOR_ALPHA == 0x3000)
    ok("EXTEND_REFLECT == 2", cairo.EXTEND_REFLECT == 2)
    ok("FILL_RULE_EVEN_ODD == 1", cairo.FILL_RULE_EVEN_ODD == 1)
    ok("LINE_CAP_ROUND == 1", cairo.LINE_CAP_ROUND == 1)
    ok("ANTIALIAS_BEST == 6", cairo.ANTIALIAS_BEST == 6)
    ok("OPERATOR_HSL_LUMINOSITY == 28", cairo.OPERATOR_HSL_LUMINOSITY == 28)
    ok("PATH_CURVE_TO == 2", cairo.PATH_CURVE_TO == 2)
    ok("Format.ARGB32 is IntEnum member", int(cairo.Format.ARGB32) == 0)


def test_matrix():
    print("Matrix algebra:")
    m = cairo.Matrix()  # identity
    ok("identity translate_point", m.transform_point(3, 4) == (3.0, 4.0))
    m = cairo.Matrix(1, 0, 0, 1, 10, 20)
    ok("translate matrix point", m.transform_point(1, 1) == (11.0, 21.0))
    m2 = cairo.Matrix.init_rotate(0.0)
    ok("init_rotate(0) is identity-ish", abs(m2.xx - 1.0) < 1e-9 and abs(m2.yx) < 1e-9)
    s = cairo.Matrix(2, 0, 0, 3, 0, 0)
    p = s.transform_distance(1, 1)
    ok("scale distance", p == (2.0, 3.0))
    inv = cairo.Matrix(2, 0, 0, 2, 0, 0)
    inv.invert()
    ok("invert scale", inv.transform_point(2, 2) == (1.0, 1.0))
    a = cairo.Matrix(1, 0, 0, 1, 5, 0)
    b = cairo.Matrix(1, 0, 0, 1, 0, 7)
    c = a.multiply(b)
    ok("multiply (compose translates)", c.transform_point(0, 0) == (5.0, 7.0))
    ok("operator* matches multiply", (a * b).transform_point(0, 0) == (5.0, 7.0))
    ok("members xx/yx/.. readable", a.xx == 1.0 and a.x0 == 5.0)
    ok("indexable m[4]==x0", a[4] == 5.0)
    ok("equality", cairo.Matrix() == cairo.Matrix())


def test_region():
    print("Region algebra:")
    r = cairo.Region((0, 0, 100, 100))
    ok("contains point", r.contains_point(50, 50))
    ok("not contains far point", not r.contains_point(200, 200))
    r.union((50, 50, 100, 100))
    ext = r.get_extents()
    ok("union extents", ext == (0, 0, 150, 150), str(ext))
    r2 = cairo.Region((0, 0, 100, 100))
    r2.intersect((50, 50, 100, 100))
    ok("intersect extents", r2.get_extents() == (50, 50, 50, 50), str(r2.get_extents()))
    ok("num_rectangles >= 1", r2.num_rectangles() >= 1)
    empty = cairo.Region()
    ok("empty region is_empty", empty.is_empty())
    ok("overlap enum", r.contains_rectangle((10, 10, 5, 5)) == cairo.REGION_OVERLAP_IN)


def test_patterns():
    print("Patterns (solid / gradients / surface / mesh):")
    sp = cairo.SolidPattern(0.25, 0.5, 0.75, 1.0)
    ok("SolidPattern get_rgba", sp.get_rgba() == (0.25, 0.5, 0.75, 1.0))
    ok("SolidPattern type", sp.get_type() == cairo.PATTERN_TYPE_SOLID)

    lg = cairo.LinearGradient(0, 0, 100, 100)
    lg.add_color_stop_rgba(0.0, 1, 0, 0, 1)
    lg.add_color_stop_rgb(1.0, 0, 0, 1)
    ok("LinearGradient stop count", lg.get_color_stop_count() == 2)
    ok("LinearGradient points", lg.get_linear_points() == (0.0, 0.0, 100.0, 100.0))
    lg.set_extend(cairo.EXTEND_REPEAT)
    ok("set/get_extend", lg.get_extend() == cairo.EXTEND_REPEAT)
    stops = lg.get_color_stops_rgba()
    ok("color stops readback", len(stops) == 2 and stops[0][1] == 1.0)

    rg = cairo.RadialGradient(50, 50, 10, 50, 50, 60)
    rg.add_color_stop_rgba(0.0, 1, 1, 1, 1)
    ok("RadialGradient circles", rg.get_radial_circles() == (50.0, 50.0, 10.0, 50.0, 50.0, 60.0))
    ok("RadialGradient type", rg.get_type() == cairo.PATTERN_TYPE_RADIAL)

    mesh = cairo.MeshPattern()
    mesh.begin_patch()
    mesh.move_to(0, 0)
    mesh.line_to(1, 0)
    mesh.line_to(1, 1)
    mesh.line_to(0, 1)
    mesh.set_corner_color_rgb(0, 1, 0, 0)
    mesh.set_corner_color_rgb(1, 0, 1, 0)
    mesh.set_corner_color_rgb(2, 0, 0, 1)
    mesh.set_corner_color_rgb(3, 1, 1, 0)
    mesh.end_patch()
    ok("MeshPattern patch count", mesh.get_patch_count() == 1)
    ok("MeshPattern type", mesh.get_type() == cairo.PATTERN_TYPE_MESH)

    # SurfacePattern over a small surface
    src = cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8)
    spat = cairo.SurfacePattern(src)
    ok("SurfacePattern type", spat.get_type() == cairo.PATTERN_TYPE_SURFACE)
    got = spat.get_surface()
    ok("SurfacePattern get_surface w", got.get_width() == 8)


def test_fonts():
    print("Fonts (FontOptions / ToyFontFace / ScaledFont):")
    fo = cairo.FontOptions()
    fo.set_antialias(cairo.ANTIALIAS_GRAY)
    ok("FontOptions antialias", fo.get_antialias() == cairo.ANTIALIAS_GRAY)
    fo.set_hint_style(cairo.HINT_STYLE_FULL)
    ok("FontOptions hint_style", fo.get_hint_style() == cairo.HINT_STYLE_FULL)
    fo2 = fo.copy()
    ok("FontOptions equal after copy", fo == fo2)

    tf = cairo.ToyFontFace("sans", cairo.FONT_SLANT_ITALIC, cairo.FONT_WEIGHT_BOLD)
    ok("ToyFontFace family", tf.get_family() == "sans")
    ok("ToyFontFace slant", tf.get_slant() == cairo.FONT_SLANT_ITALIC)
    ok("ToyFontFace weight", tf.get_weight() == cairo.FONT_WEIGHT_BOLD)
    ok("ToyFontFace type", tf.get_type() == cairo.FONT_TYPE_TOY)

    ident = cairo.Matrix(16, 0, 0, 16, 0, 0)
    ctm = cairo.Matrix()
    sf = cairo.ScaledFont(tf, ident, ctm, cairo.FontOptions())
    ok("ScaledFont type", sf.get_type() == cairo.FONT_TYPE_TOY)
    ok("ScaledFont font_face roundtrip", sf.get_font_face().get_type() == cairo.FONT_TYPE_TOY)
    ext = sf.extents()
    ok("ScaledFont extents len", len(ext) == 5)


def test_recording_surface():
    print("RecordingSurface (create + introspect; drawing is a C-lib stub):")
    rs = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 50, 50))
    ok("RecordingSurface created", rs.get_type() == cairo.SURFACE_TYPE_RECORDING)
    ink = rs.ink_extents()
    ok("ink_extents len 4", len(ink) == 4)
    ge = rs.get_extents()
    ok("get_extents bounded", ge == (0.0, 0.0, 50.0, 50.0), str(ge))
    # NOTE: the C library does not (yet) rasterize/record drawing ops into a
    # recording surface -- cm_fill/stroke/paint require a GPU IOSurface target,
    # so a context bound to a recording surface raises DEVICE_ERROR on fill.
    rc = cairo.Context(rs)
    rc.set_source_rgba(1, 0, 0, 1)
    rc.rectangle(5, 5, 20, 20)
    raised = False
    try:
        rc.fill()
    except cairo.Error as e:
        raised = True
        print(f"    (expected) drawing into RecordingSurface -> {e}")
    ok("recording draw raises (documented C-lib limitation)", raised)


def test_context_state():
    print("Context state getters/setters + transforms:")
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    ctx = cairo.Context(surf)
    ctx.set_line_width(7.0)
    ok("get_line_width", ctx.get_line_width() == 7.0)
    ctx.set_line_join(cairo.LINE_JOIN_BEVEL)
    ok("get_line_join", ctx.get_line_join() == cairo.LINE_JOIN_BEVEL)
    ctx.set_line_cap(cairo.LINE_CAP_SQUARE)
    ok("get_line_cap", ctx.get_line_cap() == cairo.LINE_CAP_SQUARE)
    ctx.set_operator(cairo.OPERATOR_MULTIPLY)
    ok("get_operator", ctx.get_operator() == cairo.OPERATOR_MULTIPLY)
    ctx.set_miter_limit(3.0)
    ok("get_miter_limit", ctx.get_miter_limit() == 3.0)
    ctx.set_dash([4.0, 2.0], 1.0)
    d, off = ctx.get_dash()
    ok("get_dash", d == [4.0, 2.0] and off == 1.0, f"{d},{off}")
    ok("get_dash_count", ctx.get_dash_count() == 2)
    ctx.set_dash([])  # disable
    ok("dash disabled", ctx.get_dash_count() == 0)

    # transform stack + user/device
    ctx.identity_matrix()
    ctx.translate(10, 20)
    ctx.scale(2, 2)
    ok("user_to_device", ctx.user_to_device(1, 1) == (12.0, 22.0), str(ctx.user_to_device(1, 1)))
    ctx.save()
    ctx.scale(5, 5)
    ctx.restore()
    ok("save/restore restores CTM", ctx.user_to_device(1, 1) == (12.0, 22.0))

    # path queries
    ctx.identity_matrix()
    ctx.new_path()
    ctx.move_to(50, 50)
    ctx.line_to(150, 50)
    ctx.line_to(150, 150)
    ok("has_current_point", ctx.has_current_point())
    ok("get_current_point", ctx.get_current_point() == (150.0, 150.0))
    x1, y1, x2, y2 = ctx.path_extents()
    ok("path_extents", (x1, y1, x2, y2) == (50.0, 50.0, 150.0, 150.0), str((x1, y1, x2, y2)))

    # clip
    ctx.new_path()
    ctx.rectangle(0, 0, 100, 100)
    ctx.clip()
    ok("in_clip inside", ctx.in_clip(10, 10))
    ok("in_clip outside", not ctx.in_clip(300, 300))
    ce = ctx.clip_extents()
    ok("clip_extents", ce == (0.0, 0.0, 100.0, 100.0), str(ce))
    ctx.reset_clip()


def test_draw_and_png():
    print("Full drawing + PNG (move_to/curve_to/arc/rectangle, gradient, fill+stroke):")
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    ctx = cairo.Context(surf)

    # opaque background via paint
    ctx.set_source_rgba(0.10, 0.10, 0.12, 1.0)
    ctx.paint()
    ok("paint status", ctx.status() == 0)

    # rectangle fill
    ctx.rectangle(20, 20, 120, 80)
    ctx.set_source_rgb(0.9, 0.4, 0.2)
    ctx.fill()

    # curve_to path, stroked
    ctx.new_path()
    ctx.move_to(20, 200)
    ctx.curve_to(80, 120, 160, 280, 220, 200)
    ctx.set_source_rgb(0.2, 0.8, 0.5)
    ctx.set_line_width(8.0)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.stroke()

    # arc, filled with a radial gradient
    rg = cairo.RadialGradient(320, 150, 5, 320, 150, 70)
    rg.add_color_stop_rgba(0.0, 1, 1, 1, 1)
    rg.add_color_stop_rgba(1.0, 0.2, 0.3, 0.9, 1)
    ctx.new_path()
    ctx.arc(320, 150, 70, 0, 2 * 3.14159265358979)
    ctx.set_source(rg)
    ctx.fill()

    # arc, filled with a linear gradient
    lg = cairo.LinearGradient(40, 240, 360, 280)
    lg.add_color_stop_rgba(0.0, 0.95, 0.2, 0.5, 1)
    lg.add_color_stop_rgba(1.0, 0.2, 0.6, 0.95, 1)
    ctx.new_path()
    ctx.arc(120, 255, 30, 0, 2 * 3.14159265358979)
    ctx.set_source(lg)
    ctx.fill()

    ok("draw status clean", ctx.status() == 0)

    surf.flush()
    out = os.path.join(HERE, "full_shim_out.png")
    surf.write_to_png(out)
    size = os.path.getsize(out)
    ok("PNG written non-empty", size > 1000, f"{size} bytes")
    print(f"  wrote {out} ({size} bytes)")

    # Round-trip: read the PNG back via the C API and confirm dimensions.
    rt = cairo.ImageSurface.create_from_png(out)
    ok("PNG read-back dims", rt.get_width() == W and rt.get_height() == H)

    # If PIL is available, confirm the decoded image actually has colour.
    try:
        from PIL import Image
        im = Image.open(out).convert("RGB")
        ok("PNG decodes to right size", im.size == (W, H), str(im.size))
        colors = im.getcolors(maxcolors=1 << 20)
        ok("PNG has many colors (gradients rendered)", colors is None or len(colors) > 50,
           f"{None if colors is None else len(colors)} distinct")
        # center of the radial disc should be near-white
        r, g, b = im.getpixel((320, 150))
        ok("radial disc center bright", r > 150 and g > 150 and b > 150, f"({r},{g},{b})")
    except ImportError:
        print("  (PIL not present; skipped decode-back colour check)")

    return out


def test_create_for_data_bytearray():
    print("create_for_data (external buffer, no numpy):")
    buf = bytearray(W * H * 4)
    surf = cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_ARGB32, W, H)
    ctx = cairo.Context(surf)
    ctx.set_source_rgba(1.0, 1.0, 1.0, 1.0)  # premultiplied BGRA white
    ctx.rectangle(0, 0, W, H)
    ctx.fill()
    surf.flush()  # copies GPU pixels back into `buf`
    ok("buffer written non-zero", any(buf))
    # a center pixel should be opaque
    idx = ((H // 2) * W + (W // 2)) * 4
    ok("center pixel opaque", buf[idx + 3] == 255, f"alpha={buf[idx+3]}")


def main():
    print(f"cairo_metal {cairo.cairo_version_string()} on device {cairo.metal_device_name()!r}")
    print(f"module exposes {len(dir(cairo))} symbols\n")
    ok("gpu_selftest passes", cairo.gpu_selftest()[0] == 1, str(cairo.gpu_selftest()))
    test_enums()
    test_matrix()
    test_region()
    test_patterns()
    test_fonts()
    test_recording_surface()
    test_context_state()
    test_draw_and_png()
    test_create_for_data_bytearray()
    print(f"\nALL {len(PASS)} CHECKS PASSED")


if __name__ == "__main__":
    main()
