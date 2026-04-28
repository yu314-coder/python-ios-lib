import Foundation
import PyTorch
import Tokenizers

/// HuggingFace Transformers. Auto-includes: PyTorch, Tokenizers.
public enum TransformersLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }

    /// Force-link PyTorch + Tokenizers. See Manim.swift for the
    /// rationale. Note that consumers still must call
    /// `PyTorchLib.bootstrap()` once to materialize libtorch_python.
    public static let _bundledDependencies: [Bundle] = [
        PyTorchLib.resourceBundle,
        TokenizersLib.resourceBundle,
    ]
}
