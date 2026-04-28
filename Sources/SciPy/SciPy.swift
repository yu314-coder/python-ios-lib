import Foundation
import NumPy

/// SciPy — scientific computing. Auto-includes: NumPy.
public enum SciPyLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force the linker to keep NumPy's resource bundle in the final
    /// .app. See Manim.swift for the full rationale — TL;DR is that
    /// SwiftPM's pure-resource targets get dead-stripped unless an
    /// explicit symbol reference pins them.
    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
    ]
}
