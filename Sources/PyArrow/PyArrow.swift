import Foundation
// pyarrow 15.0.2 — cross-compiled for iOS arm64 (2026-05-23). The
// `pyarrow/` resource directory next to this file contains 8
// `cpython-314-iphoneos.so` extension modules + libarrow_python.dylib
// + ~80 pure-Python modules + Cython .pxd declarations.
//
// Available APIs at runtime:
//   pa.Table / pa.array / pa.Schema     — full
//   pa.compute.*                         — full (aggregate, scalar, vector)
//   pa.csv.read_csv / write_csv          — full
//   pa.json.read_json                    — full
//   pa.ipc.new_stream / open_stream      — full (Arrow IPC, Feather v2)
//   pa.fs.LocalFileSystem                — full
//
// NOT available (not built — see BUILD_INSTRUCTIONS.md to extend):
//   pa.parquet.*    — ImportError
//   pa.dataset.*    — ImportError
//   pa.flight.*     — ImportError
//   pa.gandiva.*    — ImportError
//   pa.cuda.*       — ImportError (iOS has no CUDA)
public enum PyArrowLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// True when the cross-compiled pyarrow tree is present in the
    /// resource bundle. Stays here so legacy callers that were branching
    /// on it during the placeholder era still work.
    public static var isAvailable: Bool {
        guard let path = resourcePath else { return false }
        return FileManager.default.fileExists(atPath: "\(path)/pyarrow/__init__.py")
    }
}
