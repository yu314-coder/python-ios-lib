import Foundation
import Compression

/// PyTorch resource bundle accessor — exposes the bundled torch/ Python
/// package and handles one-time materialization of `libtorch_python.dylib`
/// from its xz-compressed form.
///
/// **Why the dylib ships compressed:** GitHub rejects regular blobs over
/// 100 MB. The dylib is 103 MB. Git LFS works in the git CLI but breaks
/// SwiftPM's checkout (SPM uses local-path origins, which kill the LFS
/// smudge filter — proven incompatibility, open issue swiftlang/swift-
/// package-manager#5351). xz -9 brings it to 14 MB, well under the
/// limit, and we decompress at first use.
///
/// **Usage from a host app:**
///
///   import PyTorch
///   try PyTorchLib.bootstrap()         // one call at app startup
///   // …then your Python embedder can `import torch` normally
///
/// `bootstrap()` is idempotent — the second call is a quick stat() and
/// returns immediately. Decompression takes ~0.5 s on an A14, ~1.5 s
/// on an A12, then never again until the app is reinstalled.
public enum PyTorchLib {

    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Path where `import torch` expects the C extension to live. We
    /// drop the decompressed dylib here so torch's normal dlopen path
    /// (`torch._C` → `torch/lib/libtorch_python.dylib`) works without
    /// any patching of the bundled Python files.
    ///
    /// Inside the resource bundle: `torch/lib/libtorch_python.dylib`.
    /// Bundle.module is read-only, so we materialize into Caches/ and
    /// the bundled Python uses our writable copy via a sys.path tweak
    /// the host app makes (or via a symlink from the bundle path —
    /// host-app's choice).
    public static var dylibPath: String {
        let caches = NSSearchPathForDirectoriesInDomains(
            .cachesDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (caches as NSString)
            .appendingPathComponent("python-ios-lib/torch/lib/libtorch_python.dylib")
    }

    /// One-time decompression. Returns immediately if the dylib is
    /// already materialized AND has the expected size — re-runs if
    /// the file is missing, truncated, or corrupted.
    ///
    /// Throws if the bundled .xz isn't found or decompression fails
    /// (both indicate a corrupted install — re-add the package).
    public static func bootstrap() throws {
        let target = dylibPath
        let fm = FileManager.default

        // Fast path: already materialized at the expected size.
        if let attrs = try? fm.attributesOfItem(atPath: target),
           let size = attrs[.size] as? UInt64,
           size == expectedDylibSize {
            return
        }

        guard let blobPath = resourceBundle.path(
            forResource: "libtorch_python.dylib",
            ofType: "applzma",
            inDirectory: "torch_dylib")
        else {
            throw BootstrapError.bundledDylibMissing
        }

        try fm.createDirectory(
            atPath: (target as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        try decompressLZMA(source: blobPath, dest: target)

        // Sanity-check the materialized file matches the expected size
        // — if not, surface a clear error rather than letting torch
        // fail with an opaque "Symbol not found" downstream.
        let attrs = try fm.attributesOfItem(atPath: target)
        guard let size = attrs[.size] as? UInt64, size == expectedDylibSize else {
            throw BootstrapError.sizeMismatch(
                got: (attrs[.size] as? UInt64) ?? 0,
                expected: expectedDylibSize)
        }
    }

    public enum BootstrapError: Error, CustomStringConvertible {
        case bundledDylibMissing
        case sizeMismatch(got: UInt64, expected: UInt64)
        case decompressionFailed(reason: String)

        public var description: String {
            switch self {
            case .bundledDylibMissing:
                return "PyTorch bootstrap: libtorch_python.dylib.xz not in bundle. " +
                       "Re-add the python-ios-lib package; resources are likely missing."
            case .sizeMismatch(let g, let e):
                return "PyTorch bootstrap: dylib size mismatch (got \(g) bytes, " +
                       "expected \(e)). Decompression produced wrong-sized output."
            case .decompressionFailed(let reason):
                return "PyTorch bootstrap: xz decompression failed — \(reason)"
            }
        }
    }

    /// Expected size of the decompressed dylib. Hard-coded so we can
    /// cheaply detect partial / corrupted files without re-decompressing.
    private static let expectedDylibSize: UInt64 = 103_335_120

    /// LZMA decompression via `Compression.framework` (zero added deps —
    /// the framework ships in iOS 9+).
    ///
    /// **Format:** the bundled blob (`libtorch_python.dylib.applzma`)
    /// is a raw LZMA stream produced by Apple's
    /// `compression_encode_buffer(..., COMPRESSION_LZMA)`. It is NOT
    /// xz-container format — Compression.framework's LZMA is its own
    /// variant and standard `xz` output is incompatible. The
    /// repackaging happens at build time on the maintainer's machine
    /// (see scripts/repack-torch-dylib.swift); consumers just decode
    /// here.
    ///
    /// Memory cost: peak ~120 MB during decode (compressed input
    /// ~14 MB + decompressed output ~99 MB). Done once at app launch,
    /// then never again.
    private static func decompressLZMA(source: String, dest: String) throws {
        guard let compressed = FileManager.default.contents(atPath: source) else {
            throw BootstrapError.decompressionFailed(reason: "couldn't read \(source)")
        }
        let dstCapacity = Int(expectedDylibSize) + 4096
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
                        "scripts/repack-torch-dylib.swift on the maintainer side.")
        }
        let outData = Data(bytesNoCopy: dst, count: written, deallocator: .none)
        FileManager.default.createFile(atPath: dest, contents: outData)
    }
}
