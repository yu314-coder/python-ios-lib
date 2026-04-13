# Media & Rendering

Video encoding, 2D vector graphics, image processing, and LaTeX typesetting — all running natively on iOS.

---

## PyAV — FFmpeg Python Bindings

**Native iOS build** | Python 3.14 arm64 | 17 C extension modules

PyAV provides Pythonic access to FFmpeg's libav* libraries for reading, writing, and manipulating audio/video.

### C Extension Modules

| Module | Size | Description |
|--------|------|-------------|
| `_core` | 78 KB | Core initialization and library management |
| `bitstream` | 97 KB | Bitstream filtering |
| `buffer` | 104 KB | Memory buffer management |
| `descriptor` | 93 KB | Stream descriptor access |
| `device` | — | Device enumeration (input/output) |
| `dictionary` | — | FFmpeg option dictionaries |
| `error` | 220 KB | Error handling and exception mapping |
| `format` | — | Container format enumeration |
| `frame` | — | Base frame class |
| `index` | — | Indexing support |
| `logging` | 145 KB | FFmpeg log capture |
| `opaque` | — | Opaque data types |
| `option` | — | Codec/format options |
| `packet` | 177 KB | Packet encoding/decoding |
| `plane` | — | Frame plane data access |
| `stream` | 126 KB | Stream management |
| `utils` | — | Utility functions |

### Container API

```python
import av

# Write video
container = av.open('output.mp4', mode='w')
stream = container.add_stream('h264_videotoolbox', rate=30)
stream.width = 1280
stream.height = 720
# ... encode frames ...
container.close()

# Read video
container = av.open('input.mp4')
for frame in container.decode(video=0):
    img = frame.to_ndarray(format='rgb24')
```

| Function / Class | Description |
|------------------|-------------|
| `av.open(path, mode)` | Open container for reading (`'r'`) or writing (`'w'`) |
| `container.add_stream(codec, rate)` | Add video/audio stream |
| `container.decode(video=0)` | Decode frames from stream |
| `container.mux(packet)` | Write encoded packet |
| `container.close()` | Finalize and close |

### Video API

| Class / Method | Description |
|---------------|-------------|
| `VideoFrame` | Single video frame |
| `VideoFrame.from_ndarray(arr, format)` | Create from NumPy array (`'rgb24'`, `'bgr24'`, `'yuv420p'`) |
| `frame.to_ndarray(format)` | Convert to NumPy array |
| `frame.reformat(width, height, format)` | Resize and convert pixel format |
| `VideoCodecContext` | Encoder/decoder context |
| `VideoStream` | Video stream in container |
| `stream.encode(frame)` | Encode frame → packets |

### Audio API

| Class / Method | Description |
|---------------|-------------|
| `AudioFrame` | Single audio frame |
| `AudioFifo` | Audio sample FIFO buffer |
| `AudioResampler` | Sample rate / format conversion |
| `AudioFormat` | Audio sample format descriptor |
| `AudioLayout` | Channel layout (mono, stereo, 5.1, etc.) |
| `AudioCodecContext` | Audio encoder/decoder |
| `AudioStream` | Audio stream in container |

### Codec & Format Discovery

| Function | Description |
|----------|-------------|
| `av.codecs_available` | Set of all available codec names |
| `av.formats_available` | Set of all available format names |
| `av.Codec(name)` | Get codec descriptor |
| `av.ContainerFormat(name)` | Get format descriptor |
| `av.library_versions` | Dict of FFmpeg library versions |

### iOS-Specific

- Pre-loads 7 FFmpeg dylibs from `Frameworks/ffmpeg/` on import
- Hardware encoder: `h264_videotoolbox` (Apple VideoToolbox H.264)
- Fallback encoder: `mpeg4` (software MPEG-4)
- Containers: MP4, MOV, WebM, MKV, AVI, FLV, and more
- Audio codecs: AAC, MP3, FLAC, PCM, Opus

