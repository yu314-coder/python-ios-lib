#!/usr/bin/env python3
"""
Rigorous rasterization & compositing pixel-math test for CairoMetal.

Run:
  CM_METALLIB=".../build/default.metallib" \
  PYTHONPATH=".../python" \
  python3 '.../tests/test_raster.py'

Every check compares a SPECIFIC pixel against a COMPUTED expected value.
ARGB32 pixel memory order is B,G,R,A premultiplied:
  o = y*data_stride + x*4 ; data[o]=B, data[o+1]=G, data[o+2]=R, data[o+3]=A

IMPORTANT (discovered): get_stride() reports the GPU-aligned texture stride,
which does NOT match the actual get_data() buffer (which is tightly packed at
width*4). We therefore derive the *true* data stride from the buffer itself
(len(data)//height) for all pixel reads, and flag the get_stride() mismatch as
its own explicit check.
"""

import sys
import math

import cairo_metal as cairo

# ----------------------------------------------------------------------------
# harness
# ----------------------------------------------------------------------------
PASS = 0
FAIL = 0
FAILURES = []   # (feature, expected, actual, assessment)
CHECKS = 0


def record(ok, feature, expected, actual, assessment=""):
    global PASS, FAIL, CHECKS
    CHECKS += 1
    if ok:
        PASS += 1
        # keep output readable but confirm each pass
        print(f"  PASS  {feature}")
    else:
        FAIL += 1
        FAILURES.append((feature, expected, actual, assessment))
        print(f"  FAIL  {feature}\n        expected={expected}\n        actual  ={actual}\n        note    ={assessment}")


def approx(a, b, tol):
    return abs(int(a) - int(b)) <= tol


def px_bgra(surface, x, y):
    """Return (B,G,R,A) at (x,y) using the TRUE data stride (len/height)."""
    data = bytes(surface.get_data())
    h = surface.get_height()
    true_stride = len(data) // h
    o = y * true_stride + x * 4
    return (data[o], data[o + 1], data[o + 2], data[o + 3])


def a8_val(surface, x, y):
    data = bytes(surface.get_data())
    h = surface.get_height()
    true_stride = len(data) // h
    return data[y * true_stride + x]


def new_surface(w, h):
    return cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)


def check_bgra(feature, surface, x, y, exp_bgra, tol=2, assessment=""):
    got = px_bgra(surface, x, y)
    ok = all(approx(got[i], exp_bgra[i], tol) for i in range(4))
    if not assessment and not ok:
        assessment = "real bug (pixel math off)"
    record(ok, f"{feature} @({x},{y})", f"BGRA{tuple(exp_bgra)} tol+-{tol}", f"BGRA{got}", assessment)
    return got


# Premultiplied compositing helpers (all channels 0..255 int-ish, premultiplied)
def over(src, dst):
    """Porter-Duff OVER on premultiplied tuples (B,G,R,A) floats 0..255."""
    sa = src[3] / 255.0
    return tuple(src[i] + dst[i] * (1.0 - sa) for i in range(4))


def premult(r, g, b, a):
    """From straight rgba (0..1) -> premultiplied BGRA bytes (float)."""
    return (b * a * 255.0, g * a * 255.0, r * a * 255.0, a * 255.0)


# ============================================================================
print("=" * 70)
print("CairoMetal rasterization correctness suite")
print("device:", cairo.metal_device_name())
print("=" * 70)

# ----------------------------------------------------------------------------
# 0. STRIDE / DATA-BUFFER CONSISTENCY  (pycairo contract)
# ----------------------------------------------------------------------------
print("\n[0] Stride / data-buffer consistency")
for w in (16, 17, 100, 200):
    s = new_surface(w, 4)
    data = bytes(s.get_data())
    true_stride = len(data) // 4
    reported = s.get_stride()
    fsfw = cairo.ImageSurface.format_stride_for_width(cairo.FORMAT_ARGB32, w)
    # In pycairo: get_stride() == format_stride_for_width() == the data row size.
    record(
        reported == true_stride,
        f"get_stride matches data buffer row (w={w})",
        f"get_stride == len(data)//h == {true_stride}",
        f"get_stride={reported}, actual data row={true_stride}, format_stride_for_width={fsfw}",
        "REAL BUG: get_stride() returns GPU-aligned stride, not the get_data() row "
        "size; standard `y*get_stride()+x*4` indexing into get_data() is corrupt for "
        "widths not multiple of 32.",
    )

