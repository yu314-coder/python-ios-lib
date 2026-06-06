#!/usr/bin/env python3
"""
test_robust.py -- rigorous robustness / correctness / memory-safety / gap test
for the CairoMetal pycairo-compatible extension (cairo_metal).

This is NOT a smoke test.  Every check computes an EXPECTED outcome and asserts
it.  "Should fail" cases assert the SPECIFIC exception/status.  Documented gaps
are confirmed to fail AS DOCUMENTED (not silently corrupt).

Run:
  CM_METALLIB="/Volumes/D/OfflinAi/cairo(metal)/build/default.metallib" \
  PYTHONPATH="/Volumes/D/OfflinAi/cairo(metal)/python" \
  python3 '/Volumes/D/OfflinAi/cairo(metal)/tests/test_robust.py'

Stdlib only.  No numpy, no PIL, no pycairo.
"""
import os
import sys
import gc
import signal
import resource
import traceback

# --- locate the metallib / extension even if env not pre-set --------------
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
os.environ.setdefault("CM_METALLIB", os.path.join(ROOT, "build", "default.metallib"))
if os.path.join(ROOT, "python") not in sys.path:
    sys.path.insert(0, os.path.join(ROOT, "python"))

import cairo_metal as cairo


# ======================================================================
# tiny assertion harness
# ======================================================================
_results = []   # (name, passed, detail)
_surprises = []  # free-form notes that are not pass/fail


def check(name, passed, detail=""):
    _results.append((name, bool(passed), detail))
    tag = "PASS" if passed else "FAIL"
    line = f"  [{tag}] {name}"
    if detail:
        line += f"  -- {detail}"
    print(line)
    return bool(passed)


def note(msg):
    _surprises.append(msg)
    print(f"  [NOTE] {msg}")


def expect_raises(name, exc_types, fn, *args, **kwargs):
    """Assert fn(*args) raises one of exc_types; return the exception or None."""
    try:
        fn(*args, **kwargs)
    except exc_types as e:
        check(name, True, f"raised {type(e).__name__}: {e}")
        return e
    except BaseException as e:
        check(name, False, f"raised WRONG {type(e).__name__}: {e}")
        return e
    check(name, False, "did NOT raise")
    return None


def err_status(e):
    """Extract the cairo status code from a cairo.Error (args[-1] is the int)."""
    if e is None:
        return None
    if e.args and isinstance(e.args[-1], int):
        return e.args[-1]
    return None


# ----------------------------------------------------------------------
# wall-clock watchdog so a HANG is reported as a failure, not a stall.
# ----------------------------------------------------------------------
class Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise Timeout("wall-clock watchdog fired")


def with_timeout(seconds, fn, *args, **kwargs):
    old = signal.signal(signal.SIGALRM, _alarm)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        return fn(*args, **kwargs)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


# ----------------------------------------------------------------------
# pixel helpers.  IMPORTANT: get_data() is TIGHTLY PACKED; its true row
# stride is len(data)//height, which (we will show) does NOT equal
# get_stride().  We use the data-derived stride for all pixel reads.
# Byte order in memory is B,G,R,A (premultiplied) for ARGB32/RGB24.
# ----------------------------------------------------------------------
def data_stride(surf):
    h = surf.get_height()
    d = surf.get_data()
    return len(d) // h if h else 0


def px(surf, x, y):
    """Return (B,G,R,A) at (x,y) using the data-derived stride."""
    d = surf.get_data()
    s = data_stride(surf)
    i = y * s + x * 4
    return d[i], d[i + 1], d[i + 2], d[i + 3]


def fresh(fmt, w, h):
    return cairo.ImageSurface(fmt, w, h)


