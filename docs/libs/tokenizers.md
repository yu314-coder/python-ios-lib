# Tokenizers

**Native iOS build** | v0.19.1 | Real Rust cross-compile (first on iOS arm64)

> HuggingFace Rust tokenizers compiled for iOS. BPE/WordPiece/Unigram
> trainers, PyO3 bindings, full speed. Not a stub — it's the real thing.

The tokenizers package is normally a Rust+C mess that maturin-builds via wheels
that only exist for macOS/Linux/Windows. We cross-compiled it from source for
`aarch64-apple-ios` linked against BeeWare's Python.xcframework. As far as we
can tell, this is the **first public build of HuggingFace `tokenizers` for iOS**.

---

## What works

| Surface | Status | Notes |
|---------|--------|-------|
| `import tokenizers` | ✅ | 5.3 MB signed `.framework` |
| `Tokenizer` class + `encode`/`decode` | ✅ | All models |
| `tokenizers.models` — `BPE`, `WordLevel`, `WordPiece`, `Unigram` | ✅ | Real Rust backends |
| `tokenizers.trainers` — `BpeTrainer`, `WordPieceTrainer`, etc. | ✅ | Rayon parallelism on device |
| `tokenizers.pre_tokenizers` — `Whitespace`, `ByteLevel`, `BertPreTokenizer`, … | ✅ | All 12 variants |
| `tokenizers.normalizers` — `NFC`, `NFD`, `Lowercase`, `Strip`, … | ✅ | All 14 variants |
| `tokenizers.decoders` — `ByteLevel`, `BPEDecoder`, `WordPiece`, … | ✅ | |
| `tokenizers.processors` — `TemplateProcessing`, `BertProcessing`, … | ✅ | |
| `Tokenizer.train_from_iterator` | ✅ | Trained 157 BPE tokens in 3 ms |
| `Tokenizer.save` / `from_file` | ✅ | Standard `tokenizer.json` format |
| `PreTrainedTokenizerFast(tokenizer_object=…)` | ✅ | Wraps cleanly into transformers |
| `BertTokenizerFast`, `GPT2TokenizerFast`, etc. | ✅ | transformers' built-ins work |

---

## What doesn't work

Only two numpy-adjacent corners:

| Feature | Why | Impact |
|---------|-----|--------|
| `np.array(strings, dtype='U')` as input | We patched `PyUnicode_FromKindAndData` (not in abi3) out of `tokenizer.rs` and replaced it with manual UCS-4 LE decode. Works but possibly ~2× slower on that exact codepath | None for transformers use; numpy Unicode arrays are rare |
| Pre-built wheels from PyPI | N/A — we build from source | You cross-compile once, then it's cached |

---

## Build setup

Source: `github.com/huggingface/tokenizers` at tag `v0.19.1` (matches what
transformers 4.41.2 wants).

### Prerequisites

```bash
# Rust toolchain with iOS target
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-ios

# Xcode command-line tools (for clang + iPhoneOS SDK)
xcode-select --install
```

### Build

```bash
cd torch_ios/../tokenizers_ios
./build_tokenizers_ios.sh
```

The script sets the PyO3 + C cross-compile env vars and runs
`cargo build --release --target aarch64-apple-ios`.

Output: `tokenizers/bindings/python/target/aarch64-apple-ios/release/libtokenizers.dylib`
(5.0 MB stripped).

---

## Cross-compile environment

The tricky bits are all in environment variables. Anyone attempting this on
another Python-on-iOS distribution will need the equivalents:

```bash
# Where _sysconfigdata*.py lives (BeeWare puts it under platform-config/)
export PYO3_CROSS=1
export PYO3_CROSS_LIB_DIR="$PY_XCF/platform-config/arm64-iphoneos"
export PYO3_CROSS_PYTHON_VERSION="3.14"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export PYTHONPATH="$PY_XCF/platform-config/arm64-iphoneos:$PYTHONPATH"

# PyO3 0.21 maxes at Py 3.12 — force abi3 for forward compat with 3.14
export PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1

# C cross-compile for `onig` (Oniguruma regex) C deps
export CC_aarch64_apple_ios="$(xcrun --sdk iphoneos --find clang)"
export AR_aarch64_apple_ios="$(xcrun --sdk iphoneos --find ar)"
export CFLAGS_aarch64_apple_ios="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=13.0"

# Rust linker — defer Python symbols to dlopen time
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$CC_aarch64_apple_ios"
export CARGO_TARGET_AARCH64_APPLE_IOS_RUSTFLAGS="
  -C link-arg=-isysroot -C link-arg=$(xcrun --sdk iphoneos --show-sdk-path)
  -C link-arg=-F$PY_XCF -C link-arg=-framework -C link-arg=Python
  -C link-arg=-undefined -C link-arg=dynamic_lookup"
```

