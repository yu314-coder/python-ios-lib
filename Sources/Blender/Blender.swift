import Foundation
import Compression

/// Blender (`bpy`) resource bundle accessor — exposes the bundled `bpy/`
/// Python package and handles one-time materialization of the module binary
/// `bpy/__init__.so` from its LZMA-compressed form.
///
/// **Why the binary ships compressed:** GitHub rejects regular blobs over
/// 100 MB. The full Blender `bpy` module (`bpy/__init__.so`) is ~161 MB.
/// Git LFS works in the git CLI but breaks SwiftPM's checkout (SPM uses
/// local-path origins, which kill the LFS smudge filter — confirmed
/// incompatibility, swiftlang/swift-package-manager#5351). Apple's
/// `Compression` LZMA encoder brings it to ~69 MB, well under the limit,
/// and we decompress at first use with the same framework — exactly the
/// pattern `PyTorchLib` uses for `libtorch_python.dylib`.
///
/// **Usage from a host app:**
///
///   import Blender
///   try BlenderLib.bootstrap()        // one call at app startup
///   // …then your Python embedder can `import bpy` (point sys.path / the
///   //   loader at BlenderLib.modulePath — see the docstring there).
///
/// `bootstrap()` is idempotent — the second call is a quick stat() and
/// returns immediately. Decompression takes ~1 s, then never again until
/// the app is reinstalled.
public enum BlenderLib {

    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Path where the bundled `bpy` package lives inside the resource bundle.
    /// `import bpy` loads `<this>/__init__.so`; the bundle is read-only, so
    /// `bootstrap()` materializes the binary into Caches (see `modulePath`)
    /// and the host app points Python's loader at it.
    public static var packagePath: String? {
        resourceBundle.path(forResource: "bpy", ofType: nil)
    }

    /// Writable path where the decompressed `__init__.so` is materialized.
    /// `Bundle.module` is read-only, so we drop the binary here; the host
    /// app makes `import bpy` resolve to this copy (via a sys.path tweak or
    /// a symlink from the bundle's `bpy/` — host-app's choice, same as the
    /// PyTorch `libtorch_python.dylib` arrangement).
    ///
    /// Layout: `…/Caches/python-ios-lib/bpy/__init__.so`.
    public static var modulePath: String {
        let caches = NSSearchPathForDirectoriesInDomains(
            .cachesDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (caches as NSString)
            .appendingPathComponent("python-ios-lib/bpy/__init__.so")
    }

    /// One-time decompression. Returns immediately if the binary is already
    /// materialized AND has the expected size — re-runs if the file is
    /// missing, truncated, or corrupted.
    ///
    /// Throws if the bundled `.applzma` isn't found or decompression fails
    /// (both indicate a corrupted install — re-add the package).
    public static func bootstrap() throws {
        let target = modulePath
        let fm = FileManager.default

        // Fast path: already materialized at the expected size.
        if let attrs = try? fm.attributesOfItem(atPath: target),
           let size = attrs[.size] as? UInt64,
           size == expectedModuleSize {
            return
        }

        guard let blobPath = resourceBundle.path(
            forResource: "__init__.so",
            ofType: "applzma",
            inDirectory: "bpy_dylib")
        else {
            throw BootstrapError.bundledBinaryMissing
        }

        try fm.createDirectory(
            atPath: (target as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        try decompressLZMA(source: blobPath, dest: target)

        let attrs = try fm.attributesOfItem(atPath: target)
        guard let size = attrs[.size] as? UInt64, size == expectedModuleSize else {
            throw BootstrapError.sizeMismatch(
                got: (attrs[.size] as? UInt64) ?? 0,
                expected: expectedModuleSize)
        }
    }

    public enum BootstrapError: Error, CustomStringConvertible {
        case bundledBinaryMissing
        case sizeMismatch(got: UInt64, expected: UInt64)
        case decompressionFailed(reason: String)

        public var description: String {
            switch self {
            case .bundledBinaryMissing:
                return "Blender bootstrap: bpy_dylib/__init__.so.applzma not in bundle. " +
                       "Re-add the python-ios-lib package; resources are likely missing."
            case .sizeMismatch(let g, let e):
                return "Blender bootstrap: bpy binary size mismatch (got \(g) bytes, " +
                       "expected \(e)). Decompression produced wrong-sized output."
            case .decompressionFailed(let reason):
                return "Blender bootstrap: LZMA decompression failed — \(reason)"
            }
        }
    }

    /// Expected size of the decompressed `bpy/__init__.so`. Hard-coded so we
    /// can cheaply detect partial / corrupted files without re-decompressing.
    /// Re-run `scripts/repack-bpy-so.swift` and update this if bpy is rebuilt.
    private static let expectedModuleSize: UInt64 = 168_770_160

    /// LZMA decompression via `Compression.framework` (zero added deps — the
    /// framework ships in iOS 9+). The bundled blob is a raw
    /// `compression_encode_buffer(..., COMPRESSION_LZMA)` stream (NOT xz
    /// container format); produced at build time by `scripts/repack-bpy-so.swift`.
    ///
    /// Memory cost: peak ~230 MB during decode (compressed ~69 MB + output
    /// ~161 MB). Done once at app launch, then never again.
    private static func decompressLZMA(source: String, dest: String) throws {
        guard let compressed = FileManager.default.contents(atPath: source) else {
            throw BootstrapError.decompressionFailed(reason: "couldn't read \(source)")
        }
        let dstCapacity = Int(expectedModuleSize) + 4096
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }

        let written = compressed.withUnsafeBytes { rawBuf -> Int in
            let src = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            return compression_decode_buffer(
                dst, dstCapacity, src, compressed.count, nil, COMPRESSION_LZMA)
        }
        guard written > 0 else {
            throw BootstrapError.decompressionFailed(
                reason: "compression_decode_buffer returned 0 — bundled blob isn't " +
                        "Compression.framework LZMA. Re-encode with " +
                        "scripts/repack-bpy-so.swift on the maintainer side.")
        }
        let outData = Data(bytesNoCopy: dst, count: written, deallocator: .none)
        FileManager.default.createFile(atPath: dest, contents: outData)
    }
}
