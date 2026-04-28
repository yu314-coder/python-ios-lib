import Foundation

/// Resource bundle accessor for this package.
/// Use Bundle.module to access bundled Python libraries.
public enum LaTeXEngineLib {
    /// The bundle containing the Python library resources.
    public static var resourceBundle: Bundle { Bundle.module }
    
    /// Path to the bundled Python packages.
    public static var resourcePath: String? {
        resourceBundle.resourcePath
    }
}
