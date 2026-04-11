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
        // ── numpy ──
        Template(title: "numpy: Linear Algebra", icon: "function", category: "NumPy", language: .python, code: """
        import numpy as np
        A = np.array([[3, 2, -1], [2, -2, 4], [-1, 0.5, -1]])
        b = np.array([1, -2, 0])
        x = np.linalg.solve(A, b)
        print("Solution:", x)
        evals, evecs = np.linalg.eig(A)
        print("Eigenvalues:", evals.round(4))
        print("Determinant:", round(np.linalg.det(A), 4))
        """),

        // ── scipy ──
        Template(title: "scipy: Optimize", icon: "chart.line.downtrend.xyaxis", category: "SciPy", language: .python, code: """
        import numpy as np
        from scipy.optimize import minimize
        def f(x):
            return (x[0]-1)**2 + (x[1]-2)**2 + np.sin(x[0]*x[1])
        result = minimize(f, [0, 0], method='Nelder-Mead')
        print(f"Minimum at: {result.x.round(4)}")
        print(f"f(min) = {result.fun:.6f}")
        print(f"Iterations: {result.nit}")
        """),

        Template(title: "scipy: FFT Spectrum", icon: "waveform", category: "SciPy", language: .python, code: """
        import numpy as np
        from scipy.fft import rfft, rfftfreq
        t = np.linspace(0, 1, 1000)
        signal = np.sin(2*np.pi*5*t) + 0.5*np.sin(2*np.pi*12*t)
        freqs = rfftfreq(len(t), 1/1000)
        fft_vals = np.abs(rfft(signal))
        top3 = freqs[np.argsort(fft_vals)[-3:]]
        print(f"Detected frequencies: {sorted(top3.round(1))} Hz")
        print(f"Expected: [5.0, 12.0] Hz")
        """),

        Template(title: "scipy: Statistics", icon: "chart.bar.fill", category: "SciPy", language: .python, code: """
        import numpy as np
        from scipy.stats import ttest_1samp, norm
        np.random.seed(42)
        data = np.random.randn(1000) + 0.1
        t_stat, p_val = ttest_1samp(data, 0)
        print(f"Sample mean: {data.mean():.4f}")
        print(f"t-statistic: {t_stat:.4f}")
        print(f"p-value: {p_val:.4f}")
        print(f"Significant (p<0.05): {p_val < 0.05}")
        """),

        // ── sympy ──
        Template(title: "sympy: Solve & Calculus", icon: "x.squareroot", category: "SymPy", language: .python, code: """
        from sympy import symbols, solve, diff, integrate, sin, cos, exp, oo, pi, series
        x = symbols('x')

        roots = solve(x**3 - 6*x**2 + 11*x - 6, x)
        print(f"Roots of x^3-6x^2+11x-6=0: {roots}")

        deriv = diff(sin(x**2) * exp(x), x)
        print(f"d/dx[sin(x^2)*e^x] = {deriv}")

        integral = integrate(1/(1+x**2), (x, 0, oo))
        print(f"integral_0^inf 1/(1+x^2)dx = {integral}")

        taylor = series(cos(x), x, 0, n=8)
        print(f"cos(x) Taylor = {taylor}")
        """),

        // ── sklearn ──
        Template(title: "sklearn: RandomForest", icon: "tree.fill", category: "ML", language: .python, code: """
        import numpy as np
        from sklearn.datasets import make_classification
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import accuracy_score, confusion_matrix

        X, y = make_classification(n_samples=200, n_features=4, random_state=42)
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42)

        rf = RandomForestClassifier(n_estimators=10, max_depth=5, random_state=42)
        rf.fit(X_train, y_train)
        y_pred = rf.predict(X_test)

        print(f"Accuracy: {accuracy_score(y_test, y_pred):.3f}")
        print(f"Confusion Matrix:\\n{confusion_matrix(y_test, y_pred)}")
        """),

        Template(title: "sklearn: PCA + KMeans", icon: "circle.grid.cross.fill", category: "ML", language: .python, code: """
        import numpy as np
        from sklearn.datasets import make_blobs
        from sklearn.decomposition import PCA
        from sklearn.cluster import KMeans
        from sklearn.metrics import silhouette_score

        X, y_true = make_blobs(n_samples=300, centers=3, random_state=42)

        pca = PCA(n_components=2)
        X_pca = pca.fit_transform(X)
        print(f"PCA: {X.shape} -> {X_pca.shape}")
        print(f"Variance explained: {pca.explained_variance_ratio_.round(3)}")

        km = KMeans(n_clusters=3, random_state=42).fit(X_pca)
        sil = silhouette_score(X_pca, km.labels_)
        print(f"KMeans silhouette: {sil:.3f}")
        print(f"Cluster sizes: {[int((km.labels_==i).sum()) for i in range(3)]}")
        """),

        Template(title: "sklearn: Pipeline", icon: "arrow.right.arrow.left", category: "ML", language: .python, code: """
        import numpy as np
        from sklearn.pipeline import make_pipeline
        from sklearn.preprocessing import StandardScaler
        from sklearn.linear_model import LogisticRegression
        from sklearn.datasets import make_moons
        from sklearn.model_selection import cross_val_score

        X, y = make_moons(n_samples=200, noise=0.2, random_state=42)
        pipe = make_pipeline(StandardScaler(), LogisticRegression(max_iter=500))
        scores = cross_val_score(pipe, X, y, cv=5)
        print(f"Cross-val scores: {scores.round(3)}")
        print(f"Mean accuracy: {scores.mean():.3f} +/- {scores.std():.3f}")
        """),

        // ── matplotlib ──
        Template(title: "matplotlib: 2D Plot", icon: "chart.xyaxis.line", category: "Plot", language: .python, code: """
        import numpy as np
        import matplotlib.pyplot as plt

        x = np.linspace(-2*np.pi, 2*np.pi, 200)
        plt.plot(x, np.sin(x), label='sin(x)')
        plt.plot(x, np.cos(x), label='cos(x)')
        plt.title('Trigonometric Functions')
        plt.xlabel('x')
        plt.ylabel('y')
        plt.grid(True)
        plt.legend()
        plt.show()
        """),

        Template(title: "matplotlib: 3D Sphere", icon: "globe", category: "Plot", language: .python, code: """
        import numpy as np
        import matplotlib.pyplot as plt

        fig = plt.figure()
        ax = fig.add_subplot(111, projection='3d')
        u = np.linspace(0, 2*np.pi, 50)
        v = np.linspace(0, np.pi, 50)
        X = np.outer(np.cos(u), np.sin(v))
        Y = np.outer(np.sin(u), np.sin(v))
        Z = np.outer(np.ones_like(u), np.cos(v))
        ax.plot_surface(X, Y, Z, cmap='viridis', alpha=0.8)
        plt.title('Unit Sphere: x^2+y^2+z^2=1')
        plt.show()
        """),

        Template(title: "matplotlib: Contour", icon: "circle.and.line.horizontal", category: "Plot", language: .python, code: """
        import numpy as np
        import matplotlib.pyplot as plt

        x = np.linspace(-3, 3, 200)
        y = np.linspace(-3, 3, 200)
        X, Y = np.meshgrid(x, y)
        Z = np.exp(X) + Y**3
        plt.contour(X, Y, Z, levels=[1], colors='blue', linewidths=2)
        plt.title('e^x + y^3 = 1')
        plt.xlabel('x')
        plt.ylabel('y')
        plt.grid(True)
        plt.axis('equal')
        plt.show()
        """),

        // ── networkx ──
        Template(title: "networkx: Graph Analysis", icon: "point.3.connected.trianglepath.dotted", category: "Graph", language: .python, code: """
        import networkx as nx

        G = nx.erdos_renyi_graph(20, 0.3, seed=42)
        print(f"Nodes: {G.number_of_nodes()}")
        print(f"Edges: {G.number_of_edges()}")
        print(f"Density: {nx.density(G):.3f}")

        if nx.is_connected(G):
            print(f"Diameter: {nx.diameter(G)}")
            path = nx.shortest_path(G, 0, 5)
            print(f"Shortest path 0->5: {path}")

        degrees = dict(G.degree())
        top5 = sorted(degrees.items(), key=lambda x: -x[1])[:5]
        print(f"Top 5 nodes by degree: {top5}")

        print(f"Clustering coefficient: {nx.average_clustering(G):.3f}")
        """),

        // ── big calculation ──
        Template(title: "Big Numbers", icon: "number", category: "Math", language: .python, code: """
        import math

        print(f"2^100 = {2**100}")
        print(f"100! = {math.factorial(100)}")
        print(f"2^1000 has {len(str(2**1000))} digits")

        # Fibonacci
        a, b = 0, 1
        for i in range(98):
            a, b = b, a + b
        print(f"Fib(100) = {b}")

        # Primes (sieve)
        def sieve(n):
            is_p = [True] * (n+1)
            is_p[0] = is_p[1] = False
            for i in range(2, int(n**0.5)+1):
                if is_p[i]:
                    for j in range(i*i, n+1, i):
                        is_p[j] = False
            return [i for i in range(n+1) if is_p[i]]
        primes = sieve(100)
        print(f"Primes up to 100: {primes}")
        """),

        // ── C interpreter ──
        Template(title: "C: Structs + Algorithms", icon: "c.square.fill", category: "C", language: .c, code: """
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <math.h>

        #define MAX_SIZE 100
        #define PI 3.14159265358979
        #define SQUARE(x) ((x)*(x))

        // --- Structs ---
        struct Point {
            double x;
            double y;
        };

        // --- Union ---
        union Number {
            int i;
            double f;
        };

        // --- Functions ---
        double distance(struct Point a, struct Point b) {
            double dx = a.x - b.x;
            double dy = a.y - b.y;
            return sqrt(dx*dx + dy*dy);
        }

        int is_prime(int n) {
            if (n < 2) return 0;
            for (int i = 2; i * i <= n; i++)
                if (n % i == 0) return 0;
            return 1;
        }

        long long fibonacci(int n) {
            if (n <= 1) return n;
            long long a = 0, b = 1;
            for (int i = 2; i <= n; i++) {
                long long c = a + b;
                a = b;
                b = c;
            }
            return b;
        }

        // Static variable demo
        int counter() {
            static int count = 0;
            count++;
            return count;
        }

        // Function pointer comparator for qsort
        int compare_asc(int a, int b) {
            return a - b;
        }

        int main() {
            printf("=== OfflinAi C Interpreter ===\\n\\n");

            // --- Structs ---
            struct Point p1 = {3.0, 4.0};
            struct Point p2 = {7.0, 1.0};
            printf("Distance: %.4f\\n", distance(p1, p2));
            printf("SQUARE(5) = %d\\n\\n", SQUARE(5));

            // --- Pointers & Address-of ---
            int x = 42;
            int *px = &x;
            printf("x = %d, *px = %d\\n", x, *px);
            *px = 100;
            printf("After *px = 100: x = %d\\n\\n", x);

            // --- 2D Array ---
            int grid[3][3] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
            printf("2D Array [1][2] = %d\\n\\n", grid[1][2]);

            // --- sprintf to buffer ---
            char buf[64];
            sprintf(buf, "Hello %s, pi=%.2f", "World", PI);
            printf("sprintf result: %s\\n\\n", buf);

            // --- Static variable ---
            printf("Static counter: ");
            for (int i = 0; i < 5; i++)
                printf("%d ", counter());
            printf("\\n\\n");

            // --- Function pointers ---
            int (*cmp)(int, int) = compare_asc;
            printf("cmp(3,7) = %d\\n", cmp(3, 7));
            printf("cmp(7,3) = %d\\n\\n", cmp(7, 3));

            // --- Goto ---
            int val = 0;
            goto skip;
            val = 999;
        skip:
            printf("After goto: val = %d (should be 0)\\n\\n", val);

            // --- Union ---
            union Number num;
            num.i = 42;
            printf("Union int: %d\\n", num.i);
            num.f = 3.14;
            printf("Union float: %.2f\\n\\n", num.f);

            // --- Primes ---
            printf("Primes < 30: ");
            for (int n = 2; n < 30; n++)
                if (is_prime(n)) printf("%d ", n);
            printf("\\n\\n");

            // --- Fibonacci ---
            for (int i = 1; i <= 10; i++)
                printf("fib(%2d) = %lld\\n", i, fibonacci(i));

            printf("\\nAll features working!\\n");
            return 0;
        }
        """),

        // ── manim ──
        Template(title: "manim: Shapes", icon: "sparkles", category: "Manim", language: .python, code:
        "from manim import *\n\nclass ShapeDemo(Scene):\n  def construct(self):\n    circle = Circle(radius=1.5, color=BLUE, fill_opacity=0.5)\n    square = Square(side_length=2, color=RED, fill_opacity=0.3)\n    triangle = Triangle(color=GREEN, fill_opacity=0.3)\n    shapes = VGroup(circle, square, triangle).arrange(RIGHT, buff=1)\n    self.play(Create(shapes), run_time=2)\n    title = Text('Shapes in Manim', font_size=36).to_edge(UP)\n    self.play(Write(title))\n    self.wait(0.5)\n\nscene = ShapeDemo()\nscene.render()\n"),

        Template(title: "manim: Transform", icon: "arrow.triangle.2.circlepath", category: "Manim", language: .python, code:
        "from manim import *\n\nclass TransformDemo(Scene):\n  def construct(self):\n    circle = Circle(color=BLUE, fill_opacity=0.8)\n    square = Square(color=RED, fill_opacity=0.8)\n    triangle = Triangle(color=GREEN, fill_opacity=0.8)\n    self.play(Create(circle))\n    self.play(Transform(circle, square))\n    self.play(Transform(circle, triangle))\n    self.play(FadeOut(circle))\n\nscene = TransformDemo()\nscene.render()\n"),

        Template(title: "manim: Graph Plot", icon: "chart.xyaxis.line", category: "Manim", language: .python, code:
        "from manim import *\nimport numpy as np\n\nclass FunctionPlot(Scene):\n  def construct(self):\n    axes = Axes(x_range=[-3, 3, 1], y_range=[-2, 2, 1], axis_config={'include_numbers': False})\n    sin_graph = axes.plot(lambda x: np.sin(x), color=BLUE)\n    cos_graph = axes.plot(lambda x: np.cos(x), color=RED)\n    sin_label = Text('sin(x)', font_size=24, color=BLUE).next_to(axes, UP + LEFT)\n    cos_label = Text('cos(x)', font_size=24, color=RED).next_to(axes, UP + RIGHT)\n    self.play(Create(axes), run_time=0.5)\n    self.play(Create(sin_graph), Write(sin_label), run_time=0.5)\n    self.play(Create(cos_graph), Write(cos_label), run_time=0.5)\n\nscene = FunctionPlot()\nscene.render()\n"),

        // ── Comprehensive Tests ──
        Template(title: "Test matplotlib (ALL)", icon: "chart.xyaxis.line", category: "Test", language: .python, code: """
        import numpy as np
        import matplotlib.pyplot as plt
        import matplotlib.cm as cm
        results = []
        t = _offlinai_test

        x = np.linspace(-3, 3, 50)
        X, Y = np.meshgrid(x, x)
        Z = np.sin(X) * np.cos(Y)

        # 2D plots
        t("line plot", lambda: plt.plot(x, np.sin(x), label='sin'))
        t("multi line", lambda: (plt.plot(x, np.sin(x)), plt.plot(x, np.cos(x)), plt.legend()))
        t("scatter", lambda: plt.scatter(x, np.sin(x), c=x, cmap='viridis', s=20))
        t("bar", lambda: plt.bar(['A','B','C','D'], [3,7,2,5]))
        t("barh", lambda: plt.barh(['X','Y','Z'], [5,3,8]))
        t("hist", lambda: plt.hist(np.random.randn(500), bins=25, alpha=0.7))
        t("pie", lambda: plt.pie([30,20,50], labels=['A','B','C'], autopct='%1.1f%%'))
        t("fill_between", lambda: plt.fill_between(x, np.sin(x), 0, alpha=0.3))
        t("errorbar", lambda: plt.errorbar([1,2,3], [4,5,6], yerr=0.5))
        t("stem", lambda: plt.stem([1,2,3,4], [1,4,2,3]))
        t("step", lambda: plt.step([1,2,3,4], [1,4,2,3]))
        t("stackplot", lambda: plt.stackplot([1,2,3], [1,2,3], [3,2,1]))
        t("boxplot", lambda: plt.boxplot([np.random.randn(50) for _ in range(3)]))
        t("violinplot", lambda: plt.violinplot([np.random.randn(50) for _ in range(3)]))

        # Heatmap & contour
        t("imshow", lambda: (plt.imshow(np.random.rand(10,10), cmap='hot'), plt.colorbar()))
        t("contour", lambda: plt.contour(X, Y, Z, levels=10))
        t("contourf", lambda: plt.contourf(X, Y, Z, cmap='RdBu'))
        t("implicit eq", lambda: plt.contour(X, Y, X**2+Y**2, levels=[1], colors='blue'))

        # Styling
        t("title/labels", lambda: (plt.plot(x, np.sin(x)), plt.title("T"), plt.xlabel("X"), plt.ylabel("Y")))
        t("legend", lambda: (plt.plot(x, np.sin(x), label='sin'), plt.legend()))
        t("grid", lambda: (plt.plot(x, np.sin(x)), plt.grid(True)))
        t("xlim/ylim", lambda: (plt.plot(x, np.sin(x)), plt.xlim(-5, 5), plt.ylim(-2, 2)))
        t("log scale", lambda: (plt.plot([1,10,100,1000]), plt.yscale('log')))
        t("annotate", lambda: (plt.plot(x, np.sin(x)), plt.annotate("peak", xy=(1.57, 1))))
        t("axhline/axvline", lambda: (plt.axhline(0, color='r'), plt.axvline(0, color='b')))
        t("fmt 'ro-'", lambda: plt.plot([1,2,3], [1,4,9], 'ro-'))

        # Subplots
        t("subplots(2,2)", lambda: (lambda f,a: (a[0,0].plot(x,np.sin(x)), a[1,1].scatter(x,np.cos(x))))(*plt.subplots(2,2)))
        t("twinx", lambda: (lambda f,a: (a.plot(x,np.sin(x),'b'), a.twinx().plot(x,np.exp(x/3),'r')))(*plt.subplots()))
        t("axes.flat", lambda: (lambda f,a: [ax.plot(x,np.sin(x+i)) for i,ax in enumerate(a.flat)])(*plt.subplots(2,2)))

        # 3D
        t("plt.plot_surface", lambda: plt.plot_surface(X, Y, Z, cmap='viridis'))
        t("plt.scatter3D", lambda: plt.scatter3D([1,2,3], [4,5,6], [7,8,9], c=[1,2,3], cmap='plasma'))
        t("plt.plot3D", lambda: plt.plot3D(np.cos(np.linspace(0,6,50)), np.sin(np.linspace(0,6,50)), np.linspace(0,2,50)))
        t("plt.plot_wireframe", lambda: plt.plot_wireframe(X[:10,:10], Y[:10,:10], Z[:10,:10]))
        t("ax.plot_surface", lambda: (lambda f: f.add_subplot(111, projection='3d').plot_surface(X, Y, Z, cmap='coolwarm'))(plt.figure()))
        t("ax.view_init", lambda: (lambda ax: (ax.plot_surface(X,Y,Z), ax.view_init(30,45)))(plt.figure().add_subplot(111,projection='3d')))
        t("ax.set_zlabel", lambda: (lambda ax: (ax.plot_surface(X,Y,Z), ax.set_zlabel('Z')))(plt.figure().add_subplot(111,projection='3d')))
        t("Axes3D import", lambda: __import__('mpl_toolkits.mplot3d', fromlist=['Axes3D']))

        # Colormaps
        for c in ['viridis','plasma','hot','coolwarm','jet','RdBu','Spectral','gray']:
            t(f"cmap {c}", lambda c=c: plt.plot_surface(X[:10,:10], Y[:10,:10], Z[:10,:10], cmap=c))

        # Figure
        t("savefig", lambda: (plt.plot(x, np.sin(x)), plt.savefig('/tmp/mpl_test.html')))
        t("show", lambda: (plt.plot(x, np.sin(x)), plt.show()))

        # Polar
        t("polar", lambda: plt.polar(np.linspace(0,2*np.pi,100), 1+np.sin(np.linspace(0,2*np.pi,100))))

        p = _offlinai_test_pass
        f = _offlinai_test_fail
        print("\\n" + "=" * 40)
        print("MATPLOTLIB: " + str(p) + "/" + str(p+f) + " passed" + (" PASS" if f==0 else " (" + str(f) + " failed)"))
        """),

        Template(title: "Test sklearn (ALL)", icon: "brain", category: "Test", language: .python, code: """
        import numpy as np
        results = []
        t = _offlinai_test

        # Generate test data
        from sklearn.datasets import make_classification, make_regression, make_blobs, make_moons, load_iris
        X_cls, y_cls = make_classification(n_samples=100, n_features=5, random_state=42)
        X_reg, y_reg = make_regression(n_samples=100, n_features=5, random_state=42)
        X_blobs, y_blobs = make_blobs(n_samples=100, centers=3, random_state=42)
        X_moons, y_moons = make_moons(n_samples=100, noise=0.2, random_state=42)
        iris = load_iris()
        t("datasets", lambda: None)

        from sklearn.model_selection import train_test_split, cross_val_score
        X_tr, X_te, y_tr, y_te = train_test_split(X_cls, y_cls, test_size=0.3, random_state=42)
        t("train_test_split", lambda: None)

        # Linear models
        from sklearn.linear_model import LinearRegression, Ridge, Lasso, LogisticRegression
        t("LinearRegression", lambda: LinearRegression().fit(X_tr, y_tr).score(X_te, y_te))
        t("Ridge(alpha=1)", lambda: Ridge(alpha=1.0).fit(X_tr, y_tr))
        t("Lasso", lambda: Lasso(alpha=0.01, max_iter=1000).fit(X_tr, y_tr))
        t("LogisticRegression", lambda: LogisticRegression(max_iter=500, solver='lbfgs').fit(X_tr, y_tr).score(X_te, y_te))

        # Trees
        from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor
        t("DecisionTreeClassifier", lambda: DecisionTreeClassifier(max_depth=5, criterion='gini').fit(X_tr, y_tr).score(X_te, y_te))
        t("DecisionTreeRegressor", lambda: DecisionTreeRegressor(max_depth=5).fit(X_reg[:70], y_reg[:70]))

        # Ensemble
        from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier, AdaBoostClassifier, BaggingClassifier
        t("RandomForest", lambda: RandomForestClassifier(n_estimators=10, max_depth=5, random_state=42).fit(X_tr, y_tr).score(X_te, y_te))
        t("GradientBoosting", lambda: GradientBoostingClassifier(n_estimators=20, max_depth=3, learning_rate=0.1).fit(X_tr, y_tr))
        t("AdaBoost", lambda: AdaBoostClassifier(n_estimators=10).fit(X_tr, y_tr))
        t("Bagging", lambda: BaggingClassifier(n_estimators=5).fit(X_tr, y_tr))

        # SVM
        from sklearn.svm import SVC, SVR
        t("SVC", lambda: SVC(C=1.0, kernel='linear').fit(X_tr, y_tr).score(X_te, y_te))
        t("SVR", lambda: SVR(C=1.0, epsilon=0.1).fit(X_reg[:70], y_reg[:70]))

        # Neighbors
        from sklearn.neighbors import KNeighborsClassifier, KNeighborsRegressor
        t("KNeighborsClassifier", lambda: KNeighborsClassifier(n_neighbors=5).fit(X_tr, y_tr).score(X_te, y_te))
        t("KNeighborsRegressor", lambda: KNeighborsRegressor(n_neighbors=5).fit(X_reg[:70], y_reg[:70]))

        # Naive Bayes
        from sklearn.naive_bayes import GaussianNB, MultinomialNB
        t("GaussianNB", lambda: GaussianNB().fit(X_tr, y_tr).score(X_te, y_te))

        # Clustering
        from sklearn.cluster import KMeans, DBSCAN, AgglomerativeClustering
        t("KMeans", lambda: KMeans(n_clusters=3, init='k-means++', random_state=42).fit(X_blobs))
        t("DBSCAN", lambda: DBSCAN(eps=0.5, min_samples=5).fit(X_blobs))
        t("Agglomerative", lambda: AgglomerativeClustering(n_clusters=3).fit(X_blobs))

        # Decomposition
        from sklearn.decomposition import PCA, TruncatedSVD
        t("PCA", lambda: PCA(n_components=2, svd_solver='auto').fit_transform(X_cls))
        t("TruncatedSVD", lambda: TruncatedSVD(n_components=2).fit_transform(X_cls))

        # Preprocessing
        from sklearn.preprocessing import StandardScaler, MinMaxScaler, LabelEncoder, OneHotEncoder, PolynomialFeatures, RobustScaler
        t("StandardScaler", lambda: StandardScaler(copy=True).fit_transform(X_cls))
        t("MinMaxScaler", lambda: MinMaxScaler().fit_transform(X_cls))
        t("LabelEncoder", lambda: LabelEncoder().fit_transform(['a','b','c','a','b']))
        t("OneHotEncoder", lambda: OneHotEncoder(sparse_output=False).fit_transform([[0],[1],[2],[0]]))
        t("PolynomialFeatures", lambda: PolynomialFeatures(degree=2, include_bias=False).fit_transform(X_cls[:10,:2]))
        t("RobustScaler", lambda: RobustScaler().fit_transform(X_cls))

        # Pipeline
        from sklearn.pipeline import Pipeline, make_pipeline
        t("Pipeline", lambda: make_pipeline(StandardScaler(), LogisticRegression(max_iter=500)).fit(X_tr, y_tr).score(X_te, y_te))

        # Metrics
        from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, r2_score, classification_report, silhouette_score
        y_pred = LogisticRegression(max_iter=500).fit(X_tr, y_tr).predict(X_te)
        t("accuracy_score", lambda: accuracy_score(y_te, y_pred))
        t("confusion_matrix", lambda: confusion_matrix(y_te, y_pred))
        t("f1_score", lambda: f1_score(y_te, y_pred, average='binary'))
        t("classification_report", lambda: classification_report(y_te, y_pred))
        km_labels = KMeans(n_clusters=3, random_state=42).fit_predict(X_blobs)
        t("silhouette_score", lambda: silhouette_score(X_blobs, km_labels))

        # Model selection
        t("cross_val_score", lambda: cross_val_score(LogisticRegression(max_iter=500), X_cls, y_cls, cv=3))
        from sklearn.model_selection import GridSearchCV
        t("GridSearchCV", lambda: GridSearchCV(Ridge(), {'alpha':[0.1,1.0,10.0]}, cv=3).fit(X_reg, y_reg))

        # Feature extraction
        from sklearn.feature_extraction import CountVectorizer, TfidfVectorizer
        docs = ["hello world", "world of code", "hello code"]
        t("CountVectorizer", lambda: CountVectorizer(analyzer='word').fit_transform(docs))
        t("TfidfVectorizer", lambda: TfidfVectorizer().fit_transform(docs))

        # Feature selection
        from sklearn.feature_selection import SelectKBest, VarianceThreshold, f_classif
        t("SelectKBest", lambda: SelectKBest(f_classif, k=3).fit_transform(X_cls, y_cls))
        t("VarianceThreshold", lambda: VarianceThreshold(threshold=0.0).fit_transform(X_cls))

        # Impute
        from sklearn.impute import SimpleImputer
        X_miss = X_cls.copy(); X_miss[0,0] = np.nan; X_miss[5,2] = np.nan
        t("SimpleImputer", lambda: SimpleImputer(strategy='mean').fit_transform(X_miss))

        # Manifold
        from sklearn.manifold import TSNE, MDS
        t("TSNE", lambda: TSNE(n_components=2, init='random', perplexity=10, random_state=42).fit_transform(X_cls[:50]))
        t("MDS", lambda: MDS(n_components=2, random_state=42).fit_transform(X_cls[:30]))

        # Neural Network
        from sklearn.neural_network import MLPClassifier
        t("MLPClassifier", lambda: MLPClassifier(hidden_layer_sizes=(20,10), max_iter=100, solver='adam', random_state=42).fit(X_tr, y_tr).score(X_te, y_te))

        # Discriminant Analysis
        from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
        t("LDA", lambda: LinearDiscriminantAnalysis(solver='svd').fit(X_tr, y_tr).score(X_te, y_te))

        # Mixture
        from sklearn.mixture import GaussianMixture
        t("GaussianMixture", lambda: GaussianMixture(n_components=3, n_init=1, random_state=42).fit(X_blobs))

        # Dummy
        from sklearn.dummy import DummyClassifier
        t("DummyClassifier", lambda: DummyClassifier(strategy='most_frequent').fit(X_tr, y_tr).score(X_te, y_te))

        # Isotonic
        from sklearn.isotonic import IsotonicRegression
        t("IsotonicRegression", lambda: IsotonicRegression().fit_transform([1,2,3,4,5], [1,3,2,5,4]))

        # Multiclass
        from sklearn.multiclass import OneVsRestClassifier
        t("OneVsRestClassifier", lambda: OneVsRestClassifier(SVC(kernel='linear')).fit(X_tr, y_tr))

        # Compose
        from sklearn.compose import ColumnTransformer
        t("ColumnTransformer", lambda: ColumnTransformer(transformers=[('num', StandardScaler(), [0,1,2])]).fit_transform(X_cls))

        # Calibration
        from sklearn.calibration import CalibratedClassifierCV
        t("CalibratedClassifierCV", lambda: CalibratedClassifierCV)

        # Kernel
        from sklearn.kernel_ridge import KernelRidge
        t("KernelRidge", lambda: KernelRidge(alpha=1.0).fit(X_reg[:50], y_reg[:50]))

        # Gaussian Process
        from sklearn.gaussian_process import GaussianProcessRegressor
        t("GaussianProcessRegressor", lambda: GaussianProcessRegressor().fit(X_reg[:20,:2], y_reg[:20]))

        # Utils
        from sklearn.utils import check_array, Bunch
        t("check_array", lambda: check_array(X_cls))
        t("Bunch", lambda: Bunch(data=X_cls, target=y_cls))

        # Exceptions
        from sklearn.exceptions import NotFittedError
        t("NotFittedError", lambda: NotFittedError("test"))

        p = _offlinai_test_pass
        f = _offlinai_test_fail
        print("\\n" + "=" * 40)
        print("SKLEARN: " + str(p) + "/" + str(p+f) + " passed" + (" PASS" if f==0 else " (" + str(f) + " failed)"))
        """),

        // ── All libs quick test ──
        Template(title: "Test ALL Libraries (quick)", icon: "checkmark.shield.fill", category: "Test", language: .python, code: """
        t = _offlinai_test
        t("numpy", lambda: __import__('numpy').__version__)
        t("scipy", lambda: __import__('scipy').__version__)
        t("sympy", lambda: __import__('sympy').__version__)
        t("sklearn", lambda: __import__('sklearn').__version__)
        t("matplotlib", lambda: __import__('matplotlib').__version__)
        t("plotly", lambda: __import__('plotly').__version__)
        t("networkx", lambda: __import__('networkx').__version__)
        t("PIL", lambda: __import__('PIL').__version__)
        t("bs4", lambda: __import__('bs4').__version__)
        t("yaml", lambda: __import__('yaml').__version__)
        t("rich", lambda: __import__('rich').__version__)
        t("tqdm", lambda: __import__('tqdm').__version__)
        t("pygments", lambda: __import__('pygments').__version__)
        t("svgelements", lambda: __import__('svgelements').__version__)
        t("click", lambda: __import__('click').__version__)
        t("jsonschema", lambda: __import__('jsonschema').__version__)
        t("mpmath", lambda: __import__('mpmath').__version__)
        print("\\nPassed: " + str(_offlinai_test_pass) + " Failed: " + str(_offlinai_test_fail))
        """),

        // ── Full comprehensive test ──
        Template(title: "Test ALL Modules (280 tests)", icon: "testtube.2", category: "Test", language: .python, code: """
        import sys, time
        import numpy as np
        _t0 = time.time()
        _pass = 0
        _fail = 0
        _errors = []
        t = _offlinai_test
        _pass = _offlinai_test_pass
        _fail = _offlinai_test_fail
        _errors = _offlinai_test_errors
        def S(x):
            print("\\n== " + x + " ==")


        S("NUMPY")
        t("array+math", lambda: np.sin(np.linspace(0, 2*np.pi, 100)).mean())
        t("linalg.solve", lambda: np.linalg.solve([[3,1],[1,2]], [9,8]))
        t("linalg.eig", lambda: np.linalg.eig(np.array([[2,1],[1,3]])))
        t("linalg.svd", lambda: np.linalg.svd(np.random.randn(4,3)))
        t("fft", lambda: np.fft.fft(np.random.randn(64)))
        t("random", lambda: np.random.RandomState(0).randn(5,5))
        t("meshgrid", lambda: np.meshgrid(np.arange(5), np.arange(5)))
        t("broadcasting", lambda: (np.arange(12).reshape(3,4) * np.arange(4)).sum())
        t("boolean idx", lambda: np.arange(20)[np.arange(20) % 3 == 0])
        t("matmul", lambda: np.matmul(np.eye(3), np.ones((3,2))))

        S("SCIPY")
        t("optimize.minimize", lambda: __import__('scipy.optimize',fromlist=['minimize']).minimize(lambda x: (x[0]-3)**2+(x[1]+1)**2, [0,0], method='Nelder-Mead').x)
        t("integrate.quad", lambda: __import__('scipy.integrate',fromlist=['quad']).quad(lambda x: np.exp(-x**2), -np.inf, np.inf)[0])
        t("stats.norm.cdf", lambda: __import__('scipy.stats',fromlist=['norm']).norm.cdf(0))
        t("stats.ttest_ind", lambda: __import__('scipy.stats',fromlist=['ttest_ind']).ttest_ind([1,2,3,4],[2,3,4,5]))
        t("interpolate.interp1d", lambda: __import__('scipy.interpolate',fromlist=['interp1d']).interp1d([0,1,2,3],[0,1,4,9])(1.5))
        t("linalg.solve", lambda: __import__('scipy.linalg',fromlist=['solve']).solve([[2,1],[5,3]], [4,7]))
        t("fft.rfft", lambda: __import__('scipy.fft',fromlist=['rfft']).rfft(np.sin(np.linspace(0,2*np.pi,64))))
        t("signal.butter", lambda: __import__('scipy.signal',fromlist=['butter']).butter(4, 0.2))
        t("spatial.distance", lambda: __import__('scipy.spatial.distance',fromlist=['euclidean']).euclidean([0,0,0],[1,2,3]))
        t("sparse.csr_matrix", lambda: __import__('scipy.sparse',fromlist=['csr_matrix']).csr_matrix(np.eye(5)).toarray())
        t("special.gamma", lambda: __import__('scipy.special',fromlist=['gamma']).gamma(5))
        t("ndimage.gaussian", lambda: __import__('scipy.ndimage',fromlist=['gaussian_filter']).gaussian_filter(np.random.randn(8,8), 1.0))
        t("cluster.hierarchy", lambda: __import__('scipy.cluster.hierarchy',fromlist=['linkage']).linkage(np.random.randn(10,3)))
        t("constants.c", lambda: __import__('scipy.constants',fromlist=['c']).c)

        S("SKLEARN — Datasets (15)")
        from sklearn.datasets import *
        t("make_classification", lambda: make_classification(100, 10, random_state=0))
        t("make_regression", lambda: make_regression(100, 5, random_state=0))
        t("make_blobs", lambda: make_blobs(100, random_state=0))
        t("make_moons", lambda: make_moons(100, random_state=0))
        t("make_circles", lambda: make_circles(100, random_state=0))
        t("load_iris", lambda: load_iris())
        t("load_digits", lambda: load_digits())
        t("load_wine", lambda: load_wine())
        t("load_breast_cancer", lambda: load_breast_cancer())
        t("load_diabetes", lambda: load_diabetes())
        t("make_swiss_roll", lambda: make_swiss_roll(50, random_state=0))
        t("make_s_curve", lambda: make_s_curve(50, random_state=0))
        t("make_friedman1", lambda: make_friedman1(50, random_state=0))
        t("make_friedman2", lambda: make_friedman2(50, random_state=0))
        t("make_friedman3", lambda: make_friedman3(50, random_state=0))

        X, y = make_classification(200, 10, random_state=42)
        Xr, yr = make_regression(200, 5, random_state=42)
        from sklearn.model_selection import train_test_split
        Xt, Xte, yt, yte = train_test_split(X, y, test_size=0.3, random_state=0)
        Xrt, Xrte, yrt, yrte = train_test_split(Xr, yr, test_size=0.3, random_state=0)
        Xc, _ = make_blobs(100, centers=3, random_state=0)

        S("SKLEARN — Model Selection (9)")
        from sklearn.model_selection import *
        t("KFold", lambda: list(KFold(5).split(X)))
        t("StratifiedKFold", lambda: list(StratifiedKFold(5).split(X, y)))
        t("LeaveOneOut", lambda: len(list(LeaveOneOut().split(np.arange(10).reshape(-1,1)))))
        t("TimeSeriesSplit", lambda: list(TimeSeriesSplit(3).split(X)))
        t("ShuffleSplit", lambda: list(ShuffleSplit(3, random_state=0).split(X)))
        t("RepeatedKFold", lambda: list(RepeatedKFold(n_splits=3, n_repeats=2, random_state=0).split(X)))
        t("cross_val_score", lambda: cross_val_score(__import__('sklearn.linear_model',fromlist=['Ridge']).Ridge(), Xr, yr, cv=3))
        t("cross_validate", lambda: cross_validate(__import__('sklearn.linear_model',fromlist=['Ridge']).Ridge(), Xr, yr, cv=3))
        t("RandomizedSearchCV", lambda: RandomizedSearchCV(__import__('sklearn.linear_model',fromlist=['Ridge']).Ridge(), {'alpha':[0.1,1,10]}, n_iter=2, cv=2).fit(Xrt, yrt).best_score_)

        S("SKLEARN — Preprocessing (16)")
        from sklearn.preprocessing import *
        Xp = np.random.RandomState(0).randn(50, 4)
        t("StandardScaler", lambda: StandardScaler().fit_transform(Xp))
        t("MinMaxScaler", lambda: MinMaxScaler().fit_transform(Xp))
        t("RobustScaler", lambda: RobustScaler().fit_transform(Xp))
        t("MaxAbsScaler", lambda: MaxAbsScaler().fit_transform(Xp))
        t("Normalizer", lambda: Normalizer().fit_transform(Xp))
        t("Binarizer", lambda: Binarizer().fit_transform(Xp))
        t("LabelEncoder", lambda: LabelEncoder().fit_transform(['a','b','c','a']))
        t("OneHotEncoder", lambda: OneHotEncoder(sparse_output=False).fit_transform([[0],[1],[2],[0]]))
        t("OrdinalEncoder", lambda: OrdinalEncoder().fit_transform([['a'],['b'],['c']]))
        t("LabelBinarizer", lambda: LabelBinarizer().fit_transform([0,1,2,0]))
        t("PolynomialFeatures", lambda: PolynomialFeatures(2).fit_transform(Xp[:5,:2]))
        t("PowerTransformer", lambda: PowerTransformer().fit_transform(np.abs(Xp)+1))
        t("QuantileTransformer", lambda: QuantileTransformer(n_quantiles=20).fit_transform(Xp))
        t("KBinsDiscretizer", lambda: KBinsDiscretizer(n_bins=3, encode='ordinal', strategy='uniform').fit_transform(Xp))
        t("FunctionTransformer", lambda: FunctionTransformer(func=np.abs).fit_transform(Xp))
        t("SplineTransformer", lambda: SplineTransformer(n_knots=4, degree=3).fit_transform(Xp[:,:1]))

        S("SKLEARN — Linear Models (14)")
        from sklearn.linear_model import *
        t("LinearRegression", lambda: LinearRegression().fit(Xrt, yrt).score(Xrte, yrte))
        t("Ridge", lambda: Ridge().fit(Xrt, yrt).predict(Xrte))
        t("Lasso", lambda: Lasso(alpha=0.1).fit(Xrt, yrt).predict(Xrte))
        t("ElasticNet", lambda: ElasticNet(alpha=0.1).fit(Xrt, yrt).predict(Xrte))
        t("LogisticRegression", lambda: LogisticRegression().fit(Xt, yt).score(Xte, yte))
        t("SGDClassifier", lambda: SGDClassifier(random_state=0).fit(Xt, yt).predict(Xte))
        t("SGDRegressor", lambda: SGDRegressor(random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("RidgeClassifier", lambda: RidgeClassifier().fit(Xt, yt).predict(Xte))
        t("Perceptron", lambda: Perceptron(random_state=0).fit(Xt, yt).predict(Xte))
        t("BayesianRidge", lambda: BayesianRidge().fit(Xrt, yrt).predict(Xrte))
        t("HuberRegressor", lambda: HuberRegressor().fit(Xrt, yrt).predict(Xrte))
        t("Lars", lambda: Lars().fit(Xrt, yrt).predict(Xrte))
        t("LassoLars", lambda: LassoLars(alpha=0.01).fit(Xrt, yrt).predict(Xrte))
        t("PoissonRegressor", lambda: PoissonRegressor().fit(np.abs(Xrt)+1, np.abs(yrt)+1).predict(np.abs(Xrte)+1))

        S("SKLEARN — Ensemble (17)")
        from sklearn.ensemble import *
        t("RandomForestCls", lambda: RandomForestClassifier(n_estimators=10, random_state=0).fit(Xt, yt).score(Xte, yte))
        t("RandomForestReg", lambda: RandomForestRegressor(n_estimators=10, random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("GradBoostCls", lambda: GradientBoostingClassifier(n_estimators=20).fit(Xt, yt).score(Xte, yte))
        t("GradBoostReg", lambda: GradientBoostingRegressor(n_estimators=20).fit(Xrt, yrt).predict(Xrte))
        t("AdaBoostCls", lambda: AdaBoostClassifier(n_estimators=20, random_state=0).fit(Xt, yt).predict(Xte))
        t("AdaBoostReg", lambda: AdaBoostRegressor(n_estimators=20, random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("BaggingCls", lambda: BaggingClassifier(n_estimators=10, random_state=0).fit(Xt, yt).predict(Xte))
        t("BaggingReg", lambda: BaggingRegressor(n_estimators=10, random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("ExtraTreesCls", lambda: ExtraTreesClassifier(n_estimators=10, random_state=0).fit(Xt, yt).predict(Xte))
        t("ExtraTreesReg", lambda: ExtraTreesRegressor(n_estimators=10, random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("HistGBCls", lambda: HistGradientBoostingClassifier(max_iter=20, random_state=0).fit(Xt, yt).predict(Xte))
        t("HistGBReg", lambda: HistGradientBoostingRegressor(max_iter=20).fit(Xrt, yrt).predict(Xrte))
        t("IsolationForest", lambda: IsolationForest(n_estimators=20, random_state=0).fit(Xt).predict(Xte))
        t("VotingCls", lambda: VotingClassifier(estimators=[('lr', LogisticRegression()), ('rf', RandomForestClassifier(n_estimators=5, random_state=0))]).fit(Xt, yt).predict(Xte))
        t("VotingReg", lambda: VotingRegressor(estimators=[('lr', LinearRegression()), ('r', Ridge())]).fit(Xrt, yrt).predict(Xrte))
        t("StackingCls", lambda: StackingClassifier(estimators=[('lr', LogisticRegression())], cv=2).fit(Xt, yt).predict(Xte))
        t("StackingReg", lambda: StackingRegressor(estimators=[('lr', LinearRegression())], cv=2).fit(Xrt, yrt).predict(Xrte))

        S("SKLEARN — Tree/SVM/Neighbors/NB (20)")
        from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor, ExtraTreeClassifier, ExtraTreeRegressor
        from sklearn.svm import SVC, SVR, LinearSVC, LinearSVR, NuSVC, NuSVR, OneClassSVM
        from sklearn.neighbors import (KNeighborsClassifier, KNeighborsRegressor, NearestNeighbors, NearestCentroid, LocalOutlierFactor, KernelDensity, RadiusNeighborsClassifier, RadiusNeighborsRegressor)
        from sklearn.naive_bayes import GaussianNB, MultinomialNB, BernoulliNB
        t("DecisionTreeCls", lambda: DecisionTreeClassifier().fit(Xt, yt).score(Xte, yte))
        t("DecisionTreeReg", lambda: DecisionTreeRegressor().fit(Xrt, yrt).predict(Xrte))
        t("ExtraTreeCls", lambda: ExtraTreeClassifier(random_state=0).fit(Xt, yt).predict(Xte))
        t("ExtraTreeReg", lambda: ExtraTreeRegressor(random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("SVC", lambda: SVC().fit(Xt, yt).score(Xte, yte))
        t("SVR", lambda: SVR().fit(Xrt, yrt).predict(Xrte))
        t("LinearSVC", lambda: LinearSVC(random_state=0).fit(Xt, yt).predict(Xte))
        t("LinearSVR", lambda: LinearSVR(random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("NuSVC", lambda: NuSVC().fit(Xt, yt).predict(Xte))
        t("NuSVR", lambda: NuSVR().fit(Xrt, yrt).predict(Xrte))
        t("OneClassSVM", lambda: OneClassSVM().fit(Xt).predict(Xte))
        t("KNeighborsCls", lambda: KNeighborsClassifier().fit(Xt, yt).score(Xte, yte))
        t("KNeighborsReg", lambda: KNeighborsRegressor().fit(Xrt, yrt).predict(Xrte))
        t("NearestNeighbors", lambda: NearestNeighbors().fit(Xt).kneighbors(Xte[:5]))
        t("NearestCentroid", lambda: NearestCentroid().fit(Xt, yt).predict(Xte))
        t("LocalOutlierFactor", lambda: LocalOutlierFactor().fit_predict(Xt))
        t("KernelDensity", lambda: KernelDensity().fit(Xt).score_samples(Xte[:5]))
        t("GaussianNB", lambda: GaussianNB().fit(Xt, yt).score(Xte, yte))
        t("MultinomialNB", lambda: MultinomialNB().fit(np.abs(Xt), yt).predict(np.abs(Xte)))
        t("BernoulliNB", lambda: BernoulliNB().fit(Xt>0, yt).predict(Xte>0))

        S("SKLEARN — Cluster (12)")
        from sklearn.cluster import *
        t("KMeans", lambda: KMeans(3, random_state=0, n_init=3).fit_predict(Xc))
        t("MiniBatchKMeans", lambda: MiniBatchKMeans(3, random_state=0, n_init=3).fit_predict(Xc))
        t("DBSCAN", lambda: DBSCAN(eps=1.0).fit_predict(Xc))
        t("Agglomerative", lambda: AgglomerativeClustering(3).fit_predict(Xc))
        t("SpectralClustering", lambda: SpectralClustering(3, random_state=0, n_init=3).fit_predict(Xc))
        t("MeanShift", lambda: MeanShift().fit_predict(Xc))
        t("OPTICS", lambda: OPTICS(min_samples=5).fit_predict(Xc))
        t("Birch", lambda: Birch(n_clusters=3).fit_predict(Xc))
        t("AffinityPropagation", lambda: AffinityPropagation(random_state=0).fit_predict(Xc))
        t("BisectingKMeans", lambda: BisectingKMeans(3, random_state=0).fit_predict(Xc))
        t("HDBSCAN", lambda: HDBSCAN(min_cluster_size=10).fit_predict(Xc))
        t("FeatureAgglom", lambda: FeatureAgglomeration(n_clusters=2).fit_transform(Xc))

        S("SKLEARN — Decomposition (11)")
        from sklearn.decomposition import *
        Xd = np.abs(np.random.RandomState(0).randn(50, 8)) + 0.1
        t("PCA", lambda: PCA(2).fit_transform(Xd))
        t("TruncatedSVD", lambda: TruncatedSVD(2).fit_transform(Xd))
        t("NMF", lambda: NMF(2, max_iter=50, random_state=0).fit_transform(Xd))
        t("FastICA", lambda: FastICA(2, random_state=0).fit_transform(Xd))
        t("KernelPCA", lambda: KernelPCA(2, kernel='rbf').fit_transform(Xd))
        t("IncrementalPCA", lambda: IncrementalPCA(2).fit_transform(Xd))
        t("LDA_topic", lambda: LatentDirichletAllocation(2, max_iter=5, random_state=0).fit_transform(Xd))
        t("SparsePCA", lambda: SparsePCA(2, max_iter=10, random_state=0).fit_transform(Xd))
        t("FactorAnalysis", lambda: FactorAnalysis(2, max_iter=50).fit_transform(Xd))
        t("DictLearning", lambda: DictionaryLearning(2, max_iter=10, random_state=0).fit_transform(Xd))
        t("MiniBatchNMF", lambda: MiniBatchNMF(2, max_iter=50, random_state=0).fit_transform(Xd))

        S("SKLEARN — Manifold/NN/GP/DA/Mix (13)")
        from sklearn.manifold import TSNE, MDS, Isomap, LocallyLinearEmbedding, SpectralEmbedding
        from sklearn.neural_network import MLPClassifier, MLPRegressor
        from sklearn.gaussian_process import GaussianProcessClassifier, GaussianProcessRegressor
        from sklearn.discriminant_analysis import LinearDiscriminantAnalysis, QuadraticDiscriminantAnalysis
        from sklearn.mixture import GaussianMixture, BayesianGaussianMixture
        Xs, ys = Xt[:60], yt[:60]
        t("TSNE", lambda: TSNE(2, random_state=0, perplexity=15).fit_transform(Xs))
        t("MDS", lambda: MDS(2, random_state=0, max_iter=50).fit_transform(Xs))
        t("Isomap", lambda: Isomap(n_components=2, n_neighbors=10).fit_transform(Xs))
        t("LLE", lambda: LocallyLinearEmbedding(n_components=2, n_neighbors=10).fit_transform(Xs))
        t("SpectralEmbed", lambda: SpectralEmbedding(n_components=2, n_neighbors=10).fit_transform(Xs))
        t("MLPClassifier", lambda: MLPClassifier(hidden_layer_sizes=(20,), max_iter=50, random_state=0).fit(Xt, yt).score(Xte, yte))
        t("MLPRegressor", lambda: MLPRegressor(hidden_layer_sizes=(20,), max_iter=50, random_state=0).fit(Xrt, yrt).predict(Xrte))
        t("GaussianProcessCls", lambda: GaussianProcessClassifier(random_state=0).fit(Xs[:30], ys[:30]).predict(Xs[:5]))
        t("GaussianProcessReg", lambda: GaussianProcessRegressor(random_state=0).fit(Xrt[:30], yrt[:30]).predict(Xrte[:5]))
        t("LDA", lambda: LinearDiscriminantAnalysis().fit(Xt, yt).score(Xte, yte))
        t("QDA", lambda: QuadraticDiscriminantAnalysis().fit(Xt, yt).score(Xte, yte))
        t("GaussianMixture", lambda: GaussianMixture(3, random_state=0).fit(Xc).predict(Xc))
        t("BayesianGMM", lambda: BayesianGaussianMixture(3, random_state=0).fit(Xc).predict(Xc))

        S("SKLEARN — Metrics (28)")
        from sklearn.metrics import *
        yt_c = np.array([0,0,1,1,0,1,1,0,1,0])
        yp_c = np.array([0,1,1,1,0,0,1,0,1,0])
        yprob = np.array([0.1,0.6,0.8,0.9,0.2,0.4,0.7,0.3,0.85,0.15])
        yt_r, yp_r = np.array([1.0,2.0,3.0,4.0,5.0]), np.array([1.1,2.2,2.8,4.1,4.9])
        t("accuracy", lambda: accuracy_score(yt_c, yp_c))
        t("confusion_matrix", lambda: confusion_matrix(yt_c, yp_c))
        t("f1", lambda: f1_score(yt_c, yp_c))
        t("precision", lambda: precision_score(yt_c, yp_c))
        t("recall", lambda: recall_score(yt_c, yp_c))
        t("balanced_accuracy", lambda: balanced_accuracy_score(yt_c, yp_c))
        t("roc_auc", lambda: roc_auc_score(yt_c, yprob))
        t("log_loss", lambda: log_loss(yt_c, yprob))
        t("roc_curve", lambda: roc_curve(yt_c, yprob))
        t("pr_curve", lambda: precision_recall_curve(yt_c, yprob))
        t("matthews_corrcoef", lambda: matthews_corrcoef(yt_c, yp_c))
        t("cohen_kappa", lambda: cohen_kappa_score(yt_c, yp_c))
        t("hamming_loss", lambda: hamming_loss(yt_c, yp_c))
        t("jaccard", lambda: jaccard_score(yt_c, yp_c))
        t("brier_score", lambda: brier_score_loss(yt_c, yprob))
        t("r2", lambda: r2_score(yt_r, yp_r))
        t("mse", lambda: mean_squared_error(yt_r, yp_r))
        t("mae", lambda: mean_absolute_error(yt_r, yp_r))
        t("max_error", lambda: max_error(yt_r, yp_r))
        t("median_abs_err", lambda: median_absolute_error(yt_r, yp_r))
        t("MAPE", lambda: mean_absolute_percentage_error(yt_r, yp_r))
        t("explained_var", lambda: explained_variance_score(yt_r, yp_r))
        t("pairwise_dist", lambda: pairwise_distances(Xc[:10]))
        t("silhouette", lambda: silhouette_score(Xc, KMeans(3,random_state=0,n_init=3).fit_predict(Xc)))
        t("calinski", lambda: calinski_harabasz_score(Xc, KMeans(3,random_state=0,n_init=3).fit_predict(Xc)))
        t("davies_bouldin", lambda: davies_bouldin_score(Xc, KMeans(3,random_state=0,n_init=3).fit_predict(Xc)))
        t("adjusted_rand", lambda: adjusted_rand_score([0,0,1,1,2,2],[0,0,1,1,1,2]))

        S("SKLEARN — Pipeline/Impute/Feature/Inspect (9)")
        from sklearn.pipeline import Pipeline, make_pipeline
        from sklearn.impute import SimpleImputer, KNNImputer
        from sklearn.feature_extraction import CountVectorizer, TfidfVectorizer
        from sklearn.feature_selection import SelectKBest, VarianceThreshold
        from sklearn.inspection import permutation_importance
        t("Pipeline", lambda: Pipeline([('s',StandardScaler()),('lr',LogisticRegression())]).fit(Xt,yt).score(Xte,yte))
        t("make_pipeline", lambda: make_pipeline(StandardScaler(), Ridge()).fit(Xrt,yrt).score(Xrte,yrte))
        t("SimpleImputer", lambda: SimpleImputer().fit_transform([[1,np.nan],[3,4],[np.nan,6]]))
        t("KNNImputer", lambda: KNNImputer().fit_transform([[1,np.nan],[3,4],[np.nan,6],[2,3]]))
        t("SelectKBest", lambda: SelectKBest(k=3).fit_transform(Xt, yt))
        t("VarianceThreshold", lambda: VarianceThreshold().fit_transform(Xp))
        t("CountVectorizer", lambda: CountVectorizer().fit_transform(["hello world","world peace"]))
        t("TfidfVectorizer", lambda: TfidfVectorizer().fit_transform(["hello world","world peace"]))
        t("permutation_imp", lambda: permutation_importance(Ridge().fit(Xrt,yrt), Xrte, yrte, n_repeats=2, random_state=0))

        S("MATPLOTLIB — Modules + Colormaps")
        import matplotlib
        import matplotlib.pyplot as plt
        import matplotlib.cm as cm
        import matplotlib.colors as mcolors
        t("version", lambda: matplotlib.__version__)
        t("cm.viridis", lambda: cm.viridis(0.5))
        t("cm.plasma", lambda: cm.plasma(np.linspace(0,1,5)))
        t("cm.jet", lambda: cm.jet(0.3))
        t("cm.coolwarm", lambda: cm.coolwarm(0.9))
        t("cm.get_cmap", lambda: cm.get_cmap('hot'))
        t("to_rgba('red')", lambda: mcolors.to_rgba('red'))
        t("to_rgba(hex)", lambda: mcolors.to_rgba('#FF5500'))
        t("to_hex", lambda: mcolors.to_hex((1,0,0)))
        t("Normalize", lambda: mcolors.Normalize(0,10)(5))
        t("CSS4_COLORS", lambda: len(mcolors.CSS4_COLORS))
        for mod in ['patches','ticker','animation','gridspec','lines','image','text','collections','path','transforms','legend','artist','axes','axis','colorbar','contour','dates','scale','widgets','offsetbox','cbook','spines','table','markers','patheffects','font_manager','backend_bases','style','projections','tri','backends']:
            t(f"mpl.{mod}", lambda m=mod: __import__(f'matplotlib.{m}'))
        t("mpl_toolkits.mplot3d", lambda: __import__('mpl_toolkits.mplot3d'))
        t("mpl_toolkits.axes_grid1", lambda: __import__('mpl_toolkits.axes_grid1'))
        t("mpl_toolkits.axisartist", lambda: __import__('mpl_toolkits.axisartist'))

        S("SYMPY")
        from sympy import (symbols, solve, diff, integrate, sin, cos, exp, log, pi, oo, series, limit, Matrix, simplify, factor, expand, Eq, sqrt, Rational, Sum, lambdify, latex)
        x, y = symbols('x y')
        t("solve x²-5x+6", lambda: solve(x**2-5*x+6, x))
        t("diff sin(x)e^x", lambda: diff(sin(x)*exp(x), x))
        t("integrate x²cos", lambda: integrate(x**2*cos(x), x))
        t("limit sin(x)/x", lambda: limit(sin(x)/x, x, 0))
        t("series e^x", lambda: series(exp(x), x, 0, 6))
        t("Matrix det", lambda: Matrix([[1,2],[3,4]]).det())
        t("simplify", lambda: simplify((x**2-1)/(x-1)))
        t("factor x³-1", lambda: factor(x**3-1))
        t("expand (x+y)³", lambda: expand((x+y)**3))
        t("Sum 1/n²", lambda: Sum(1/x**2, (x, 1, oo)).doit())
        t("lambdify", lambda: lambdify(x, sin(x)*exp(-x))(1.0))
        t("latex", lambda: latex(integrate(exp(-x**2), x)))

        S("NETWORKX")
        import networkx as nx
        t("erdos_renyi", lambda: nx.erdos_renyi_graph(30, 0.3, seed=42))
        t("shortest_path", lambda: nx.shortest_path(nx.path_graph(10), 0, 9))
        t("pagerank", lambda: nx.pagerank(nx.erdos_renyi_graph(20, 0.3, seed=42)))
        t("betweenness", lambda: nx.betweenness_centrality(nx.karate_club_graph()))
        t("min_span_tree", lambda: nx.minimum_spanning_tree(nx.complete_graph(6)))
        t("barabasi_albert", lambda: nx.barabasi_albert_graph(50, 2, seed=42))
        t("topo_sort", lambda: list(nx.topological_sort(nx.DiGraph([(1,2),(2,3),(1,3)]))))

        S("PIL / PILLOW")
        from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
        t("Image.new", lambda: Image.new('RGB', (100, 100), 'red'))
        t("ImageDraw", lambda: ImageDraw.Draw(Image.new('RGB',(100,100))).rectangle([10,10,90,90], fill='blue'))
        t("BLUR filter", lambda: Image.new('RGB',(50,50)).filter(ImageFilter.BLUR))
        t("Brightness", lambda: ImageEnhance.Brightness(Image.new('RGB',(50,50))).enhance(1.5))
        t("resize", lambda: Image.new('RGB',(100,100)).resize((50,50)))
        t("rotate", lambda: Image.new('RGB',(100,100)).rotate(45))
        t("convert L", lambda: Image.new('RGB',(100,100)).convert('L'))

        S("OTHER LIBS")
        t("mpmath", lambda: __import__('mpmath').mpf('3.141592653589793238'))
        t("bs4", lambda: __import__('bs4').BeautifulSoup('<h1>Hi</h1>','html.parser').h1.text)
        t("yaml", lambda: __import__('yaml').safe_load('x: 1'))
        t("tqdm", lambda: list(__import__('tqdm').tqdm(range(5), disable=True)))
        t("rich", lambda: __import__('rich.console',fromlist=['Console']).Console)
        t("click", lambda: __import__('click').command)
        t("jsonschema", lambda: __import__('jsonschema').validate({"n":"t"}, {"type":"object"}))
        t("pygments", lambda: list(__import__('pygments').lex('x=1', __import__('pygments.lexers',fromlist=['PythonLexer']).PythonLexer())))
        t("pydub", lambda: __import__('pydub').AudioSegment)
        t("svgelements", lambda: __import__('svgelements').SVG)
        t("packaging", lambda: __import__('packaging.version',fromlist=['Version']).Version('2.0.0'))
        t("cffi", lambda: __import__('cffi').FFI())
        t("manim", lambda: __import__('manim').Circle)
        t("manim Scene", lambda: __import__('manim').Scene)
        t("manim Text", lambda: __import__('manim').Text)

        S("FINAL RESULTS")
        elapsed = time.time() - _t0
        p = _offlinai_test_pass
        f = _offlinai_test_fail
        errs = _offlinai_test_errors
        total = p + f
        pct = (p / total * 100) if total else 0
        print("\\nPASSED: " + str(p) + "/" + str(total) + " (" + str(round(pct,1)) + "%)")
        print("FAILED: " + str(f) + "/" + str(total))
        print("TIME:   " + str(round(elapsed,1)) + "s")
        [print("  FAIL " + ne[0] + ": " + ne[1]) for ne in errs]
        print("\\n" + "=" * 50)
        """),
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

    // Editor
    private let editorContainer = UIView()
    private let gutterView = UIView()
    private let lineNumberLabel = UILabel()
    private let codeTextView = UITextView()

    // AI Chat
    private let chatContainer = UIView()
    private let chatTitleLabel = UILabel()
    private let modelSelectorButton = UIButton(type: .system)
    private let chatScrollView = UIScrollView()
    private let chatStackView = UIStackView()
    private let chatInputField = UITextField()
    private let chatSendButton = UIButton(type: .system)

    // Terminal
    private let terminalContainer = UIView()
    private let terminalTitleBar = UIView()
    private let terminalTitleLabel = UILabel()
    private let terminalTextView = UITextView()
    private var terminalHeightConstraint: NSLayoutConstraint!
    private let terminalDragHandle = UIView()

    // Image / chart output
    private let imageOutputView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .white
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()
    private let chartWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.layer.cornerRadius = 8
        wv.clipsToBounds = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.isHidden = true
        return wv
    }()

    // Layout
    private let topStack = UIStackView()
    private let mainStack = UIStackView()
    private var chatWidthConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EditorTheme.background
        setupToolbar()
        setupEditor()
        setupAIChat()
        setupTerminal()
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

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolbarStack = UIStackView(arrangedSubviews: [languageControl, runButton, clearButton, templatesButton, spacer, aiToggleButton])
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
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.backgroundColor = EditorTheme.chatBg
        chatContainer.layer.cornerRadius = 8
        chatContainer.clipsToBounds = true

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

        chatContainer.addSubview(chatHeaderRow)
        chatContainer.addSubview(chatScrollView)
        chatContainer.addSubview(inputRow)

        NSLayoutConstraint.activate([
            chatHeaderRow.topAnchor.constraint(equalTo: chatContainer.topAnchor, constant: 10),
            chatHeaderRow.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 10),
            chatHeaderRow.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -10),

            chatScrollView.topAnchor.constraint(equalTo: chatHeaderRow.bottomAnchor, constant: 8),
            chatScrollView.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 8),
            chatScrollView.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -8),
            chatScrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor, constant: -8),

            chatStackView.topAnchor.constraint(equalTo: chatScrollView.topAnchor),
            chatStackView.leadingAnchor.constraint(equalTo: chatScrollView.leadingAnchor),
            chatStackView.trailingAnchor.constraint(equalTo: chatScrollView.trailingAnchor),
            chatStackView.bottomAnchor.constraint(equalTo: chatScrollView.bottomAnchor),
            chatStackView.widthAnchor.constraint(equalTo: chatScrollView.widthAnchor),

            inputRow.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 8),
            inputRow.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -8),
            inputRow.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -8),
            inputRow.heightAnchor.constraint(equalToConstant: 36),

            chatSendButton.widthAnchor.constraint(equalToConstant: 36),
            chatSendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: - Setup Terminal

    /// Constraint that pins textView.top below chart/image when visible
    private var terminalTextTopToChartConstraint: NSLayoutConstraint!
    /// Constraint that pins textView.top to title bar when no chart
    private var terminalTextTopToTitleConstraint: NSLayoutConstraint!
    /// Height constraint for chart/image area
    private var chartHeightConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!

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

        // Terminal output
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
        // Add chart/image AFTER textView so they render on top
        terminalContainer.addSubview(imageOutputView)
        terminalContainer.addSubview(chartWebView)

        // Chart and image share the same slot (only one visible at a time)
        chartHeightConstraint = chartWebView.heightAnchor.constraint(equalToConstant: 280)
        imageHeightConstraint = imageOutputView.heightAnchor.constraint(equalToConstant: 280)

        // Two mutually exclusive top anchors for terminalTextView:
        // 1) Directly below title bar (no chart)
        terminalTextTopToTitleConstraint = terminalTextView.topAnchor.constraint(equalTo: terminalTitleBar.bottomAnchor)
        // 2) Below chart/image area
        terminalTextTopToChartConstraint = terminalTextView.topAnchor.constraint(equalTo: terminalTitleBar.bottomAnchor, constant: 288)

        terminalTextTopToTitleConstraint.isActive = true
        terminalTextTopToChartConstraint.isActive = false

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

            // Image output (hidden by default)
            imageOutputView.topAnchor.constraint(equalTo: terminalTitleBar.bottomAnchor, constant: 4),
            imageOutputView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 4),
            imageOutputView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -4),
            imageHeightConstraint,

            // Chart web view (hidden by default)
            chartWebView.topAnchor.constraint(equalTo: terminalTitleBar.bottomAnchor, constant: 4),
            chartWebView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 4),
            chartWebView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -4),
            chartHeightConstraint,

            // Text view fills remaining space
            terminalTextView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminalTextView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            terminalTextView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
        ])

        // Pan gesture for resizing
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTerminalDrag(_:)))
        terminalTitleBar.addGestureRecognizer(pan)
    }

    // MARK: - Layout

    private func setupLayout() {
        // Top section: editor + AI chat side by side
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.axis = .horizontal
        topStack.spacing = 2
        topStack.distribution = .fill
        topStack.addArrangedSubview(editorContainer)
        topStack.addArrangedSubview(chatContainer)

        chatWidthConstraint = chatContainer.widthAnchor.constraint(equalTo: topStack.widthAnchor, multiplier: 0.35)
        chatWidthConstraint.isActive = true

        // Main vertical stack: top + terminal
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 2
        mainStack.addArrangedSubview(toolbar)
        mainStack.addArrangedSubview(topStack)
        mainStack.addArrangedSubview(terminalContainer)

        view.addSubview(mainStack)

        terminalHeightConstraint = terminalContainer.heightAnchor.constraint(equalToConstant: 200)
        terminalHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbar.heightAnchor.constraint(equalToConstant: 48),
            terminalHeightConstraint
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
        imageOutputView.isHidden = true
        imageOutputView.image = nil
        chartWebView.isHidden = true

        // Reset layout
        terminalTextTopToChartConstraint.isActive = false
        terminalTextTopToTitleConstraint.isActive = true
        terminalTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        terminalHeightConstraint.constant = 200
        view.layoutIfNeeded()
    }

    @objc private func toggleAIChat() {
        isAIChatVisible.toggle()
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.chatContainer.isHidden = !self.isAIChatVisible
            self.chatWidthConstraint.isActive = self.isAIChatVisible
            self.topStack.layoutIfNeeded()
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

    // MARK: - Image Output

    private func showImageOutput(path: String?) {
        // Hide both first
        imageOutputView.isHidden = true
        imageOutputView.image = nil
        chartWebView.isHidden = true

        // Reset text view position to directly below title bar
        terminalTextTopToChartConstraint.isActive = false
        terminalTextTopToTitleConstraint.isActive = true
        terminalTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        guard let path = path, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            // Shrink terminal back to normal size
            terminalHeightConstraint.constant = 200
            view.layoutIfNeeded()
            return
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        var showingChart = false

        if ext == "html" {
            chartWebView.isHidden = false
            chartWebView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            showingChart = true
        } else if ["png", "jpg", "jpeg", "gif"].contains(ext) {
            if let image = UIImage(contentsOfFile: path) {
                imageOutputView.image = image
                imageOutputView.isHidden = false
                showingChart = true
            }
        }

        if showingChart {
            // Push text view below the chart/image area
            terminalTextTopToTitleConstraint.isActive = false
            terminalTextTopToChartConstraint.isActive = true

            // Expand terminal to fit chart (280) + text area (120) + title bar (28) + padding
            let expandedHeight: CGFloat = 440
            UIView.animate(withDuration: 0.25) {
                self.terminalHeightConstraint.constant = expandedHeight
                self.view.layoutIfNeeded()
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
