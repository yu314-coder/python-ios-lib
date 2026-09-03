import Foundation

/// contourpy — imported by matplotlib at import time.
public enum ContourpyLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }
}
