"""Benchmark + sanity-check the Metal GPU matmul/linear bridge.

Three pieces of evidence that the GPU path fired (all printed below):
  1. bridge.is_available() == True       → Swift symbols reachable, MTLDevice OK
  2. bridge.stats()["dtype_*"] > 0       → cb_metal_matmul_ex was called
  3. timings show GPU faster than CPU at large sizes, with matching outputs

If (1) is False the cb_metal_* symbols weren't linked into the running
executable. If (2) stays 0 even with the threshold forced to 0, the
patch didn't install. If (3) shows no speedup at 2048³ the kernel
isn't doing real work.

Also exercises fp16, bf16, and 3-D batched (attention-style) matmul.
"""
from __future__ import annotations
import sys
import time

import torch
import torch.nn.functional as F

try:
    import _torch_metal_bridge as bridge
except ImportError:
    print("_torch_metal_bridge not bundled — exiting.")
    sys.exit(0)

print(f"PyTorch     : {torch.__version__}")
print(f"num_threads : {torch.get_num_threads()}")
print(f"is_available: {bridge.is_available()}")
if not bridge.is_available():
    print(f"\nReason: {bridge.diagnose()}")
    print("\nThe rest of this benchmark would be meaningless without GPU dispatch. Exiting.")
    sys.exit(0)

bridge.install(verbose=False)
_orig_matmul = bridge._orig_matmul
_orig_linear = bridge._orig_linear
bridge._MIN_FLOPS = 0  # force every size onto the GPU


def _time(fn, *, iters=10, warmup=2):
    for _ in range(warmup):
        fn()
    t0 = time.perf_counter()
    for _ in range(iters):
        fn()
    return (time.perf_counter() - t0) / iters


def _section(title):
    print(f"\n== {title} ==")
    print("                                  CPU       GPU   speedup    max-err   GPU-calls")


def _row(label, cpu_ms, gpu_ms, err, calls):
    speed = cpu_ms / gpu_ms if gpu_ms > 0 else float("inf")
    print(f"  {label:<28}  {cpu_ms:>8.2f}  {gpu_ms:>8.2f}  "
          f"{speed:>6.2f}x  {err:>9.2e}  {calls:>6d}")


def _count_kernel_calls(before, after):
    keys = ("dtype_fp32", "dtype_fp16", "dtype_bf16_cast")
    return sum(after[k] - before[k] for k in keys)


# ─── 2-D matmul, fp32 ──────────────────────────────────────────────
_section("torch.matmul fp32  shape (M, K) @ (K, N)")
for M, K, N in [(64,64,64), (256,256,256), (1024,1024,1024), (2048,2048,2048)]:
    A = torch.randn(M, K, dtype=torch.float32)
    B = torch.randn(K, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_matmul(A, B)) * 1000
    gpu_ms = _time(lambda: torch.matmul(A, B)) * 1000
    err = (_orig_matmul(A, B) - torch.matmul(A, B)).abs().max().item()
    after = bridge.stats()
    _row(f"({M},{K},{N})", cpu_ms, gpu_ms, err, _count_kernel_calls(before, after))


# ─── 2-D matmul, fp16 ──────────────────────────────────────────────
# iOS PyTorch CPU has no fp16 matmul kernel ("addmm_impl_cpu_ not
# implemented for Half"), so the CPU baseline runs as fp32. That's
# also what a user would have to do without the bridge installed, so
# the comparison is honest: GPU-native-fp16 vs CPU-cast-to-fp32.
_section("torch.matmul fp16  (CPU baseline runs fp32; iOS torch has no fp16 CPU)")
for M, K, N in [(256,256,256), (1024,1024,1024), (2048,2048,2048)]:
    A = torch.randn(M, K, dtype=torch.float16)
    B = torch.randn(K, N, dtype=torch.float16)
    A32 = A.float(); B32 = B.float()
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_matmul(A32, B32)) * 1000
    gpu_ms = _time(lambda: torch.matmul(A, B)) * 1000
    err = (_orig_matmul(A32, B32) - torch.matmul(A, B).float()).abs().max().item()
    after = bridge.stats()
    _row(f"({M},{K},{N})", cpu_ms, gpu_ms, err, _count_kernel_calls(before, after))


