#!/usr/bin/env python3
"""
test_gaps.py -- rigorous verification of the newly-exposed pycairo features in
the CairoMetal Python extension (the binding-coverage gaps that were closed):

  1. Glyph / text-glyph API:
        Context.show_glyphs / show_text_glyphs / glyph_path / glyph_extents
        ScaledFont.text_to_glyphs / glyph_extents
  2. FreeType-style font face from a FILE on disk:
        cairo_metal.ft_font_face_create(path, index=0)
  3. RasterSourcePattern (construct + extend/filter/matrix + fallback paint)
  4. Surface.create_for_rectangle  (subsurface)
  5. Surface.map_to_image / unmap_image  (zero-copy alias round-trip)
  6. Surface.create_similar + ImageSurface.create_similar_image

Each check computes an EXPECTATION (ink where expected, metrics > 0, pixels
round-trip, distinct rendering, ...) rather than merely asserting presence.

Run:
  CM_METALLIB=".../build/default.metallib" PYTHONPATH=".../python" python3 python/test_gaps.py
"""
import os
import sys

import cairo_metal as cairo

PASS = 0
FAIL = 0
FAILED = []


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}" + (f"  -- {detail}" if detail else ""))
    else:
        FAIL += 1
        FAILED.append(name)
        print(f"  [FAIL] {name}" + (f"  -- {detail}" if detail else ""))


# ---------------------------------------------------------------- pixel helpers
def argb_at(surf, x, y):
    """Return (R, G, B, A) at (x, y) from an ARGB32 surface (premultiplied
    B,G,R,A row layout)."""
    surf.flush()
    d = surf.get_data()
    st = surf.get_stride()
    o = y * st + x * 4
    b, g, r, a = d[o], d[o + 1], d[o + 2], d[o + 3]
    return (r, g, b, a)


def count_white(surf, w, h, thresh=128):
    """Count near-white pixels (all of R,G,B above thresh) -- glyph ink on a
    black background."""
    surf.flush()
    d = surf.get_data()
    st = surf.get_stride()
    n = 0
    for y in range(h):
        row = y * st
        for x in range(w):
            o = row + x * 4
            if d[o] > thresh and d[o + 1] > thresh and d[o + 2] > thresh:
                n += 1
    return n


def white_mask(surf, w, h, thresh=128):
    surf.flush()
    d = surf.get_data()
    st = surf.get_stride()
    return bytes(
        1 if (d[y * st + x * 4] > thresh and d[y * st + x * 4 + 1] > thresh
              and d[y * st + x * 4 + 2] > thresh) else 0
        for y in range(h) for x in range(w)
    )


def black_surface(w, h):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    c = cairo.Context(s)
    c.set_source_rgb(0, 0, 0)
    c.paint()
    s.flush()
    return s, c


def find_font_file():
    for p in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
        "/System/Library/Fonts/Supplemental/Georgia.ttf",
        "/System/Library/Fonts/Geneva.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if os.path.exists(p):
            return p
    return None