# ----------------------------------------------------------------------------
# 1. SOLID FILLS -> exact premultiplied BGRA
# ----------------------------------------------------------------------------
print("\n[1] Solid fills (exact premultiplied BGRA)")
W = H = 64  # multiple of 32 so get_stride() coincidentally == w*4; pixel math clean
solids = [
    ("red    a=1.0", (1, 0, 0, 1.0), (0, 0, 255, 255)),
    ("green  a=1.0", (0, 1, 0, 1.0), (0, 255, 0, 255)),
    ("blue   a=1.0", (0, 0, 1, 1.0), (255, 0, 0, 255)),
    ("white  a=1.0", (1, 1, 1, 1.0), (255, 255, 255, 255)),
    ("black  a=1.0", (0, 0, 0, 1.0), (0, 0, 0, 255)),
    ("gray.5 a=1.0", (0.5, 0.5, 0.5, 1.0), (128, 128, 128, 255)),
    ("red    a=0.5", (1, 0, 0, 0.5), (0, 0, 128, 128)),       # premult
    ("white  a=0.25", (1, 1, 1, 0.25), (64, 64, 64, 64)),     # premult
    ("green  a=0.0", (0, 1, 0, 0.0), (0, 0, 0, 0)),           # fully transparent
]
for name, (r, g, b, a), exp in solids:
    s = new_surface(W, H)
    ctx = cairo.Context(s)
    ctx.set_source_rgba(r, g, b, a)
    ctx.paint()
    s.flush()
    check_bgra(f"solid {name}", s, 32, 32, exp, tol=2)

# fill of a sub-rectangle: inside filled, outside untouched(0)
print("\n[1b] rectangle fill localization")
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_source_rgba(0, 0, 1, 1)
ctx.rectangle(16, 16, 32, 32)   # x,y,w,h -> covers [16,48)
ctx.fill()
s.flush()
check_bgra("rect interior blue", s, 32, 32, (255, 0, 0, 255), tol=2)
check_bgra("rect exterior transparent", s, 4, 4, (0, 0, 0, 0), tol=0,
           assessment="background outside fill must stay cleared")
check_bgra("rect exterior transparent2", s, 60, 60, (0, 0, 0, 0), tol=0)

# ----------------------------------------------------------------------------
# 2. FILL RULES
# ----------------------------------------------------------------------------
print("\n[2] Fill rules (WINDING vs EVEN_ODD)")

def two_same_winding_rects(fill_rule):
    """Two overlapping rectangles, SAME orientation (both CW).
    Overlap winding number = 2. WINDING: filled (nz). EVEN_ODD: 2 is even -> hole."""
    s = new_surface(W, H)
    ctx = cairo.Context(s)
    ctx.set_fill_rule(fill_rule)
    ctx.set_source_rgba(1, 0, 0, 1)
    # rect A [10,40)x[10,40)  CW
    ctx.move_to(10, 10); ctx.line_to(40, 10); ctx.line_to(40, 40); ctx.line_to(10, 40); ctx.close_path()
    # rect B [25,55)x[25,55)  CW (same direction)
    ctx.move_to(25, 25); ctx.line_to(55, 25); ctx.line_to(55, 55); ctx.line_to(25, 55); ctx.close_path()
    ctx.fill()
    s.flush()
    return s

# Overlap region is [25,40)x[25,40); pick (32,32). Non-overlap part e.g. (15,15).
s_w = two_same_winding_rects(cairo.FILL_RULE_WINDING)
check_bgra("WINDING overlap filled", s_w, 32, 32, (0, 0, 255, 255), tol=2,
           assessment="winding# 2 != 0 -> filled")
check_bgra("WINDING single-cover filled", s_w, 15, 15, (0, 0, 255, 255), tol=2)

s_eo = two_same_winding_rects(cairo.FILL_RULE_EVEN_ODD)
check_bgra("EVEN_ODD overlap is HOLE", s_eo, 32, 32, (0, 0, 0, 0), tol=2,
           assessment="even-odd: crossing count 2 (even) -> background")
check_bgra("EVEN_ODD single-cover filled", s_eo, 15, 15, (0, 0, 255, 255), tol=2,
           assessment="single coverage (odd) -> filled")

