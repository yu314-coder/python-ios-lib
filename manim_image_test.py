"""
manim_image_test.py — drawing ImageMobjects, in the same style as
manim_writer_test.py.

Run from the in-app shell:

    python manim_image_test.py          # under a minute

Why this exists. Every MathTex in ManimStudio is typeset by BusyTeX into a
PNG, so each number in a matrix is an ImageMobject. Camera.display_image_mobject
used to paste each one into a transparent image the size of the frame and
alpha-composite the whole frame, so an image cost as much as the frame: about
95 ms at 7680x4320, and 33-40 s a frame for a 20x16 matrix on an iPad. It now
composites only the image's own box. Two things have to hold:

  1. The frame is pixel-identical to the full-frame way, for opaque,
     see-through, rotated, perspective (ThreeDScene), fixed-in-frame, partly
     and wholly off-frame, tiny and edge-on images, over a frame that already
     has content, including a see-through background.
  2. 320 BusyTeX-sized numbers at 7680x4320 draw in well under a second.
"""
from __future__ import annotations

import sys
import time
import zlib

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
    from PIL import Image
    from manim import (DEGREES, DOWN, DR, LEFT, OUT, RIGHT, UL, UP, UR, Circle,
                       ImageMobject, Square, tempconfig)
    from manim.camera.camera import Camera
    from manim.camera.three_d_camera import ThreeDCamera
except Exception as exc:                                   # pragma: no cover
    print(f"  FAIL  import manim  {type(exc).__name__}: {exc}")
    raise SystemExit(1)


def full_frame_composite(self, pixel_array, image, corner):
    """What display_image_mobject did before: paste into a transparent image
    the size of the frame, then composite the whole frame."""
    full = Image.new("RGBA", (pixel_array.shape[1], pixel_array.shape[0]), (0, 0, 0, 0))
    full.paste(image, box=(int(corner[0]), int(corner[1]),
                           int(corner[0]) + image.width, int(corner[1]) + image.height))
    self.overlay_PIL_image(pixel_array, full)


def picture(rng, h, w, alpha="mixed"):
    a = rng.integers(0, 256, size=(h, w, 4), dtype=np.uint8)
    if alpha == "opaque":
        a[..., 3] = 255
    elif alpha == "half":
        a[..., 3] = 128
    else:  # clear corners, a soft ramp, an opaque middle
        yy, xx = np.mgrid[0:h, 0:w]
        r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
        a[..., 3] = np.clip((1.2 - r) * 400, 0, 255).astype(np.uint8)
    return a


def number_png(text="255"):
    """A BusyTeX-shaped number: white glyph strokes on clear, 4x, 2 pt border."""
    from PIL import ImageDraw
    w, h = 22 * len(text) + 16, 48
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(len(text)):
        x = 8 + 22 * i
        d.ellipse((x, 8, x + 18, 40), outline=(255, 255, 255, 255), width=4)
    return np.array(im)


def img(arr, height=2.0):
    m = ImageMobject(arr)
    m.height = height
    return m


def under():
    return [Square(side_length=3, fill_opacity=0.6, color="#3399ff").shift(LEFT),
            Circle(radius=1.5, fill_opacity=1, color="#ff6633").shift(RIGHT + UP)]


def cases(rng):
    def resampling(cam):
        a = img(picture(rng, 8, 12), 3).rotate(10 * DEGREES)
        a.set_resampling_algorithm(Image.Resampling.NEAREST)
        b = img(picture(rng, 9, 9), 2).shift(LEFT * 3).rotate(-20 * DEGREES)
        b.set_resampling_algorithm(Image.Resampling.BILINEAR)
        return [a, b]

    def perspective(cam):
        cam.set_phi(65 * DEGREES)
        cam.set_theta(-40 * DEGREES)
        return [img(picture(rng, 60, 90), 3),
                img(picture(rng, 40, 40, "opaque"), 2).rotate(70 * DEGREES, axis=RIGHT)
                .shift(OUT + RIGHT * 2)]

    def fixed_in_frame(cam):
        cam.set_phi(70 * DEGREES)
        cam.set_theta(30 * DEGREES)
        f = img(picture(rng, 30, 50), 1.5).to_corner(UL)
        g = img(number_png(), 0.4).to_corner(DR)
        cam.add_fixed_in_frame_mobjects(f, g)
        return [img(picture(rng, 40, 40)).shift(DOWN), f, g]

    def partly_off(cam):
        return [img(picture(rng, 40, 60), 3).move_to(LEFT * 7.2 + UP * 3.9),
                img(picture(rng, 40, 60), 3).move_to(RIGHT * 7.4),
                img(picture(rng, 40, 60), 3).move_to(DOWN * 4.2).rotate(25 * DEGREES)]

    def matrix(cam):
        cam.set_phi(70 * DEGREES)
        mobs = []
        for r in range(20):
            for c in range(16):
                m = img(number_png(str((r * 16 + c) % 256)), 0.3)
                mobs.append(m.move_to(LEFT * 5.5 + RIGHT * c * 0.7 + UP * 3.4 + DOWN * r * 0.36))
        cam.add_fixed_in_frame_mobjects(*mobs)
        return mobs

    return {
        # name: (camera, mobjects drawn over under(), config, draws something)
        "opaque": ("2d", lambda cam: [img(picture(rng, 40, 60, "opaque"))], {}, True),
        "see-through": ("2d", lambda cam: [img(picture(rng, 40, 60, "half")),
                                           img(picture(rng, 30, 30)).set_opacity(0.4).shift(RIGHT)], {}, True),
        "rotated": ("2d", lambda cam: [img(picture(rng, 50, 80)).rotate(37 * DEGREES)], {}, True),
        "resampling": ("2d", resampling, {}, True),
        "perspective (ThreeDScene)": ("3d", perspective, {}, True),
        "fixed in frame (ThreeDScene)": ("3d", fixed_in_frame, {}, True),
        "partly off-frame": ("2d", partly_off, {}, True),
        "wholly off-frame": ("2d", lambda cam: [img(picture(rng, 40, 60)).move_to(RIGHT * 12),
                                                img(picture(rng, 40, 60)).move_to(UP * 9 + LEFT * 20)], {}, False),
        "tiny": ("2d", lambda cam: [img(picture(rng, 40, 60), 0.02),
                                    img(picture(rng, 40, 60), 0.004).shift(UR),
                                    img(picture(rng, 4, 4), 0.05).shift(LEFT * 2).rotate(45 * DEGREES)], {}, None),
        "edge-on (skipped)": ("2d", lambda cam: [img(picture(rng, 40, 60)).rotate(90 * DEGREES, axis=UP)], {}, False),
        "see-through background": ("2d", lambda cam: [img(picture(rng, 40, 60)),
                                                      img(picture(rng, 30, 30, "half")).shift(RIGHT)],
                                   {"background_opacity": 0.4}, True),
        "overlapping": ("2d", lambda cam: [img(picture(rng, 40, 60)).shift(RIGHT * 0.3 * i).rotate(i * 0.3)
                                           for i in range(6)], {}, True),
        "20x16 matrix (fixed in frame)": ("3d", matrix, {}, True),
    }