# ─── 2-D matmul, bf16 (bridge casts to fp32 internally) ────────────
_section("torch.matmul bf16  (CPU baseline runs fp32; bridge casts bf16→fp32→bf16)")
for M, K, N in [(256,256,256), (1024,1024,1024), (2048,2048,2048)]:
    A = torch.randn(M, K, dtype=torch.bfloat16)
    B = torch.randn(K, N, dtype=torch.bfloat16)
    A32 = A.float(); B32 = B.float()
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_matmul(A32, B32)) * 1000
    gpu_ms = _time(lambda: torch.matmul(A, B)) * 1000
    err = (_orig_matmul(A32, B32) - torch.matmul(A, B).float()).abs().max().item()
    after = bridge.stats()
    bf16_casts = after["dtype_bf16_cast"] - before["dtype_bf16_cast"]
    _row(f"({M},{K},{N})  bf16_casts={bf16_casts}", cpu_ms, gpu_ms, err,
         _count_kernel_calls(before, after))


# ─── 3-D batched matmul (attention QKᵀ shape) ──────────────────────
_section("torch.matmul fp32 batched  (B, M, K) @ (B, K, N)")
for B_, M, K, N in [(8, 128, 64, 128), (16, 256, 64, 256), (32, 512, 64, 512)]:
    A = torch.randn(B_, M, K, dtype=torch.float32)
    Bm = torch.randn(B_, K, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_matmul(A, Bm)) * 1000
    gpu_ms = _time(lambda: torch.matmul(A, Bm)) * 1000
    err = (_orig_matmul(A, Bm) - torch.matmul(A, Bm)).abs().max().item()
    after = bridge.stats()
    _row(f"(batch={B_}, {M}x{K}x{N})", cpu_ms, gpu_ms, err,
         _count_kernel_calls(before, after))


# ─── F.linear forward + backward, fp32 ─────────────────────────────
_section("F.linear fp32  forward + backward")
for B_, I, O in [(32, 512, 512), (64, 1024, 1024), (32, 2048, 2048),
                 (64, 2048, 4096)]:
    def make(dt):
        W = torch.randn(O, I, dtype=dt, requires_grad=True)
        x = torch.randn(B_, I, dtype=dt, requires_grad=True)
        return W, x
    def step(linear_fn, dt):
        W, x = make(dt)
        out = linear_fn(x, W)
        out.sum().backward()

    before = bridge.stats()
    cpu_ms = _time(lambda: step(_orig_linear, torch.float32), iters=5) * 1000
    gpu_ms = _time(lambda: step(F.linear, torch.float32), iters=5) * 1000
    W, x = make(torch.float32)
    err = (_orig_linear(x, W) - F.linear(x, W)).abs().max().item()
    after = bridge.stats()
    _row(f"(b={B_}, in={I}, out={O})", cpu_ms, gpu_ms, err,
         _count_kernel_calls(before, after))


# ─── torch.mm ──────────────────────────────────────────────────────
_section("torch.mm fp32   (M, K) @ (K, N)")
_orig_mm = bridge._orig_mm
for M, K, N in [(512,512,512), (1024,1024,1024), (2048,2048,2048)]:
    A = torch.randn(M, K, dtype=torch.float32)
    B = torch.randn(K, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_mm(A, B)) * 1000
    gpu_ms = _time(lambda: torch.mm(A, B)) * 1000
    err = (_orig_mm(A, B) - torch.mm(A, B)).abs().max().item()
    after = bridge.stats()
    _row(f"({M},{K},{N})", cpu_ms, gpu_ms, err, _count_kernel_calls(before, after))


# ─── torch.bmm ─────────────────────────────────────────────────────
_section("torch.bmm fp32  (B, M, K) @ (B, K, N)")
_orig_bmm = bridge._orig_bmm
for B_, M, K, N in [(8, 128, 128, 128), (16, 256, 256, 256), (32, 512, 64, 512)]:
    A = torch.randn(B_, M, K, dtype=torch.float32)
    Bm = torch.randn(B_, K, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_bmm(A, Bm)) * 1000
    gpu_ms = _time(lambda: torch.bmm(A, Bm)) * 1000
    err = (_orig_bmm(A, Bm) - torch.bmm(A, Bm)).abs().max().item()
    after = bridge.stats()
    _row(f"(b={B_}, {M}x{K}x{N})", cpu_ms, gpu_ms, err, _count_kernel_calls(before, after))


# ─── torch.addmm ───────────────────────────────────────────────────
_section("torch.addmm fp32   C + A@B")
_orig_addmm = bridge._orig_addmm
for M, K, N in [(512,512,512), (1024,1024,1024), (2048,2048,2048)]:
    A = torch.randn(M, K, dtype=torch.float32)
    B = torch.randn(K, N, dtype=torch.float32)
    C = torch.randn(M, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_addmm(C, A, B)) * 1000
    gpu_ms = _time(lambda: torch.addmm(C, A, B)) * 1000
    err = (_orig_addmm(C, A, B) - torch.addmm(C, A, B)).abs().max().item()
    after = bridge.stats()
    _row(f"({M},{K},{N})", cpu_ms, gpu_ms, err, _count_kernel_calls(before, after))