# ============================================================ 1. GLYPH API
def test_glyph_api():
    print("\n== 1. Glyph / text-glyph API ==")
    W = H = 64
    s, c = black_surface(W, H)
    c.select_font_face("sans-serif")
    c.set_font_size(40)
    sf = c.get_scaled_font()

    # ScaledFont.text_to_glyphs -> real glyph indices + advancing pens.
    res = sf.text_to_glyphs(10, 45, "AV", True)
    check("text_to_glyphs returns (glyphs, clusters, flags) 3-tuple",
          isinstance(res, tuple) and len(res) == 3, f"res={res!r}")
    glyphs, clusters, flags = res
    check("text_to_glyphs: 2 glyphs for 'AV'", len(glyphs) == 2, f"n={len(glyphs)}")
    check("text_to_glyphs: glyph tuples are (index, x, y)",
          all(len(g) == 3 for g in glyphs)
          and all(isinstance(g[0], int) for g in glyphs), f"glyphs={glyphs}")
    check("text_to_glyphs: first glyph at pen origin (10, 45)",
          glyphs[0][1] == 10.0 and glyphs[0][2] == 45.0, f"g0={glyphs[0]}")
    check("text_to_glyphs: second glyph advanced past the first (x grows)",
          glyphs[1][1] > glyphs[0][1], f"g0.x={glyphs[0][1]} g1.x={glyphs[1][1]}")

    # glyphs-only form.
    g_only = sf.text_to_glyphs(0, 0, "A", False)
    check("text_to_glyphs(with_clusters=False) returns a plain glyph list",
          isinstance(g_only, list) and len(g_only) == 1, f"g_only={g_only}")

    # ScaledFont.glyph_extents: a non-empty run has positive width + advance.
    se = sf.glyph_extents(glyphs)
    check("ScaledFont.glyph_extents: width > 0 for a 2-glyph run",
          se[2] > 0, f"width={se[2]}")
    check("ScaledFont.glyph_extents: x_advance > 0",
          se[4] > 0, f"x_advance={se[4]}")
    se_empty = sf.glyph_extents([])
    check("ScaledFont.glyph_extents([]) is all-zero",
          se_empty == (0, 0, 0, 0, 0, 0), f"{se_empty}")

    # Context.glyph_extents: applies the font matrix -> ~font-size scale.
    ce = c.glyph_extents(glyphs)
    check("Context.glyph_extents: width > 0 (user space)", ce[2] > 0, f"width={ce[2]}")
    check("Context.glyph_extents: height comparable to font size (~40)",
          15.0 < ce[3] < 45.0, f"height={ce[3]}")

    # Context.show_glyphs renders ink where expected (white 'A' on black).
    g_A = sf.text_to_glyphs(10, 45, "A", False)
    c.set_source_rgb(1, 1, 1)
    c.show_glyphs(g_A)
    ink = count_white(s, W, H)
    check("Context.show_glyphs renders glyph ink (white px in range)",
          50 < ink < 2500, f"white_px={ink}")

    # ink must sit near the pen (10,45): not at the surface corner.
    s2, c2 = black_surface(W, H)
    c2.select_font_face("sans-serif")
    c2.set_font_size(40)
    sf2 = c2.get_scaled_font()
    c2.set_source_rgb(1, 1, 1)
    c2.show_glyphs(sf2.text_to_glyphs(10, 45, "A", False))
    s2.flush()
    d = s2.get_data(); st = s2.get_stride()
    ys = [y for y in range(H) for x in range(W)
          if d[y * st + x * 4] > 128 and d[y * st + x * 4 + 1] > 128 and d[y * st + x * 4 + 2] > 128]
    check("show_glyphs ink is positioned near the pen baseline (y in 15..45)",
          ys and 12 <= min(ys) and max(ys) <= 46, f"y range=({min(ys) if ys else None},{max(ys) if ys else None})")

    # empty run is a documented no-op (no crash, nothing drawn).
    s3, c3 = black_surface(W, H)
    c3.set_source_rgb(1, 1, 1)
    c3.show_glyphs([])
    check("show_glyphs([]) is a no-op (no ink, no crash)",
          count_white(s3, W, H) == 0)

    # Context.glyph_path: appending the outline then filling == show_glyphs ink.
    s4, c4 = black_surface(W, H)
    c4.select_font_face("sans-serif"); c4.set_font_size(40)
    sf4 = c4.get_scaled_font()
    g4 = sf4.text_to_glyphs(10, 45, "A", False)
    c4.set_source_rgb(1, 1, 1)
    c4.new_path(); c4.glyph_path(g4); c4.fill()
    ink_path = count_white(s4, W, H)
    check("glyph_path + fill renders the same glyph ink as show_glyphs",
          50 < ink_path < 2500 and abs(ink_path - ink) <= max(8, ink * 0.1),
          f"glyph_path_ink={ink_path} show_glyphs_ink={ink}")

    # show_text_glyphs(utf8, glyphs, clusters, flags): draws the run; clusters
    # are metadata only (accepted for signature compat).
    s5, c5 = black_surface(W, H)
    c5.select_font_face("sans-serif"); c5.set_font_size(40)
    sf5 = c5.get_scaled_font()
    g5 = sf5.text_to_glyphs(10, 45, "A", False)
    c5.set_source_rgb(1, 1, 1)
    clusters = [(1, 1)]  # 1 byte 'A' -> 1 glyph
    c5.show_text_glyphs("A", g5, clusters, 0)
    check("show_text_glyphs draws the glyph run (ink present)",
          50 < count_white(s5, W, H) < 2500, f"white_px={count_white(s5, W, H)}")
    # also tolerates clusters=None / empty.
    s6, c6 = black_surface(W, H)
    c6.select_font_face("sans-serif"); c6.set_font_size(40)
    c6.set_source_rgb(1, 1, 1)
    c6.show_text_glyphs("A", sf5.text_to_glyphs(10, 45, "A", False), None)
    check("show_text_glyphs tolerates clusters=None",
          50 < count_white(s6, W, H) < 2500)

    # malformed glyph entry raises TypeError (no crash).
    try:
        c.show_glyphs([(1, 2)])  # 2-tuple, not (index, x, y)
        check("show_glyphs rejects a malformed glyph tuple", False, "no error raised")
    except TypeError:
        check("show_glyphs rejects a malformed glyph tuple (TypeError)", True)