def draw(name, w, h, seed, full_frame=False, images=True):
    """The frame for one case: under() and then the case's images (or, with
    images=False, under() alone from the same camera)."""
    real = Camera._composite_onto
    if full_frame:
        Camera._composite_onto = full_frame_composite
    try:
        kind, setup, extra, _ = cases(np.random.default_rng(seed))[name]
        with tempconfig({"pixel_width": w, "pixel_height": h, **extra}):
            cam = ThreeDCamera() if kind == "3d" else Camera()
            mobs = setup(cam)
            cam.capture_mobjects(under() + (mobs if images else []))
            return cam.pixel_array.copy()
    finally:
        Camera._composite_onto = real


print("== every frame is pixel-identical to the full-frame way ==")
names = list(cases(np.random.default_rng(0)))
for w, h in ((160, 90), (853, 480), (1920, 1080)):
    for name in names:
        seed = zlib.crc32(name.encode()) + w
        new = draw(name, w, h, seed)
        old = draw(name, w, h, seed, full_frame=True)
        n = int(np.count_nonzero(np.any(new != old, axis=-1)))
        check(f"{name} at {w}x{h}", np.array_equal(new, old), f"{n} pixels differ")
        draws = cases(np.random.default_rng(0))[name][3]
        if draws is not None and w == 853:
            drew = not np.array_equal(new, draw(name, w, h, seed, images=False))
            check(f"{name}: {'it drew' if draws else 'nothing drawn'}", drew == draws)

print("\n== at 3840x2160 ==")
for name in ("perspective (ThreeDScene)", "partly off-frame", "20x16 matrix (fixed in frame)"):
    seed = zlib.crc32(name.encode())
    check(name, np.array_equal(draw(name, 3840, 2160, seed),
                               draw(name, 3840, 2160, seed, full_frame=True)))

print("\n== other overlay callers keep the full-frame composite ==")
with tempconfig({"pixel_width": 160, "pixel_height": 90}):
    cam = Camera()
    rng = np.random.default_rng(1)
    base = rng.integers(0, 256, size=(90, 160, 4), dtype=np.uint8)
    top = rng.integers(0, 256, size=(90, 160, 4), dtype=np.uint8)
    pa = base.copy()
    cam.overlay_rgba_array(pa, top)
    want = np.array(Image.alpha_composite(Image.fromarray(base, "RGBA"), Image.fromarray(top, "RGBA")))
    check("overlay_rgba_array composites the whole frame", np.array_equal(pa, want))

print("\n== a 20x16 BusyTeX matrix at 7680x4320 ==")
with tempconfig({"pixel_width": 7680, "pixel_height": 4320}):
    cam = ThreeDCamera()
    mobs = cases(np.random.default_rng(2))["20x16 matrix (fixed in frame)"][1](cam)
    widest = max(mobs, key=lambda m: m.width)
    corners = cam.points_to_subpixel_coords(widest, widest.points)
    size = corners.max(0) - corners.min(0)
    print(f"  a three-digit number covers {size[0]:.0f}x{size[1]:.0f} px, about what BusyTeX's"
          f" 255 does at font_size 24 (297x162)")
    t0 = time.perf_counter()
    cam.display_multiple_image_mobjects(mobs, cam.pixel_array)
    took = time.perf_counter() - t0
    print(f"  320 numbers: {took:.2f} s ({took / 320 * 1000:.2f} ms each)")
    check("320 numbers draw in well under a second", took < 1.5, f"{took:.2f} s")
    real = Camera._composite_onto
    Camera._composite_onto = full_frame_composite
    try:
        t0 = time.perf_counter()
        for m in mobs[:3]:
            cam.display_image_mobject(m, cam.pixel_array)
        before = (time.perf_counter() - t0) / 3
    finally:
        Camera._composite_onto = real
    print(f"  the full-frame way: {before * 1000:.0f} ms each ({before * 320:.1f} s for 320, "
          f"without the float64 frame it also allocated)")
    check("the box-only way is much faster", took / 320 < before / 10)

print()
print(f"{PASSED} passed, {FAILED} failed")
if FAILED:
    raise SystemExit(1)
