// swift-tools-version: 5.9
// CairoMetal — a Metal-GPU drop-in for the exact subset of the cairo 2D API
// that manim's iOS Cairo renderer (camera.py) calls, rendering vector paths
// into an IOSurface-backed MTLTexture for zero-copy handoff to VideoToolbox.
//
// NOTE: the *folder* is "cairo(metal)" (parentheses), but a Swift package /
// target identifier may not contain parentheses, so the package and its single
// target are named "CairoMetal".
//
// ---------------------------------------------------------------------------
// Build layout (this list is the single source of truth — it matches the files
// that actually exist on disk and is kept in lock-step with the Makefile).
// ---------------------------------------------------------------------------
// CairoMetal is a clang (C / Objective-C) target:
//   * Public C API .......... include/cairo_metal.h          (publicHeadersPath)
//   * Internal contract ..... src/cm_internal.h
//   * Source  (C) ........... src/cm_matrix.c
//   * Sources (Obj-C) ....... src/cairo_metal.m  src/cm_surface.m  src/cm_device.m
//                             src/cm_path.m  src/cm_fill.m  src/cm_stroke.m
//                             src/cm_paint.m
//   * Metal shader .......... shaders/fill.metal
//
// SwiftPM has NO command-line build rule that compiles a `.metal` source
// (Metal compilation is an Xcode-only build phase). So the shaders are NOT
// `sources`; they ship as *resources* (`.copy`) and are loaded at runtime.
//
// How the Metal library is found at runtime (src/cm_device.m, cm_load_library):
//   1. $CM_METALLIB — absolute path to a prebuilt default.metallib (the
//      Makefile's `make run` sets this for the CLI/demo path).
//   2. When consumed in an Xcode/iOS app: add shaders/fill.metal to the app
//      target so Xcode's Metal build phase produces the app's
//      `default.metallib`; cm_device.m loads it via the main bundle.
//   3. Self-contained fallback: the raw shaders/fill.metal is packaged here as a
//      resource so cm_device.m can compile it at runtime from the package
//      resource bundle. fill.metal alone defines every shader entry point the
//      device module references (cm_vs_stencil / cm_fs_stencil / cm_vs_cover /
//      cm_fs_cover_solid / cm_fs_cover_linear).
//
// A build *product* (default.metallib) is deliberately NOT referenced as a
// resource, so a plain `swift build` never depends on the Makefile having run.

import PackageDescription

let package = Package(
    name: "CairoMetal",
    platforms: [
        .iOS(.v17),
        .macOS(.v11),
    ],
    products: [
        .library(name: "CairoMetal", targets: ["CairoMetal"]),
    ],
    targets: [
        .target(
            name: "CairoMetal",
            path: ".",
            exclude: [
                // Everything under the package root that is NOT a library
                // source, the public-headers dir, or a declared resource must
                // be excluded or SwiftPM errors on "unhandled files".
                ".github",
                "README.md",
                "DESIGN.md",
                "STATUS.md",
                "Makefile",
                "build.sh",   // one-shot build/render script, not a lib source
                "examples",   // demo.m is a standalone smoke test, not the lib
                "tests",      // standalone test programs, not the lib
            ],
            sources: [
                // Objective-C (Metal / IOSurface / CoreText / ImageIO) modules.
                // SwiftPM compiles Obj-C with ARC by default; -fobjc-arc is also
                // passed below to mirror the Makefile and remove ambiguity.
                "src/cairo_metal.m",   // public context/path/paint/fill/stroke glue
                "src/cm_surface.m",    // format-general IOSurface target + surface API
                "src/cm_surface_png.m",// PNG encode/decode via ImageIO
                "src/cm_recording.m",  // RecordingSurface op-log record + replay
                "src/cm_device.m",     // MTLDevice/queue, pipelines, ring, frames
                "src/cm_clip.m",       // GPU A8 clip-mask + CPU clip geometry
                "src/cm_group.m",      // push/pop_group offscreen targets
                "src/cm_compose.m",    // operator + paint + mask encode
                "src/cm_text.m",       // CoreText glyph-outline source + metrics
                "src/cm_path.m",       // record / adaptive-flatten / tessellate fans
                "src/cm_fill.m",       // stencil-then-cover encode
                "src/cm_stroke.m",     // stroke expansion -> fillable polygon
                "src/cm_paint.m",      // solid + linear gradient, 1D LUT bake
                // Pure-C modules.
                "src/cm_matrix.c",         // full affine algebra
                "src/cm_surface_format.c", // format metadata table
                "src/cm_surface_similar.c",// create_similar / for_rectangle glue
                "src/cm_state.c",          // gstate stack + non-GPU state + dash
                "src/cm_pattern.c",        // universal pattern base + queries
                "src/cm_mesh.c",           // MeshPattern Coons record + tessellation
                "src/cm_raster.c",         // RasterSourcePattern callbacks
                "src/cm_query.c",          // fill/stroke extents + in_fill/in_stroke
                "src/cm_region.c",         // cairo_region_t band algebra
                "src/cm_font.c",           // FontOptions/FontFace/ScaledFont + state
                "src/cm_ft.c",             // optional FreeType outline (guarded)
            ],
            // Ship the Metal shader SOURCES so the runtime can compile/locate the
            // library from the package resource bundle. (No build product here.)
            // NOTE: SwiftPM requires `resources` to precede `publicHeadersPath`.
            resources: [
                .copy("shaders/fill.metal"),
            ],
            // Public C API header lives in include/; internal header in src/.
            publicHeadersPath: "include",
            cSettings: [
                // So the .m / .c files can #include "cm_internal.h" and the
                // public header by relative path.
                .headerSearchPath("src"),
                .headerSearchPath("include"),
                .unsafeFlags(["-fobjc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Foundation"),
                // cm_text.m needs CoreText; cm_text.m + cm_surface_png.m need
                // CoreGraphics; cm_surface_png.m needs ImageIO +
                // UniformTypeIdentifiers (moved from the demo into the library).
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
    ]
)
