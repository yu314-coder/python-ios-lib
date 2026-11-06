#!/usr/bin/env python3
"""
Layer frames and kept GPU wraps (frames drawn into caller memory).

Run:
  CM_METALLIB=".../build/default.metallib" \
  PYTHONPATH=".../python" \
  python3 '.../tests/test_layer_frames.py'

A frame drawn into a caller's buffer (ImageSurface.create_for_data, manim's
pixel_array) draws its OVER draws on a transparent layer and composites the
layer into the buffer at its end, instead of loading the whole buffer into the
GPU and resolving all of it back.  Every scene here is drawn both ways
(cairo_metal._set_layer_frames) and compared: opaque OVER scenes must agree to
one level; translucency over a background rounds to 8 bits after every draw in
both paths, on different values, so there both are held to the exact result;
a scene that switches operator mid frame finishes its layer first and must
still agree away from shape edges.
Also: the GPU wrap of an array is kept while the array lives (a new surface
over it reuses it) and dropped when the array is freed.
"""
import gc
import math
import os
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


W, H = 517, 389          # odd: tiles cut off at the right and bottom edges
rng0 = np.random.default_rng(7)
NOISE = rng0.integers(0, 256, (H, W, 4)).astype(np.uint8)
NOISE[:, :, 3] = 255


def draw_scene(name, a):
    s = cairo.ImageSurface.create_for_data(a.data, cairo.FORMAT_ARGB32, W, H)
    c = cairo.Context(s)
    if name == "opaque shapes":
        for i in range(40):
            c.set_source_rgb((i % 5) / 4, (i % 3) / 2, (i % 7) / 6)
            c.arc(13 * i % W, 29 * i % H, 5 + i % 30, 0, 2 * math.pi)
            c.fill()
    elif name == "translucent stack":
        for i in range(30):
            c.set_source_rgba(1, 0.4, 0.1 * (i % 10), 0.15)
            c.rectangle(10 + 7 * i, 10 + 5 * i, 200, 150)
            c.fill()
    elif name == "strokes":
        c.set_line_width(6)
        for i in range(12):
            c.set_source_rgba(0.2, 0.9, 0.4, 0.8)
            c.move_to(5, 20 + 30 * i)
            c.curve_to(150, 300 - 20 * i, 300, 10 + 25 * i, W - 5, 200)
            c.stroke()
    elif name == "gradients":
        g = cairo.LinearGradient(0, 0, W, H)
        g.add_color_stop_rgba(0, 1, 0, 0, 1)
        g.add_color_stop_rgba(1, 0, 0, 1, 0.3)
        c.set_source(g)
        c.arc(W / 2, H / 2, 150, 0, 2 * math.pi)
        c.fill()
        r = cairo.RadialGradient(100, 100, 5, 120, 120, 90)
        r.add_color_stop_rgba(0, 1, 1, 1, 1)
        r.add_color_stop_rgba(1, 0, 0.5, 0, 0)
        c.set_source(r)
        c.paint()
    elif name == "paint with alpha + clip":
        c.rectangle(50, 40, 300, 200)
        c.clip()
        c.set_source_rgb(0.1, 0.6, 0.9)
        c.paint_with_alpha(0.35)
        c.reset_clip()
        c.arc(400, 300, 60, 0, 2 * math.pi)
        c.clip()
        c.set_source_rgba(1, 1, 0, 0.7)
        c.paint()
    elif name == "image mask":
        ms = cairo.ImageSurface(cairo.FORMAT_A8, 64, 64)
        mc = cairo.Context(ms)
        mc.arc(32, 32, 30, 0, 2 * math.pi)
        mc.fill()
        ms.flush()
        c.set_source_rgb(1, 0, 1)
        c.mask_surface(ms, 100, 80)
    elif name == "flush, numpy write, more drawing":
        c.set_source_rgb(1, 1, 1)
        c.rectangle(20, 20, 200, 200)
        c.fill()
        cairo._flush_all()
        a[100:110, :, :] = (0, 0, 255, 255)        # what manim does with images
        c.set_source_rgba(0, 1, 0, 0.5)
        c.rectangle(100, 50, 300, 200)
        c.fill()
    elif name == "aliased draws between":
        c.set_source_rgb(1, 0.5, 0)
        c.arc(200, 200, 80, 0, 2 * math.pi)
        c.fill()
        c.set_antialias(cairo.ANTIALIAS_NONE)
        c.set_source_rgb(0, 0, 1)
        c.rectangle(150.3, 150.6, 100, 30)
        c.fill()
        c.set_antialias(cairo.ANTIALIAS_DEFAULT)
        c.set_source_rgba(0, 1, 0, 0.6)
        c.arc(260, 220, 70, 0, 2 * math.pi)
        c.fill()
    elif name == "operator switch mid frame":
        c.set_source_rgb(1, 1, 1)
        c.rectangle(30, 30, 300, 200)
        c.fill()
        c.set_operator(cairo.OPERATOR_DEST_OUT)
        c.set_source_rgba(0, 0, 0, 1)
        c.rectangle(80, 60, 100, 100)
        c.fill()
        c.set_operator(cairo.OPERATOR_OVER)
        c.set_source_rgba(1, 0, 0, 0.5)
        c.rectangle(150, 90, 150, 120)
        c.fill()
    cairo._flush_all()
    del c, s


