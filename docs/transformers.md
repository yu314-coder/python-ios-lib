# transformers

> **Version:** 4.41.2  | **Type:** Pure Python (deps: PyTorch + Tokenizers + huggingface_hub + safetensors + filelock)  | **Status:** Working — train + `.generate()` + save/load all on-device

HuggingFace's transformers library: pre-trained model architectures
(BERT, GPT-2, T5, BART, Llama, Qwen, …), training utilities, the
`pipeline()` shortcuts, the `Auto*` classes for one-line model loads.

A more category-organised reference is at
[docs/libs/transformers.md](libs/transformers.md). This page is the
standalone summary.

---

## Quick start

```python
from transformers import AutoTokenizer, AutoModelForCausalLM

tok = AutoTokenizer.from_pretrained("path/to/Qwen2.5-1.5B")
model = AutoModelForCausalLM.from_pretrained("path/to/Qwen2.5-1.5B")

ids = tok("The quick brown fox", return_tensors="pt").input_ids
out = model.generate(ids, max_new_tokens=20, do_sample=True, temperature=0.8)
print(tok.decode(out[0], skip_special_tokens=True))
```

```python
# Encoder model: BERT
from transformers import AutoModel
model = AutoModel.from_pretrained("path/to/distilbert-base-uncased")

ids = tok("Hello world", return_tensors="pt")
embeddings = model(**ids).last_hidden_state
print(embeddings.shape)             # [1, 4, 768]
```

```python
# Fine-tuning loop (no Trainer — manual since multiprocessing dataloaders don't work)
import torch
import torch.nn.functional as F

opt = torch.optim.AdamW(model.parameters(), lr=5e-5)

for epoch in range(3):
    for batch_text, batch_label in your_dataset:
        ids = tok(batch_text, return_tensors="pt", padding=True, truncation=True)
        out = model(**ids, labels=batch_label)
        out.loss.backward()
        opt.step()
        opt.zero_grad()
```

---

## What works

- **All model architectures** importable from `transformers.models.*`
- **`AutoTokenizer.from_pretrained` / `AutoModel.from_pretrained` /
  `AutoModelForCausalLM` / `AutoModelForSeq2SeqLM` / etc.** — all work
- **`generate()`** — greedy, beam-search, sampling, top-k, top-p,
  temperature, repetition-penalty, all stopping criteria
- **`pipeline("text-generation"|"summarization"|"translation"|...)`**
  — works as long as the underlying model is bundled or downloadable
- **Manual training loop** — full forward + backward + optimizer step
- **`save_pretrained()` / `load_pretrained()`** — save fine-tuned
  weights back to disk (uses safetensors when available)
- **Tokenization** — Rust BPE/WordPiece/Unigram via the `tokenizers`
  package (also a python-ios-lib target)

---

## What's limited or doesn't work

- **`Trainer`** — works for the in-process training case (no
  `multiprocessing` workers). Set `dataloader_num_workers=0` and
  pre-load data into memory. For very large datasets this won't
  scale beyond what fits in RAM.
- **`torch.compile`** — silently falls back to eager (no on-device
  JIT compiler). All performance numbers are eager-mode.
- **`accelerate`** library — not bundled. If you need it for
  device placement utilities, it's pure Python; `pip install accelerate`
  works.
- **Vision models** with custom CUDA ops — fallback to CPU is
  usually fine but slow.
- **`device_map="auto"`** — there's only one device (CPU), so this
  is effectively a no-op. Pass `torch_dtype=torch.float16` to
  reduce memory.
- **`bitsandbytes` 4-bit / 8-bit quantization** — not supported on
  iOS (CUDA-only library).

---

## iOS-specific tips

### Loading bundled models

```python
import os, transformers
os.environ["HF_HUB_CACHE"] = os.path.expanduser("~/Documents/.cache/huggingface/hub")
# (huggingface_hub auto-redirects this on iOS — but you can set it explicitly)

# If you ship a model in the app bundle, point at that path:
model_dir = "/path/to/CodeBench.app/bundled-models/Qwen2.5-1.5B"
tok = AutoTokenizer.from_pretrained(model_dir)
model = AutoModelForCausalLM.from_pretrained(model_dir, torch_dtype=torch.float16)
```

### Memory

- **Half-precision (`fp16`) for inference.** Models load 2× smaller and
  inference is ~1.5× faster on Accelerate.
- **Don't keep gradients during inference.** Wrap in `torch.no_grad()`
  or use `model.eval()`.
- **Free unused models.** Python's GC won't reclaim a 1.5 GB model
  promptly; explicitly `del model; gc.collect()` between switching.

### Quick test models that fit in memory

| Model | Size | Use case |
|---|---|---|
| `distilbert-base-uncased` | 250 MB | Embeddings / classification |
| `Qwen2.5-1.5B-Instruct-Q4` | 1.0 GB | Chat / generation (quantized) |
| `Qwen2.5-3B-Instruct-Q4` | 1.9 GB | Better generation, 8 GB devices |
| `whisper-tiny` | 75 MB | Speech recognition |
| `bart-large-cnn` | 1.6 GB | Summarization |

For models > 4 GB: load with `torch_dtype=torch.float16` and pre-quantize.

---

## Test coverage

24/24 integration asserts passing on real iOS devices, covering:
- Tokenization: BERT WordPiece + GPT-2 BPE + Sentence-piece
- Forward pass: BERT, GPT-2, T5, DistilBERT
- Generation: greedy + beam + sampling
- Save / load: weights + tokenizer config + generation config
- Pipeline: text-generation + summarization

See `app_packages/site-packages/test_transformers.py`.

---

## See also

- [docs/libs/transformers.md](libs/transformers.md) — category-organised
- [docs/torch.md](torch.md) — PyTorch backend
- [docs/tokenizers.md](tokenizers.md) — Rust tokenizer details
- [docs/huggingface-hub.md](huggingface-hub.md) — model downloads
- [docs/safetensors.md](safetensors.md) — weight I/O (use NumPy roundtrip on iOS)
