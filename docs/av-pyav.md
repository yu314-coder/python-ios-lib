# PyAV (av) — FFmpeg bindings

**Version:** 17.0.1 (`__version__ = "17.0.1pre"`)
**Type:** Native iOS arm64 Cython bindings to FFmpeg (17 `.so` files)
**SPM target:** `PyAV` (links libavcodec, libavformat, libavutil, libswresample, libswscale)
**Total submodules:** 50 Python + 17 compiled extensions

Python bindings around FFmpeg's libav* — open / inspect / decode / encode / mux audio + video + subtitle containers. Cross-compiled with a custom FFmpeg build for iOS arm64. Used by pydub, moviepy, image-processing pipelines, and any code that needs to touch a media container at the frame level.

---

## Modules

### Top-level

| Module | What it does |
|---|---|
| `av.__init__` | Re-exports: `open`, `Codec`, `CodecContext`, `Packet`, `AudioFrame`/`VideoFrame`, format/layout enums |
| `av._core` | Library bootstrap, `time_base`, `library_versions`, `ffmpeg_version_info` |
| `av.about` | `__version__` |
| `av.bitstream` | `BitStreamFilterContext`, `bitstream_filters_available` |
| `av.buffer` | Internal AVBuffer wrapper |
| `av.datasets` | Sample-media URLs (upstream test fixtures) |
| `av.descriptor` | AVOption descriptor (for codec / filter introspection) |
| `av.device` | `enumerate_input_devices` / `enumerate_output_devices` (iOS: empty — no AVFoundation device backend) |
| `av.dictionary` | AVDictionary wrapper (used everywhere for codec/format options) |
| `av.error` | Exception hierarchy: `FFmpegError`, `EOFError`, `InvalidDataError`, `PatchWelcomeError`, … |
| `av.format` | `ContainerFormat`, `formats_available` |
| `av.frame` | Base `Frame` class |
| `av.index` | Index-entry types (seek tables) |
| `av.logging` | FFmpeg `av_log_*` capture — wires libav's log into Python `logging` |
| `av.opaque` | Opaque-ref helpers |
| `av.option` | AVOption Python wrappers |
| `av.packet` | `Packet` (compressed frame container) |
| `av.plane` | Generic frame-plane base class |
| `av.stream` | `Stream` base class |
| `av.utils` | Shared helpers |

### `av.audio` — Audio streams + frames

| Submodule | Provides |
|---|---|
| `audio.codeccontext` | `AudioCodecContext` — encode/decode params, rate, channels, format |
| `audio.fifo` | `AudioFifo` — sample buffer queue (resampler input/output staging) |
| `audio.format` | `AudioFormat` — `s16`, `s16p`, `flt`, `fltp`, … |
| `audio.frame` | `AudioFrame` — `.to_ndarray()`, `.from_ndarray()`, `.samples`, `.layout` |
| `audio.layout` | `AudioLayout` — mono/stereo/5.1, named channel maps |
| `audio.plane` | `AudioPlane` (interleaved or planar sample buffer) |
| `audio.resampler` | `AudioResampler` — wraps libswresample (rate / format / channel-layout conversion) |
| `audio.stream` | `AudioStream` |

### `av.video` — Video streams + frames

| Submodule | Provides |
|---|---|
| `video.codeccontext` | `VideoCodecContext` — encode/decode params, pix_fmt, gop_size, bit_rate |
| `video.format` | `VideoFormat` — `yuv420p`, `nv12`, `rgb24`, `rgba`, … |
| `video.frame` | `VideoFrame` — `.to_image()` → PIL, `.to_ndarray()`, `.from_image()`, `.from_ndarray()` |
| `video.plane` | `VideoPlane` (per-plane buffer view) |
| `video.reformatter` | `VideoReformatter` — libswscale wrapper (color / scale / pix-fmt conversion) |
| `video.stream` | `VideoStream` |

### `av.container`

| Submodule | Provides |
|---|---|
| `container.core` | `Container` base (opened via `av.open()`) |
| `container.input` | `InputContainer` — `.decode()`, `.demux()`, `.seek()` |
| `container.output` | `OutputContainer` — `.add_stream()`, `.mux()`, `.close()` |
| `container.pyio` | Python file-like → AVIO bridge (read from BytesIO, write to in-memory buffer) |
| `container.streams` | `StreamContainer` — `.video`, `.audio`, `.subtitles` accessors |

### `av.codec`

| Submodule | Provides |
|---|---|
| `codec.codec` | `Codec` (descriptor) + `codecs_available` set |
| `codec.context` | `CodecContext` (the universal encode/decode object) |
| `codec.hwaccel` | Hardware-accel descriptor — **iOS: returns empty list** (no `videotoolbox` exposed via this API; encode is wired via `h264_videotoolbox` codec name directly) |

### `av.filter`

| Submodule | Provides |
|---|---|
| `filter.filter` | `Filter` descriptor + `filters_available` |
| `filter.graph` | `Graph` — build a filter pipeline (e.g., `scale=640:360,format=yuv420p`) |
| `filter.context` | `FilterContext` (per-node) |
| `filter.link` | Filter graph edges |
| `filter.loudnorm` | EBU R128 loudness normalization (custom bundled — `loudnorm_impl.c`) |

### `av.sidedata`

