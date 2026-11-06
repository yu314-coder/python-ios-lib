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
  7. The renderer hands each frame to the writer instead of copying it, and
     the next frame starts in a new array (Camera.release_frame): the same
     frames, and the cairo state carries over to the new array.
  8. One-colour rows of a read-only background are filled, not copied.
  9. The camera's family list is one walk over the scene, remove_list_
     redundancies runs in C, update walks the family without recursion,
     and interpolate_color writes interpolate() out: same lists, same order,
     same numbers.
 10. The movie writer converts each frame to the encoder's YUV on several
     cores before encode() (PyAV did it inside, on one): the encoder gets
     the bytes PyAV's own conversion gives, and only where that was checked.
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
    from manim import (BLUE, DEGREES, LEFT, RED, RIGHT, UP, YELLOW, Annulus, Arc, Axes, Circle,
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

    print("7. frames handed to the writer")
    from manim import Scene, FadeIn, Write, Create, Transform, Square as Sq, LineJointType
    from manim.renderer.cairo_renderer import CairoRenderer

    class Probe(Scene):
        def construct(self):
            a = Sq().set_stroke(width=30).set_joint_type(LineJointType.ROUND)
            b = Circle().shift(RIGHT)  # AUTO joint: draws with the context's join
            self.add(Text("static", font_size=30).to_edge(UP))
            self.play(Create(a), run_time=0.3)
            self.play(Transform(a, b), FadeIn(Star().shift(LEFT)), run_time=0.3)

    def frames_of(hand_off):
        got = []
        orig = CairoRenderer._frame_for_writer
        def take(self):
            frame = orig(self) if hand_off else self.get_frame()
            got.append(frame)
            return frame
        CairoRenderer._frame_for_writer = take
        try:
            with tempconfig({"write_to_movie": False, "frame_rate": 15, "pixel_width": 480,
                             "pixel_height": 270, "verbosity": "WARNING", "disable_caching": True, "progress_bar": "none"}):
                Probe().render()
        finally:
            CairoRenderer._frame_for_writer = orig
        return got

    copied, handed = frames_of(False), frames_of(True)
    check(f"{len(handed)} frames handed over are the frames copied before",
          len(copied) == len(handed) and all(np.array_equal(a, b) for a, b in zip(copied, handed)))
    check("…each one its own array", len({id(f) for f in handed}) == len(handed))
    cam = Camera()
    ctx = cam.get_cairo_context(cam.pixel_array)
    import cairo as _cairo
    ctx.set_line_join(_cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(_cairo.LINE_CAP_SQUARE)
    released = cam.release_frame()
    cam.reset()
    moved = cam.get_cairo_context(cam.pixel_array)
    check("after a hand-off the frame is a new array with the background",
          cam.pixel_array is not released and np.array_equal(cam.pixel_array, cam.background))
    check("…and its cairo context keeps the join, cap and matrix",
          moved.get_line_join() == _cairo.LINE_JOIN_ROUND
          and moved.get_line_cap() == _cairo.LINE_CAP_SQUARE
          and tuple(moved.get_matrix()) == tuple(ctx.get_matrix()))

    print("8. one-colour rows filled")
    ok = 0
    for trial in range(40):
        h, w = rng.integers(1, 200), rng.integers(1, 120)
        bg = np.empty((h, w, 4), np.uint8)
        bg[:] = rng.integers(0, 256, 4, dtype=np.uint8)
        for _ in range(rng.integers(0, 4)):  # some rows with something drawn on them
            y0 = rng.integers(0, h); y1 = min(h, y0 + rng.integers(1, 40))
            x0 = rng.integers(0, w)
            bg[y0:y1, x0] = rng.integers(0, 256, 4, dtype=np.uint8)
        bg.flags.writeable = False
        c = Camera(pixel_height=h, pixel_width=w)
        c.pixel_array = np.full((h, w, 4), 7, np.uint8)
        c.set_pixel_array(bg)
        ok += np.array_equal(c.pixel_array, bg)
    check("40 read-only backgrounds with plain and drawn rows paint exactly", ok == 40, f"{ok}/40")

    print("9. families, updates, colours")
    from manim.utils.family import extract_mobject_family_members
    def old_extract(mobs, points):
        method = Mobject.family_members_with_points if points else Mobject.get_family
        return remove_list_redundancies(list(it.chain(*(method(m) for m in mobs))))
    def old_rlr(lst):
        out, used = [], set()
        for x in reversed(lst):
            if x not in used:
                out.append(x); used.add(x)
        out.reverse()
        return out
    ok = ok2 = 0
    for _ in range(200):
        nodes = [VMobject() if rnd.random() < 0.6 else Mobject() for _ in range(rnd.randint(1, 40))]
        for i, node in enumerate(nodes):
            later = nodes[i + 1:]
            if later:
                node.submobjects = [rnd.choice(later) for _ in range(rnd.randint(0, 4))]
            if isinstance(node, VMobject) and rnd.random() < 0.5:
                node.set_points_as_corners([LEFT, RIGHT, UP])
        roots = [rnd.choice(nodes) for _ in range(rnd.randint(1, 12))]
        for pts in (False, True):
            ok += extract_mobject_family_members(roots, only_those_with_points=pts) == old_extract(roots, pts)
        seq = [rnd.choice(nodes) for _ in range(rnd.randint(0, 60))]
        ok2 += remove_list_redundancies(seq) == old_rlr(seq)
    check("400 scene family lists come out the same", ok == 400, f"{ok}/400")
    check("200 de-duplicated lists come out the same", ok2 == 200, f"{ok2}/200")

    def old_update(mob, dt, log):
        if not mob.updating_suspended:
            for u in mob.updaters:
                u(mob, dt)
        for sub in mob.submobjects:
            old_update(sub, dt, log)
    ok = 0
    for _ in range(100):
        nodes = [Mobject() for _ in range(rnd.randint(1, 30))]
        for i, node in enumerate(nodes):
            later = nodes[i + 1:]
            if later:
                node.submobjects = [rnd.choice(later) for _ in range(rnd.randint(0, 3))]
        logs = ([], [])
        which = [0]
        for n, node in enumerate(nodes):
            if rnd.random() < 0.4:
                node.add_updater(lambda m, dt, n=n: logs[which[0]].append(n))
            if rnd.random() < 0.1:
                node.suspend_updating(recursive=False)
        old_update(nodes[0], 0.1, None)
        which[0] = 1
        nodes[0].update(0.1)
        ok += logs[0] == logs[1]
    check("100 families run their updaters in the same order", ok == 100, f"{ok}/100")

    ok = 0
    from manim.utils.bezier import interpolate as _interp
    for _ in range(100):
        a, b = Square().set_fill(BLUE, 0.3), Circle().set_stroke(RED, 7).set_fill(YELLOW, 0.9)
        b.set_sheen(0.4, UP)
        alpha = float(rng.random()) if _ else 1.0
        target = VMobject()
        target.interpolate_color(a, b, alpha)
        same = True
        for attr in ("fill_rgbas", "stroke_rgbas", "background_stroke_rgbas", "stroke_width",
                     "background_stroke_width", "sheen_direction", "sheen_factor"):
            want = getattr(b, attr) if alpha == 1.0 else _interp(getattr(a, attr), getattr(b, attr), alpha)
            same &= bool(np.array_equal(getattr(target, attr), want))
        ok += same
    check("interpolate_color gives interpolate()'s numbers", ok == 100, f"{ok}/100")

print("10. frames converted for the encoder on several cores")
import av
from manim.scene import scene_file_writer as sfw


class FakeStream:
    """Stands in for a VideoToolbox stream: keeps what encode() is given."""

    def __init__(self, w, h, pix_fmt):
        self.width, self.height, self.pix_fmt = w, h, pix_fmt
        self.got = []

    def encode(self, frame=None):
        self.got.append(frame)
        return []


swscale = tuple(av.library_versions["libswscale"])[:2]
checked = swscale >= sfw._THREADED_CONVERT_SWSCALE
ok = total = 0
for (h, w) in ((4320, 7680), (1080, 1920), (720, 1280)):
    for fmt in ("yuv420p", "nv12"):
        stream = FakeStream(w, h, fmt)
        wrapped = sfw._with_threaded_convert(stream)
        if not checked:
            total += 1
            ok += wrapped is stream  # left to PyAV on a swscale not checked
            continue
        a = rng.integers(0, 256, size=(h, w, 4), dtype=np.uint8)
        a[: h // 3] = (20, 30, 40, 255)
        frame = av.VideoFrame.from_ndarray(a, format="rgba")
        wrapped.encode(frame)
        want = [bytes(p) for p in frame.reformat(w, h, fmt, threads=1).planes]
        got = stream.got[-1]
        total += 1
        ok += (wrapped is not stream and got.format.name == fmt
               and [bytes(p) for p in got.planes] == want)
if checked:
    check(f"{total} frames reach the encoder as PyAV's own conversion makes them "
          f"(libswscale {swscale})", ok == total, f"{ok}/{total}")
else:
    check(f"libswscale {swscale} is not the checked one: PyAV converts as before",
          ok == total, f"{ok}/{total}")
odd = FakeStream(853, 481, "yuv420p")
check("odd sizes and other formats keep PyAV's conversion",
      sfw._with_threaded_convert(odd) is odd
      and sfw._with_threaded_convert(FakeStream(1920, 1080, "argb")).pix_fmt == "argb"
      and not isinstance(sfw._with_threaded_convert(FakeStream(1920, 1080, "argb")),
                         sfw._ConvertingVideoStream))
s2 = FakeStream(1920, 1080, "yuv420p")
w2 = sfw._ConvertingVideoStream(s2, 4)
w2.encode(None)
w2.codec_tag = "hvc1"
check("…flushing passes None through, and settings reach the stream",
      s2.got == [None] and s2.codec_tag == "hvc1" and w2.width == 1920)

print(f"{PASSED} passed, {FAILED} failed")
raise SystemExit(1 if FAILED else 0)