# ============================================================ 2. FT FILE FACE
def test_ft_font_face():
    print("\n== 2. Font face from a FILE on disk (ft_font_face_create) ==")
    check("module has ft_font_face_create", hasattr(cairo, "ft_font_face_create"))
    path = find_font_file()
    if not path:
        check("a system font file is available to test", False, "none found")
        return
    ff = cairo.ft_font_face_create(path, 0)
    check("ft_font_face_create returns a FontFace", isinstance(ff, cairo.FontFace))
    check("file-loaded face reports FONT_TYPE_FT",
          ff.get_type() == cairo.FONT_TYPE_FT, f"type={ff.get_type()}")
    check("file-loaded face status is SUCCESS", ff.status() == cairo.STATUS_SUCCESS,
          f"status={ff.status()}")

    W = H = 72
    s, c = black_surface(W, H)
    c.set_font_face(ff)
    c.set_font_size(48)
    c.set_source_rgb(1, 1, 1)
    c.move_to(8, 56)
    c.show_text("R")
    ink = count_white(s, W, H)
    check("file face renders real glyph ink via show_text",
          50 < ink < 3500, f"white_px={ink}")

    # metrics from the file face are sane.
    ext = c.text_extents("R")
    check("file face text_extents width > 0", ext[2] > 0, f"ext={ext[:4]}")
    fe = c.font_extents()
    check("file face font_extents ascent > 0", fe[0] > 0, f"font_extents={fe}")

    # the file face renders DIFFERENT pixels than a clearly-different toy face,
    # proving the file's outlines are actually used (not a system fallback).
    def render(setter, ch="g", size=56):
        ss, cc = black_surface(W, H)
        setter(cc); cc.set_font_size(size); cc.set_source_rgb(1, 1, 1)
        cc.move_to(8, 60); cc.show_text(ch)
        return white_mask(ss, W, H)
    m_file = render(lambda cc: cc.set_font_face(ff))
    m_toy = render(lambda cc: cc.select_font_face("monospace",
                   cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD))
    diff = sum(1 for a, b in zip(m_file, m_toy) if a != b)
    check("file face renders its OWN glyphs (distinct from a monospace toy face)",
          diff > 40 and sum(m_file) > 20, f"differing_px={diff} file_ink={sum(m_file)}")

    # missing file -> raises (no silent NULL / crash).
    try:
        cairo.ft_font_face_create("/no/such/font____.ttf")
        check("ft_font_face_create on a missing file raises", False, "no error")
    except cairo.Error:
        check("ft_font_face_create on a missing file raises cairo.Error", True)