# Donut: outer rect CW + inner rect CCW (reversed) -> hole in center under WINDING
print("\n[2b] Donut (reversed inner sub-path) -> center hole")
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
ctx.set_source_rgba(0, 1, 0, 1)
# outer [8,56) CW
ctx.move_to(8, 8); ctx.line_to(56, 8); ctx.line_to(56, 56); ctx.line_to(8, 56); ctx.close_path()
# inner [24,40) CCW (reversed winding)
ctx.move_to(24, 24); ctx.line_to(24, 40); ctx.line_to(40, 40); ctx.line_to(40, 24); ctx.close_path()
ctx.fill()
s.flush()
check_bgra("donut center HOLE", s, 32, 32, (0, 0, 0, 0), tol=2,
           assessment="outer(+1)+inner(-1)=0 -> hole")
check_bgra("donut ring filled", s, 12, 32, (0, 255, 0, 255), tol=2,
           assessment="ring between outer and inner -> filled")

# Same donut under EVEN_ODD: center is also a hole (2 crossings even); ring odd -> filled
s2 = new_surface(W, H)
ctx = cairo.Context(s2)
ctx.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
ctx.set_source_rgba(0, 1, 0, 1)
ctx.move_to(8, 8); ctx.line_to(56, 8); ctx.line_to(56, 56); ctx.line_to(8, 56); ctx.close_path()
ctx.move_to(24, 24); ctx.line_to(24, 40); ctx.line_to(40, 40); ctx.line_to(40, 24); ctx.close_path()
ctx.fill()
s2.flush()
check_bgra("donut EO center hole", s2, 32, 32, (0, 0, 0, 0), tol=2)
check_bgra("donut EO ring filled", s2, 12, 32, (0, 255, 0, 255), tol=2)

# ----------------------------------------------------------------------------
# 3. OPERATORS (Porter-Duff / blend), premultiplied math
# ----------------------------------------------------------------------------
print("\n[3] Operators (set_operator) - premultiplied Porter-Duff")

def op_result(op, dst_rgba, src_rgba, x=32, y=32):
    """Paint dst (whole), then src (whole) with operator op. Return BGRA at (x,y)."""
    s = new_surface(W, H)
    ctx = cairo.Context(s)
    ctx.set_operator(cairo.OPERATOR_SOURCE)            # lay down dst cleanly
    ctx.set_source_rgba(*dst_rgba); ctx.paint()
    ctx.set_operator(op)
    ctx.set_source_rgba(*src_rgba); ctx.paint()
    s.flush()
    return px_bgra(s, x, y)

# dst and src as premultiplied BGRA floats for hand math
def P(rgba):
    return premult(*rgba)

# We use: dst = blue @1.0, src = red @0.5  (classic), plus extra cases.
dst_blue = (0, 0, 1, 1.0)      # premult BGRA (255,0,0,255)
src_red5 = (1, 0, 0, 0.5)      # premult BGRA (0,0,128,128)
Db = P(dst_blue)               # (255,0,0,255)
Sr = P(src_red5)               # (0,0,128,128)
sa = Sr[3] / 255.0             # 0.5
da = Db[3] / 255.0             # 1.0

# Compute each operator's premultiplied result. Formulas (premultiplied):
#  CLEAR:    0
#  SOURCE:   src
#  OVER:     src + dst*(1-sa)
#  DEST_OVER:dst + src*(1-da)
#  IN:       src*da
#  OUT:      src*(1-da)
#  DEST_IN:  dst*sa
#  DEST_OUT: dst*(1-sa)
#  ATOP:     src*da + dst*(1-sa)
#  DEST_ATOP:dst*sa + src*(1-da)
#  XOR:      src*(1-da) + dst*(1-sa)
#  ADD:      min(src+dst, 1) per channel (premult, clamp at alpha-aware 255)
def clear_(): return (0, 0, 0, 0)
def source_(): return Sr
def over_(): return tuple(Sr[i] + Db[i] * (1 - sa) for i in range(4))
def destover_(): return tuple(Db[i] + Sr[i] * (1 - da) for i in range(4))
def in_(): return tuple(Sr[i] * da for i in range(4))
def out_(): return tuple(Sr[i] * (1 - da) for i in range(4))
def atop_(): return tuple(Sr[i] * da + Db[i] * (1 - sa) for i in range(4))
def xor_(): return tuple(Sr[i] * (1 - da) + Db[i] * (1 - sa) for i in range(4))
def add_(): return tuple(min(255.0, Sr[i] + Db[i]) for i in range(4))

