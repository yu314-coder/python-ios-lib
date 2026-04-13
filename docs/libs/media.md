# Media & Rendering

Libraries for video encoding, 2D graphics, image processing, and LaTeX typesetting.

---

## PyAV (FFmpeg bindings)

**Native iOS build** | 7 dylibs | Hardware H.264 via VideoToolbox

| API | Description |
|-----|-------------|
| `av.open(path, mode='w')` | Open container for reading/writing |
| `container.add_stream(codec, rate)` | Add video/audio stream |
| `av.VideoFrame.from_ndarray(arr)` | Create frame from NumPy array |
| `stream.encode(frame)` | Encode frame to packets |
| `container.mux(packet)` | Write packet to container |

Codecs: `h264_videotoolbox` (hardware), `mpeg4` (fallback), `aac`

---

## Cairo (pycairo)

**Native iOS build** | SVG + PNG surfaces

| API | Description |
|-----|-------------|
| `cairo.SVGSurface(path, w, h)` | Create SVG output |
| `cairo.ImageSurface(fmt, w, h)` | Create bitmap output |
| `ctx.move_to` / `line_to` / `arc` | Path construction |
| `ctx.text_path(text)` | Convert text to vector paths |
| `ctx.fill()` / `ctx.stroke()` | Render paths |
| `ctx.set_source_rgb(r, g, b)` | Set color |

Used by manim for text rendering (bypasses Pango).

---

## Pillow (PIL)

**Native iOS build** | v12.2.0

| API | Description |
|-----|-------------|
| `Image.open(path)` | Load image |
| `Image.new(mode, size)` | Create blank image |
| `img.resize(size)` | Resize image |
| `img.crop(box)` | Crop region |
| `img.rotate(angle)` | Rotate image |
| `img.filter(ImageFilter.BLUR)` | Apply filter |
| `ImageDraw.Draw(img)` | Drawing context |
| `draw.rectangle` / `ellipse` / `text` | Shape drawing |

---

## offlinai_latex

**Local LaTeX engine** | pdftex C library

| API | Description |
|-----|-------------|
| `tex_to_svg(expr)` | LaTeX expression to SVG file |
| `compile_tex(source)` | Compile .tex to DVI/PDF |

Pipeline: LaTeX source -> pdftex (C lib) -> PDF -> Core Graphics render -> SVG

Fallback: LaTeX -> Unicode conversion -> Cairo text_path -> SVG
