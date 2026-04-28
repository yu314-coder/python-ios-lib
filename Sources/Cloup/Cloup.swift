import Foundation
import Click

/// Cloup — extension to Click (option groups, constraints, sub-command
/// groups). Auto-includes: Click.
public enum CloupLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force-link Click bundle. See Manim.swift for the rationale.
    public static let _bundledDependencies: [Bundle] = [
        ClickLib.resourceBundle,
    ]
}