op_cases = [
    ("CLEAR", cairo.OPERATOR_CLEAR, clear_()),
    ("SOURCE", cairo.OPERATOR_SOURCE, source_()),
    ("OVER", cairo.OPERATOR_OVER, over_()),
    ("DEST_OVER", cairo.OPERATOR_DEST_OVER, destover_()),
    ("IN", cairo.OPERATOR_IN, in_()),
    ("OUT", cairo.OPERATOR_OUT, out_()),
    ("ATOP", cairo.OPERATOR_ATOP, atop_()),
    ("XOR", cairo.OPERATOR_XOR, xor_()),
    ("ADD", cairo.OPERATOR_ADD, add_()),
]
for name, op, exp in op_cases:
    got = op_result(op, dst_blue, src_red5)
    exp_r = tuple(round(v) for v in exp)
    ok = all(approx(got[i], exp_r[i], 2) for i in range(4))
    record(ok, f"OP {name} (blue<-red@.5)",
           f"BGRA{exp_r}", f"BGRA{got}",
           "" if ok else "REAL BUG: operator deviates from premultiplied Porter-Duff")

# ---- Separable blend modes (MULTIPLY/SCREEN/DARKEN/LIGHTEN/DIFFERENCE/EXCLUSION).
# Tested with OPAQUE src & dst (alpha=1) so the result is purely the blend B(cs,cb)
# per straight channel, alpha=1. dst=blue(0,0,1), src=red(1,0,0).
print("\n[3b] Separable blend modes (opaque red over blue)")

def comp_opaque(op):
    s = new_surface(W, H)
    ctx = cairo.Context(s)
    ctx.set_operator(cairo.OPERATOR_SOURCE); ctx.set_source_rgba(0, 0, 1, 1); ctx.paint()
    ctx.set_operator(op); ctx.set_source_rgba(1, 0, 0, 1); ctx.paint()
    s.flush()
    return px_bgra(s, 32, 32)

# straight channels: src=(R,G,B)=(1,0,0), dst=(0,0,1)
def blend_expected(fn):
    r = fn(1.0, 0.0); g = fn(0.0, 0.0); b = fn(0.0, 1.0)
    return (round(b * 255), round(g * 255), round(r * 255), 255)

blend_cases = [
    ("MULTIPLY",   cairo.OPERATOR_MULTIPLY,   lambda cs, cb: cs * cb),
    ("SCREEN",     cairo.OPERATOR_SCREEN,     lambda cs, cb: cs + cb - cs * cb),
    ("DARKEN",     cairo.OPERATOR_DARKEN,     lambda cs, cb: min(cs, cb)),
    ("LIGHTEN",    cairo.OPERATOR_LIGHTEN,    lambda cs, cb: max(cs, cb)),
    ("DIFFERENCE", cairo.OPERATOR_DIFFERENCE, lambda cs, cb: abs(cs - cb)),
    ("EXCLUSION",  cairo.OPERATOR_EXCLUSION,  lambda cs, cb: cs + cb - 2 * cs * cb),
]
over_ref = comp_opaque(cairo.OPERATOR_OVER)   # (0,0,255,255) pure red
for name, op, fn in blend_cases:
    got = comp_opaque(op)
    exp = blend_expected(fn)
    ok = all(approx(got[i], exp[i], 2) for i in range(4))
    if not ok:
        if got == over_ref:
            assess = ("REAL BUG: blend mode NOT implemented - output identical to OVER "
                      "(plain source-over fallback)")
        else:
            assess = "REAL BUG: blend formula deviates"
    else:
        assess = ""
    record(ok, f"OP {name} (blue<-red opaque)", f"BGRA{exp}", f"BGRA{got}", assess)

# ----------------------------------------------------------------------------
# 4. paint_with_alpha & mask
# ----------------------------------------------------------------------------
print("\n[4] paint_with_alpha & mask")
# paint blue opaque, then paint red opaque with paint_with_alpha(0.5) -> OVER
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_source_rgba(0, 0, 1, 1); ctx.paint()
ctx.set_source_rgba(1, 0, 0, 1); ctx.paint_with_alpha(0.5)
s.flush()
# src effective = red premult by 0.5 = (0,0,128,128) OVER blue(255,0,0,255)
exp = tuple(round(v) for v in over((0, 0, 128, 128), (255, 0, 0, 255)))
check_bgra("paint_with_alpha 0.5 red over blue", s, 32, 32, exp, tol=2)

