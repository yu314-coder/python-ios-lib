# tokenizers — fast Rust BPE / WordPiece / Unigram

**Version:** 0.19.1
**Type:** Native iOS arm64 (Rust via PyO3) — `tokenizers.cpython-314-iphoneos.so` (~5 MB)
**SPM target:** `Tokenizers`
**Auto-includes:** (none)
**Total Python modules:** 8 packages (top-level + 7 sub) wrapping the Rust extension

HuggingFace's fast tokenization library — Rust-implemented BPE, WordPiece, Unigram, WordLevel tokenizers plus their pre-tokenizers, normalizers, post-processors, and decoders. Used by every HF model loaded via `transformers.AutoTokenizer`. First public iOS arm64 build.

## Modules

### Top-level

| Module | What it does |
|---|---|
| `tokenizers.__init__` | Re-exports the Rust API: `Tokenizer`, `Encoding`, `Token`, `AddedToken`, `NormalizedString`, `PreTokenizedString`, `Regex`, plus the sub-packages `models`, `pre_tokenizers`, `normalizers`, `processors`, `decoders`, `trainers`. Also exports input/offset type enums (`OffsetReferential`, `OffsetType`, `SplitDelimiterBehavior`) |
| `tokenizers.tokenizers` (`.so`) | The native Rust extension — backing for every class above |

### `tokenizers.models` — tokenizer model types

The vocabulary/merge-table layer. Sub-tokens: `BPE`, `WordPiece`, `Unigram`, `WordLevel`. Each `.from_file()` / `.read_file()` to load a pre-trained model.

### `tokenizers.pre_tokenizers` — input splitting

Run BEFORE the model. Available types: `BertPreTokenizer`, `ByteLevel`, `CharDelimiterSplit`, `Digits`, `Metaspace`, `Punctuation`, `Sequence` (chain multiple), `Split` (regex-based), `UnicodeScripts`, `Whitespace`, `WhitespaceSplit`.

### `tokenizers.normalizers` — text normalisation

Run BEFORE pre-tokenization. Available types: `BertNormalizer`, `Lowercase`, `NFC`, `NFD`, `NFKC`, `NFKD`, `Nmt`, `Prepend`, `Precompiled`, `Replace`, `Sequence`, `Strip`, `StripAccents`.

### `tokenizers.processors` — post-processing

Run AFTER the model, adds special tokens / template patterns. Available types: `BertProcessing`, `ByteLevel`, `RobertaProcessing`, `Sequence`, `TemplateProcessing`.

### `tokenizers.decoders` — IDs → text

Inverse of pre-tokenizer + model. Available types: `BPEDecoder`, `ByteFallback`, `ByteLevel`, `CTC`, `Fuse`, `Metaspace`, `Replace`, `Sequence`, `Strip`, `WordPiece`.

### `tokenizers.trainers` — train new tokenizers

Available types: `BpeTrainer`, `WordPieceTrainer`, `UnigramTrainer`, `WordLevelTrainer`. Each takes `vocab_size`, `special_tokens`, `min_frequency`, `show_progress`, plus model-specific knobs.

### `tokenizers.implementations` — ready-made tokenizers

Pre-wired bundles of model + pre-tok + decoder for common recipes:

| Class | What it builds |
|---|---|
| `BertWordPieceTokenizer` | WordPiece + BertPreTokenizer + WordPieceDecoder + BertProcessing |
| `ByteLevelBPETokenizer` | BPE + ByteLevel everywhere (GPT-2 style) |
| `CharBPETokenizer` | BPE at character level |
| `SentencePieceBPETokenizer` | BPE + Metaspace pre-tok (SentencePiece-style) |
| `SentencePieceUnigramTokenizer` | Unigram + Metaspace |
| `base_tokenizer.BaseTokenizer` | Shared base for the above |

### `tokenizers.tools` — visualisation helpers

`tools.visualizer` (HTML widget for inspecting tokenizations) + `visualizer-styles.css`. Output renders in `WKWebView` on iOS.

## iOS-specific notes

- **Rust runtime fully self-contained** — `tokenizers.cpython-314-iphoneos.so` is a single arm64 `.so` cross-compiled via `cibuildwheel` with the `aarch64-apple-ios` Rust target and the PyO3 `extension-module` feature. No Rust installation, no runtime compilation.
- **Threading** — `encode_batch` releases the GIL and uses Rayon under the hood (cores − 1 by default). Calling from a Python thread doesn't block other Python code.
- **Memory** — tokenizer files are tiny (10-50 KB on disk); loaded vocabularies use ~5-50 MB depending on size.
- **No Python-defined custom pre-tokenizers / decoders** — those plug-in points expect a Rust trait. The bundled set covers every standard tokenizer recipe; custom recipes require a rebuild of the Rust crate.
- **No interactive Rust tracing** — debugging is via Rust stack traces returned through PyO3, compile-time only.
- **Cross-compilation provenance** — this `.so` is unique to this distribution; not available on PyPI for iOS.

## iOS cross-compile build

Source: `github.com/huggingface/tokenizers` at tag `v0.19.1` (matches transformers 4.41.2). Built from source for `aarch64-apple-ios` against BeeWare's Python.xcframework — as far as we can tell, the **first public iOS build** of HF tokenizers.

