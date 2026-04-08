# pydub

> **Version:** 0.25.1 | **Type:** Stock (pure Python) | **Status:** Partial

Audio manipulation library.

---

## Usage

```python
from pydub import AudioSegment
from pydub.generators import Sine, WhiteNoise

# Generate tone
tone = Sine(440).to_audio_segment(duration=1000)  # 440Hz for 1 second
tone.export("/tmp/tone.wav", format="wav")

# Mix audio
silence = AudioSegment.silent(duration=500)
combined = tone + silence + tone
combined.export("/tmp/beeps.wav", format="wav")

# Adjust volume
louder = tone + 6   # +6 dB
quieter = tone - 6  # -6 dB
```

## Key Functions

| Function | Description |
|----------|-------------|
| `AudioSegment.from_file(path)` | Load audio file |
| `AudioSegment.silent(duration)` | Generate silence |
| `segment.export(path, format)` | Save audio |
| `segment + segment` | Concatenate |
| `segment.overlay(other)` | Mix/overlay |
| `segment.fade_in(ms)` / `fade_out(ms)` | Fade effects |
| `segment + 6` / `segment - 6` | Volume adjust (dB) |

## Limitations

- No ffmpeg subprocess on iOS (limited format support)
- WAV format works best
- No real-time playback API
