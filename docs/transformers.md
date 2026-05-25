# transformers — HuggingFace model library

**Version:** 4.41.2
**Type:** Pure Python (deps: PyTorch + Tokenizers + huggingface_hub + safetensors + filelock)
**SPM target:** `Transformers`
**Auto-includes:** Torch, Tokenizers, Huggingface-Hub, Safetensors, Accelerate, PEFT
**Total Python modules:** 1500+ (top-level + 250+ model packages)

HuggingFace's transformers library: pre-trained model architectures (BERT, GPT-2, T5, Llama, Qwen, Mistral, Phi, Whisper, …), training utilities (`Trainer`, `TrainingArguments`), the `pipeline()` shortcuts, the `Auto*` classes for one-line model loads. Train, fine-tune, and `.generate()` on-device. A more category-organised reference is at [docs/libs/transformers.md](libs/transformers.md).

## Modules

### Top-level — Auto / config / tokenizer / model API

| Module | What it does |
|---|---|
| `transformers.__init__` | Lazy-loaded re-exports for every `Auto*` / model / tokenizer / pipeline. Triggers **sitecustomize transformers-auto-patch** for `TrainingArguments` checkpointing defaults |
| `transformers.configuration_utils` | `PretrainedConfig` base class |
| `transformers.modeling_utils` | `PreTrainedModel` base — `.from_pretrained`, `.save_pretrained`, `.generate`, `.gradient_checkpointing_enable`, weight tying |
| `transformers.tokenization_utils` / `tokenization_utils_base` / `tokenization_utils_fast` | `PreTrainedTokenizer` (slow Python) + `PreTrainedTokenizerFast` (wraps `tokenizers.Tokenizer`) |
| `transformers.modeling_outputs` | Dataclasses returned by model forward (`BaseModelOutput`, `CausalLMOutput`, `Seq2SeqLMOutput`, …) |
| `transformers.modeling_attn_mask_utils` | Attention-mask construction helpers |
| `transformers.activations` | `gelu_new`, `gelu_fast`, `silu`, `mish`, `quick_gelu`, etc. |
| `transformers.cache_utils` | `DynamicCache`, `StaticCache`, `SinkCache`, `HybridCache` (KV-cache abstractions) |
| `transformers.processing_utils` | `ProcessorMixin` (multi-modal model helpers — text + image + audio) |
| `transformers.feature_extraction_utils` / `feature_extraction_sequence_utils` | Feature extraction base classes (audio / time-series) |
| `transformers.image_processing_utils` / `image_transforms` / `image_utils` | Vision model preprocessing |
| `transformers.audio_utils` | Mel-spectrogram, STFT helpers (Whisper, Wav2Vec2) |
| `transformers.modelcard` | Model card generation |
| `transformers.hf_argparser` | Dataclass → argparse glue used by `TrainingArguments` |
| `transformers.dynamic_module_utils` | `trust_remote_code` machinery for repos that ship custom modeling code |
| `transformers.convert_slow_tokenizer` | Convert slow tokenizers to fast (Rust) versions |
| `transformers.optimization` | `AdamW` (HF variant), `get_linear_schedule_with_warmup`, `get_cosine_schedule_with_warmup` |
| `transformers.pytorch_utils` | PyTorch helpers (`Conv1D`, `prune_*`, version-gated branches). Uses `safetensors.torch.storage_ptr` / `storage_size` |
| `transformers.file_utils` | Legacy re-exports (forwarded to `utils.hub`) |
| `transformers.debug_utils` / `testing_utils` / `time_series_utils` / `safetensors_conversion` | Misc utilities |

### `transformers.models.*` — 250+ model architectures

Each model family lives in its own subpackage with `configuration_<name>.py`, `modeling_<name>.py`, and (usually) `tokenization_<name>.py`. Selected high-traffic families:

**Encoders (BERT family):** `albert`, `bert`, `bert_generation`, `bertweet`, `big_bird`, `camembert`, `convbert`, `deberta`, `deberta_v2`, `distilbert`, `electra`, `ernie`, `ernie_m`, `flaubert`, `fnet`, `funnel`, `herbert`, `ibert`, `mobilebert`, `mpnet`, `nezha`, `nystromformer`, `phobert`, `rembert`, `roberta`, `roberta_prelayernorm`, `roc_bert`, `roformer`, `splinter`, `squeezebert`, `xlm`, `xlm_roberta`, `xlm_roberta_xl`, `xlnet`, `xmod`, `yoso`