**Prerequisites:** Rust with the iOS target (`rustup target add aarch64-apple-ios`) + Xcode command-line tools. Build via `tokenizers_ios/build_tokenizers_ios.sh`, which sets the cross-compile env and runs `cargo build --release --target aarch64-apple-ios` → `…/release/libtokenizers.dylib` (5.0 MB stripped).

**Cross-compile environment** (the load-bearing part — PyO3 + C deps):

```bash
export PYO3_CROSS=1
export PYO3_CROSS_LIB_DIR="$PY_XCF/platform-config/arm64-iphoneos"
export PYO3_CROSS_PYTHON_VERSION="3.14"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1   # PyO3 0.21 caps at Py 3.12 → force abi3
export CC_aarch64_apple_ios="$(xcrun --sdk iphoneos --find clang)"
export AR_aarch64_apple_ios="$(xcrun --sdk iphoneos --find ar)"
export CFLAGS_aarch64_apple_ios="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=13.0"
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$CC_aarch64_apple_ios"
export CARGO_TARGET_AARCH64_APPLE_IOS_RUSTFLAGS="-C link-arg=-F$PY_XCF -C link-arg=-framework -C link-arg=Python -C link-arg=-undefined -C link-arg=dynamic_lookup"
```

**One source patch** — `bindings/python/src/tokenizer.rs` uses `PyUnicode_FromKindAndData` / `PyUnicode_4BYTE_KIND`, which aren't in the stable ABI; replaced with a manual UCS-4 LE decode loop. Only hit when encoding `numpy.array(strings, dtype='U')` (rare; possibly ~2× slower on that exact path — no impact on normal transformers use).

**Installed layout:** `site-packages/tokenizers/` (`tokenizers.cpython-314-iphoneos.so` ~5 MB + the `tokenizers.abi3.so` alias + the py wrapper subpackages) plus `tokenizers-0.19.1.dist-info/` (WHEEL tag `cp314-abi3-ios_13_0_arm64_iphoneos`). At Xcode build time BeeWare's `utils.sh` wraps the `.so` into a `.framework` + a `.fwork` stub.

**Performance (iPad Air M3):** train BPE on a 32-sentence corpus → 157 tokens in **3 ms**; `encode("the quick brown fox")` < 0.1 ms; batch-encode 3 strings → padded `torch.Tensor` < 1 ms. Same speed as on a Mac (Rust + Rayon threads).

## Standalone example

```python
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import Whitespace
from tokenizers.decoders import BPEDecoder
from tokenizers.processors import TemplateProcessing

# Load a pre-trained tokenizer JSON
tok = Tokenizer.from_file("/path/to/tokenizer.json")
enc = tok.encode("Hello, world!")
print(enc.ids, enc.tokens)

# Batch encoding (releases GIL, Rayon parallelism)
batch = tok.encode_batch(["Hi", "How are you?"])
for e in batch:
    print(e.tokens, e.ids)

# Decode
print(tok.decode([101, 7592, 1010, 2088, 999, 102]))

# Train a brand-new BPE tokenizer
new_tok = Tokenizer(BPE(unk_token="[UNK]"))
new_tok.pre_tokenizer = Whitespace()
new_tok.decoder = BPEDecoder()
new_tok.post_processor = TemplateProcessing(
    single="[CLS] $A [SEP]",
    special_tokens=[("[CLS]", 1), ("[SEP]", 2)],
)
trainer = BpeTrainer(
    vocab_size=10_000,
    special_tokens=["[UNK]", "[CLS]", "[SEP]", "[PAD]"],
)
new_tok.train(["/path/Documents/corpus.txt"], trainer)
new_tok.save("/path/Documents/my-tokenizer.json")
```

## Pairing with transformers

`transformers.AutoTokenizer.from_pretrained(path)` returns a `PreTrainedTokenizerFast` wrapping a `tokenizers.Tokenizer`. Access the underlying tokenizer via `.backend_tokenizer`:

```python
from transformers import AutoTokenizer
hf_tok = AutoTokenizer.from_pretrained("path/to/model")
fast = hf_tok.backend_tokenizer        # the tokenizers.Tokenizer instance

# For most use cases, call the HF tokenizer directly — it adds padding,
# truncation, attention-mask, and tensor-output (return_tensors="pt") on top.
enc = hf_tok("Hello", return_tensors="pt", padding=True, truncation=True)
```

## Limitations

- **No `wandb` integration** for training metrics — wrap `train()` on the Python side
- **`encode_batch` thread count** is fixed at Rayon's default; no per-call override
- **SentencePiece-only formats** (Llama-1, T5, raw mBART) need the `sentencepiece` C++ package, which is **not** cross-compiled for iOS in this build. BPE-based tokenizers (GPT-2, Qwen, Mistral, Phi, RoBERTa, DistilBERT) work via this `tokenizers` package directly

## See also

- [docs/transformers.md](transformers.md) — uses `tokenizers` under the hood
- [docs/torch.md](torch.md) — PyTorch backend
- [docs/huggingface-hub.md](huggingface-hub.md) — download tokenizer files
