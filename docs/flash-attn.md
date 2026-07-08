# flash-attn — SDPA-backed shim (iOS)

Real [flash-attn](https://github.com/Dao-AILab/flash-attention) is a CUDA/Triton
package and can never run on iOS. This bundle ships a **pure-Python shim** that
implements flash-attn's public API on top of
`torch.nn.functional.scaled_dot_product_attention`, which CodeBench routes to the
GPU via the Metal bridge ([torch.md](torch.md#gpu-acceleration-on-metal)). So code
that hard-imports `flash_attn` — including HuggingFace models and diffusers — runs
unchanged and gets **real GPU attention**, not an `ImportError`.

`__version__` reports `2.5.8` (via `importlib.metadata`) so downstream version
checks pass.

## What's implemented

| Symbol | Notes |
|---|---|
| `flash_attn_func(q, k, v, dropout_p, softmax_scale, causal)` | Layout `(batch, seqlen, nheads, headdim)` |
| `flash_attn_varlen_func(...)` | Variable-length / unpadded — one SDPA call per sequence |
| `flash_attn.bert_padding.index_first_axis` | Row gather |
| `flash_attn.bert_padding.pad_input` / `unpad_input` | The pad/unpad pair transformers uses around FA2 |

Semantics match flash-attn **≥ 2.1**:

- **Bottom-right causal alignment** when `seqlen_q != seqlen_k` — a 1-token decode
  step attends to the whole KV cache (SDPA's `is_causal` is top-left, so the shim
  builds the mask explicitly).
- **GQA / MQA** — key/value heads fewer than query heads are repeated internally.
- Custom `softmax_scale`, `dropout_p`, fp16/bf16.

## Gaps

These are CUDA-kernel features with no iOS meaning — they raise an informative
error rather than silently returning wrong numbers:

| Not supported | Why |
|---|---|
| `window_size=(...)` sliding-window attention | No fused kernel; SDPA has no windowed mode |
| `alibi_slopes=...` | ALiBi bias is a kernel feature |
| `return_attn_probs=True` | SDPA doesn't expose the probability matrix — use `attn_implementation="eager"` if you need weights |

## Verification

Device-verified numerically correct against a naive attention reference:
non-causal, causal (equal-length + decode + bottom-right), GQA, custom scale,
varlen + pad round-trip, fp16. See `Workspace/attn_shims_verify.py`.

## See also

- [torch.md — Attention shims](torch.md#attention-shims)
- [transformers.md](transformers.md) — `attn_implementation="flash_attention_2"` auto-remap
- [xformers](xformers.md) — the sibling shim
