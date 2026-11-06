#!/usr/bin/env python3
"""
Context._append_cubic_curves and the transparent-source early-out.

Run:
  CM_METALLIB=".../build/default.metallib" \
  PYTHONPATH=".../python" \
  python3 '.../tests/test_path_batch.py'

_append_cubic_curves(points, atol) builds, in one call, the path manim's camera
builds from a VMobject's cubic Bezier points: a subpath starts wherever a
curve's first anchor is not the previous curve's last anchor, and a subpath is
closed when its last point equals its first (manim's consider_points_equals_2d:
|dx| <= atol + 1e-5*|x| and |dy| <= atol + 1e-5*|y|).  Checked here against that
rule written out in Python (manim's own loop), on random shapes built to land
on, just inside and just outside the tolerance.
"""
import math
import sys

import numpy as np

import cairo_metal as cairo

PASS = FAIL = 0


def check(label, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  [PASS] {label}")
    else:
        FAIL += 1
        print(f"  [FAIL] {label}  {detail}")


INF = float("inf")


def python_loop(ctx, points, atol):
    """manim's camera._append_cubic_path, as it is written there."""
    count = len(points) // 4
    rows = points[:, :2].reshape(count, 8).tolist()
    rtol = 1.0e-5
    same_passes = atol >= 0
    first = prev = rows[0]
    ctx.new_sub_path()
    ctx.move_to(first[0], first[1])
    for row in rows:
        if row is not first:
            x, y, px, py = row[0], row[1], prev[6], prev[7]
            if not (same_passes and px == x and py == y and -INF < y < INF) and (
                abs(px - x) > atol + rtol * abs(x) or not (abs(py - y) <= atol + rtol * abs(y))
            ):
                if not (abs(first[0] - px) > atol + rtol * abs(px)) and abs(first[1] - py) <= atol + rtol * abs(py):
                    ctx.close_path()
                first = row
                ctx.new_sub_path()
                ctx.move_to(x, y)
        ctx.curve_to(row[2], row[3], row[4], row[5], row[6], row[7])
        prev = row
    x, y = prev[6], prev[7]
    if not (abs(first[0] - x) > atol + rtol * abs(x)) and abs(first[1] - y) <= atol + rtol * abs(y):
        ctx.close_path()


surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 64, 64)
ctx = cairo.Context(surf)


def path_of(build):
    ctx.new_path()
    build()
    return list(ctx.copy_path())


print("== the same path as manim's loop ==")
rng = np.random.default_rng(11)
same = total = 0
for trial in range(600):
    n = int(rng.integers(1, 16))
    pts = rng.normal(scale=3.0, size=(4 * n, 3))
    atol = float(rng.choice([1e-8, 1e-6, 1e-3, 0.0]))
    for j in range(4, len(pts), 4):          # joins: exact, inside, at, outside the tolerance
        r = rng.random()
        if r < 0.4:
            pts[j] = pts[j - 1]
        elif r < 0.55:
            pts[j] = pts[j - 1] + rng.choice([-1, 1], 3) * atol * rng.uniform(0.2, 0.9)
        elif r < 0.7:
            pts[j] = pts[j - 1] + rng.choice([-1, 1], 3) * atol * rng.uniform(1.1, 3.0)
    if rng.random() < 0.5:
        pts[-1] = pts[0]
    if trial % 50 == 7 and n > 1:            # a non-finite y, as manim may meet it
        pts[4, 1] = pts[3, 1] = INF
    total += 1
    a = path_of(lambda: ctx._append_cubic_curves(np.ascontiguousarray(pts), atol))
    b = path_of(lambda: python_loop(ctx, pts, atol))
    same += a == b
check(f"{same} of {total} random paths identical (subpaths, closes, tolerances)", same == total)
pts2 = rng.normal(size=(8, 2))
check("two columns (x, y) work as well as three",
      path_of(lambda: ctx._append_cubic_curves(pts2, 1e-6)) == path_of(lambda: python_loop(ctx, pts2, 1e-6)))
for bad, why in ((np.zeros((6, 3)), "not 4n rows"), (np.zeros((8, 3), np.float32), "float32"),
                 (np.zeros((8, 3))[:, ::2].copy()[:, :1], "one column"), (np.zeros((8, 3)).T, "not C-contiguous")):
    try:
        ctx._append_cubic_curves(bad, 1e-6)
        check(f"refuses {why}", False, "no error")
    except (ValueError, BufferError, TypeError):
        check(f"refuses {why}", True)
check("an empty array is no path", path_of(lambda: ctx._append_cubic_curves(np.zeros((0, 3)), 1e-6)) == [])

print("== a transparent source drawn OVER does nothing ==")
W = H = 256
a = np.empty((H, W, 4), np.uint8)
a[:] = (10, 20, 30, 255)
s = cairo.ImageSurface.create_for_data(a.data, cairo.FORMAT_ARGB32, W, H)
c = cairo.Context(s)
c.set_source_rgba(0, 0, 1, 1)               # a frame the GPU runs, to read its time
c.rectangle(200, 200, 8, 8)
c.fill()
cairo._flush_all()
before = a.copy()
gpu0 = cairo.last_gpu_ms()                  # changes whenever a frame is waited for
c.set_source_rgba(1, 0, 0, 0)
c.arc(128, 128, 100, 0, 2 * math.pi)
c.fill_preserve()
c.set_line_width(9)
c.stroke()
cairo._flush_all()
check("pixels unchanged", np.array_equal(a, before))
check("no GPU frame was begun for it", cairo.last_gpu_ms() == gpu0, f"{gpu0} -> {cairo.last_gpu_ms()}")
c.set_source_rgba(1, 0, 0, 1)
c.rectangle(10, 10, 20, 20)
c.fill()
cairo._flush_all()
check("an opaque fill afterwards still draws", tuple(a[15, 15]) == (0, 0, 255, 255), str(a[15, 15]))
c.set_operator(cairo.OPERATOR_SOURCE)
c.set_source_rgba(0, 0, 0, 0)
c.rectangle(100, 100, 10, 10)
c.fill()
cairo._flush_all()
check("…and SOURCE with a transparent source still clears", tuple(a[105, 105]) == (0, 0, 0, 0), str(a[105, 105]))
del c, s

print()
print(f"TOTAL: {PASS + FAIL}   PASS: {PASS}   FAIL: {FAIL}")
sys.exit(1 if FAIL else 0)
