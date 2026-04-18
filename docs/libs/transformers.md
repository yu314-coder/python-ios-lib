# Transformers

**HuggingFace transformers** | v4.41.2 | Full Python source, no patches to model code

> Real HuggingFace transformers running against our iOS-native PyTorch.
> Construct and train BERT, GPT-2, any model — all on-device. The same
> `AutoConfig`/`AutoModel`/`pipeline` API you use on a Mac.

---

## What works

| Surface | Status | Notes |
|---------|--------|-------|
| `import transformers` | ✅ | v4.41.2 imports clean in ~50 ms |
| `AutoConfig`, `BertConfig`, `GPT2Config`, … | ✅ | Full config system |
| `BertModel`, `GPT2LMHeadModel`, `BertForMaskedLM`, all PyTorch model classes | ✅ | Real `nn.Module` subclasses, not dummy stubs |
| Forward pass + backward | ✅ | Real autograd on iPad |
| `.generate()` — greedy, beam, sampling | ✅ | Works on GPT-2, BART, T5, encoder-decoders |
| Training with `AdamW` + `labels=input_ids` | ✅ | Loss decreases as expected |
| `PreTrainedTokenizerFast` (wraps Rust tokenizers) | ✅ | Fast path active |
| `BertTokenizer`, `GPT2Tokenizer` (slow / pure-Python) | ✅ | Also works |
| `pipeline("text-generation", ...)` | ✅ | Patched for our numpy-less torch build |
| `pipeline("feature-extraction", ...)` | ✅ | Works out of the box |
| `save_pretrained` / `from_pretrained` (local dir) | ✅ | Bit-identical round-trip on reload |
| `from_pretrained("bert-base-uncased")` (HF Hub download) | 🟡 | Needs network; `huggingface_hub` is installed |

---

## What doesn't work

| Feature | Why | Workaround |
|---------|-----|------------|
| `safetensors` weight loading | Rust backend not built for iOS | Use `torch.save` / `torch.load` with `.pt` files |
| `transformers.Trainer` full loop | `torch.utils.data.DataLoader` multi-worker needs `fork` | Hand-rolled loop with `num_workers=0` |
| GGUF weight import | `llama.cpp` is separate; transformers' GGUF path needs `tokenizers` features we don't expose | Use llama.cpp for GGUF; this stack is for training |
| TF / Flax backends | We ship only PyTorch | Don't pass `framework="tf"` to pipelines |

---

## Dependency shims installed

Transformers has a tangled import graph. These shims unblock the critical path:

| Package | Type | Purpose |
|---------|------|---------|
| `torch` dist-info | Metadata only | Makes `_is_package_available("torch")` return True so real model classes aren't replaced by `dummy_pt_objects` stubs |
| `safetensors` | Stub module with real `storage_ptr` / `storage_size` | transformers' `pytorch_utils.py` imports these two at module load; we provide HF's actual implementations. File I/O raises `NotImplementedError` |
| `regex` | Full forwarding shim to stdlib `re` | Transformers uses only features `re` supports |
| `tokenizers` | **Real** Rust cross-compile | See [tokenizers.md](tokenizers.md) |

---

## Quick start

### Construct a model from config (no download)

```python
from transformers import GPT2Config, GPT2LMHeadModel
import torch

cfg = GPT2Config(vocab_size=5000, n_positions=128, n_embd=128,
                 n_layer=4, n_head=4)
model = GPT2LMHeadModel(cfg)

# Forward + generate
ids = torch.randint(0, 5000, (1, 8))
with torch.no_grad():
    out = model.generate(ids, max_new_tokens=20, do_sample=False,
                         pad_token_id=cfg.pad_token_id or cfg.eos_token_id)
```

### Train a model

```python
import torch
from transformers import GPT2Config, GPT2LMHeadModel

model = GPT2LMHeadModel(GPT2Config(vocab_size=100, n_layer=2, n_head=4, n_embd=32))
opt = torch.optim.AdamW(model.parameters(), lr=5e-3)
seq = torch.arange(10).unsqueeze(0)

for step in range(80):
    opt.zero_grad()
    out = model(seq, labels=seq)
    out.loss.backward()
    opt.step()

# Model now memorizes: generate from [0, 1, 2] → [0,1,2,3,4,5,6,7,8,9]
```

### Use a real tokenizer + pipeline

```python
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import Whitespace
from transformers import PreTrainedTokenizerFast, pipeline

# Train a BPE on your own corpus
tok = Tokenizer(BPE(unk_token="<unk>"))
tok.pre_tokenizer = Whitespace()
tok.train_from_iterator(my_corpus,
    trainer=BpeTrainer(vocab_size=500, special_tokens=["<unk>", "<pad>"]))

ftok = PreTrainedTokenizerFast(tokenizer_object=tok,
    unk_token="<unk>", pad_token="<pad>")

# Wire into a transformers pipeline
gen = pipeline("text-generation", model=my_model, tokenizer=ftok)
print(gen("the quick", max_new_tokens=10))
```

---

## Patches applied

Transformers' source is mostly unchanged. Only one file needed patching:

### `transformers/pipelines/text_generation.py`

`postprocess()` calls `generated_sequence.numpy().tolist()`. Our torch was built
without numpy bindings, so `.numpy()` raises. Patched to prefer `.tolist()`:

```python
generated_sequence = (
    generated_sequence.tolist()
    if hasattr(generated_sequence, "tolist")
    else generated_sequence.numpy().tolist()
)
```

Same pattern would fix `image_classification.py`, `text_classification.py`,
`fill_mask.py`, `zero_shot_classification.py` — apply on demand if you hit
those pipelines.

---

## Test coverage

`Workspace/full_integration_test.py` — **24 asserts** across 8 sections
covering train BPE → fast tokenizer → batch encode → BERT embeddings →
GPT-2 generate → train loop → save/load → pipeline. Whole thing runs in
~7 seconds on an iPad Air M3.

```
section 1: versions                ✓
section 2: BPE trainer             ✓ (157 tokens in 3 ms)
section 3: PreTrainedTokenizerFast ✓ (is_fast=True)
section 4: BERT → embeddings       ✓
section 5: GPT-2 generate          ✓
section 6: GPT-2 train             ✓ (loss 5.07 → 0.48 in 0.3 s)
section 7: save+reload             ✓ (max |Δ logits| = 0.00e+00)
section 8: pipeline()              ✓ text-generation + feature-extraction

  ✅ FULL INTEGRATION (24/24)
```
