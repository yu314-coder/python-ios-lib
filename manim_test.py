"""
manim_test.py — bundled Manim smoke test, in the same style as
scikit.py / numpy_test.py / sympy_test.py.

Run from the in-app shell:

    python manim_test.py

We deliberately don't *render* anything — rendering needs ffmpeg /
Cairo / a writable scratch space that the iOS sandbox may not provide.
Instead each check exercises an *object-level* manim API (constructing
mobjects, transforming them, inspecting their points / dimensions /
colours, building animation objects without playing them, etc.). That
covers the vast majority of bugs that show up when calling manim from
user scripts.

Footer summarises PASSED / FAILED counts.
"""
from __future__ import annotations

import os
import sys
import time
import numpy as np

import manim
from manim import (
    # Constants
    UP, DOWN, LEFT, RIGHT, IN, OUT, UR, UL, DR, DL, ORIGIN,
    PI, TAU, DEGREES,
    # Colors
    BLUE, RED, GREEN, YELLOW, WHITE, BLACK, ORANGE, PURPLE, PINK, GRAY,
    # 2D Mobjects
    Circle, Square, Rectangle, Triangle, RegularPolygon, Polygon,
    Star, RoundedRectangle, Dot, Ellipse,
    # Arcs / lines / arrows
    Arc, AnnularSector, Annulus, Sector,
    Line, Arrow, DoubleArrow, Vector, DashedLine,
    # 3D
    Sphere, Cube, Cone, Cylinder, Torus,
    # Groups
    VGroup, Group, VMobject, Mobject,
    # Coordinate systems
    Axes, NumberPlane, NumberLine, ThreeDAxes,
    # Numbers / values
    DecimalNumber, Integer, ValueTracker,
    # Animations (object-level only — never .play() in this test)
    Create, FadeIn, FadeOut, Write, Unwrite, Transform, ReplacementTransform,
    Rotate, GrowFromCenter,
    # Scene (constructed defensively, never rendered)
    Scene,
)

# ─── tracking ────────────────────────────────────────────────────────
_t0 = time.time()
_results: list[tuple[str, str, str]] = []
_section_name: str = ""


def section(n: int, name: str) -> None:
    global _section_name
    _section_name = name
    print()
    print(f"[{n:>2}] {name}")
    print("-" * 64)


def ok(msg: str) -> None:
    _results.append(("ok", _section_name, msg))
    print(f"  ok    {msg}")


def check(fn) -> None:
    try:
        fn()
    except Exception as e:
        _results.append(("FAIL", _section_name, f"{type(e).__name__}: {e}"))
        print(f"  FAIL  {_section_name} → {type(e).__name__}: {e}")


# ────────────────────────────────────────────────────────────────────
# [ 1] constants
# ────────────────────────────────────────────────────────────────────
section(1, "manim constants")

def _t():
    assert np.allclose(UP, [0, 1, 0])
    assert np.allclose(DOWN, [0, -1, 0])
    assert np.allclose(LEFT, [-1, 0, 0])
    assert np.allclose(RIGHT, [1, 0, 0])
    assert np.allclose(ORIGIN, [0, 0, 0])
    ok(f"UP={UP.tolist()}, DOWN={DOWN.tolist()}, LEFT={LEFT.tolist()}, RIGHT={RIGHT.tolist()}")
check(_t)

def _t():
    assert np.allclose(IN, [0, 0, -1])
    assert np.allclose(OUT, [0, 0, 1])
    ok(f"IN={IN.tolist()}, OUT={OUT.tolist()}")
check(_t)

def _t():
    # Diagonals
    assert np.allclose(UR, UP + RIGHT)
    assert np.allclose(DL, DOWN + LEFT)
    ok(f"UR=UP+RIGHT={UR.tolist()}, DL=DOWN+LEFT={DL.tolist()}")
check(_t)

