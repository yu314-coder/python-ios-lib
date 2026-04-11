# pydub

> **Version:** 0.25.1 | **Type:** Stock (pure Python) | **Status:** Partial

Audio manipulation library for creating, editing, and converting audio.

---

## Quick Start

```python
from pydub import AudioSegment
from pydub.generators import Sine, WhiteNoise

tone = Sine(440).to_audio_segment(duration=1000)  # 440Hz for 1 second
tone.export("/tmp/tone.wav", format="wav")
```

---

## `AudioSegment` -- Core Class

### Creation

| Method | Description |
|--------|-------------|
| `AudioSegment.from_file(path, format)` | Load audio file |
| `AudioSegment.from_wav(path)` | Load WAV file |
| `AudioSegment.from_mp3(path)` | Load MP3 (needs ffmpeg) |
| `AudioSegment.from_raw(data, sample_width, frame_rate, channels)` | From raw PCM data |
| `AudioSegment.silent(duration, frame_rate)` | Generate silence (ms) |
| `AudioSegment.empty()` | Empty segment |

### Operations

| Operation | Description |
|-----------|-------------|
| `seg1 + seg2` | Concatenate audio |
| `seg * 3` | Repeat 3 times |
| `seg + 6` | Increase volume by 6 dB |
| `seg - 6` | Decrease volume by 6 dB |
| `seg.overlay(other, position, gain_during_overlay)` | Mix/overlay audio |
| `seg.append(other, crossfade)` | Append with optional crossfade |

### Effects

| Method | Description |
|--------|-------------|
| `seg.fade_in(duration_ms)` | Fade in |
| `seg.fade_out(duration_ms)` | Fade out |
| `seg.fade(from_gain, to_gain, start, end)` | Custom fade |
| `seg.reverse()` | Reverse audio |
| `seg.apply_gain(gain_dB)` | Apply gain |
| `seg.normalize(headroom)` | Normalize to max volume |
| `seg.compress_dynamic_range(threshold, ratio, attack, release)` | Dynamic range compression |
| `seg.low_pass_filter(cutoff)` | Low-pass filter |
| `seg.high_pass_filter(cutoff)` | High-pass filter |
| `seg.pan(pan_amount)` | Pan left (-1) to right (+1) |
| `seg.invert_phase()` | Invert phase |
| `seg.speedup(playback_speed)` | Speed up (changes pitch) |

### Slicing & Properties

| Method / Property | Description |
|-------------------|-------------|
| `seg[start_ms:end_ms]` | Slice by time in milliseconds |
| `seg.duration_seconds` | Duration in seconds |
| `len(seg)` | Duration in milliseconds |
| `seg.frame_rate` | Sample rate (Hz) |
| `seg.channels` | Number of channels |
| `seg.sample_width` | Bytes per sample |
| `seg.frame_count()` | Total number of frames |
| `seg.max` | Maximum amplitude |
| `seg.max_dBFS` | Max amplitude in dBFS |
| `seg.dBFS` | Average loudness in dBFS |
| `seg.rms` | RMS amplitude |
| `seg.raw_data` | Raw PCM bytes |

### Export

| Method | Description |
|--------|-------------|
| `seg.export(path, format, bitrate, parameters)` | Save audio file |
| `seg.set_frame_rate(rate)` | Change sample rate |
| `seg.set_channels(n)` | Convert mono/stereo |
| `seg.set_sample_width(width)` | Change bit depth |

---

## `pydub.generators` -- Audio Generators

| Class | Description |
|-------|-------------|
| `Sine(freq)` | Sine wave generator |
| `Square(freq)` | Square wave |
| `Sawtooth(freq)` | Sawtooth wave |
| `Triangle(freq)` | Triangle wave |
| `WhiteNoise()` | White noise |
| `Pulse(freq, duty_cycle)` | Pulse wave |

All generators support `.to_audio_segment(duration, volume)`.

---

## Limitations

- No ffmpeg subprocess on iOS (limited format support)
- WAV format works best; MP3/OGG encoding may not work
- No real-time playback API
