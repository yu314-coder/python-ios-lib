import Foundation
import UIKit

/// LaTeX rendering engine for iOS using pdftex (lib-tex) + dvisvgm.
/// Initializes ios_system and calls dllpdftexmain as a library function.
@objc class LaTeXEngine: NSObject {

    static let shared = LaTeXEngine()

    private var isInitialized = false
    private let queue = DispatchQueue(label: "com.offlinai.latex", qos: .userInitiated)

    // Paths
    private var texmfPath: String = ""
    private var workDir: String = ""

    override init() {
        super.init()
        setupPaths()
    }

    private func setupPaths() {
        let bundle = Bundle.main
        // texmf is at Frameworks/latex/texmf/ in the app bundle
        if let fwPath = bundle.privateFrameworksPath {
            texmfPath = (fwPath as NSString).appendingPathComponent("latex/texmf")
        }
        // Working directory for tex compilation output
        workDir = NSTemporaryDirectory().appending("latex_work/")
        try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    }

    /// Initialize the ios_system environment (must be called once from main thread)
    func initialize() {
        guard !isInitialized else { return }

        // Set environment variables for TeX
        setenv("TEXMFCNF", (texmfPath as NSString).appendingPathComponent("web2c"), 1)
        setenv("TEXMFDIST", texmfPath, 1)
        setenv("TEXMF", texmfPath, 1)
        setenv("TEXMFHOME", texmfPath, 1)
        setenv("TEXMFVAR", workDir, 1)
        setenv("TEXMFCONFIG", workDir, 1)
        setenv("TEXINPUTS", texmfPath + "//:", 1)
        setenv("TFMFONTS", (texmfPath as NSString).appendingPathComponent("fonts/tfm//"), 1)
        setenv("T1FONTS", (texmfPath as NSString).appendingPathComponent("fonts/type1//"), 1)

        // Initialize ios_system
        initializeEnvironment()

        isInitialized = true
        print("[LaTeX] Engine initialized. texmf=\(texmfPath)")
    }

    /// Compile a LaTeX expression to DVI, then return the path to the output.
    /// This runs pdftex synchronously on a background queue.
    func compileToDVI(texSource: String, outputDir: String? = nil) -> String? {
        if !isInitialized { initialize() }

        let outDir = outputDir ?? workDir
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        // Write .tex file
        let texFile = (outDir as NSString).appendingPathComponent("input.tex")
        do {
            try texSource.write(toFile: texFile, atomically: true, encoding: .utf8)
        } catch {
            print("[LaTeX] Failed to write .tex file: \(error)")
            return nil
        }

        // Redirect stdout/stderr to files for pdftex output
        let stdoutFile = (outDir as NSString).appendingPathComponent("pdftex_stdout.log")
        let stderrFile = (outDir as NSString).appendingPathComponent("pdftex_stderr.log")

        var result: Int32 = -1

        // Call pdftex on background queue (it's CPU-intensive)
        queue.sync {
            // Set working directory
            let prevDir = FileManager.default.currentDirectoryPath
            FileManager.default.changeCurrentDirectoryPath(outDir)

            // Redirect streams
            let oldStdout = stdout
            let oldStderr = stderr
            if let fout = fopen(stdoutFile, "w"),
               let ferr = fopen(stderrFile, "w") {
                // Use ios_system's thread-local streams
                thread_stdin = stdin
                thread_stdout = fout
                thread_stderr = ferr

                // Call pdftex
                var args: [UnsafeMutablePointer<CChar>?] = [
                    strdup("pdftex"),
                    strdup("--interaction=nonstopmode"),
                    strdup("--output-format=dvi"),
                    strdup(texFile),
                    nil
                ]
                result = dllpdftexmain(Int32(args.count - 1), &args)

                // Clean up
                for arg in args { if let a = arg { free(a) } }
                fclose(fout)
                fclose(ferr)
                thread_stdout = oldStdout
                thread_stderr = oldStderr
            }

            FileManager.default.changeCurrentDirectoryPath(prevDir)
        }

        // Check for DVI output
        let dviFile = (outDir as NSString).appendingPathComponent("input.dvi")
        if FileManager.default.fileExists(atPath: dviFile) {
            print("[LaTeX] DVI created: \(dviFile) (pdftex returned \(result))")
            return dviFile
        }

        // Check for PDF output (pdftex might output PDF instead of DVI)
        let pdfFile = (outDir as NSString).appendingPathComponent("input.pdf")
        if FileManager.default.fileExists(atPath: pdfFile) {
            print("[LaTeX] PDF created: \(pdfFile)")
            return pdfFile
        }

        print("[LaTeX] Compilation failed (code \(result)). Check \(stderrFile)")
        return nil
    }

