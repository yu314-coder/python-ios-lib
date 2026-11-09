"""
manim_regression_test.py — renders what moving the bundled manim to 0.22.1
fixed (2026-11-09), and the seams host apps patch, in the same style as
manim_writer_test.py.

Run from the in-app shell:

    python manim_regression_test.py

On a Mac it runs the same checks; the formula ones need `latex` and
`dvisvgm` on PATH (skipped otherwise), and also run manim's iOS LaTeX branch
against a stand-in `offlinai_latex` that compiles with them.

1. A `}}` inside a formula was taken for manim's `{{ }}` part syntax:
   MathTex(r"\\sum_{k\\ \\mathrm{odd}}^{N} ...") was cut at `\\mathrm{odd}}`, and
   everything after it stayed in the subscript, in roman type. 0.22's rule:
   `{{` opens a part only at the start of the string or after whitespace.
2. An always_redraw DashedLine of zero length (no dashes, no points) crashed
   the render: become() -> align_points -> get_nth_subpath indexed an empty
   list (IndexError). That was manim 0.20.0's own code; 0.22 pads it.
3. ManimStudio and CodeBench patch the writer as manim 0.20 shaped it:
   write_frame(frame, num_frames) positionally, encode_and_write_frame,
   video_stream / video_container / partial_movie_file_path / queue while a
   clip is open, writer.renderer.num_plays, and to_av_frame_rate in
   scene_file_writer.
4. A scene that raises mid-animation stops its clip's writer thread (the
   process used to wait for it at exit, for good) and drops the clip.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import threading
from fractions import Fraction
from pathlib import Path

PASSED = 0
FAILED = 0
SKIPPED = 0
ON_IOS = sys.platform.startswith("ios")


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}  {detail}")


def skip(label, why):
    global SKIPPED
    SKIPPED += 1
    print(f"  SKIP  {label} ({why})")


import av  # noqa: E402
import numpy as np  # noqa: E402
from manim import *  # noqa: E402,F403
from manim.scene import scene_file_writer as sfw  # noqa: E402
from manim.utils import tex_file_writing as tfw  # noqa: E402

print(f"manim {__import__('manim').__version__} from {__import__('manim').__file__}")

MEDIA = tempfile.mkdtemp(prefix="manim-regression-")
SMALL = {
    "media_dir": MEDIA,
    "pixel_width": 160,
    "pixel_height": 90,
    "frame_rate": 15,
    "disable_caching": True,
    "format": "mp4",
    "save_last_frame": False,
    "progress_bar": "none",
    "verbosity": "WARNING",
}


def frames_in(path):
    with av.open(str(path)) as container:
        return sum(1 for _ in container.decode(video=0))


LAST_WRITER = [None]


def render(scene_class, **extra):
    """Render at 160x90, 15 fps; (scene, movie path or None, error or None).

    The writer is taken before the render: a host app may let go of the
    scene's renderer once it has rendered (CodeBench does)."""
    with tempconfig({**SMALL, **extra}):
        scene = scene_class()
        writer = LAST_WRITER[0] = scene.renderer.file_writer
        try:
            scene.render()
        except BaseException as error:  # noqa: BLE001 - reported as a check
            return scene, None, error
        try:
            movie = writer.movie_file_path
        except AttributeError:
            movie = None
        return scene, movie, None


def movie_there(label, movie):
    """Whether the movie can be read; a skip, not a silent pass, if not."""
    if movie is not None and Path(movie).exists():
        return True
    skip(label, f"no movie at {movie} (a host app may have moved it)")
    return False


# ── 1. zero-length always_redraw ─────────────────────────────────────
print("\n== an always_redraw that reaches zero length renders ==")

dash_counts: list[int] = []


class ZeroDash(Scene):
    def construct(self):
        t = ValueTracker(0)
        p = always_redraw(lambda: Dot([np.cos(t.get_value()), np.sin(t.get_value()), 0]))

        def drop_line():
            line = DashedLine(p.get_center(), [p.get_x(), 0, 0], color=PINK)
            dash_counts.append(len(line.submobjects))
            return line

        drop = always_redraw(drop_line)
        self.add(p, drop)
        self.play(t.animate.set_value(PI), run_time=1)


class ZeroLine(Scene):
    def construct(self):
        t = ValueTracker(0)
        p = always_redraw(lambda: Dot([np.cos(t.get_value()), np.sin(t.get_value()), 0]))
        same = always_redraw(lambda: Line(p.get_center(), p.get_center(), color=RED))
        self.add(p, same)
        self.play(t.animate.set_value(PI), run_time=1)


class ZeroArc(Scene):
    def construct(self):
        t = ValueTracker(0)
        arc = always_redraw(lambda: Arc(radius=1.5, angle=t.get_value(), color=BLUE))
        self.add(arc)
        self.play(t.animate.set_value(PI), run_time=1)


for cls in (ZeroDash, ZeroLine, ZeroArc):
    scene, movie, error = render(cls)
    check(f"{cls.__name__} renders", error is None, repr(error))
    if error is None and movie_there(f"{cls.__name__}: frames", movie):
        n = frames_in(movie)
        check(f"{cls.__name__}: a second at 15 fps is 15 frames", n == 15, n)