| Submodule | Provides |
|---|---|
| `sidedata.sidedata` | `SideData` base — AV_FRAME_DATA_* parsers |
| `sidedata.motionvectors` | Motion-vector side-data accessor (for codec analysis) |
| `sidedata.encparams` | Encoding-parameters side data |

### `av.subtitles`

| Submodule | Provides |
|---|---|
| `subtitles.codeccontext` | `SubtitleCodecContext` |
| `subtitles.stream` | `SubtitleStream` |
| `subtitles.subtitle` | `Subtitle`, `SubtitleRect`, `BitmapSubtitle`, `AssSubtitle`, `TextSubtitle` |

---

## Quick start

```python
import av

# Inspect a media container
container = av.open('/path/Documents/video.mp4')
for s in container.streams:
    print(f"{s.type}: {s.codec_context.name} {s.codec_context.width}x{s.codec_context.height}"
          if s.type == "video"
          else f"{s.type}: {s.codec_context.name} {s.codec_context.sample_rate}Hz")

# Decode video frames to PIL Images
for frame in container.decode(video=0):
    img = frame.to_image()        # PIL.Image
    arr = frame.to_ndarray(format="rgb24")   # numpy HxWx3 uint8
    break

# Decode audio to numpy
for frame in container.decode(audio=0):
    samples = frame.to_ndarray()   # shape: (channels, samples)
    break

container.close()
```

```python
# Encode a sequence of numpy frames to MP4 via VideoToolbox
import av, numpy as np

out = av.open('/path/Documents/out.mp4', mode='w')
stream = out.add_stream('h264_videotoolbox', rate=30)   # iOS HW encoder
stream.width = 640
stream.height = 480
stream.pix_fmt = 'yuv420p'

for i in range(60):
    img = np.random.randint(0, 256, (480, 640, 3), dtype=np.uint8)
    frame = av.VideoFrame.from_ndarray(img, format='rgb24')
    for packet in stream.encode(frame):
        out.mux(packet)

for packet in stream.encode():   # flush
    out.mux(packet)
out.close()
```

---

## iOS notes

### FFmpeg build

The bundled libav* is a **custom GPL-free FFmpeg build** cross-compiled
for `arm64-apple-ios17.0`. Native libraries are linked statically into
the SPM `PyAV` target. The 17 `.so` files in `av/` are thin Cython
wrappers (~2-12 MB each).

`av._core.library_versions` returns the linked FFmpeg version tuple
at runtime; `av._core.ffmpeg_version_info` is the human-readable
string (`"FFmpeg 7.x (offlinai-ios)"`).

### Codec availability

| Codec | Decode | Encode | Notes |
|---|---|---|---|
| H.264 | yes (`h264`) | yes (`h264_videotoolbox`) | HW encoder via Apple VideoToolbox; `libx264` NOT bundled (GPL) |
| H.265 / HEVC | yes (`hevc`) | yes (`hevc_videotoolbox`) | HW encoder |
| AV1 | yes (`av1`, libdav1d) | no | Decode-only |
| VP8 / VP9 | yes (`vp8`, `vp9`) | software | libvpx not bundled — encode falls back to internal |
| MPEG-4 | yes | yes (`mpeg4` software) | Always-available software fallback for encode |
| AAC | yes | yes | Both directions |
| Opus | yes | yes (libopus bundled) | |
| MP3 | yes | no | libmp3lame not bundled (license) |
| FLAC, ALAC, PCM | yes | yes | |

`av.codecs_available` returns the live list at runtime — call it on
device for the authoritative set.

### Hardware acceleration

iOS HW encoders (`h264_videotoolbox`, `hevc_videotoolbox`) work for
**encoding** only. HW decoders aren't exposed through PyAV's hwaccel
API on iOS — decode is done in software. For most decode workloads
(< 1080p30) the CPU keeps up; 4K decode is slow.

manim uses `h264_videotoolbox` automatically on iOS — see
[manim.md](manim.md). Override with
`OFFLINAI_MANIM_SOFTWARE_ENCODER=1` to force `mpeg4` software encoding
(more deterministic memory profile for long scenes).

### Devices

`av.enumerate_input_devices()` / `enumerate_output_devices()` return
empty on iOS — PyAV's device backends (`avfoundation`, `v4l2`, `dshow`)
aren't compiled in. For live camera capture, use Swift's AVFoundation
+ bridge frames into Python via numpy.

### Pickling / threading

- `av.VideoFrame` and `av.Packet` are not pickleable across processes
  — but iOS has no multiprocessing anyway.
- Encode/decode releases the GIL during the FFmpeg call. Safe to use
  from a Python thread; the host app's UI stays responsive.

---

## Limitations

- **No libx264, libx265, libmp3lame** — GPL/license issues with iOS
  App Store distribution. Use `*_videotoolbox` for H.264/HEVC encode;
  use AAC/Opus for audio encode.
- **No streaming protocols beyond `file://` and `http(s)://`** —
  RTMP, RTSP, SRT not enabled in the iOS FFmpeg build.
- **`av.open(file_like)`** works via the `pyio` bridge but has higher
  overhead than a real path. Prefer disk paths.
- **No subprocess fallback for codecs** — the ffmpeg CLI isn't on iOS.
  Everything goes through libav* directly.
