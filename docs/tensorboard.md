# TensorBoard — 2.19.0 (iOS, writer only)

Bundled and device-verified for **writing** event logs. Version **2.19.0**
specifically: 2.21's protobuf gencode declares a min-runtime of 6.31.1, but the
bundle ships protobuf 5.29.6 → "incompatible Gencode/Runtime" at import. 2.19 uses
old-style gencode (no min check) and works.

## What works

- `torch.utils.tensorboard.SummaryWriter(log_dir=...)`
- `add_scalar`, `add_scalars`, `add_histogram`, `add_image`, `add_text`,
  `add_hparams`, `add_graph` — write real `events.out.tfevents.*` files offline
  (device-verified: 10 KB event file written)
- `Trainer(..., report_to="tensorboard")` in transformers logs through the same writer

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `tensorboard` **viewer** server (`tensorboard --logdir`) | **Not available** — needs `grpcio` (C extension, not cross-compiled) and a background HTTP server | Copy the `events.out.tfevents.*` files off-device and open them in desktop TensorBoard; or use `_cb_training.TrainingMonitor` for in-terminal metrics |

## See also
- [transformers.md](transformers.md) · [torch.md](torch.md) · [codebench-extras.md](codebench-extras.md)
