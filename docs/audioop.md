# audioop — PCM audio operations (audioop-lts backport)

**Version:** 0.2.1 (PyPI: `audioop-lts`)
**Type:** Native iOS arm64 C extension (`_audioop.abi3.so`)
**SPM target:** Bundled into the Python framework
**Total modules:** 1 Python + 1 compiled extension

Backport of the standard library's `audioop` module, which was
**removed from Python 3.13**. Provides primitive operations on raw
audio sample buffers (PCM bytes): mixing, gain control, format
conversion, RMS / max calculation, μ-law / A-law / IMA ADPCM codecs.

iOS Python is 3.14, so the stdlib version is gone. `pydub` and a few
other packages depend on this backport.

---

## Modules

| Module | What it does |
|---|---|
| `audioop.__init__` | Re-exports the full PCM API from `_audioop` |
| `audioop._audioop` (compiled `.abi3.so`) | The C implementation — verbatim port of CPython 3.12's `Modules/audioop.c` |
| `audioop.__init__.pyi` | Type stubs |

Direct use cases:
- Working with raw PCM audio outside of `pydub` / PyAV
- Implementing a custom audio processing pipeline
- Reading older code that called `audioop.ratecv` or `audioop.lin2lin`

For most use cases, prefer the higher-level `pydub` API.

---

## Quick start

```python
import audioop

# Read raw 16-bit mono PCM from a WAV file's data chunk
with open("/path/Documents/clip.wav", "rb") as f:
    f.seek(44)               # skip the WAV header (assumes standard 44-byte header)
    pcm = f.read()

# Sample width = 2 bytes (16-bit), channels = 1 (mono)

# Compute RMS (loudness)
rms = audioop.rms(pcm, 2)
print(f"RMS: {rms}")

# Find the peak sample
peak = audioop.max(pcm, 2)
print(f"Peak: {peak}  (full-scale 16-bit = 32767)")

# Apply 6 dB gain (multiply by 2)
loud = audioop.mul(pcm, 2, 2.0)

# Resample 44100 Hz → 22050 Hz (1:2 decimation)
resampled, state = audioop.ratecv(pcm, 2, 1, 44100, 22050, None)
```

---

## API surface

1:1 reimplementation of the stdlib API removed in Python 3.13.

| Function | Purpose |
|---|---|
| `add(b1, b2, width)` | Element-wise add two PCM buffers (saturation clamp) |
| `mul(b, width, factor)` | Multiply each sample by `factor` (gain) |
| `bias(b, width, bias)` | Add a constant to every sample (DC offset) |
| `reverse(b, width)` | Reverse the byte order of samples (audio time-reverse) |
| `byteswap(b, width)` | Endian swap |
| `tomono(b, width, lf, rf)` | Mix stereo → mono with per-channel gain |
| `tostereo(b, width, lf, rf)` | Mono → stereo (split with per-channel gain) |
| `cross(b, width)` | Count zero crossings (rough pitch / activity detect) |
| `findfit(b, ref)` | Find the offset where `ref` best matches `b` |
| `findfactor(b, ref)` | Best linear factor for matching |
| `findmax(b, len)` | Find the time offset of the loudest section |
| `getsample(b, width, i)` | Read sample `i` |
| `lin2lin(b, width, newwidth)` | Convert sample width (8↔16↔24↔32 bit) |
| `lin2ulaw(b, width)` / `ulaw2lin(b, width)` | μ-law codec |
| `lin2alaw(b, width)` / `alaw2lin(b, width)` | A-law codec |
| `lin2adpcm(b, width, state)` / `adpcm2lin(b, width, state)` | IMA ADPCM codec |
| `max(b, width)` | Largest absolute sample value |
| `maxpp(b, width)` | Largest peak-to-peak sample value |
| `minmax(b, width)` | `(min_sample, max_sample)` tuple |
| `avg(b, width)` | Average sample value |
| `avgpp(b, width)` | Average peak-to-peak |
| `rms(b, width)` | Root-mean-square loudness |
| `ratecv(b, width, nchannels, inrate, outrate, state, weightA=1, weightB=0)` | Sample-rate conversion |
| `error` | Exception type raised for invalid widths / states |