---

## FFmpeg — Native iOS Libraries

**7 dynamic libraries** | Cross-compiled for arm64-iphoneos | ~21 MB total

All inter-library dependencies rewritten to `@rpath/` for iOS framework loading.

| Library | Version | Size | Description |
|---------|---------|------|-------------|
| **libavcodec** | 62.29.101 | 12.7 MB | Codec library — encoding and decoding (H.264, HEVC, VP8/9, AV1, AAC, MP3, FLAC, etc.) |
| **libavformat** | 62.13.101 | 2.2 MB | Container formats — MP4, MOV, MKV, WebM, FLV, AVI, WAV, etc. |
| **libavfilter** | 11.15.101 | 3.7 MB | Audio/video filters — scale, crop, overlay, color correction, etc. |
| **libswscale** | 9.7.100 | 1.2 MB | Image scaling and pixel format conversion (RGB↔YUV, resize) |
| **libavutil** | 60.29.100 | 719 KB | Shared utilities — pixel formats, math, error codes, memory |
| **libswresample** | 6.4.100 | 118 KB | Audio resampling and sample format conversion |
| **libavdevice** | 62.4.100 | 96 KB | Device input/output abstraction |

### Symlink Structure

Each library has a version-less symlink for stable linking:
```
libavcodec.62.29.101.dylib → libavcodec.62.dylib
libavformat.62.13.101.dylib → libavformat.62.dylib
...
```

### Video Codecs (selected)

| Codec | Type | Notes |
|-------|------|-------|
| `h264_videotoolbox` | Hardware | Apple VideoToolbox H.264, zero-copy |
| `hevc_videotoolbox` | Hardware | Apple VideoToolbox H.265 |
| `mpeg4` | Software | MPEG-4 Part 2 (fallback) |
| `libvpx` / `libvpx-vp9` | Software | VP8/VP9 (if compiled in) |
| `rawvideo` | Uncompressed | Raw frames |
| `png` / `mjpeg` | Image | Per-frame image codecs |

### Audio Codecs (selected)

`aac`, `mp3`, `flac`, `pcm_s16le`, `pcm_f32le`, `opus`, `vorbis`

### Container Formats (selected)

`mp4`, `mov`, `mkv` / `webm`, `avi`, `flv`, `wav`, `mp3`, `ogg`, `gif`, `image2`

---

## Cairo (pycairo)

**Native iOS build** | C extension (2.8 MB) | Full 2D vector graphics

### Surfaces

| Class | Description |
|-------|-------------|
| `SVGSurface(path, w, h)` | Vector SVG output |
| `ImageSurface(format, w, h)` | Raster bitmap (ARGB32, RGB24, A8, A1, RGB16_565, RGB30, RGB96F, RGBA128F) |
| `PDFSurface(path, w, h)` | PDF document output |
| `PSSurface(path, w, h)` | PostScript output |
| `RecordingSurface(content, extents)` | Record drawing operations |
| `ScriptSurface(device, content, w, h)` | Cairo script device |

### Drawing Context

| Method | Description |
|--------|-------------|
| `Context(surface)` | Create drawing context |
| `ctx.move_to(x, y)` | Move pen position |
| `ctx.line_to(x, y)` | Line from current point |
| `ctx.curve_to(x1, y1, x2, y2, x3, y3)` | Cubic Bezier curve |
| `ctx.arc(xc, yc, radius, angle1, angle2)` | Circular arc |
| `ctx.arc_negative(...)` | Counter-clockwise arc |
| `ctx.rectangle(x, y, w, h)` | Rectangle path |
| `ctx.close_path()` | Close current sub-path |
| `ctx.new_path()` / `new_sub_path()` | Start fresh path |

### Rendering

