# Pillow (PIL)

> **Version:** 12.2.0 | **Type:** Stock (pre-built iOS wheel) | **Status:** Fully working

Python Imaging Library for image processing.

---

## Quick Start

```python
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Create image
img = Image.new('RGB', (400, 300), color='white')
draw = ImageDraw.Draw(img)
draw.rectangle([50, 50, 350, 250], outline='blue', width=3)
draw.ellipse([100, 75, 300, 225], fill='lightblue', outline='navy')
draw.text((150, 130), "Hello!", fill='black')
img.save('/tmp/test.png')
```

## Key Modules

| Module | Functions |
|--------|-----------|
| `Image` | `open()`, `new()`, `save()`, `resize()`, `crop()`, `rotate()`, `transpose()`, `convert()`, `filter()`, `paste()`, `split()`, `merge()` |
| `ImageDraw` | `line()`, `rectangle()`, `ellipse()`, `polygon()`, `text()`, `arc()`, `chord()`, `pieslice()` |
| `ImageFilter` | `BLUR`, `CONTOUR`, `DETAIL`, `EDGE_ENHANCE`, `EMBOSS`, `SHARPEN`, `SMOOTH`, `GaussianBlur`, `UnsharpMask` |
| `ImageEnhance` | `Brightness`, `Contrast`, `Color`, `Sharpness` |
| `ImageFont` | `truetype()`, `load_default()` |
| `ImageOps` | `autocontrast()`, `equalize()`, `flip()`, `mirror()`, `invert()`, `grayscale()` |

## Not Available

- Display (`img.show()` — no display on iOS, use `img.save()` instead)
- System fonts (limited font access on iOS)
