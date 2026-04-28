import Foundation
import NumPy

/// scikit-learn — ML algorithms. Auto-includes: NumPy.
public enum SklearnLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force-link NumPy bundle so consumers who tick only `Sklearn`
    /// still get NumPy at runtime. See Manim.swift for the rationale.
    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
    ]
}