**Decoders / causal LMs:** `bloom`, `codegen`, `code_llama`, `cohere`, `cpm`, `cpmant`, `ctrl`, `dbrx`, `falcon`, `gemma`, `gpt2`, `gptj`, `gpt_bigcode`, `gpt_neo`, `gpt_neox`, `gpt_neox_japanese`, `gpt_sw3`, `llama`, `mamba`, `mistral`, `mixtral`, `mpt`, `olmo`, `openai`, `opt`, `persimmon`, `phi`, `phi3`, `qwen2`, `qwen2_moe`, `recurrent_gemma`, `rwkv`, `stablelm`, `starcoder2`, `xglm`

**Encoder-decoders / seq2seq:** `bart`, `barthez`, `bartpho`, `bigbird_pegasus`, `blenderbot`, `blenderbot_small`, `byt5`, `encoder_decoder`, `fsmt`, `led`, `longt5`, `m2m_100`, `marian`, `mbart`, `mbart50`, `mt5`, `mvp`, `nllb`, `nllb_moe`, `pegasus`, `pegasus_x`, `plbart`, `prophetnet`, `seamless_m4t`, `seamless_m4t_v2`, `switch_transformers`, `t5`, `udop`, `umt5`, `xlm_prophetnet`

**Vision:** `beit`, `bit`, `conditional_detr`, `convnext`, `convnextv2`, `cvt`, `deformable_detr`, `deit`, `deta`, `detr`, `dinat`, `dinov2`, `dit`, `donut`, `dpt`, `efficientformer`, `efficientnet`, `focalnet`, `glpn`, `imagegpt`, `levit`, `mask2former`, `maskformer`, `mobilenet_v1`, `mobilenet_v2`, `mobilevit`, `mobilevitv2`, `nat`, `oneformer`, `poolformer`, `pvt`, `pvt_v2`, `regnet`, `resnet`, `segformer`, `seggpt`, `superpoint`, `swiftformer`, `swin`, `swin2sr`, `swinv2`, `table_transformer`, `timesformer`, `upernet`, `videomae`, `vit`, `vit_hybrid`, `vit_mae`, `vit_msn`, `vitdet`, `vitmatte`, `vivit`, `yolos`

**Audio / speech:** `audio_spectrogram_transformer`, `bark`, `clap`, `clvp`, `encodec`, `fastspeech2_conformer`, `hubert`, `musicgen`, `musicgen_melody`, `pop2piano`, `sew`, `sew_d`, `speech_to_text`, `speech_to_text_2`, `speech_encoder_decoder`, `speecht5`, `unispeech`, `unispeech_sat`, `univnet`, `wav2vec2`, `wav2vec2_bert`, `wav2vec2_conformer`, `wav2vec2_phoneme`, `wav2vec2_with_lm`, `wavlm`, `whisper`

**Multi-modal:** `align`, `altclip`, `blip`, `blip_2`, `bridgetower`, `chinese_clip`, `clip`, `clipseg`, `flava`, `git`, `groupvit`, `idefics`, `instructblip`, `kosmos2`, `llava`, `llava_next`, `mgp_str`, `nougat`, `owlv2`, `owlvit`, `paligemma`, `pix2struct`, `siglip`, `tvlt`, `tvp`, `video_llava`, `vilt`, `vipllava`, `vision_encoder_decoder`, `vision_text_dual_encoder`, `visual_bert`, `x_clip`

**Other:** `autoformer`, `bros`, `canine`, `decision_transformer`, `depth_anything`, `dpr`, `esm` (protein), `fuyu`, `graphormer`, `grounding_dino`, `informer`, `jukebox`, `layoutlm*`, `luke`, `lxmert`, `markuplm`, `mega`, `megatron_*`, `mra`, `patchtst`, `patchtsmixer`, `perceiver`, `qdqbert`, `rag`, `reformer`, `realm`, `sam`, `tapas`, `time_series_transformer`, `timm_backbone`, `trocr`, `vits`

**`models.auto`** — `AutoConfig`, `AutoTokenizer`, `AutoModel`, `AutoModelFor*` (`CausalLM`, `Seq2SeqLM`, `MaskedLM`, `SequenceClassification`, `TokenClassification`, `QuestionAnswering`, `MultipleChoice`, `Vision2Seq`, `SpeechSeq2Seq`, `AudioClassification`, etc.), `AutoFeatureExtractor`, `AutoImageProcessor`, `AutoProcessor`.

**`models.deprecated`** — older architectures retained for backwards-compat.

### `transformers.generation` — text generation

