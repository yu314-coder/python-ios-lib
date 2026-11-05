"""
manim_speed_test.py — the per-frame speed-ups give the same frames, in the
same style as manim_image_test.py.

Run from the in-app shell:

    python manim_speed_test.py          # under a minute

What changed, and what has to hold for each:

  1. Camera.set_cairo_context_path builds each path from plain floats
     instead of NumPy scalars, one curve at a time: cairo must get exactly
     the calls and numbers it got before.
  2. Mobject.get_family walks the family once instead of recursing with a
     dedupe at every level: the same list, in the same order, for families
     with shared members.
  3. Camera.set_pixel_array copies the background into the frame once (it
     made a frame-sized temporary first): same bytes, same array (the cached
     cairo context draws into it).
  4. Mobject.__deepcopy__ hands immutable values over and lets glyph copies
     share the parsed SVG path: copies stay independent where it matters.
  5. ThreeDCamera.project_points works the perspective factor out once:
     same numbers.
  6. Images are resampled on worker threads and composited in order: the
     frame is the same with OFFLINAI_MANIM_IMAGE_THREADS=0.
"""
from __future__ import annotations

import copy
import itertools as it
import os
import random
import time

PASSED = 0
FAILED = 0


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}  {detail}")


try:
    import numpy as np
    from manim import (DEGREES, LEFT, RIGHT, UP, Annulus, Arc, Axes, Circle,
                       DashedLine, Dot, ImageMobject, Mobject, NumberPlane,
                       ParametricFunction, Square, Star, Text, VGroup,
                       VMobject, tempconfig)
    from manim.camera import camera as camera_module
    from manim.camera.camera import Camera
    from manim.camera.three_d_camera import ThreeDCamera
    from manim.utils.iterables import remove_list_redundancies
except Exception as exc:                                   # pragma: no cover
    print(f"  FAIL  import manim  {type(exc).__name__}: {exc}")
    raise SystemExit(1)


class Recorder:
    """A cairo context that writes down what it is asked to do."""

    def __init__(self):
        self.calls = []

    def __getattr__(self, name):
        def call(*args):
            self.calls.append((name, tuple(float(a) for a in args)))
        return call


def old_path(cam, ctx, vmobject):
    """set_cairo_context_path as it was."""
    points = cam.transform_points_pre_display(vmobject, vmobject.points)
    if len(points) == 0:
        return
    ctx.new_path()
    for subpath in vmobject.gen_subpaths_from_points_2d(points):
        quads = vmobject.gen_cubic_bezier_tuples_from_points(subpath)
        ctx.new_sub_path()
        ctx.move_to(*subpath[0][:2])
        for _p0, p1, p2, p3 in quads:
            ctx.curve_to(*p1[:2], *p2[:2], *p3[:2])
        if vmobject.consider_points_equals_2d(subpath[0], subpath[-1]):
            ctx.close_path()


def old_family(mob):
    """Mobject.get_family as it was."""
    subs = [old_family(x) for x in mob.submobjects]
    return remove_list_redundancies([mob] + list(it.chain(*subs)))