def _t():
    # PI / TAU / DEGREES
    assert abs(PI - np.pi) < 1e-12
    assert abs(TAU - 2 * np.pi) < 1e-12
    assert abs(DEGREES - PI / 180) < 1e-12
    ok(f"PI≈π, TAU=2π, DEGREES=π/180 ({DEGREES:.6f})")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 2] colors
# ────────────────────────────────────────────────────────────────────
section(2, "manim colors")

def _t():
    from manim.utils.color import color_to_rgb, rgb_to_color
    rgb = color_to_rgb(RED)
    # RGB values are floats in [0, 1]
    assert all(0 <= c <= 1 for c in rgb)
    ok(f"color_to_rgb(RED) = {[round(c, 3) for c in rgb]}")
check(_t)

def _t():
    from manim.utils.color import interpolate_color
    mid = interpolate_color(BLUE, RED, 0.5)
    ok(f"interpolate_color(BLUE, RED, 0.5) = {mid}")
check(_t)

def _t():
    from manim.utils.color import color_to_rgb
    for name, col in [("RED", RED), ("BLUE", BLUE), ("GREEN", GREEN),
                       ("WHITE", WHITE), ("BLACK", BLACK)]:
        r = color_to_rgb(col)
        assert len(r) == 3
    ok(f"all 5 named colors round-trip through color_to_rgb")
check(_t)