# paint_with_alpha onto transparent: red @ pwa 0.3 -> premult (0,0,0.3*255, 0.3*255)
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_source_rgba(1, 0, 0, 1); ctx.paint_with_alpha(0.3)
s.flush()
exp = (0, 0, round(0.3 * 255), round(0.3 * 255))
check_bgra("paint_with_alpha 0.3 on clear", s, 32, 32, exp, tol=2)

# --- A8 alpha-write semantics. In real cairo, an A8 surface stores ONLY coverage
# alpha; the RGB of the source is irrelevant. So set_source_rgba(*,*,*,0.5)+paint
# must yield value 128 regardless of color. We test BOTH black@.5 and white@.5.
print("\n[4b] A8 alpha-write semantics")
def make_a8(r, g, b, a):
    m = cairo.ImageSurface(cairo.FORMAT_A8, W, H)
    mc = cairo.Context(m)
    mc.set_source_rgba(r, g, b, a)
    mc.paint()
    m.flush()
    return m

a8_white = make_a8(1, 1, 1, 0.5)
a8_black = make_a8(0, 0, 0, 0.5)
vw = a8_val(a8_white, 32, 32)
vb = a8_val(a8_black, 32, 32)
record(approx(vw, 128, 2), "A8 white@0.5 -> 128", "128", f"{vw}",
       "" if approx(vw, 128, 2) else "A8 write off")
record(approx(vb, 128, 2), "A8 black@0.5 -> 128 (alpha-only)", "128", f"{vb}",
       "" if approx(vb, 128, 2) else
       "REAL BUG: A8 stores premultiplied COLOR (alpha*luminance), not coverage "
       "alpha; black@0.5 yields 0 instead of 128. A8 should ignore source RGB.")

# --- mask() with a valid A8 (value 128) over an OPAQUE red source.
# Expected: coverage 0.5 applied to red(a=1) -> premult red@0.5 = (0,0,128,128).
print("\n[4c] mask() / mask_surface coverage")
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_source_rgba(1, 0, 0, 1)
ctx.mask(cairo.SurfacePattern(a8_white))
s.flush()
got = px_bgra(s, 32, 32)
# Color channels: red masked 0.5 -> R=128. Alpha: must also be 0.5 -> 128.
ok_color = approx(got[2], 128, 3) and approx(got[0], 0, 3) and approx(got[1], 0, 3)
ok_alpha = approx(got[3], 128, 3)
record(ok_color and ok_alpha, "mask() red by A8=0.5", "BGRA(0,0,128,128)",
       f"BGRA{got}",
       "" if (ok_color and ok_alpha) else
       ("REAL BUG: mask() masks color channels but leaves ALPHA unmasked (A=255 "
        "instead of 128) -> result is not premultiplied-consistent."
        if ok_color and not ok_alpha else "mask() coverage wrong"))

# mask_surface (uses a DIFFERENT A8 to avoid the reuse-crash; see [4d]).
a8_white2 = make_a8(1, 1, 1, 0.5)
s = new_surface(W, H)
ctx = cairo.Context(s)
ctx.set_source_rgba(0, 1, 0, 1)
ctx.mask_surface(a8_white2, 0, 0)
s.flush()
got = px_bgra(s, 32, 32)
ok_color = approx(got[1], 128, 3) and approx(got[0], 0, 3) and approx(got[2], 0, 3)
ok_alpha = approx(got[3], 128, 3)
# Characterized separately: mask_surface ALWAYS emits BGRA(0,0,<A8val>,255) -- it
# ignores the source color and writes the A8 coverage value into the RED channel.
ignores_src = approx(got[2], 128, 3) and got[0] == 0 and got[1] == 0 and got[3] == 255
record(ok_color and ok_alpha, "mask_surface green by A8=0.5", "BGRA(0,128,0,128)",
       f"BGRA{got}",
       "" if (ok_color and ok_alpha) else
       ("REAL BUG: mask_surface IGNORES the source-pattern color and writes the A8 "
        "coverage value straight into the RED channel (result BGRA(0,0,A8val,255) "
        "for any source color); alpha left at 255. mask_surface is non-functional "
        "for color." if ignores_src else "mask_surface coverage wrong"))