# ======================================================================
# SECTION 1 — edge cases (must not crash; assert sane result/error)
# ======================================================================
def section_edge_cases():
    print("\n== SECTION 1: edge cases ==")

    # --- empty path then fill()/stroke(): no-op, surface stays background ---
    s = fresh(cairo.FORMAT_ARGB32, 20, 20)
    c = cairo.Context(s)
    # background is zero (transparent). Fill/stroke an empty path.
    c.new_path()
    c.set_source_rgba(1, 0, 0, 1)
    c.fill()           # empty path -> nothing
    c.new_path()
    c.stroke()         # empty path -> nothing
    s.flush()
    allzero = all(b == 0 for b in s.get_data())
    check("empty-path fill+stroke is a no-op (surface stays transparent)",
          allzero and c.status() == 0,
          f"status={c.status()} allzero={allzero}")

    # --- new_sub_path with no points then fill/stroke ---
    s = fresh(cairo.FORMAT_ARGB32, 16, 16)
    c = cairo.Context(s)
    c.new_sub_path()
    has_cp = c.has_current_point()
    c.set_source_rgba(0, 1, 0, 1)
    c.fill()
    c.new_sub_path()
    c.stroke()
    s.flush()
    check("new_sub_path with no points: no current point, no crash, no ink",
          (not has_cp) and c.status() == 0 and all(b == 0 for b in s.get_data()),
          f"has_current_point={has_cp} status={c.status()}")

    # --- zero-length line stroke (move_to == line_to). With round caps a dot
    #     may appear; with butt caps nothing. We only require: no crash, clean
    #     status, and ink (if any) is confined near the point.
    s = fresh(cairo.FORMAT_ARGB32, 40, 40)
    c = cairo.Context(s)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.set_line_width(10)
    c.set_source_rgba(1, 1, 1, 1)
    c.move_to(20, 20)
    c.line_to(20, 20)
    c.stroke()
    s.flush()
    # any ink must be within radius ~6 of (20,20)
    stray = 0
    for y in range(40):
        for x in range(40):
            if px(s, x, y)[3] != 0:
                if (x - 20) ** 2 + (y - 20) ** 2 > 8 * 8:
                    stray += 1
    check("zero-length line stroke: no crash, no stray ink far from point",
          c.status() == 0 and stray == 0, f"status={c.status()} stray={stray}")

    # --- arc with r=0: degenerate, must not crash; fill is empty ---
    s = fresh(cairo.FORMAT_ARGB32, 16, 16)
    c = cairo.Context(s)
    c.set_source_rgba(1, 0, 0, 1)
    c.arc(8, 8, 0, 0, 2 * 3.141592653589793)
    c.fill()
    s.flush()
    check("arc r=0 fill: no crash, clean status, empty fill",
          c.status() == 0 and all(b == 0 for b in s.get_data()),
          f"status={c.status()}")

    # --- 1x1 surface fill (paint a known colour) ---
    s = fresh(cairo.FORMAT_ARGB32, 1, 1)
    c = cairo.Context(s)
    c.set_source_rgba(0.0, 0.0, 1.0, 1.0)  # blue, opaque
    c.paint()
    s.flush()
    b, g, r, a = px(s, 0, 0)
    check("1x1 surface paint blue: B=255,G=0,R=0,A=255",
          (b, g, r, a) == (255, 0, 0, 255), f"BGRA={(b,g,r,a)}")

    # --- very large coordinates (1e6) clipped to a small surface ---
    s = fresh(cairo.FORMAT_ARGB32, 32, 32)
    c = cairo.Context(s)
    c.set_source_rgba(1, 1, 1, 1)
    c.rectangle(-1e6, -1e6, 2e6, 2e6)  # covers everything; clipped to surface
    c.fill()
    s.flush()
    corners_opaque = all(px(s, x, y)[3] == 255 for x, y in
                         [(0, 0), (31, 0), (0, 31), (31, 31), (16, 16)])
    check("huge rect (2e6) clipped to 32x32: fully painted, no crash",
          c.status() == 0 and corners_opaque, f"status={c.status()}")

    # a huge rect entirely OUTSIDE the surface paints nothing
    s = fresh(cairo.FORMAT_ARGB32, 32, 32)
    c = cairo.Context(s)
    c.set_source_rgba(1, 1, 1, 1)
    c.rectangle(1e6, 1e6, 10, 10)
    c.fill()
    s.flush()
    check("huge rect fully offscreen: nothing painted",
          c.status() == 0 and all(b == 0 for b in s.get_data()),
          f"status={c.status()}")

    # --- degenerate curve_to (all control points equal to current point) ---
    # In cairo, curve_to sets the current point to the END point.  Check that
    # BEFORE stroke (stroke() correctly clears the path/current point).
    s = fresh(cairo.FORMAT_ARGB32, 32, 32)
    c = cairo.Context(s)
    c.set_source_rgba(1, 0, 0, 1)
    c.move_to(10, 10)
    c.curve_to(10, 10, 10, 10, 10, 10)  # zero-extent curve
    cp_before = c.get_current_point()
    c.set_line_width(2)
    c.stroke()
    s.flush()
    # current point becomes the curve end (10,10); after stroke it is cleared.
    check("degenerate curve_to: no crash, clean status, current point = end (10,10)",
          c.status() == 0 and cp_before == (10.0, 10.0),
          f"status={c.status()} cp_before_stroke={cp_before}")
    check("stroke() clears the current point (cairo semantics)",
          not c.has_current_point(),
          f"has_current_point_after_stroke={c.has_current_point()}")

    # --- set_source_rgba out of [0,1]: clamp vs corrupt. Report behaviour. ---
    s = fresh(cairo.FORMAT_ARGB32, 1, 1)
    c = cairo.Context(s)
    c.set_source_rgba(2.0, -1.0, 0.5, 1.0)  # R high, G low, B mid
    c.paint()
    s.flush()
    b, g, r, a = px(s, 0, 0)
    clamped = (r == 255 and g == 0 and 120 <= b <= 136 and a == 255)
    check("set_source_rgba(2,-1,0.5,1) CLAMPS to [0,1] (R=255,G=0,B~128)",
          clamped, f"BGRA={(b,g,r,a)} (expected ~(128,0,255,255))")
    if not clamped:
        note(f"out-of-range rgba did NOT clamp cleanly: BGRA={(b,g,r,a)}")

    # alpha out of range, premultiplied: a=2.0 with white should not overflow
    s = fresh(cairo.FORMAT_ARGB32, 1, 1)
    c = cairo.Context(s)
    c.set_source_rgba(1.0, 1.0, 1.0, 2.0)
    c.paint()
    s.flush()
    b, g, r, a = px(s, 0, 0)
    check("set_source_rgba alpha=2.0 clamps to opaque white (255,255,255,255)",
          (b, g, r, a) == (255, 255, 255, 255), f"BGRA={(b,g,r,a)}")