# At zero length a DashedLine is a couple of empty dashes (0.22.1); it grows.
check("the dashed line starts empty and grows",
      bool(dash_counts) and dash_counts[0] < max(dash_counts), dash_counts[:8])


# ── 2. }} inside a formula ───────────────────────────────────────────
print("\n== }} inside a formula stays in one piece ==")

ODD = r"\sum_{k\ \mathrm{odd}}^{N} \frac{4}{\pi k}\,\sin kx"
have_latex = ON_IOS or (shutil.which("latex") and shutil.which("dvisvgm"))
captured_expressions: list[str] = []
captured_bodies: list[str] = []
_real_generate = tfw.generate_tex_file


def _capture_generate(expression, *args, **kwargs):
    captured_expressions.append(expression)
    return _real_generate(expression, *args, **kwargs)


tfw.generate_tex_file = _capture_generate
_restore_offlinai = None
if ON_IOS:
    try:
        import offlinai_latex as _ol

        _real_to_svg = _ol.tex_to_svg

        def _capture_to_svg(expression, *args, **kwargs):
            captured_bodies.append(kwargs.get("tex_template_body") or "")
            return _real_to_svg(expression, *args, **kwargs)

        _ol.tex_to_svg = _capture_to_svg
        _restore_offlinai = (_ol, _real_to_svg)
    except Exception as error:  # noqa: BLE001
        print(f"  (offlinai_latex unavailable: {type(error).__name__}: {error})")

if not have_latex:
    skip("the formula checks", "no latex + dvisvgm on PATH")
else:
    try:
        with tempconfig(SMALL):
            m = MathTex(ODD)
            check("the formula is one part", len(m.tex_strings) == 1, m.tex_strings)
            check("and no {{ }} split happened", not m.brace_notation_split_occurred)
            sent = [e for e in captured_expressions if "mathrm{odd" in e]
            check("the TeX compiled keeps \\mathrm{odd}}^{N} whole",
                  bool(sent) and r"\mathrm{odd}}^{N}" in sent[-1]
                  and "unique001" not in sent[-1], sent[-1:] or captured_expressions[-1:])
            plain = MathTex(r"\sum_{k \text{ odd}}^{N} x")
            check("and is as tall as its \\text{} twin (the rest is not in the subscript)",
                  abs(m.height - plain.height) < 0.05, (m.height, plain.height))

            eq = MathTex("{{ a }} + {{ b }}", "= c")
            check("{{ a }} + {{ b }} still splits into its parts",
                  [s.strip() for s in eq.tex_strings] == ["a", "+", "b", "= c"], eq.tex_strings)
            # set_color_by_tex matches a part's string exactly ("{{ b }}" is
            # " b "), so the idiom is {{b}}.
            sq = MathTex("{{a}}^2 + {{b}}^2", "= {{c}}^2")
            sq.set_color_by_tex("b", RED)
            colours = {s.tex_string: {g.get_fill_color().to_hex() for g in s.submobjects}
                       for s in sq.submobjects}
            check("and set_color_by_tex finds its part",
                  sq.tex_strings == ["a", "^2 + ", "b", "^2", "= ", "c", "^2"]
                  and colours.get("b") == {ManimColor(RED).to_hex()}
                  and colours.get("a") == {ManimColor(WHITE).to_hex()},
                  (sq.tex_strings, colours))

            ends = MathTex(r"x_{\frac{a}{b}}")
            check(r"x_{\frac{a}{b}} (a formula ending in }}) is one part",
                  len(ends.tex_strings) == 1, ends.tex_strings)
    except Exception as error:  # noqa: BLE001
        check("the formula checks run", False, f"{type(error).__name__}: {error}")

    class Matching(Scene):
        def construct(self):
            a = MathTex("{{ a }} + {{ b }}", "= c")
            b = MathTex("{{ a }} + {{ b }}", "= d")
            self.add(a)
            self.play(TransformMatchingTex(a, b), run_time=0.5)

    _, movie, error = render(Matching)
    check("TransformMatchingTex renders", error is None, repr(error))

    if ON_IOS:
        if _restore_offlinai is None:
            skip("what offlinai_latex is handed", "offlinai_latex not importable")
        else:
            bodies = [b for b in captured_bodies if "mathrm{odd" in b]
            check("offlinai_latex (picture and vector paths) gets it unsplit",
                  bool(bodies) and r"\mathrm{odd}}^{N}" in bodies[-1]
                  and "unique001" not in bodies[-1], bodies[-1:] or len(captured_bodies))
    else:
        # The iOS branch of tex_to_svg_file, with a stand-in offlinai_latex that
        # compiles what it is handed with this Mac's latex.
        import types

        stand_in = types.ModuleType("offlinai_latex")

        def _stand_in_to_svg(expression, svg_path=None, tex_template_body=None):
            captured_bodies.append(tex_template_body or "")
            template = config["tex_template"]
            tex = Path(svg_path).with_suffix(".tex")
            tex.write_text(tex_template_body, encoding="utf-8")
            dvi = tfw.compile_tex(tex, template.tex_compiler, template.output_format)
            return str(tfw.convert_to_svg(dvi, template.output_format))

        stand_in.tex_to_svg = _stand_in_to_svg
        saved_module = sys.modules.get("offlinai_latex")
        saved_platform = sys.platform
        sys.modules["offlinai_latex"] = stand_in
        try:
            with tempconfig({**SMALL, "media_dir": tempfile.mkdtemp(prefix="manim-ios-tex-")}):
                sys.platform = "ios"
                try:
                    m = MathTex(ODD)
                finally:
                    sys.platform = saved_platform
            bodies = [b for b in captured_bodies if "mathrm{odd" in b]
            check("the iOS branch hands offlinai_latex the formula unsplit",
                  bool(bodies) and r"\mathrm{odd}}^{N}" in bodies[-1]
                  and "unique001" not in bodies[-1], bodies[-1:])
        except Exception as error:  # noqa: BLE001
            check("the iOS LaTeX branch runs", False, f"{type(error).__name__}: {error}")
        finally:
            sys.platform = saved_platform
            if saved_module is None:
                sys.modules.pop("offlinai_latex", None)
            else:
                sys.modules["offlinai_latex"] = saved_module

