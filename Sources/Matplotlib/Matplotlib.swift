import Foundation
import Plotly

/// Matplotlib — plotting (uses Plotly as the backend on iOS).
/// Auto-includes: Plotly.
public enum MatplotlibLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force-link Plotly's resource bundle. See Manim.swift for why
    /// this is necessary (SwiftPM dead-strips pure-resource targets
    /// without an explicit symbol reference).
    public static let _bundledDependencies: [Bundle] = [
        PlotlyLib.resourceBundle,
    ]
}
