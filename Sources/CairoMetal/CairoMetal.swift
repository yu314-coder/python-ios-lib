import Foundation

// CairoMetal — pycairo-compatible GPU cairo on Apple Metal.
// Standalone repo: https://github.com/yu314-coder/cairometal
// This SwiftPM target ships the prebuilt iOS arm64 extension
// (cairo_metal.cpython-314-iphoneos.so) + its compiled metallib as
// resources, so consumers can `import cairo_metal`.
public enum CairoMetalLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }
}
