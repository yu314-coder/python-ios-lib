# pydub — audio manipulation

**Version:** 0.25.1  
**Type:** Pure Python  
**SPM target:** `Pydub`  
**Total Python modules:** 11

High-level audio editing — load WAV/MP3, slice, concatenate, mix, fade, normalize, filter, export. All operations go through `AudioSegment`. Internally pydub shells out to `ffmpeg` for non-WAV formats; on iOS we don't have a `ffmpeg` subprocess, so WAV is the only first-class format. Use `pyav` directly for MP3/AAC/OGG.

## Modules

| Module | What it does |
|---|---|
| `pydub.__init__` | Re-exports `AudioSegment` (the only name 95% of users need) |
| `pydub.audio_segment` | `AudioSegment` — the core immutable audio buffer. Construction (`from_file`, `from_wav`, `from_mp3`, `from_raw`, `silent`, `empty`), arithmetic (`+`/`*`/`-`), slicing (`seg[ms:ms]`), property accessors (`duration_seconds`, `frame_rate`, `channels`, `sample_width`, `rms`, `dBFS`, `max`, `max_dBFS`, `raw_data`), conversion (`set_frame_rate`, `set_channels`, `set_sample_width`), export, overlay, append, crossfade |
| `pydub.generators` | Synthesizers: `Sine`, `Square`, `Sawtooth`, `Triangle`, `Pulse`, `WhiteNoise`. All inherit from `SignalGenerator` and have `.to_audio_segment(duration_ms, volume=0)` |
| `pydub.effects` | Free-function effects: `normalize`, `speedup` (preserves pitch by chunking), `strip_silence`, `compress_dynamic_range`, `invert_phase`, `low_pass_filter`, `high_pass_filter`, `pan`, `apply_gain_stereo`, `apply_mono_filter_to_each_channel`. Also bound on `AudioSegment` as methods via `register_pydub_effect` |
| `pydub.scipy_effects` | Higher-quality `band_pass_filter`, `low_pass_filter`, `high_pass_filter`, `eq` using `scipy.signal` IIR — auto-registered onto `AudioSegment` if scipy is importable |
| `pydub.silence` | Silence detection + splitting: `detect_silence`, `detect_nonsilent`, `split_on_silence`, `detect_leading_silence` |
| `pydub.playback` | `play(segment)` — tries simpleaudio → pyaudio → `ffplay`. **All three are unavailable on iOS** — see notes |
| `pydub.utils` | `db_to_float`, `ratio_to_db`, `make_chunks`, `which` (PATH lookup), `mediainfo` / `mediainfo_json` (ffprobe wrappers), encoder/decoder discovery, codec caching, `register_pydub_effect` decorator |
| `pydub.exceptions` | `PydubException`, `TooManyMissingFrames`, `InvalidDuration`, `InvalidID3TagVersion`, `InvalidTag`, `CouldntDecodeError`, `CouldntEncodeError`, `MissingAudioParameter` |
| `pydub.pyaudioop` | Pure-Python reimplementation of stdlib `audioop` — used as a fallback when the C ext isn't available (Python 3.13+). On iOS this is the active backend |
| `pydub.logging_utils` | `log_conversion`, `log_subprocess_output` — wire pydub's subprocess calls into `logging` |

## iOS notes

- **No `ffmpeg` subprocess.** `AudioSegment.from_mp3(...)`, `.from_ogg(...)`, `.export(format="mp3")`, etc. all shell out to `ffmpeg`/`ffprobe` — both unavailable. WAV-only is the reality.
  - For non-WAV decode: use `av` (PyAV / FFmpeg-as-library) directly to read frames into a numpy array, then `AudioSegment(data=arr.tobytes(), sample_width=2, frame_rate=44100, channels=2)`.
  - For non-WAV encode: same — write WAV via pydub, transcode with `av`.
- **No playback.** `pydub.playback.play(seg)` will fail — simpleaudio/pyaudio aren't built, and `ffplay` isn't on PATH. Export to a temp WAV and play with `AVAudioPlayer` from Swift, or use the host app's audio infrastructure.
- **`audioop` shim is active.** Python 3.13 removed the stdlib `audioop` C module. pydub auto-detects this and uses `pydub.pyaudioop` (pure Python) — slower for very long files but correct.
- **scipy effects work** if scipy is imported first — they're registered as methods on `AudioSegment` at import time.

## Example

```python
from pydub import AudioSegment
from pydub.generators import Sine, WhiteNoise
from pydub.silence import split_on_silence

# 1. Synth a chord
a4   = Sine(440).to_audio_segment(duration=1000, volume=-6)
cs5  = Sine(554.37).to_audio_segment(duration=1000, volume=-6)
e5   = Sine(659.25).to_audio_segment(duration=1000, volume=-6)
chord = a4.overlay(cs5).overlay(e5)
chord.export("/tmp/A-major.wav", format="wav")

# 2. Load + edit a recording (must be WAV on iOS)
voice = AudioSegment.from_wav("/tmp/recording.wav")
voice = voice.normalize()                       # peak to -0.1 dBFS
voice = voice.fade_in(200).fade_out(500)
voice = voice.low_pass_filter(8000)             # remove hiss
voice = voice + 3                               # +3 dB
voice[5000:10000].export("/tmp/clip.wav", format="wav")  # 5-10 s

# 3. Split by silence
chunks = split_on_silence(voice, min_silence_len=500, silence_thresh=voice.dBFS - 16)
for i, ch in enumerate(chunks):
    ch.export(f"/tmp/segment_{i}.wav", format="wav")
```
