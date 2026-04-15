// swift-tools-version: 5.9
// python-ios-lib — Offline Python libraries for iOS/iPadOS
// https://github.com/yu314-coder/python-ios-lib
//
// Add to your Xcode project:
//   File → Add Package Dependencies → paste this URL:
//   https://github.com/yu314-coder/python-ios-lib
//
// Then select which packages you need.

import PackageDescription

let package = Package(
    name: "python-ios-lib",
    platforms: [.iOS(.v17)],
    products: [
        // ── C/C++/Fortran Interpreters (compiles from source) ──
        .library(name: "CInterpreter", targets: ["CInterpreter"]),

        // ── Python Libraries (bundled as resources) ──
        .library(name: "PythonSklearn", targets: ["PythonSklearn"]),
        .library(name: "PythonScipy", targets: ["PythonScipy"]),
        .library(name: "PythonMatplotlib", targets: ["PythonMatplotlib"]),
        .library(name: "PythonManim", targets: ["PythonManim"]),
        .library(name: "PythonRequests", targets: ["PythonRequests"]),

        // ── Native Frameworks (pre-compiled binaries) ──
        .library(name: "FFmpegPyAV", targets: ["FFmpegPyAV"]),
        .library(name: "CairoGraphics", targets: ["CairoGraphics"]),
        .library(name: "LaTeXEngine", targets: ["LaTeXEngine"]),
    ],
    targets: [
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // C INTERPRETERS — Compiles from source in your project
        // Usage: import CInterpreter, then call occ_create() etc.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        .target(
            name: "CInterpreter",
            path: "gcc",
            sources: ["offlinai_cc.c"],
            publicHeadersPath: "."
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PYTHON LIBRARIES — Bundled as resources
        // Copy from Bundle.main to your app's site-packages/
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // scikit-learn: 40 modules, pure NumPy ML
        // Requires: numpy (iOS wheel from BeeWare)
        .target(
            name: "PythonSklearn",
            path: "Sources/PythonSklearn",
            resources: [.copy("sklearn")]
        ),

        // SciPy: optimization, integration, signal, stats
        // Requires: numpy
        .target(
            name: "PythonScipy",
            path: "Sources/PythonScipy",
            resources: [.copy("scipy")]
        ),

        // matplotlib: Plotly-backed shim, 64 modules
        // Requires: plotly (pure Python)
        .target(
            name: "PythonMatplotlib",
            path: "Sources/PythonMatplotlib",
            resources: [.copy("matplotlib")]
        ),

        // manim: math animations + all dependencies
        // Requires: numpy, PythonMatplotlib, FFmpegPyAV, CairoGraphics
        .target(
            name: "PythonManim",
            path: "Sources/PythonManim",
            resources: [
                .copy("manim"),
                .copy("manimpango"),
                .copy("offlinai_latex"),
                .copy("svgelements"),
                .copy("pathops"),
            ]
        ),

        // requests: HTTP client
        .target(
            name: "PythonRequests",
            path: "Sources/PythonRequests",
            resources: [.copy("requests")]
        ),

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // NATIVE FRAMEWORKS — Pre-compiled for iOS arm64
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // FFmpeg + PyAV: video encoding/decoding
        .target(
            name: "FFmpegPyAV",
            path: "Sources/FFmpegPyAV",
            resources: [
                .copy("ffmpeg"),
                .copy("av"),
            ]
        ),

        // Cairo + Pango + HarfBuzz: 2D vector graphics
        .target(
            name: "CairoGraphics",
            path: "Sources/CairoGraphics",
            resources: [
                .copy("cairo"),
                .copy("pango"),
                .copy("harfbuzz"),
            ]
        ),

        // LaTeX engine: pdftex + kpathsea + texmf fonts
        .target(
            name: "LaTeXEngine",
            path: "Sources/LaTeXEngine",
            resources: [.copy("latex")]
        ),
    ]
)
