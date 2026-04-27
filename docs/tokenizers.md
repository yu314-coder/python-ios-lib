# tokenizers

> **Version:** 0.19.1  | **Type:** Native iOS arm64 (Rust via PyO3)  | **Status:** Working — first public iOS build

HuggingFace's fast tokenization library — Rust-implemented BPE,
WordPiece, Unigram, and SentencePiece tokenizers. Used by every
HuggingFace model loaded via `transformers`.

A more category-organised reference is at
[docs/libs/tokenizers.md](libs/tokenizers.md). This page is the
standalone summary.

---

## Quick start

```python
from tokenizers import Tokenizer

# Load a pre-trained tokenizer JSON
tok = Tokenizer.from_file("/path/to/tokenizer.json")

ids = tok.encode("Hello, world!").ids
print(ids)                            # [101, 7592, 1010, 2088, 999, 102]

text = tok.decode(ids)
print(text)                           # 'Hello, world!'

# Batch encoding
batch = tok.encode_batch(["Hi", "How are you?"])
for enc in batch:
    print(enc.tokens, enc.ids)
```

```python
# Train a new BPE tokenizer
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import Whitespace

tok = Tokenizer(BPE(unk_token="[UNK]"))
tok.pre_tokenizer = Whitespace()
trainer = BpeTrainer(
    vocab_size=10_000,
    special_tokens=["[UNK]", "[CLS]", "[SEP]", "[PAD]"],
)

# Train on a list of files OR an iterator
tok.train(["/path/Documents/corpus.txt"], trainer)
tok.save("/path/Documents/my-tokenizer.json")
```

```python
# Use the higher-level transformers AutoTokenizer (which wraps tokenizers)
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained("path/to/model")
ids = tok("Hello", return_tensors="pt").input_ids
```

---

## What works

- **All trainer types** — `BpeTrainer`, `WordPieceTrainer`,
  `UnigramTrainer`, `WordLevelTrainer`
- **All model types** — BPE, WordPiece, Unigram, WordLevel
- **All pre-tokenizers** — Whitespace, ByteLevel, Digits, Punctuation,
  Sequence, Split, …
- **All normalizers** — NFD, NFKC, Lowercase, Strip, StripAccents,
  Replace, Sequence
- **All decoders** — BPE, WordPiece, ByteLevel, Metaspace, Sequence
- **All post-processors** — TemplateProcessing, ByteLevel, BertProcessing
- **Save / load** — `Tokenizer.save(json_path)` and
  `Tokenizer.from_file(json_path)`
- **`encode_batch`** — multi-threaded internally (Rayon under the
  hood)

---

## iOS-specific notes

- **Rust runtime is fully self-contained** — no separate Rust
  installation, no compilation needed at runtime
- **Threading**: tokenization releases the GIL, so calling
  `encode_batch` from a Python thread doesn't block other Python
  code. The Rust side uses Rayon for parallelism (cores - 1 by
  default).
- **Memory**: tokenizers themselves are tiny (~10-50 KB on disk).
  Vocabularies in memory are ~5-50 MB depending on size.

### Cross-compilation provenance

The 5 MB `tokenizers.cpython-314-iphoneos.so` was built via:
- Rust toolchain `aarch64-apple-ios` target
- PyO3 bindings (with the `extension-module` feature)
- Cross-compiled on macOS hosts via the `cibuildwheel` iOS preset
- Unique to this distribution — not available on PyPI for iOS

---

## Pairing with transformers

`transformers.AutoTokenizer.from_pretrained(path)` returns a
`PreTrainedTokenizerFast` object that wraps a `tokenizers.Tokenizer`
instance. You can access the underlying tokenizer via:

```python
from transformers import AutoTokenizer
hf_tok = AutoTokenizer.from_pretrained("path/to/model")
fast = hf_tok.backend_tokenizer  # the underlying tokenizers.Tokenizer
```

For most use cases, just call the HF tokenizer directly — it adds
padding / truncation / attention mask convenience methods that the
raw tokenizers package doesn't.

---

## Limitations

- **No Python-defined custom Pre-tokenizers / Decoders** — anything
  custom must be implemented in Rust and rebuilt. The bundled set
  covers all standard tokenizer recipes.
- **No interactive Rust tracing** — debugging is via Rust stack
  traces returned through Python; compile-time only.
- **No `wandb` integration** for trainer metrics — you'd add that on
  the Python side around `train()`.

---

## See also

- [docs/libs/tokenizers.md](libs/tokenizers.md) — category-organised
- [docs/transformers.md](transformers.md) — uses tokenizers under the hood
- [docs/torch.md](torch.md) — PyTorch backend
- [docs/huggingface-hub.md](huggingface-hub.md) — download tokenizer files
