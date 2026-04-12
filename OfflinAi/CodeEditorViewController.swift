import UIKit
import WebKit

// MARK: - CodeEditorViewController

/// Monaco-style split-view code editor with AI chat sidebar and terminal output.
final class CodeEditorViewController: UIViewController {

    // MARK: - Types

    enum Language: Int, CaseIterable {
        case python = 0
        case c = 1
        case cpp = 2
        case fortran = 3

        var title: String {
            switch self {
            case .python: return "Python"
            case .c: return "C"
            case .cpp: return "C++"
            case .fortran: return "Fortran"
            }
        }

        var defaultCode: String {
            switch self {
            case .python:
                return "# Python playground\nimport math\n\ndef greet(name):\n    return f\"Hello, {name}!\"\n\nprint(greet(\"World\"))\nprint(f\"pi = {math.pi:.6f}\")\n"
            case .c:
                return "#include <stdio.h>\n#include <math.h>\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    printf(\"pi = %.6f\\n\", M_PI);\n    return 0;\n}\n"
            case .cpp:
                return "#include <iostream>\n#include <vector>\n#include <string>\nusing namespace std;\n\nclass Greeter {\npublic:\n    string name;\n    Greeter(string n) { name = n; }\n    void greet() { cout << \"Hello, \" << name << \"!\" << endl; }\n};\n\nint main() {\n    Greeter g(\"World\");\n    g.greet();\n\n    vector<int> nums = {1, 2, 3, 4, 5};\n    for (auto& n : nums) {\n        cout << n * n << \" \";\n    }\n    cout << endl;\n    return 0;\n}\n"
            case .fortran:
                return "program hello\n    implicit none\n    integer :: i\n    real :: pi\n    pi = 4.0 * atan(1.0)\n    print *, \"Hello, World!\"\n    print *, \"pi =\", pi\n    do i = 1, 5\n        print *, \"i =\", i, \"i^2 =\", i*i\n    end do\nend program hello\n"
            }
        }
    }

    // MARK: - Template

    struct Template {
        let title: String
        let icon: String
        let category: String
        let language: Language
        let code: String
    }