| Submodule | Provides |
|---|---|
| `generation.utils` | `GenerationMixin` (the `.generate()` method itself), `BeamSearchScorer`, `GenerateOutput` |
| `generation.configuration_utils` | `GenerationConfig` |
| `generation.logits_process` | `TemperatureLogitsWarper`, `TopKLogitsWarper`, `TopPLogitsWarper`, `RepetitionPenaltyLogitsProcessor`, `MinLengthLogitsProcessor`, `NoRepeatNGramLogitsProcessor`, `EncoderRepetitionPenaltyLogitsProcessor`, … |
| `generation.stopping_criteria` | `MaxLengthCriteria`, `MaxTimeCriteria`, `StoppingCriteriaList`, `EosTokenCriteria` |
| `generation.beam_search` / `beam_constraints` | Beam search + constrained beam search |
| `generation.candidate_generator` | Speculative / assisted decoding |
| `generation.streamers` | `TextStreamer`, `TextIteratorStreamer` (token-by-token streaming) |
| `generation.watermarking` | `WatermarkingConfig`, `WatermarkDetector` |
| `generation.flax_utils` / `tf_utils` / `flax_logits_process` / `tf_logits_process` | JAX + TF variants — **not used on iOS** |

### `transformers.pipelines` — high-level task shortcuts

| Pipeline | Task |
|---|---|
| `pipelines.text_generation` | `pipeline("text-generation")` |
| `pipelines.text_classification` | `pipeline("text-classification" / "sentiment-analysis")` |
| `pipelines.token_classification` | `pipeline("token-classification" / "ner")` |
| `pipelines.question_answering` | `pipeline("question-answering")` |
| `pipelines.fill_mask` | `pipeline("fill-mask")` |
| `pipelines.text2text_generation` | `pipeline("text2text-generation" / "translation" / "summarization")` |
| `pipelines.conversational` | `pipeline("conversational")` (deprecated; use chat templates) |
| `pipelines.feature_extraction` | `pipeline("feature-extraction")` — embeddings |
| `pipelines.image_classification` / `image_segmentation` / `image_feature_extraction` / `image_to_image` / `image_to_text` | Vision tasks |
| `pipelines.automatic_speech_recognition` | Whisper / Wav2Vec2 ASR |
| `pipelines.audio_classification` | Audio classification |
| `pipelines.text_to_audio` | `pipeline("text-to-audio")` (Bark, MusicGen) |
| `pipelines.object_detection` / `depth_estimation` / `mask_generation` | More vision |
| `pipelines.zero_shot_classification` / `zero_shot_image_classification` / `zero_shot_audio_classification` / `zero_shot_object_detection` | Zero-shot variants |
| `pipelines.video_classification` | Video |
| `pipelines.table_question_answering` | TAPAS |
| `pipelines.document_question_answering` / `visual_question_answering` | DocQA + VQA |

### `transformers.data` — datasets, collators, processors

| Submodule | Provides |
|---|---|
| `data.data_collator` | `DataCollatorWithPadding`, `DataCollatorForLanguageModeling`, `DataCollatorForSeq2Seq`, `DataCollatorForTokenClassification`, `DefaultDataCollator` |
| `data.datasets` | Lightweight torch `Dataset` wrappers (`GlueDataset`, `SquadDataset`, `LineByLineTextDataset`, `TextDataset`) |
| `data.processors` | GLUE / SQuAD / XNLI feature converters |
| `data.metrics` | Built-in metric helpers (mostly superseded by `evaluate`) |

### `transformers.trainer*` — training loop

| Module | What it does |
|---|---|
| `trainer` | The `Trainer` class — full training loop with eval, checkpointing, logging. **sitecustomize-patched** to auto-resume from `output_dir/checkpoint-*` |
| `trainer_callback` | `TrainerCallback`, `ProgressCallback`, `EarlyStoppingCallback` |
| `trainer_pt_utils` | PyTorch-specific helpers (`get_parameter_names`, distributed gathers — distributed paths inert on iOS) |
| `trainer_seq2seq` | `Seq2SeqTrainer` |
| `trainer_utils` | `EvalPrediction`, `IntervalStrategy`, `SchedulerType`, `set_seed` |
| `training_args` | `TrainingArguments`. **sitecustomize-patched**: `save_steps=100`, `save_total_limit=3` defaults injected |
| `training_args_seq2seq` | `Seq2SeqTrainingArguments` |
| `training_args_tf` | TF variant — unused on iOS |
| `hyperparameter_search` | Optuna / Ray / SigOpt wrappers — none bundled |
| `keras_callbacks` | Keras integration — N/A on iOS |

### `transformers.utils`

