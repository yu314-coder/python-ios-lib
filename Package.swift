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
        // ── Standalone (no dependencies) ──
        .library(name: "CInterpreter", targets: ["CInterpreter"]),
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
        .library(name: "Pygments", targets: ["Pygments"]),
        .library(name: "Mpmath", targets: ["Mpmath"]),
        .library(name: "Pydub", targets: ["Pydub"]),
        .library(name: "JsonSchema", targets: ["JsonSchema"]),
        .library(name: "CairoGraphics", targets: ["CairoGraphics"]),
        .library(name: "FFmpegPyAV", targets: ["FFmpegPyAV"]),

        // ── Requires NumPy ──
        .library(name: "Sklearn", targets: ["Sklearn"]),
        .library(name: "SciPy", targets: ["SciPy"]),

        // ── Requires Plotly ──
        .library(name: "Matplotlib", targets: ["Matplotlib"]),

        // ── Requires multiple deps ──
        .library(name: "Manim", targets: ["Manim"]),
        .library(name: "LaTeXEngine", targets: ["LaTeXEngine"]),

        // ── Machine Learning: PyTorch + HuggingFace stack ──
        .library(name: "PyTorch", targets: ["PyTorch"]),
        .library(name: "Tokenizers", targets: ["Tokenizers"]),
        .library(name: "Transformers", targets: ["Transformers"]),
    ],
    targets: [
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  STANDALONE — No dependencies
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // C/C++/Fortran interpreters — compiles from source
        .target(name: "CInterpreter", path: "gcc", sources: ["offlinai_cc.c"], publicHeadersPath: "."),

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

        // Pygments — syntax highlighting (pure Python)
        .target(name: "Pygments", path: "Sources/Pygments", resources: [.copy("pygments")]),

        // mpmath — arbitrary precision math (pure Python)
        .target(name: "Mpmath", path: "Sources/Mpmath", resources: [.copy("mpmath")]),

        // pydub — audio manipulation (pure Python)
        .target(name: "Pydub", path: "Sources/Pydub", resources: [.copy("pydub")]),

        // jsonschema — JSON validation (pure Python)
        .target(name: "JsonSchema", path: "Sources/JsonSchema", resources: [.copy("jsonschema")]),

        // Cairo + Pango + HarfBuzz — 2D vector graphics (native iOS)
        .target(name: "CairoGraphics", path: "Sources/CairoGraphics", resources: [.copy("cairo"), .copy("pango"), .copy("harfbuzz")]),

        // FFmpeg 62 + PyAV — video encoding/decoding (native iOS, 7 dylibs)
        .target(name: "FFmpegPyAV", path: "Sources/FFmpegPyAV", resources: [.copy("ffmpeg"), .copy("av")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES NUMPY — auto-included when you select these
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // scikit-learn — ML (40 modules). Needs: NumPy
        .target(name: "Sklearn", dependencies: ["NumPy"], path: "Sources/Sklearn", resources: [.copy("sklearn")]),

        // SciPy — scientific computing. Needs: NumPy
        .target(name: "SciPy", dependencies: ["NumPy"], path: "Sources/SciPy", resources: [.copy("scipy")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES PLOTLY
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // matplotlib — Plotly backend (64 modules). Needs: Plotly
        .target(name: "Matplotlib", dependencies: ["Plotly"], path: "Sources/Matplotlib", resources: [.copy("matplotlib")]),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        //  REQUIRES MULTIPLE DEPS — all auto-included
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // manim — math animations. Needs: NumPy + Matplotlib + FFmpeg + Cairo
        .target(name: "Manim", dependencies: ["NumPy", "Matplotlib", "FFmpegPyAV", "CairoGraphics"], path: "Sources/Manim", resources: [
            .copy("manim"), .copy("manimpango"), .copy("offlinai_latex"), .copy("svgelements"), .copy("pathops"),
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
        .target(
            name: "PyTorch",
            path: "Sources/PyTorch",
            resources: [.copy("torch"), .copy("regex")]
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
