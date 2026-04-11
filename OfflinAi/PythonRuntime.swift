import Foundation

private typealias PyObjectPointer = OpaquePointer
private typealias PyGILStateState = Int32
private typealias PySsizeT = Int

@_silgen_name("Py_IsInitialized") private func Py_IsInitialized() -> Int32
@_silgen_name("Py_Initialize") private func Py_Initialize()
@_silgen_name("PyGILState_Ensure") private func PyGILState_Ensure() -> PyGILStateState
@_silgen_name("PyGILState_Release") private func PyGILState_Release(_ state: PyGILStateState)
@_silgen_name("PyImport_AddModule") private func PyImport_AddModule(_ name: UnsafePointer<CChar>) -> PyObjectPointer?
@_silgen_name("PyModule_GetDict") private func PyModule_GetDict(_ module: PyObjectPointer?) -> PyObjectPointer?
@_silgen_name("Py_CompileString") private func Py_CompileString(_ code: UnsafePointer<CChar>, _ filename: UnsafePointer<CChar>, _ mode: Int32) -> PyObjectPointer?
@_silgen_name("PyEval_EvalCode") private func PyEval_EvalCode(_ code: PyObjectPointer?, _ globals: PyObjectPointer?, _ locals: PyObjectPointer?) -> PyObjectPointer?
@_silgen_name("Py_DecRef") private func Py_DecRef(_ object: PyObjectPointer?)
@_silgen_name("PyUnicode_FromString") private func PyUnicode_FromString(_ value: UnsafePointer<CChar>) -> PyObjectPointer?
@_silgen_name("PyDict_SetItemString") private func PyDict_SetItemString(_ dict: PyObjectPointer?, _ key: UnsafePointer<CChar>, _ item: PyObjectPointer?) -> Int32
@_silgen_name("PyDict_GetItemString") private func PyDict_GetItemString(_ dict: PyObjectPointer?, _ key: UnsafePointer<CChar>) -> PyObjectPointer?
@_silgen_name("PyUnicode_AsUTF8AndSize") private func PyUnicode_AsUTF8AndSize(_ object: PyObjectPointer?, _ size: UnsafeMutablePointer<PySsizeT>?) -> UnsafePointer<CChar>?
@_silgen_name("PyObject_Str") private func PyObject_Str(_ object: PyObjectPointer?) -> PyObjectPointer?
@_silgen_name("PyErr_Occurred") private func PyErr_Occurred() -> PyObjectPointer?
@_silgen_name("PyErr_Fetch") private func PyErr_Fetch(_ type: UnsafeMutablePointer<PyObjectPointer?>?, _ value: UnsafeMutablePointer<PyObjectPointer?>?, _ traceback: UnsafeMutablePointer<PyObjectPointer?>?)
@_silgen_name("PyErr_NormalizeException") private func PyErr_NormalizeException(_ type: UnsafeMutablePointer<PyObjectPointer?>?, _ value: UnsafeMutablePointer<PyObjectPointer?>?, _ traceback: UnsafeMutablePointer<PyObjectPointer?>?)
@_silgen_name("PyEval_SaveThread") private func PyEval_SaveThread() -> OpaquePointer?

final class PythonRuntime {
    static let shared = PythonRuntime()

    struct ExecutionResult {
        let output: String
        let imagePath: String?
    }

    struct LibraryProbe: Equatable {
        enum State: String {
            case installed
            case shim
            case missing
            case error
        }

        let name: String
        let state: State
        let detail: String?
    }