tfw.generate_tex_file = _real_generate
if _restore_offlinai is not None:
    _restore_offlinai[0].tex_to_svg = _restore_offlinai[1]


# ── 3. the seams host apps patch ─────────────────────────────────────
print("\n== the writer as ManimStudio and CodeBench patch it ==")

check("scene_file_writer.to_av_frame_rate is there",
      sfw.to_av_frame_rate(29.97) == Fraction(30000, 1001), sfw.to_av_frame_rate(29.97))

seen = {"frames": 0, "plays": set(), "open": []}
real_write = sfw.SceneFileWriter.write_frame
real_encode = sfw.SceneFileWriter.encode_and_write_frame


def host_write_frame(self_fw, frame_or_renderer, num_frames=1):
    # ManimStudio's and CodeBench's wrapper, as they have it.
    seen["frames"] += int(num_frames)
    seen["plays"].add(int(self_fw.renderer.num_plays))
    real_write(self_fw, frame_or_renderer, num_frames)


def host_encode(self_fw, frame, num_frames):
    seen["open"].append(all(getattr(self_fw, name, None) is not None for name in
                            ("video_stream", "video_container",
                             "partial_movie_file_path", "queue")))
    return real_encode(self_fw, frame, num_frames)


class Plays(Scene):
    def construct(self):
        self.play(Create(Square()), run_time=1)
        self.wait(0.4)
        self.play(FadeOut(Square()), run_time=0.6)


sfw.SceneFileWriter.write_frame = host_write_frame
sfw.SceneFileWriter.encode_and_write_frame = host_encode
try:
    _, movie, error = render(Plays)
finally:
    sfw.SceneFileWriter.write_frame = real_write
    sfw.SceneFileWriter.encode_and_write_frame = real_encode
check("a render through a (frame, num_frames=1) write_frame wrapper", error is None, repr(error))
check("the wrapper saw every frame (2 s at 15 fps)", seen["frames"] == 30, seen["frames"])
check("and renderer.num_plays through the writer", seen["plays"] == {0, 1, 2}, seen["plays"])
check("encode_and_write_frame ran with the clip's stream, container, path and queue",
      bool(seen["open"]) and all(seen["open"]), seen["open"][:3])
if error is None and movie_there("the movie's length", movie):
    n = frames_in(movie)
    # A wait() may be written as its first and last frame (VideoToolbox):
    # count by time where it is, by frames elsewhere.
    with av.open(str(movie)) as container:
        seconds = float(container.duration or 0) / 1e6
    check("the movie is 2 s long", abs(seconds - 2.0) < 0.1 and n >= 22, (seconds, n))


# ── 4. a failing scene stops its writer thread ───────────────────────
print("\n== a scene that raises mid-animation ==")


class Boom(Exception):
    pass


class Raises(Scene):
    def construct(self):
        count = [0]

        def blow_up(mob):
            count[0] += 1
            if count[0] == 6:
                raise Boom("raised by the scene at frame 6")

        sq = Square().add_updater(blow_up)
        self.add(sq)
        self.play(sq.animate.shift(RIGHT), run_time=1)


scene, _, error = render(Raises)
check("the scene's error reaches the caller", isinstance(error, Boom), repr(error))
alive = [t.name for t in threading.enumerate()
         if t.name.startswith("partial-movie-encoder") and t.is_alive()]
check("no clip writer thread is left running", not alive, alive)
writer = LAST_WRITER[0]
partials = [p for p in writer.partial_movie_files if p]
check("the clip it was writing is gone", partials and not Path(partials[-1]).exists(), partials[-1:])

shutil.rmtree(MEDIA, ignore_errors=True)
print(f"\n{PASSED} passed, {FAILED} failed" + (f", {SKIPPED} skipped" if SKIPPED else ""))
sys.exit(1 if FAILED else 0)