BACKGROUNDS = {
    "black": lambda a: a.__setitem__(slice(None), (0, 0, 0, 255)),
    "noise": lambda a: a.__setitem__(slice(None), NOISE),
    "half alpha": lambda a: a.__setitem__(slice(None), (30, 20, 10, 128)),
    "transparent": lambda a: a.__setitem__(slice(None), 0),
}
SCENES = ["opaque shapes", "translucent stack", "strokes", "gradients",
          "paint with alpha + clip", "image mask", "flush, numpy write, more drawing",
          "aliased draws between", "operator switch mid frame"]


def render(scene, bg, layer):
    cairo._set_layer_frames(layer)
    a = np.empty((H, W, 4), np.uint8)
    BACKGROUNDS[bg](a)
    draw_scene(scene, a)
    return a.astype(int)


print("== layer frames give the pixels of whole-frame loads ==")
for scene in SCENES:
    for bg in BACKGROUNDS:
        old = render(scene, bg, 0)
        new = render(scene, bg, 1)
        d = np.abs(old - new)
        if scene == "operator switch mid frame":
            # the layer is composited before DEST_OUT; shape edges may round
            # differently (per pixel, not per sample)
            ok = (d.max(axis=2) > 1).mean() < 0.01
        elif scene in ("translucent stack", "gradients") and bg in ("noise", "half alpha"):
            # translucency over a background: each path rounds to 8 bits after
            # every draw, on different values (layer vs frame); their accuracy
            # is checked against the exact result below
            ok = d.max() <= 6 and d.mean() <= 0.5
        else:
            ok = d.max() <= 1
        check(f"{scene} on {bg}", ok,
              f"max {d.max()}, {100 * (d.max(axis=2) > 1).mean():.3f}% px off by more than 1")
cairo._set_layer_frames(1)

print("== translucent layers: as close to the exact result as whole-frame loads ==")
for bg in ("noise", "half alpha"):
    a = np.empty((H, W, 4), np.uint8)
    BACKGROUNDS[bg](a)
    exact = a.astype(float) / 255
    for i in range(30):          # the "translucent stack" scene, in floats
        y0, x0 = 10 + 5 * i, 10 + 7 * i
        src = np.array([0.1 * (i % 10), 0.4, 1.0, 1.0]) * 0.15      # B,G,R,A premultiplied
        exact[y0:y0 + 150, x0:x0 + 200] = src + exact[y0:y0 + 150, x0:x0 + 200] * 0.85
    exact *= 255
    inner = np.zeros((H, W), bool)
    inner[12:380, 12:500] = True           # away from the rectangles' edges
    e_old = np.abs(render("translucent stack", bg, 0) - exact)[inner].mean()
    e_new = np.abs(render("translucent stack", bg, 1) - exact)[inner].mean()
    check(f"on {bg}: mean error {e_new:.3f} (whole-frame load {e_old:.3f})", e_new <= e_old + 0.05)
