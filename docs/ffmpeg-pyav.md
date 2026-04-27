# FFmpegPyAV

> **Versions:** FFmpeg 6.1 / 7.x + PyAV 17.0.1pre  | **Type:** Native iOS arm64 build (FFmpeg static + PyAV cython)  | **Status:** Decode + encode, no hardware accel beyond VideoToolbox H.264

Native FFmpeg cross-compiled for `arm64-apple-ios` with the PyAV
Python bindings on top. Used by `manim` to encode rendered scenes
into MP4 / WebM, and available standalone for any user code that
needs video / audio / image-sequence I/O.

```
   manim ──┐         ┌── av (PyAV — Python API)
           │         │
           ▼         ▼
       FFmpegPyAV  ◄── this package
       │  libav* static archives
       │  + libavcodec / libavformat / libavfilter / libswscale / libswresample
       │  + Apple's VideoToolbox (H.264 hardware encode)
       │  + Apple's AudioToolbox (AAC encode)
```

---

## When to add this target

Two main reasons:

1. You depend on `Manim` — SPM resolves `FFmpegPyAV` as a transitive
   dependency automatically; you don't need to add it yourself.
2. You want raw `import av` from Python — for example to:
   - Decode webcam captures, screen recordings, or downloaded videos
   - Re-encode user uploads into a target format
   - Mux audio + video tracks together
   - Probe codec / container metadata

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "FFmpegPyAV", package: "python-ios-lib"),
])
```

---

## What's bundled

| Folder | Contents |
|---|---|
| `ffmpeg/` | The FFmpeg static-library install tree (headers + `.a` archives) |
| `av/` | The PyAV Python package — Cython-compiled `.so` extensions plus pure-Python wrappers |

PyAV's `_core.cpython-314-iphoneos.so` is the main extension; it
links against the FFmpeg archives at build time. Inside the `.so`
it's a self-contained codec / container / filter implementation —
no external `ffmpeg` CLI needed (which is good, because iOS can't
spawn it anyway).

### Codecs included

**Video decode**: H.264, H.265, VP8, VP9, AV1, MPEG-4, MJPEG, GIF,
WebP, ProRes (some profiles), DNxHD, and ~30 less-common ones.

**Video encode**: H.264 (via x264 + VideoToolbox), MPEG-4, MJPEG,
ProRes, GIF, WebP. **VP8/VP9/AV1 encode** are NOT compiled in (the
encoders are heavy and slow without hw accel; skip if you don't
need them).

**Audio decode**: AAC, MP3, Opus, FLAC, Vorbis, PCM (all variants),
WMA v1/v2.

**Audio encode**: AAC (via Apple's AudioToolbox bridge), MP3 (via
LAME if linked — verify with `av.codecs_available`), Opus, FLAC,
PCM.

**Containers**: MP4, MOV, M4V, MKV, WebM, AVI, MPEG-TS, FLV, GIF,
PNG, image2 (sequence).

### What's NOT included
- **NVENC / NVDEC / CUDA** — not on iOS
- **VAAPI / QSV** — Linux-only acceleration
- **librtmp** — RTMP streaming server
- **libfdk-aac** — non-free, can't redistribute
- **libdav1d as separate dylib** — AV1 decode is via FFmpeg's
  internal decoder (slower than dav1d on big frames; fine for
  typical app use)

---

## Python usage — basics

```python
import av

# Probe a file
container = av.open("/path/in/Documents/video.mp4")
print(f"format:    {container.format.name}")
print(f"duration:  {container.duration / 1_000_000:.1f}s")
for stream in container.streams:
    print(f"stream {stream.index}: {stream.type}  codec={stream.codec_context.name}")
container.close()
```

```python
# Decode + extract first 5 frames as PIL Images
import av
container = av.open("/path/video.mp4")
frames = []
for i, frame in enumerate(container.decode(video=0)):
    frames.append(frame.to_image())   # → PIL.Image
    if i == 4: break
container.close()

# Save them
for i, img in enumerate(frames):
    img.save(f"/path/Documents/frame_{i:03d}.png")
```

```python
# Decode to numpy array (faster than to_image for downstream NumPy work)
import av, numpy as np
container = av.open("/path/video.mp4")
frame = next(container.decode(video=0))
arr = frame.to_ndarray(format="rgb24")    # (H, W, 3) uint8
print(arr.shape, arr.dtype)
container.close()
```

---

## Python usage — encoding

```python
import av
import numpy as np

# Encode a numpy stack into an MP4
output = av.open("/path/Documents/out.mp4", mode="w")
stream = output.add_stream("h264", rate=30)
stream.width = 640
stream.height = 360
stream.pix_fmt = "yuv420p"

