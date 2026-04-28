import Foundation
import NumPy
import SciPy
import Matplotlib
import FFmpegPyAV
import CairoGraphics
import LaTeXEngine
import Pillow
import Tqdm
import Rich
import Click
import Cloup
import NetworkX
import Pygments
import SymPy
import Sklearn
import Decorator
import Mapbox_earcut
import Isosurfaces
import Jinja2
import Screeninfo
import Watchdog
import Typing_extensions
import Psutil
import Moderngl
import Moderngl_window
import Pydub

/// Manim — math animations.
///
/// One tick in Xcode's product picker links every Python module manim
/// imports anywhere in its codebase: hard imports at module load,
/// per-mobject runtime imports, render-pipeline tools, optional
/// surface algorithms, file-watch reload, OpenGL renderer, the works.
public enum ManimLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force the linker to keep every dep target's library + resource
    /// bundle in the final .app. Without an explicit symbol reference,
    /// Xcode's linker dead-strips pure-resource targets and their
    /// bundles never reach the consumer's app.
    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
        SciPyLib.resourceBundle,
        MatplotlibLib.resourceBundle,
        FFmpegPyAVLib.resourceBundle,
        CairoGraphicsLib.resourceBundle,
        LaTeXEngineLib.resourceBundle,
        PillowLib.resourceBundle,
        TqdmLib.resourceBundle,
        RichLib.resourceBundle,
        ClickLib.resourceBundle,
        CloupLib.resourceBundle,
        NetworkXLib.resourceBundle,
        PygmentsLib.resourceBundle,
        SymPyLib.resourceBundle,
        SklearnLib.resourceBundle,
        DecoratorLib.resourceBundle,
        Mapbox_earcutLib.resourceBundle,
        IsosurfacesLib.resourceBundle,
        Jinja2Lib.resourceBundle,
        ScreeninfoLib.resourceBundle,
        WatchdogLib.resourceBundle,
        Typing_extensionsLib.resourceBundle,
        PsutilLib.resourceBundle,
        ModernglLib.resourceBundle,
        Moderngl_windowLib.resourceBundle,
        PydubLib.resourceBundle,
    ]
}
