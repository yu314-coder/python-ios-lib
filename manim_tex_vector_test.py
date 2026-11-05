"""
manim_tex_vector_test.py — MathTex / Tex as real glyph outlines, as on a
desktop, in the same style as manim_image_test.py.

Run from the in-app shell:

    python manim_tex_vector_test.py        # about a minute the first time

On a Mac (no BusyTeX), pdflatex from TeX Live stands in for the app's
engine:

    python manim_tex_vector_test.py --host

Why this exists. Desktop manim turns each formula into SVG with dvisvgm: a
path per glyph, a <g id='uniqueNNN'> per MathTex part. On iOS formulas came
back as one PNG (BusyTeX -> PDF -> picture), so Write was a left-to-right
wipe, Transform between two formulas crashed ("pixel array shapes
incompatible"), Indicate and set_color_by_tex couldn't recolour, and
multi-part MathTex("a^2", "+", "b^2") or Tex with inline math failed to
compile. offlinai_latex now compiles manim's own .tex with pdflatex and
offlinai_latex.pdf_vector turns the PDF into dvisvgm's SVG. Checked here:

  1. Formulas are vector glyphs (no ImageMobject), with the right number of
     glyphs and parts, and colours from \\color.
  2. The SVG carries the marker manim's cache check accepts.
  3. Transform, set_color_by_tex, Indicate, Write and Tex with inline math
     work, in a small scene.
  4. The brace repair: plain parts stay as they are; a formula manim cut at
     `}}` (\\frac{p_{i|j}}{2n}) is mended, and still comes out as glyphs.
"""
from __future__ import annotations

import os
import subprocess  # noqa: F401  (imported before sys.platform changes)
import sys
import tempfile

PASSED = 0
FAILED = 0
HOST = "--host" in sys.argv


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}  {detail}")


try:
    import offlinai_latex
    from offlinai_latex import pdf_vector
    import manim
    from manim import (BLUE, RED, YELLOW, Indicate, MathTex, Scene, Tex,
                       TexTemplate, Transform, Write, tempconfig)
    from manim.mobject.types.image_mobject import ImageMobject
except Exception as exc:                                   # pragma: no cover
    print(f"  FAIL  import  {type(exc).__name__}: {exc}")
    raise SystemExit(1)

if HOST:
    # The app's BusyTeX engine answers compile_doc_request; on a Mac,
    # pdflatex does the same job.
    import shutil

    def _host_compile(tex_source, timeout=120.0):
        work = tempfile.mkdtemp(prefix="vec_test_")
        try:
            with open(os.path.join(work, "formula.tex"), "w") as f:
                f.write(tex_source)
            subprocess.run(["pdflatex", "-interaction=batchmode", "-halt-on-error",
                            "formula.tex"], cwd=work, capture_output=True, timeout=timeout)
            pdf = os.path.join(work, "formula.pdf")
            if not os.path.exists(pdf):
                raise pdf_vector.VectorTexError("pdflatex failed")
            return open(pdf, "rb").read()
        finally:
            shutil.rmtree(work, ignore_errors=True)

    offlinai_latex._compile_doc_pdf = _host_compile


def on_ios(make):
    """Build a mobject the way the app does (manim's iOS branch)."""
    real = sys.platform
    sys.platform = "ios"
    try:
        return make()
    finally:
        sys.platform = real


def glyphs(mob):
    return mob.family_members_with_points()


def no_images(mob):
    return not any(isinstance(m, ImageMobject) for m in mob.get_family())