| Module | What it does |
|---|---|
| `utils.hub` | `cached_file`, `try_to_load_from_cache`, `extract_commit_hash` — wraps `huggingface_hub` |
| `utils.import_utils` | `is_torch_available`, `is_tf_available`, `is_flash_attn_2_available`, `requires_backends` |
| `utils.generic` | `ModelOutput` base dataclass, `cached_property`, `find_labels` |
| `utils.logging` | HF logging wrapper |
| `utils.constants` / `versions` / `peft_utils` / `quantization_config` / `bitsandbytes` / `fx` | Misc |
| `utils.dummy_*_objects` | Stub-class placeholders for missing optional backends (TF, Flax, vision, music, sentencepiece, tokenizers) so import errors are deferred to use-site |
| `utils.notebook` | Jupyter / Colab progress widgets |
| `utils.sentencepiece_model_pb2` / `sentencepiece_model_pb2_new` | Protobuf for SentencePiece model files |

### `transformers.integrations` — third-party glue

`bitsandbytes`, `awq`, `aqlm`, `eetq`, `hqq`, `quanto`, `peft`, `deepspeed`, `ggml`, `tpu`, `integration_utils` (W&B, MLflow, Neptune, Comet, ClearML, TensorBoard, CodeCarbon, DagsHub). Most of the quantization integrations are **CUDA-only** and inert on iOS; `peft` works, `ggml` works for reading, `integration_utils` falls back gracefully when backends are absent.

### `transformers.quantizers` — quantization frontends

`auto`, `base`, `quantizer_aqlm`, `quantizer_awq`, `quantizer_bnb_4bit`, `quantizer_bnb_8bit`, `quantizer_eetq`, `quantizer_gptq`, `quantizer_hqq`, `quantizer_quanto`. Backends gated by availability checks — most fail-soft on iOS.

### `transformers.agents` — tool-using LLM agents (experimental)

`agents`, `default_tools`, `llm_engine`, `python_interpreter`, `prompts`, `tools`, `agent_types`, `document_question_answering`, `image_question_answering`, `speech_to_text`, `text_to_speech`, `translation`, `evaluate_agent`. The `PythonInterpreter` tool works on-device; remote tools need network.

### `transformers.onnx` / `transformers.benchmark` / `transformers.commands`

ONNX export (`features`, `convert`), inference-speed benchmark helpers, and the `transformers-cli` entry points (`add_new_model_like`, `convert`, `download`, `env`, `lfs`, `pt_to_tf`, `run`, `serving`, `train`, `user`).

### `transformers.kernels` — CUDA kernel sources

`deformable_detr`, `deta`, `mra`, `rwkv`, `yoso`. Source-only — the CUDA kernels don't build on iOS; PyTorch fallbacks are used instead.

### `transformers.sagemaker`

Amazon SageMaker `Trainer` variants — present for upstream parity; not useful on iOS.

### TF / Flax / Keras files

`modeling_tf_*`, `modeling_flax_*`, `tf_utils`, `activations_tf`, `keras_callbacks`, `optimization_tf` are present for upstream parity; TF / Flax / Keras aren't bundled, so importing these triggers a "backend not available" error.

## iOS-specific patches

| Patch | Where | Why |
|---|---|---|
| `TrainingArguments` defaults | `sitecustomize.py` (`_apply_transformers_defaults`) | `save_steps=100`, `save_total_limit=3` injected unless user passes them — iPad can be backgrounded any moment |
| `Trainer.train()` auto-resume | `sitecustomize.py` | Scans `args.output_dir` for `checkpoint-*` dirs and sets `resume_from_checkpoint=True` if found; disable with `CODEBENCH_AUTO_CHECKPOINT=0` |
| `transformers` import hook | `sitecustomize.py` (`_install_transformers_import_hook`) | Wraps `transformers`'s import spec via `importlib.util.spec_from_file_location` so `__file__` gets set on the partial module (HF lazy-import scaffolding `KeyError`s otherwise) |
| `safetensors.torch.storage_ptr` / `storage_size` | `app_packages/.../safetensors/torch.py` | Real safetensors is unavailable as a Rust wheel; `transformers.pytorch_utils` needs these two functions for tied-weight detection — pure-Python copies provided |
| `safetensors.torch.load_file` / `save_file` | `app_packages/.../safetensors/torch.py` | Re-exports the pure-Python writer from the parent `safetensors` module — letting `model.save_pretrained()` produce valid `.safetensors` files |

## Standalone example