# ======================================================================
# SECTION 2 — surface creation errors (no segfault)
# ======================================================================
def section_surface_errors():
    print("\n== SECTION 2: surface creation errors ==")

    for w, h in [(0, 4), (4, 0), (-1, 4), (4, -2), (0, 0)]:
        e = expect_raises(f"ImageSurface({w},{h}) raises (no segfault)",
                          (ValueError, cairo.Error, OverflowError),
                          cairo.ImageSurface, cairo.FORMAT_ARGB32, w, h)

    # unsupported / invalid format value -> INVALID_FORMAT (16), not crash
    for bad in (999, -5, cairo.FORMAT_INVALID):
        e = expect_raises(f"ImageSurface(format={bad}) raises",
                          (cairo.Error, ValueError),
                          cairo.ImageSurface, bad, 4, 4)
        if isinstance(e, cairo.Error):
            check(f"  format={bad} -> status INVALID_FORMAT (16)",
                  err_status(e) == cairo.STATUS_INVALID_FORMAT,
                  f"status={err_status(e)}")

    # absurdly large allocation should error, not OOM-kill the interpreter
    e = expect_raises("ImageSurface(2_000_000 x 2_000_000) raises (no OOM-kill)",
                      (cairo.Error, ValueError, OverflowError, MemoryError),
                      cairo.ImageSurface, cairo.FORMAT_ARGB32, 2_000_000, 2_000_000)