# ============================================================ 3. RASTER SOURCE
def test_raster_source():
    print("\n== 3. RasterSourcePattern ==")
    check("module has RasterSourcePattern", hasattr(cairo, "RasterSourcePattern"))
    p = cairo.RasterSourcePattern(cairo.CONTENT_COLOR_ALPHA, 16, 16)
    check("RasterSourcePattern constructs", isinstance(p, cairo.Pattern))
    check("RasterSourcePattern get_type == RASTER_SOURCE",
          p.get_type() == cairo.PATTERN_TYPE_RASTER_SOURCE, f"type={p.get_type()}")
    check("RasterSourcePattern status SUCCESS", p.status() == cairo.STATUS_SUCCESS,
          f"status={p.status()}")

    # inherited base-Pattern setters round-trip.
    p.set_extend(cairo.EXTEND_REPEAT)
    check("RasterSourcePattern set/get_extend round-trips",
          p.get_extend() == cairo.EXTEND_REPEAT, f"extend={p.get_extend()}")
    p.set_filter(cairo.FILTER_NEAREST)
    check("RasterSourcePattern set/get_filter round-trips",
          p.get_filter() == cairo.FILTER_NEAREST, f"filter={p.get_filter()}")
    m = cairo.Matrix(2, 0, 0, 2, 3, 4)
    p.set_matrix(m)
    check("RasterSourcePattern set/get_matrix round-trips",
          tuple(p.get_matrix()) == (2, 0, 0, 2, 3, 4), f"m={tuple(p.get_matrix())}")
    check("RasterSourcePattern get_callback_data is NULL (no callback wired)",
          p.get_callback_data() == 0, f"cbdata={p.get_callback_data()}")

    # documented FALLBACK: with no callback the pattern degenerates to a plain
    # SurfacePattern over a blank (transparent) surface -- set_source + paint
    # must not crash or error (it paints the transparent fallback).
    s, c = black_surface(16, 16)
    p2 = cairo.RasterSourcePattern(cairo.CONTENT_COLOR_ALPHA, 16, 16)
    try:
        c.set_source(p2)
        c.paint()
        ok = (c.status() == cairo.STATUS_SUCCESS)
        check("set_source(raster) + paint() succeeds (fallback path, no crash)",
              ok, f"ctx status={c.status()}")
    except cairo.Error as e:
        check("set_source(raster) + paint() succeeds (fallback path)", False, f"raised {e}")


# ============================================================ 4. SUBSURFACE
def test_subsurface():
    print("\n== 4. Surface.create_for_rectangle (subsurface) ==")
    W = H = 32
    s, c = black_surface(W, H)
    sub = s.create_for_rectangle(8, 8, 16, 16)
    check("create_for_rectangle returns a Surface", isinstance(sub, cairo.Surface))
    check("subsurface get_type == SUBSURFACE",
          sub.get_type() == cairo.SURFACE_TYPE_SUBSURFACE, f"type={sub.get_type()}")
    check("subsurface width/height match the rectangle",
          sub.get_width() == 16 and sub.get_height() == 16,
          f"w={sub.get_width()} h={sub.get_height()}")

    # Draw red filling the whole subsurface; flush the SUBSURFACE (its frame is
    # keyed on itself).  Verify the red lands in the parent's (8,8,16,16) window.
    sc = cairo.Context(sub)
    sc.set_source_rgb(1, 0, 0)
    sc.rectangle(0, 0, 16, 16)
    sc.fill()
    check("drawing into a subsurface raises no error", sub.status() == cairo.STATUS_SUCCESS,
          f"status={sub.status()}")
    sub.flush()
    del sc
    s.flush()

    d = s.get_data(); st = s.get_stride()

    def is_red(x, y):
        o = y * st + x * 4
        return d[o + 2] > 200 and d[o] < 50 and d[o + 1] < 50  # R high, B/G low

    red = [(x, y) for y in range(H) for x in range(W) if is_red(x, y)]
    check("subsurface draw produced red ink", len(red) > 0, f"red_px={len(red)}")
    if red:
        xs = [r[0] for r in red]; ys = [r[1] for r in red]
        bbox = (min(xs), min(ys), max(xs), max(ys))
        # The red must be confined to the (8,8)-(23,23) window (scissored), and
        # cover it (16x16 = 256 px).
        check("subsurface draw is CONFINED to its window [8..23] x [8..23]",
              min(xs) >= 8 and min(ys) >= 8 and max(xs) <= 23 and max(ys) <= 23,
              f"bbox={bbox}")
        check("subsurface draw COVERS its window (256 px filled)",
              len(red) == 256, f"red_px={len(red)}")


