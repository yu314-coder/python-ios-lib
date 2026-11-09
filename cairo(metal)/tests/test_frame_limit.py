"""
test_frame_limit.py — drawing never waits for ever for a GPU frame.

    CM_METALLIB=".../build/default.metallib" \\
      PYTHONPATH=python python3 tests/test_frame_limit.py

cairo draws at once. CairoMetal batches a surface's drawing into one open
frame (one command buffer) until the surface is flushed, and the device has
three frames (CM_FRAMES_IN_FLIGHT). A fourth surface drawn while three others
held open frames waited for a frame only a flush of those surfaces could
return — for ever, holding the GIL, so nothing else in the process ran
(2026-11-09: manim_image_test.py hung CodeBench's GPU mode; manim with more
than 64 live cameras overflowed the flush registry, so their frames were
never flushed). Each case runs in a child process with a time limit, so a
hang is a FAIL here, not a hung test.
"""
from __future__ import annotations

import os
import subprocess
import sys
import textwrap
import time

PASS = FAIL = 0
LIMIT_S = 30


def check(label, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  [PASS] {label}")
    else:
        FAIL += 1
        print(f"  [FAIL] {label}  {detail}")


PRELUDE = textwrap.dedent("""
    import gc, sys
    import numpy as np
    import cairo_metal as cairo

    def surface(w=64, h=48):
        buf = np.zeros((h, w, 4), np.uint8)
        return buf, cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_ARGB32, w, h, w * 4)

    def fill(s, rgb=(1, 0, 0), aa=None):
        ctx = cairo.Context(s)
        if aa is not None:
            ctx.set_antialias(aa)
        ctx.set_source_rgb(*rgb)
        ctx.rectangle(8, 8, 32, 24)
        ctx.fill()
        return ctx

    def red_at_centre(buf):
        b, g, r, a = (int(v) for v in buf[20, 24])   # premultiplied BGRA
        return r > 200 and g < 40 and b < 40 and a > 200
""")


IN_PROCESS = sys.platform.startswith("ios")   # iOS has no subprocess


def run_here(label, code, expect):
    """iOS: the case runs in this process. A hang can't be caught from here
    (it holds the GIL), but with the engine's frame wait bounded it is an
    error after CM_FRAME_WAIT_S, not a hang."""
    import contextlib
    import io
    out = io.StringIO()
    started = time.monotonic()
    try:
        with contextlib.redirect_stdout(out):
            exec(compile(code, "<case>", "exec"), {"__name__": "__case__"})
        error = ""
    except SystemExit:
        error = ""
    except Exception as e:  # noqa: BLE001 - reported as a check
        error = f"{type(e).__name__}: {e}"
    took = time.monotonic() - started
    lines = [l for l in out.getvalue().splitlines() if l.strip()]
    last = lines[-1] if lines else ""
    check(f"{label} ({took:.1f} s)", not error and last == expect, f"{error} last line {last!r}")


def run(label, body, expect="OK"):
    """Run PRELUDE + body in a child; it must print `expect` and exit 0 in time."""
    code = PRELUDE + textwrap.dedent(body)
    if IN_PROCESS:
        return run_here(label, code, expect)
    env = dict(os.environ)
    started = time.monotonic()
    try:
        out = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True,
                             text=True, timeout=LIMIT_S)
    except subprocess.TimeoutExpired:
        check(label, False, f"hung: no answer in {LIMIT_S} s")
        return
    took = time.monotonic() - started
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    last = lines[-1] if lines else ""
    check(f"{label} ({took:.1f} s)", out.returncode == 0 and last == expect,
          f"exit {out.returncode}, last line {last!r}, stderr {out.stderr[-300:]!r}")


print("== more surfaces drawn than there are frames, none flushed ==")
run("five create_for_data surfaces drawn in turn, then flushed", """
    surfs = [surface() for _ in range(5)]
    ctxs = [fill(s) for _, s in surfs]
    for _, s in surfs:
        s.flush()
    print("OK" if all(red_at_centre(b) for b, _ in surfs) else "missing pixels")
""")
run("twelve surfaces, each drawn twice in turn (frames end early, nothing lost)", """
    surfs = [surface() for _ in range(12)]
    ctxs = [fill(s, (0, 0, 1)) for _, s in surfs]
    ctxs = [fill(s) for _, s in surfs]
    for _, s in surfs:
        s.flush()
    print("OK" if all(red_at_centre(b) for b, _ in surfs) else "missing pixels")
""")
run("plain ImageSurfaces (not create_for_data) the same way", """
    surfs = [cairo.ImageSurface(cairo.FORMAT_ARGB32, 64, 48) for _ in range(6)]
    ctxs = [fill(s) for s in surfs]
    for s in surfs:
        s.flush()
    ok = all(s.get_data()[20 * s.get_stride() + 24 * 4 + 2] > 200 for s in surfs)
    print("OK" if ok else "missing pixels")
""")
run("ANTIALIAS_NONE draws among open frames", """
    surfs = [surface() for _ in range(4)]
    ctxs = [fill(s) for _, s in surfs[:3]]
    fill(surfs[3][1], aa=cairo.ANTIALIAS_NONE)
    for _, s in surfs:
        s.flush()
    print("OK" if all(red_at_centre(b) for b, _ in surfs) else "missing pixels")
""")