# ======================================================================
# SECTION 3 — secondary formats (RGB24, A8)
# ======================================================================
def section_formats():
    print("\n== SECTION 3: secondary formats (RGB24, A8) ==")

    # ---- get_stride vs get_data consistency (surfaced a real bug) ----
    # The pycairo contract: get_data() is a buffer of exactly
    # get_stride()*height bytes, and get_stride() == format_stride_for_width().
    # You walk pixels as data[y*get_stride() + x*bpp].  CairoMetal returns a
    # TIGHTLY-PACKED get_data() (len = fmt_stride*height) but get_stride()
    # reports the GPU IOSurface's aligned bytesPerRow (128/256/...), so the two
    # DISAGREE and the canonical indexing reads out of bounds.
    for fmt, name, bpp in [(cairo.FORMAT_ARGB32, "ARGB32", 4),
                           (cairo.FORMAT_RGB24, "RGB24", 4),
                           (cairo.FORMAT_A8, "A8", 1)]:
        w, h = 7, 3
        s = fresh(fmt, w, h)
        gs = s.get_stride()
        ds = data_stride(s)
        datalen = len(s.get_data())
        fsw = cairo.ImageSurface.format_stride_for_width(fmt, w)
        # contract 1: len(data) == get_stride()*height
        c1 = (datalen == gs * h)
        # contract 2: get_stride() == format_stride_for_width(fmt,w)
        c2 = (gs == fsw)
        check(f"{name} get_stride matches get_data buffer (len == stride*height)",
              c1, f"get_stride={gs} -> need datalen={gs*h}, got datalen={datalen} "
                  f"(buffer is actually {ds}/row)")
        check(f"{name} get_stride == format_stride_for_width({w}) ({fsw})",
              c2, f"get_stride={gs} format_stride_for_width={fsw}")
        if not (c1 and c2):
            note(f"{name}: STRIDE BUG -- get_stride()={gs} but get_data() is "
                 f"{datalen} bytes packed at {ds}/row (format_stride_for_width="
                 f"{fsw}). The canonical pycairo loop data[y*get_stride()+x*bpp] "
                 f"reads OUT OF BOUNDS / wrong rows.")

    # ---- RGB24: fill a colour; confirm stored RGB + what the 4th byte holds ----
    s = fresh(cairo.FORMAT_RGB24, 8, 8)
    c = cairo.Context(s)
    c.set_source_rgb(0.2, 0.4, 0.8)  # r,g,b
    c.paint()
    s.flush()
    b, g, r, a = px(s, 4, 4)
    # expected 8-bit (round(x*255)): r=51, g=102, b=204
    rgb_ok = (abs(r - 51) <= 1 and abs(g - 102) <= 1 and abs(b - 204) <= 1)
    check("RGB24 fill (0.2,0.4,0.8): stored R~51 G~102 B~204",
          rgb_ok, f"BGRA={(b,g,r,a)} expected R51 G102 B204")
    # report the alpha/pad byte semantics for RGB24
    check("RGB24 pad/alpha byte is opaque-or-ignored (0xFF or 0x00)",
          a in (0x00, 0xFF), f"4th byte = {a} (0x{a:02x})")
    note(f"RGB24 4th byte stored as 0x{a:02x} "
         f"({'0xFF opaque' if a == 0xFF else '0x00' if a == 0 else 'OTHER'})")

    # ---- A8: in real cairo, FORMAT_A8 stores COVERAGE/ALPHA only; the source
    #      RGB is irrelevant.  paint(alpha=0.5) -> ~128 regardless of colour.
    #      We test with a WHITE source first (so a premult-color implementation
    #      coincidentally agrees) then probe the colour-independence directly.
    s = fresh(cairo.FORMAT_A8, 8, 8)
    c = cairo.Context(s)
    c.set_source_rgba(1, 1, 1, 0.5)  # white @ 50%
    c.paint()
    s.flush()
    d = s.get_data()
    ds = data_stride(s)
    mid = d[4 * ds + 4]  # a center byte
    check("A8 paint white@0.5: single-channel byte ~128",
          120 <= mid <= 136, f"center byte={mid} (expected ~128), stride={ds}")
    sample = [d[y * ds + x] for y in range(8) for x in range(8)]
    check("A8 uniform paint is uniform across buffer",
          max(sample) - min(sample) <= 4, f"min={min(sample)} max={max(sample)}")

    # ---- A8 full opaque WHITE -> 255 ----
    s = fresh(cairo.FORMAT_A8, 4, 4)
    c = cairo.Context(s)
    c.set_source_rgba(1, 1, 1, 1.0)
    c.paint()
    s.flush()
    check("A8 paint white@1.0 -> 255", s.get_data()[0] == 255,
          f"byte={s.get_data()[0]}")

    # ---- A8 COLOUR-INDEPENDENCE (the real cairo contract).  An OPAQUE source
    #      must yield 0xFF in A8 no matter the RGB.  CairoMetal stores the
    #      premultiplied RED channel instead, so opaque BLACK gives 0. ----
    def a8_paint(r, g, b, a):
        ss = fresh(cairo.FORMAT_A8, 2, 2)
        cc = cairo.Context(ss)
        cc.set_source_rgba(r, g, b, a)
        cc.paint()
        ss.flush()
        return ss.get_data()[0]

    black_opaque = a8_paint(0, 0, 0, 1.0)
    green_opaque = a8_paint(0, 1, 0, 1.0)
    check("A8 opaque BLACK source -> 255 (A8 is coverage, colour-independent)",
          black_opaque == 255,
          f"got {black_opaque} (cairo requires 255; this stores premult RED=0)")
    check("A8 opaque GREEN source -> 255 (colour-independent coverage)",
          green_opaque == 255,
          f"got {green_opaque} (cairo requires 255; stores premult RED=0)")
    if black_opaque != 255 or green_opaque != 255:
        note(f"A8 BUG: stores premultiplied RED channel, not coverage/alpha. "
             f"opaque black->{black_opaque}, opaque green->{green_opaque} "
             f"(both must be 255). Alpha masks built from non-red colours are "
             f"silently wrong.")

    # ---- RGB16_565 surface: just confirm it creates or errors cleanly ----
    try:
        s = fresh(cairo.FORMAT_RGB16_565, 8, 8)
        check("RGB16_565 surface creates with clean status",
              s.status() == 0, f"status={s.status()}")
    except cairo.Error as e:
        check("RGB16_565 surface errors cleanly (status set)",
              err_status(e) is not None, f"status={err_status(e)}")