with tempconfig({"verbosity": "WARNING"}):
    print("1. cairo paths")
    cam = Camera()
    rng = np.random.default_rng(3)
    shapes = [Text("Speed, same frames.", font_size=40), Circle(), Square(), Annulus(),
              DashedLine(LEFT, RIGHT), Axes(), NumberPlane(), Arc(angle=4), Star(),
              ParametricFunction(lambda t: [np.cos(3 * t), np.sin(5 * t), 0], t_range=[0, 6.3]),
              VGroup(*[Dot(rng.normal(size=3)) for _ in range(40)])]
    gap = VMobject()  # anchors just inside and just outside the tolerance
    gap.set_points(np.array([[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 2, 0], [2 + 5e-7, 2, 0],
                             [3, 2, 0], [3, 3, 0], [0, 9e-7, 0], [0, 0, 0], [1, 1, 0],
                             [2, 1, 0], [3, 3 + 3e-6, 0]], float))
    shapes.append(gap)
    long = VMobject()
    long.set_points(rng.normal(size=(4000, 3)))
    shapes.append(long)
    same = total = 0
    for shape in shapes:
        for vm in shape.family_members_with_points():
            a, b = Recorder(), Recorder()
            old_path(cam, a, vm)
            cam.set_cairo_context_path(b, vm)
            total += 1
            same += a.calls == b.calls
    check(f"cairo gets the same calls for {total} paths", same == total, f"{same}/{total}")
    t0 = time.perf_counter()
    for _ in range(3):
        for vm in long.family_members_with_points():
            old_path(cam, Recorder(), vm)
    t_old = time.perf_counter() - t0
    t0 = time.perf_counter()
    for _ in range(3):
        for vm in long.family_members_with_points():
            cam.set_cairo_context_path(Recorder(), vm)
    t_new = time.perf_counter() - t0
    print(f"        a 1000-curve path: {t_old / 3 * 1000:.1f} ms -> {t_new / 3 * 1000:.1f} ms")

    print("2. families")
    rnd = random.Random(1)
    ok = 0
    for _ in range(200):
        nodes = [Mobject() for _ in range(rnd.randint(1, 40))]
        for i, node in enumerate(nodes):
            later = nodes[i + 1:]
            if later:
                node.submobjects = [rnd.choice(later) for _ in range(rnd.randint(0, 4))]
        ok += all(old_family(n) == n.get_family() for n in nodes)
    check("200 random families with shared members come out the same", ok == 200, f"{ok}/200")
    scene_like = VGroup(*shapes)
    check("a scene's family comes out the same", old_family(scene_like) == scene_like.get_family())

    print("3. frame reset")
    cam = Camera()
    frame = cam.pixel_array
    cam.background = rng.integers(0, 256, size=frame.shape, dtype=frame.dtype)
    cam.reset()
    check("reset copies the background into the same frame array",
          cam.pixel_array is frame and np.array_equal(frame, cam.background))

    print("4. copies")
    text = Text("Copy me", font_size=40)
    dup = text.copy()
    glyph, glyph2 = text.submobjects[0], dup.submobjects[0]
    check("a copied glyph shares the parsed SVG path", glyph.path_obj is glyph2.path_obj)
    glyph2.shift(UP)
    check("…but not its points", not np.allclose(glyph.points, glyph2.points))
    check("…nor its colour arrays", glyph.fill_rgbas is not glyph2.fill_rgbas)
    t0 = time.perf_counter()
    for _ in range(20):
        text.copy()
    print(f"        copying a 7-letter Text: {(time.perf_counter() - t0) / 20 * 1000:.2f} ms")

    print("5. 3D projection")
    tcam = ThreeDCamera()
    tcam.set_phi(70 * DEGREES)
    tcam.set_theta(-30 * DEGREES)
    pts = rng.normal(size=(500, 3)) * 3
    # project_points as it was
    p = pts - tcam.frame_center
    p = np.dot(p, tcam.get_rotation_matrix().T)
    zs = p[:, 2]
    for i in 0, 1:
        d = tcam.get_focal_distance()
        if tcam.exponential_projection:
            f = np.exp(zs / d)
            lt0 = zs < 0
            f[lt0] = d / (d - zs[lt0])
        else:
            f = d / (d - zs)
            f[(d - zs) < 0] = 10**6
        p[:, i] *= f * tcam.get_zoom()
    check("project_points gives the same numbers", np.array_equal(p, tcam.project_points(pts)))

    print("6. images on worker threads")
    images = []
    for i in range(48):
        a = rng.integers(0, 256, size=(48, 40, 4), dtype=np.uint8)
        im = ImageMobject(a).scale(0.6).move_to([(i % 8) - 3.5, (i // 8) - 2.5, 0])
        if i % 5 == 0:
            im.rotate(20 * DEGREES)
        images.append(im)

    def draw(threads):
        os.environ["OFFLINAI_MANIM_IMAGE_THREADS"] = str(threads)
        camera_module._image_pool_state.clear()
        with tempconfig({"pixel_width": 3840, "pixel_height": 2160}):
            c = Camera()
            c.pixel_array[:] = 30
            t0 = time.perf_counter()
            c.display_multiple_image_mobjects(images, c.pixel_array)
            return c.pixel_array.copy(), time.perf_counter() - t0

    one, t_one = draw(0)
    many, t_many = draw(4)
    os.environ.pop("OFFLINAI_MANIM_IMAGE_THREADS", None)
    camera_module._image_pool_state.clear()
    check("48 overlapping images at 4K: threads give the same frame", np.array_equal(one, many))
    print(f"        one by one {t_one * 1000:.0f} ms, on threads {t_many * 1000:.0f} ms")

print(f"{PASSED} passed, {FAILED} failed")
raise SystemExit(1 if FAILED else 0)