    static let templates: [Template] = [
        // ── manim ──

        Template(title: "manim: Basic Shapes", icon: "sparkles", category: "Manim", language: .python, code:
        "from manim import *\n\nclass BasicShapes(Scene):\n  def construct(self):\n    circle = Circle(radius=0.6, color=BLUE, fill_opacity=0.6)\n    square = Square(side_length=1.0, color=RED, fill_opacity=0.5)\n    triangle = Triangle(color=GREEN, fill_opacity=0.5).scale(0.6)\n    star = Star(n=5, outer_radius=0.6, color=GOLD, fill_opacity=0.6)\n    dot = Dot(radius=0.2, color=WHITE)\n    arrow = Arrow(LEFT*0.5, RIGHT*0.5, color=YELLOW)\n    line = Line(LEFT*0.5, RIGHT*0.5, color=PURPLE, stroke_width=4)\n    row1 = VGroup(circle, square, triangle, star).arrange(RIGHT, buff=0.8)\n    row2 = VGroup(dot, arrow, line).arrange(RIGHT, buff=1.2)\n    grid = VGroup(row1, row2).arrange(DOWN, buff=1.0)\n    self.play(LaggedStart(*[Create(m) for m in [circle, square, triangle, star, dot, arrow, line]], lag_ratio=0.2), run_time=3)\n    self.wait(0.5)\n\nscene = BasicShapes()\nscene.render()\n"),

        Template(title: "manim: Transformations", icon: "arrow.triangle.2.circlepath", category: "Manim", language: .python, code:
        "from manim import *\n\nclass Transformations(Scene):\n  def construct(self):\n    circle = Circle(color=BLUE, fill_opacity=0.8)\n    square = Square(color=RED, fill_opacity=0.8)\n    triangle = Triangle(color=GREEN, fill_opacity=0.8)\n    star = Star(color=GOLD, fill_opacity=0.8)\n    self.play(Create(circle))\n    self.play(Transform(circle, square))\n    self.play(ReplacementTransform(circle, triangle))\n    self.play(FadeOut(triangle))\n    self.play(FadeIn(star))\n    self.play(Rotate(star, angle=PI), run_time=1)\n    self.play(star.animate.scale(0.3))\n    self.play(star.animate.scale(3))\n    self.play(FadeOut(star))\n    self.wait(0.5)\n\nscene = Transformations()\nscene.render()\n"),

        Template(title: "manim: Function Graphs", icon: "chart.xyaxis.line", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass FunctionGraphs(Scene):\n  def construct(self):\n    axes = Axes(x_range=[-4, 4, 1], y_range=[-2, 4, 1], x_length=10, y_length=6, axis_config={'include_numbers': False})\n    sin_curve = axes.plot(lambda x: np.sin(x), color=BLUE, x_range=[-4, 4])\n    cos_curve = axes.plot(lambda x: np.cos(x), color=RED, x_range=[-4, 4])\n    para_curve = axes.plot(lambda x: 0.25*x**2, color=GREEN, x_range=[-3.5, 3.5])\n    self.play(Create(axes), run_time=1)\n    self.play(Create(sin_curve), run_time=1)\n    self.play(Create(cos_curve), run_time=1)\n    self.play(Create(para_curve), run_time=1)\n    area = axes.get_area(sin_curve, x_range=[0, PI], color=BLUE, opacity=0.3)\n    self.play(FadeIn(area))\n    self.wait(0.5)\n\nscene = FunctionGraphs()\nscene.render()\n"),

        Template(title: "manim: Animated Plot", icon: "point.topleft.down.to.point.bottomright.curvepath", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass AnimatedPlot(Scene):\n  def construct(self):\n    axes = Axes(x_range=[-4, 4, 1], y_range=[-2, 2, 1], x_length=10, y_length=5, axis_config={'include_numbers': False})\n    curve = axes.plot(lambda x: np.sin(x), color=BLUE)\n    self.play(Create(axes), Create(curve), run_time=1)\n    tracker = ValueTracker(-4)\n    dot = Dot(color=YELLOW, radius=0.12)\n    dot.add_updater(lambda d: d.move_to(axes.c2p(tracker.get_value(), np.sin(tracker.get_value()))))\n    trail = TracedPath(dot.get_center, stroke_color=YELLOW, stroke_width=3)\n    self.add(trail, dot)\n    self.play(tracker.animate.set_value(4), run_time=4, rate_func=linear)\n    self.wait(0.5)\n\nscene = AnimatedPlot()\nscene.render()\n"),

        Template(title: "manim: 3D Surface", icon: "cube", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass ThreeDSurface(ThreeDScene):\n  def construct(self):\n    axes = ThreeDAxes(x_range=[-3, 3], y_range=[-3, 3], z_range=[-2, 2])\n    surface = Surface(lambda u, v: axes.c2p(u, v, np.sin(u) * np.cos(v)), u_range=[-3, 3], v_range=[-3, 3], resolution=(30, 30))\n    surface.set_style(fill_opacity=0.7)\n    surface.set_fill_by_value(axes=axes, colorscale=[(RED, -1), (YELLOW, 0), (GREEN, 1)])\n    self.set_camera_orientation(phi=70*DEGREES, theta=30*DEGREES)\n    self.play(Create(axes), Create(surface), run_time=2)\n    self.begin_ambient_camera_rotation(rate=0.3)\n    self.wait(3)\n    self.stop_ambient_camera_rotation()\n    self.wait(0.5)\n\nscene = ThreeDSurface()\nscene.render()\n"),

        Template(title: "manim: Color Gradient", icon: "paintbrush", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass ColorGradient(Scene):\n  def construct(self):\n    colors = [RED, RED_A, ORANGE, YELLOW, YELLOW_A, GREEN, GREEN_A, TEAL, TEAL_A, BLUE, BLUE_A, PURPLE, PURPLE_A, PINK, MAROON, GOLD]\n    dots = VGroup()\n    n = len(colors)\n    for i, c in enumerate(colors):\n      angle = i * TAU / n\n      dot = Dot(radius=0.25, color=c, fill_opacity=0.9)\n      dot.move_to(2.5 * np.array([np.cos(angle), np.sin(angle), 0]))\n      dots.add(dot)\n    inner = VGroup()\n    for i, c in enumerate(colors):\n      angle = i * TAU / n + TAU / (2*n)\n      dot = Dot(radius=0.15, color=c, fill_opacity=0.6)\n      dot.move_to(1.5 * np.array([np.cos(angle), np.sin(angle), 0]))\n      inner.add(dot)\n    self.play(LaggedStart(*[FadeIn(d, scale=0.5) for d in dots], lag_ratio=0.08), run_time=2)\n    self.play(LaggedStart(*[FadeIn(d, scale=0.5) for d in inner], lag_ratio=0.08), run_time=1.5)\n    self.play(Rotate(dots, angle=TAU, run_time=2, rate_func=smooth))\n    self.wait(0.5)\n\nscene = ColorGradient()\nscene.render()\n"),

        Template(title: "manim: Geometry Proof", icon: "triangle", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass GeometryProof(Scene):\n  def construct(self):\n    a = np.array([-2, -1, 0])\n    b = np.array([1, -1, 0])\n    c = np.array([-2, 2, 0])\n    tri = Polygon(a, b, c, color=WHITE, stroke_width=3)\n    right_angle = Square(side_length=0.3, color=WHITE, stroke_width=2).move_to(a + np.array([0.15, 0.15, 0]))\n    ab = np.linalg.norm(b - a)\n    bc = np.linalg.norm(c - b)\n    ca = np.linalg.norm(a - c)\n    sq_a = Square(side_length=ab, color=RED, fill_opacity=0.3, stroke_width=2)\n    sq_a.next_to(Line(a, b), DOWN, buff=0)\n    sq_b = Square(side_length=ca, color=GREEN, fill_opacity=0.3, stroke_width=2)\n    sq_b.next_to(Line(a, c), LEFT, buff=0)\n    sq_c_side = bc\n    mid_bc = (b + c) / 2\n    direction = np.array([c[1] - b[1], b[0] - c[0], 0])\n    direction = direction / np.linalg.norm(direction)\n    sq_c = Square(side_length=sq_c_side, color=BLUE, fill_opacity=0.3, stroke_width=2)\n    sq_c.move_to(mid_bc + direction * sq_c_side / 2)\n    sq_c.rotate(np.arctan2(c[1]-b[1], c[0]-b[0]))\n    self.play(Create(tri), Create(right_angle), run_time=1)\n    self.play(FadeIn(sq_a), run_time=0.8)\n    self.play(FadeIn(sq_b), run_time=0.8)\n    self.play(FadeIn(sq_c), run_time=0.8)\n    self.play(Indicate(sq_a), Indicate(sq_b), run_time=1)\n    self.play(Indicate(sq_c), run_time=1)\n    self.wait(0.5)\n\nscene = GeometryProof()\nscene.render()\n"),

        Template(title: "manim: Number Line", icon: "ruler", category: "Manim", language: .python, code:
        "from manim import *\n\nclass NumberLineDemo(Scene):\n  def construct(self):\n    nline = NumberLine(x_range=[-5, 5, 1], length=10, include_numbers=False, include_tip=True)\n    ticks = VGroup(*[Dot(radius=0.06, color=YELLOW).move_to(nline.n2p(i)) for i in range(-5, 6)])\n    self.play(Create(nline), run_time=1)\n    self.play(LaggedStart(*[FadeIn(t, scale=0.5) for t in ticks], lag_ratio=0.1))\n    arrow = Arrow(start=UP*0.8, end=DOWN*0.1, color=RED, buff=0).move_to(nline.n2p(-4) + UP*0.5)\n    self.play(GrowArrow(arrow))\n    tracker = ValueTracker(-4)\n    arrow.add_updater(lambda a: a.move_to(nline.n2p(tracker.get_value()) + UP*0.5))\n    self.play(tracker.animate.set_value(4), run_time=3, rate_func=smooth)\n    self.play(tracker.animate.set_value(0), run_time=1.5)\n    self.wait(0.5)\n\nscene = NumberLineDemo()\nscene.render()\n"),

        Template(title: "manim: Matrix Transform", icon: "grid", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass MatrixTransform(Scene):\n  def construct(self):\n    plane = NumberPlane(x_range=[-5, 5], y_range=[-4, 4], background_line_style={'stroke_color': BLUE_D, 'stroke_opacity': 0.3})\n    basis_i = Arrow(plane.c2p(0, 0), plane.c2p(1, 0), buff=0, color=GREEN, stroke_width=5)\n    basis_j = Arrow(plane.c2p(0, 0), plane.c2p(0, 1), buff=0, color=RED, stroke_width=5)\n    dot = Dot(plane.c2p(1, 1), color=YELLOW, radius=0.1)\n    self.play(Create(plane), GrowArrow(basis_i), GrowArrow(basis_j), FadeIn(dot), run_time=1.5)\n    matrix = [[2, 1], [0, 1.5]]\n    self.play(plane.animate.apply_matrix(matrix), basis_i.animate.put_start_and_end_on(plane.c2p(0, 0), plane.c2p(2, 0)), basis_j.animate.put_start_and_end_on(plane.c2p(0, 0), plane.c2p(1, 1.5)), dot.animate.move_to(plane.c2p(3, 1.5)), run_time=2)\n    self.wait(0.5)\n\nscene = MatrixTransform()\nscene.render()\n"),

        Template(title: "manim: Bar Chart", icon: "chart.bar", category: "Manim", language: .python, code:
        "from manim import *\n\nclass BarChartDemo(Scene):\n  def construct(self):\n    chart = BarChart(values=[3, 5, 2, 8, 4, 7], bar_names=['A', 'B', 'C', 'D', 'E', 'F'], bar_colors=[BLUE, RED, GREEN, YELLOW, PURPLE, ORANGE], y_range=[0, 10, 2], y_length=4, x_length=9)\n    self.play(Create(chart), run_time=2)\n    self.play(chart.animate.change_bar_values([7, 3, 9, 2, 6, 4]), run_time=1.5)\n    self.play(chart.animate.change_bar_values([5, 5, 5, 5, 5, 5]), run_time=1.5)\n    self.play(chart.animate.change_bar_values([1, 4, 9, 4, 1, 6]), run_time=1.5)\n    self.wait(0.5)\n\nscene = BarChartDemo()\nscene.render()\n"),

        Template(title: "manim: Vector Field", icon: "wind", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass VectorFieldDemo(Scene):\n  def construct(self):\n    func = lambda p: np.array([-p[1], p[0], 0]) * 0.3\n    field = ArrowVectorField(func, x_range=[-4, 4, 0.8], y_range=[-3, 3, 0.8], colors=[BLUE, GREEN, YELLOW, RED])\n    self.play(Create(field), run_time=2)\n    dot = Dot(color=WHITE, radius=0.12).move_to(RIGHT*2 + UP)\n    self.play(FadeIn(dot))\n    stream = StreamLines(func, x_range=[-4, 4], y_range=[-3, 3], stroke_width=2, max_anchors_per_line=30)\n    self.play(FadeOut(field), run_time=0.5)\n    self.add(stream)\n    stream.start_animation(warm_up=True, flow_speed=1.5)\n    self.wait(3)\n    self.wait(0.5)\n\nscene = VectorFieldDemo()\nscene.render()\n"),

        Template(title: "manim: Fractal (Sierpinski)", icon: "triangle.inset.filled", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass Sierpinski(Scene):\n  def construct(self):\n    def make_triangles(vertices, depth):\n      if depth == 0:\n        return [Polygon(*vertices, color=BLUE, fill_opacity=0.7, stroke_width=1)]\n      a, b, c = vertices\n      ab = (a + b) / 2\n      bc = (b + c) / 2\n      ca = (c + a) / 2\n      t1 = make_triangles([a, ab, ca], depth - 1)\n      t2 = make_triangles([ab, b, bc], depth - 1)\n      t3 = make_triangles([ca, bc, c], depth - 1)\n      return t1 + t2 + t3\n    v0 = np.array([-3.5, -2.5, 0])\n    v1 = np.array([3.5, -2.5, 0])\n    v2 = np.array([0, 3.0, 0])\n    colors = [BLUE, GREEN, YELLOW, RED, PURPLE]\n    prev = None\n    for d in range(5):\n      tris = make_triangles([v0, v1, v2], d)\n      col = colors[d % len(colors)]\n      for t in tris:\n        t.set_fill(col, opacity=0.6)\n        t.set_stroke(col, width=1)\n      group = VGroup(*tris)\n      if prev is None:\n        self.play(Create(group), run_time=1)\n      else:\n        self.play(ReplacementTransform(prev, group), run_time=1)\n      prev = group\n    self.wait(0.5)\n\nscene = Sierpinski()\nscene.render()\n"),

        Template(title: "manim: Pendulum", icon: "metronome", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass PendulumScene(Scene):\n  def construct(self):\n    pivot = Dot(UP*3, color=WHITE, radius=0.08)\n    length = 3.0\n    tracker = ValueTracker(PI/4)\n    bob = Dot(color=RED, radius=0.2)\n    rod = Line(start=UP*3, end=UP*3, color=GREY, stroke_width=3)\n    def update_bob(b):\n      angle = tracker.get_value()\n      pos = pivot.get_center() + length * np.array([np.sin(angle), -np.cos(angle), 0])\n      b.move_to(pos)\n    def update_rod(r):\n      r.put_start_and_end_on(pivot.get_center(), bob.get_center())\n    bob.add_updater(update_bob)\n    rod.add_updater(update_rod)\n    trail = TracedPath(bob.get_center, stroke_color=YELLOW, stroke_width=2, stroke_opacity=0.5)\n    self.add(pivot, rod, bob, trail)\n    update_bob(bob)\n    update_rod(rod)\n    for i in range(6):\n      amp = PI/4 * (0.85 ** i)\n      self.play(tracker.animate.set_value(-amp), run_time=0.7, rate_func=smooth)\n      self.play(tracker.animate.set_value(amp), run_time=0.7, rate_func=smooth)\n    self.play(tracker.animate.set_value(0), run_time=0.5)\n    self.wait(0.5)\n\nscene = PendulumScene()\nscene.render()\n"),

        Template(title: "manim: Wave Animation", icon: "wave.3.right", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass WaveAnimation(Scene):\n  def construct(self):\n    axes = Axes(x_range=[0, 10, 1], y_range=[-2, 2, 1], x_length=12, y_length=4, axis_config={'include_numbers': False})\n    self.play(Create(axes), run_time=0.5)\n    tracker = ValueTracker(0)\n    wave = always_redraw(lambda: axes.plot(lambda x: np.sin(2*x - tracker.get_value()), color=BLUE, x_range=[0, 10]))\n    wave2 = always_redraw(lambda: axes.plot(lambda x: 0.5 * np.sin(4*x - 2*tracker.get_value()), color=RED, x_range=[0, 10]))\n    combined = always_redraw(lambda: axes.plot(lambda x: np.sin(2*x - tracker.get_value()) + 0.5*np.sin(4*x - 2*tracker.get_value()), color=GREEN, x_range=[0, 10]))\n    self.play(Create(wave), run_time=0.5)\n    self.play(Create(wave2), run_time=0.5)\n    self.play(Create(combined), run_time=0.5)\n    self.play(tracker.animate.set_value(4*PI), run_time=5, rate_func=linear)\n    self.wait(0.5)\n\nscene = WaveAnimation()\nscene.render()\n"),

    ]

    // MARK: - Theme Colors

    private enum EditorTheme {
        static let background    = UIColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0) // #1e1e2e
        static let foreground    = UIColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0) // #cdd6f4
        static let keyword       = UIColor(red: 0.980, green: 0.651, blue: 0.376, alpha: 1.0) // orange
        static let string        = UIColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1.0) // green
        static let comment       = UIColor(red: 0.533, green: 0.553, blue: 0.627, alpha: 1.0) // gray
        static let number        = UIColor(red: 0.710, green: 0.561, blue: 0.906, alpha: 1.0) // purple
        static let gutterBg      = UIColor(red: 0.098, green: 0.098, blue: 0.149, alpha: 1.0)
        static let gutterText    = UIColor(red: 0.400, green: 0.420, blue: 0.502, alpha: 1.0)
        static let terminalBg    = UIColor(red: 0.059, green: 0.059, blue: 0.082, alpha: 1.0)
        static let terminalText  = UIColor(red: 0.298, green: 0.886, blue: 0.412, alpha: 1.0)
        static let terminalError = UIColor(red: 0.957, green: 0.318, blue: 0.318, alpha: 1.0)
        static let chatBg        = UIColor(red: 0.137, green: 0.137, blue: 0.200, alpha: 1.0)
        static let userBubble    = UIColor(red: 0.200, green: 0.200, blue: 0.310, alpha: 1.0)
        static let aiBubble      = UIColor(red: 0.160, green: 0.220, blue: 0.290, alpha: 1.0)
    }

    // MARK: - Syntax Keywords

    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import",
        "from", "as", "in", "not", "and", "or", "try", "except", "with", "lambda",
        "print", "True", "False", "None", "raise", "finally", "yield", "pass",
        "break", "continue", "del", "global", "nonlocal", "assert", "is"
    ]

    private static let cKeywords: Set<String> = [
        "int", "float", "double", "char", "void", "if", "else", "for", "while",
        "do", "return", "struct", "enum", "typedef", "printf", "malloc", "free",
        "sizeof", "static", "const", "unsigned", "long", "short", "switch", "case",
        "break", "continue", "default", "NULL", "auto", "register", "extern", "union"
    ]

    private static let cppKeywords: Set<String> = [
        // C base
        "int", "float", "double", "char", "void", "if", "else", "for", "while",
        "do", "return", "struct", "enum", "typedef", "sizeof", "static", "const",
        "unsigned", "long", "short", "switch", "case", "break", "continue", "default",
        // C++ specific
        "class", "public", "private", "protected", "new", "delete", "this", "virtual",
        "override", "namespace", "using", "template", "typename", "auto", "bool",
        "true", "false", "nullptr", "try", "catch", "throw", "operator", "friend",
        "inline", "explicit", "mutable", "constexpr", "final", "noexcept",
        // STL
        "cout", "cin", "endl", "string", "vector", "map", "pair", "tuple",
        "sort", "find", "count", "reverse", "begin", "end", "push_back", "size",
        "make_pair", "include", "iostream", "algorithm"
    ]

    private static let fortranKeywords: Set<String> = [
        "program", "end", "implicit", "none", "integer", "real", "character",
        "logical", "complex", "double", "precision", "print", "write", "read",
        "if", "then", "else", "elseif", "endif", "do", "while", "enddo",
        "call", "subroutine", "function", "module", "use", "contains", "result",
        "allocate", "deallocate", "allocatable", "dimension", "intent",
        "type", "select", "case", "exit", "cycle", "return", "stop",
        "parameter", "save", "data"
    ]

    // MARK: - Properties

    private var currentLanguage: Language = .python
    private var chatMessages: [(role: String, text: String)] = []
    private var isAIChatVisible = true
    private var isSettingsPanelVisible = false
    /// Assigned externally by GameViewController when embedding
    var llamaRunner: LlamaRunner?
    /// Called when the user picks a model from the model selector menu
    var onModelSelected: ((ModelSlot) -> Void)?

    // MARK: - UI Components

    // Toolbar
    private let toolbar = UIView()
    private let languageControl = UISegmentedControl(items: ["Python", "C", "C++", "Fortran"])
    private let runButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let templatesButton = UIButton(type: .system)
    private let aiToggleButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)

    // Editor
    private let editorContainer = UIView()
    private let gutterView = UIView()
    private let lineNumberLabel = UILabel()
    private let codeTextView = UITextView()

    // AI Chat (below code editor in left panel)
    private let aiChatContainer = UIView()
    private let chatTitleLabel = UILabel()
    private let modelSelectorButton = UIButton(type: .system)
    private let chatScrollView = UIScrollView()
    private let chatStackView = UIStackView()
    private let chatInputField = UITextField()
    private let chatSendButton = UIButton(type: .system)
    private var aiChatHeightConstraint: NSLayoutConstraint!

    // Output panel (right side)
    private let outputPanel = UIView()
    private let outputWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.layer.cornerRadius = 8
        wv.clipsToBounds = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()
    private let outputImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()
    private let outputPlaceholderLabel: UILabel = {
        let l = UILabel()
        l.text = "Output will appear here"
        l.textColor = UIColor(red: 0.400, green: 0.420, blue: 0.502, alpha: 1.0)
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Terminal (text only)
    private let terminalContainer = UIView()
    private let terminalTitleBar = UIView()
    private let terminalTitleLabel = UILabel()
    private let terminalTextView = UITextView()
    private var terminalHeightConstraint: NSLayoutConstraint!
    private let terminalDragHandle = UIView()

    // Settings panel (slides in from right)
    private let settingsPanel = UIView()
    private var settingsPanelTrailingConstraint: NSLayoutConstraint!
    private let qualitySegmented = UISegmentedControl(items: ["Low 480p", "Med 720p", "High 1080p"])
    private let fpsSegmented = UISegmentedControl(items: ["15", "24", "30"])

    // Layout
    private let leftPanel = UIView()
    private let topStack = UIStackView()
    private let mainStack = UIStackView()
    private var outputPanelWidthConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EditorTheme.background
        setupToolbar()
        setupEditor()
        setupAIChat()
        setupOutputPanel()
        setupTerminal()
        setupSettingsPanel()
        setupLayout()
        loadDefaultCode()
    }

    // MARK: - Setup Toolbar

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = EditorTheme.background.withAlphaComponent(0.95)

        languageControl.selectedSegmentIndex = 0
        languageControl.backgroundColor = EditorTheme.gutterBg
        languageControl.selectedSegmentTintColor = UIColor.systemBlue.withAlphaComponent(0.5)
        languageControl.setTitleTextAttributes([.foregroundColor: EditorTheme.foreground], for: .normal)
        languageControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        languageControl.addTarget(self, action: #selector(languageChanged), for: .valueChanged)
        languageControl.translatesAutoresizingMaskIntoConstraints = false

        var runConfig = UIButton.Configuration.filled()
        runConfig.image = UIImage(systemName: "play.fill")
        runConfig.title = "Run"
        runConfig.imagePadding = 6
        runConfig.baseBackgroundColor = .systemGreen
        runConfig.baseForegroundColor = .white
        runConfig.cornerStyle = .capsule
        runConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        runButton.configuration = runConfig
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        runButton.translatesAutoresizingMaskIntoConstraints = false

        var clearConfig = UIButton.Configuration.plain()
        clearConfig.image = UIImage(systemName: "trash")
        clearConfig.baseForegroundColor = EditorTheme.foreground
        clearButton.configuration = clearConfig
        clearButton.addTarget(self, action: #selector(clearTerminal), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        var templatesConfig = UIButton.Configuration.plain()
        templatesConfig.image = UIImage(systemName: "doc.text")
        templatesConfig.title = "Templates"
        templatesConfig.imagePadding = 4
        templatesConfig.baseForegroundColor = .systemOrange
        templatesButton.configuration = templatesConfig
        templatesButton.addTarget(self, action: #selector(templatesTapped), for: .touchUpInside)
        templatesButton.translatesAutoresizingMaskIntoConstraints = false

        var aiConfig = UIButton.Configuration.plain()
        aiConfig.image = UIImage(systemName: "brain.head.profile")
        aiConfig.title = "AI Assist"
        aiConfig.imagePadding = 4
        aiConfig.baseForegroundColor = .systemCyan
        aiToggleButton.configuration = aiConfig
        aiToggleButton.addTarget(self, action: #selector(toggleAIChat), for: .touchUpInside)
        aiToggleButton.translatesAutoresizingMaskIntoConstraints = false

        var settingsConfig = UIButton.Configuration.plain()
        settingsConfig.image = UIImage(systemName: "gearshape.fill")
        settingsConfig.baseForegroundColor = EditorTheme.foreground
        settingsButton.configuration = settingsConfig
        settingsButton.addTarget(self, action: #selector(toggleSettingsPanel), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolbarStack = UIStackView(arrangedSubviews: [languageControl, runButton, clearButton, templatesButton, spacer, aiToggleButton, settingsButton])
        toolbarStack.axis = .horizontal
        toolbarStack.spacing = 12
        toolbarStack.alignment = .center
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(toolbarStack)
        NSLayoutConstraint.activate([
            toolbarStack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -8)
        ])
    }

    // MARK: - Setup Editor

    private func setupEditor() {
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.backgroundColor = EditorTheme.background
        editorContainer.layer.cornerRadius = 8
        editorContainer.clipsToBounds = true

        // Gutter (line numbers)
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        gutterView.backgroundColor = EditorTheme.gutterBg

        lineNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        lineNumberLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        lineNumberLabel.textColor = EditorTheme.gutterText
        lineNumberLabel.textAlignment = .right
        lineNumberLabel.numberOfLines = 0
        lineNumberLabel.text = "1"
        gutterView.addSubview(lineNumberLabel)

        // Code text view
        codeTextView.translatesAutoresizingMaskIntoConstraints = false
        codeTextView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        codeTextView.backgroundColor = EditorTheme.background
        codeTextView.textColor = EditorTheme.foreground
        codeTextView.autocorrectionType = .no
        codeTextView.autocapitalizationType = .none
        codeTextView.spellCheckingType = .no
        codeTextView.smartQuotesType = .no
        codeTextView.smartDashesType = .no
        codeTextView.smartInsertDeleteType = .no
        codeTextView.keyboardAppearance = .dark
        codeTextView.isEditable = true
        codeTextView.isScrollEnabled = true
        codeTextView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 8)
        codeTextView.delegate = self
        codeTextView.tintColor = .systemCyan

        editorContainer.addSubview(gutterView)
        editorContainer.addSubview(codeTextView)

        NSLayoutConstraint.activate([
            gutterView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            gutterView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            gutterView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: 40),

            lineNumberLabel.topAnchor.constraint(equalTo: gutterView.topAnchor, constant: 8),
            lineNumberLabel.leadingAnchor.constraint(equalTo: gutterView.leadingAnchor, constant: 2),
            lineNumberLabel.trailingAnchor.constraint(equalTo: gutterView.trailingAnchor, constant: -4),

            codeTextView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            codeTextView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            codeTextView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            codeTextView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor)
        ])
    }

    // MARK: - Setup AI Chat

    private func setupAIChat() {
        aiChatContainer.translatesAutoresizingMaskIntoConstraints = false
        aiChatContainer.backgroundColor = EditorTheme.chatBg
        aiChatContainer.layer.cornerRadius = 8
        aiChatContainer.clipsToBounds = true

        // Title
        chatTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chatTitleLabel.text = "AI Assistant"
        chatTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        chatTitleLabel.textColor = EditorTheme.foreground

        // Model selector
        var modelConfig = UIButton.Configuration.tinted()
        modelConfig.title = "No Model"
        modelConfig.image = UIImage(systemName: "cpu")
        modelConfig.imagePadding = 4
        modelConfig.baseBackgroundColor = .systemPurple
        modelConfig.baseForegroundColor = .systemPurple
        modelConfig.cornerStyle = .capsule
        modelConfig.buttonSize = .small
        modelSelectorButton.configuration = modelConfig
        modelSelectorButton.translatesAutoresizingMaskIntoConstraints = false
        modelSelectorButton.showsMenuAsPrimaryAction = true
        modelSelectorButton.menu = buildModelMenu()

        // Chat scroll area
        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.showsVerticalScrollIndicator = true
        chatScrollView.alwaysBounceVertical = true

        chatStackView.translatesAutoresizingMaskIntoConstraints = false
        chatStackView.axis = .vertical
        chatStackView.spacing = 8
        chatStackView.alignment = .fill
        chatScrollView.addSubview(chatStackView)

        // Input row
        chatInputField.translatesAutoresizingMaskIntoConstraints = false
        chatInputField.placeholder = "Ask about your code..."
        chatInputField.font = UIFont.systemFont(ofSize: 14)
        chatInputField.backgroundColor = EditorTheme.gutterBg
        chatInputField.textColor = EditorTheme.foreground
        chatInputField.layer.cornerRadius = 8
        chatInputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        chatInputField.leftViewMode = .always
        chatInputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        chatInputField.rightViewMode = .always
        chatInputField.keyboardAppearance = .dark
        chatInputField.returnKeyType = .send
        chatInputField.delegate = self

        var sendConfig = UIButton.Configuration.filled()
        sendConfig.image = UIImage(systemName: "arrow.up.circle.fill")
        sendConfig.baseBackgroundColor = .systemCyan
        sendConfig.baseForegroundColor = .white
        sendConfig.cornerStyle = .capsule
        sendConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        chatSendButton.configuration = sendConfig
        chatSendButton.addTarget(self, action: #selector(sendChatMessage), for: .touchUpInside)
        chatSendButton.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = UIStackView(arrangedSubviews: [chatInputField, chatSendButton])
        inputRow.axis = .horizontal
        inputRow.spacing = 6
        inputRow.alignment = .center
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        let chatHeaderRow = UIStackView(arrangedSubviews: [chatTitleLabel, modelSelectorButton])
        chatHeaderRow.axis = .horizontal
        chatHeaderRow.spacing = 8
        chatHeaderRow.alignment = .center
        chatHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        aiChatContainer.addSubview(chatHeaderRow)
        aiChatContainer.addSubview(chatScrollView)
        aiChatContainer.addSubview(inputRow)

        NSLayoutConstraint.activate([
            chatHeaderRow.topAnchor.constraint(equalTo: aiChatContainer.topAnchor, constant: 10),
            chatHeaderRow.leadingAnchor.constraint(equalTo: aiChatContainer.leadingAnchor, constant: 10),
            chatHeaderRow.trailingAnchor.constraint(equalTo: aiChatContainer.trailingAnchor, constant: -10),

            chatScrollView.topAnchor.constraint(equalTo: chatHeaderRow.bottomAnchor, constant: 8),
            chatScrollView.leadingAnchor.constraint(equalTo: aiChatContainer.leadingAnchor, constant: 8),
            chatScrollView.trailingAnchor.constraint(equalTo: aiChatContainer.trailingAnchor, constant: -8),
            chatScrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor, constant: -8),

            chatStackView.topAnchor.constraint(equalTo: chatScrollView.topAnchor),
            chatStackView.leadingAnchor.constraint(equalTo: chatScrollView.leadingAnchor),
            chatStackView.trailingAnchor.constraint(equalTo: chatScrollView.trailingAnchor),
            chatStackView.bottomAnchor.constraint(equalTo: chatScrollView.bottomAnchor),
            chatStackView.widthAnchor.constraint(equalTo: chatScrollView.widthAnchor),

            inputRow.leadingAnchor.constraint(equalTo: aiChatContainer.leadingAnchor, constant: 8),
            inputRow.trailingAnchor.constraint(equalTo: aiChatContainer.trailingAnchor, constant: -8),
            inputRow.bottomAnchor.constraint(equalTo: aiChatContainer.bottomAnchor, constant: -8),
            inputRow.heightAnchor.constraint(equalToConstant: 36),

            chatSendButton.widthAnchor.constraint(equalToConstant: 36),
            chatSendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: - Setup Output Panel

    private func setupOutputPanel() {
        outputPanel.translatesAutoresizingMaskIntoConstraints = false
        outputPanel.backgroundColor = EditorTheme.terminalBg
        outputPanel.layer.cornerRadius = 8
        outputPanel.clipsToBounds = true

        outputPanel.addSubview(outputPlaceholderLabel)
        outputPanel.addSubview(outputWebView)
        outputPanel.addSubview(outputImageView)

        // Initially hide everything except placeholder
        outputWebView.isHidden = true
        outputImageView.isHidden = true

        NSLayoutConstraint.activate([
            outputWebView.topAnchor.constraint(equalTo: outputPanel.topAnchor),
            outputWebView.leadingAnchor.constraint(equalTo: outputPanel.leadingAnchor),
            outputWebView.trailingAnchor.constraint(equalTo: outputPanel.trailingAnchor),
            outputWebView.bottomAnchor.constraint(equalTo: outputPanel.bottomAnchor),

            outputImageView.topAnchor.constraint(equalTo: outputPanel.topAnchor, constant: 4),
            outputImageView.leadingAnchor.constraint(equalTo: outputPanel.leadingAnchor, constant: 4),
            outputImageView.trailingAnchor.constraint(equalTo: outputPanel.trailingAnchor, constant: -4),
            outputImageView.bottomAnchor.constraint(equalTo: outputPanel.bottomAnchor, constant: -4),

            outputPlaceholderLabel.centerXAnchor.constraint(equalTo: outputPanel.centerXAnchor),
            outputPlaceholderLabel.centerYAnchor.constraint(equalTo: outputPanel.centerYAnchor),
        ])
    }

    // MARK: - Setup Terminal

    private func setupTerminal() {
        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.backgroundColor = EditorTheme.terminalBg
        terminalContainer.layer.cornerRadius = 8
        terminalContainer.clipsToBounds = true

        // Drag handle for resizing
        terminalDragHandle.translatesAutoresizingMaskIntoConstraints = false
        terminalDragHandle.backgroundColor = EditorTheme.gutterText.withAlphaComponent(0.3)
        terminalDragHandle.layer.cornerRadius = 2

        // Title bar
        terminalTitleBar.translatesAutoresizingMaskIntoConstraints = false
        terminalTitleBar.backgroundColor = EditorTheme.gutterBg

        terminalTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        terminalTitleLabel.text = "  Terminal"
        terminalTitleLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        terminalTitleLabel.textColor = EditorTheme.gutterText

        terminalTitleBar.addSubview(terminalDragHandle)
        terminalTitleBar.addSubview(terminalTitleLabel)

        // Terminal output (text only — charts/images go to output panel)
        terminalTextView.translatesAutoresizingMaskIntoConstraints = false
        terminalTextView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalTextView.backgroundColor = EditorTheme.terminalBg
        terminalTextView.textColor = EditorTheme.terminalText
        terminalTextView.isEditable = false
        terminalTextView.isScrollEnabled = true
        terminalTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        terminalTextView.text = "$ Ready.\n"

        terminalContainer.addSubview(terminalTitleBar)
        terminalContainer.addSubview(terminalTextView)

        NSLayoutConstraint.activate([
            terminalTitleBar.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            terminalTitleBar.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminalTitleBar.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            terminalTitleBar.heightAnchor.constraint(equalToConstant: 28),

            terminalDragHandle.centerXAnchor.constraint(equalTo: terminalTitleBar.centerXAnchor),
            terminalDragHandle.topAnchor.constraint(equalTo: terminalTitleBar.topAnchor, constant: 4),
            terminalDragHandle.widthAnchor.constraint(equalToConstant: 36),
            terminalDragHandle.heightAnchor.constraint(equalToConstant: 4),

            terminalTitleLabel.leadingAnchor.constraint(equalTo: terminalTitleBar.leadingAnchor, constant: 8),
            terminalTitleLabel.centerYAnchor.constraint(equalTo: terminalTitleBar.centerYAnchor),

            // Text view fills below title bar
            terminalTextView.topAnchor.constraint(equalTo: terminalTitleBar.bottomAnchor),
            terminalTextView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminalTextView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            terminalTextView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
        ])

        // Pan gesture for resizing
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTerminalDrag(_:)))
        terminalTitleBar.addGestureRecognizer(pan)
    }

    // MARK: - Setup Settings Panel

    private func setupSettingsPanel() {
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.backgroundColor = EditorTheme.chatBg
        settingsPanel.layer.cornerRadius = 12
        settingsPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        settingsPanel.clipsToBounds = true
        settingsPanel.layer.shadowColor = UIColor.black.cgColor
        settingsPanel.layer.shadowOpacity = 0.4
        settingsPanel.layer.shadowRadius = 10

        let titleLabel = UILabel()
        titleLabel.text = "Manim Settings"
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = EditorTheme.foreground
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let qualityLabel = UILabel()
        qualityLabel.text = "Quality"
        qualityLabel.font = .systemFont(ofSize: 13, weight: .medium)
        qualityLabel.textColor = EditorTheme.gutterText
        qualityLabel.translatesAutoresizingMaskIntoConstraints = false

        qualitySegmented.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "manim_quality")
        qualitySegmented.backgroundColor = EditorTheme.gutterBg
        qualitySegmented.selectedSegmentTintColor = UIColor.systemPurple.withAlphaComponent(0.5)
        qualitySegmented.setTitleTextAttributes([.foregroundColor: EditorTheme.foreground, .font: UIFont.systemFont(ofSize: 11)], for: .normal)
        qualitySegmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .selected)
        qualitySegmented.addTarget(self, action: #selector(manimQualityChanged), for: .valueChanged)
        qualitySegmented.translatesAutoresizingMaskIntoConstraints = false

        let fpsLabel = UILabel()
        fpsLabel.text = "FPS"
        fpsLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fpsLabel.textColor = EditorTheme.gutterText
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false

        let savedFPS = UserDefaults.standard.integer(forKey: "manim_fps")
        fpsSegmented.selectedSegmentIndex = savedFPS
        fpsSegmented.backgroundColor = EditorTheme.gutterBg
        fpsSegmented.selectedSegmentTintColor = UIColor.systemPurple.withAlphaComponent(0.5)
        fpsSegmented.setTitleTextAttributes([.foregroundColor: EditorTheme.foreground], for: .normal)
        fpsSegmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        fpsSegmented.addTarget(self, action: #selector(manimFPSChanged), for: .valueChanged)
        fpsSegmented.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        var closeConfig = UIButton.Configuration.plain()
        closeConfig.image = UIImage(systemName: "xmark.circle.fill")
        closeConfig.baseForegroundColor = EditorTheme.gutterText
        closeButton.configuration = closeConfig
        closeButton.addTarget(self, action: #selector(toggleSettingsPanel), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        settingsPanel.addSubview(titleLabel)
        settingsPanel.addSubview(closeButton)
        settingsPanel.addSubview(qualityLabel)
        settingsPanel.addSubview(qualitySegmented)
        settingsPanel.addSubview(fpsLabel)
        settingsPanel.addSubview(fpsSegmented)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: settingsPanel.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -12),

            qualityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            qualityLabel.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),

            qualitySegmented.topAnchor.constraint(equalTo: qualityLabel.bottomAnchor, constant: 8),
            qualitySegmented.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),
            qualitySegmented.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -16),

            fpsLabel.topAnchor.constraint(equalTo: qualitySegmented.bottomAnchor, constant: 20),
            fpsLabel.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),

            fpsSegmented.topAnchor.constraint(equalTo: fpsLabel.bottomAnchor, constant: 8),
            fpsSegmented.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),
            fpsSegmented.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -16),
        ])
    }

    @objc private func manimQualityChanged() {
        UserDefaults.standard.set(qualitySegmented.selectedSegmentIndex, forKey: "manim_quality")
    }

    @objc private func manimFPSChanged() {
        UserDefaults.standard.set(fpsSegmented.selectedSegmentIndex, forKey: "manim_fps")
    }

    // MARK: - Layout

    private func setupLayout() {
        // Left panel: code editor (flex) + AI chat (collapsible, below editor)
        leftPanel.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.addSubview(editorContainer)
        leftPanel.addSubview(aiChatContainer)

        aiChatHeightConstraint = aiChatContainer.heightAnchor.constraint(equalToConstant: 150)
        aiChatHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            editorContainer.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: aiChatContainer.topAnchor, constant: -2),

            aiChatContainer.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            aiChatContainer.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            aiChatContainer.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            aiChatHeightConstraint,
        ])

        // Top section: leftPanel (55%) | outputPanel (45%)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.axis = .horizontal
        topStack.spacing = 2
        topStack.distribution = .fill
        topStack.addArrangedSubview(leftPanel)
        topStack.addArrangedSubview(outputPanel)

        outputPanelWidthConstraint = outputPanel.widthAnchor.constraint(equalTo: topStack.widthAnchor, multiplier: 0.45)
        outputPanelWidthConstraint.isActive = true

        // Main vertical stack: toolbar + topStack + terminal
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 2
        mainStack.addArrangedSubview(toolbar)
        mainStack.addArrangedSubview(topStack)
        mainStack.addArrangedSubview(terminalContainer)

        view.addSubview(mainStack)

        // Settings panel overlay (slides in from right edge)
        view.addSubview(settingsPanel)
        settingsPanelTrailingConstraint = settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 260)

        terminalHeightConstraint = terminalContainer.heightAnchor.constraint(equalToConstant: 150)
        terminalHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbar.heightAnchor.constraint(equalToConstant: 48),
            terminalHeightConstraint,

            // Settings panel
            settingsPanel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            settingsPanel.bottomAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: -8),
            settingsPanel.widthAnchor.constraint(equalToConstant: 250),
            settingsPanelTrailingConstraint,
        ])
    }

    // MARK: - Default Code

    private func loadDefaultCode() {
        codeTextView.text = currentLanguage.defaultCode
        applySyntaxHighlighting()
        updateLineNumbers()
    }

    // MARK: - Actions

    @objc private func languageChanged() {
        currentLanguage = Language(rawValue: languageControl.selectedSegmentIndex) ?? .python
        loadDefaultCode()
    }

    @objc private func runTapped() {
        guard let code = codeTextView.text, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendToTerminal("$ No code to run.\n", isError: true)
            return
        }

        runButton.isEnabled = false
        appendToTerminal("$ Running \(currentLanguage.title)...\n", isError: false)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let start = CFAbsoluteTimeGetCurrent()
            var output = ""
            var hasError = false
            var resultImagePath: String?

            switch self.currentLanguage {
            case .python:
                let result = PythonRuntime.shared.execute(code: code)
                output = result.output.isEmpty ? "(no output)" : result.output
                hasError = output.lowercased().contains("error") || output.contains("Traceback")
                resultImagePath = result.imagePath

            case .c:
                let result = CRuntime.shared.execute(code)
                if result.success {
                    output = result.output.isEmpty ? "(no output)" : result.output
                } else {
                    output = "Error: \(result.error ?? "unknown")\n\(result.output)"
                    hasError = true
                }

            case .cpp:
                let result = CppRuntime.shared.execute(code)
                if result.success {
                    output = result.output.isEmpty ? "(no output)" : result.output
                } else {
                    output = "Error: \(result.error ?? "unknown")\n\(result.output)"
                    hasError = true
                }

            case .fortran:
                let result = FortranRuntime.shared.execute(code)
                if result.success {
                    output = result.output.isEmpty ? "(no output)" : result.output
                } else {
                    output = "Error: \(result.error ?? "unknown")\n\(result.output)"
                    hasError = true
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - start

            DispatchQueue.main.async {
                self.runButton.isEnabled = true
                self.showImageOutput(path: resultImagePath)
                self.appendToTerminal("> \(output)\n", isError: hasError)
                let status = hasError ? "completed with errors" : "completed"
                self.appendToTerminal("$ Execution \(status) in \(String(format: "%.3f", elapsed))s\n", isError: false)
            }
        }
    }

    @objc private func clearTerminal() {
        terminalTextView.text = "$ Ready.\n"
        terminalTextView.textColor = EditorTheme.terminalText

        // Clear output panel
        outputImageView.isHidden = true
        outputImageView.image = nil
        outputWebView.isHidden = true
        outputPlaceholderLabel.isHidden = false

        terminalHeightConstraint.constant = 150
        view.layoutIfNeeded()
    }

    @objc private func toggleAIChat() {
        isAIChatVisible.toggle()
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.aiChatContainer.isHidden = !self.isAIChatVisible
            self.aiChatHeightConstraint.isActive = self.isAIChatVisible
            self.leftPanel.layoutIfNeeded()
        }
    }

    @objc private func toggleSettingsPanel() {
        isSettingsPanelVisible.toggle()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseInOut) {
            self.settingsPanelTrailingConstraint.constant = self.isSettingsPanelVisible ? 0 : 260
            self.view.layoutIfNeeded()
        }
    }

    @objc private func sendChatMessage() {
        guard let text = chatInputField.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatInputField.text = ""
        chatInputField.resignFirstResponder()

        addChatBubble(text: text, isUser: true)

        let code = codeTextView.text ?? ""
        let langName = currentLanguage.title.lowercased()
        let prompt = "Here is my \(langName) code:\n```\(langName)\n\(code)\n```\n\nUser question: \(text)"

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "You are a helpful coding assistant integrated with a code editor. Answer concisely about the user's code. When suggesting code changes, ALWAYS include the complete updated code in a ```\(langName) code block so the user can apply it directly to the editor. Keep responses under 300 words."),
            ChatMessage(role: .user, content: prompt)
        ]

        guard let runner = llamaRunner else {
            addChatBubble(text: "No model loaded. Load a model from the Chat tab first.", isUser: false)
            return
        }

        var accumulated = ""
        let bubbleLabel = addChatBubble(text: "Thinking...", isUser: false)

        runner.generate(messages: messages, maxTokens: 512, onToken: { [weak self] token in
            accumulated += token
            DispatchQueue.main.async {
                bubbleLabel.text = accumulated
                self?.scrollChatToBottom()
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let full):
                    bubbleLabel.text = full
                    // If response contains a code block, add "Apply to Editor" button
                    self.addApplyButtonIfCodeBlock(full, below: bubbleLabel)
                case .failure(let error):
                    bubbleLabel.text = "Error: \(error.localizedDescription)"
                }
                self.scrollChatToBottom()
            }
        })
    }

    // MARK: - Apply Code from AI Chat

    private func extractCodeBlock(_ text: String) -> String? {
        // Match ```language\n...\n``` or ```\n...\n```
        let pattern = "```(?:\\w+)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let codeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addApplyButtonIfCodeBlock(_ text: String, below label: UILabel) {
        guard let code = extractCodeBlock(text) else { return }

        let applyButton = UIButton(type: .system)
        applyButton.setTitle("  Apply to Editor", for: .normal)
        applyButton.setImage(UIImage(systemName: "arrow.right.doc.on.clipboard"), for: .normal)
        applyButton.tintColor = .systemBlue
        applyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        applyButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        applyButton.layer.cornerRadius = 8
        applyButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        applyButton.translatesAutoresizingMaskIntoConstraints = false

        // Store code in tag via objc associated object
        objc_setAssociatedObject(applyButton, "codeBlock", code, .OBJC_ASSOCIATION_RETAIN)
        applyButton.addTarget(self, action: #selector(applyCodeToEditor(_:)), for: .touchUpInside)

        // Insert button into chat stack after the label's parent
        if let parentStack = label.superview as? UIStackView {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(applyButton)
            NSLayoutConstraint.activate([
                applyButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                applyButton.topAnchor.constraint(equalTo: container.topAnchor),
                applyButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            parentStack.addArrangedSubview(container)
        } else {
            // Fallback: add to chat stack directly
            chatStackView.addArrangedSubview(applyButton)
        }
    }

    @objc private func applyCodeToEditor(_ sender: UIButton) {
        guard let code = objc_getAssociatedObject(sender, "codeBlock") as? String else { return }
        codeTextView.text = code
        applySyntaxHighlighting()
        updateLineNumbers()

        // Visual feedback
        sender.setTitle("  Applied!", for: .normal)
        sender.setImage(UIImage(systemName: "checkmark"), for: .normal)
        sender.tintColor = .systemGreen
        sender.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
        sender.isEnabled = false
    }

    // MARK: - Terminal Resize

    @objc private func handleTerminalDrag(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        if gesture.state == .changed {
            let newHeight = terminalHeightConstraint.constant - translation.y
            terminalHeightConstraint.constant = max(60, min(newHeight, view.bounds.height * 0.6))
            gesture.setTranslation(.zero, in: view)
        }
    }

    // MARK: - Helpers

    private func appendToTerminal(_ text: String, isError: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: isError ? EditorTheme.terminalError : EditorTheme.terminalText
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let current = terminalTextView.attributedText.mutableCopy() as! NSMutableAttributedString
        current.append(attributed)
        terminalTextView.attributedText = current
        let bottom = NSRange(location: current.length - 1, length: 1)
        terminalTextView.scrollRangeToVisible(bottom)
    }

    @discardableResult
    private func addChatBubble(text: String, isUser: Bool) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = EditorTheme.foreground
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        let bubble = UIView()
        bubble.backgroundColor = isUser ? EditorTheme.userBubble : EditorTheme.aiBubble
        bubble.layer.cornerRadius = 10
        bubble.translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)
        ])

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(bubble)

        // Align bubble to right for user, left for AI
        if isUser {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: wrapper.topAnchor),
                bubble.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                bubble.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor, multiplier: 0.9)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: wrapper.topAnchor),
                bubble.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                bubble.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor, multiplier: 0.9)
            ])
        }

        chatStackView.addArrangedSubview(wrapper)
        scrollChatToBottom()
        return label
    }

    private func scrollChatToBottom() {
        chatScrollView.layoutIfNeeded()
        let bottomOffset = CGPoint(x: 0, y: max(0, chatScrollView.contentSize.height - chatScrollView.bounds.height))
        chatScrollView.setContentOffset(bottomOffset, animated: true)
    }

    // MARK: - Line Numbers

    private func updateLineNumbers() {
        let text = codeTextView.text ?? ""
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        lineNumberLabel.text = (1...lineCount).map { String($0) }.joined(separator: "\n")

        // Sync gutter scroll offset
        let yOffset = codeTextView.contentOffset.y
        lineNumberLabel.transform = CGAffineTransform(translationX: 0, y: -yOffset + 8)
    }

    // MARK: - Syntax Highlighting

    private func applySyntaxHighlighting() {
        guard let text = codeTextView.text, !text.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)

        // Base style
        attributed.addAttributes([
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: EditorTheme.foreground
        ], range: fullRange)

        let keywords: Set<String>
        let commentPrefix: String
        let hasPreprocessor: Bool

        switch currentLanguage {
        case .python:
            keywords = Self.pythonKeywords
            commentPrefix = "#"
            hasPreprocessor = false
        case .c:
            keywords = Self.cKeywords
            commentPrefix = "//"
            hasPreprocessor = true
        case .cpp:
            keywords = Self.cppKeywords
            commentPrefix = "//"
            hasPreprocessor = true
        case .fortran:
            keywords = Self.fortranKeywords
            commentPrefix = "!"
            hasPreprocessor = false
        }

        let nsText = text as NSString

        // 1. Comments (line-based)
        let commentPattern = "\(NSRegularExpression.escapedPattern(for: commentPrefix)).*"
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: []) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: EditorTheme.comment, range: match.range)
            }
        }

        // 2. Strings (double and single quoted)
        if let regex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", options: []) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: EditorTheme.string, range: match.range)
            }
        }

        // 3. Numbers
        if let regex = try? NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: []) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: EditorTheme.number, range: match.range)
            }
        }

        // 4. Keywords
        for keyword in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                for match in regex.matches(in: text, options: [], range: fullRange) {
                    attributed.addAttribute(.foregroundColor, value: EditorTheme.keyword, range: match.range)
                }
            }
        }

        // 5. Preprocessor directives (#include, #define) for C
        if hasPreprocessor {
            if let regex = try? NSRegularExpression(pattern: "#\\w+", options: []) {
                for match in regex.matches(in: text, options: [], range: fullRange) {
                    attributed.addAttribute(.foregroundColor, value: EditorTheme.keyword, range: match.range)
                }
            }
        }

        // Preserve selection
        let selectedRange = codeTextView.selectedRange
        codeTextView.attributedText = attributed
        codeTextView.selectedRange = selectedRange
    }

    // MARK: - Templates

    @objc private func templatesTapped() {
        let vc = TemplatePickerViewController()
        vc.templates = Self.templates
        vc.onSelect = { [weak self] template in
            guard let self else { return }
            self.currentLanguage = template.language
            self.languageControl.selectedSegmentIndex = template.language.rawValue
            // Dedent the template code (remove leading 8-space indent from multiline strings)
            let lines = template.code.split(separator: "\n", omittingEmptySubsequences: false)
            let dedented = lines.map { line in
                var s = String(line)
                if s.hasPrefix("        ") { s = String(s.dropFirst(8)) }
                return s
            }.joined(separator: "\n")
            self.codeTextView.text = dedented
            self.applySyntaxHighlighting()
            self.updateLineNumbers()
        }
        vc.modalPresentationStyle = .popover
        vc.preferredContentSize = CGSize(width: 400, height: 500)
        if let popover = vc.popoverPresentationController {
            popover.sourceView = templatesButton
            popover.sourceRect = templatesButton.bounds
            popover.permittedArrowDirections = .up
        }
        present(vc, animated: true)
    }

    // MARK: - Model Selector

    private func buildModelMenu() -> UIMenu {
        let actions = ModelSlot.allCases.map { slot in
            UIAction(title: slot.title, subtitle: slot.subtitle) { [weak self] _ in
                self?.onModelSelected?(slot)
            }
        }
        return UIMenu(title: "Select Model", children: actions)
    }

    func updateModelName(_ name: String) {
        var config = modelSelectorButton.configuration ?? UIButton.Configuration.tinted()
        config.title = name
        modelSelectorButton.configuration = config
    }

    // MARK: - File Loading

    private var currentFileURL: URL?
    private var currentOutputPath: String?

    func loadFile(url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "py": currentLanguage = .python
        case "c", "h": currentLanguage = .c
        case "cpp", "cc", "cxx", "hpp": currentLanguage = .cpp
        case "f90", "f95", "f", "for": currentLanguage = .fortran
        default: break
        }
        languageControl.selectedSegmentIndex = currentLanguage.rawValue
        codeTextView.text = contents
        applySyntaxHighlighting()
        updateLineNumbers()
        currentFileURL = url
        appendToTerminal("$ Loaded: \(url.lastPathComponent)\n", isError: false)
    }

    func insertCode(_ code: String, language: String) {
        switch language.lowercased() {
        case "c": currentLanguage = .c
        case "cpp", "c++": currentLanguage = .cpp
        case "fortran", "f90": currentLanguage = .fortran
        default: currentLanguage = .python
        }
        languageControl.selectedSegmentIndex = currentLanguage.rawValue
        codeTextView.text = code
        applySyntaxHighlighting()
        updateLineNumbers()
        currentFileURL = nil
    }

    func saveCurrentFile() {
        guard let url = currentFileURL, let text = codeTextView.text else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        appendToTerminal("$ Saved: \(url.lastPathComponent)\n", isError: false)
    }

    // MARK: - Image Output

    @objc private func exportOutput() {
        guard let path = currentOutputPath, FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        ac.popoverPresentationController?.sourceView = view
        ac.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 50, width: 0, height: 0)
        present(ac, animated: true)
    }

    private func showImageOutput(path: String?) {
        // Hide both first
        outputImageView.isHidden = true
        outputImageView.image = nil
        outputWebView.isHidden = true
        outputPlaceholderLabel.isHidden = false
        currentOutputPath = path

        guard let path = path, !path.isEmpty else {
            appendToTerminal("$ [output] No image path\n", isError: false)
            return
        }
        let exists = FileManager.default.fileExists(atPath: path)
        appendToTerminal("$ [output] \(URL(fileURLWithPath: path).lastPathComponent) exists=\(exists)\n", isError: false)
        guard exists else { return }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if ext == "html" {
            outputPlaceholderLabel.isHidden = true
            outputWebView.isHidden = false
            outputWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if ext == "gif" {
            // Animated GIF (manim) — display in WKWebView for animation support
            outputPlaceholderLabel.isHidden = true
            outputWebView.isHidden = false
            let gifHTML = """
            <!DOCTYPE html>
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{margin:0;background:#000;display:flex;align-items:center;justify-content:center;height:100vh}
            img{max-width:100%;max-height:100%;border-radius:8px;image-rendering:auto}</style></head>
            <body><img src="\(url.lastPathComponent)"></body></html>
            """
            let htmlURL = url.deletingLastPathComponent().appendingPathComponent("_gif_viewer.html")
            try? gifHTML.write(to: htmlURL, atomically: true, encoding: .utf8)
            outputWebView.loadFileURL(htmlURL, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if ["mp4", "mov", "webm", "m4v"].contains(ext) {
            // Video output — play in WKWebView with HTML5 video
            outputPlaceholderLabel.isHidden = true
            outputWebView.isHidden = false
            let videoHTML = """
            <!DOCTYPE html>
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
            *{margin:0;padding:0;box-sizing:border-box}
            body{background:#1e1e2e;display:flex;flex-direction:column;height:100vh;font-family:-apple-system,sans-serif}
            .player{flex:1;display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden}
            video{max-width:100%;max-height:100%;border-radius:8px;background:#000}
            .controls{display:flex;align-items:center;gap:8px;padding:8px 12px;background:#313244}
            .btn{background:none;border:none;color:#cdd6f4;font-size:18px;cursor:pointer;padding:4px 8px;border-radius:4px}
            .btn:active{background:rgba(255,255,255,0.1)}
            .progress{flex:1;height:4px;background:#45475a;border-radius:2px;cursor:pointer;position:relative}
            .progress-fill{height:100%;background:#89b4fa;border-radius:2px;width:0%;transition:none}
            .time{color:#a6adc8;font-size:11px;min-width:40px;text-align:center}
            .speed{color:#a6adc8;font-size:11px;cursor:pointer;padding:2px 6px;border:1px solid #45475a;border-radius:4px}
            </style></head>
            <body>
            <div class="player"><video id="v" playsinline preload="auto" muted>
            <source src="\(url.lastPathComponent)" type="video/mp4"></video></div>
            <div class="controls">
            <button class="btn" id="playBtn" onclick="togglePlay()">▶</button>
            <span class="time" id="curTime">0:00</span>
            <div class="progress" id="prog" onclick="seek(event)"><div class="progress-fill" id="progFill"></div></div>
            <span class="time" id="durTime">0:00</span>
            <span class="speed" id="speedBtn" onclick="cycleSpeed()">1x</span>
            <button class="btn" onclick="toggleLoop()">🔁</button>
            </div>
            <script>
            const v=document.getElementById('v'),pb=document.getElementById('playBtn'),
            pf=document.getElementById('progFill'),ct=document.getElementById('curTime'),
            dt=document.getElementById('durTime'),sb=document.getElementById('speedBtn');
            let speeds=[0.5,1,1.5,2],si=1;
            v.loop=true;v.muted=true;
            v.addEventListener('loadeddata',()=>{v.play();pb.textContent='⏸';dt.textContent=fmt(v.duration)});
            v.addEventListener('timeupdate',()=>{if(v.duration){pf.style.width=(v.currentTime/v.duration*100)+'%';ct.textContent=fmt(v.currentTime)}});
            v.addEventListener('ended',()=>{if(!v.loop){pb.textContent='▶'}});
            function togglePlay(){if(v.paused){v.play();pb.textContent='⏸'}else{v.pause();pb.textContent='▶'}}
            function seek(e){const r=e.target.getBoundingClientRect();v.currentTime=(e.clientX-r.left)/r.width*v.duration}
            function cycleSpeed(){si=(si+1)%speeds.length;v.playbackRate=speeds[si];sb.textContent=speeds[si]+'x'}
            function toggleLoop(){v.loop=!v.loop}
            function fmt(s){const m=Math.floor(s/60),sec=Math.floor(s%60);return m+':'+(sec<10?'0':'')+sec}
            </script>
            </body></html>
            """
            let htmlURL = url.deletingLastPathComponent().appendingPathComponent("_video_player.html")
            try? videoHTML.write(to: htmlURL, atomically: true, encoding: .utf8)
            outputWebView.loadFileURL(htmlURL, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if ["png", "jpg", "jpeg"].contains(ext) {
            if let image = UIImage(contentsOfFile: path) {
                outputPlaceholderLabel.isHidden = true
                outputImageView.image = image
                outputImageView.isHidden = false
            }
        }
    }
}

// MARK: - UITextViewDelegate

extension CodeEditorViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        applySyntaxHighlighting()
        updateLineNumbers()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === codeTextView {
            updateLineNumbers()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView === codeTextView else { return true }

        // Tab key inserts 4 spaces
        if text == "\t" {
            let spaces = "    "
            let nsText = (textView.text as NSString).replacingCharacters(in: range, with: spaces)
            textView.text = nsText
            textView.selectedRange = NSRange(location: range.location + 4, length: 0)
            applySyntaxHighlighting()
            updateLineNumbers()
            return false
        }

        // Auto-indent after colon or opening brace
        if text == "\n" {
            let nsText = textView.text as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = nsText.substring(with: lineRange)

            // Compute current indentation
            var indent = ""
            for ch in currentLine {
                if ch == " " { indent += " " }
                else { break }
            }

            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":") || trimmed.hasSuffix("{") {
                indent += "    "
            }

            let replacement = "\n\(indent)"
            let newText = nsText.replacingCharacters(in: range, with: replacement)
            textView.text = newText
            textView.selectedRange = NSRange(location: range.location + replacement.count, length: 0)
            applySyntaxHighlighting()
            updateLineNumbers()
            return false
        }

        return true
    }
}

// MARK: - UITextFieldDelegate

extension CodeEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === chatInputField {
            sendChatMessage()
        }
        return true
    }
}

// MARK: - Template Picker

/// Popover/modal that lists templates grouped by category.
final class TemplatePickerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    var templates: [CodeEditorViewController.Template] = []
    var onSelect: ((CodeEditorViewController.Template) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var grouped: [(category: String, items: [CodeEditorViewController.Template])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildGrouped()
        setupTable()
    }

    private func buildGrouped() {
        var dict: [String: [CodeEditorViewController.Template]] = [:]
        var order: [String] = []
        for t in templates {
            if dict[t.category] == nil { order.append(t.category) }
            dict[t.category, default: []].append(t)
        }
        grouped = order.map { (category: $0, items: dict[$0]!) }
    }

    private func setupTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        let titleLabel = UILabel()
        titleLabel.text = "Templates"
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { grouped.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { grouped[section].category }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { grouped[section].items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = grouped[indexPath.section].items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.language.title
        config.image = UIImage(systemName: item.icon)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = grouped[indexPath.section].items[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onSelect?(item)
        }
    }
}
