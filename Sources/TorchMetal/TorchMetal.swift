import Foundation

// TorchMetal — routes PyTorch's hot inference ops to Apple Metal/MPS.
// Standalone repo: https://github.com/yu314-coder/torchmetal
// This SwiftPM target ships the prebuilt iOS arm64 extension
// (torch_metal.cpython-314-iphoneos.so), the routing layer
// (torchmetal.py), and the compiled metallib as resources, so consumers
// can `import torchmetal; torchmetal.enable()`.
public enum TorchMetalLib {
    public static var resourceBundle: Bundle { Bundle.module }
    public static var resourcePath: String? { resourceBundle.resourcePath }
}