# --- Lifecycle crash: reusing the SAME A8 surface for mask() then mask_surface()
# corrupts the target's GPU map and aborts the process on the next get_data().
# Run it in a child process so we can OBSERVE the crash without killing this suite.
print("\n[4d] A8-mask-reuse lifecycle (subprocess; expected to crash today)")
import subprocess, os, textwrap
child = textwrap.dedent('''
    import cairo_metal as cairo
    W=H=64
    m=cairo.ImageSurface(cairo.FORMAT_A8,W,H); c=cairo.Context(m)
    c.set_source_rgba(1,1,1,0.5); c.paint(); m.flush()
    s1=cairo.ImageSurface(cairo.FORMAT_ARGB32,W,H); c1=cairo.Context(s1)
    c1.set_source_rgba(1,0,0,1); c1.mask(cairo.SurfacePattern(m)); s1.flush()
    _=bytes(s1.get_data())
    s2=cairo.ImageSurface(cairo.FORMAT_ARGB32,W,H); c2=cairo.Context(s2)
    c2.set_source_rgba(0,1,0,1); c2.mask_surface(m,0,0); s2.flush()
    _=bytes(s2.get_data())          # <-- aborts here today
    print("OK")
''')
env = dict(os.environ)
res = subprocess.run([sys.executable, "-c", child], capture_output=True, text=True, env=env)
reuse_ok = (res.returncode == 0 and "OK" in res.stdout)
record(reuse_ok, "reuse one A8 for mask()+mask_surface() does not crash",
       "child exits 0 with 'OK'",
       f"returncode={res.returncode}, stdout={res.stdout.strip()!r}, "
       f"stderr_tail={res.stderr.strip()[-120:]!r}",
       "" if reuse_ok else
       "REAL BUG: reusing one A8 surface as the mask for both mask() and "
       "mask_surface() leaves a dangling/double GPU map; the subsequent get_data() "
       "raises 'surface map failed' and SIGABRTs the process (returncode -6/134).")