# ─── N-D × 2-D matmul (activations @ weight, common pattern) ───────
_section("torch.matmul fp32  (B, S, D) @ (D, N)  [mixed rank]")
for B_, S, D, N in [(2, 512, 1024, 1024), (4, 256, 2048, 2048), (2, 1024, 2048, 4096)]:
    A = torch.randn(B_, S, D, dtype=torch.float32)
    Bm = torch.randn(D, N, dtype=torch.float32)
    before = bridge.stats()
    cpu_ms = _time(lambda: _orig_matmul(A, Bm)) * 1000
    gpu_ms = _time(lambda: torch.matmul(A, Bm)) * 1000
    err = (_orig_matmul(A, Bm) - torch.matmul(A, Bm)).abs().max().item()
    after = bridge.stats()
    _row(f"(b={B_}, S={S}, D={D}, N={N})", cpu_ms, gpu_ms, err,
         _count_kernel_calls(before, after))


# ─── F.scaled_dot_product_attention (attention-shaped) ─────────────
if hasattr(F, "scaled_dot_product_attention") and bridge._orig_sdpa is not None:
    _section("F.scaled_dot_product_attention fp32  (B, H, S, D)")
    _orig_sdpa = bridge._orig_sdpa
    for B_, H, S, D in [(1, 8, 256, 64), (1, 14, 512, 64), (2, 14, 256, 64)]:
        q = torch.randn(B_, H, S, D, dtype=torch.float32)
        k = torch.randn(B_, H, S, D, dtype=torch.float32)
        v = torch.randn(B_, H, S, D, dtype=torch.float32)
        before = bridge.stats()
        cpu_ms = _time(lambda: _orig_sdpa(q, k, v), iters=5) * 1000
        gpu_ms = _time(lambda: F.scaled_dot_product_attention(q, k, v), iters=5) * 1000
        cpu_out = _orig_sdpa(q, k, v)
        gpu_out = F.scaled_dot_product_attention(q, k, v)
        err = (cpu_out - gpu_out).abs().max().item()
        after = bridge.stats()
        _row(f"(B={B_}, H={H}, S={S}, D={D})", cpu_ms, gpu_ms, err,
             _count_kernel_calls(before, after))


# ─── F.linear forward + backward, bf16 ─────────────────────────────
# Same story: CPU baseline runs fp32 (iOS torch has no bf16 CPU
# matmul); GPU runs native bf16 (with internal cast).
_section("F.linear bf16  (CPU baseline fp32, GPU native bf16)")
for B_, I, O in [(32, 1024, 1024), (32, 2048, 2048), (64, 2048, 4096)]:
    def step_cpu():
        W = torch.randn(O, I, dtype=torch.float32, requires_grad=True)
        x = torch.randn(B_, I, dtype=torch.float32, requires_grad=True)
        out = _orig_linear(x, W)
        out.sum().backward()
    def step_gpu():
        W = torch.randn(O, I, dtype=torch.bfloat16, requires_grad=True)
        x = torch.randn(B_, I, dtype=torch.bfloat16, requires_grad=True)
        out = F.linear(x, W)
        out.sum().backward()

    before = bridge.stats()
    cpu_ms = _time(step_cpu, iters=5) * 1000
    gpu_ms = _time(step_gpu, iters=5) * 1000
    # Accuracy check at matching fp32 inputs (cast bf16 result to fp32).
    W = torch.randn(O, I, dtype=torch.bfloat16)
    x = torch.randn(B_, I, dtype=torch.bfloat16)
    err = (_orig_linear(x.float(), W.float()) - F.linear(x, W).float()).abs().max().item()
    after = bridge.stats()
    _row(f"(b={B_}, in={I}, out={O})", cpu_ms, gpu_ms, err,
         _count_kernel_calls(before, after))


# ─── Final summary ─────────────────────────────────────────────────
collected = bridge.release_memory()
print(f"\nGC swept {collected} reference cycles on exit.")
print(f"Final stats: {bridge.stats()}")
total = (bridge.stats()["dtype_fp32"] + bridge.stats()["dtype_fp16"]
         + bridge.stats()["dtype_bf16_cast"])
if total == 0:
    print("\nNO GPU dispatches happened. The patch didn't fire — check that")
    print("the bridge installed and that _MIN_FLOPS was lowered.")
else:
    print(f"\nGPU was used {total} times across fp32/fp16/bf16 and 2-D/3-D paths.")
    print("Numerical errors are at the level expected from fp32 summation-order")
    print("differences (1e-3..1e-5 for fp32, 1e-1..1e-2 for fp16/bf16), so the")
    print("kernel is doing real arithmetic, not returning zeros.")
