# Manim

> **Version:** 0.20.1 | **Type:** Stock + iOS stubs | **Status:** Experimental

Mathematical animation engine. Installed with all dependencies but rendering pipeline is limited on iOS (no OpenGL display).

---

## Dependencies (all installed)

| Package | Version | Status |
|---------|---------|--------|
| numpy | 2.3.5 | Working |
| scipy | 1.15.2 | Partial |
| Pillow | 12.2.0 | Working |
| pycairo | - | Working |
| manimpango | 0.6.1 | Working |
| svgelements | 1.9.6 | Working |
| isosurfaces | 0.1.2 | Working |
| mapbox_earcut | - | Working |
| pathops (skia) | - | Working |
| moderngl | stub | Non-functional |
| screeninfo | stub | Hardcoded iPad dims |
| click | 8.3.2 | Working |
| rich | 14.3.3 | Working |
| pygments | 2.20.0 | Working |
| networkx | 3.6.1 | Working |
| srt | 3.5.3 | Working |
| watchdog | stub | Non-functional |

## iOS Stubs

| Package | Purpose |
|---------|---------|
| `moderngl` | OpenGL stub — `create_standalone_context()` returns a no-op context |
| `moderngl_window` | Window management stub |
| `screeninfo` | Returns hardcoded iPad dimensions (1024x1366) |
| `watchdog` | File watching stub (no filesystem events on iOS) |

## Limitations

- No OpenGL rendering (moderngl is a stub)
- No video output (ffmpeg subprocess limited)
- Scene rendering may fail for complex animations
- Text rendering works via manimpango + pango + cairo
- Math rendering works for LaTeX-like expressions