    /// Compile LaTeX expression to SVG via pdftex → DVI → convert to SVG paths.
    /// Returns the path to the SVG file, or nil if compilation failed.
    @objc func compileToSVG(expression: String, outputPath: String) -> Bool {
        // Wrap in minimal LaTeX document
        let texSource = """
        \\documentclass[12pt]{article}
        \\usepackage{amsmath}
        \\usepackage{amssymb}
        \\pagestyle{empty}
        \\begin{document}
        $\\displaystyle \(expression)$
        \\end{document}
        """

        let outDir = (outputPath as NSString).deletingLastPathComponent
        guard let dviPath = compileToDVI(texSource: texSource, outputDir: outDir) else {
            return false
        }

        // Convert DVI/PDF to SVG
        // For now, we create a minimal SVG from the DVI metrics
        // Full dvisvgm conversion would need that library too
        return convertToSVG(inputPath: dviPath, svgPath: outputPath)
    }

    /// Convert DVI to SVG (simplified — extracts glyph paths)
    private func convertToSVG(inputPath: String, svgPath: String) -> Bool {
        // TODO: Use real dvisvgm library for proper conversion
        // For now, if DVI exists, the compilation succeeded
        // We'll create an SVG that indicates success
        let ext = (inputPath as NSString).pathExtension

        if ext == "pdf" {
            // Convert PDF to SVG using Core Graphics
            return convertPDFToSVG(pdfPath: inputPath, svgPath: svgPath)
        }

        // For DVI: would need dvisvgm — fall back to indicating success
        print("[LaTeX] DVI→SVG conversion needs dvisvgm (not yet available)")
        return false
    }

    /// Convert PDF to SVG by rendering to bitmap and tracing
    private func convertPDFToSVG(pdfPath: String, svgPath: String) -> Bool {
        guard let pdfDoc = CGPDFDocument(URL(fileURLWithPath: pdfPath) as CFURL),
              let page = pdfDoc.page(at: 1) else {
            return false
        }

        let mediaBox = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 4.0 // High resolution for crisp text
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)

        // Render PDF page to bitmap
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        // White background
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Render the PDF page
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.drawPDFPage(page)
        context.restoreGState()

        guard let cgImage = context.makeImage() else { return false }

        // Encode as PNG and embed in SVG
        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else { return false }
        let base64 = pngData.base64EncodedString()

        // Create SVG with embedded PNG image
        // Use the original mediaBox dimensions for proper scaling
        let svgWidth = mediaBox.width
        let svgHeight = mediaBox.height
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             width="\(svgWidth)" height="\(svgHeight)" viewBox="0 0 \(svgWidth) \(svgHeight)">
        <g id="unique000">
        <image width="\(svgWidth)" height="\(svgHeight)"
               href="data:image/png;base64,\(base64)"/>
        </g>
        </svg>
        """

        do {
            try svg.write(toFile: svgPath, atomically: true, encoding: .utf8)
            print("[LaTeX] SVG created via PDF→PNG→SVG: \(svgPath)")
            return true
        } catch {
            return false
        }
    }
}
