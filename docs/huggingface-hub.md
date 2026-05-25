# huggingface_hub — HF Hub client

**Version:** 0.24.7
**Type:** Pure Python
**SPM target:** `HuggingfaceHub`
**Auto-includes:** (none)
**Total Python modules:** 60+ (top-level + 5 sub-packages)

Official client for the [Hugging Face Hub](https://huggingface.co/). Used to fetch pre-trained models, tokenizer configs, datasets, and metadata files — and (with a token) upload them too. Pairs with `transformers`, `tokenizers`, and `safetensors` to make the model lifecycle work on-device.

## Modules

### Top-level — public API surface

The package uses **lazy loading**: every top-level name is wired through `_SUBMOD_ATTRS` and resolved on first access.

| Module | What it does |
|---|---|
| `huggingface_hub.__init__` | Lazy re-exports. `from huggingface_hub import X` imports `X` from its sub-module on first use |
| `huggingface_hub.hf_api` | The `HfApi` class — every Hub HTTP endpoint as a Python method (`list_repo_files`, `model_info`, `dataset_info`, `space_info`, `list_models`, `list_datasets`, `list_spaces`, `upload_file`, `upload_folder`, `create_repo`, `delete_repo`, `create_branch`, `create_commit`, `create_discussion`, `comment_discussion`, …) |
| `huggingface_hub.file_download` | `hf_hub_download`, `try_to_load_from_cache`, `hf_hub_url`, etag-based resume, file-locking, ranged-GET retries |
| `huggingface_hub.hf_file_system` | `HfFileSystem` — fsspec-compatible filesystem over the Hub (`fs.ls`, `fs.glob`, `fs.open`) |
| `huggingface_hub._snapshot_download` | `snapshot_download(repo_id, ...)` — fetch all files for a revision |
| `huggingface_hub._commit_api` / `_commit_scheduler` | `CommitOperation*`, `CommitScheduler` (background commit batching) |
| `huggingface_hub._local_folder` | Per-folder cache index (`.cache/huggingface/download/`) |
| `huggingface_hub._login` | `login`, `logout`, `interpreter_login`, `notebook_login` (browser-based — **iOS not viable**) |
| `huggingface_hub._multi_commits` | Multi-commit PR workflow for large updates |
| `huggingface_hub._inference_endpoints` | `InferenceEndpoint` (serverless inference endpoint management) |
| `huggingface_hub._space_api` | `SpaceHardware`, `SpaceRuntime`, `SpaceStage`, `SpaceVariable` |
| `huggingface_hub._tensorboard_logger` | `HFSummaryWriter` — TensorBoard with auto-push to Hub |
| `huggingface_hub._webhooks_payload` / `_webhooks_server` | Webhook server harness — needs a public URL, not useful on iOS |
| `huggingface_hub.constants` | `HF_HOME`, `HF_HUB_CACHE`, `HF_HUB_OFFLINE`, `HF_HUB_DISABLE_*` env-var-driven constants. Default cache is `~/.cache/huggingface/hub` |
| `huggingface_hub.errors` | `HfHubHTTPError`, `RepositoryNotFoundError`, `RevisionNotFoundError`, `EntryNotFoundError`, `LocalEntryNotFoundError`, `BadRequestError`, `GatedRepoError`, `DisabledRepoError` |
| `huggingface_hub.community` | `Discussion`, `DiscussionWithDetails`, `DiscussionComment`, `DiscussionEvent`, `DiscussionStatusChange`, `DiscussionTitleChange`, `DiscussionCommit`, `DiscussionEdit` |
| `huggingface_hub.repocard` / `repocard_data` | `ModelCard`, `DatasetCard`, `SpaceCard`, `RepoCard.from_template` + dataclass-backed metadata |
| `huggingface_hub.hub_mixin` | `ModelHubMixin`, `PyTorchModelHubMixin` — add `from_pretrained` / `save_pretrained` to custom classes |
| `huggingface_hub.fastai_utils` | fastai save/load helpers (unused on iOS; fastai not bundled) |
| `huggingface_hub.keras_mixin` | Keras save/load helpers (unused on iOS) |
| `huggingface_hub.lfs` | Git-LFS multi-part upload (HTTP, not git) |
| `huggingface_hub.repository` | Legacy git-LFS wrapper (`Repository`) — **needs git binary, unused on iOS** |
| `huggingface_hub.inference_api` | Deprecated; superseded by `InferenceClient` |

### `huggingface_hub.inference` — Hub inference API client

| Module | What it does |
|---|---|
| `inference._client` | `InferenceClient` — chat, generation, image, audio, embeddings via Hub's hosted inference |
| `inference._async_client` | `AsyncInferenceClient` (asyncio variant) |
| `inference._common` | Shared validation + payload builders |
| `inference._templating` | Chat-template rendering helpers |
| `inference._generated.types.*` | Per-task input/output dataclasses (`ChatCompletionInput`, `TextGenerationInput`, `ImageToImageOutput`, etc.) auto-generated from the API spec |
| `inference._types` | Legacy aliases |

### `huggingface_hub.utils` — internal helpers

| Module | What it does |
|---|---|
| `utils._cache_manager` | `scan_cache_dir()`, `HFCacheInfo`, `CachedRepoInfo`, `DeleteCacheStrategy` — disk usage report + GC |
| `utils._cache_assets` | Asset cache (`HF_ASSETS_CACHE`) for non-repo files |
| `utils._hf_folder` | `HfFolder.get_token`, `save_token`, `delete_token` (back-compat alias) |
| `utils._token` | `get_token`, `interpreter_login`-friendly token resolution |
| `utils._http` | `configure_http_backend`, `get_session`, `hf_raise_for_status`, request middleware |
| `utils._headers` | Build `User-Agent` + `Authorization` headers |
| `utils._chunk_utils` | Iter file in HTTP-Range chunks |
| `utils._paths` | Path validation + repo-relative path helpers |
| `utils._git_credential` | Stash token in git credential helper (no-op without git) |
| `utils._validators` | `validate_repo_id`, `smoothly_deprecate_use_auth_token` |
| `utils._deprecation` | Deprecation-warning decorators |
| `utils._errors` | Exception hierarchy (re-exported from `huggingface_hub.errors`) |
| `utils._datetime` | Hub-format date parsing |
| `utils._pagination` | `paginate(...)` for endpoint listings |
| `utils._runtime` | `is_torch_available`, `is_tf_available`, `dump_environment_info`, package-version sniffing |
| `utils._safetensors` | Internal `.safetensors` header parsing |
| `utils._subprocess` | `run_subprocess` — unused on iOS (no subprocess) |
| `utils._telemetry` | Send-only telemetry; respects `HF_HUB_DISABLE_TELEMETRY` |
| `utils._fixes` | Vendored backports (`yaml.SafeLoader`, etc.) |
| `utils._experimental` | `experimental` decorator (warns on use) |
| `utils._typing` | TypedDicts |
| `utils.endpoint_helpers` | `DatasetFilter`, `ModelFilter`, `_filter_emissions` |
| `utils.insecure_hashlib` / `sha` | MD5 + SHA helpers (etag computation; cache keying) |
| `utils.logging` | HF logging wrapper |
| `utils.tqdm` | tqdm wrapper (respects `HF_HUB_DISABLE_PROGRESS_BARS`) |

### `huggingface_hub.serialization` — state-dict ↔ file conversions

| Module | What it does |
|---|---|
| `serialization._base` | `save_torch_state_dict`, `load_torch_state_dict`, `split_state_dict_into_shards_factory` |
| `serialization._torch` | PyTorch shard splitter (auto-sharded `pytorch_model-00001-of-00003.bin` etc.) |
| `serialization._tensorflow` | TF variant — unused on iOS |

### `huggingface_hub.commands` — `huggingface-cli` entry points

`huggingface_cli`, `delete_cache`, `download`, `env`, `lfs`, `repo_files`, `scan_cache`, `tag`, `upload`, `user`, `_cli_utils`. The CLI itself is **not bundled** as a script on iOS — use the Python API directly.

### `huggingface_hub.templates`

`modelcard_template.md`, `datasetcard_template.md` — Jinja sources used by `RepoCard.from_template()`.

## iOS-specific notes

### Cache layout

The default cache lives at `~/.cache/huggingface/hub/`, which is **sandbox-blocked on iOS**. Set `HF_HUB_CACHE` (or `HF_HOME`) to a writable path BEFORE first import:

```python
import os
os.environ["HF_HUB_CACHE"] = os.path.expanduser(
    "~/Documents/.cache/huggingface/hub")
import huggingface_hub
print(huggingface_hub.constants.HF_HUB_CACHE)
```

`~/Documents/` is writable on iOS AND survives app upgrades (Documents is user data, not the app bundle).

### Symlinks

The Hub cache normally uses symlinks to dedupe revisions sharing files. iOS's sandbox is iffy with symlinks crossing paths; set `HF_HUB_DISABLE_SYMLINKS_WARNING=1` and the cache silently copies files instead. Costs disk; safer.

### Authentication

```python
from huggingface_hub import HfFolder, login

# Programmatic — works on iOS
HfFolder.save_token("hf_xxxxxx")    # writes ~/.cache/huggingface/token

# Browser-based — DOES NOT work on iOS
login()                              # opens system browser
interpreter_login()                  # same
```

`login()` / `interpreter_login()` / `notebook_login()` all expect either a TTY or `webbrowser.open()` — neither works under the iOS app sandbox. Use `HfFolder.save_token()` with a token fetched from a settings UI or keychain.

### Pre-loading for offline use

```python
# On a Mac before building the app:
from huggingface_hub import snapshot_download
snapshot_download("distilbert/distilbert-base-uncased",
                  local_dir="./bundled_models/distilbert")
# Then copy bundled_models/distilbert/ into your iOS app bundle and
# point HF_HUB_CACHE at it on startup.
```

## Standalone example

```python
from huggingface_hub import hf_hub_download, snapshot_download, HfApi

# Single file (e.g. a tokenizer config)
cfg = hf_hub_download(repo_id="bert-base-uncased", filename="config.json")

# Whole repo (weights + tokenizer + config)
local = snapshot_download(
    repo_id="distilbert/distilbert-base-uncased",
    local_dir="/path/Documents/models/distilbert",
)

# Metadata + listing
api = HfApi()
info = api.model_info("openai/whisper-tiny")
print(info.tags, info.pipeline_tag)
print([s.rfilename for s in info.siblings])

# Search the Hub
for m in api.list_models(filter="text-generation", limit=10):
    print(m.id, m.downloads)
```

## Pairing with transformers

```python
from transformers import AutoTokenizer, AutoModel

# Both route through huggingface_hub for downloads.
tok   = AutoTokenizer.from_pretrained("distilbert-base-uncased")
model = AutoModel.from_pretrained("distilbert-base-uncased")
```

The `from_pretrained` cache is shared with `huggingface_hub`'s, so manual `hf_hub_download` calls populate the same cache.

## Limitations

- **`interpreter_login()` / `notebook_login()` / `login()` browser flow** — don't work; use `HfFolder.save_token(...)` directly
- **No `git` / `git-lfs` push** — uploads via `upload_file` use the HTTP API; the legacy `Repository` class needs a git binary and is unusable on iOS
- **`huggingface-cli` shell command** — not bundled as a script; use the Python API
- **`_webhooks_server`** — needs a public URL, can't run on iOS
- **`hf_transfer` fast downloader** — Rust binary, not bundled; falls back to plain Python HTTP
- **Telemetry** — respects `HF_HUB_DISABLE_TELEMETRY=1` if you want to silence the once-per-session phone-home

## Troubleshooting

### `ConnectionError: Connection aborted`

Cellular ↔ Wi-Fi switch mid-download. `hf_hub_download` auto-retries with etag-based resume — prefer it over streaming `requests`.

### `OSError: Disk quota exceeded`

Cache grew large. Clean with:
```python
from huggingface_hub import scan_cache_dir
report = scan_cache_dir()
print(report)
report.delete_revisions(...).execute()
```

### `LocalEntryNotFoundError`

File isn't in cache and `local_files_only=True`. Either download first or set `local_files_only=False`.

### Slow first download on cellular

Pass `etag_timeout=30` to give the metadata fetch more headroom.

## See also

- [docs/transformers.md](transformers.md) — uses `huggingface_hub` for downloads
- [docs/tokenizers.md](tokenizers.md) — `Tokenizer.from_pretrained` routes through it too
- [docs/safetensors.md](safetensors.md) — weights downloaded via the Hub are `.safetensors` by default
