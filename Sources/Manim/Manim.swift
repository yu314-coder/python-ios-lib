import Foundation
/// Manim — math animations. Auto-includes: NumPy, Matplotlib, FFmpegPyAV, CairoGraphics.
public enum ManimLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }
}