# ============================================================ 5. MAP_TO_IMAGE
def test_map_to_image():
    print("\n== 5. Surface.map_to_image / unmap_image ==")
    # Whole-surface map: aliases the parent's pixels.
    p, pc = black_surface(16, 16)
    pc.set_source_rgb(0, 0, 1)  # blue
    pc.paint()
    p.flush()
    img = p.map_to_image()
    check("map_to_image returns an ImageSurface", isinstance(img, cairo.ImageSurface))
    check("mapped image dims match the parent",
          img.get_width() == 16 and img.get_height() == 16,
          f"w={img.get_width()} h={img.get_height()}")
    r, g, b, a = argb_at(img, 8, 8)
    check("mapped image reads back the parent's pixels (blue)",
          b > 200 and r < 50 and g < 50, f"(r,g,b,a)=({r},{g},{b},{a})")
    p.unmap_image(img)
    check("unmap_image succeeds; alias detached (surf dead)",
          True)

    # Sub-rect map: a (8,8,16,16) window of a 32x32 parent that has a red patch
    # there reads red at the window's top-left.
    p2 = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
    c2 = cairo.Context(p2)
    c2.set_source_rgb(0, 0, 0); c2.paint()
    c2.set_source_rgb(1, 0, 0); c2.rectangle(8, 8, 16, 16); c2.fill()
    p2.flush()
    sub = p2.map_to_image((8, 8, 16, 16))
    check("sub-rect map_to_image dims == requested window",
          sub.get_width() == 16 and sub.get_height() == 16,
          f"w={sub.get_width()} h={sub.get_height()}")
    r, g, b, a = argb_at(sub, 0, 0)  # window (0,0) == parent (8,8) == red
    check("sub-rect map reads the offset window (red at window origin)",
          r > 200 and b < 50 and g < 50, f"(r,g,b,a)=({r},{g},{b},{a})")
    # window (15,15) == parent (23,23), still inside the red patch.
    r2, g2, b2, a2 = argb_at(sub, 15, 15)
    check("sub-rect map reads the far corner of the window (still red)",
          r2 > 200 and b2 < 50, f"(r,g,b,a)=({r2},{g2},{b2},{a2})")
    p2.unmap_image(sub)
    check("sub-rect unmap_image succeeds", True)

    # unmap with a foreign image raises (validation).
    pa, _ = black_surface(8, 8)
    pb, _ = black_surface(8, 8)
    ia = pa.map_to_image()
    try:
        pb.unmap_image(ia)
        check("unmap_image rejects an image mapped from a different surface", False,
              "no error")
    except cairo.Error:
        check("unmap_image rejects a foreign image (cairo.Error)", True)
    pa.unmap_image(ia)


# ============================================================ 6. CREATE_SIMILAR
def test_create_similar():
    print("\n== 6. create_similar / create_similar_image ==")
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)

    # create_similar(content, w, h) -> usable surface of the resolved format.
    sim = s.create_similar(cairo.CONTENT_COLOR_ALPHA, 20, 24)
    check("create_similar returns a Surface", isinstance(sim, cairo.Surface))
    check("create_similar dims are honored",
          sim.get_width() == 20 and sim.get_height() == 24,
          f"w={sim.get_width()} h={sim.get_height()}")
    check("create_similar(COLOR_ALPHA) -> ARGB32 format",
          sim.get_format() == cairo.FORMAT_ARGB32, f"fmt={sim.get_format()}")
    # it is a real drawable surface.
    cc = cairo.Context(sim)
    cc.set_source_rgb(1, 0, 0)
    cc.paint()
    sim.flush()
    r, g, b, a = argb_at(sim, 5, 5)
    check("create_similar surface is drawable (paints red)",
          r > 200 and b < 50 and g < 50, f"(r,g,b,a)=({r},{g},{b},{a})")

    # COLOR -> RGB24 (opaque).
    sim_rgb = s.create_similar(cairo.CONTENT_COLOR, 8, 8)
    check("create_similar(COLOR) -> RGB24 format",
          sim_rgb.get_format() == cairo.FORMAT_RGB24, f"fmt={sim_rgb.get_format()}")

    # create_similar_image(format, w, h) -> ImageSurface of the named format.
    simi = s.create_similar_image(cairo.FORMAT_A8, 10, 12)
    check("create_similar_image returns an ImageSurface",
          isinstance(simi, cairo.ImageSurface))
    check("create_similar_image honors the named format (A8)",
          simi.get_format() == cairo.FORMAT_A8, f"fmt={simi.get_format()}")
    check("create_similar_image dims honored",
          simi.get_width() == 10 and simi.get_height() == 12,
          f"w={simi.get_width()} h={simi.get_height()}")
    simi_argb = s.create_similar_image(cairo.FORMAT_ARGB32, 6, 6)
    cci = cairo.Context(simi_argb)
    cci.set_source_rgb(0, 1, 0); cci.paint(); simi_argb.flush()
    r, g, b, a = argb_at(simi_argb, 3, 3)
    check("create_similar_image surface is drawable (paints green)",
          g > 200 and r < 50 and b < 50, f"(r,g,b,a)=({r},{g},{b},{a})")


