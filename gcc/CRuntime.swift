import Foundation

/// Swift wrapper for the OfflinAi C Interpreter (gcc/).
/// Executes C code interpreted on-device — no JIT, no compilation, App Store safe.
final class CRuntime {
    static let shared = CRuntime()

    struct ExecutionResult {
        let output: String
        let error: String?
        let success: Bool
    }

    private let queue = DispatchQueue(label: "ai.offlinai.c-runtime", qos: .userInitiated)

    private init() {}

    /// Execute C source code synchronously on the caller's thread.
    func execute(_ source: String) -> ExecutionResult {
        guard let interp = occ_create() else {
            return ExecutionResult(output: "", error: "Failed to create C interpreter", success: false)
        }
        defer { occ_destroy(interp) }

        let result = occ_execute(interp, source)
        let output = String(cString: occ_get_output(interp))
        let error = String(cString: occ_get_error(interp))

        if result != 0 {
            return ExecutionResult(
                output: output,
                error: error.isEmpty ? "C execution failed" : error,
                success: false
            )
        }

        return ExecutionResult(output: output, error: nil, success: true)
    }

    /// Execute C source code on a background thread, returning via completion handler.
    func executeAsync(_ source: String, completion: @escaping (ExecutionResult) -> Void) {
        queue.async {
            let result = self.execute(source)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
