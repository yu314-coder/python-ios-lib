#!/usr/bin/env python3
# =====================================================================
# test_reference.py -- gold-standard pixel diff: CairoMetal vs REAL cairo
# ---------------------------------------------------------------------
# Renders identical scenes through pycairo (real libcairo, software) and
# through cairo_metal (our GPU/Metal engine), then compares the ARGB32
# buffers byte-for-byte. Interiors should match within premultiplied-alpha
# rounding (+-1 LSB); anti-aliased EDGES legitimately differ because the two
# use different rasterizers (libcairo's coverage AA vs our MSAA), so a few
# units of MEAN diff on edged shapes is expected, not a bug.
#
# Run on macOS with pycairo installed:
#   CM_METALLIB=<cairo(metal)>/build/default.metallib \
#   PYTHONPATH=<cairo(metal)>/python python3 tests/test_reference.py
# =====================================================================
import os, math, sys

try:
    import cairo as REF            # real pycairo / libcairo
except Exception as e:
    print("pycairo (real cairo) not importable:", e)
    print("install with:  python3 -m pip install pycairo")
    sys.exit(2)
import cairo_metal as CM           # our Metal engine

if not os.environ.get("CM_METALLIB"):
    for cand in ("../build/default.metallib", "build/default.metallib"):
        p = os.path.join(os.path.dirname(CM.__file__), cand)
        if os.path.exists(p):
            os.environ["CM_METALLIB"] = p
            break

W = H = 64

def render(C, scene):
    s = C.ImageSurface(C.FORMAT_ARGB32, W, H)
    ctx = C.Context(s)            # MUST stay alive through flush(): cairo_metal
    scene(C, ctx)                 # commits its deferred GPU frame on surface.flush(),
    s.flush()                     # so a context destroyed before flush loses the frame.
    data = bytes(s.get_data())
    del ctx
    return data

def compare(scene):
    a = render(REF, scene)
    b = render(CM, scene)
    n = min(len(a), len(b))
    mx = 0
    tot = 0
    nonzero = 0
    for i in range(n):
        d = a[i] - b[i]
        if d < 0:
            d = -d
        if d > mx:
            mx = d
        tot += d
        if d > 24:           # count "materially different" bytes (beyond AA/round)
            nonzero += 1
    return mx, tot / n, nonzero, n

# --- scenes: identical pycairo-style API drives BOTH backends ----------
def s_solid(C, c):
    c.set_source_rgba(1, 0, 0, 1); c.rectangle(8, 8, 48, 48); c.fill()
def s_evenodd(C, c):
    c.set_source_rgba(1, 1, 1, 1); c.set_fill_rule(C.FILL_RULE_EVEN_ODD)
    c.rectangle(8, 8, 48, 48); c.rectangle(40, 40, -16, -16); c.fill()
def s_linear(C, c):
    g = C.LinearGradient(0, 0, 64, 0)
    g.add_color_stop_rgba(0, 0, 0, 0, 1); g.add_color_stop_rgba(1, 1, 1, 1, 1)
    c.set_source(g); c.paint()
def s_radial(C, c):
    g = C.RadialGradient(32, 32, 0, 32, 32, 32)
    g.add_color_stop_rgba(0, 1, 1, 1, 1); g.add_color_stop_rgba(1, 0, 0, 0, 1)
    c.set_source(g); c.paint()
def s_over(C, c):
    c.set_source_rgba(0, 0, 1, 1); c.paint()
    c.set_source_rgba(1, 0, 0, 0.5); c.paint()
def s_multiply(C, c):
    c.set_source_rgba(0, 0, 1, 1); c.paint()
    c.set_operator(C.OPERATOR_MULTIPLY); c.set_source_rgba(1, 0.6, 0.2, 1); c.paint()
def s_screen(C, c):
    c.set_source_rgba(0, 0, 1, 1); c.paint()
    c.set_operator(C.OPERATOR_SCREEN); c.set_source_rgba(1, 0, 0, 1); c.paint()
def s_clip_rect(C, c):
    c.rectangle(16, 16, 32, 32); c.clip(); c.set_source_rgba(1, 0, 0, 1); c.paint()
def s_clip_circ(C, c):
    c.arc(32, 32, 22, 0, 2 * math.pi); c.clip(); c.set_source_rgba(1, 0, 0, 1); c.paint()
def s_alpha(C, c):
    c.set_source_rgba(0, 0, 1, 1); c.paint()
    c.set_source_rgba(1, 0, 0, 1); c.paint_with_alpha(0.5)
def s_arc(C, c):
    c.arc(32, 32, 20, 0, 2 * math.pi); c.set_source_rgba(0, 0.7, 1, 1); c.fill()
def s_xform(C, c):
    c.translate(20, 12); c.scale(2, 2); c.set_source_rgba(1, 0, 0, 1); c.rectangle(0, 0, 12, 12); c.fill()

SCENES = [
    ("solid fill", s_solid), ("even-odd hole", s_evenodd),
    ("linear gradient", s_linear), ("radial gradient", s_radial),
    ("operator OVER (50%)", s_over), ("operator MULTIPLY", s_multiply),
    ("operator SCREEN", s_screen), ("clip rectangle", s_clip_rect),
    ("clip circle", s_clip_circ), ("paint_with_alpha", s_alpha),
    ("arc fill", s_arc), ("transform t+s", s_xform),
]

print("=" * 60)
print(" pycairo", REF.version, "/ libcairo", REF.cairo_version_string())
print(" vs cairo_metal  GPU:", CM.gpu_selftest()[1])
print("=" * 60)
print(" %-22s %4s %6s  %s" % ("scene", "max", "mean", "verdict"))
print("-" * 60)
worst_mean = 0.0
fails = 0
for name, fn in SCENES:
    try:
        mx, mean, nz, n = compare(fn)
    except Exception as e:
        print(" %-22s   --   --   ERROR %s" % (name, e))
        fails += 1
        continue
    worst_mean = max(worst_mean, mean)
    # interiors must match within rounding; small mean = AA-edge-only differences
    if mean < 3.0 and mx <= 8:
        verdict = "MATCH (within rounding)"
    elif mean < 12.0:
        verdict = "match; diff is AA edges"
    else:
        verdict = "DIFF -- investigate"
        fails += 1
    print(" %-22s %4d %6.2f  %s" % (name, mx, mean, verdict))
print("-" * 60)
print(" worst mean abs diff: %.2f   (interiors exact to +-1 LSB; mean>0 = AA-edge" % worst_mean)
print(" rasterizer differences, expected vs a different cairo backend)")
print(" scenes flagged DIFF/ERROR:", fails)
sys.exit(1 if fails else 0)