    private enum RuntimeError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let value):
                return value
            }
        }
    }

    private let queue = DispatchQueue(label: "offlinai.python.runtime")
    private let queueKey = DispatchSpecificKey<Void>()
    private var pathsConfigured = false
    private var toolOutputDirectoryURL: URL?
    private var environmentConfigured = false
    private let fileInputMode: Int32 = 257 // Py_file_input
    private var gilReleasedForThreads = false

    private init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    func execute(code: String) -> ExecutionResult {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return executeSync(code: code)
        }
        return queue.sync {
            executeSync(code: code)
        }
    }

    /// Call after first Py_Initialize to release the GIL for other threads
    private func releaseMainGILIfNeeded() {
        guard !gilReleasedForThreads else { return }
        gilReleasedForThreads = true
        // After Py_Initialize(), the calling thread holds the GIL.
        // We must release it so that PyGILState_Ensure can work from other threads.
        print("[python] Releasing initial GIL for thread safety")
    }

    func probeLibraries(_ libraries: [String]) -> [LibraryProbe] {
        let filtered = libraries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !filtered.isEmpty else { return [] }

        let script = """
import importlib, json
_offlinai_lib_status = []
for _name in \(pythonArrayLiteral(filtered)):
    try:
        _mod = importlib.import_module(_name)
        _file = getattr(_mod, "__file__", "")
        _shim = not bool(_file)
        _offlinai_lib_status.append({
            "name": _name,
            "state": "shim" if _shim else "installed",
            "detail": _file if _file else "built-in compatibility layer"
        })
    except Exception as _exc:
        _offlinai_lib_status.append({
            "name": _name,
            "state": "missing",
            "detail": f"{type(_exc).__name__}: {_exc}"
        })
print("__OFFLINAI_LIB_STATUS__=" + json.dumps(_offlinai_lib_status))
"""

        let result = execute(code: script)
        let output = result.output
        guard let markerRange = output.range(of: "__OFFLINAI_LIB_STATUS__=") else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return filtered.map {
                LibraryProbe(name: $0, state: .error, detail: detail.isEmpty ? "Probe failed." : detail)
            }
        }

        let jsonText = output[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return filtered.map {
                LibraryProbe(name: $0, state: .error, detail: "Probe response parsing failed.")
            }
        }

        return object.map { entry in
            let name = (entry["name"] as? String) ?? "unknown"
            let rawState = (entry["state"] as? String) ?? "error"
            let state = LibraryProbe.State(rawValue: rawState) ?? .error
            let detail = entry["detail"] as? String
            return LibraryProbe(name: name, state: state, detail: detail)
        }
    }

    private func executeSync(code: String) -> ExecutionResult {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ExecutionResult(output: "Python tool error: empty code.", imagePath: nil)
        }

        let execStart = Date()
        func elapsed() -> String { String(format: "%.2fs", Date().timeIntervalSince(execStart)) }

        do {
            if Py_IsInitialized() == 0 {
                print("[python] [\(elapsed())] Py not initialized, configuring environment...")
                try configureEnvironmentBeforeInitialize()
                print("[python] [\(elapsed())] Calling Py_Initialize()...")
                Py_Initialize()
                guard Py_IsInitialized() != 0 else {
                    throw RuntimeError.message("Embedded Python failed to initialize. Check bundled runtime files.")
                }
                print("[python] [\(elapsed())] Py_Initialize() done, releasing GIL for thread safety...")
                // After Py_Initialize the calling thread holds the GIL.
                // Release it so PyGILState_Ensure works correctly from any thread.
                let _ = PyEval_SaveThread()
                print("[python] [\(elapsed())] GIL released (SaveThread)")
            } else {
                print("[python] [\(elapsed())] Python already initialized")
            }

            print("[python] [\(elapsed())] Acquiring GIL...")
            let gil = PyGILState_Ensure()
            defer {
                print("[python] [\(elapsed())] Releasing GIL")
                PyGILState_Release(gil)
            }
            print("[python] [\(elapsed())] GIL acquired")

            let globals = try mainGlobals()
            print("[python] [\(elapsed())] Configuring paths...")
            try configurePythonPathsIfNeeded(globals: globals)
            print("[python] [\(elapsed())] Paths configured")

            let toolDir = try ensureToolOutputDirectory()
            let encoded = Data(trimmed.utf8).base64EncodedString()
            try setGlobalString(encoded, key: "__offlinai_code_b64", globals: globals)
            try setGlobalString(toolDir.path, key: "__offlinai_tool_dir", globals: globals)

            // Pass manim quality settings
            let manimQuality = UserDefaults.standard.integer(forKey: "manim_quality") // 0=low, 1=med, 2=high
            let manimFPS = UserDefaults.standard.integer(forKey: "manim_fps")
            try setGlobalString(String(manimQuality), key: "__offlinai_manim_quality", globals: globals)
            try setGlobalString(String(manimFPS > 0 ? manimFPS : 24), key: "__offlinai_manim_fps", globals: globals)

            print("[python] [\(elapsed())] Running wrapper script (code: \(trimmed.count) chars)...")
            try runStatements(Self.executionWrapperScript, filename: "<offlinai-python-tool>")
            print("[python] [\(elapsed())] Wrapper script completed")

            print("[python] [\(elapsed())] Reading stdout...")
            let stdoutRaw = getGlobalString("__offlinai_stdout", globals: globals)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = sanitizeToolStdout(stdoutRaw)
            let stderr = getGlobalString("__offlinai_stderr", globals: globals)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let imagePath = getGlobalString("__offlinai_plot_path", globals: globals)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[python] [\(elapsed())] stdout=\(stdout.prefix(100)), stderr=\(stderr.prefix(200)), image=\(imagePath.prefix(80))")

            var finalImagePath: String?
            if !imagePath.isEmpty, FileManager.default.fileExists(atPath: imagePath) {
                finalImagePath = imagePath
            }

            let plotOnlyStdout = Self.isPlotOnlyOutput(stdout, imagePath: finalImagePath)
            var sections: [String] = []
            if !stdout.isEmpty && !plotOnlyStdout {
                sections.append(stdout)
            }
            // Filter stderr: only include actual errors, not warnings
            if !stderr.isEmpty {
                let isWarningOnly = stderr.allSatisfy(\.isWhitespace)
                    || (stderr.contains("Warning") && !stderr.contains("Error") && !stderr.contains("Traceback"))
                let isActualError = stderr.contains("Traceback") || stderr.contains("Error") || stderr.contains("Exception")
                if isActualError {
                    sections.append("stderr:\n\(stderr)")
                } else if !isWarningOnly {
                    sections.append("stderr:\n\(stderr)")
                }
                // Print warnings to Xcode console but don't pollute tool output
                if !isActualError {
                    print("[python] warning (hidden from user): \(stderr.prefix(200))")
                }
            }

            if sections.isEmpty && finalImagePath == nil {
                sections.append("Python executed successfully (no output).")
            }
            return ExecutionResult(output: sections.joined(separator: "\n\n"), imagePath: finalImagePath)
        } catch {
            print("[python] [\(elapsed())] ERROR: \(error.localizedDescription)")
            return ExecutionResult(output: "Python tool error: \(error.localizedDescription)", imagePath: nil)
        }
    }

    private static func isPlotOnlyOutput(_ stdout: String, imagePath: String?) -> Bool {
        guard imagePath != nil else { return false }
        let lines = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return true }
        return lines.allSatisfy { line in
            line == "plt.show()"
                || line.hasPrefix("[plot saved]")
                || line.hasPrefix("[manim rendered]")
                || line == "None"
                || line == "Using built-in numpy compatibility layer."
                || line == "Using built-in matplotlib compatibility layer."
        }
    }

    private func sanitizeToolStdout(_ stdout: String) -> String {
        if stdout.isEmpty {
            return stdout
        }
        let lines = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line == "plt.show()" { return false }
                if line.hasPrefix("[plot saved]") { return false }
                if line == "Using built-in numpy compatibility layer." { return false }
                if line == "Using built-in matplotlib compatibility layer." { return false }
                return true
            }
        return lines.joined(separator: "\n")
    }

    private func configurePythonPathsIfNeeded(globals: PyObjectPointer) throws {
        guard !pathsConfigured else { return }

        let bundleURL = Bundle.main.bundleURL
        let pythonLibRoot = bundleURL.appendingPathComponent("python/lib", isDirectory: true)
        guard let versionPath = firstPythonVersionPath(in: pythonLibRoot) else {
            throw RuntimeError.message("Python runtime not found in app bundle.")
        }

        let dynloadPath = URL(fileURLWithPath: versionPath).appendingPathComponent("lib-dynload", isDirectory: true).path
        let sitePackagesPath = bundleURL.appendingPathComponent("app_packages/site-packages", isDirectory: true).path
        let toolDir = try ensureToolOutputDirectory().path

        let script = """
import os, sys
for _p in [\(pythonQuoted(versionPath)), \(pythonQuoted(dynloadPath)), \(pythonQuoted(sitePackagesPath))]:
    if _p and _p not in sys.path:
        sys.path.insert(0, _p)
os.environ.setdefault("MPLCONFIGDIR", \(pythonQuoted(toolDir)))
"""
        _ = globals
        try runStatements(script, filename: "<offlinai-python-paths>")
        pathsConfigured = true
    }

    private func configureEnvironmentBeforeInitialize() throws {
        guard !environmentConfigured else { return }

        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let pythonRoot = bundleURL.appendingPathComponent("python", isDirectory: true).path
        guard fileManager.fileExists(atPath: pythonRoot) else {
            throw RuntimeError.message("Bundled Python root is missing at \(pythonRoot).")
        }
        let pythonLibRoot = bundleURL.appendingPathComponent("python/lib", isDirectory: true)
        guard let versionPath = firstPythonVersionPath(in: pythonLibRoot) else {
            throw RuntimeError.message("Python runtime not found in app bundle.")
        }
        let encodingsDir = URL(fileURLWithPath: versionPath).appendingPathComponent("encodings", isDirectory: true).path
        let osModule = URL(fileURLWithPath: versionPath).appendingPathComponent("os.py").path
        guard fileManager.fileExists(atPath: encodingsDir), fileManager.fileExists(atPath: osModule) else {
            throw RuntimeError.message("Bundled Python stdlib is incomplete. Missing encodings/os.py under \(versionPath).")
        }

        let dynloadPath = URL(fileURLWithPath: versionPath).appendingPathComponent("lib-dynload", isDirectory: true).path
        let sitePackagesPath = bundleURL.appendingPathComponent("app_packages/site-packages", isDirectory: true).path
        let pythonPath = [versionPath, dynloadPath, sitePackagesPath].joined(separator: ":")
        let toolDir = try ensureToolOutputDirectory().path

        setenv("PYTHONHOME", pythonRoot, 1)
        setenv("PYTHONPATH", pythonPath, 1)
        setenv("PYTHONNOUSERSITE", "1", 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        setenv("MPLCONFIGDIR", toolDir, 1)

        environmentConfigured = true
    }

    private func ensureToolOutputDirectory() throws -> URL {
        if let cached = toolOutputDirectoryURL {
            return cached
        }
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RuntimeError.message("Unable to resolve documents directory for Python tool output.")
        }
        let outputURL = documentsURL.appendingPathComponent("ToolOutputs", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        toolOutputDirectoryURL = outputURL
        return outputURL
    }

    private func firstPythonVersionPath(in rootURL: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let candidates = entries
            .filter { $0.lastPathComponent.hasPrefix("python") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return candidates.first?.path
    }

    private func mainGlobals() throws -> PyObjectPointer {
        guard let module = "__main__".withCString({ PyImport_AddModule($0) }) else {
            throw RuntimeError.message("Unable to load Python __main__ module.")
        }
        guard let globals = PyModule_GetDict(module) else {
            throw RuntimeError.message("Unable to access Python global dictionary.")
        }
        return globals
    }

    private func runStatements(_ source: String, filename: String) throws {
        let compiled = source.withCString { sourcePointer in
            filename.withCString { filenamePointer in
                Py_CompileString(sourcePointer, filenamePointer, fileInputMode)
            }
        }
        guard let codeObject = compiled else {
            throw RuntimeError.message(currentPythonError() ?? "Failed to compile Python source.")
        }
        defer { Py_DecRef(codeObject) }

        let globals = try mainGlobals()
        guard let result = PyEval_EvalCode(codeObject, globals, globals) else {
            throw RuntimeError.message(currentPythonError() ?? "Failed to execute Python code.")
        }
        Py_DecRef(result)
    }

    private func setGlobalString(_ value: String, key: String, globals: PyObjectPointer) throws {
        let pyValue = value.withCString { PyUnicode_FromString($0) }
        guard let pyValue else {
            throw RuntimeError.message(currentPythonError() ?? "Unable to convert Swift string for Python.")
        }
        defer { Py_DecRef(pyValue) }

        let status = key.withCString { keyPointer in
            PyDict_SetItemString(globals, keyPointer, pyValue)
        }
        if status != 0 {
            throw RuntimeError.message(currentPythonError() ?? "Unable to store Python runtime variable.")
        }
    }

    private func getGlobalString(_ key: String, globals: PyObjectPointer) -> String {
        let object = key.withCString { keyPointer in
            PyDict_GetItemString(globals, keyPointer)
        }
        guard let object else { return "" }
        return pythonString(from: object) ?? ""
    }

    private func pythonString(from object: PyObjectPointer) -> String? {
        var size: PySsizeT = 0
        if let utf8 = PyUnicode_AsUTF8AndSize(object, &size) {
            return String(cString: utf8)
        }
        guard let rendered = PyObject_Str(object) else {
            return nil
        }
        defer { Py_DecRef(rendered) }
        var renderedSize: PySsizeT = 0
        guard let utf8 = PyUnicode_AsUTF8AndSize(rendered, &renderedSize) else {
            return nil
        }
        return String(cString: utf8)
    }

    private func currentPythonError() -> String? {
        guard PyErr_Occurred() != nil else {
            return nil
        }
        var type: PyObjectPointer?
        var value: PyObjectPointer?
        var traceback: PyObjectPointer?
        PyErr_Fetch(&type, &value, &traceback)
        PyErr_NormalizeException(&type, &value, &traceback)
        defer {
            if let type { Py_DecRef(type) }
            if let value { Py_DecRef(value) }
            if let traceback { Py_DecRef(traceback) }
        }
        if let value, let text = pythonString(from: value), !text.isEmpty {
            return text
        }
        if let type, let text = pythonString(from: type), !text.isEmpty {
            return text
        }
        return "Unknown Python error."
    }

    private func pythonQuoted(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    private func pythonArrayLiteral(_ values: [String]) -> String {
        let encoded = values.map { pythonQuoted($0) }
        return "[\(encoded.joined(separator: ", "))]"
    }


    private static let executionWrapperScript = """
import base64, io, os, sys, time, traceback, uuid, warnings
warnings.filterwarnings("ignore", category=SyntaxWarning)
warnings.filterwarnings("ignore", category=DeprecationWarning)
__offlinai_stdout = ""
__offlinai_stderr = ""
__offlinai_plot_path = ""
_t0 = time.time()
# On iOS there's no real tty — sys.__stderr__ may be broken (Errno 5).
# Use a StringIO log buffer that we can read later if needed.
_log_buf = io.StringIO()
def _log(msg):
    line = f"[py-exec] [{time.time()-_t0:.2f}s] {msg}"
    _log_buf.write(line + "\\n")
    try:
        sys.__stderr__.write(line + "\\n")
        sys.__stderr__.flush()
    except Exception:
        pass
_log("Decoding code...")
_offlinai_code = base64.b64decode(__offlinai_code_b64.encode("utf-8")).decode("utf-8", "replace")
_log(f"Code decoded ({len(_offlinai_code)} chars)")
_out_buf = io.StringIO()
_err_buf = io.StringIO()
_old_stdout, _old_stderr = sys.stdout, sys.stderr
sys.stdout, sys.stderr = _out_buf, _err_buf
try:
    # Import numpy and create SafeArray subclass so `if array:` never crashes
    _log("Importing numpy...")
    try:
        import numpy as np
        np.seterr(divide='ignore', invalid='ignore')

        # ndarray.__bool__ raises on multi-element arrays. We can't patch the
        # immutable builtin type, but we CAN subclass it. SafeArray.__bool__
        # falls back to .any(), and __array_finalize__ ensures ALL numpy ops
        # (ufuncs, slicing, arithmetic) propagate the subclass automatically.
        class SafeArray(np.ndarray):
            def __new__(cls, input_array):
                return np.asarray(input_array).view(cls)
            def __array_finalize__(self, obj):
                pass
            def __bool__(self):
                if self.size == 0: return False
                if self.size == 1: return bool(self.flat[0])
                return bool(self.any())
            def __and__(self, other):
                return np.bitwise_and(np.asarray(self), np.asarray(other)).view(SafeArray)
            def __or__(self, other):
                return np.bitwise_or(np.asarray(self), np.asarray(other)).view(SafeArray)

        # Patch numpy functions ONCE so they return SafeArray.
        # Guard: skip if already patched (script re-runs per execution).
        if not getattr(np, '_offlinai_patched', False):
            np._offlinai_patched = True

            _np_creators = [
                'linspace', 'arange', 'zeros', 'ones', 'array', 'asarray',
                'empty', 'full', 'zeros_like', 'ones_like', 'empty_like',
                'full_like', 'logspace', 'geomspace', 'eye', 'identity',
                'diag', 'fromfunction', 'copy',
            ]
            for _fn_name in _np_creators:
                _orig = getattr(np, _fn_name, None)
                if _orig is None:
                    continue
                def _make_safe(_orig_fn):
                    def _wrapper(*a, **k):
                        r = _orig_fn(*a, **k)
                        if isinstance(r, np.ndarray) and type(r) is np.ndarray:
                            return r.view(SafeArray)
                        return r
                    _wrapper.__name__ = _orig_fn.__name__
                    return _wrapper
                setattr(np, _fn_name, _make_safe(_orig))

            # meshgrid returns a list of arrays
            _orig_meshgrid = np.meshgrid
            def _safe_meshgrid(*a, **k):
                results = _orig_meshgrid(*a, **k)
                return [r.view(SafeArray) if isinstance(r, np.ndarray) else r for r in results]
            np.meshgrid = _safe_meshgrid

            # random functions
            for _rng_name in ['rand', 'randn', 'random', 'uniform', 'normal', 'randint']:
                _orig_rng = getattr(np.random, _rng_name, None)
                if _orig_rng:
                    def _make_safe_rng(_orig_fn):
                        def _wrapper(*a, **k):
                            r = _orig_fn(*a, **k)
                            if isinstance(r, np.ndarray) and type(r) is np.ndarray:
                                return r.view(SafeArray)
                            return r
                        return _wrapper
                    setattr(np.random, _rng_name, _make_safe_rng(_orig_rng))

            _log(f"numpy {np.__version__} OK (SafeArray patched)")
        else:
            _log(f"numpy {np.__version__} OK (already patched)")
    except Exception as _e:
        _log(f"numpy failed: {_e}")

    # Import matplotlib (our plotly-backed package in site-packages/matplotlib/)
    _log("Importing matplotlib...")
    _plt = None
    try:
        import matplotlib
        import matplotlib.pyplot as _plt
        _log(f"matplotlib {matplotlib.__version__} OK")
    except Exception as _e:
        _log(f"matplotlib failed: {_e}")

    # Hook matplotlib.pyplot.show to capture chart output
    if _plt and hasattr(_plt, '_show_hook'):
        def _offlinai_mpl_show(fig_obj=None):
            global __offlinai_plot_path
            os.makedirs(__offlinai_tool_dir, exist_ok=True)
            if fig_obj is not None and hasattr(fig_obj, 'write_html'):
                _path = os.path.join(__offlinai_tool_dir, f"chart_{uuid.uuid4().hex[:8]}.html")
                # Unwrap SafeFigure to get the real plotly Figure
                _real_fig = getattr(fig_obj, '_fig', fig_obj)
                if hasattr(_real_fig, 'update_layout'):
                    _real_fig.update_layout(height=400)
                _real_fig.write_html(_path, include_plotlyjs=True, full_html=True,
                                  default_width="100%", default_height="420px")
                __offlinai_plot_path = _path
                _log(f"chart saved: {_path}")
                print(f"[plot saved] {_path}")
            else:
                _log("show() called but no plotly figure available")
        _plt._show_hook = _offlinai_mpl_show

    # Hook plotly.graph_objects.Figure.show directly
    try:
        import plotly.graph_objects as _pgo
        _log("plotly OK")
        def _offlinai_plotly_show(self, *args, **kwargs):
            global __offlinai_plot_path
            os.makedirs(__offlinai_tool_dir, exist_ok=True)
            _path = os.path.join(__offlinai_tool_dir, f"chart_{uuid.uuid4().hex[:8]}.html")
            # Clean numpy arrays for JSON serialization
            try:
                import numpy as _npx
                for trace in self.data:
                    for attr in ['x', 'y', 'z']:
                        val = getattr(trace, attr, None)
                        if val is not None and hasattr(val, 'tolist'):
                            arr = _npx.asarray(val, dtype=float).ravel()
                            trace[attr] = [None if not _npx.isfinite(v) else float(v) for v in arr]
            except Exception:
                pass
            self.update_layout(height=400)
            self.write_html(_path, include_plotlyjs=True, full_html=True,
                           default_width="100%", default_height="420px")
            __offlinai_plot_path = _path
            _log(f"plotly chart saved: {_path}")
            print(f"[plot saved] {_path}")
        _pgo.Figure.show = _offlinai_plotly_show
    except ImportError:
        _log("plotly not available")

    # Configure manim for iOS (if available)
    try:
        import manim
        _manim_run_id = uuid.uuid4().hex[:8]
        _manim_media = os.path.join(__offlinai_tool_dir, f"manim_{_manim_run_id}")
        os.makedirs(_manim_media, exist_ok=True)
        manim.config.media_dir = _manim_media
        manim.config.renderer = "cairo"
        manim.config.format = "mp4"
        manim.config.write_to_movie = True
        manim.config.save_last_frame = False
        manim.config.preview = False
        manim.config.show_in_file_browser = False
        manim.config.disable_caching = True
        manim.config.verbosity = "WARNING"
        # Read quality settings from __offlinai_manim_quality / __offlinai_manim_fps
        # (set by CodeEditorViewController via UserDefaults → wrapper globals)
        _mq = int(globals().get('__offlinai_manim_quality', '0') or '0')  # Default: low (480p)
        _mfps = int(globals().get('__offlinai_manim_fps', '15') or '15')  # Default: 15fps
        if _mq == 0:
            manim.config.pixel_width = 854
            manim.config.pixel_height = 480
        elif _mq == 1:
            manim.config.pixel_width = 1280
            manim.config.pixel_height = 720
        elif _mq == 2:
            manim.config.pixel_width = 1920
            manim.config.pixel_height = 1080
        manim.config.frame_rate = int(_mfps) if _mfps else 15

        # Monkey-patch to capture frames → animated GIF (since ffmpeg unavailable)
        if not getattr(manim.Scene, '_offlinai_patched', False):
            _orig_render = manim.Scene.render
            # Also patch write_frame to collect frames for GIF
            from manim.scene.scene_file_writer import SceneFileWriter
            _orig_write_frame = SceneFileWriter.write_frame
            _collected_frames = []  # shared frame buffer

            def _capture_write_frame(self_fw, frame_or_renderer, num_frames=1):
                # Intercept write_frame to collect PIL frames for GIF
                try:
                    if isinstance(frame_or_renderer, np.ndarray):
                        frame = frame_or_renderer
                    elif hasattr(frame_or_renderer, 'get_frame'):
                        frame = frame_or_renderer.get_frame()
                    else:
                        frame = None
                    if frame is not None and frame.size > 0:
                        from PIL import Image as _PILImage
                        # frame is RGBA uint8 numpy array
                        if frame.shape[-1] == 4:
                            img = _PILImage.fromarray(frame, 'RGBA').convert('RGB')
                        else:
                            img = _PILImage.fromarray(frame, 'RGB')
                        # Sample every few frames to keep GIF small
                        _collected_frames.append(img)
                except Exception:
                    pass
                # Still call original (for save_last_frame PNG)
                try:
                    _orig_write_frame(self_fw, frame_or_renderer, num_frames)
                except Exception:
                    pass

            SceneFileWriter.write_frame = _capture_write_frame

            def _offlinai_manim_render(self, *args, **kwargs):
                global __offlinai_plot_path
                import manim as _m
                _m.config.renderer = "cairo"
                _m.config.format = "mp4"
                _m.config.write_to_movie = True
                _m.config.save_last_frame = False  # MUST be False — save_last_frame=True sets skip_animations=True which kills video!
                _m.config.preview = False
                _m.config.disable_caching = True
                _collected_frames.clear()
                _orig_render(self, *args, **kwargs)
                try:
                    fw = self.renderer.file_writer
                    _log(f"fw attrs: movie={hasattr(fw,'movie_file_path')}, image={hasattr(fw,'image_file_path')}")
                    if hasattr(fw, 'movie_file_path'):
                        _log(f"movie_file_path={fw.movie_file_path}")
                    # 1. Check for mp4 video (PyAV + ffmpeg)
                    movie_path = str(fw.movie_file_path) if hasattr(fw, 'movie_file_path') and fw.movie_file_path else None
                    if movie_path and os.path.exists(movie_path) and os.path.getsize(movie_path) > 500:
                        __offlinai_plot_path = movie_path
                        _log(f"manim MP4: {movie_path} ({os.path.getsize(movie_path)} bytes)")
                        print(f"[manim rendered] {movie_path}")
                        _collected_frames.clear()
                        return
                    # 2. Fallback: assemble GIF from captured frames
                    if len(_collected_frames) >= 2:
                        from PIL import Image as _PILImage
                        gif_path = os.path.join(_m.config.media_dir, f"{type(self).__name__}.gif")
                        frames = _collected_frames
                        if len(frames) > 80:
                            step = len(frames) // 80
                            frames = frames[::step]
                        w, h = frames[0].size
                        if w > 480:
                            ratio = 480 / w
                            new_size = (480, int(h * ratio))
                            frames = [f.resize(new_size, _PILImage.LANCZOS) for f in frames]
                        fps = _m.config.frame_rate or 15
                        duration = max(int(1000 / fps), 33)
                        frames[0].save(gif_path, save_all=True, append_images=frames[1:], duration=duration, loop=0, optimize=True)
                        if os.path.exists(gif_path) and os.path.getsize(gif_path) > 100:
                            __offlinai_plot_path = gif_path
                            _log(f"manim GIF: {gif_path} ({len(frames)} frames)")
                            print(f"[manim rendered] {gif_path}")
                            _collected_frames.clear()
                            return
                    # 3. Fallback: static PNG
                    img_path = str(fw.image_file_path) if hasattr(fw, 'image_file_path') and fw.image_file_path else None
                    if img_path and os.path.exists(img_path):
                        __offlinai_plot_path = img_path
                        _log(f"manim PNG: {img_path}")
                        print(f"[manim rendered] {img_path}")
                    else:
                        latest = None
                        latest_t = 0
                        for root, dirs, files in os.walk(_m.config.media_dir):
                            for f in files:
                                if f.endswith(('.mp4', '.gif', '.png')):
                                    fpath = os.path.join(root, f)
                                    mt = os.path.getmtime(fpath)
                                    if mt > latest_t:
                                        latest = fpath
                                        latest_t = mt
                        if latest:
                            __offlinai_plot_path = latest
                            _log(f"manim found: {latest}")
                            print(f"[manim rendered] {latest}")
                except Exception as e:
                    _log(f"manim output error: {e}")
                _collected_frames.clear()

            manim.Scene.render = _offlinai_manim_render
            manim.Scene._offlinai_patched = True
        _log("manim configured for iOS (Cairo → GIF animation)")
    except ImportError:
        _log("manim not available")
    except Exception as _me:
        _log(f"manim config error: {_me}")

    # Pre-import useful math modules so user code can use them
    import math
    import cmath
    from math import factorial, gcd, comb, perm, isqrt
    from fractions import Fraction
    try:
        import decimal
        from decimal import Decimal
    except ImportError:
        pass

    # Test helper for templates (avoids nested exec + try/except indentation issues)
    _offlinai_test_pass = 0
    _offlinai_test_fail = 0
    _offlinai_test_errors = []
    def _offlinai_test(name, fn):
        global _offlinai_test_pass, _offlinai_test_fail, _offlinai_test_errors
        try:
            fn()
            _offlinai_test_pass += 1
            print("  ok " + str(name))
        except Exception as _te:
            _offlinai_test_fail += 1
            _offlinai_test_errors.append((str(name), str(_te)[:100]))
            print("  FAIL " + str(name) + ": " + str(_te)[:80])

    # Execute user code
    _log("Executing user code...")
    exec(_offlinai_code, globals(), globals())
    _log("User code finished")

    # Auto-save any unsaved matplotlib figures
    try:
        if _plt and hasattr(_plt, 'get_fignums') and _plt.get_fignums() and not __offlinai_plot_path:
            _plt.show()
    except Exception:
        pass
except Exception:
    traceback.print_exc()
finally:
    sys.stdout, sys.stderr = _old_stdout, _old_stderr
__offlinai_stdout = _out_buf.getvalue()
__offlinai_stderr = _err_buf.getvalue()
"""
}
