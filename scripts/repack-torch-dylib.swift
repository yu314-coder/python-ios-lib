#!/usr/bin/env swift
// Repackage libtorch_python.dylib as a Compression.framework-LZMA blob.
//
// Why: GitHub rejects raw git blobs > 100 MB; the dylib is 103 MB.
// Git LFS works at the CLI but breaks SwiftPM checkout (SPM uses
// local-path origins, kills the LFS smudge filter — confirmed
// incompatibility, swiftlang/swift-package-manager#5351). Apple's
// Compression framework's LZMA encoder gets the file to ~14 MB,
// well under GitHub's limit, and the same framework decodes it on
// the consumer side at PyTorchLib.bootstrap() time.
//
// Run when libtorch_python.dylib is rebuilt for a new torch version:
//
//   swift scripts/repack-torch-dylib.swift
//
// Reads:  app_packages/site-packages/torch/lib/libtorch_python.dylib
// Writes: Sources/PyTorch/torch_dylib/libtorch_python.dylib.applzma
// Updates: the expectedDylibSize constant in Sources/PyTorch/PyTorch.swift
//          (you'll need to edit by hand if the size changes).

import Compression
import Foundation

let here = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()  // …/python-ios-lib
let src = here.appendingPathComponent(
    "app_packages/site-packages/torch/lib/libtorch_python.dylib")
let dstDir = here.appendingPathComponent("Sources/PyTorch/torch_dylib")
let dst = dstDir.appendingPathComponent("libtorch_python.dylib.applzma")

guard FileManager.default.fileExists(atPath: src.path) else {
    FileHandle.standardError.write(Data(
        "ERROR: source not found at \(src.path)\n".utf8))
    exit(1)
}

let raw = try Data(contentsOf: src)
print("source: \(raw.count) bytes")

let cap = raw.count + 4096
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
defer { buf.deallocate() }

let n = raw.withUnsafeBytes { rb -> Int in
    let s = rb.bindMemory(to: UInt8.self).baseAddress!
    return compression_encode_buffer(buf, cap, s, raw.count, nil, COMPRESSION_LZMA)
}
guard n > 0 else {
    FileHandle.standardError.write(Data("ERROR: encoder returned 0\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
try Data(bytes: buf, count: n).write(to: dst)
let pct = String(format: "%.1f", Double(n) / Double(raw.count) * 100)
print("packed:  \(n) bytes (\(pct)% of source) → \(dst.path)")

// Quick round-trip sanity check.
let comp = try Data(contentsOf: dst)
let outCap = raw.count + 4096
let out = UnsafeMutablePointer<UInt8>.allocate(capacity: outCap)
defer { out.deallocate() }
let m = comp.withUnsafeBytes { rb -> Int in
    let s = rb.bindMemory(to: UInt8.self).baseAddress!
    return compression_decode_buffer(out, outCap, s, comp.count, nil, COMPRESSION_LZMA)
}
print("round-trip: decoded \(m) bytes — match: \(m == raw.count ? "yes" : "NO")")

print("")
print("Now update expectedDylibSize in Sources/PyTorch/PyTorch.swift to \(raw.count)")
print("(currently the file expects 103_335_120 — only change if the source size changed).")
