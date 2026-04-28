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
        .library(name: "Pygments", targets: ["Pygments"]),
        .library(name: "Mpmath", targets: ["Mpmath"]),
        .library(name: "Pydub", targets: ["Pydub"]),
        .library(name: "JsonSchema", targets: ["JsonSchema"]),
        .library(name: "CairoGraphics", targets: ["CairoGraphics"]),
        .library(name: "FFmpegPyAV", targets: ["FFmpegPyAV"]),
        .library(name: "Decorator", targets: ["Decorator"]),
        .library(name: "PyWebView", targets: ["PyWebView"]),

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
        .library(name: "Matplotlib", targets: ["Matplotlib", "Plotly"]),

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
                           "Jinja2", "Markupsafe",
                           "Screeninfo", "Watchdog"]),
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
        .target(name: "NumPy", path: "Sources/NumPy", resources: [.copy("numpy")]),

        // SymPy 1.14 — symbolic math (pure Python)
        .target(name: "SymPy", path: "Sources/SymPy", resources: [.copy("sympy")]),

        // Plotly 6.6 — interactive charts (pure Python)
        .target(name: "Plotly", path: "Sources/Plotly", resources: [.copy("plotly")]),

        // NetworkX 3.6 — graph theory (pure Python)
        .target(name: "NetworkX", path: "Sources/NetworkX", resources: [.copy("networkx")]),

        // Pillow 12.2 — image processing (native iOS build)
        .target(name: "Pillow", path: "Sources/Pillow", resources: [.copy("PIL")]),

        // BeautifulSoup4 — HTML/XML parsing (pure Python)
        .target(name: "BeautifulSoup", path: "Sources/BeautifulSoup", resources: [.copy("bs4")]),

        // requests — HTTP client (pure Python)
        .target(name: "Requests", path: "Sources/Requests", resources: [.copy("requests")]),

        // PyYAML — YAML parser (native build)
        .target(name: "PyYAML", path: "Sources/PyYAML", resources: [.copy("yaml")]),

        // rich — rich text, tables, progress bars (pure Python)
        .target(name: "Rich", path: "Sources/Rich", resources: [.copy("rich")]),

        // tqdm — progress bars (pure Python)
        .target(name: "Tqdm", path: "Sources/Tqdm", resources: [.copy("tqdm")]),

        // click — CLI framework (pure Python)
        .target(name: "Click", path: "Sources/Click", resources: [.copy("click")]),

        // cloup — click extension (option groups, constraints, sub-command
        // groups with section headers). Hard-imported by manim/_config at
        // module load — without it `import manim` fails before any code
        // runs. Pure Python, ~212 KB.
        .target(name: "Cloup",
                dependencies: ["Click"],
                path: "Sources/Cloup",
                resources: [.copy("cloup")]),

        // mapbox_earcut — polygon triangulation (164 KB, native .so).
        // Hard-imported by manim/utils/space_ops.py at module load.
        .target(name: "Mapbox_earcut", path: "Sources/Mapbox_earcut",
                resources: [.copy("mapbox_earcut")]),

        // isosurfaces — 3D surface algorithm. Hard-imported by manim's
        // surface mobjects.
        .target(name: "Isosurfaces", path: "Sources/Isosurfaces",
                resources: [.copy("isosurfaces")]),

        // markupsafe — XML/HTML escape utilities. Required by Jinja2
        // (Jinja2 hard-imports `markupsafe` at module load).
        .target(name: "Markupsafe", path: "Sources/Markupsafe",
                resources: [.copy("markupsafe")]),

        // jinja2 — templating engine. Used by manim for its HTML/SVG
        // export templates and by torch's inductor codegen path.
        .target(name: "Jinja2",
                dependencies: ["Markupsafe"],
                path: "Sources/Jinja2",
                resources: [.copy("jinja2")]),

        // screeninfo — multi-monitor query. manim's camera reads this
        // to decide default frame size if not configured.
        .target(name: "Screeninfo", path: "Sources/Screeninfo",
                resources: [.copy("screeninfo")]),

        // watchdog — file-system event observer. Used by manim's
        // --auto-rerun and `manim render` hot-reload modes.
        .target(name: "Watchdog", path: "Sources/Watchdog",
                resources: [.copy("watchdog")]),

        // fsspec — filesystem-spec abstraction. Required by torch's
        // distributed checkpoint loaders + huggingface_hub's downloads.
        .target(name: "Fsspec", path: "Sources/Fsspec",
                resources: [.copy("fsspec")]),

        // Pygments — syntax highlighting (pure Python)
        .target(name: "Pygments", path: "Sources/Pygments", resources: [.copy("pygments")]),

        // mpmath — arbitrary precision math (pure Python)
        .target(name: "Mpmath", path: "Sources/Mpmath", resources: [.copy("mpmath")]),

        // pydub — audio manipulation (pure Python)
        .target(name: "Pydub", path: "Sources/Pydub", resources: [.copy("pydub")]),

        // jsonschema — JSON validation (pure Python)
        .target(name: "JsonSchema", path: "Sources/JsonSchema", resources: [.copy("jsonschema")]),

        // decorator — single-file shim of Michele Simionato's decorator
        // package; provides `decorate` + `decorator` (manim's only deps
        // from it). Pure Python, ~150 LOC.
        .target(name: "Decorator", path: "Sources/Decorator", resources: [.copy("decorator.py")]),

        // pywebview — CodeBench shim of pywebview that routes
        // create_window/load_url/load_html into the host app's preview
        // pane via file-IPC instead of spawning a real native window
        // (which iOS forbids). Pure Python.
        .target(name: "PyWebView", path: "Sources/PyWebView", resources: [.copy("webview")]),

        // Cairo + Pango + HarfBuzz — 2D vector graphics (native iOS)
        .target(name: "CairoGraphics", path: "Sources/CairoGraphics", resources: [.copy("cairo"), .copy("pango"), .copy("harfbuzz")]),

        // FFmpeg 62 + PyAV — video encoding/decoding (native iOS, 7 dylibs)
        .target(name: "FFmpegPyAV", path: "Sources/FFmpegPyAV", resources: [.copy("ffmpeg"), .copy("av")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES NUMPY — auto-included when you select these
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // scikit-learn — ML (40 modules). Needs: NumPy
        .target(name: "Sklearn", dependencies: ["NumPy"], path: "Sources/Sklearn", resources: [.copy("sklearn")]),

        // SciPy — scientific computing. Needs: NumPy.
        // Bundles libfortran_io_stubs.dylib + libsf_error_state.dylib
        // (Fortran runtime for scipy's BLAS/LAPACK/sparse paths). Without
        // these, `import scipy.spatial` / `scipy.sparse` / `scipy.linalg`
        // crash at load with "symbol not found".
        .target(name: "SciPy",
                dependencies: ["NumPy"],
                path: "Sources/SciPy",
                resources: [.copy("scipy"), .copy("scipy_runtime")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES PLOTLY
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // matplotlib — Plotly backend (64 modules). Needs: Plotly
        .target(name: "Matplotlib", dependencies: ["Plotly"], path: "Sources/Matplotlib", resources: [.copy("matplotlib")]),

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
                               "Jinja2", "Screeninfo", "Watchdog"],
                path: "Sources/Manim",
                resources: [
            .copy("manim"), .copy("manimpango"), .copy("offlinai_latex"),
            .copy("svgelements"), .copy("pathops"),
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
            ]
        ),

        // tokenizers 0.19.1 — HuggingFace's Rust tokenizers, cross-compiled
        // for iOS arm64 (first public iOS build). BPE/WordPiece/Unigram
        // trainers + fast tokenizers via PyO3.
        .target(
            name: "Tokenizers",
            path: "Sources/Tokenizers",
            resources: [.copy("tokenizers")]
        ),

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
            ]
        ),
    ]
)