**Conventions**
- `width` is bytes per sample: 1 (8-bit), 2 (16-bit), 3 (24-bit), 4 (32-bit).
- `state` for stateful ops (`ratecv`, `*adpcm*`) is `None` on the first call and the returned state on subsequent calls.
- All sample arithmetic is signed integer with saturation clamping.

---

## Why this is shipped

Python 3.13 removed `audioop` from the standard library, citing low
maintenance interest and few in-tree users. iOS Python is 3.14, so
the stdlib version is gone. But:

- **`pydub` depends on `audioop`** — it uses it for raw PCM
  manipulation. Without this backport, `import pydub` fails with
  `ModuleNotFoundError: audioop` on Python 3.13+.
- **`speech_recognition`** (if a user pip-installs it) depends on it.
- **WAV inspection / generation** — anyone who wrote a pre-3.13 audio
  script likely calls audioop functions directly.

The backport (`audioop-lts`) is a literal extraction of the stdlib C
code into a standalone PyPI wheel.

---

## When to use audioop vs higher-level libs

| Need | Use |
|---|---|
| Trim / fade / mix MP3 / WAV / M4A files | `pydub` (uses audioop under the hood) |
| Encode / decode codecs (AAC, Opus, WebM) | `av` (PyAV) |
| Real-time effects (EQ, compression, reverb) | Apple's AudioUnit via Swift (not available from Python) |
| Raw PCM math (gain, mix, resample, bit depth) | **audioop** directly |
| Generate sine waves / tones | `numpy` + `wave` (stdlib) — see example below |

---

## Example — generate + save a 440 Hz tone

```python
import audioop
import wave
import math
import struct

SAMPLE_RATE = 44100
DURATION_S = 2.0
FREQ_HZ = 440.0
n = int(SAMPLE_RATE * DURATION_S)

# Synthesize 16-bit PCM samples
samples = bytearray()
for i in range(n):
    t = i / SAMPLE_RATE
    s = int(32767 * 0.5 * math.sin(2 * math.pi * FREQ_HZ * t))
    samples += struct.pack("<h", s)
pcm = bytes(samples)

# Apply -6 dB attenuation via audioop
quieter = audioop.mul(pcm, 2, 0.5)

# Save as WAV
with wave.open("/path/Documents/tone.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SAMPLE_RATE)
    w.writeframes(quieter)
```

---

## iOS notes

Cross-compiled for `arm64-apple-ios17.0`. Single C extension —
`_audioop.abi3.so` (stable ABI3, works across Python 3.x versions).
No external library dependencies; the C source is self-contained.

Dist-info advertises it as `audioop-lts` so `pip install audioop-lts`
reports already-satisfied.

The compiled extension uses CPython's stable ABI, so it survives
Python minor-version upgrades (3.13 → 3.14 → 3.15) without rebuild.

---

## Limitations

- **Single-threaded C extension** — fine for typical buffer sizes
  (< 10 MB), saturates a single core for big batches. Releases the
  GIL during the heavy loops.
- **No floating-point sample support** — fixed-point only (PCM 8 / 16
  / 24 / 32 bit signed integers). For float PCM, convert manually:
  ```python
  import numpy as np
  fpcm = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
  ```
- **`ratecv`'s quality is "okay, not great"** — for high-quality
  resampling, use `scipy.signal.resample_poly` (bundled, slower) or
  `librosa` (not bundled).
- **No multichannel beyond stereo** — `tomono`/`tostereo` assume 2-channel
  layouts. For 5.1/7.1, manage channel maps in numpy directly.

---

## Build provenance

audioop-lts 0.2.1 — single C extension `_audioop.abi3.so`,
cross-compiled for `arm64-apple-ios17.0`. The dist-info package name
is `audioop-lts` (matches PyPI), so pip resolution is satisfied.
