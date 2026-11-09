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
 11. A GPU cairo (CairoMetal) draws when flushed: the camera flushes before
     writing images into the frame itself and when the frame is done.
 12. A wait() is written as its first and last frame, the first lasting
     until the second: the movie is as long and shows the same picture at
     every moment, with fewer frames; a GIF keeps every frame.
 13. PyAV's from_ndarray (rebuilt for the app) copies the array once without
     the GIL: the planes hold the array's bytes, and in the app another
     thread keeps running during an 8K copy.
 14. Frames the writer is done with go back to the camera to draw in again
     while the stream caps the frames VideoToolbox holds (python-ios-lib's
     FFmpeg: max_pending_frames; without it frames would pile up in the
     encoder) and the frame is within the frame queue's budget (up to 8K):
     only frames the camera handed out and nothing else holds; the encoder
     gets the same frames on and off. In the app, the bundled FFmpeg has
     the option.
"""
from __future__ import annotations

import copy
import itertools as it
import os
import random
import shutil
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
    try:
        import cairo_metal as _cm
    except Exception:
        _cm = None
    if _cm is None or not hasattr(_cm.Context, "_append_cubic_curves"):
        print("        (CairoMetal not here: its one-call paths are checked in the app)")
    else:
        # CairoMetal builds the path in one call (Context._append_cubic_curves);
        # the same calls made one by one must give the same path.
        _surf = _cm.ImageSurface(_cm.FORMAT_ARGB32, 64, 64)
        _one, _each = _cm.Context(_surf), _cm.Context(_surf)
        same = total = 0
        for shape in shapes:
            for vm in shape.family_members_with_points():
                _one.new_path()
                cam.set_cairo_context_path(_one, vm)
                rec = Recorder()
                old_path(cam, rec, vm)
                _each.new_path()
                for name, args in rec.calls:
                    getattr(_each, name)(*args)
                total += 1
                same += list(_one.copy_path()) == list(_each.copy_path())
        check(f"CairoMetal's one-call paths are the paths made call by call ({total} paths)",
              same == total, f"{same}/{total}")
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
        # manim 0.22.1's recursive update: a suspended mobject updates
        # neither itself nor its family (0.20 still updated the family).
        if mob.updating_suspended:
            return
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
        wrapped = sfw._writer_stream(stream)
        if not checked:
            total += 1
            ok += wrapped._threads == 1  # left to PyAV on a swscale not checked
            continue
        a = rng.integers(0, 256, size=(h, w, 4), dtype=np.uint8)
        a[: h // 3] = (20, 30, 40, 255)
        frame = av.VideoFrame.from_ndarray(a, format="rgba")
        wrapped.encode(frame)
        want = [bytes(p) for p in frame.reformat(w, h, fmt, threads=1).planes]
        got = stream.got[-1]
        total += 1
        ok += (wrapped._threads > 1 and got.format.name == fmt
               and [bytes(p) for p in got.planes] == want)
if checked:
    check(f"{total} frames reach the encoder as PyAV's own conversion makes them "
          f"(libswscale {swscale})", ok == total, f"{ok}/{total}")
else:
    check(f"libswscale {swscale} is not the checked one: PyAV converts as before",
          ok == total, f"{ok}/{total}")
odd = FakeStream(853, 481, "yuv420p")
check("odd sizes and other formats keep PyAV's conversion",
      sfw._writer_stream(odd)._threads == 1
      and sfw._writer_stream(FakeStream(1920, 1080, "argb"))._threads == 1
      and sfw._writer_stream(FakeStream(1920, 1080, "argb")).pix_fmt == "argb")
s2 = FakeStream(1920, 1080, "yuv420p")
w2 = sfw._WriterStream(s2, 4)
w2.encode(None)
w2.codec_tag = "hvc1"
check("…flushing passes None through, and settings reach the stream",
      s2.got == [None] and s2.codec_tag == "hvc1" and w2.width == 1920)
s3 = FakeStream(64, 36, "yuv420p")
w3 = sfw._WriterStream(s3, 1)
for _ in range(2):
    w3.encode(av.VideoFrame(64, 36, "yuv420p"))
w3.hold(5)
w3.encode(av.VideoFrame(64, 36, "yuv420p"))
check("frames numbered 0, 1, then 7 after a hold of 5", [f.pts for f in s3.got] == [0, 1, 7],
      str([f.pts for f in s3.got]))

print("11. GPU cairo flushed before images and at the end of a frame")
import types
calls = []
real_cairo = camera_module.cairo
gpu_like = types.ModuleType("cairo")
gpu_like.__dict__.update(real_cairo.__dict__)
gpu_like._flush_all = lambda: calls.append("flush")
orig_images = Camera.display_multiple_image_mobjects
orig_vectors = Camera.display_multiple_non_background_colored_vmobjects

def images_seen(self, *a, **k):
    calls.append("images")
    return orig_images(self, *a, **k)

def vectors_seen(self, *a, **k):
    calls.append("vectors")
    return orig_vectors(self, *a, **k)

camera_module.cairo = gpu_like
Camera.display_multiple_image_mobjects = images_seen
Camera.display_multiple_non_background_colored_vmobjects = vectors_seen
try:
    c = Camera()
    c.capture_mobjects([Square(), ImageMobject(np.full((8, 8, 4), 200, np.uint8)), Circle()])
finally:
    camera_module.cairo = real_cairo
    Camera.display_multiple_image_mobjects = orig_images
    Camera.display_multiple_non_background_colored_vmobjects = orig_vectors
check("vectors, flush, images, vectors, flush", calls == ["vectors", "flush", "images", "vectors", "flush"],
      str(calls))
calls.clear()
c = Camera()
c.capture_mobjects([Square()])
check("…and pycairo, which has no flush, is never asked", calls == [], str(calls))

from manim import Create as _Create, Scene as _GScene
from manim.renderer.cairo_renderer import CairoRenderer as _CR


class _GpuProbe(_GScene):
    def construct(self):
        self.play(_Create(Square()), run_time=0.2)


_handed = []
_orig_ffw = _CR._frame_for_writer


def _record_hand_off(self):
    frame = _orig_ffw(self)
    _handed.append(frame is self.camera.pixel_array)
    return frame


_CR._frame_for_writer = _record_hand_off
camera_module.cairo = gpu_like
try:
    with tempconfig({"write_to_movie": False, "frame_rate": 15, "pixel_width": 320,
                     "pixel_height": 180, "verbosity": "WARNING", "disable_caching": True,
                     "progress_bar": "none"}):
        _GpuProbe().render()
finally:
    camera_module.cairo = real_cairo
    _CR._frame_for_writer = _orig_ffw
check(f"…and a GPU cairo's frames go to the writer as they are, flushed, not copied "
      f"({len(_handed)} frames)", bool(_handed) and all(_handed) and "flush" in calls)

print("12. wait() written as its first and last frame")
import sys as _sys
import tempfile as _tf
from manim import BLUE as _BLUE, FadeIn as _FadeIn, FadeOut as _FadeOut, Scene as _Scene
from manim.utils.ios_encoder import settings as _enc


class _Holds(_Scene):
    def construct(self):
        sq = Square().set_fill(_BLUE, 0.6)
        self.play(_FadeIn(sq), run_time=0.3)
        self.wait(0.7)
        self.play(sq.animate.shift(RIGHT), run_time=0.3)
        self.wait(0.4)
        self.play(_FadeOut(sq), run_time=0.2)
        self.wait(0.3)


class _AppTookTheRender(Exception):
    """An app's own render hook (CodeBench's editor: its quality settings,
    its output folder) moved the movie away."""


_made_dirs = []


def _render_holds(mode):
    _enc.hold_frames = mode
    media = _tf.mkdtemp(prefix="holds_")
    _made_dirs.append(media)
    with tempconfig({"media_dir": media, "pixel_width": 320, "pixel_height": 180,
                     "frame_rate": 30, "disable_caching": True, "verbosity": "WARNING",
                     "progress_bar": "none", "write_to_movie": True}):
        sc = _Holds()
        fw = sc.renderer.file_writer
        real = _sys.platform
        _sys.platform = "ios"  # the app's writer: VideoToolbox (a Mac has it too)
        try:
            sc.render()
        finally:
            _sys.platform = real
        path = fw.movie_file_path
        _render_holds.writer = fw
        _render_holds.clips = [str(c) for c in fw.partial_movie_files if c]
    if not os.path.exists(str(path)) or not all(os.path.exists(c) for c in _render_holds.clips):
        raise _AppTookTheRender
    with av.open(str(path)) as cont:
        st = cont.streams.video[0]
        shots = [(float(f.pts * f.time_base), f.to_ndarray(format="rgb24")[::4, ::4].astype(int))
                 for f in cont.decode(st)]
        dur = float(cont.duration / av.time_base)
    return shots, dur


def _on_screen(shots, t):
    best = None
    for ft, img in shots:
        if ft <= t + 1e-9:
            best = img
    return best


try:
    _was = _enc.hold_frames
    try:
        every, dur_every = _render_holds("every")
        once, dur_once = _render_holds("once")
    finally:
        _enc.hold_frames = _was
    check(f"as long either way ({dur_every:.3f} s / {dur_once:.3f} s)",
          abs(dur_every - 2.2) < 0.02 and abs(dur_once - dur_every) < 1e-6)
    check(f"with fewer frames ({len(every)} -> {len(once)})", len(once) < len(every) - 20)
    worst = max(int(np.abs(_on_screen(every, t) - _on_screen(once, t)).max())
                for t in np.arange(0.0, 2.2, 1 / 60))
    check(f"the same picture at every moment (worst {worst}/255, encoder noise)", worst <= 32)
    from manim import config as _cfg
    _fmt = _cfg.format
    try:
        _cfg.format = "gif"
        check("a GIF keeps every frame", not sfw._holds_written_once())
    finally:
        _cfg.format = _fmt


    # ManimStudio's encoder wrapper moves an animation to a new clip when iOS
    # takes the hardware encoder away (writer._ms_segments); if the clips then
    # differ in encoding, it joins them by decoding and numbering every frame.
    import shutil as _sh


    def _renumbering_join(paths):
        n = 0
        for pth in paths:
            with av.open(pth) as cont:
                n += sum(1 for _ in cont.decode(video=0))
        return n


    def _length(pth):
        with av.open(pth) as cont:
            return float(cont.duration / av.time_base)


    once_writer, once_clips = _render_holds.writer, _render_holds.clips
    work = _tf.mkdtemp(prefix="split_")
    _made_dirs.append(work)
    copies = []
    for c in once_clips:
        dst = os.path.join(work, os.path.basename(c))
        _sh.copy(c, dst)
        copies.append(dst)
    seg = os.path.join(work, "continued.mp4")  # a software clip continuing the first
    with av.open(copies[0]) as src, av.open(seg, "w") as dst:
        st = dst.add_stream("mpeg4", rate=30)
        st.width, st.height, st.pix_fmt = 320, 180, "yuv420p"
        for k, fr in enumerate(src.decode(video=0)):
            g = av.VideoFrame.from_ndarray(fr.to_ndarray(format="rgb24"), format="rgb24")
            g.pts = k
            for pk in st.encode(g):
                dst.mux(pk)
        for pk in st.encode():
            dst.mux(pk)
    held_copies = {os.path.join(work, os.path.basename(c)) for c in once_writer.__dict__.get("_held_clips", ())}
    fake = object.__new__(SceneFileWriter := type(once_writer))
    fake.__dict__["_held_clips"] = set(held_copies)
    paths = [p for c in copies for p in [c] + ([seg] if c == copies[0] else [])]
    frames_due = int(round(sum(_length(p) for p in paths) * 30))
    before = _renumbering_join(paths)
    fake._ms_segments = {copies[0]: [seg]}
    with tempconfig({"frame_rate": 30, "pixel_width": 320, "pixel_height": 180}):
        SceneFileWriter._fill_holds_before_reencoding(fake, copies)
    after = _renumbering_join(paths)
    check(f"a join that numbers frames keeps the holds' length once they are written out "
          f"({before} -> {after} of {frames_due} frames)",
          len(held_copies) == 3 and before < frames_due and after == frames_due)
    work2 = _tf.mkdtemp(prefix="split2_")
    _made_dirs.append(work2)
    fresh = []
    for c in once_clips:
        dst = os.path.join(work2, os.path.basename(c))
        _sh.copy(c, dst)
        fresh.append(dst)
    held2 = {os.path.join(work2, os.path.basename(c)) for c in once_writer.__dict__.get("_held_clips", ())}
    sizes = {c: os.path.getsize(c) for c in fresh}
    w2 = object.__new__(SceneFileWriter)
    w2.__dict__["_held_clips"] = set(held2)
    w2._ms_segments = {fresh[1]: []}  # a split, but no clip in another encoding
    same = len({sfw._clip_encoding(c) for c in fresh}) == 1
    with tempconfig({"frame_rate": 30, "pixel_width": 320, "pixel_height": 180}):
        SceneFileWriter._fill_holds_before_reencoding(w2, fresh)
    untouched = w2.__dict__["_held_clips"] == held2 and all(os.path.getsize(c) == sizes[c] for c in fresh)
    check("…and only then: clips that join packet for packet are left as they are"
          + ("" if same else " (these encoder sessions differ, so they were written out)"),
          untouched == same)


    class _Ctx:
        def __init__(self, name):
            self.codec_context = type("C", (), {"name": name})()


    check("…and so does an encoder that reorders frames (libx264)",
          not sfw._holds_written_once(_Ctx("libx264"))
          and sfw._holds_written_once(_Ctx("hevc_videotoolbox")))

except _AppTookTheRender:
    print("        (the app's render hook moved this scene's movie: checked by rendering"
          " through manim's own writer, as manim_writer_test.py does)")

for _d in _made_dirs:
    shutil.rmtree(_d, ignore_errors=True)

print("13. from_ndarray: one copy, without the GIL")
import threading
ok = total = 0
for (h, w) in ((7, 9), (480, 854), (1080, 1920)):
    for fmt, ch in (("rgba", 4), ("rgb24", 3), ("gray", None)):
        shape = (h, w) if ch is None else (h, w, ch)
        a = rng.integers(0, 256, size=shape, dtype=np.uint8)
        for x in (a, np.asfortranarray(a)):
            f = av.VideoFrame.from_ndarray(x, format=fmt)
            p = f.planes[0]
            bpp = 1 if ch is None else ch
            rows = np.frombuffer(p, np.uint8).reshape(p.height, p.line_size)[:, : p.width * bpp]
            total += 1
            ok += rows.tobytes() == x.tobytes(order="C")
check(f"{total} frames hold exactly the array's bytes", ok == total, f"{ok}/{total}")
big = np.zeros((4320, 7680, 4), np.uint8)
count = [0]
stop = threading.Event()


def _spin():
    while not stop.is_set():
        count[0] += 1


th = threading.Thread(target=_spin)
th.start()
time.sleep(0.05)
c0 = count[0]; t0 = time.perf_counter()
for _ in range(5):
    av.VideoFrame.from_ndarray(big, format="rgba")
during = (count[0] - c0) / (time.perf_counter() - t0)
c0 = count[0]; t0 = time.perf_counter()
time.sleep(0.3)
free = (count[0] - c0) / (time.perf_counter() - t0)
stop.set(); th.join()
ratio = during / max(free, 1)
if _sys.platform == "ios":
    check(f"another thread runs during an 8K copy ({ratio:.0%} of its free speed)", ratio > 0.4)
else:
    print(f"        (this PyAV is not the app's: another thread ran at {ratio:.0%} during an 8K copy)")

print("14. frames drawn again in once the writer is done with them")
from manim.camera import camera as _cm
from manim.scene.scene_file_writer import SceneFileWriter
_pool_env = os.environ.pop("OFFLINAI_MANIM_FRAME_POOL", None)


class _Capped:
    _capped = True


def _given_back(stream):
    f = np.zeros((6, 8, 4), np.uint8)
    _cm._frame_pool.handed_out(f)
    ok = sfw._return_frame(f, stream)
    _cm._frame_pool.clear()
    return ok


check("frames go back only while VideoToolbox is capped (memory as before otherwise)",
      _given_back(_Capped()) and not _given_back(None) and not _given_back(FakeStream(4, 4, "yuv420p")))
_big = np.zeros(sfw._pool_budget_bytes() // 4 + 16, np.uint32)  # a frame past the queue budget (12K, 14K)
_cm._frame_pool.handed_out(_big)
check("…and only frames within the frame queue's budget (up to 8K)", not sfw._return_frame(_big, _Capped()))
del _big
_cm._frame_pool.clear()
os.environ["OFFLINAI_MANIM_FRAME_POOL"] = "0"
check("…OFFLINAI_MANIM_FRAME_POOL=0 never gives frames back", not _given_back(_Capped()))
caps = sfw._caps_pending_frames("hevc_videotoolbox")
if _sys.platform == "ios":
    check("the app's FFmpeg caps the frames VideoToolbox holds (max_pending_frames)", caps)
else:
    print(f"        (this FFmpeg {'has' if caps else 'does not have'} max_pending_frames)")
os.environ["OFFLINAI_MANIM_FRAME_POOL"] = "1"
pool = _cm._FramePool()
a = np.zeros((6, 8, 4), np.uint8)
pool.handed_out(a)
check("a frame the camera handed out comes back to it", pool.give_back(a) and pool.take(a.shape, a.dtype) is a)
b = np.zeros((6, 8, 4), np.uint8)
check("…an array it never handed out does not", not pool.give_back(b))
frames = [np.zeros((6, 8, 4), np.uint8) for _ in range(4)]
for f in frames:
    pool.handed_out(f)
    pool.give_back(f)
check(f"…at most {pool.MAX} wait", len(pool) == pool.MAX)
check("…none of another size is taken", pool.take((5, 8, 4), np.dtype(np.uint8)) is None)
pool.clear()
check("…and clearing empties it", len(pool) == 0)


def _writer_returns(extra_holder):
    frame_data = np.zeros((6, 8, 4), np.uint8)
    _cm._frame_pool.handed_out(frame_data)
    keep = [frame_data] if extra_holder else None  # noqa: F841
    return sfw._return_frame(frame_data)


check("the writer gives back a frame nothing else holds", _writer_returns(False))
check("…but not one a hook kept", not _writer_returns(True))
_cm._frame_pool.clear()


def _encoded_hashes(pool_on):
    import hashlib
    got = []
    real = SceneFileWriter.encode_and_write_frame

    def hashing(self, frame, num_frames):
        got.append(hashlib.blake2b(np.ascontiguousarray(frame).tobytes(), digest_size=12).hexdigest())
        return real(self, frame, num_frames)

    os.environ["OFFLINAI_MANIM_FRAME_POOL"] = "1" if pool_on else "0"
    SceneFileWriter.encode_and_write_frame = hashing
    media = _tf.mkdtemp(prefix="pool_")
    try:
        with tempconfig({"media_dir": media, "pixel_width": 320, "pixel_height": 180,
                         "frame_rate": 30, "disable_caching": True, "verbosity": "WARNING",
                         "progress_bar": "none", "write_to_movie": True}):
            sc = _Holds()
            real_platform = _sys.platform
            _sys.platform = "ios"
            try:
                sc.render()
            finally:
                _sys.platform = real_platform
    finally:
        SceneFileWriter.encode_and_write_frame = real
        os.environ.pop("OFFLINAI_MANIM_FRAME_POOL", None)
        shutil.rmtree(media, ignore_errors=True)
    return got


off, on = _encoded_hashes(False), _encoded_hashes(True)
check(f"the encoder gets the same {len(on)} frames with the pool on and off", on and on == off,
      f"{len(on)} vs {len(off)}")
if _pool_env is None:
    os.environ.pop("OFFLINAI_MANIM_FRAME_POOL", None)
else:
    os.environ["OFFLINAI_MANIM_FRAME_POOL"] = _pool_env

print(f"{PASSED} passed, {FAILED} failed")
raise SystemExit(1 if FAILED else 0)
