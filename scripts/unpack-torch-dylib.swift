#!/usr/bin/env swift
// Decompress Sources/PyTorch/torch_dylib/libtorch_python.dylib.applzma
// → app_packages/site-packages/torch/lib/libtorch_python.dylib
//
// The compressed blob is what ships in git (~14 MB, under GitHub's
// 100 MB limit). The CodeBench Xcode build script expects the
// uncompressed dylib to be present at the destination path BEFORE
// the build runs — it copies that .dylib into the app bundle's
// Frameworks/ and runs install_name_tool to rewrite @loader_path
// references to @rpath.
//
// If the dylib is missing (fresh clone, or someone deleted the
// uncompressed copy), `import torch` at runtime crashes with:
//
//   ImportError: dlopen(... torch._C ...): Library not loaded:
//   @rpath/libtorch_python.dylib  →  tried multiple paths,
//   none found.
//
// Run this script once after cloning the repo, before opening
// CodeBench.xcodeproj in Xcode:
//
//   swift scripts/unpack-torch-dylib.swift
//
// Idempotent — re-runs are fast (~stat call) if the dylib already
// exists at the expected size.

import Compression
import Foundation

let here = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()  // …/python-ios-lib
let src = here.appendingPathComponent(
    "Sources/PyTorch/torch_dylib/libtorch_python.dylib.applzma")
let dstDir = here.appendingPathComponent("app_packages/site-packages/torch/lib")
let dst = dstDir.appendingPathComponent("libtorch_python.dylib")

// Hard-coded — must match Sources/PyTorch/PyTorch.swift's
// `expectedDylibSize`. If repack-torch-dylib.swift is run for a
// new torch version, update both.
let expectedSize: UInt64 = 103_335_120

guard FileManager.default.fileExists(atPath: src.path) else {
    FileHandle.standardError.write(Data(
        "ERROR: compressed source not found at \(src.path)\n".utf8))
    FileHandle.standardError.write(Data(
        "       Re-clone the repo or run scripts/repack-torch-dylib.swift\n".utf8))
    exit(1)
}

// Fast path: already materialized at the expected size.
if let attrs = try? FileManager.default.attributesOfItem(atPath: dst.path),
   let size = attrs[.size] as? UInt64, size == expectedSize {
    print("already unpacked at expected size: \(dst.path)")
    exit(0)
}

print("reading \(src.lastPathComponent) …")
let compressed = try Data(contentsOf: src)
print("compressed: \(compressed.count) bytes")

// Output buffer — round up to next megabyte beyond the expected
// uncompressed size for safety.
let outCap = Int(expectedSize) + 4096
let out = UnsafeMutablePointer<UInt8>.allocate(capacity: outCap)
defer { out.deallocate() }

print("decoding via Compression.framework LZMA …")
let n = compressed.withUnsafeBytes { rb -> Int in
    let s = rb.bindMemory(to: UInt8.self).baseAddress!
    return compression_decode_buffer(
        out, outCap, s, compressed.count, nil, COMPRESSION_LZMA)
}
guard n > 0 else {
    let msg = "ERROR: decoder returned 0 — the .applzma blob is "
        + "corrupted or built with a different LZMA variant.\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: dstDir, withIntermediateDirectories: true)
try Data(bytes: out, count: n).write(to: dst)
print("wrote \(n) bytes → \(dst.path)")

// Make it executable so install_name_tool / codesign / dyld all work.
try FileManager.default.setAttributes(
    [.posixPermissions: 0o755], ofItemAtPath: dst.path)

if UInt64(n) == expectedSize {
    print("✓ size matches expectedDylibSize (\(expectedSize) bytes)")
} else {
    let warn = "⚠ size \(n) doesn't match expectedDylibSize "
        + "\(expectedSize) — may need to update the constant in "
        + "Sources/PyTorch/PyTorch.swift"
    print(warn)
}
