# Pillow (PIL)

> **Version:** 12.2.0 | **Type:** Stock (pre-built iOS wheel) | **Status:** Fully working

Python Imaging Library for image creation, manipulation, and processing.

---

## Quick Start

```python
from PIL import Image, ImageDraw, ImageFont, ImageFilter

img = Image.new('RGB', (400, 300), color='white')
draw = ImageDraw.Draw(img)
draw.rectangle([50, 50, 350, 250], outline='blue', width=3)
draw.ellipse([100, 75, 300, 225], fill='lightblue', outline='navy')
draw.text((150, 130), "Hello!", fill='black')
img.save('/tmp/test.png')
```

---

## `Image` Module -- Core Operations

### Creation & I/O

| Function | Description |
|----------|-------------|
| `Image.new(mode, size, color)` | Create new image. Modes: `'L'` (grayscale), `'RGB'`, `'RGBA'`, `'1'` (binary), `'P'` (palette), `'CMYK'`, `'HSV'`, `'I'` (32-bit int), `'F'` (32-bit float) |
| `Image.open(fp)` | Open image file |
| `img.save(fp, format, **params)` | Save to file. Formats: PNG, JPEG, BMP, GIF, TIFF, WEBP |
| `img.copy()` | Copy image |
| `Image.fromarray(arr, mode)` | Create from numpy array |
| `Image.frombytes(mode, size, data)` | Create from raw bytes |
| `Image.merge(mode, bands)` | Merge single-band images |
| `Image.blend(im1, im2, alpha)` | Blend two images (alpha mix) |
| `Image.composite(im1, im2, mask)` | Composite using mask |
| `Image.alpha_composite(im1, im2)` | Alpha composite |
| `Image.eval(image, func)` | Apply function to each pixel |

### Geometry Transforms

| Method | Description |
|--------|-------------|
| `img.resize(size, resample)` | Resize. Resample: `NEAREST`, `BILINEAR`, `BICUBIC`, `LANCZOS` |
| `img.thumbnail(size)` | Resize in-place (preserves aspect ratio) |
| `img.crop(box)` | Crop to bounding box (left, top, right, bottom) |
| `img.rotate(angle, expand, center, fillcolor)` | Rotate by degrees |
| `img.transpose(method)` | `FLIP_LEFT_RIGHT`, `FLIP_TOP_BOTTOM`, `ROTATE_90/180/270`, `TRANSPOSE`, `TRANSVERSE` |
| `img.transform(size, method, data)` | Affine, perspective, quad transforms |
| `img.paste(im, box, mask)` | Paste image onto self |
| `img.offset(xoffset, yoffset)` | Offset image |

### Color & Mode Conversion

| Method | Description |
|--------|-------------|
| `img.convert(mode)` | Convert color mode (e.g., RGB -> L, RGBA -> RGB) |
| `img.split()` | Split into individual bands |
| `img.getchannel(channel)` | Get single channel |
| `img.point(lut)` | Apply lookup table or function |
| `img.quantize(colors)` | Reduce to N colors |
| `img.putpalette(data)` | Set palette for mode P |

### Pixel Access

| Method | Description |
|--------|-------------|
| `img.getpixel((x, y))` | Get pixel value at coordinates |
| `img.putpixel((x, y), value)` | Set pixel value |
| `img.load()` | Get pixel access object `pix[x, y]` |
| `img.tobytes()` | Raw pixel bytes |
| `img.getdata()` | Pixel data as flat sequence |
| `img.putdata(data)` | Set pixels from flat sequence |
| `img.histogram(mask)` | Color histogram (list of 256 values per band) |
| `img.getextrema()` | Min/max pixel values |
| `img.getbbox()` | Bounding box of non-zero regions |

### Image Properties

| Property | Description |
|----------|-------------|
| `img.size` | `(width, height)` tuple |
| `img.width` / `img.height` | Dimensions |
| `img.mode` | Color mode string |
| `img.format` | File format (PNG, JPEG, etc.) |
| `img.info` | Metadata dict |

---

## `ImageDraw` -- 2D Drawing

```python
from PIL import ImageDraw
draw = ImageDraw.Draw(img)
```

| Method | Description |
|--------|-------------|
| `draw.line(xy, fill, width, joint)` | Draw line(s). `joint='curve'` for smooth |
| `draw.rectangle(xy, fill, outline, width)` | Rectangle |
| `draw.rounded_rectangle(xy, radius, fill, outline, width)` | Rounded rectangle |
| `draw.ellipse(xy, fill, outline, width)` | Ellipse |
| `draw.polygon(xy, fill, outline, width)` | Polygon |
| `draw.regular_polygon(bounding_circle, n_sides, rotation, fill, outline)` | Regular polygon |
| `draw.arc(xy, start, end, fill, width)` | Arc |
| `draw.chord(xy, start, end, fill, outline)` | Chord (arc + line) |
| `draw.pieslice(xy, start, end, fill, outline)` | Pie slice |
| `draw.point(xy, fill)` | Single pixel(s) |
| `draw.text(xy, text, fill, font, anchor, align)` | Draw text |
| `draw.multiline_text(xy, text, fill, font, spacing, align)` | Multi-line text |
| `draw.textbbox(xy, text, font)` | Text bounding box |
| `draw.textlength(text, font)` | Text width in pixels |
| `draw.bitmap(xy, bitmap, fill)` | Draw bitmap |
| `draw.floodfill(xy, value, border, thresh)` | Flood fill |

---

## `ImageFilter` -- Predefined Filters

