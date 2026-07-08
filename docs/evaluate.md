# evaluate — HuggingFace Evaluate 0.4.6 (iOS)

Bundled and device-verified. Computes metrics for training/eval loops.

## What works

- `import evaluate` and local metric compute
- `evaluate.load("accuracy")` → `.compute(references=..., predictions=...)`
  (device-verified → `{'accuracy': 0.75}`)
- Combining metrics, `evaluate.combine([...])`

## Gaps

| Feature | Status | Workaround |
|---|---|---|
| `evaluate.load("<name>")` first call | **Downloads the metric script** from the Hub | Needs network once; the script then runs fully offline. Or compute the metric inline (accuracy/F1 are a few lines) |
| Metrics needing extra C/Rust deps (e.g. `sacrebleu`, `bleurt`) | The metric script imports a dep that may not be bundled | Stick to pure-Python metrics (accuracy, f1, precision, recall, mse, mae) |

## See also
- [datasets.md](datasets.md) · [transformers.md](transformers.md)
