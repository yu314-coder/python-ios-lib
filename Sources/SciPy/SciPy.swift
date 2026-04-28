import Foundation
import NumPy

/// SciPy — scientific computing.
/// Auto-includes: NumPy. Bundles libfortran_io_stubs.dylib +
/// libsf_error_state.dylib (scipy's BLAS/LAPACK/sparse Fortran
/// runtime — without these, scipy.spatial / scipy.sparse / scipy.linalg
/// crash with "symbol not found" at import).
public enum SciPyLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    public static let _bundledDependencies: [Bundle] = [
        NumPyLib.resourceBundle,
    ]
}