| Filter | Description |
|--------|-------------|
| `ImageFilter.BLUR` | Box blur |
| `ImageFilter.CONTOUR` | Contour detection |
| `ImageFilter.DETAIL` | Detail enhancement |
| `ImageFilter.EDGE_ENHANCE` | Edge enhancement |
| `ImageFilter.EDGE_ENHANCE_MORE` | Strong edge enhancement |
| `ImageFilter.EMBOSS` | Emboss effect |
| `ImageFilter.FIND_EDGES` | Edge detection |
| `ImageFilter.SHARPEN` | Sharpen |
| `ImageFilter.SMOOTH` | Smooth |
| `ImageFilter.SMOOTH_MORE` | Strong smooth |
| `ImageFilter.GaussianBlur(radius)` | Gaussian blur with radius |
| `ImageFilter.BoxBlur(radius)` | Box blur with radius |
| `ImageFilter.UnsharpMask(radius, percent, threshold)` | Unsharp mask sharpening |
| `ImageFilter.MedianFilter(size)` | Median filter |
| `ImageFilter.MinFilter(size)` | Minimum filter (erosion) |
| `ImageFilter.MaxFilter(size)` | Maximum filter (dilation) |
| `ImageFilter.ModeFilter(size)` | Mode filter |
| `ImageFilter.RankFilter(size, rank)` | Rank filter |
| `ImageFilter.Kernel(size, kernel, scale, offset)` | Custom convolution kernel |

Usage: `img.filter(ImageFilter.GaussianBlur(5))`

---

## `ImageEnhance` -- Enhancement

```python
from PIL import ImageEnhance

enhancer = ImageEnhance.Brightness(img)
img_bright = enhancer.enhance(1.5)  # 1.0 = original, >1 = brighter
```

| Class | Description |
|-------|-------------|
| `ImageEnhance.Brightness(img)` | Adjust brightness (0=black, 1=original, 2=2x bright) |
| `ImageEnhance.Contrast(img)` | Adjust contrast (0=grey, 1=original) |
| `ImageEnhance.Color(img)` | Adjust color saturation (0=B&W, 1=original) |
| `ImageEnhance.Sharpness(img)` | Adjust sharpness (0=blur, 1=original, 2=2x sharp) |

---

## `ImageFont` -- Font Handling

| Function | Description |
|----------|-------------|
| `ImageFont.truetype(font, size)` | Load TrueType/OpenType font |
| `ImageFont.load_default(size)` | Load default bitmap font |

---

## `ImageOps` -- Image Operations

| Function | Description |
|----------|-------------|
| `ImageOps.autocontrast(img, cutoff)` | Normalize histogram |
| `ImageOps.equalize(img, mask)` | Histogram equalization |
| `ImageOps.flip(img)` | Flip top-to-bottom |
| `ImageOps.mirror(img)` | Flip left-to-right |
| `ImageOps.invert(img)` | Invert colors |
| `ImageOps.grayscale(img)` | Convert to grayscale |
| `ImageOps.posterize(img, bits)` | Reduce bit depth per channel |
| `ImageOps.solarize(img, threshold)` | Solarize effect |
| `ImageOps.colorize(img, black, white)` | Colorize grayscale image |
| `ImageOps.pad(img, size, color, centering)` | Pad to size |
| `ImageOps.fit(img, size, method, centering)` | Crop and resize to exact size |
| `ImageOps.contain(img, size)` | Resize to fit within size (keep aspect) |
| `ImageOps.expand(img, border, fill)` | Add border |
| `ImageOps.crop(img, border)` | Remove border pixels |
| `ImageOps.exif_transpose(img)` | Apply EXIF orientation |

---

## `ImageChops` -- Channel Operations

| Function | Description |
|----------|-------------|
| `ImageChops.add(im1, im2, scale, offset)` | Add images |
| `ImageChops.subtract(im1, im2, scale, offset)` | Subtract images |
| `ImageChops.multiply(im1, im2)` | Multiply (darken) |
| `ImageChops.screen(im1, im2)` | Screen (lighten) |
| `ImageChops.difference(im1, im2)` | Absolute difference |
| `ImageChops.lighter(im1, im2)` | Element-wise max |
| `ImageChops.darker(im1, im2)` | Element-wise min |
| `ImageChops.invert(im)` | Invert image |
| `ImageChops.offset(im, xoffset, yoffset)` | Offset with wrap |
| `ImageChops.overlay(im1, im2)` | Overlay blend |

---

## `ImageColor` -- Color Names

```python
from PIL import ImageColor
rgb = ImageColor.getrgb("red")              # (255, 0, 0)
rgb = ImageColor.getrgb("#ff8800")          # (255, 136, 0)
rgb = ImageColor.getrgb("rgb(100,200,50)") # (100, 200, 50)
rgb = ImageColor.getrgb("hsl(120,100%,50%)") # (0, 255, 0)
```

Supports: Named colors (148 CSS4), hex (`#RGB`, `#RRGGBB`, `#RRGGBBAA`), `rgb()`, `hsl()` functions.

---

## `ImageStat` -- Statistics

```python
from PIL import ImageStat
stat = ImageStat.Stat(img)
stat.mean      # Mean per band
stat.median    # Median per band
stat.stddev    # Standard deviation per band
stat.extrema   # Min/max per band
stat.count     # Pixel count per band
stat.sum       # Sum per band
stat.sum2      # Sum of squares per band
stat.var       # Variance per band
```

---

## Not Available

- `img.show()` (no display on iOS -- use `img.save()` instead)
- System font discovery (limited font access on iOS)
- Some codecs may be unavailable depending on iOS build (e.g., JPEG2000)
