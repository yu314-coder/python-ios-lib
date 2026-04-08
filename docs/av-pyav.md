# PyAV (av)

> **Version:** 17.0.1pre | **Type:** Cross-compiled for iOS arm64 | **Status:** Partial

Python bindings for FFmpeg. Cross-compiled with custom ffmpeg build for iOS.

---

## Usage

```python
import av

# Inspect video/audio file
container = av.open('/path/to/video.mp4')
for stream in container.streams:
    print(f"Stream: {stream.type}, codec: {stream.codec_context.name}")

# Decode frames
for frame in container.decode(video=0):
    img = frame.to_image()  # PIL Image
    break  # first frame only
```

## Key Classes

| Class | Description |
|-------|-------------|
| `av.open(path)` | Open media container |
| `container.streams` | Access audio/video streams |
| `container.decode(video=0)` | Decode video frames |
| `container.decode(audio=0)` | Decode audio frames |
| `frame.to_image()` | Convert video frame to PIL Image |
| `frame.to_ndarray()` | Convert to numpy array |

## Limitations

- No hardware-accelerated decoding on iOS
- Encoding support limited
- Some codecs may be missing from the iOS ffmpeg build
