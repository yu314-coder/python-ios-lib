import Foundation
import Markupsafe

/// Jinja2 — templating engine. Auto-includes: Markupsafe.
public enum Jinja2Lib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    public static let _bundledDependencies: [Bundle] = [
        MarkupsafeLib.resourceBundle,
    ]
}