# ----------------------------------------------------------------------------
# 5. GRADIENTS
# ----------------------------------------------------------------------------
print("\n[5] Gradients")
GW = 256  # wide, multiple of 32
s = cairo.ImageSurface(cairo.FORMAT_ARGB32, GW, 16)
ctx = cairo.Context(s)
lg = cairo.LinearGradient(0, 0, GW, 0)
lg.add_color_stop_rgba(0.0, 0, 0, 0, 1)   # black opaque
lg.add_color_stop_rgba(1.0, 1, 1, 1, 1)   # white opaque
ctx.set_source(lg)
ctx.paint()
s.flush()
# sample x=0, mid, end ; expect R~ x/(GW-1)*255 (linear). Gradient sampling tol +-6.
for xs, label in [(0, "x=0"), (GW // 2, "x=mid"), (GW - 1, "x=end")]:
    got = px_bgra(s, xs, 8)
    # opaque grey ramp: at position t=xs/(GW-1) (cairo maps pixel center; use xs/GW..)
    # cairo evaluates gradient at the pixel's location along the axis; for x in [0,GW]
    # offset ~ (xs+0.5)/GW. Expected channel value ~ offset*255 (grey, all equal).
    t = (xs + 0.5) / GW
    exp_v = round(t * 255)
    # grey => B=G=R=exp_v, A=255 (opaque, premult grey)
    ok = (approx(got[0], exp_v, 6) and approx(got[1], exp_v, 6)
          and approx(got[2], exp_v, 6) and approx(got[3], 255, 2))
    record(ok, f"linear gradient {label}", f"grey~{exp_v} (B=G=R), A=255",
           f"BGRA{got}", "" if ok else "gradient ramp value off (>6) -> investigate")

# also assert monotonic increase L->R
mids = [px_bgra(s, x, 8)[2] for x in (10, 64, 128, 200, 245)]
mono = all(mids[i] <= mids[i + 1] + 2 for i in range(len(mids) - 1))
record(mono, "linear gradient monotonic L->R", "non-decreasing R", f"{mids}",
       "" if mono else "gradient not monotonic -> direction/eval bug")

# Radial: center white -> edge black
print("\n[5b] Radial gradient")
RW = 128
s = cairo.ImageSurface(cairo.FORMAT_ARGB32, RW, RW)
ctx = cairo.Context(s)
rg = cairo.RadialGradient(RW / 2, RW / 2, 0, RW / 2, RW / 2, RW / 2)
rg.add_color_stop_rgba(0.0, 1, 1, 1, 1)   # center white
rg.add_color_stop_rgba(1.0, 0, 0, 0, 1)   # edge black
ctx.set_source(rg)
ctx.paint()
s.flush()
center = px_bgra(s, RW // 2, RW // 2)
corner = px_bgra(s, 2, 2)
record(center[2] >= 250, "radial center bright", "R>=250", f"R={center[2]} (BGRA{center})",
       "" if center[2] >= 250 else "radial center not white")
record(corner[2] <= 30, "radial corner dark", "R<=30", f"R={corner[2]} (BGRA{corner})",
       "" if corner[2] <= 30 else "radial corner not dark")
# midway between center and edge (dist = RW/4) should be ~ mid grey along radius
midpt = px_bgra(s, RW // 2 + RW // 4, RW // 2)
# t = dist/radius = (RW/4)/(RW/2)=0.5 -> grey ~128
record(approx(midpt[2], 128, 18), "radial mid radius ~grey", "R~128 (+-18)",
       f"R={midpt[2]}", "" if approx(midpt[2], 128, 18) else "radial radial-falloff off")

# ----------------------------------------------------------------------------
# 6. STROKE band width & caps
# ----------------------------------------------------------------------------
print("\n[6] Stroke band width & caps")
SW, SH = 64, 64
s = new_surface(SW, SH)
ctx = cairo.Context(s)
ctx.set_source_rgba(1, 0, 0, 1)
ctx.set_line_width(8)
ctx.set_line_cap(cairo.LINE_CAP_BUTT)
cy = SH / 2  # 32.0
ctx.move_to(10, cy)
ctx.line_to(SW - 10, cy)   # to x=54
ctx.stroke()
s.flush()
# Within +-3 of center-y should be solid red (band half-width=4); 6px away background.
xmid = SW // 2  # 32, inside [10,54]
check_bgra("stroke band center", s, xmid, 32, (0, 0, 255, 255), tol=2,
           assessment="line center -> full stroke color")
check_bgra("stroke band +3px", s, xmid, 35, (0, 0, 255, 255), tol=2,
           assessment="3px from center still within 4px half-width")
# 6px away (y=38 or y=26): outside the 4px half-width -> background
check_bgra("stroke band +6px is bg", s, xmid, 38, (0, 0, 0, 0), tol=2,
           assessment="6px from center > half-width(4) -> background")
check_bgra("stroke band -6px is bg", s, xmid, 26, (0, 0, 0, 0), tol=2)

# Caps: BUTT must NOT extend past endpoint x=54; SQUARE extends ~line_width/2=4.
print("\n[6b] BUTT vs SQUARE cap extension")
def stroke_caps(cap):
    s = new_surface(SW, SH)
    ctx = cairo.Context(s)
    ctx.set_source_rgba(1, 0, 0, 1)
    ctx.set_line_width(8)
    ctx.set_line_cap(cap)
    ctx.move_to(10, cy); ctx.line_to(40, cy)   # endpoint x=40
    ctx.stroke()
    s.flush()
    return s

s_butt = stroke_caps(cairo.LINE_CAP_BUTT)
s_sq = stroke_caps(cairo.LINE_CAP_SQUARE)
# Just inside the line (x=38, y=32): both filled
check_bgra("butt: interior filled", s_butt, 38, 32, (0, 0, 255, 255), tol=2)
check_bgra("square: interior filled", s_sq, 38, 32, (0, 0, 255, 255), tol=2)
# x=42 (2px beyond endpoint 40): BUTT background, SQUARE filled
check_bgra("butt: 2px beyond endpoint = bg", s_butt, 42, 32, (0, 0, 0, 0), tol=2,
           assessment="butt cap ends exactly at endpoint")
check_bgra("square: 2px beyond endpoint filled", s_sq, 42, 32, (0, 0, 255, 255), tol=2,
           assessment="square cap extends line_width/2=4 beyond endpoint")
# x=47 (7px beyond, > 4 extension): SQUARE also background
check_bgra("square: 7px beyond = bg", s_sq, 47, 32, (0, 0, 0, 0), tol=2,
           assessment="square extends only 4px -> 7px is background")

# ----------------------------------------------------------------------------
# 7. ANTI-ALIASING (non-axis-aligned edge -> intermediate values)
# ----------------------------------------------------------------------------
print("\n[7] Anti-aliasing on a diagonal edge")
AW = 64
s = new_surface(AW, AW)
ctx = cairo.Context(s)
ctx.set_antialias(cairo.ANTIALIAS_DEFAULT)
ctx.set_source_rgba(1, 1, 1, 1)
# triangle covering lower-left under a diagonal y=x line
ctx.move_to(0, 0); ctx.line_to(AW, AW); ctx.line_to(0, AW); ctx.close_path()
ctx.fill()
s.flush()
# Scan pixels straddling the diagonal; expect some A in (0,255).
intermediate = 0
total_edge = 0
samples = []
for d in range(2, AW - 2):
    a = px_bgra(s, d, d)[3]   # right on the diagonal
    total_edge += 1
    if 10 < a < 245:
        intermediate += 1
    if len(samples) < 8:
        samples.append(a)
record(intermediate >= 5, "AA produces intermediate alphas on diagonal",
       ">=5 edge px with 10<A<245", f"{intermediate}/{total_edge} edge px intermediate; sample A={samples}",
       "" if intermediate >= 5 else "AA appears OFF (all edge px hard 0/255)")

# ANTIALIAS_NONE correctness. The SOLID INTERIOR of a fill must be fully opaque
# (alpha 255) under EVERY antialias mode -- AA only affects edge pixels. We check
# the deep interior (far from any edge) of an axis-aligned rectangle.
s = new_surface(AW, AW)
ctx = cairo.Context(s)
ctx.set_antialias(cairo.ANTIALIAS_NONE)
ctx.set_source_rgba(1, 1, 1, 1)
ctx.rectangle(8, 8, 48, 48)   # interior point (32,32) is ~24px from any edge
ctx.fill()
s.flush()
interior = px_bgra(s, 32, 32)
record(approx(interior[3], 255, 2) and approx(interior[2], 255, 2),
       "ANTIALIAS_NONE: solid interior fully opaque",
       "BGRA(255,255,255,255)", f"BGRA{interior}",
       "" if approx(interior[3], 255, 2) else
       "REAL BUG: ANTIALIAS_NONE corrupts the SOLID interior of every fill to "
       f"alpha {interior[3]} (~25%); DEFAULT/GOOD/FAST give 255. Any drawing using "
       "set_antialias(ANTIALIAS_NONE) renders near-transparent.")

# And the diagonal-edge sanity under NONE (secondary): with AA off, on-diagonal
# pixels should be a clean 0/255 step, not partial coverage.
s = new_surface(AW, AW)
ctx = cairo.Context(s)
ctx.set_antialias(cairo.ANTIALIAS_NONE)
ctx.set_source_rgba(1, 1, 1, 1)
ctx.move_to(0, 0); ctx.line_to(AW, AW); ctx.line_to(0, AW); ctx.close_path()
ctx.fill()
s.flush()
hard = sum(1 for d in range(2, AW - 2) if px_bgra(s, d, d)[3] in (0, 255))
record(hard >= (AW - 4) - 3, "ANTIALIAS_NONE diagonal is a hard 0/255 step",
       f"~all of {AW-4} diagonal px are 0 or 255", f"{hard} hard px",
       "" if hard >= (AW - 4) - 3 else
       "ANTIALIAS_NONE not honored: diagonal pixels carry partial coverage "
       "(consistent with the interior-opacity bug above).")

# ----------------------------------------------------------------------------
# REPORT
# ----------------------------------------------------------------------------
print("\n" + "=" * 70)
print(f"TOTAL CHECKS: {CHECKS}    PASS: {PASS}    FAIL: {FAIL}")
print("=" * 70)
if FAILURES:
    print("\nFAILURES:")
    for i, (feat, exp, act, ass) in enumerate(FAILURES, 1):
        print(f"\n{i}. {feat}")
        print(f"   expected : {exp}")
        print(f"   actual   : {act}")
        print(f"   assessment: {ass}")
else:
    print("\nAll checks passed.")

sys.exit(0 if FAIL == 0 else 1)