| Method | Description |
|--------|-------------|
| `ctx.fill()` / `fill_preserve()` | Fill current path |
| `ctx.stroke()` / `stroke_preserve()` | Stroke current path outline |
| `ctx.paint()` / `paint_with_alpha(a)` | Paint entire surface |
| `ctx.clip()` / `clip_preserve()` | Set clip region from path |
| `ctx.mask(pattern)` / `mask_surface(s, x, y)` | Alpha mask |

### Color & Style

| Method | Description |
|--------|-------------|
| `ctx.set_source_rgb(r, g, b)` | Solid color (0.0–1.0) |
| `ctx.set_source_rgba(r, g, b, a)` | Color with alpha |
| `ctx.set_source_surface(surface, x, y)` | Surface pattern |
| `ctx.set_source(pattern)` | Any pattern |
| `ctx.set_line_width(w)` | Stroke width |
| `ctx.set_line_cap(cap)` | BUTT, ROUND, SQUARE |
| `ctx.set_line_join(join)` | BEVEL, MITER, ROUND |
| `ctx.set_dash(dashes, offset)` | Dash pattern |
| `ctx.set_operator(op)` | Compositing: OVER, ADD, MULTIPLY, SCREEN, etc. (24 modes) |
| `ctx.set_antialias(aa)` | BEST, DEFAULT, FAST, GOOD, GRAY, NONE, SUBPIXEL |

### Transformations

| Method | Description |
|--------|-------------|
| `ctx.translate(tx, ty)` | Translate origin |
| `ctx.scale(sx, sy)` | Scale axes |
| `ctx.rotate(angle)` | Rotate (radians) |
| `ctx.transform(matrix)` | Apply affine matrix |
| `ctx.set_matrix(matrix)` / `get_matrix()` | Direct matrix access |
| `ctx.identity_matrix()` | Reset transform |
| `ctx.user_to_device(x, y)` | Coordinate conversion |
| `ctx.device_to_user(x, y)` | Inverse conversion |

### Text & Fonts

| Method | Description |
|--------|-------------|
| `ctx.select_font_face(family, slant, weight)` | Choose font |
| `ctx.set_font_size(size)` | Set font size |
| `ctx.show_text(text)` | Render text at current point |
| `ctx.text_path(text)` | Convert text to vector outlines (used by manim) |
| `ctx.text_extents(text)` | Measure text bounding box |
| `ctx.font_extents()` | Font metric info |
| `ctx.show_glyphs(glyphs)` | Render glyph array |
| `ctx.glyph_extents(glyphs)` | Measure glyph bounding box |

### Patterns

| Class | Description |
|-------|-------------|
| `SolidPattern(r, g, b, a)` | Flat color |
| `LinearGradient(x0, y0, x1, y1)` | Linear color gradient |
| `RadialGradient(cx0, cy0, r0, cx1, cy1, r1)` | Radial color gradient |
| `SurfacePattern(surface)` | Image/surface as pattern |
| `MeshPattern()` | Coons/tensor patch mesh |
| `pattern.add_color_stop_rgb(offset, r, g, b)` | Gradient color stop |
| `pattern.set_extend(extend)` | NONE, PAD, REFLECT, REPEAT |
| `pattern.set_filter(filter)` | BEST, BILINEAR, FAST, GAUSSIAN, GOOD, NEAREST |

### Matrix

```python
m = cairo.Matrix(xx, yx, xy, yy, x0, y0)  # Affine transform
m.rotate(angle)
m.translate(tx, ty)
m.scale(sx, sy)
m.invert()
m.multiply(other)
```

### Enumerations (24 types)

`Antialias`, `Content`, `FillRule`, `Format`, `HintMetrics`, `HintStyle`, `SubpixelOrder`, `LineCap`, `LineJoin`, `Filter`, `Operator` (24 blending modes), `Extend`, `FontSlant`, `FontWeight`, `Status`, `PDFVersion`, `PSLevel`, `PathDataType`, `RegionOverlap`, `SVGVersion`, `SVGUnit`, `PDFMetadata`, `ScriptMode`, `TextClusterFlags`

