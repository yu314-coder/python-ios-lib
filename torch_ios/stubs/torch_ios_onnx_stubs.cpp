// torch_ios: stubs for torch::jit ONNX-export and related functions.
//
// These live in torch/csrc/jit/serialization/export.cpp,
// torch/csrc/jit/passes/onnx/helper.cpp, and
// torch/csrc/jit/mobile/train/export_data.cpp — all excluded under
// INTERN_DISABLE_ONNX (no onnx/onnx_pb.h available). But pybind11
// `m.def("export_onnx", &export_onnx)` in torch_python takes the
// function address at module-init time, so the symbols must exist.
//
// Calling any of these at runtime throws a clear Python-visible error,
// pointing the user to ExecuTorch for iPad model export.

#include <torch/csrc/jit/serialization/export.h>
#include <torch/csrc/jit/passes/onnx/helper.h>
#include <torch/csrc/jit/mobile/train/export_data.h>
#include <torch/csrc/lazy/ts_backend/ts_backend_impl.h>

#include <c10/util/Exception.h>

namespace ONNX_NAMESPACE {
class ModelProto {};  // minimal forward-decl-matching stub type.
} // namespace ONNX_NAMESPACE

namespace torch {
namespace jit {

[[noreturn]] static void throw_onnx_unsupported(const char* name) {
  TORCH_CHECK(
      false,
      "torch_ios: ",
      name,
      " is not available in the iOS build. ONNX export requires protobuf "
      "headers that aren't compiled in for the iPad target. Use ExecuTorch "
      "on iPad instead (preconvert your model on desktop with torch.export).");
}

std::tuple<
    std::shared_ptr<::ONNX_NAMESPACE::ModelProto>,
    RawDataExportMap,
    SymbolDimMap,
    bool,
    NodeNameMap>
export_onnx(
    const std::shared_ptr<Graph>& /*graph*/,
    const std::map<std::string, at::Tensor>& /*initializers*/,
    int64_t /*onnx_opset_version*/,
    const std::unordered_map<
        std::string,
        std::unordered_map<int64_t, std::string>>& /*dynamic_axes*/,
    bool /*defer_weight_export*/,
    ::torch::onnx::OperatorExportTypes /*operator_export_type*/,
    bool /*strip_doc_string*/,
    bool /*keep_initializers_as_inputs*/,
    const std::map<std::string, int>& /*custom_opsets*/,
    bool /*add_node_names*/,
    bool /*use_external_data_format*/,
    const std::string& /*onnx_file_path*/,
    const NodeAttrNameMap& /*node_attr_to_name*/) {
  throw_onnx_unsupported("export_onnx");
}

std::string serialize_model_proto_to_string(
    const std::shared_ptr<::ONNX_NAMESPACE::ModelProto>& /*model_proto*/) {
  throw_onnx_unsupported("serialize_model_proto_to_string");
}

std::string pretty_print_onnx(
    const std::shared_ptr<Graph>& /*graph*/,
    const std::map<std::string, at::Tensor>& /*initializers*/,
    int64_t /*onnx_opset_version*/,
    bool /*defer_weight_export*/,
    ::torch::onnx::OperatorExportTypes /*operator_export_type*/,
    bool /*google_printer*/,
    bool /*keep_initializers_as_inputs*/,
    const std::map<std::string, int>& /*custom_opsets*/,
    bool /*add_node_names*/) {
  throw_onnx_unsupported("pretty_print_onnx");
}

Node* addNodeToBlock(
    Block* /*block*/,
    c10::Symbol /*kind*/,
    c10::ArrayRef<Value*> /*inputs*/) {
  throw_onnx_unsupported("addNodeToBlock");
}

Value* addInputToBlock(Block* /*block*/) {
  throw_onnx_unsupported("addInputToBlock");
}

void _save_parameters(
    const std::map<std::string, at::Tensor>& /*map*/,
    std::ostream& /*out*/,
    bool /*use_flatbuffer*/) {
  throw_onnx_unsupported("_save_parameters");
}

void _save_parameters(
    const std::map<std::string, at::Tensor>& /*map*/,
    const std::string& /*filename*/,
    bool /*use_flatbuffer*/) {
  throw_onnx_unsupported("_save_parameters");
}

} // namespace jit

namespace lazy {
// torch_ios: torch/csrc/lazy/python/init.cpp's lazy_ts_backend._init()
// pybind binding holds a reference to this function symbol. The real
// definition lives in torch/csrc/lazy/ts_backend/ts_backend_impl.cpp,
// which we don't compile (BUILD_LAZY_TS_BACKEND=OFF — there's no
// TorchScript backend on iPad). Provide a stub so dlopen succeeds;
// calling lazy._init() throws.
void InitTorchScriptBackend() {
  TORCH_CHECK(
      false,
      "torch_ios: torch.lazy TorchScript backend is not built into the "
      "iPad target. The lazy backend pulls in the full TorchScript "
      "compiler and isn't useful on-device — use eager mode instead.");
}
} // namespace lazy
} // namespace torch