for t in range(120):                              # 4 s @ 30 fps
    frame_arr = np.random.randint(0, 255, (360, 640, 3), dtype=np.uint8)
    frame = av.VideoFrame.from_ndarray(frame_arr, format="rgb24")
    for packet in stream.encode(frame):
        output.mux(packet)

# Flush encoder
for packet in stream.encode():
    output.mux(packet)
output.close()
```

```python
# H.264 via VideoToolbox (hardware-accelerated)
import av
output = av.open("/path/Documents/hwaccel.mp4", mode="w")
stream = output.add_stream("h264_videotoolbox", rate=30)
stream.options = {"realtime": "1"}                # for live capture
stream.width = 1280
stream.height = 720
# ... add frames as above
```

Hardware-accelerated H.264 encode via Apple's VideoToolbox is
significantly faster than software x264 — typically 5-10× on the
A17 Pro / M-series, and uses far less battery. Recommended for
anything ≥720p.

---

## manim integration

manim's `SceneFileWriter` uses PyAV under the hood for video output.
The iOS-patched build:

- Defaults to `h264_videotoolbox` codec
- Sets `realtime=1` so frames flush quickly (avoids OOM on long renders)
- Bounds the encoder's frame queue to 32 (the default unbounded queue
  blew the 8 GB jetsam limit for long manim scenes)
- Uses 720p @ 30 fps as the default low-quality preset (`-ql`)

If you want different defaults, set `manim.config.codec`,
`manim.config.frame_rate`, etc. at the top of your script.

---

## Limitations

- **No hardware-accelerated DECODE.** Apple's VideoToolbox decoder
  isn't wired into FFmpeg's `h264_videotoolbox` decoder path in
  this build; decode goes through libavcodec's software H.264
  decoder. That's fine for typical sizes (up to 1080p @ 30 fps
  on an A17 Pro is real-time) but heavier than encode.
- **No `subprocess.run('ffmpeg', ...)`.** iOS sandbox blocks
  `fork/exec`; you cannot invoke an external ffmpeg binary. All
  work has to go through `import av`.
- **No live network protocols.** RTSP / RTMP / HLS aren't compiled
  in. For HTTP(S) streaming, decode the file URL directly (FFmpeg's
  HTTP demuxer works, but you'll be downloading the whole thing
  before seek works well).
- **Color management.** No ICC profile pipeline; FFmpeg's pixfmt
  conversion is the only color path. For app-specific color
  pipelines (HDR / wide gamut), composite at higher levels.
- **MP3 encoding** — depends on LAME being statically linked at
  build time. Check at runtime with:
  ```python
  import av
  print('mp3' in av.codecs_available)
  ```

---

## Troubleshooting

### `OSError: Could not find FFmpeg shared library`

PyAV is looking for a dylib that doesn't exist in our build (we use
static linking). The Python wrapper has a workaround: `av._core` is
the compiled extension that bakes FFmpeg in directly. If you see
this error, you're probably importing `av` from a non-bundled path —
check `import av; print(av.__file__)` resolves under
`Bundle.main.bundlePath/.../app_packages/site-packages/av/`.

### Encoding hangs with no output frames

Encoder is buffering. Always flush at the end:
```python
for packet in stream.encode():       # no argument = flush
    output.mux(packet)
```

### `ValueError: invalid pixel format 'rgb24'` when adding stream

The codec doesn't accept `rgb24` directly — it wants YUV. Set
`stream.pix_fmt = "yuv420p"` (which the encoder accepts) and PyAV
auto-converts via swscale.

### Memory grows unbounded during encoding

For VideoFrames you've stopped using, explicitly `del frame` or
let the loop scope reclaim them. PyAV holds frame buffers until
the next `encode(frame)` call — large frame queues balloon
quickly at high resolution. Consider:
```python
encoder_queue_max = 32   # manim default
```

### `Mach-O has bad magic` at link time

You're linking against an arm64 archive on an x86_64 simulator (or
vice versa). The bundled archives are arm64-only — develop / test
on a real device or the arm64 simulator (Designed-for-iPad on
Apple Silicon Macs).

---

## Build provenance

- FFmpeg 6.1.x base, with selective patches from main for AV1
  decode improvements
- Configured with:
  ```
  ./configure --target-os=ios --arch=arm64 --cc='clang -arch arm64'
              --enable-static --disable-shared --disable-programs
              --disable-debug --enable-pic --enable-cross-compile
              --enable-videotoolbox --disable-network --disable-iconv
              --enable-gpl --enable-libx264 --enable-libfreetype
  ```
- PyAV built with `cibuildwheel`-style hooks targeting iOS Python 3.14
- Python extension `.so` files renamed / signed by the host app's
  Install Python build phase