---

## ManimPango — Text Rendering

**Cairo-based fallback** | Replaces native Pango on iOS

Since Pango's native GObject libraries don't load on iOS, manimpango is reimplemented using pycairo's text API.

### Pipeline
```
Text string → Font selection → Cairo text_path() → SVG vector outlines → manim SVGMobject
```

### Font Weights (11)
`THIN` (100), `ULTRALIGHT` (200), `LIGHT` (300), `BOOK` (380), `NORMAL` (400), `MEDIUM` (500), `SEMIBOLD` (600), `BOLD` (700), `ULTRABOLD` (800), `HEAVY` (900), `ULTRAHEAVY` (1000)

### Font Styles
`NORMAL`, `ITALIC`, `OBLIQUE`

### API

| Function | Description |
|----------|-------------|
| `text2svg(settings, size, line_no, ...)` | Render text to SVG file |
| `markup2svg(text, file, ...)` | Render Pango markup to SVG |
| `register_font(path)` | Register .ttf/.otf font |
| `list_fonts()` | List available font families |

---

## Pillow (PIL)

**Native iOS build** | v12.2.0

### Image Operations

| API | Description |
|-----|-------------|
| `Image.open(path)` | Load PNG, JPEG, GIF, BMP, TIFF, WebP |
| `Image.new(mode, size, color)` | Create blank (RGB, RGBA, L, P, CMYK) |
| `img.resize(size, resample)` | Resize with resampling |
| `img.crop(box)` | Crop region (left, upper, right, lower) |
| `img.rotate(angle, expand, fillcolor)` | Rotate image |
| `img.transpose(method)` | Flip/rotate 90/180/270 |
| `img.convert(mode)` | Convert color mode |
| `img.filter(kernel)` | Apply convolution filter |
| `img.save(path, format, quality)` | Save to file |

### Drawing (ImageDraw)

| Method | Description |
|--------|-------------|
| `draw.line(xy, fill, width)` | Draw line |
| `draw.rectangle(xy, fill, outline, width)` | Draw rectangle |
| `draw.ellipse(xy, fill, outline, width)` | Draw ellipse |
| `draw.polygon(xy, fill, outline)` | Draw polygon |
| `draw.arc(xy, start, end, fill, width)` | Draw arc |
| `draw.text(xy, text, fill, font)` | Draw text |
| `draw.textbbox(xy, text, font)` | Measure text bounding box |

### Filters (ImageFilter)

`BLUR`, `CONTOUR`, `DETAIL`, `EDGE_ENHANCE`, `EMBOSS`, `FIND_EDGES`, `SHARPEN`, `SMOOTH`, `GaussianBlur(radius)`, `UnsharpMask(radius, percent, threshold)`, `BoxBlur(radius)`, `MedianFilter(size)`, `MinFilter(size)`, `MaxFilter(size)`, `ModeFilter(size)`

---

## offlinai_latex — Local LaTeX Engine

**pdftex C library** | texmf bundle (9 MB, 302 files)

### Pipeline
```
LaTeX expression
  → pdftex (C library via ctypes, dllpdftexmain)
    → PDF output
      → Core Graphics render (4x resolution)
        → PNG bitmap
          → SVG with embedded image
            → manim SVGMobject
```

### API

| Function | Description |
|----------|-------------|
| `tex_to_svg(expression, svg_path)` | Full pipeline: LaTeX → SVG |
| `compile_tex(tex_source, output_dir)` | Compile .tex to DVI/PDF |

### TeX Packages Included

`article.cls`, `amsmath.sty`, `amssymb.sty`, `amsfonts.sty`, Computer Modern fonts (TFM + Type1), LaTeX3 kernel

### Fallback Chain
1. **pdftex** (real LaTeX typesetting) → PDF → SVG
2. **Cairo text_path** (LaTeX → Unicode conversion → vector text)
3. **Plain SVG text** (minimal `<text>` element)
