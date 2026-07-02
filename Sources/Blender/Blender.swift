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

    /// One-time decompression of BOTH binaries — the bpy module and its hard
    /// dylib dependency `libusd_ms` (USD), which the packed `.so` references as
    /// `@loader_path/libusd_ms.dylib`, i.e. side-by-side with `modulePath`.
    /// Returns immediately if both are already materialized at the expected
    /// sizes — re-runs if either is missing, truncated, or corrupted. Also
    /// points `PXR_PLUGINPATH_NAME` at the bundled USD plugin metadata so the
    /// USD plugin registry resolves at `import bpy` time.
    ///
    /// Throws if a bundled `.applzma` isn't found or decompression fails
    /// (both indicate a corrupted install — re-add the package).
    public static func bootstrap() throws {
        let fm = FileManager.default
        let dir = (modulePath as NSString).deletingLastPathComponent
        let targets: [(blob: String, dest: String, expected: UInt64)] = [
            ("__init__.so", modulePath, expectedModuleSize),
            ("libusd_ms.dylib", (dir as NSString).appendingPathComponent("libusd_ms.dylib"),
             expectedUsdSize),
        ]

        for t in targets {
            // Fast path: already materialized at the expected size.
            if let attrs = try? fm.attributesOfItem(atPath: t.dest),
               let size = attrs[.size] as? UInt64,
               size == t.expected {
                continue
            }

            guard let blobPath = resourceBundle.path(
                forResource: t.blob,
                ofType: "applzma",
                inDirectory: "bpy_dylib")
            else {
                throw BootstrapError.bundledBinaryMissing
            }

            try fm.createDirectory(
                atPath: (t.dest as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)

            try decompressLZMA(source: blobPath, dest: t.dest, expected: t.expected)

            let attrs = try fm.attributesOfItem(atPath: t.dest)
            guard let size = attrs[.size] as? UInt64, size == t.expected else {
                throw BootstrapError.sizeMismatch(
                    got: (attrs[.size] as? UInt64) ?? 0,
                    expected: t.expected)
            }
        }

        // USD plugin discovery: without this, `import bpy` still works but
        // USD import/export fails with a plugin-registry error.
        if let pkg = packagePath {
            let res = (pkg as NSString).appendingPathComponent("usd_resources")
            if fm.fileExists(atPath: res),
               getenv("PXR_PLUGINPATH_NAME") == nil {
                let paths = [(res as NSString).appendingPathComponent("lib_usd"),
                             (res as NSString).appendingPathComponent("plugin_usd")]
                setenv("PXR_PLUGINPATH_NAME", paths.joined(separator: ":"), 0)
            }
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

    /// Expected sizes of the decompressed binaries. Hard-coded so we can
    /// cheaply detect partial / corrupted files without re-decompressing.
    /// Re-run `scripts/repack-bpy-so.swift` and update these if bpy is rebuilt.
    private static let expectedModuleSize: UInt64 = 232_093_520
    private static let expectedUsdSize: UInt64 = 68_866_848

    /// LZMA decompression via `Compression.framework` (zero added deps — the
    /// framework ships in iOS 9+). The bundled blob is a raw
    /// `compression_encode_buffer(..., COMPRESSION_LZMA)` stream (NOT xz
    /// container format); produced at build time by `scripts/repack-bpy-so.swift`.
    ///
    /// Memory cost: peak ~230 MB during decode (compressed ~69 MB + output
    /// ~161 MB). Done once at app launch, then never again.
    private static func decompressLZMA(source: String, dest: String, expected: UInt64) throws {
        guard let compressed = FileManager.default.contents(atPath: source) else {
            throw BootstrapError.decompressionFailed(reason: "couldn't read \(source)")
        }
        let dstCapacity = Int(expected) + 4096
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
