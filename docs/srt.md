# srt — SubRip subtitle parsing / generation

**Version:** 3.5.3
**Type:** Pure Python (single file: `srt.py`)
**SPM target:** Bundled in `Manim` (no standalone target)
**Auto-included by:** Manim (`manim/scene/scene.py` imports it)
**Total Python modules:** 1

A small, no-dependency parser and composer for the `.srt` (SubRip)
subtitle format. Manim renders subtitles for its voiceover/captions
features, and you can use `srt` directly to mux subtitle tracks
alongside video output.

## Module

Single file at `app_packages/site-packages/srt.py` (~510 lines). Public
API:

| Symbol | Kind | What it does |
|---|---|---|
| `Subtitle(index, start, end, content, proprietary='')` | class | One subtitle cue. `start`/`end` are `datetime.timedelta` |
| `parse(data, ignore_errors=False)` | generator | Yields `Subtitle` objects from a string, bytes, or file-like containing an `.srt` document |
| `compose(subtitles, reindex=True, start_index=1, strict=True, eol='\n', in_place=False)` | function | Serialize an iterable of `Subtitle` back to `.srt` text |
| `sort_and_reindex(subtitles, start_index=1, in_place=False, skip=True)` | function | Sort by start time, renumber cues sequentially |
| `make_legal_content(content)` | function | Strip illegal characters (consecutive blank lines, indices that could confuse parsers) |
| `timedelta_to_srt_timestamp(td)` | function | `00:01:23,456` formatting |
| `srt_timestamp_to_timedelta(ts)` | function | Inverse |
| `SRTParseError` | exception | Raised by `parse()` on malformed input |
| `TimestampParseError` | exception | Raised on bad timestamp strings |

## iOS-specific patches

None — pure Python, stdlib-only (uses `re`, `datetime.timedelta`,
`functools`, `logging`, `io`). Works on iOS as-is.

## Standalone example

```python
import srt
from datetime import timedelta

# Build cues
subs = [
    srt.Subtitle(
        index=1,
        start=timedelta(seconds=0),
        end=timedelta(seconds=2, milliseconds=500),
        content="Hello, world!",
    ),
    srt.Subtitle(
        index=2,
        start=timedelta(seconds=3),
        end=timedelta(seconds=5),
        content="Running on iPhone",
    ),
]

# Serialize to .srt
text = srt.compose(subs)
print(text)
# 1
# 00:00:00,000 --> 00:00:02,500
# Hello, world!
#
# 2
# 00:00:03,000 --> 00:00:05,000
# Running on iPhone

# Parse it back
for sub in srt.parse(text):
    print(f"#{sub.index}  {sub.start} → {sub.end}: {sub.content}")
```

Combined with PyAV, you can mux subtitles into an MP4 alongside a
manim-rendered video.

## See also

- [docs/manim.md](manim.md) — primary consumer
- [docs/av-pyav.md](av-pyav.md) — for muxing `.srt` into containers