# CairoMetal blends in float where cairo rounds to 8 bits after every
# operator: at half alpha the two differ by one level, with or without frames
# ended early (3 surfaces, none ended early, differ the same way). So: within
# one level of real cairo, with frames ended early along the way.
run("random draws over 7 surfaces in turn stay within 1 of real cairo", """
    import random
    import cairo as real                     # pycairo: the reference
    if hasattr(real, "_flush_all"):
        # An app's GPU switch put CairoMetal in as `cairo` (CodeBench's does):
        # import the real pycairo package past it.
        swapped = sys.modules.pop("cairo")
        try:
            import cairo as real
        finally:
            sys.modules["cairo"] = swapped
    assert not hasattr(real, "_flush_all"), "no pycairo to compare with"
    rnd = random.Random(7)
    W, H, N = 96, 64, 7
    ops = [(cairo.OPERATOR_OVER, real.OPERATOR_OVER), (cairo.OPERATOR_SOURCE, real.OPERATOR_SOURCE),
           (cairo.OPERATOR_ADD, real.OPERATOR_ADD), (cairo.OPERATOR_CLEAR, real.OPERATOR_CLEAR)]
    mine, ref = [], []
    for _ in range(N):
        b = np.zeros((H, W, 4), np.uint8)
        mine.append((b, cairo.ImageSurface.create_for_data(b, cairo.FORMAT_ARGB32, W, H, W * 4)))
        ref.append(real.ImageSurface(real.FORMAT_ARGB32, W, H))
    mctx = [cairo.Context(s) for _, s in mine]
    rctx = [real.Context(s) for s in ref]
    before = cairo._frames_ended_early()
    for _ in range(160):
        i = rnd.randrange(N)
        x, y = rnd.randrange(0, W - 8), rnd.randrange(0, H - 8)
        w, h = rnd.randrange(4, W - x), rnd.randrange(4, H - y)
        r, g, b, a = (rnd.choice([0.0, 0.5, 1.0]) for _ in range(4))
        op = rnd.choice(ops) if rnd.random() < 0.3 else ops[0]
        for ctx, k in ((mctx[i], 0), (rctx[i], 1)):
            ctx.set_operator(op[k])
            ctx.set_source_rgba(r, g, b, a)
            ctx.rectangle(x, y, w, h)
            ctx.fill()
    for _, s in mine:
        s.flush()
    bad = []
    for i in range(N):
        ref[i].flush()
        want = np.ndarray((H, W, 4), np.uint8, ref[i].get_data(), 0, (ref[i].get_stride(), 4, 1))
        worst = int(np.abs(mine[i][0].astype(int) - want.astype(int)).max())
        if worst > 1:
            bad.append((i, worst))
    ended = cairo._frames_ended_early() - before
    print("OK" if not bad and ended > 0 else f"differ {bad}, frames ended early {ended}")
""")

print("\n== manim's way: many live surfaces, flushed through _flush_all ==")
run("100 live create_for_data surfaces, each drawn and _flush_all'd", """
    gc.disable()          # as when the collector has not run: they all stay alive
    keep = []
    for i in range(100):
        buf, s = surface()
        ctx = fill(s)
        cairo._flush_all()
        keep.append((buf, s, ctx))
        if not red_at_centre(buf):
            print(f"surface {i} not drawn after _flush_all"); sys.exit(0)
    gc.enable()
    print("OK" if cairo.live_surfaces() >= 100 else f"registry holds {cairo.live_surfaces()}")
""")
run("and the registry lets go of them", """
    gc.collect()
    base = cairo.live_surfaces()
    keep = [surface() for _ in range(150)]
    n = cairo.live_surfaces() - base
    del keep
    gc.collect()
    left = cairo.live_surfaces() - base
    print("OK" if n == 150 and left == 0 else f"{n} added, {left} left")
""")

print()
print(f"TOTAL: {PASS + FAIL}   PASS: {PASS}   FAIL: {FAIL}")
sys.exit(1 if FAIL else 0)
