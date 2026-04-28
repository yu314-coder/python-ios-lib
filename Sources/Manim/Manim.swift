import Foundation
import NumPy
import Matplotlib
import FFmpegPyAV
import CairoGraphics
import LaTeXEngine

/// Manim — math animations.
/// Auto-includes: NumPy, Matplotlib (→Plotly), FFmpegPyAV, CairoGraphics, LaTeXEngine.
public enum ManimLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force the linker to keep every dep target's library + resource
    /// bundle. Without an explicit symbol reference, Xcode's linker
    /// dead-strips pure-resource targets (NumPy.swift et al. expose
    /// nothing the consumer's code uses), and their bundles never
    /// reach the final .app — so `import numpy` fails at runtime
    /// even though the user ticked Manim.
    ///
    /// This is the SwiftPM workaround for resource-only target
    /// chains. Each entry is the dep's own resourceBundle accessor;
    /// touching it at module-load time pins the symbol.
    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
        MatplotlibLib.resourceBundle,
        FFmpegPyAVLib.resourceBundle,
        CairoGraphicsLib.resourceBundle,
        LaTeXEngineLib.resourceBundle,
    ]
}
