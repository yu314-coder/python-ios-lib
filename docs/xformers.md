# xformers — SDPA-backed shim (iOS)

Real [xformers](https://github.com/facebookresearch/xformers) is a CUDA/Triton
package. This bundle ships a **pure-Python shim** for the one API that third-party
code actually hard-imports — `xformers.ops.memory_efficient_attention` — mapping it
onto `torch.nn.functional.scaled_dot_product_attention`, which CodeBench
GPU-accelerates via the Metal bridge ([torch.md](torch.md#gpu-acceleration-on-metal)).
So diffusers and custom scripts that call it run unchanged and get real GPU
attention.

`__version__` reports `0.0.26` (via `importlib.metadata`).

## What's implemented

| Symbol | Notes |
|---|---|
| `xformers.ops.memory_efficient_attention(q, k, v, attn_bias, p, scale)` | Layout `(batch, seqlen, nheads, headdim)` (BMHK) and 3-D `(batch, seqlen, headdim)` (BMK) |
| `xformers.ops.LowerTriangularMask` | Causal marker → `is_causal=True` |
| `xformers.ops.AttentionBias` / `AttentionOpBase` | Placeholders so `attn_bias=` / `op=` kwargs don't crash |

Supports GQA/MQA (kv-head repeat), an additive float `attn_bias` tensor, and
`LowerTriangularMask` for causal. `dropout_p` and custom `scale` pass through.

## Gaps

| Not supported | Why / workaround |
|---|---|
| Block-diagonal / arbitrary `AttentionBias` subclasses (`BlockDiagonalMask`, etc.) | Raise `NotImplementedError` — pass `None`, a float tensor, or `LowerTriangularMask` |
| `xformers.ops.fmha.*` low-level ops, memory-efficient MLP, sparse attention | Not shimmed — use `F.scaled_dot_product_attention` directly |
| Triton fused kernels | No JIT on iOS |

## Verification

Device-verified: `memory_efficient_attention` causal + non-causal + 3-D BMK match a
naive reference. See `Workspace/attn_shims_verify.py`.

## See also

- [torch.md — Attention shims](torch.md#attention-shims)
- [flash-attn](flash-attn.md) — the sibling shim