print("1. formulas are glyphs")
media = tempfile.mkdtemp(prefix="vec_media_")
with tempconfig({"media_dir": media, "verbosity": "WARNING", "disable_caching": True}):
    e = on_ios(lambda: MathTex(r"e^{i\pi} + 1 = 0"))
    check("e^{i pi} + 1 = 0 is 7 glyphs, no picture", no_images(e) and len(glyphs(e)) == 7,
          f"{len(glyphs(e))} glyphs, images={not no_images(e)}")
    parts = on_ios(lambda: MathTex("a^2", "+", "b^2", "=", "c^2"))
    sizes = [len(glyphs(p)) for p in parts]
    check("MathTex('a^2', '+', 'b^2', '=', 'c^2') has parts of 2,1,2,1,2 glyphs",
          sizes == [2, 1, 2, 1, 2], str(sizes))
    xt = TexTemplate()
    xt.add_to_preamble(r"\usepackage{xcolor}")
    col = on_ios(lambda: MathTex(r"\color{red} x", "+", r"{\color{blue} y}", tex_template=xt))
    cols = [m.get_fill_color().to_hex().lower() for m in glyphs(col)]
    check("\\color gives red and blue glyphs", cols[0] == "#ff0000" and cols[-1] == "#0000ff", str(cols))
    t = on_ios(lambda: Tex(r"The area is $\pi r^2$"))
    check("Tex with inline math compiles to glyphs", no_images(t) and len(glyphs(t)) == 12,
          f"{len(glyphs(t))} glyphs")
    m = on_ios(lambda: MathTex(r"A=\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}"))
    check("a bmatrix is glyphs (rules too)", no_images(m) and len(glyphs(m)) == 8, str(len(glyphs(m))))

    print("2. the SVG")
    svgs = sorted(p for p in os.listdir(os.path.join(media, "Tex")) if p.endswith(".svg"))
    head = open(os.path.join(media, "Tex", svgs[0]), encoding="utf-8").read(400) if svgs else ""
    check("carries the vector marker manim's cache check accepts",
          pdf_vector.SVG_MARKER in head, head[:120])

    print("3. animations that need glyphs")

    class Probe(Scene):
        def construct(self):
            a = on_ios(lambda: MathTex(r"e^{i\pi} + 1 = 0"))
            b = on_ios(lambda: MathTex(r"\int_0^1 x^2\,dx = \frac{1}{3}"))
            self.play(Write(a), run_time=0.2)
            self.play(Transform(a, b), run_time=0.2)
            self.play(Indicate(a), run_time=0.2)
            p = on_ios(lambda: MathTex("a^2", "+", "b^2", "=", "c^2"))
            self.add(p)
            p.set_color_by_tex("c^2", YELLOW)
            self.colour = p[4][0].get_fill_color().to_hex().lower()

    try:
        with tempconfig({"media_dir": media, "write_to_movie": False, "frame_rate": 10,
                         "pixel_width": 320, "pixel_height": 180, "verbosity": "WARNING"}):
            scene = Probe()
            scene.render()
        check("Write, Transform between two formulas, Indicate render", True)
        check("set_color_by_tex colours the c^2 part", scene.colour == YELLOW.to_hex().lower(),
              scene.colour)
    except Exception as exc:
        check("Write, Transform between two formulas, Indicate render", False,
              f"{type(exc).__name__}: {exc}")

    print("4. the brace repair")
    strip = offlinai_latex._strip_specials_balanced
    o, c = r"\special{dvisvgm:raw <g id='unique00%d'>}", r"\special{dvisvgm:raw </g>}"
    plain = o % 0 + "a^2 " + c + o % 1 + "+ " + c + o % 2 + "b^2" + c
    check("plain parts are left as they are", strip(plain) == "a^2 + b^2", repr(strip(plain)))
    cut = o % 0 + r"p_{ij} = \frac{p_{j|i} + p_{i|j " + c + o % 1 + "{2n}" + c + "}}"
    check("a formula cut at }} is mended", strip(cut) == r"p_{ij} = \frac{p_{j|i} + p_{i|j}}{2n}",
          repr(strip(cut)))
    pij = on_ios(lambda: MathTex(r"p_{ij} = \frac{p_{j|i} + p_{i|j}}{2n}"))
    check("…and it still comes out as glyphs", no_images(pij) and len(glyphs(pij)) >= 15,
          f"{len(glyphs(pij))} glyphs, images={not no_images(pij)}")

print(f"{PASSED} passed, {FAILED} failed")
raise SystemExit(1 if FAILED else 0)
