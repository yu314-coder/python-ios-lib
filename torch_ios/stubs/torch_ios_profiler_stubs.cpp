// torch_ios: stubs for profiler helper functions that
// torch/csrc/profiler/combined_traceback.cpp depends on but that live in
// libtorch_cpu source files excluded from BUILD_LITE_INTERPRETER=1.
//
// Specifically:
//   * torch::jit::currentCallstack()  – normally in torch/csrc/jit/runtime/
//     interpreter.cpp; pulling in the full interpreter chain is far too much
//     code for the mobile build.
//   * torch::unwind::unwind()/symbolize()/stats() – normally in
//     torch/csrc/profiler/unwind/unwind.cpp; upstream already provides a
//     TORCH_CHECK(false) fallback for non-Linux-x86_64, but we don't compile
//     the file. Provide equivalent stubs here.
//
// Returning empty vectors (instead of throwing) keeps CUDA memory viz / gc
// traceback hooks working — they just report "no traceback info on iOS".

#include <vector>
#include <torch/csrc/jit/frontend/source_range.h>
#include <torch/csrc/profiler/unwind/unwind.h>

namespace torch {
namespace jit {
std::vector<StackEntry> currentCallstack() {
  // torch_ios: iPad has no JIT interpreter call stack to gather.
  return {};
}
} // namespace jit
} // namespace torch

namespace torch {
namespace unwind {
std::vector<void*> unwind() {
  // torch_ios: no libunwind on iOS; return empty frame list.
  return {};
}

std::vector<Frame> symbolize(const std::vector<void*>& /*frames*/) {
  // torch_ios: can't symbolize without unwind support.
  return {};
}

Stats stats() {
  return Stats{};
}
} // namespace unwind
} // namespace torch
