// swift-tools-version: 5.9
// python-ios-lib — Offline Python libraries for iOS/iPadOS
// https://github.com/yu314-coder/python-ios-lib
//
// In Xcode: File → Add Package Dependencies → paste:
//   https://github.com/yu314-coder/python-ios-lib
// Then pick which packages you need. Dependencies auto-resolve.

import PackageDescription

let package = Package(
    name: "python-ios-lib",
    platforms: [.iOS(.v17)],
    products: [
        // ── Language interpreters (standalone, no Python runtime needed) ──
        .library(name: "CInterpreter", targets: ["CInterpreter"]),
        .library(name: "CppInterpreter", targets: ["CppInterpreter"]),
        .library(name: "FortranInterpreter", targets: ["FortranInterpreter"]),
        .library(name: "NumPy", targets: ["NumPy"]),
        .library(name: "SymPy", targets: ["SymPy"]),
        .library(name: "Plotly", targets: ["Plotly"]),
        .library(name: "NetworkX", targets: ["NetworkX"]),
        .library(name: "Pillow", targets: ["Pillow"]),
        .library(name: "BeautifulSoup", targets: ["BeautifulSoup"]),
        .library(name: "Requests", targets: ["Requests"]),
        .library(name: "PyYAML", targets: ["PyYAML"]),
        .library(name: "Rich", targets: ["Rich"]),
        .library(name: "Tqdm", targets: ["Tqdm"]),
        .library(name: "Click", targets: ["Click"]),
        .library(name: "Cloup", targets: ["Cloup", "Click"]),
        .library(name: "Mapbox_earcut", targets: ["Mapbox_earcut"]),
        .library(name: "Isosurfaces", targets: ["Isosurfaces"]),
        .library(name: "Markupsafe", targets: ["Markupsafe"]),
        .library(name: "Jinja2", targets: ["Jinja2", "Markupsafe"]),
        .library(name: "Screeninfo", targets: ["Screeninfo"]),
        .library(name: "Watchdog", targets: ["Watchdog"]),
        .library(name: "Fsspec", targets: ["Fsspec"]),
        .library(name: "Moderngl",         targets: ["Moderngl"]),
        .library(name: "Moderngl_window",  targets: ["Moderngl_window", "Moderngl"]),
        .library(name: "Typing_extensions",targets: ["Typing_extensions"]),
        .library(name: "Psutil",           targets: ["Psutil"]),
        .library(name: "Pygments", targets: ["Pygments"]),
        .library(name: "Mpmath", targets: ["Mpmath"]),
        .library(name: "Pydub", targets: ["Pydub"]),
        .library(name: "JsonSchema", targets: ["JsonSchema"]),
        .library(name: "CairoGraphics", targets: ["CairoGraphics"]),
        .library(name: "FFmpegPyAV", targets: ["FFmpegPyAV"]),
        .library(name: "Decorator", targets: ["Decorator"]),
        .library(name: "PyWebView", targets: ["PyWebView"]),

        // ── Web frameworks + scientific extras (2026-05) ──
        // Tropycal is standalone. Flask brings its full pure-Python
        // stack so it actually runs (Werkzeug + Jinja2 + Markupsafe +
        // Click). Dash bundles Flask + Plotly because that's the
        // minimum that lets dash.Dash().run() serve a usable page.
        // Streamlit lists PyArrow as a dep so SPM expresses the build
        // graph correctly — but PyArrow is a placeholder target (no
        // bundled binaries), so Streamlit's dataframe features error
        // at runtime until someone cross-compiles Arrow C++ for iOS.
        // See Sources/PyArrow/BUILD_INSTRUCTIONS.md.
        .library(name: "Tropycal", targets: ["Tropycal"]),
        .library(name: "Werkzeug", targets: ["Werkzeug"]),
        .library(name: "Flask",    targets: ["Flask", "Werkzeug", "Jinja2",
                                              "Markupsafe", "Click"]),
        .library(name: "Dash",     targets: ["Dash", "Flask", "Werkzeug",
                                              "Jinja2", "Markupsafe", "Click",
                                              "Plotly"]),
        .library(name: "PyArrow",  targets: ["PyArrow"]),
        .library(name: "Streamlit", targets: ["Streamlit", "Click", "Watchdog",
                                               "Typing_extensions", "PyArrow",
                                               "Tornado"]),
        .library(name: "Tornado",  targets: ["Tornado"]),
        .library(name: "Xxhash",   targets: ["Xxhash"]),
        .library(name: "Rapidfuzz",   targets: ["Rapidfuzz"]),
        .library(name: "Levenshtein", targets: ["Levenshtein", "Rapidfuzz"]),
        // Performance-accelerator block (added 2026-05-26):
        .library(name: "Orjson",     targets: ["Orjson"]),     // fast JSON
        .library(name: "Uvloop",     targets: ["Uvloop"]),     // fast asyncio
        .library(name: "Ciso8601",   targets: ["Ciso8601"]),   // fast ISO date parse
        .library(name: "Numexpr",    targets: ["Numexpr"]),    // fast NumPy expressions
        .library(name: "Bottleneck", targets: ["Bottleneck"]), // fast NaN/rolling stats

        // ── Multi-target umbrella products ──
        // Each tick in Xcode's product picker adds EVERY listed target's
        // framework + resource bundle to the consumer's project.pbxproj.
        // Without these, SPM's `target.dependencies` only build them
        // — Xcode never writes them into Frameworks/Libraries/Embedded
        // Content, so the .app ships missing every transitive dep.
        // (See https://forums.swift.org for "SPM transitive resources
        // not embedded" — this is the standard workaround.)

        // ── Requires NumPy ──
        .library(name: "Sklearn", targets: ["Sklearn", "NumPy", "SciPy"]),
        // SciPy auto-bundles its Fortran runtime (libfortran_io_stubs +
        // libsf_error_state) as resources of the SciPy target itself,
        // so this product needs no separate "ScipyRuntime" target.
        .library(name: "SciPy",   targets: ["SciPy",   "NumPy"]),

        // ── Requires Plotly ──
        // Matplotlib now also pulls Dateutil (matplotlib/dates.py hard
        // dep) so date-axis plots work for SwiftPM consumers.
        .library(name: "Matplotlib", targets: ["Matplotlib", "Plotly", "Dateutil"]),

        // python-dateutil — standalone product for consumers that want
        // just the date utilities without the whole matplotlib stack.
        .library(name: "Dateutil", targets: ["Dateutil"]),

        // ── Requires multiple deps ──
        // Manim covers the entire animation stack. Hard-imports at
        // module load (every entry below crashes `import manim` if
        // missing — traced from manim/__init__.py through
        // utils/space_ops.py and _config):
        //   numpy, scipy, mapbox_earcut, cloup, click, rich, PIL,
        //   decorator
        // Required by specific mobjects / features:
        //   matplotlib + plotly (plot mobjects)
        //   ffmpeg/pyav (Scene.render → mp4)
        //   cairo/pango/harfbuzz (manimpango text shaping)
        //   tqdm (render progress bar)
        //   latex (MathTex/Tex compile)
        //   pillow (image_mobject, camera, scene_file_writer)
        //   networkx (Graph mobject)
        //   pygments (Code mobject syntax highlighting)
        //   jinja2 (manim's HTML/SVG export templating)
        //   isosurfaces (3D surface plotting)
        //   screeninfo (camera defaults — multi-monitor query)
        //   watchdog (--auto-rerun file-watch mode)
        // One tick → all 21 ride along.
        .library(name: "Manim",
                 targets: ["Manim", "NumPy", "SciPy",
                           "Matplotlib", "Plotly",
                           "FFmpegPyAV", "CairoGraphics", "LaTeXEngine",
                           "Pillow", "Tqdm", "Rich", "Click", "Cloup",
                           "NetworkX", "Pygments", "SymPy", "Sklearn",
                           "Decorator", "Mapbox_earcut", "Isosurfaces",
                           "Jinja2", "Markupsafe", "FontTools", "Dateutil",
                           "Screeninfo", "Watchdog",
                           "Typing_extensions", "Psutil",
                           "Moderngl", "Moderngl_window",
                           "Pydub", "BeautifulSoup",
                           // ── Transitive runtime imports that were
                           //    silently missing on SwiftPM consumers.
                           // Requests bundles urllib3/certifi/idna/
                           // charset_normalizer; without it any user code
                           // doing requests.get(...) ImportErrors at
                           // module load on the iOS target even though
                           // CodeBench shipped them in the bundled
                           // app_packages. Mpmath is a hard SymPy dep
                           // (arbitrary-precision math). PyYAML is read
                           // by manim's config loader. JsonSchema is
                           // required by Plotly + Jupyter for figure
                           // validation. Fsspec / Tornado are optional
                           // but pulled in by huggingface_hub and
                           // web-stack libs that manim users commonly
                           // combine with their scenes.
                           "Requests", "Mpmath", "PyYAML", "JsonSchema",
                           "Fsspec", "Tornado"]),
        // LaTeXEngine renders SVG via cairo — bundle it together.
        .library(name: "LaTeXEngine",
                 targets: ["LaTeXEngine", "CairoGraphics"]),

        // ── Machine Learning: PyTorch + HuggingFace stack ──
        .library(name: "PyTorch",      targets: ["PyTorch"]),
        .library(name: "Tokenizers",   targets: ["Tokenizers"]),
        .library(name: "Transformers",
                 targets: ["Transformers", "PyTorch", "Tokenizers"]),
    ],
    targets: [
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  STANDALONE — No dependencies
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // C interpreter (~3,661-line tree-walking interpreter, single C file).
        // C89/C99/C23, 48 operators, structs, pointers, full preprocessor.
        .target(
            name: "CInterpreter",
            path: "gcc",
            sources: ["offlinai_cc.c"],
            publicHeadersPath: "."
        ),

        // C++ interpreter (~4,287 lines). Classes, STL, templates, inheritance.
        .target(
            name: "CppInterpreter",
            path: "cpp",
            sources: ["offlinai_cpp.c"],
            publicHeadersPath: "."
        ),

        // Fortran interpreter (~3,876 lines). Modules, allocatable arrays,
        // 45+ intrinsics, subroutines, functions.
        .target(
            name: "FortranInterpreter",
            path: "fortran",
            sources: ["offlinai_fortran.c"],
            publicHeadersPath: "."
        ),

        // NumPy 2.3.5 — native iOS build (arrays, linalg, FFT, random)
        .target(name: "NumPy", path: "Sources/NumPy", resources: [.copy("numpy"),
            .copy("numpy-2.3.5.post1.dist-info")]),

        // SymPy 1.14 — symbolic math (pure Python)
        .target(name: "SymPy", path: "Sources/SymPy", resources: [.copy("sympy"),
            .copy("sympy-1.14.0.dist-info")]),

        // Plotly 6.6 — interactive charts (pure Python).
        // Bundles the sibling _plotly_utils package too — plotly's
        // __init__.py imports from _plotly_utils.basevalidators et al.,
        // which ships as a separate top-level package.
        .target(name: "Plotly", path: "Sources/Plotly",
                resources: [.copy("plotly"), .copy("_plotly_utils"),
                            .copy("plotly-6.6.0.dist-info")]),

        // NetworkX 3.6 — graph theory (pure Python)
        .target(name: "NetworkX", path: "Sources/NetworkX", resources: [.copy("networkx"),
            .copy("networkx-3.6.1.dist-info")]),

        // Pillow 12.2 — image processing (native iOS build)
        .target(name: "Pillow", path: "Sources/Pillow", resources: [.copy("PIL"),
            .copy("pillow-11.0.0.dist-info")]),

        // BeautifulSoup4 — HTML/XML parsing (pure Python)
        .target(name: "BeautifulSoup", path: "Sources/BeautifulSoup", resources: [.copy("bs4"),
            .copy("beautifulsoup4-4.14.3.dist-info"),
            .copy("bs4-4.14.3.dist-info"),
            .copy("soupsieve-2.8.dist-info"),
            .copy("soupsieve")]),

        // requests — HTTP client (pure Python)
        .target(name: "Requests", path: "Sources/Requests", resources: [.copy("requests"),
            .copy("certifi-2026.2.25.dist-info"),
            .copy("charset_normalizer-3.4.7.dist-info"),
            .copy("idna-3.11.dist-info"),
            .copy("requests-2.33.1.dist-info"),
            .copy("urllib3-2.6.3.dist-info"),
            .copy("charset_normalizer"),
            .copy("certifi"),
            .copy("idna"),
            .copy("urllib3")]),

        // PyYAML — YAML parser (native build)
        .target(name: "PyYAML", path: "Sources/PyYAML", resources: [.copy("yaml"),
            .copy("pyyaml-6.0.3.dist-info")]),

        // rich — rich text, tables, progress bars (pure Python)
        .target(name: "Rich", path: "Sources/Rich", resources: [.copy("rich"),
            .copy("markdown_it_py-3.0.0.dist-info"),
            .copy("mdurl-0.1.2.dist-info"),
            .copy("rich-13.7.0.dist-info"),
            .copy("markdown_it"),
            .copy("mdurl")]),

        // tqdm — progress bars (pure Python)
        .target(name: "Tqdm", path: "Sources/Tqdm", resources: [.copy("tqdm"),
            .copy("tqdm-4.67.3.dist-info")]),

        // click — CLI framework (pure Python)
        .target(name: "Click", path: "Sources/Click", resources: [.copy("click"),
            .copy("click-8.1.7.dist-info")]),

        // cloup — click extension (option groups, constraints, sub-command
        // groups with section headers). Hard-imported by manim/_config at
        // module load — without it `import manim` fails before any code
        // runs. Pure Python, ~212 KB.
        .target(name: "Cloup",
                dependencies: ["Click"],
                path: "Sources/Cloup",
                resources: [.copy("cloup"),
            .copy("cloup-3.0.5.dist-info")]),

        // mapbox_earcut — polygon triangulation (164 KB, native .so).
        // Hard-imported by manim/utils/space_ops.py at module load.
        .target(name: "Mapbox_earcut", path: "Sources/Mapbox_earcut",
                resources: [.copy("mapbox_earcut"),
            .copy("mapbox_earcut-1.0.3.dist-info")]),

        // isosurfaces — 3D surface algorithm. Hard-imported by manim's
        // surface mobjects.
        .target(name: "Isosurfaces", path: "Sources/Isosurfaces",
                resources: [.copy("isosurfaces"),
            .copy("isosurfaces-0.1.2.dist-info")]),

        // markupsafe — XML/HTML escape utilities. Required by Jinja2
        // (Jinja2 hard-imports `markupsafe` at module load).
        .target(name: "Markupsafe", path: "Sources/Markupsafe",
                resources: [.copy("markupsafe"),
            .copy("markupsafe-3.0.3.dist-info")]),

        // jinja2 — templating engine. Used by manim for its HTML/SVG
        // export templates and by torch's inductor codegen path.
        .target(name: "Jinja2",
                dependencies: ["Markupsafe"],
                path: "Sources/Jinja2",
                resources: [.copy("jinja2"),
            .copy("jinja2-3.1.6.dist-info")]),

        // fontTools 4.60.2 — TTF/OTF parser + SVG path emitter. manimpango
        // hard-imports `fontTools.ttLib.TTFont` and
        // `fontTools.pens.svgPathPen.SVGPathPen` at module load to read
        // installed fonts and rasterise per-codepoint vector paths for
        // `Text` mobjects. Without this target SwiftPM consumers of the
        // Manim product fall through to manimpango's "fontTools not
        // available — minimal SVG fallback" branch (search
        // `Sources/Manim/manimpango/__init__.py` for that string), which
        // emits an empty SVG box where the text glyphs should be.
        // No dist-info wheel — fontTools was source-installed, so we
        // ship the package directory only.
        .target(name: "FontTools", path: "Sources/FontTools",
                resources: [.copy("fontTools")]),

        // screeninfo — multi-monitor query. manim's camera reads this
        // to decide default frame size if not configured.
        .target(name: "Screeninfo", path: "Sources/Screeninfo",
                resources: [.copy("screeninfo"),
            .copy("screeninfo-0.8.1.dist-info")]),

        // watchdog — file-system event observer. Used by manim's
        // --auto-rerun and `manim render` hot-reload modes.
        .target(name: "Watchdog", path: "Sources/Watchdog",
                resources: [.copy("watchdog"),
            .copy("watchdog-4.0.0.dist-info")]),

        // fsspec — filesystem-spec abstraction. Required by torch's
        // distributed checkpoint loaders + huggingface_hub's downloads.
        .target(name: "Fsspec", path: "Sources/Fsspec",
                resources: [.copy("fsspec"),
            .copy("fsspec-2026.3.0.dist-info")]),

        // Pygments — syntax highlighting (pure Python)
        .target(name: "Pygments", path: "Sources/Pygments", resources: [.copy("pygments"),
            .copy("pygments-2.18.0.dist-info")]),

        // mpmath — arbitrary precision math (pure Python)
        .target(name: "Mpmath", path: "Sources/Mpmath", resources: [.copy("mpmath"),
            .copy("mpmath-1.4.1.dist-info")]),

        // pydub — audio manipulation (pure Python)
        .target(name: "Pydub", path: "Sources/Pydub", resources: [.copy("pydub"),
            .copy("audioop_lts-0.2.1.dist-info"),
            .copy("pydub-0.25.1.dist-info"),
            .copy("audioop")]),

        // jsonschema — JSON validation (pure Python)
        .target(name: "JsonSchema", path: "Sources/JsonSchema", resources: [.copy("jsonschema"),
            .copy("attr-24.2.0.dist-info"),
            .copy("attrs-24.2.0.dist-info"),
            .copy("jsonschema-4.26.0.dist-info"),
            .copy("jsonschema_specifications-2024.10.1.dist-info"),
            .copy("referencing-0.36.2.dist-info"),
            .copy("rpds_py-0.22.3.dist-info"),
            .copy("attr"),
            .copy("attrs"),
            .copy("referencing"),
            .copy("rpds"),
            .copy("jsonschema_specifications")]),

        // decorator — single-file shim of Michele Simionato's decorator
        // package; provides `decorate` + `decorator` (manim's only deps
        // from it). Pure Python, ~150 LOC.
        .target(name: "Decorator", path: "Sources/Decorator", resources: [.copy("decorator.py"),
            .copy("decorator-5.1.1.dist-info")]),

        // pywebview — CodeBench shim of pywebview that routes
        // create_window/load_url/load_html into the host app's preview
        // pane via file-IPC instead of spawning a real native window
        // (which iOS forbids). Pure Python.
        .target(name: "PyWebView", path: "Sources/PyWebView", resources: [.copy("webview"),
            .copy("pywebview-5.4.0.dist-info")]),

        // pycairo Python bindings to cairo. Ships the full Python module
        // (cairo/__init__.py + _cairo.cpython-314-iphoneos.so), which
        // statically links libcairo + libpixman + libfreetype + libfribidi
        // into the .so. So `import cairo` gives the full Pythonic API
        // (cairo.LineJoin, cairo.LineCap, cairo.Context, …) without
        // needing any separate libcairo.dylib at runtime.
        //
        // pango / harfbuzz come along inside manimpango's own .so files
        // (manimpango is shipped via the Manim target). We don't ship
        // them as separate Python modules because there's no pycairo-
        // style Python binding for them — they're consumed via manimpango
        // and via cairo's text APIs.
        .target(name: "CairoGraphics", path: "Sources/CairoGraphics",
                resources: [.copy("cairo"),
                            .copy("pycairo-1.29.0.dist-info")]),

        // FFmpeg 62 + PyAV — video encoding/decoding (native iOS, 7 dylibs)
        .target(name: "FFmpegPyAV", path: "Sources/FFmpegPyAV", resources: [.copy("ffmpeg"), .copy("av"),
            .copy("av-17.0.1.dist-info")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES NUMPY — auto-included when you select these
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // scikit-learn — ML (40 modules). Needs: NumPy
        .target(name: "Sklearn", dependencies: ["NumPy"], path: "Sources/Sklearn", resources: [.copy("sklearn"),
            .copy("scikit_learn-1.8.0.dist-info")]),

        // SciPy — scientific computing. Needs: NumPy.
        // Bundles libfortran_io_stubs.dylib + libsf_error_state.dylib
        // (Fortran runtime for scipy's BLAS/LAPACK/sparse paths). Without
        // these, `import scipy.spatial` / `scipy.sparse` / `scipy.linalg`
        // crash at load with "symbol not found".
        .target(name: "SciPy",
                dependencies: ["NumPy"],
                path: "Sources/SciPy",
                resources: [.copy("scipy"), .copy("scipy_runtime"),
            .copy("scipy-1.15.0.dist-info")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES PLOTLY
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // matplotlib — Plotly backend (64 modules). Needs: Plotly
        .target(name: "Matplotlib", dependencies: ["Plotly", "Dateutil"], path: "Sources/Matplotlib", resources: [.copy("matplotlib"),
            .copy("matplotlib-3.9.0.dist-info"),
            .copy("narwhals-1.16.0.dist-info"),
            .copy("packaging-26.0.dist-info"),
            .copy("narwhals"),
            .copy("packaging"),
            // cycler is a hard matplotlib import (matplotlib/rcsetup.py →
            // `from cycler import Cycler, cycler`). It was bundled in
            // app_packages but never copied into this target, so SVM
            // consumers ImportError'd at `import matplotlib`. dateutil
            // (the other missing hard dep, used by matplotlib/dates.py)
            // comes in via the Dateutil target dependency above.
            .copy("cycler"),
            .copy("mpl_toolkits")]),

        // python-dateutil 2.x — date parsing / recurrence rules. A hard
        // import of matplotlib (matplotlib/dates.py → `from dateutil.rrule
        // import rrule`) AND pandas (pandas/_libs/tslibs needs it) AND a
        // long tail of other libraries. Ships partly as sourceless .pyc;
        // its `six` shim lives as a top-level six.pyc, bundled here too
        // (dateutil/rrule.py → `from six import advance_iterator`).
        // Shared target so matplotlib + pandas don't each duplicate it.
        // The package dirs are symlinks into app_packages (same pattern
        // as Sources/Matplotlib/matplotlib) → ~0 added repo bytes.
        .target(name: "Dateutil", path: "Sources/Dateutil",
                resources: [.copy("dateutil"), .copy("six.pyc")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES MULTIPLE DEPS — all auto-included
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // manim — math animations.
        // Needs: NumPy + Matplotlib + FFmpeg + Cairo + LaTeXEngine.
        // (LaTeXEngine is required because manim's `Tex` / `MathTex`
        // mobjects shell out to pdflatex via offlinai_latex, which is
        // the bridge target inside LaTeXEngine. Without it those
        // mobjects raise "pdflatex not found" at runtime.)
        // Adding `Manim` as a SwiftPM product dependency auto-includes
        // every transitive resource bundle below — Xcode's Product
        // Picker only needs Manim ticked.
        .target(name: "Manim",
                dependencies: ["NumPy", "SciPy",
                               "Matplotlib", "FFmpegPyAV",
                               "CairoGraphics", "LaTeXEngine",
                               "Pillow", "Tqdm", "Rich", "Click", "Cloup",
                               "NetworkX", "Pygments", "SymPy", "Sklearn",
                               "Decorator", "Mapbox_earcut", "Isosurfaces",
                               "Jinja2", "FontTools", "Dateutil",
                               "Screeninfo", "Watchdog",
                               "Typing_extensions", "Psutil",
                               "Moderngl", "Moderngl_window",
                               "Pydub", "BeautifulSoup"],
                path: "Sources/Manim",
                resources: [
            .copy("manim"), .copy("manimpango"), .copy("offlinai_latex"),
            .copy("svgelements"), .copy("pathops"),
            .copy("srt.py"),                         // single-file pkg, manim/scene/scene.py imports it
            .copy("manim-0.19.0.dist-info"),
            .copy("manimpango-0.6.1.dist-info"),
            .copy("offlinai_latex-1.0.1.dist-info"),
            .copy("skia_pathops-0.9.2.dist-info"),
            .copy("svgelements-1.9.6.dist-info"),
            .copy("srt-3.5.3.dist-info"),
        ]),

        // LaTeX engine — pdftex + texmf. Needs: Cairo
        .target(name: "LaTeXEngine", dependencies: ["CairoGraphics"], path: "Sources/LaTeXEngine", resources: [.copy("latex")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  MACHINE LEARNING — PyTorch + HuggingFace stack
        //  (native iOS arm64 — first public build of each on iOS)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // PyTorch 2.1.2 — full `import torch` on iPad (tensors, autograd,
        // nn, optim, JIT). 95/95 numerical + training correctness asserts.
        // libtorch_python.dylib (99 MB) ships via Git LFS.
        // typing_extensions.py: `torch.serialization`, `torch.optim`, onnx
        // exporter, etc. all `from typing_extensions import ...` at module
        // load — BeeWare's stdlib doesn't ship it so we bundle it alongside.
        .target(
            name: "PyTorch",
            path: "Sources/PyTorch",
            resources: [
                .copy("torch"),
                .copy("regex"),
                .copy("typing_extensions.py"),
                // libtorch_python.dylib (103MB) ships as an LZMA blob
                // because GitHub rejects raw blobs over 100MB and Git
                // LFS is incompatible with SwiftPM's checkout machinery.
                // Materialized to ~/Library/Caches at first use via
                // PyTorchLib.bootstrap() — see PyTorch.swift.
                .copy("torch_dylib"),
            .copy("regex-2024.11.6.dist-info"),
            .copy("torch-2.1.0.dist-info"),
            .copy("typing_extensions-4.15.0.dist-info"),
            ]
        ),

        // tokenizers 0.19.1 — HuggingFace's Rust tokenizers, cross-compiled
        // for iOS arm64 (first public iOS build). BPE/WordPiece/Unigram
        // trainers + fast tokenizers via PyO3.
        .target(
            name: "Tokenizers",
            path: "Sources/Tokenizers",
            resources: [.copy("tokenizers"),
            .copy("tokenizers-0.19.1.dist-info")]
        ),


        // moderngl — OpenGL bindings (alternative renderer to Cairo).
        // Only loaded by manim.renderer.opengl_renderer; lazy-imported.
        .target(name: "Moderngl", path: "Sources/Moderngl",
                resources: [.copy("moderngl")]),

        // moderngl_window — windowing layer for moderngl. Lazy-imported.
        .target(name: "Moderngl_window", path: "Sources/Moderngl_window",
                resources: [.copy("moderngl_window")]),

        // typing_extensions — backports of typing features. Many libs
        // (huggingface_hub, narwhals, pydantic-style codebases) hard-import
        // this at module load.
        .target(name: "Typing_extensions", path: "Sources/Typing_extensions",
                resources: [.copy("typing_extensions.py")]),

        // psutil — process/system info. Used by manim's render-pipeline
        // memory-tracking and by transformers' device introspection.
        .target(name: "Psutil", path: "Sources/Psutil",
                resources: [.copy("psutil")]),

        // transformers 4.41.2 — HuggingFace models (BERT, GPT-2, T5, BART).
        // Construct + train + generate + save/load on-device. Needs: PyTorch + Tokenizers.
        .target(
            name: "Transformers",
            dependencies: ["PyTorch", "Tokenizers"],
            path: "Sources/Transformers",
            resources: [
                .copy("transformers"),
                .copy("huggingface_hub"),
                .copy("filelock"),
                .copy("safetensors"),
            .copy("filelock-3.28.0.dist-info"),
            .copy("huggingface_hub-0.24.7.dist-info"),
            .copy("safetensors-0.4.5.dist-info"),
            .copy("transformers-4.41.2.dist-info"),
            ]
        ),

        // ─── New 2026-05 additions: web/data-app stacks ───────────────

        // tropycal 1.4 — tropical cyclone analysis (HURDAT2, IBTrACS,
        // climo statistics, storm-track utilities). Pure Python; the
        // map-plotting features need cartopy which isn't bundled, but
        // every data-analysis API works without it.
        .target(name: "Tropycal", path: "Sources/Tropycal",
                resources: [.copy("tropycal"),
                            .copy("tropycal-1.4.dist-info")]),

        // werkzeug 3.1 — WSGI utility layer; Flask's HTTP plumbing.
        // Pure Python.
        .target(name: "Werkzeug", path: "Sources/Werkzeug",
                resources: [.copy("werkzeug"),
                            .copy("werkzeug-3.1.8.dist-info")]),

        // flask 3.1 — web microframework. Pure Python. Listed deps
        // (Werkzeug / Jinja2 / Markupsafe / Click) are SPM dependencies
        // so they end up linked into anything that depends on Flask.
        .target(name: "Flask",
                dependencies: ["Werkzeug", "Jinja2", "Markupsafe", "Click"],
                path: "Sources/Flask",
                resources: [.copy("flask"),
                            .copy("flask-3.1.3.dist-info")]),

        // dash 4.1 — Plotly's reactive web framework. Pure Python.
        // The ~28 MB this adds is the prebuilt JS for dash-html-
        // components and dash-core-components that ships inside the
        // wheel; we can't strip it because Dash serves these as
        // static assets at runtime.
        .target(name: "Dash",
                dependencies: ["Flask", "Plotly"],
                path: "Sources/Dash",
                resources: [.copy("dash"),
                            .copy("dash-4.1.0.dist-info")]),

        // pyarrow 15.0.2 — cross-compiled for iOS arm64. The actual
        // tree is deployed via app_packages/site-packages/pyarrow/
        // rather than through the SPM resource bundle. Reason: when
        // SPM copies pyarrow's .so files into a Bundle.module, Xcode
        // promotes each one into a `*.framework/` wrapper directory,
        // which BREAKS `@rpath/libarrow_python.dylib` resolution —
        // dyld looks for the dylib inside the wrapper instead of
        // next to the .so where it actually sits.
        //
        // Living in app_packages/site-packages/ keeps the original
        // `.so + .dylib` colocated, so `@loader_path` resolves cleanly.
        // The SPM target is kept (as a Swift-only stub) so consumers
        // can still depend on it for the version stamp / namespace.
        //
        // To rebuild or extend (parquet, dataset, etc.) see
        // Sources/PyArrow/BUILD_INSTRUCTIONS.md.
        .target(name: "PyArrow", path: "Sources/PyArrow"),

        // streamlit 1.50 — data-app framework. Universal wheel; the
        // 23 MB of static/ is the prebuilt React frontend it serves.
        // Listed deps cover the pure-Python ones we already ship; the
        // heavy hitters (numpy/pandas/pillow/rich/requests) the user
        // ticks separately in Xcode since they're shared widely.
        // PyArrow dep is intentional: streamlit's import will error
        // clearly on iOS until the user supplies a real Arrow build.
        .target(name: "Streamlit",
                dependencies: ["Click", "Watchdog", "Typing_extensions",
                               "PyArrow", "Tornado"],
                path: "Sources/Streamlit",
                resources: [.copy("streamlit"),
                            .copy("streamlit-1.50.0.dist-info")]),

        // tornado 6.5 — async HTTP / websocket framework, required by
        // streamlit. The shipped wheel includes one optional C
        // extension (tornado.speedups) for websocket-mask SIMD; we
        // strip the .so on deploy because (a) it's a macOS Mach-O and
        // would fail to load on iOS, and (b) tornado has a pure-Python
        // fallback wrapped in try/except ImportError. Perf hit is
        // negligible for the dashboard-render workloads.
        .target(name: "Tornado",
                path: "Sources/Tornado",
                resources: [.copy("tornado"),
                            .copy("tornado-6.5.5.dist-info")]),

        // xxhash 3.7.0 — fast non-cryptographic hash (xxh32/64/3/128).
        // Single C extension (105 KB iOS arm64 .so) wrapping the bundled
        // xxhash C library. Common transitive dep of HuggingFace datasets,
        // polars, and many ML/data libs.
        .target(name: "Xxhash",
                path: "Sources/Xxhash",
                resources: [.copy("xxhash"),
                            .copy("xxhash-3.7.0.dist-info")]),

        // rapidfuzz 3.14.5 — fast string distance / fuzzy matching engine.
        // 6 native modules cross-compiled from Cython output (.cxx):
        //   _feature_detector_cpp (98 KB) — CPU SIMD detection (no-op on
        //     arm64 — patched CpuInfo.cpp to skip x86 cpuid intrinsics)
        //   fuzz_cpp (2.1 MB) — fuzz ratio, partial ratio, token sort
        //   utils_cpp (249 KB) — string normalization helpers
        //   process_cpp_impl (907 KB) — extract / extractOne over corpora
        //   distance/_initialize_cpp (361 KB) — distance scorer init
        //   distance/metrics_cpp (2.7 MB) — Levenshtein/Hamming/Jaro/etc.
        // Total native: ~6.4 MB. Header-only rapidfuzz-cpp + taskflow C++
        // libraries vendored at build time. Used directly OR as the engine
        // under Levenshtein (which is just a thin wrapper).
        .target(name: "Rapidfuzz",
                path: "Sources/Rapidfuzz",
                resources: [.copy("rapidfuzz"),
                            .copy("rapidfuzz-3.14.5.dist-info")]),

        // Levenshtein 0.27.3 — Cython wrapper over rapidfuzz exposing the
        // classic python-Levenshtein API (distance, ratio, editops,
        // matching_blocks, StringMatcher). 1 native module (579 KB iOS
        // arm64 .so). Requires rapidfuzz at runtime — SPM dep above ties
        // them together so users only have to tick Levenshtein in Xcode.
        .target(name: "Levenshtein",
                dependencies: ["Rapidfuzz"],
                path: "Sources/Levenshtein",
                resources: [.copy("Levenshtein"),
                            .copy("Levenshtein-0.27.3.dist-info")]),

        // ── Performance accelerators (added 2026-05-26) ──
        // Five drop-in or near-drop-in replacements that speed up common
        // operations across the entire Python stack. Total ~3.2 MB native.

        // orjson 3.11.9 — Rust-backed JSON encode/decode. 5-10× faster
        // than stdlib json. Used by FastAPI internals (when present) and
        // by anything that hits json.dumps in a hot path. Single 757 KB
        // .so. Compiled via cargo + pyo3 (config file overrides cross
        // compile target — no Python interpreter probe needed).
        .target(name: "Orjson",
                path: "Sources/Orjson",
                resources: [.copy("orjson.cpython-314-iphoneos.so"),
                            .copy("orjson-3.11.9.dist-info")]),

        // uvloop 0.22.1 — libuv-backed asyncio event loop. 2-4× faster
        // than the stdlib selectors_events policy. Drop-in:
        //   import uvloop; uvloop.install()
        // 1.8 MB total: vendored libuv built as a static archive
        // (autotools cross-compile via ./configure --host=aarch64-apple-
        // darwin), then uvloop/loop.c (Cython output) linked against it.
        .target(name: "Uvloop",
                path: "Sources/Uvloop",
                resources: [.copy("uvloop"),
                            .copy("uvloop-0.22.1.dist-info")]),

        // ciso8601 2.3.3 — fast ISO 8601 datetime parser. 20-50× faster
        // than datetime.fromisoformat for CSV / Parquet / JSON timestamp
        // ingestion. 67 KB single .so. Three C files compiled in one
        // clang call.
        .target(name: "Ciso8601",
                path: "Sources/Ciso8601",
                resources: [.copy("ciso8601"),
                            .copy("ciso8601.cpython-314-iphoneos.so"),
                            .copy("ciso8601-2.3.3.dist-info")]),

        // numexpr 2.14.1 — fast NumPy array-expression evaluator. 2-5×
        // faster pandas.eval / pandas.query and large element-wise
        // arithmetic. 175 KB native (C++17 interpreter linking numpy
        // C API).
        .target(name: "Numexpr",
                path: "Sources/Numexpr",
                resources: [.copy("numexpr"),
                            .copy("numexpr-2.14.1.dist-info")]),

        // Bottleneck 1.6.0 — fast NaN-aware numpy ops + rolling stats.
        // pandas uses it under the hood for nanmean / nanstd /
        // .rolling().mean() etc. 5-25× speedup for those paths.
        // 4 native modules (reduce, move, nonreduce, nonreduce_axis)
        // totaling ~390 KB. Templates expanded by bn_template.py before
        // the clang cross-compile pass.
        .target(name: "Bottleneck",
                path: "Sources/Bottleneck",
                resources: [.copy("bottleneck"),
                            .copy("bottleneck-1.6.0.dist-info")]),
    ]
)
