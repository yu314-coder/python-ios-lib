# huggingface_hub

> **Version:** 0.24.7  | **Type:** Pure Python  | **Status:** Working — model download + cache + metadata; uploads need a HF token

The official client for the [Hugging Face Hub](https://huggingface.co/).
Used for fetching pre-trained models, tokenizer configs, datasets, and
metadata files — and (with a token) uploading them too. Pairs with
`transformers` and `tokenizers` to make the model lifecycle work
on-device.

---

## Quick start — download a model

```python
from huggingface_hub import hf_hub_download, snapshot_download

# Single file (e.g. a tokenizer config)
config_path = hf_hub_download(
    repo_id="bert-base-uncased",
    filename="config.json",
)
print(config_path)  # /Users/.../.cache/huggingface/hub/models--bert-base-uncased/.../config.json

# Whole repo (model weights + tokenizer + config)
local_dir = snapshot_download(
    repo_id="distilbert/distilbert-base-uncased",
    local_dir="/path/Documents/models/distilbert",
)
```

```python
# List files in a repo without downloading
from huggingface_hub import HfApi

api = HfApi()
for f in api.list_repo_files("bert-base-uncased"):
    print(f)
```

```python
# Get repo metadata
info = api.model_info("openai/whisper-tiny")
print(info.tags)               # ['audio', 'automatic-speech-recognition', ...]
print(info.pipeline_tag)       # 'automatic-speech-recognition'
print([s.rfilename for s in info.siblings])  # all files in the repo
```

---

## iOS-specific cache layout

The default cache lives at `~/.cache/huggingface/hub/`, but on iOS
that path is sandbox-blocked. The shim auto-redirects to
`~/Documents/.cache/huggingface/hub/`, which is writable AND survives
app upgrades (Documents is part of the user's data, not the app
bundle).

```python
from huggingface_hub import constants
print(constants.HF_HUB_CACHE)  # ~/Documents/.cache/huggingface/hub
```

To use a custom location:

```python
import os
os.environ["HF_HUB_CACHE"] = "/path/Documents/my-models"
# Set BEFORE importing huggingface_hub
import huggingface_hub
```

---

## Authentication

For downloads of public models, no token is needed.

For private / gated models OR uploads, you need a token:

```python
from huggingface_hub import HfFolder, login

# Interactive login (writes token to ~/Documents/.cache/huggingface/token)
login()                          # prompts for token

# Or set explicitly (e.g. from your app's keychain)
HfFolder.save_token("hf_xxxxxx")

# All subsequent calls use it
hf_hub_download("private/model", "config.json")  # works now
```

---

## API surface

| Function | What it does |
|---|---|
| `hf_hub_download(repo_id, filename, ...)` | Single-file download with caching |
| `snapshot_download(repo_id, local_dir=None, ...)` | Whole-repo download |
| `HfApi().list_repo_files(repo_id)` | List files without downloading |
| `HfApi().model_info(repo_id)` | Repo metadata (tags, siblings, downloads, …) |
| `HfApi().dataset_info(repo_id)` | Same for datasets |
| `HfApi().space_info(repo_id)` | Same for Spaces |
| `HfApi().list_models(filter=…)` | Search the Hub |
| `HfApi().upload_file(...)` / `upload_folder(...)` | Push to Hub (needs write token) |
| `create_repo(repo_id, ...)` / `delete_repo(...)` | Manage repos |
| `login()` / `HfFolder.save_token(...)` | Auth |
| `interpreter_login()` | Web-based OAuth flow (won't work on iOS — use save_token) |
| `cached_download(...)` | Deprecated, use hf_hub_download |

---

## Pairing with transformers

```python
from transformers import AutoTokenizer, AutoModel

# Both calls auto-route through huggingface_hub for downloads.
tok = AutoTokenizer.from_pretrained("distilbert-base-uncased")
model = AutoModel.from_pretrained("distilbert-base-uncased")

# First call downloads ~250MB; subsequent calls hit the cache.
```

The `from_pretrained(...)` cache is shared with `huggingface_hub`'s,
so manual `hf_hub_download` calls populate it too.

---

## Pre-loading models for offline use

For an app you want to ship with bundled models (no first-run
download), pre-fetch on a development machine and bundle the cache:

```python
# Run on Mac before building the app:
from huggingface_hub import snapshot_download
snapshot_download(
    "distilbert/distilbert-base-uncased",
    local_dir="./bundled_models/distilbert",
)
```

Then copy `bundled_models/distilbert/` into your iOS app's bundle and
point `HF_HUB_CACHE` at it on startup.

---

## Limitations

- **`interpreter_login()` (web OAuth flow) won't work** — opens
  `webbrowser`, which on iOS doesn't have a system handler. Use
  `HfFolder.save_token(token_str)` directly.
- **No `git` / `git-lfs` push** — uploads via `upload_file` use the
  HTTP API, not git. (Same as upstream when run without git installed.)
- **Symlink cache is disabled** — upstream uses symlinks for
  deduplication when multiple revisions of a model share files;
  iOS's sandbox is iffy with symlinks across paths, so the shim sets
  `HF_HUB_DISABLE_SYMLINKS_WARNING=1` and copies files instead. Costs
  some disk; safer.
- **`huggingface-cli` command-line tool** — not bundled. Use the
  Python API directly.

---

## Troubleshooting

### `ConnectionError: ('Connection aborted.', RemoteDisconnected(...))`

Cellular vs Wi-Fi switch mid-download. Use `hf_hub_download` (which
auto-retries with the etag-based resume) instead of streaming `requests`
directly.

### `OSError: Disk quota exceeded`

The `~/Documents/.cache/huggingface/hub/` directory grew large. Clean:
```python
from huggingface_hub import scan_cache_dir
report = scan_cache_dir()
print(report)                    # see what's there
report.delete_revisions(...).execute()    # delete by revision sha
```

### `LocalEntryNotFoundError`

The file isn't in the cache and `local_files_only=True` was set. Either
download first or set `local_files_only=False`.

### Slow first download on cellular

`huggingface_hub` resumes interrupted downloads via HTTP Range. If a
download keeps failing, try `etag_timeout=30` to give the metadata
fetch more headroom.
