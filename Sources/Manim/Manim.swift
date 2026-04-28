import Foundation
import NumPy
import Matplotlib
import FFmpegPyAV
import CairoGraphics
import LaTeXEngine
import Pillow
import Tqdm
import Rich
import Click
import Cloup

/// Manim — math animations.
/// Auto-includes everything `import manim` + `Scene.render()` need:
/// NumPy, Matplotlib (→Plotly), FFmpegPyAV, CairoGraphics, LaTeXEngine,
/// Pillow, Tqdm, Rich, Click, Cloup.
public enum ManimLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force the linker to keep every dep target's library + resource
    /// bundle. Without an explicit symbol reference, Xcode's linker
    /// dead-strips pure-resource targets (NumPy.swift et al. expose
    /// nothing the consumer's code uses), and their bundles never
    /// reach the final .app.
    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
        MatplotlibLib.resourceBundle,
        FFmpegPyAVLib.resourceBundle,
        CairoGraphicsLib.resourceBundle,
        LaTeXEngineLib.resourceBundle,
        PillowLib.resourceBundle,
        TqdmLib.resourceBundle,
        RichLib.resourceBundle,
        ClickLib.resourceBundle,
        CloupLib.resourceBundle,
    ]
}