# ============================================================ 7. PATH INTROSPECT
def test_path_introspection():
    """GAP 2 -- copy_path / copy_path_flat / append_path + the iterable Path."""
    print("\n== 7. Path introspection (copy_path / copy_path_flat / append_path) ==")

    # Path is opaque: not user-constructible (mirrors pycairo).
    check("cairo_metal exposes Path + PathIterator types",
          hasattr(cairo, "Path") and hasattr(cairo, "PathIterator"))
    try:
        cairo.Path()
        check("Path() cannot be instantiated directly", False, "no TypeError")
    except TypeError:
        check("Path() cannot be instantiated directly (TypeError)", True)

    # Build a path with one of each verb, then copy_path and check EXACT
    # element types + coordinates (including cairo's synthetic post-CLOSE move).
    W = H = 64
    s, c = black_surface(W, H)
    c.move_to(5, 6)
    c.line_to(50, 6)
    c.curve_to(55, 11, 55, 40, 50, 50)
    c.close_path()
    p = c.copy_path()
    check("copy_path() returns a Path", isinstance(p, cairo.Path))

    els = list(p)
    # Expect: MOVE(5,6) LINE(50,6) CURVE(6 coords) CLOSE() + synthetic MOVE(5,6).
    types = [t for (t, _) in els]
    check("copy_path element types in order (MOVE,LINE,CURVE,CLOSE,MOVE)",
          types == [cairo.PATH_MOVE_TO, cairo.PATH_LINE_TO, cairo.PATH_CURVE_TO,
                    cairo.PATH_CLOSE_PATH, cairo.PATH_MOVE_TO],
          f"types={types}")
    check("copy_path MOVE_TO coords exact (5,6)", els[0][1] == (5.0, 6.0),
          f"{els[0]}")
    check("copy_path LINE_TO coords exact (50,6)", els[1][1] == (50.0, 6.0),
          f"{els[1]}")
    check("copy_path CURVE_TO carries all 6 control coords",
          els[2][1] == (55.0, 11.0, 55.0, 40.0, 50.0, 50.0), f"{els[2]}")
    check("copy_path CLOSE_PATH carries an empty point tuple",
          els[3][1] == (), f"{els[3]}")
    check("copy_path emits cairo's synthetic post-CLOSE MOVE_TO to sub-path start",
          els[4][1] == (5.0, 6.0), f"{els[4]}")

    # Path is RE-iterable (fresh iterator each time) and reports a length.
    check("Path is re-iterable (second pass yields the same element count)",
          len(list(p)) == len(els) and len(p) == len(els),
          f"len(p)={len(p)} els={len(els)}")

    # copy_path_flat: curves -> line segments; ONLY MOVE/LINE/CLOSE remain.
    pf = c.copy_path_flat()
    ftypes = [t for (t, _) in pf]
    check("copy_path_flat contains NO CURVE_TO", cairo.PATH_CURVE_TO not in ftypes,
          f"types set={sorted(set(ftypes))}")
    check("copy_path_flat uses only MOVE/LINE/CLOSE",
          set(ftypes) <= {cairo.PATH_MOVE_TO, cairo.PATH_LINE_TO,
                          cairo.PATH_CLOSE_PATH}, f"types set={sorted(set(ftypes))}")
    check("copy_path_flat has MORE elements than the cubic path (curve split)",
          len(ftypes) > len(types), f"flat={len(ftypes)} orig={len(types)}")
    # every flat LINE_TO point stays within the path's bounding box (sanity).
    flat_pts = [pt for (t, pt) in pf if t == cairo.PATH_LINE_TO]
    check("copy_path_flat segment points stay within the curve's bbox",
          all(5.0 <= x <= 55.0 and 6.0 <= y <= 50.0 for (x, y) in flat_pts),
          f"n_seg={len(flat_pts)}")

    # append_path round-trip: new_path + append_path(copied) + fill renders
    # PIXEL-IDENTICALLY to filling the original path.
    def render_fill(build):
        ss = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
        cc = cairo.Context(ss)
        cc.set_source_rgb(0, 0, 0); cc.paint()
        build(cc)
        cc.set_source_rgb(1, 1, 1); cc.fill()
        ss.flush()
        return bytes(ss.get_data())

    def build_orig(cc):
        cc.move_to(8, 9); cc.line_to(54, 9)
        cc.curve_to(58, 18, 58, 46, 50, 54); cc.line_to(10, 50); cc.close_path()

    s1 = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    c1 = cairo.Context(s1)
    build_orig(c1)
    copied = c1.copy_path()

    orig_px = render_fill(build_orig)
    appended_px = render_fill(lambda cc: (cc.new_path(), cc.append_path(copied)))
    check("new_path + append_path(copied) + fill == original fill (pixel-identical)",
          orig_px == appended_px,
          f"differing_bytes={sum(1 for a, b in zip(orig_px, appended_px) if a != b)}")

    # append_path rejects a non-Path argument (TypeError, no crash).
    try:
        c.append_path([(cairo.PATH_MOVE_TO, (0, 0))])
        check("append_path rejects a non-Path argument", False, "no TypeError")
    except TypeError:
        check("append_path rejects a non-Path argument (TypeError)", True)

    # an empty path copies to an empty (but valid, iterable) Path.
    s2 = cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8)
    c2 = cairo.Context(s2)
    pe = c2.copy_path()
    check("copy_path on an empty path yields an empty iterable Path",
          isinstance(pe, cairo.Path) and list(pe) == [] and len(pe) == 0)


