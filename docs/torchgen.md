# torchgen — PyTorch operator code generator

**Version:** 2.1.0 (ships with torch 2.1.0)  
**Type:** Pure Python  
**SPM target:** Bundled in the Python framework (top-level package alongside `torch`)  
**Auto-included by:** torch (build-time tooling — packaged into the wheel)  
**Total Python modules:** 62

PyTorch's code-generation toolchain. Used at upstream torch BUILD time to generate C++ operator dispatch tables, autograd bindings, lazy-tensor IR, and ATen kernel registrations from `native_functions.yaml`. NOT used at runtime — the generated `.cpp` files are already baked into the iOS torch binaries. It ships in the bundle because it's part of the torch wheel layout and writing a custom out-of-tree op may eventually need it.

If your IDE flags `torchgen` as unused: it's correct. Safe to ignore unless you're authoring custom ops.

> **Note:** Despite the name suggesting it lives under `torch/`, on disk `torchgen/` is a separate top-level package at `app_packages/site-packages/torchgen/`. Import as `from torchgen import ...`, NOT `from torch.torchgen import ...`.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `torchgen.__init__` | Empty package marker — see module docstring for BC disclaimer |
| `torchgen.gen` | Main entry point — generates ATen operator dispatch tables from YAML |
| `torchgen.gen_aoti_c_shim` | Generates Ahead-of-Time Inductor C shim wrappers |
| `torchgen.gen_backend_stubs` | Generates dispatch stubs for out-of-tree backends |
| `torchgen.gen_functionalization_type` | Generates functionalization pass kernels |
| `torchgen.gen_lazy_tensor` | Generates lazy-tensor IR nodes + lowerings |
| `torchgen.gen_schema_utils` | Helpers for parsing JIT schema strings |
| `torchgen.gen_vmap_plumbing` | Generates `vmap` (vectorizing-map) plumbing |
| `torchgen.model` | Core data classes — `NativeFunction`, `Argument`, `Return`, `DispatchKey`, `BackendIndex` |
| `torchgen.context` | Codegen-context tracking (current op being generated, error reporting) |
| `torchgen.local` | Thread-local codegen state |
| `torchgen.code_template` | Jinja-like `$variable` template engine for emitting C++ |
| `torchgen.native_function_generation` | Auto-derives composite kernels from primitives |
| `torchgen.yaml_utils` | YAML loader with custom constructors for torch types |
| `torchgen.utils` | `concatMap`, `mapMaybe`, `OrderedSet`, file-writing helpers |

### `torchgen.api` — C++ API signatures per dispatch layer

| Submodule | Provides |
|---|---|
| `api.cpp` | C++ user-facing API signature derivation |
| `api.dispatcher` | Dispatcher-layer signatures (`at::_ops::add_call`) |
| `api.native` | Per-backend kernel signatures |
| `api.meta` | Meta-tensor (shape-inference) kernel signatures |
| `api.structured` | Structured-kernel signatures (`out`-overload + meta) |
| `api.functionalization` | Functional-pass kernel signatures |
| `api.lazy` | Lazy-tensor IR-node signatures |
| `api.autograd` | Autograd backward-function signatures |
| `api.python` | Python C-API binding signatures (`THPVariable_add`) |
| `api.translate` | Translates between argument representations across layers |
| `api.ufunc` | Universal-function signatures |
| `api.unboxing` | Boxed-call → unboxed-call translation |
| `api.types` (sub-pkg) | `BaseCType`, `ConstRefCType`, `MutRefCType`, `OptionalCType`, `ListCType`, `ArrayRefCType` — the C++ type system |

### `torchgen.dest` — Emitters (per output target)

| Submodule | Provides |
|---|---|
| `dest.native_functions` | Emits `aten/src/ATen/RegisterDispatchKey*.cpp` |
| `dest.register_dispatch_key` | Per-DispatchKey kernel registration |
| `dest.lazy_ir` | Lazy-tensor IR node `.cpp` emitters |
| `dest.lazy_ts_lowering` | TorchScript-lowering emitters for lazy IR |
| `dest.ufunc` | Universal-function `.cpp` emitters |

### `torchgen.aoti` — Ahead-of-Time Inductor

| Submodule | Provides |
|---|---|
| `aoti.fallback_ops` | List of ops AOTInductor falls back to interpreted PyTorch for |

### `torchgen.selective_build`

| Submodule | Provides |
|---|---|
| `selective_build.selector` | `SelectiveBuilder` — narrows the operator set for mobile builds |
| `selective_build.operator` | Per-op metadata for selective build |

### `torchgen.static_runtime`

| Submodule | Provides |
|---|---|
| `static_runtime.generator` + `static_runtime.gen_static_runtime_ops` | Generates kernels for the static-runtime inference engine |
| `static_runtime.config` | Static-runtime op include/exclude lists |

### `torchgen.operator_versions`

| Submodule | Provides |
|---|---|
| `operator_versions.gen_mobile_upgraders` | Generates op-version upgraders for mobile model load compatibility |
| `operator_versions.gen_mobile_upgraders_constant` | Constant tables consumed by the above |

### `torchgen.packaged/`

| Subdir | Contents |
|---|---|
| `packaged/ATen` | YAML inputs: `native_functions.yaml`, `tags.yaml`, `Declarations.cwrap` |
| `packaged/autograd` | YAML inputs: `derivatives.yaml`, `deprecated.yaml`, `templates/` |

## iOS-specific notes

- **Runtime no-op.** Nothing in `torchgen` is loaded by `import torch` at app launch. It's static tooling.
- **No native deps.** Pure Python; no `.so`, no Cython. Safe on any iOS device.
- **Don't run `gen.py` on device.** It writes `.cpp` and `.h` files — the iOS app sandbox can write inside Documents, but you have no C++ compiler to consume the output.

## Standalone example

You almost never invoke `torchgen` directly. The one realistic use is inspecting the parsed operator model:

```python
from torchgen.model import NativeFunction, Location
from torchgen.yaml_utils import YamlLoader
import yaml, importlib.resources as ir

# Load the bundled native_functions.yaml
nf_path = ir.files("torchgen") / "packaged/ATen/native/native_functions.yaml"
docs = yaml.load(nf_path.read_text(), Loader=YamlLoader)
print(f"{len(docs)} native functions defined in ATen")
print("First:", docs[0]["func"])
```

For everything else, prefer the runtime APIs in `torch.*`.

## See also

- [docs/pytorch.md](pytorch.md) — the runtime `torch` package this generator targets
- [docs/small-utils.md](small-utils.md) — index of other rarely-imported transitive deps
