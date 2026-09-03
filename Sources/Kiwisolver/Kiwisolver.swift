import Foundation

/// kiwisolver — imported by matplotlib at import time.
public enum KiwisolverLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }
}