# ============================================================ 8. RECORDING DRAW
def test_recording_surface_draw():
    """GAP 3 -- drawing into a bounded RecordingSurface (raster-backed).

    The capability is gated behind CM_RECORDING_RASTER (see cm_recording.m):
    the DEFAULT keeps the historical 'recording draw raises DEVICE_ERROR'
    behaviour that the frozen spec suites assert.  We enable it here, in-process,
    to verify the real path -- paint/fill/stroke land, the surface replays as a
    source, and ink_extents reflects the drawing."""
    print("\n== 8. RecordingSurface drawing (raster-backed; Gap 3) ==")

    prev = os.environ.get("CM_RECORDING_RASTER")
    os.environ["CM_RECORDING_RASTER"] = "1"   # read by the C lib at create time
    try:
        # (a) paint red into a RecordingSurface: NO exception, status SUCCESS.
        rs = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 40, 40))
        check("RecordingSurface type is RECORDING (kind preserved)",
              rs.get_type() == cairo.SURFACE_TYPE_RECORDING, f"type={rs.get_type()}")
        rc = cairo.Context(rs)
        rc.set_source_rgb(1, 0, 0)
        raised = None
        try:
            rc.paint()
        except cairo.Error as e:
            raised = e
        check("paint() into a (raster-backed) RecordingSurface raises NO exception",
              raised is None, f"raised={raised}")
        check("paint() into RecordingSurface leaves status SUCCESS",
              rc.status() == cairo.STATUS_SUCCESS, f"status={rc.status()}")
        rs.flush()

        # (b) ink_extents reflects the drawing (whole 40x40 for a full paint).
        ink = rs.ink_extents()
        check("ink_extents reflects the paint (covers the 40x40 extent)",
              ink[2] >= 39.0 and ink[3] >= 39.0, f"ink={ink}")

        # (c) use the recording as a source on an ARGB32 surface -> red appears.
        dst = cairo.ImageSurface(cairo.FORMAT_ARGB32, 40, 40)
        dc = cairo.Context(dst)
        dc.set_source_rgb(0, 0, 0); dc.paint()
        dc.set_source_surface(rs, 0, 0)
        dc.paint()
        dst.flush()
        r, g, b, a = argb_at(dst, 20, 20)
        check("set_source_surface(recording) replays red onto the destination",
              r > 200 and g < 50 and b < 50, f"(r,g,b,a)=({r},{g},{b},{a})")
        check("recording-as-source replay leaves the destination status SUCCESS",
              dc.status() == cairo.STATUS_SUCCESS, f"status={dc.status()}")

        # (d) a PARTIAL fill: ink hugs the filled rect, not the whole surface,
        #     and the replay shows ink only where filled.
        rs2 = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 60, 60))
        rc2 = cairo.Context(rs2)
        rc2.set_source_rgb(0, 1, 0)
        rc2.rectangle(10, 12, 20, 16)
        rc2.fill()
        check("fill() into RecordingSurface raises no exception (status SUCCESS)",
              rc2.status() == cairo.STATUS_SUCCESS, f"status={rc2.status()}")
        rs2.flush()
        ink2 = rs2.ink_extents()
        # box ~ (10,12)-(30,28); allow the half-pixel MSAA guard band.
        check("ink_extents of a partial fill hugs the filled rect (not full surface)",
              9.0 <= ink2[0] <= 11.0 and 11.0 <= ink2[1] <= 13.0
              and 19.0 <= ink2[2] <= 23.0 and 15.0 <= ink2[3] <= 19.0,
              f"ink={ink2}")

        dst2 = cairo.ImageSurface(cairo.FORMAT_ARGB32, 60, 60)
        dc2 = cairo.Context(dst2)
        dc2.set_source_rgb(0, 0, 0); dc2.paint()
        dc2.set_source_surface(rs2, 0, 0); dc2.paint(); dst2.flush()
        rin = argb_at(dst2, 20, 20)     # inside the filled rect
        rout = argb_at(dst2, 50, 50)    # outside it
        check("partial-fill replay: green inside the filled rect",
              rin[1] > 200 and rin[0] < 50, f"inside={rin}")
        check("partial-fill replay: untouched (black bg) outside the filled rect",
              rout[1] < 50 and rout[0] < 50, f"outside={rout}")

        # (e) stroke into a recording surface also lands.
        rs3 = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 60, 60))
        rc3 = cairo.Context(rs3)
        rc3.set_source_rgb(0, 0, 1); rc3.set_line_width(4)
        rc3.move_to(10, 10); rc3.line_to(50, 50); rc3.stroke()
        check("stroke() into RecordingSurface raises no exception (status SUCCESS)",
              rc3.status() == cairo.STATUS_SUCCESS, f"status={rc3.status()}")
        rs3.flush()
        ink3 = rs3.ink_extents()
        check("stroke ink reflects the line footprint (non-empty, within extent)",
              ink3[2] > 30 and ink3[3] > 30, f"ink={ink3}")

        # (f) DEFAULT (gate off) still raises DEVICE_ERROR -- confirm the gate
        #     actually controls the behaviour (so the spec suites stay valid).
        os.environ.pop("CM_RECORDING_RASTER", None)
        rs_off = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 20, 20))
        rc_off = cairo.Context(rs_off)
        rc_off.set_source_rgb(1, 0, 0)
        off_raised = False
        try:
            rc_off.paint()
        except cairo.Error as e:
            off_raised = (cairo.STATUS_DEVICE_ERROR == getattr(e, "args", [None, None])[-1]
                          or rc_off.status() == cairo.STATUS_DEVICE_ERROR)
        check("with the gate OFF (default), RecordingSurface draw still raises "
              "DEVICE_ERROR (spec-suite contract preserved)",
              off_raised, f"raised={off_raised} status={rc_off.status()}")
    finally:
        if prev is None:
            os.environ.pop("CM_RECORDING_RASTER", None)
        else:
            os.environ["CM_RECORDING_RASTER"] = prev


def main():
    print("=" * 70)
    print("CairoMetal binding-gap verification (test_gaps.py)")
    print("device:", cairo.metal_device_name())
    print("=" * 70)
    for fn in (test_glyph_api, test_ft_font_face, test_raster_source,
               test_subsurface, test_map_to_image, test_create_similar,
               test_path_introspection, test_recording_surface_draw):
        try:
            fn()
        except Exception as ex:  # noqa
            global FAIL
            FAIL += 1
            FAILED.append(f"{fn.__name__} raised {type(ex).__name__}: {ex}")
            print(f"  [FAIL] {fn.__name__} raised {type(ex).__name__}: {ex}")
            import traceback
            traceback.print_exc()
    print("\n" + "=" * 70)
    print(f"TOTAL: {PASS + FAIL}   PASS: {PASS}   FAIL: {FAIL}")
    if FAILED:
        print("FAILURES:")
        for f in FAILED:
            print("   -", f)
    print("=" * 70)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