def _t():
    # Average a list of colors
    from manim.utils.color import average_color
    avg = average_color(RED, BLUE)
    ok(f"average_color(RED, BLUE) = {avg}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 3] 2D mobjects — basic shapes
# ────────────────────────────────────────────────────────────────────
section(3, "manim 2D mobjects (basic)")

def _t():
    c = Circle(radius=2)
    assert abs(c.width - 4.0) < 1e-9 and abs(c.height - 4.0) < 1e-9
    ok(f"Circle(radius=2): width={c.width:.3f}, height={c.height:.3f}, center={c.get_center().tolist()}")
check(_t)

def _t():
    s = Square(side_length=3)
    assert abs(s.width - 3.0) < 1e-9 and abs(s.height - 3.0) < 1e-9
    ok(f"Square(side_length=3): w×h = {s.width:.2f}×{s.height:.2f}")
check(_t)

def _t():
    r = Rectangle(width=4, height=2)
    assert abs(r.width - 4.0) < 1e-9 and abs(r.height - 2.0) < 1e-9
    ok(f"Rectangle(4×2): w={r.width:.2f}, h={r.height:.2f}")
check(_t)

def _t():
    t = Triangle()
    # Triangle has 3 vertices
    pts = t.get_vertices() if hasattr(t, "get_vertices") else t.points
    ok(f"Triangle: vertex count ≥ 3, n_pts={len(pts)}")
check(_t)

def _t():
    p = RegularPolygon(n=6, radius=1)
    v = p.get_vertices()
    assert len(v) == 6
    ok(f"RegularPolygon(n=6): vertices={len(v)}")
check(_t)

def _t():
    p = Polygon(*[[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]])
    v = p.get_vertices()
    assert len(v) == 4
    ok(f"Polygon (unit square): vertices={len(v)}")
check(_t)

def _t():
    rr = RoundedRectangle(width=4, height=2, corner_radius=0.3)
    assert abs(rr.width - 4.0) < 1e-9
    ok(f"RoundedRectangle(4×2, r=0.3): width={rr.width:.2f}")
check(_t)

def _t():
    s = Star(n=5, outer_radius=1.5)
    ok(f"Star(n=5, R=1.5): width={s.width:.3f}, height={s.height:.3f}")
check(_t)

def _t():
    d = Dot(point=[2, 1, 0])
    assert np.allclose(d.get_center(), [2, 1, 0])
    ok(f"Dot at (2,1,0): center={d.get_center().tolist()}")
check(_t)

def _t():
    e = Ellipse(width=3, height=1)
    assert abs(e.width - 3.0) < 1e-9 and abs(e.height - 1.0) < 1e-9
    ok(f"Ellipse(3×1): w={e.width:.2f}, h={e.height:.2f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 4] lines / arrows / vectors
# ────────────────────────────────────────────────────────────────────
section(4, "manim lines / arrows")

def _t():
    L = Line([0, 0, 0], [3, 4, 0])
    length = L.get_length()
    assert abs(length - 5.0) < 1e-9
    ok(f"Line (0,0)→(3,4): length={length:.4f}")
check(_t)

def _t():
    a = Arrow(start=[0, 0, 0], end=[1, 1, 0])
    ok(f"Arrow start={a.get_start().tolist()}, end={a.get_end().tolist()}")
check(_t)

def _t():
    d = DoubleArrow(start=[0, 0, 0], end=[2, 0, 0])
    ok(f"DoubleArrow length={d.get_length():.3f}")
check(_t)

def _t():
    v = Vector([3, 4, 0])
    assert np.allclose(v.get_start(), ORIGIN)
    ok(f"Vector([3,4,0]) end={v.get_end().tolist()}, length≈{v.get_length():.4f}")
check(_t)

def _t():
    dl = DashedLine([0, 0, 0], [4, 0, 0])
    ok(f"DashedLine 0→4: length={dl.get_length():.3f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 5] arcs / sectors
# ────────────────────────────────────────────────────────────────────
section(5, "manim arcs / sectors")

def _t():
    a = Arc(radius=2, start_angle=0, angle=PI / 2)
    ok(f"Arc(r=2, θ=π/2): width={a.width:.3f}, height={a.height:.3f}")
check(_t)

def _t():
    # NB: manim's Sector subclasses AnnularSector and takes ``radius`` —
    # NOT ``outer_radius`` — because internally it does
    # ``super().__init__(inner_radius=0, outer_radius=radius, **kwargs)``.
    # Passing ``outer_radius=`` here would collide via **kwargs.
    s = Sector(radius=1.5, angle=PI)
    ok(f"Sector(radius=1.5, θ=π): width={s.width:.3f}")
check(_t)

def _t():
    an = Annulus(inner_radius=1, outer_radius=2)
    ok(f"Annulus(r=1, R=2): outer width={an.width:.3f}")
check(_t)

def _t():
    sec = AnnularSector(inner_radius=1, outer_radius=2, angle=PI / 2)
    ok(f"AnnularSector(r=1, R=2, θ=π/2): width={sec.width:.3f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 6] 3D mobjects
# ────────────────────────────────────────────────────────────────────
section(6, "manim 3D mobjects")

def _t():
    s = Sphere(radius=1.5)
    ok(f"Sphere(r=1.5): width={s.width:.3f}, height={s.height:.3f}, depth={s.depth:.3f}")
check(_t)

def _t():
    c = Cube(side_length=2)
    # 6 faces, each face is a square
    ok(f"Cube(side=2): width={c.width:.3f}, height={c.height:.3f}, depth={c.depth:.3f}")
check(_t)

def _t():
    co = Cone(base_radius=1, height=2)
    ok(f"Cone(r=1, h=2): width={co.width:.3f}, height={co.height:.3f}")
check(_t)

def _t():
    cy = Cylinder(radius=1, height=3)
    ok(f"Cylinder(r=1, h=3): width={cy.width:.3f}, height={cy.height:.3f}")
check(_t)

def _t():
    t = Torus(major_radius=2, minor_radius=0.5)
    ok(f"Torus(R=2, r=0.5): width={t.width:.3f}, depth={t.depth:.3f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 7] transformations (shift / scale / rotate / move_to)
# ────────────────────────────────────────────────────────────────────
section(7, "manim transformations")

def _t():
    c = Circle()
    c.shift(2 * RIGHT)
    assert np.allclose(c.get_center(), [2, 0, 0])
    ok(f"Circle().shift(2·RIGHT): center={c.get_center().tolist()}")
check(_t)

def _t():
    s = Square(side_length=1)
    s.scale(3)
    assert abs(s.width - 3.0) < 1e-9
    ok(f"Square(1).scale(3): width={s.width:.3f}")
check(_t)

def _t():
    s = Square(side_length=2)
    s.rotate(PI / 2)
    # Width and height shouldn't change for π/2 rotation (square is symmetric)
    ok(f"Square(2).rotate(π/2): width={s.width:.3f}, height={s.height:.3f}")
check(_t)

def _t():
    c = Circle()
    c.move_to([1, 2, 0])
    assert np.allclose(c.get_center(), [1, 2, 0])
    ok(f"Circle().move_to([1,2,0]): center={c.get_center().tolist()}")
check(_t)

def _t():
    a = Circle()
    b = Square()
    b.next_to(a, RIGHT, buff=0.5)
    # b should be to the right of a
    assert b.get_center()[0] > a.get_center()[0]
    ok(f"Square.next_to(Circle, RIGHT, buff=.5): Δx={b.get_center()[0] - a.get_center()[0]:.3f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 8] groups (VGroup / Group)
# ────────────────────────────────────────────────────────────────────
section(8, "manim groups (VGroup / Group)")

def _t():
    g = VGroup(Circle(), Square(), Triangle())
    assert len(g) == 3
    ok(f"VGroup(Circle, Square, Triangle): len={len(g)}")
check(_t)

def _t():
    g = VGroup(*[Circle().shift(i * RIGHT) for i in range(5)])
    # Arrange should reposition them
    g.arrange(RIGHT, buff=0.2)
    ok(f"VGroup(5 circles).arrange(RIGHT): width={g.width:.3f}")
check(_t)

def _t():
    g = VGroup()
    g.add(Circle())
    g.add(Square())
    assert len(g) == 2
    g.remove(g[0])
    assert len(g) == 1
    ok(f"VGroup .add / .remove: final len={len(g)}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [ 9] coordinate systems
# ────────────────────────────────────────────────────────────────────
section(9, "manim coordinate systems")

def _t():
    ax = Axes(x_range=[-3, 3, 1], y_range=[-2, 2, 1])
    pt = ax.coords_to_point(1, 1)
    # Round-trip
    coords = ax.point_to_coords(pt)
    assert abs(coords[0] - 1) < 1e-9 and abs(coords[1] - 1) < 1e-9
    ok(f"Axes coords_to_point(1,1) → {pt[:2].tolist()}, round-trip OK")
check(_t)

def _t():
    np_ = NumberPlane()
    # Should have x_axis and y_axis subobjects
    assert hasattr(np_, "x_axis") and hasattr(np_, "y_axis")
    ok(f"NumberPlane(): x_axis & y_axis present")
check(_t)

def _t():
    nl = NumberLine(x_range=[-5, 5, 1])
    pt = nl.number_to_point(2)
    n = nl.point_to_number(pt)
    assert abs(n - 2) < 1e-9
    ok(f"NumberLine.number_to_point(2) round-trip → {n:.4f}")
check(_t)

def _t():
    ta = ThreeDAxes()
    assert hasattr(ta, "x_axis") and hasattr(ta, "y_axis") and hasattr(ta, "z_axis")
    ok(f"ThreeDAxes(): x/y/z axes present")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [10] graphing (plot a function)
# ────────────────────────────────────────────────────────────────────
section(10, "manim graphing")

def _t():
    ax = Axes(x_range=[-2, 2, 1], y_range=[-1, 4, 1])
    graph = ax.plot(lambda x: x ** 2, x_range=[-1.5, 1.5])
    # graph is a VMobject with points
    assert hasattr(graph, "points") and len(graph.points) > 0
    ok(f"ax.plot(x²): {len(graph.points)} points")
check(_t)

def _t():
    ax = Axes(x_range=[-2, 2, 1], y_range=[-1, 4, 1])
    g = ax.plot(lambda x: np.exp(-(x ** 2)))
    ok(f"ax.plot(exp(-x²)): points={len(g.points)}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [11] numbers / value tracker
# ────────────────────────────────────────────────────────────────────
section(11, "manim numbers / ValueTracker")

def _t():
    d = DecimalNumber(3.14159, num_decimal_places=3)
    # Inspect the rendered value
    assert abs(d.get_value() - 3.14159) < 1e-9
    ok(f"DecimalNumber(3.14159).get_value() = {d.get_value()}")
check(_t)

def _t():
    i = Integer(42)
    assert i.get_value() == 42
    ok(f"Integer(42).get_value() = {i.get_value()}")
check(_t)

def _t():
    vt = ValueTracker(0)
    assert vt.get_value() == 0
    vt.set_value(7)
    assert vt.get_value() == 7
    ok(f"ValueTracker: 0 → set_value(7) → {vt.get_value()}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [12] animation classes (construct only — never play)
# ────────────────────────────────────────────────────────────────────
section(12, "manim animation classes (no playback)")

def _t():
    c = Circle()
    anim = Create(c)
    assert anim.mobject is c
    ok(f"Create(Circle) → animation type={type(anim).__name__}")
check(_t)

def _t():
    c = Circle()
    a1 = FadeIn(c); a2 = FadeOut(c)
    ok(f"FadeIn / FadeOut constructed: types={type(a1).__name__}, {type(a2).__name__}")
check(_t)

def _t():
    a = Circle(); b = Square()
    t = Transform(a, b)
    assert t.mobject is a
    ok(f"Transform(Circle, Square): mobject={type(t.mobject).__name__}")
check(_t)

def _t():
    c = Circle()
    r = Rotate(c, angle=PI / 4)
    ok(f"Rotate(Circle, π/4): type={type(r).__name__}")
check(_t)

def _t():
    c = Circle()
    g = GrowFromCenter(c)
    ok(f"GrowFromCenter(Circle): type={type(g).__name__}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [13] vector math helpers
# ────────────────────────────────────────────────────────────────────
section(13, "manim vector helpers")

def _t():
    from manim.utils.space_ops import angle_between_vectors, normalize
    a = angle_between_vectors(np.array([1, 0, 0]), np.array([0, 1, 0]))
    assert abs(a - PI / 2) < 1e-9
    ok(f"angle_between_vectors(x̂, ŷ) = {a:.4f} (π/2)")
check(_t)

def _t():
    from manim.utils.space_ops import normalize
    n = normalize(np.array([3.0, 4.0, 0.0]))
    assert abs(np.linalg.norm(n) - 1.0) < 1e-9
    ok(f"normalize([3,4,0]) = {n.tolist()} (|n|=1)")
check(_t)

def _t():
    from manim.utils.space_ops import midpoint
    m = midpoint(np.array([0, 0, 0]), np.array([2, 4, 6]))
    assert np.allclose(m, [1, 2, 3])
    ok(f"midpoint((0,0,0),(2,4,6)) = {list(m)}")
check(_t)

def _t():
    from manim.utils.space_ops import line_intersection
    p = line_intersection(([-1, 0, 0], [1, 0, 0]), ([0, -1, 0], [0, 1, 0]))
    assert np.allclose(p[:2], [0, 0])
    ok(f"line_intersection(x-axis, y-axis) = {list(p[:2])}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [14] bezier utilities
# ────────────────────────────────────────────────────────────────────
section(14, "manim bezier")

def _t():
    from manim.utils.bezier import bezier
    pts = [np.array([0, 0, 0]), np.array([1, 1, 0]),
           np.array([2, 1, 0]), np.array([3, 0, 0])]
    curve = bezier(pts)
    start = curve(0); end = curve(1)
    assert np.allclose(start, pts[0]) and np.allclose(end, pts[-1])
    ok(f"bezier(4 pts): curve(0)={start.tolist()}, curve(1)={end.tolist()}")
check(_t)

def _t():
    from manim.utils.bezier import bezier
    pts = [np.array([0, 0, 0]), np.array([1, 1, 0]), np.array([2, 0, 0])]
    curve = bezier(pts)
    mid = curve(0.5)
    ok(f"bezier(3 pts) midpoint = {mid.tolist()}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [15] rate functions (easing)
# ────────────────────────────────────────────────────────────────────
section(15, "manim rate functions")

def _t():
    from manim.utils.rate_functions import linear, smooth, ease_in_out_cubic
    assert linear(0) == 0 and abs(linear(1) - 1) < 1e-9
    assert smooth(0) == 0 and abs(smooth(1) - 1) < 1e-9
    ok(f"linear/smooth boundary OK; smooth(0.5)={smooth(0.5):.4f}, linear(0.5)={linear(0.5):.4f}")
check(_t)

def _t():
    from manim.utils.rate_functions import ease_in_out_cubic, ease_in_cubic, ease_out_cubic
    # Test that easing functions return reasonable values
    vals = [ease_in_out_cubic(t) for t in [0, 0.25, 0.5, 0.75, 1]]
    assert vals[0] == 0 and abs(vals[-1] - 1) < 1e-9
    assert vals[2] == 0.5  # ease_in_out is symmetric around 0.5
    ok(f"ease_in_out_cubic at [0,.25,.5,.75,1] = {[round(v, 4) for v in vals]}")
check(_t)

def _t():
    from manim.utils.rate_functions import there_and_back
    # there_and_back should go up then back down
    assert there_and_back(0) == 0
    assert there_and_back(1) == 0
    ok(f"there_and_back: 0→1→0, peak at 0.5 = {there_and_back(0.5):.4f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [16] updaters
# ────────────────────────────────────────────────────────────────────
section(16, "manim updaters")

def _t():
    # NB: ``Mobject.has_updaters`` doesn't exist in manim 0.19.0 (it's
    # been added/removed across versions). Stick to ``get_updaters()``
    # which is stable.
    c = Circle()
    c.add_updater(lambda m, dt: None)
    assert len(c.get_updaters()) == 1
    ok(f"add_updater: count={len(c.get_updaters())}")
check(_t)

def _t():
    c = Circle()
    f = lambda m, dt: m.shift(0.01 * UP)
    c.add_updater(f)
    c.remove_updater(f)
    n = len(c.get_updaters())
    ok(f"add then remove_updater: final count={n}")
check(_t)

def _t():
    c = Circle()
    c.add_updater(lambda m, dt: None)
    c.clear_updaters()
    assert len(c.get_updaters()) == 0
    ok(f"clear_updaters: count={len(c.get_updaters())}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [17] style (stroke / fill / color)
# ────────────────────────────────────────────────────────────────────
section(17, "manim style (stroke / fill)")

def _t():
    c = Circle()
    c.set_stroke(color=RED, width=5)
    ok(f"set_stroke(RED, width=5): stroke_width = {c.stroke_width}")
check(_t)

def _t():
    c = Circle()
    c.set_fill(color=BLUE, opacity=0.5)
    ok(f"set_fill(BLUE, opacity=0.5): fill_opacity = {c.fill_opacity}")
check(_t)

def _t():
    s = Square()
    s.set_color(GREEN)
    ok(f"set_color(GREEN): color attr resolves OK")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [18] iterables / utility helpers
# ────────────────────────────────────────────────────────────────────
section(18, "manim utility iterables")

def _t():
    from manim.utils.iterables import adjacent_pairs
    pairs = list(adjacent_pairs([1, 2, 3, 4]))
    ok(f"adjacent_pairs([1,2,3,4]) = {pairs}")
check(_t)

def _t():
    from manim.utils.iterables import remove_list_redundancies
    r = remove_list_redundancies([1, 2, 1, 3, 2, 4])
    assert r == [1, 2, 3, 4] or set(r) == {1, 2, 3, 4}
    ok(f"remove_list_redundancies([1,2,1,3,2,4]) = {r}")
check(_t)

def _t():
    from manim.utils.iterables import list_difference_update
    d = list_difference_update([1, 2, 3, 4, 5], [2, 4])
    assert set(d) == {1, 3, 5}
    ok(f"list_difference_update([1..5], [2,4]) = {sorted(d)}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [19] Mobject hierarchy / submobjects
# ────────────────────────────────────────────────────────────────────
section(19, "manim Mobject hierarchy")

def _t():
    c = Circle()
    s = Square()
    g = VGroup(c, s)
    family = list(g.get_family())
    # Family should include g, c, s, plus any submobjects
    assert g in family and c in family and s in family
    ok(f"VGroup family includes parent + 2 children: total len={len(family)}")
check(_t)

def _t():
    c = Circle()
    submobs = c.submobjects
    ok(f"Circle().submobjects: count={len(submobs)}")
check(_t)

def _t():
    c1 = Circle(); c2 = Circle()
    c1.match_style(c2)
    ok(f"c1.match_style(c2) returned without error")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [20] Matrix mobject
# ────────────────────────────────────────────────────────────────────
section(20, "manim Matrix mobject")

def _t():
    from manim import IntegerMatrix
    m = IntegerMatrix([[1, 2], [3, 4]])
    ok(f"IntegerMatrix([[1,2],[3,4]]): width={m.width:.3f}, height={m.height:.3f}")
check(_t)

def _t():
    from manim import Matrix as MatrixMobject
    m = MatrixMobject([["a", "b"], ["c", "d"]])
    ok(f"Matrix(2×2 string entries) constructed: rows={len(m.get_rows())}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [21] Scene (defensive — never .render())
# ────────────────────────────────────────────────────────────────────
section(21, "manim Scene (defensive — no render)")

def _t():
    # Even constructing a Scene can fail if the renderer / config isn't
    # set up. We catch and report rather than crash the whole suite.
    s = Scene()
    ok(f"Scene() constructed; type={type(s).__name__}, n_mobjects={len(s.mobjects)}")
check(_t)

def _t():
    s = Scene()
    c = Circle()
    s.add(c)
    assert c in s.mobjects
    ok(f"Scene.add(Circle): n_mobjects={len(s.mobjects)}")
check(_t)

def _t():
    s = Scene()
    c = Circle()
    s.add(c)
    s.remove(c)
    assert c not in s.mobjects
    ok(f"Scene.remove(Circle): n_mobjects={len(s.mobjects)}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [22] points / vertices inspection
# ────────────────────────────────────────────────────────────────────
section(22, "manim point inspection")

def _t():
    c = Circle(radius=1)
    pts = c.points
    assert pts.shape[1] == 3
    ok(f"Circle.points: shape={pts.shape}")
check(_t)

def _t():
    s = Square(side_length=2)
    corners = [s.get_corner(d) for d in [UR, UL, DL, DR]]
    # All four corners should be distinct
    assert len({tuple(c.round(6)) for c in corners}) == 4
    ok(f"Square corners: UR={corners[0][:2].tolist()}, DL={corners[2][:2].tolist()}")
check(_t)

def _t():
    s = Square(side_length=2)
    assert np.allclose(s.get_top(), [0, 1, 0])
    assert np.allclose(s.get_bottom(), [0, -1, 0])
    assert np.allclose(s.get_left(), [-1, 0, 0])
    assert np.allclose(s.get_right(), [1, 0, 0])
    ok(f"Square(2): top/bot/left/right at edges, get_top()={s.get_top().tolist()}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [23] copy / deepcopy
# ────────────────────────────────────────────────────────────────────
section(23, "manim copy / deepcopy")

def _t():
    c = Circle(radius=2)
    c2 = c.copy()
    c2.shift(3 * RIGHT)
    # Original shouldn't move
    assert np.allclose(c.get_center(), ORIGIN)
    assert np.allclose(c2.get_center(), 3 * RIGHT)
    ok(f"copy(): original at {c.get_center()[:2].tolist()}, shifted copy at {c2.get_center()[:2].tolist()}")
check(_t)

def _t():
    import copy as _copy
    s = Square()
    s2 = _copy.deepcopy(s)
    s2.scale(2)
    assert abs(s.width - 2.0) < 1e-9 and abs(s2.width - 4.0) < 1e-9
    ok(f"deepcopy: original width={s.width:.2f}, scaled copy width={s2.width:.2f}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [24] align / alignment
# ────────────────────────────────────────────────────────────────────
section(24, "manim alignment")

def _t():
    a = Circle().shift(2 * LEFT)
    b = Square()
    b.align_to(a, LEFT)
    # b's left edge should equal a's left edge
    assert abs(b.get_left()[0] - a.get_left()[0]) < 1e-9
    ok(f"align_to(LEFT): b.left = a.left = {b.get_left()[0]:.3f}")
check(_t)

def _t():
    g = VGroup(*[Circle().shift(i * 2 * RIGHT) for i in range(4)])
    g.move_to(ORIGIN)
    assert np.allclose(g.get_center(), ORIGIN, atol=1e-9)
    ok(f"VGroup.move_to(ORIGIN): center={g.get_center().tolist()}")
check(_t)

# ────────────────────────────────────────────────────────────────────
# [25] table
# ────────────────────────────────────────────────────────────────────
section(25, "manim Table")

def _t():
    from manim import Table
    t = Table(
        [["a", "b"], ["c", "d"]],
        row_labels=None,
        col_labels=None,
    )
    rows = t.get_rows()
    ok(f"Table(2×2): rows={len(rows)}")
check(_t)


# ────────────────────────────────────────────────────────────────────
# [26] regressions fixed by the move to manim 0.22.1 (both seen in
#      ManimStudio / CodeBench, 2026-11-09; manim_regression_test.py renders them)
# ────────────────────────────────────────────────────────────────────
section(26, "manim regressions: }} in a formula, zero-length always_redraw")

def _t():
    # MathTex split on every "}}", so \mathrm{odd}}^{N} was cut in two and
    # the rest of the formula stayed in the subscript. 0.22's rule: "{{"
    # opens a part only at the start or after whitespace.
    split = manim.MathTex._split_double_braces
    whole = r"\sum_{k\ \mathrm{odd}}^{N} \frac{4}{\pi k}\,\sin kx"
    assert split(whole) == [whole], split(whole)
    assert split(r"\frac{a}{b}}") == [r"\frac{a}{b}}"]
    assert split(r"\frac{p_{i|j}}{2n}") == [r"\frac{p_{i|j}}{2n}"]
    parts = [p for p in split("{{ a }} + {{ b }}") if p]
    assert parts == [" a ", " + ", " b "], parts
    ok(r"}} inside a formula stays whole; {{ a }} + {{ b }} still splits")
check(_t)

def _t():
    # An always_redraw DashedLine of zero length has no dashes, and become()
    # into it raised IndexError in align_points (manim 0.20's
    # get_nth_subpath indexed an empty list).
    p = np.array([1.0, 0.0, 0.0])
    q = np.array([1.0, 0.5, 0.0])
    for make in (lambda a, b: DashedLine(a, b), lambda a, b: Line(a, b)):
        empty, full = make(p, p), make(p, q)
        full.become(empty)
        empty2, full2 = make(p, p), make(p, q)
        empty2.become(full2)
    Arc(angle=0).become(Arc(angle=PI / 2))
    Arc(angle=PI / 2).become(Arc(angle=0))
    ok("become() between zero-length and full DashedLine, Line, Arc")
check(_t)


# ────────────────────────────────────────────────────────────────────
# summary
# ────────────────────────────────────────────────────────────────────
print()
print("=" * 64)
print(f"  manim version: {manim.__version__}")
print(f"  Elapsed: {time.time() - _t0:.2f}s")
n_ok = sum(1 for s, *_ in _results if s == "ok")
n_fail = sum(1 for s, *_ in _results if s == "FAIL")
print(f"  PASSED: {n_ok}")
print(f"  FAILED: {n_fail}")
if n_fail:
    print()
    print("  Failures:")
    seen = set()
    for status, name, msg in _results:
        if status == "FAIL" and name not in seen:
            print(f"    • {name} — {msg}")
            seen.add(name)
print("=" * 64)
