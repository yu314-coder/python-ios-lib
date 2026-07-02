#!/usr/bin/env swift
// Repackage bpy/__init__.so (+ its hard dylib dependency libusd_ms) as
// Compression.framework-LZMA blobs (.applzma), mirroring
// scripts/repack-torch-dylib.swift. GitHub rejects blobs > 100 MB; Apple LZMA
// brings both under the limit and the same framework decodes them on the
// consumer side at BlenderLib.bootstrap() time.
//
// The bpy .so carries an LC_LOAD_DYLIB for USD. In app_packages it points at
// the CodeBench framework layout (@rpath/libusd_ms.framework/libusd_ms); for
// the standalone SwiftPM product both binaries are materialized side-by-side
// in Caches, so the packed VARIANT is retargeted to @loader_path/libusd_ms.dylib
// (via install_name_tool on a temp copy — app_packages itself is untouched).
import Compression
import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default
let bpyDir = here.appendingPathComponent("app_packages/site-packages/bpy")
let srcSO = bpyDir.appendingPathComponent("__init__.so")
let srcUSD = bpyDir.appendingPathComponent("lib/libusd_ms.dylib")
let dstDir = here.appendingPathComponent("Sources/Blender/bpy_dylib")

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(msg)\n".utf8)); exit(1)
}
@discardableResult
func run(_ tool: String, _ args: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    try? p.run(); p.waitUntilExit(); return p.terminationStatus
}
func packLZMA(_ data: Data, to dst: URL, label: String) throws {
    let cap = data.count + 4096
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap); defer { buf.deallocate() }
    let n = data.withUnsafeBytes { rb -> Int in
        compression_encode_buffer(buf, cap, rb.bindMemory(to: UInt8.self).baseAddress!,
                                  data.count, nil, COMPRESSION_LZMA)
    }
    guard n > 0 else { die("\(label): encoder returned 0") }
    try Data(bytes: buf, count: n).write(to: dst)
    // round-trip
    let comp = try Data(contentsOf: dst)
    let out = UnsafeMutablePointer<UInt8>.allocate(capacity: cap); defer { out.deallocate() }
    let m = comp.withUnsafeBytes { rb -> Int in
        compression_decode_buffer(out, cap, rb.bindMemory(to: UInt8.self).baseAddress!,
                                  comp.count, nil, COMPRESSION_LZMA)
    }
    guard m == data.count else { die("\(label): round-trip mismatch (\(m) vs \(data.count))") }
    print("\(label): \(data.count) -> \(n) bytes (\(String(format: "%.1f", Double(n)/1048576)) MB, " +
          "\(String(format: "%.1f", Double(n)/Double(data.count)*100))%)  " +
          "under 100MB: \(n < 100*1048576 ? "YES" : "NO")  round-trip: OK")
}

guard fm.fileExists(atPath: srcSO.path) else { die("source not found at \(srcSO.path)") }
guard fm.fileExists(atPath: srcUSD.path) else { die("libusd_ms not found at \(srcUSD.path)") }
try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

// 1) variant .so: retarget the USD load command for the side-by-side layout
let tmp = fm.temporaryDirectory.appendingPathComponent("bpy_variant_\(getpid()).so")
try? fm.removeItem(at: tmp)
try fm.copyItem(at: srcSO, to: tmp)
let ref = "@rpath/libusd_ms.framework/libusd_ms"
if run("/usr/bin/install_name_tool", ["-change", ref, "@loader_path/libusd_ms.dylib", tmp.path]) != 0 {
    die("install_name_tool failed")
}
_ = run("/usr/bin/codesign", ["-f", "-s", "-", tmp.path])   // re-seal after the edit
let soData = try Data(contentsOf: tmp)
try? fm.removeItem(at: tmp)
try packLZMA(soData, to: dstDir.appendingPathComponent("__init__.so.applzma"), label: "bpy .so")

// 2) libusd_ms
let usdData = try Data(contentsOf: srcUSD)
try packLZMA(usdData, to: dstDir.appendingPathComponent("libusd_ms.dylib.applzma"), label: "libusd_ms")

print("expectedModuleSize for Blender.swift = \(soData.count)")
print("expectedUsdSize    for Blender.swift = \(usdData.count)")