---

## Source patch

One file needed a patch for abi3 compat. `bindings/python/src/tokenizer.rs`
uses `PyUnicode_FromKindAndData` and `PyUnicode_4BYTE_KIND` which are not
exposed through the stable ABI. Replaced with manual UCS-4 LE decode:

```rust
// Was:
let unicode = pyo3::ffi::PyUnicode_FromKindAndData(
    pyo3::ffi::PyUnicode_4BYTE_KIND as _, bytes.as_ptr() as *const _,
    elsize as isize / alignment as isize,
);

// Now (abi3-safe):
let mut s = String::with_capacity(chars_per_elem);
for j in 0..chars_per_elem {
    let cp = u32::from_le_bytes([bytes[j*4], bytes[j*4+1],
                                  bytes[j*4+2], bytes[j*4+3]]);
    if cp == 0 { break; }
    if let Some(c) = char::from_u32(cp) { s.push(c); }
}
```

This codepath is only hit when encoding `numpy.array(strings, dtype='U')`.

---

## Installation layout

```
app_packages/site-packages/
├── tokenizers/
│   ├── __init__.py                          ← upstream py_src wrappers
│   ├── __init__.pyi
│   ├── tokenizers.cpython-314-iphoneos.so   ← 5.3 MB compiled Rust
│   ├── tokenizers.abi3.so                   ← same binary, abi3 name
│   ├── decoders/  models/  normalizers/     ← Python wrapper modules
│   ├── pre_tokenizers/  processors/  trainers/
│   └── implementations/
└── tokenizers-0.19.1.dist-info/
    ├── METADATA         ← so importlib.metadata.version() works
    ├── WHEEL            ← Tag: cp314-abi3-ios_13_0_arm64_iphoneos
    └── RECORD
```

At Xcode build time BeeWare's `utils.sh` wraps the `.so` into
`Frameworks/site-packages.tokenizers.tokenizers.framework/` and replaces the
`.so` with a `.fwork` stub pointing at the framework.

---

## Quick start

### Train a BPE on your own text

```python
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import Whitespace

tok = Tokenizer(BPE(unk_token="<unk>"))
tok.pre_tokenizer = Whitespace()

trainer = BpeTrainer(
    vocab_size=5000,
    min_frequency=2,
    special_tokens=["<unk>", "<pad>", "<bos>", "<eos>"],
)
tok.train_from_iterator(["your text here", "more text", ...], trainer=trainer)

enc = tok.encode("your text here")
print(enc.ids)        # [42, 17, 103]
print(enc.tokens)     # ['your', 'text', 'here']
print(tok.decode(enc.ids))  # 'your text here'

tok.save("my_tokenizer.json")
```

### Load a pre-trained tokenizer

```python
from tokenizers import Tokenizer
tok = Tokenizer.from_file("my_tokenizer.json")

# Or from HuggingFace Hub (if you have network)
tok = Tokenizer.from_pretrained("bert-base-uncased")
```

### Use with transformers

```python
from transformers import PreTrainedTokenizerFast
ftok = PreTrainedTokenizerFast(
    tokenizer_object=tok,
    unk_token="<unk>", pad_token="<pad>",
)
# ftok behaves like any HF tokenizer — use with any transformers model.
```

---

## Performance

On iPad Air M3 (arm64, Accelerate-enabled torch alongside):

| Operation | Time |
|-----------|------|
| Train BPE on 32-sentence corpus → 157 tokens | **3 ms** |
| `Tokenizer.encode("the quick brown fox")` | < 0.1 ms |
| Batch encode 3 strings with padding → torch.Tensor | < 1 ms |

Tokenization is the same speed as on a Mac — Rust + Rayon threads work as
expected.