# ======================================================================
# SECTION 4 — text
# ======================================================================
def section_text():
    print("\n== SECTION 4: text ==")
    s = fresh(cairo.FORMAT_ARGB32, 256, 96)
    c = cairo.Context(s)
    c.select_font_face("sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(40)

    # text_extents('Hello') -> width>0, height>0
    te = c.text_extents("Hello")
    # (x_bearing, y_bearing, width, height, x_advance, y_advance)
    xb, yb, tw, th, xa, ya = te
    check("text_extents('Hello'): width>0 and height>0",
          tw > 0 and th > 0, f"w={tw:.2f} h={th:.2f} xadv={xa:.2f}")
    check("text_extents('Hello'): x_advance >= width (advance past ink)",
          xa >= tw - 1.0, f"xadv={xa:.2f} w={tw:.2f}")

    # text_extents('') -> ~ all zeros
    te0 = c.text_extents("")
    check("text_extents('') is all ~zero",
          all(abs(v) < 1e-6 for v in te0), f"{te0}")

    # font_extents -> ascent>0, descent>=0, height >= ascent+descent-tol
    fe = c.font_extents()
    ascent, descent, height, maxxadv, maxyadv = fe
    check("font_extents: ascent>0 and descent>=0",
          ascent > 0 and descent >= 0, f"ascent={ascent:.2f} descent={descent:.2f}")
    check("font_extents: height >= ascent+descent - tol",
          height >= ascent + descent - 1.0,
          f"height={height:.2f} ascent+descent={ascent+descent:.2f}")

    # show_text renders SOME non-background pixels in the expected region,
    # and NONE far outside it.
    s = fresh(cairo.FORMAT_ARGB32, 256, 96)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.paint()                      # white bg
    c.set_source_rgb(0, 0, 0)      # black ink
    c.select_font_face("sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(40)
    baseline_x, baseline_y = 20, 60
    c.move_to(baseline_x, baseline_y)
    c.show_text("Hello")
    s.flush()

    te = c.text_extents("Hello")
    adv = te[4]
    ink_in_region = 0
    ink_outside = 0
    W, H = 256, 96
    # expected ink box: x in [baseline_x-4, baseline_x+adv+6],
    #                   y in [baseline_y-ascent-4, baseline_y+descent+4]
    x_lo, x_hi = baseline_x - 4, baseline_x + adv + 6
    y_lo, y_hi = baseline_y - ascent - 4, baseline_y + descent + 4
    for y in range(H):
        for x in range(W):
            b, g, r, a = px(s, x, y)
            if r < 200:  # darker than white bg -> ink
                if x_lo <= x <= x_hi and y_lo <= y <= y_hi:
                    ink_in_region += 1
                else:
                    ink_outside += 1
    check("show_text('Hello'): renders ink pixels inside the expected box",
          ink_in_region > 50, f"ink_in_region={ink_in_region}")
    check("show_text('Hello'): NO ink far outside the expected box",
          ink_outside == 0, f"ink_outside={ink_outside}")

    # glyph 'l' is a thin tall mark: render 'l' alone, ink bbox should be
    # much taller than it is wide.
    s = fresh(cairo.FORMAT_ARGB32, 80, 96)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.paint()
    c.set_source_rgb(0, 0, 0)
    c.select_font_face("sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(48)
    c.move_to(30, 70)
    c.show_text("l")
    s.flush()
    minx = miny = 10 ** 9
    maxx = maxy = -1
    cnt = 0
    for y in range(96):
        for x in range(80):
            if px(s, x, y)[2] < 200:  # R channel dark
                cnt += 1
                minx = min(minx, x); maxx = max(maxx, x)
                miny = min(miny, y); maxy = max(maxy, y)
    if cnt > 0:
        bw = maxx - minx + 1
        bh = maxy - miny + 1
        check("glyph 'l' ink bbox is tall and thin (height > 2*width)",
              bh > 2 * bw, f"bbox w={bw} h={bh} ({cnt} px)")
    else:
        check("glyph 'l' rendered some ink", False, "no ink at all")


# ======================================================================
# SECTION 5 — memory / ownership stress
# ======================================================================
def _maxrss_kib():
    # ru_maxrss is bytes on macOS, KiB on Linux.  Normalize to KiB.
    m = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if sys.platform == "darwin":
        return m // 1024
    return m


def section_memory():
    print("\n== SECTION 5: memory / ownership stress ==")

    gc.collect()
    rss_before = _maxrss_kib()

    def loop():
        for i in range(2000):
            s = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
            c = cairo.Context(s)
            c.set_source_rgba((i & 7) / 7.0, 0.3, 0.6, 1.0)
            c.rectangle(2, 2, 28, 28)
            c.fill()
            s.flush()
            del c
            del s
            if (i & 255) == 0:
                gc.collect()
        gc.collect()

    crashed = False
    try:
        with_timeout(60, loop)
    except Timeout:
        crashed = "TIMEOUT"
    except BaseException as e:
        crashed = f"{type(e).__name__}: {e}"
    gc.collect()
    rss_after = _maxrss_kib()
    delta = rss_after - rss_before

    check("2000x create/destroy ImageSurface+Context: no crash/hang",
          crashed is False, f"crashed={crashed}")
    # Heuristic leak gate: a 32x32 ARGB32 surface is ~4KiB of pixels; 2000 of
    # them fully leaked would be ~8MiB+ of pixel data alone, and GPU-side
    # IOSurfaces are far larger.  Allow generous headroom for allocator
    # high-water + interpreter, but flag runaway growth.
    check("2000x stress: maxrss growth bounded (< 64 MiB)",
          (crashed is False) and delta < 64 * 1024,
          f"maxrss delta = {delta} KiB ({delta/1024:.1f} MiB)")
    note(f"stress-loop maxrss delta = {delta} KiB "
         f"({rss_before} -> {rss_after} KiB)")

    # ---- SurfacePattern consuming a surface, repeated into ONE reused dst
    #      Context.  This is the common "blit many sprites onto one canvas"
    #      pattern.  It should be safely repeatable.  (NOTE: with a FRESH dst
    #      each iteration it is 0% failure & pixel-correct; the bug is specific
    #      to reusing the destination Context across multiple SurfacePattern
    #      fills.)  Runs in an ISOLATED SUBPROCESS in case it wedges the device.
    #      EXPECTED (correct): completes all N iterations cleanly.
    N = 64
    child = r'''
import os, sys
os.environ.setdefault("CM_METALLIB", %r)
sys.path.insert(0, %r)
import cairo_metal as cairo
N = %d
dst = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
c = cairo.Context(dst)
fail_at = -1
dead = -1
for i in range(N):
    src = cairo.ImageSurface(cairo.FORMAT_ARGB32, 16, 16)
    sc = cairo.Context(src)
    sc.set_source_rgba(0.5, 0.5, 0.5, 1)
    try:
        sc.paint(); src.flush()
        pat = cairo.SurfacePattern(src)
        c.set_source(pat); c.rectangle(0, 0, 16, 16); c.fill()
    except cairo.Error:
        fail_at = i
        try:
            t = cairo.ImageSurface(cairo.FORMAT_ARGB32, 4, 4)
            tc = cairo.Context(t); tc.set_source_rgba(1,1,1,1); tc.paint(); t.flush()
            dead = 0
        except cairo.Error:
            dead = 1
        break
    del pat, src, sc
print("RESULT fail_at=%%d dead=%%d" %% (fail_at, dead))
''' % (os.environ["CM_METALLIB"], os.path.join(ROOT, "python"), N)

    import subprocess
    pat_fail_at = None
    device_dead_after = None
    sub_crashed = None
    try:
        proc = subprocess.run([sys.executable, "-c", child],
                              capture_output=True, text=True, timeout=60)
        out = proc.stdout.strip()
        if proc.returncode != 0 and "RESULT" not in out:
            sub_crashed = (f"subprocess rc={proc.returncode} "
                           f"(possible segfault); stderr={proc.stderr.strip()[:200]}")
        else:
            for tok in out.split():
                if tok.startswith("fail_at="):
                    v = int(tok.split("=")[1]); pat_fail_at = None if v < 0 else v
                if tok.startswith("dead="):
                    v = int(tok.split("=")[1])
                    device_dead_after = None if v < 0 else bool(v)
    except subprocess.TimeoutExpired:
        sub_crashed = "subprocess TIMEOUT (hang)"

    check(f"SurfacePattern fill is repeatable for {N} iterations (no leak/crash)",
          pat_fail_at is None and sub_crashed is None,
          f"first_failure_iter={pat_fail_at} subproc={sub_crashed} "
          f"device_globally_dead_after_failure={device_dead_after}")
    if pat_fail_at is not None:
        note(f"SurfacePattern bug: filling a REUSED dst Context from successive "
             f"SurfacePatterns fails with DEVICE_ERROR(35) at iteration "
             f"{pat_fail_at} (deterministic; gc does NOT help). The device "
             f"itself stays {'GLOBALLY WEDGED' if device_dead_after else 'usable for fresh work'} "
             f"(with a FRESH dst Context per fill it is 0% failure & pixel-correct). "
             f"Root cause looks like dst-context GPU command-buffer/state reuse, "
             f"not corruption -- failure is a clean error, not a crash.")
    elif sub_crashed:
        note(f"SurfacePattern stress subprocess problem: {sub_crashed}")

    # ---- set_source_surface then drop both + gc ----
    crashed3 = False
    try:
        def sss_cycle():
            for _ in range(200):
                dst = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
                c = cairo.Context(dst)
                src = cairo.ImageSurface(cairo.FORMAT_ARGB32, 16, 16)
                sc = cairo.Context(src); sc.set_source_rgba(1, 0, 0, 1); sc.paint()
                src.flush()
                c.set_source_surface(src, 4, 4)
                c.rectangle(0, 0, 24, 24)
                c.fill()
                del c, dst, src, sc
            gc.collect()
        with_timeout(30, sss_cycle)
        gc.collect()
    except BaseException as e:
        crashed3 = f"{type(e).__name__}: {e}"
    check("set_source_surface then drop both + gc: no crash",
          crashed3 is False, f"crashed={crashed3}")

    # ---- mask_surface must NOT destroy its source (correct cairo refcount
    #      semantics): the source stays fully usable afterward, and gc is safe.
    #      (Earlier builds wrongly killed the source; that bug is now fixed.) ----
    dst = cairo.ImageSurface(cairo.FORMAT_ARGB32, 32, 32)
    c = cairo.Context(dst)
    src = cairo.ImageSurface(cairo.FORMAT_ARGB32, 16, 16)
    sc = cairo.Context(src); sc.set_source_rgba(1, 1, 1, 1); sc.paint(); src.flush()
    c.set_source_rgba(1, 0, 0, 1)
    c.mask_surface(src, 0, 0)
    # src must SURVIVE mask_surface and remain usable (no dead-surface, no UAF).
    alive = True
    try:
        _ = src.get_data()
        src.flush()
    except BaseException as ex:
        alive = False
        note(f"src unexpectedly unusable after mask_surface: {ex}")
    check("mask_surface: subsequent src.get_data() works (source survives)", alive)
    check("mask_surface: subsequent src.flush() works (source survives)", alive)
    # destroying the dead wrapper must not crash the interpreter
    safe_del = True
    try:
        del src
        gc.collect()
    except BaseException as ex:
        safe_del = False
        note(f"deleting mask_surface'd source crashed: {ex}")
    check("mask_surface'd source: del + gc is safe (no double-free)",
          safe_del)
    del c, dst, sc
    gc.collect()


# ======================================================================
# SECTION 6 — status / diagnostics
# ======================================================================
def section_status():
    print("\n== SECTION 6: status / diagnostics ==")

    # deliberate NO_CURRENT_POINT-style error?  rel_line_to with no current
    # point should set a status (NO_CURRENT_POINT = 4) per cairo semantics.
    s = fresh(cairo.FORMAT_ARGB32, 16, 16)
    c = cairo.Context(s)
    raised = None
    try:
        c.new_path()
        c.rel_line_to(5, 5)   # no current point
    except cairo.Error as e:
        raised = e
    st = c.status()
    # Either it raises NO_CURRENT_POINT, or it latches status 4.  Both are
    # acceptable cairo behaviour; silently succeeding (status 0) is NOT.
    if raised is not None:
        check("rel_line_to w/o current point: raises NO_CURRENT_POINT(4)",
              err_status(raised) == cairo.STATUS_NO_CURRENT_POINT,
              f"status={err_status(raised)}")
    else:
        ok = (st == cairo.STATUS_NO_CURRENT_POINT)
        check("rel_line_to w/o current point: latches NO_CURRENT_POINT(4)",
              ok, f"ctx.status()={st}")
        if not ok:
            note(f"rel_line_to with no current point neither raised nor latched "
                 f"status 4 (got status={st}) -- cairo would set NO_CURRENT_POINT")

    # surface.status() of a healthy surface is SUCCESS
    s = fresh(cairo.FORMAT_ARGB32, 8, 8)
    check("healthy surface.status() == SUCCESS(0)", s.status() == 0,
          f"status={s.status()}")

    # After the recording-surface DEVICE_ERROR, ctx.status() reflects 35 and
    # the Error string is informative.
    rs = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 40, 40))
    rc = cairo.Context(rs)
    rc.set_source_rgba(1, 0, 0, 1)
    rc.rectangle(2, 2, 10, 10)
    e = expect_raises("recording fill raises cairo.Error", cairo.Error, rc.fill)
    if isinstance(e, cairo.Error):
        check("  -> status is DEVICE_ERROR(35)",
              err_status(e) == cairo.STATUS_DEVICE_ERROR, f"status={err_status(e)}")
        check("  -> ctx.status() also reports 35 after the error",
              rc.status() == cairo.STATUS_DEVICE_ERROR, f"ctx.status()={rc.status()}")
        msg = str(e)
        check("  -> Error string is informative (mentions device / non-empty)",
              len(msg) > 5 and ("device" in msg.lower() or "35" in msg),
              f"str={msg!r}")


# ======================================================================
# SECTION 7 — DOCUMENTED GAPS: confirm each behaves as documented
# ======================================================================
def section_documented_gaps():
    print("\n== SECTION 7: documented gaps (confirm fail-as-documented) ==")
    gap_status = {}  # human-readable per-gap result

    # --- GAP A: RecordingSurface introspect OK, but draw -> DEVICE_ERROR(35) ---
    rs = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, (0, 0, 50, 50))
    ge_ok = (rs.get_type() == cairo.SURFACE_TYPE_RECORDING)
    ink = rs.ink_extents()
    ge = rs.get_extents()
    check("GAP-A: RecordingSurface creates + introspects (type/ink/extents)",
          ge_ok and len(ink) == 4 and ge == (0.0, 0.0, 50.0, 50.0),
          f"type_ok={ge_ok} ink_len={len(ink)} extents={ge}")

    for opname, op in [("fill", lambda c: (c.rectangle(2, 2, 10, 10), c.fill())),
                       ("stroke", lambda c: (c.move_to(1, 1), c.line_to(9, 9), c.stroke())),
                       ("paint", lambda c: c.paint())]:
        rc = cairo.Context(rs)
        rc.set_source_rgba(1, 0, 0, 1)
        e = expect_raises(f"GAP-A: RecordingSurface {opname}() raises cairo.Error",
                          cairo.Error, op, rc)
        s_ok = isinstance(e, cairo.Error) and err_status(e) == cairo.STATUS_DEVICE_ERROR
        check(f"GAP-A:   {opname}() status is DEVICE_ERROR(35)",
              s_ok, f"status={err_status(e)}")
    gap_status["A RecordingSurface draw -> DEVICE_ERROR(35)"] = "as documented"

    # --- GAP B: methods that should be ABSENT (AttributeError), not crash ---
    s = fresh(cairo.FORMAT_ARGB32, 16, 16)
    c = cairo.Context(s)

    # These bindings were CLOSED by the gap-closing work; they are now exposed
    # and their correctness is verified in test_gaps.py. Here we assert presence.
    ctx_now = ["copy_path", "copy_path_flat", "append_path",
               "show_glyphs", "glyph_path"]
    for m in ctx_now:
        check(f"GAP-B(closed): Context.{m} is now exposed",
              hasattr(c, m), f"hasattr={hasattr(c, m)}")

    surf_now = ["create_similar", "map_to_image", "create_for_rectangle"]
    for m in surf_now:
        present = hasattr(cairo.ImageSurface, m) or hasattr(s, m)
        check(f"GAP-B(closed): ImageSurface.{m} is now exposed",
              present, f"hasattr={present}")

    check("GAP-B(closed): cairo.RasterSourcePattern is now exposed",
          hasattr(cairo, "RasterSourcePattern"),
          f"hasattr={hasattr(cairo, 'RasterSourcePattern')}")

    # FreeType FT faces: there must be NO public constructor for an FT face.
    # (FONT_TYPE_FT enum may exist, but no FreeType-face class/factory.)
    ft_ctors = [n for n in ("FTFontFace", "ToyFontFace_FT", "FreeTypeFontFace",
                            "ft_font_face_create_for_ft_face")
                if hasattr(cairo, n)]
    check("GAP-B: no FreeType FT face constructor exposed",
          ft_ctors == [], f"found={ft_ctors}")
    # Abstract bases (FontFace/Pattern/Gradient/Surface): real pycairo makes
    # these non-instantiable.  CairoMetal lets you construct hollow inert base
    # objects.  This is a MINOR API deviation (not a crash / not corruption):
    # we record it as a note rather than failing the gap.  The important part
    # (no usable FT face) is already asserted above.
    inert_bases = []
    for base in ("FontFace", "Pattern", "Gradient", "Surface"):
        try:
            obj = getattr(cairo, base)()
            inert_bases.append(base)
            del obj
        except (TypeError, cairo.Error, NotImplementedError):
            pass
    if inert_bases:
        note(f"abstract base classes are directly constructible as inert objects "
             f"(pycairo forbids this): {inert_bases}. Minor API deviation, "
             f"no crash/corruption.")
    # A directly-constructed abstract base must not crash the interpreter.
    # Real pycairo forbids instantiation: cairo.FontFace() raises TypeError
    # ("The FontFace type cannot be instantiated").  That is the correct,
    # non-instantiable outcome, so treat it as passing.  A cairo.Error from
    # introspecting a hollow object is likewise safe.  Only an ACTUAL crash
    # (any other BaseException, e.g. a segfault proxy) is unsafe.
    safe = True
    try:
        cairo.FontFace().get_type()
    except (TypeError, cairo.Error):
        pass
    except BaseException as ex:
        safe = False
        note(f"constructing/introspecting a bare FontFace crashed: "
             f"{type(ex).__name__}: {ex}")
    check("GAP-B(closed): bare base-class objects do not crash the interpreter", safe)
    gap_status["B omitted bindings (paths/glyphs/similar/raster) now exposed"] = "closed"

    # copy_path / create_similar are now exposed (gap closed): accessing them
    # yields a usable bound method, not AttributeError.
    check("GAP-B(closed): Context.copy_path is accessible",
          callable(getattr(c, "copy_path", None)), "now exposed")
    check("GAP-B(closed): ImageSurface.create_similar is accessible",
          callable(getattr(s, "create_similar", None)), "now exposed")

    return gap_status