```python
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
import torch

# Encoder + decoder loads
tok   = AutoTokenizer.from_pretrained("path/to/Qwen2.5-1.5B")
model = AutoModelForCausalLM.from_pretrained(
    "path/to/Qwen2.5-1.5B",
    torch_dtype=torch.float16,   # fp16 halves memory; Metal bridge handles matmul
)

ids = tok("The quick brown fox", return_tensors="pt").input_ids
out = model.generate(ids, max_new_tokens=30, do_sample=True, temperature=0.8)
print(tok.decode(out[0], skip_special_tokens=True))

# Pipeline shortcut
pipe = pipeline("text-generation", model=model, tokenizer=tok)
print(pipe("Once upon a time,", max_new_tokens=20)[0]["generated_text"])

# Fine-tune (no Trainer, no multiprocessing dataloader)
opt = torch.optim.AdamW(model.parameters(), lr=5e-5)
for batch_text, batch_label in your_dataset:
    enc = tok(batch_text, return_tensors="pt", padding=True, truncation=True)
    loss = model(**enc, labels=batch_label).loss
    opt.zero_grad(); loss.backward(); opt.step()
```

## iOS notes

### What works on iPad

- `AutoModel`, `AutoTokenizer`, `AutoModelFor*` `.from_pretrained()` — local paths + Hub URLs (latter needs network)
- `model.generate()` — greedy, beam, sampling, top-k/p, temperature, repetition penalty, stopping criteria
- `Trainer.train()` — auto-checkpoint + auto-resume via sitecustomize patches; set `dataloader_num_workers=0`
- `model.save_pretrained(...)` — writes both `pytorch_model.bin` and `.safetensors` (pure-Python writer)
- `peft.get_peft_model()` + LoRA / IA3 / prefix-tuning (PEFT is bundled separately)
- Mixed precision: `bf16=True` or `fp16=True` in `TrainingArguments`, or `torch_dtype=torch.float16` at load
- Verified model families: BERT, GPT-2, T5, BART, Llama, Qwen, Mistral, Phi, DistilBERT, Whisper

### What doesn't / has caveats

| Op / feature | Status | Workaround |
|---|---|---|
| `datasets.load_dataset(...)` | `datasets` not bundled (needs `pyarrow` + `pandas`) | Subclass `torch.utils.data.Dataset` — 5-10 lines |
| `DataLoader(num_workers>0)` | iOS forbids `fork()` | `num_workers=0` only |
| `torch.compile` / FlashAttention2 | No Triton, no `flash_attn` package | Falls back to PyTorch SDPA — which IS GPU-accelerated via the Metal bridge |
| `bitsandbytes` 4/8-bit / AWQ / AQLM / GPTQ / EETQ | CUDA-only | Use GGUF + `llama.cpp` for quantized inference |
| `DeepSpeed`, `FSDP`, `torch.distributed.*` | Multi-process | N/A (single device) |
| Sentencepiece-only tokenizers | `sentencepiece` C++ not cross-compiled | BPE-based models (GPT-2 / Qwen / Mistral / Phi) work; pure-SP tokenizers (Llama-1, T5, BART, mBART) blocked |
| `device_map="auto"` | One device only | Pass `torch_dtype=torch.float16` to reduce memory instead |
| `evaluate.load(...)` | `evaluate` not bundled | Compute metrics inline |
| TensorBoard writer | No background server / UI | Use `_cb_training.TrainingMonitor` for terminal output |
| `interpreter_login()` | Opens system browser | Use `huggingface_hub.HfFolder.save_token("hf_...")` instead |

### Memory tips

- **Half-precision (`fp16`) for inference** — models load 2× smaller; ~1.5× faster on Accelerate
- **`torch.no_grad()` / `model.eval()`** — don't keep gradients during inference
- **Free models explicitly** — `del model; gc.collect()` between switches; GC doesn't reclaim a 1.5 GB model promptly
- **Soft cap ~3 GB** working set; ~6 GB risks jetsam on memory-tight devices

### Quick-fit models

| Model | Size | Use case |
|---|---|---|
| `distilbert-base-uncased` | 250 MB | Embeddings, classification |
| `Qwen2.5-1.5B-Instruct-Q4` | 1.0 GB | Chat / generation (quantized) |
| `Qwen2.5-3B-Instruct-Q4` | 1.9 GB | Better generation; 8 GB devices |
| `whisper-tiny` | 75 MB | Speech recognition |
| `bart-large-cnn` | 1.6 GB | Summarization |

## See also

- [docs/libs/transformers.md](libs/transformers.md) — category-organised reference
- [docs/torch.md](torch.md) — PyTorch backend
- [docs/tokenizers.md](tokenizers.md) — Rust tokenizer details
- [docs/safetensors.md](safetensors.md) — weight I/O
- [docs/huggingface-hub.md](huggingface-hub.md) — model download
