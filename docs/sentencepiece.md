# sentencepiece — C++ tokenizer (iOS)

The real `sentencepiece` C++ extension (`_sentencepiece.cpython-314-iphoneos.so`) is
cross-compiled and bundled. This unblocks the SentencePiece-only "slow" tokenizers in
transformers — `transformers.utils.is_sentencepiece_available()` returns `True`.

## What works

- `spm.SentencePieceTrainer.train(...)` — train a BPE/unigram model on-device
  (device-verified: trained vocab=120, encode→decode round-trips)
- `spm.SentencePieceProcessor(model_file=...)` — encode / decode
- Via transformers: `T5Tokenizer`, `LlamaTokenizer`, `BartTokenizer`,
  `AlbertTokenizer`, `XLNetTokenizer`, `DebertaV2Tokenizer`, `GemmaTokenizer`,
  `MBartTokenizer` — the pure-SP tokenizers that previously raised
  "requires the SentencePiece library"

## Gaps

None specific to iOS — the C++ core is fully cross-compiled. (Fast Rust tokenizers
are a separate package, [tokenizers.md](tokenizers.md); most modern models such as
GPT-2 / Qwen / Mistral / Phi use those BPE tokenizers and don't need sentencepiece
at all.)

## See also
- [transformers.md](transformers.md) · [tokenizers.md](tokenizers.md)