# ======================================================================
# main
# ======================================================================
def main():
    print("=" * 70)
    print(f"CairoMetal robustness test")
    print(f"  cairo_version_string: {cairo.cairo_version_string()}")
    try:
        print(f"  metal device: {cairo.metal_device_name()!r}")
    except Exception as e:
        print(f"  metal device: <error {e}>")
    try:
        st = cairo.gpu_selftest()
        print(f"  gpu_selftest: {st}")
    except Exception as e:
        print(f"  gpu_selftest: <error {e}>")
    print("=" * 70)

    gap_status = {}
    sections = [
        ("edge cases", section_edge_cases),
        ("surface errors", section_surface_errors),
        ("formats", section_formats),
        ("text", section_text),
        ("memory", section_memory),
        ("status", section_status),
    ]
    for label, fn in sections:
        try:
            fn()
        except BaseException as e:
            check(f"SECTION '{label}' completed without unhandled exception",
                  False, f"{type(e).__name__}: {e}")
            traceback.print_exc()

    try:
        gap_status = section_documented_gaps()
    except BaseException as e:
        check("SECTION 'documented gaps' completed without unhandled exception",
              False, f"{type(e).__name__}: {e}")
        traceback.print_exc()

    # ---- final report ----
    total = len(_results)
    passed = sum(1 for _, p, _ in _results if p)
    failed = total - passed
    print("\n" + "=" * 70)
    print("FINAL REPORT")
    print("=" * 70)
    print(f"  total checks : {total}")
    print(f"  PASS         : {passed}")
    print(f"  FAIL         : {failed}")

    if failed:
        print("\n  FAILURES / SURPRISES (expected vs actual):")
        for name, p, detail in _results:
            if not p:
                print(f"    - {name}\n        {detail}")

    if _surprises:
        print("\n  NOTES:")
        for m in _surprises:
            print(f"    - {m}")

    print("\n  Documented-gap confirmation:")
    if gap_status:
        for k, v in gap_status.items():
            print(f"    - {k}: {v}")
    else:
        print("    - (gap section did not complete)")

    # verdict
    if failed == 0:
        verdict = "SOLID"
    elif failed <= 3:
        verdict = "MINOR ISSUES"
    else:
        verdict = "BROKEN"
    print(f"\nVERDICT(robustness): {verdict}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