cairo._set_layer_frames(1)

print("== a layer frame draws where asked and nowhere else ==")
a = np.empty((H, W, 4), np.uint8)
a[:] = NOISE
before = a.copy()
s = cairo.ImageSurface.create_for_data(a.data, cairo.FORMAT_ARGB32, W, H)
c = cairo.Context(s)
c.set_source_rgb(0, 1, 0)
c.rectangle(100, 100, 50, 40)
c.fill()
cairo._flush_all()
check("inside the rectangle: the source colour", tuple(a[120, 120]) == (0, 255, 0, 255), str(a[120, 120]))
outside = np.ones((H, W), bool)
outside[99:141, 99:151] = False
check("outside it: every pixel untouched", np.array_equal(a[outside], before[outside]))
check("odd-size frame edges (last row/column) untouched",
      np.array_equal(a[-1], before[-1]) and np.array_equal(a[:, -1], before[:, -1]))
c.set_source_rgb(1, 0, 0)
c.rectangle(W - 10, H - 10, 10, 10)
c.fill()
cairo._flush_all()
check("drawing reaches the last row and column", tuple(a[H - 1, W - 1]) == (0, 0, 255, 255), str(a[H - 1, W - 1]))
del c, s

print("== GPU wraps are kept with their arrays ==")
big_w, big_h = 2048, 1536          # page-aligned allocation: zero-copy
arr = np.zeros((big_h, big_w, 4), np.uint8)
for k in range(3):
    s = cairo.ImageSurface.create_for_data(arr.data, cairo.FORMAT_ARGB32, big_w, big_h)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.rectangle(10 * k, 10, 5, 5)
    c.fill()
    cairo._flush_all()
    del c, s
check("three surfaces in turn over one array all draw into it",
      all(arr[12, 10 * k + 2, 0] == 255 for k in range(3)))
other = np.zeros_like(arr)
s = cairo.ImageSurface.create_for_data(other.data, cairo.FORMAT_ARGB32, big_w, big_h)
c = cairo.Context(s)
c.set_source_rgb(1, 1, 1)
c.rectangle(0, 0, 4, 4)
c.fill()
cairo._flush_all()
del c, s
check("a second array gets its own wrap (draws land in it, not the first)",
      other[1, 1, 0] == 255 and arr[1, 1, 0] == 0)


def footprint_mb():
    import ctypes
    libc = ctypes.CDLL(None)
    buf = (ctypes.c_uint8 * 4096)()
    cnt = ctypes.c_uint32(4096 // 4)
    if libc.task_info(libc.mach_task_self(), 22, buf, ctypes.byref(cnt)) != 0:
        return None
    return int.from_bytes(bytes(buf[144:152]), "little") / 2**20


del arr, other
gc.collect()
f0 = footprint_mb()
for k in range(12):
    a = np.zeros((big_h, big_w, 4), np.uint8)
    s = cairo.ImageSurface.create_for_data(a.data, cairo.FORMAT_ARGB32, big_w, big_h)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.paint()
    cairo._flush_all()
    del c, s, a
    gc.collect()
f1 = footprint_mb()
if f0 is not None and f1 is not None:
    check("arrays freed one after another: memory does not grow (wraps dropped)",
          f1 - f0 < 64, f"{f1 - f0:+.0f} MB after 12 arrays of 12 MB")

print()
print(f"TOTAL: {PASS + FAIL}   PASS: {PASS}   FAIL: {FAIL}")
sys.exit(1 if FAIL else 0)
