# Minor Libraries — Index

This file used to be one long page covering ~15 small utility packages.
Each one now has its own dedicated doc with the full module breakdown,
SPM-target info, iOS notes, and a worked example — same template as
[werkzeug.md](werkzeug.md). `minor-libs.md` now exists only as a
discovery index so you can scan the small-utility space at a glance.

## Per-library docs

| Lib | Version | Type | SPM target | Doc |
|---|---|---|---|---|
| **attrs** | 24.2.0 | Pure Python | Bundled in `JsonSchema` | [attrs.md](attrs.md) |
| **packaging** | 26.0 | Pure Python | Bundled in `Matplotlib` | [packaging.md](packaging.md) |
| **narwhals** | 1.16.0 | Pure Python | Bundled in `Matplotlib` | [narwhals.md](narwhals.md) |
| **referencing** | 0.36.2 | Pure Python | Bundled in `JsonSchema` | [referencing.md](referencing.md) |
| **srt** | 3.5.3 | Pure Python (single file) | Bundled in `Manim` | [srt.md](srt.md) |
| **cloup** | 3.0.5 | Pure Python | `Cloup` (pulls `Click`) | [cloup.md](cloup.md) |
| **mdurl** | 0.1.2 | Pure Python | Bundled in `Rich` | [mdurl.md](mdurl.md) |
| **typing-extensions** | 4.15.0 | Pure Python (single file) | `Typing_extensions` | [typing-extensions.md](typing-extensions.md) |
| **isosurfaces** | 0.1.2 | Pure Python (NumPy) | `Isosurfaces` | [isosurfaces.md](isosurfaces.md) |
| **rpds** | iOS stub (replaces `rpds-py` 0.22.3) | Pure Python stub | Bundled in `JsonSchema` | [rpds.md](rpds.md) |
| **pycairo** | 1.29.0 | Native iOS arm64 `.so` | Bundled in `CairoGraphics` | [pycairo.md](pycairo.md) |
| **mapbox-earcut** | 1.0.3 | Native iOS arm64 `.so` | `Mapbox_earcut` | [mapbox-earcut.md](mapbox-earcut.md) |
| **pathops** (skia-pathops) | 0.9.2 | Native iOS arm64 `abi3.so` | Bundled in `Manim` | [pathops.md](pathops.md) |

## Already had their own docs before this split

These weren't part of `minor-libs.md`; listed here for completeness:

| Lib | Doc |
|---|---|
| decorator | [decorator.md](decorator.md) |
| soupsieve | covered in [small-utils.md](small-utils.md) |
| markdown-it-py | [markdown-it.md](markdown-it.md) |
| cffi | [cffi.md](cffi.md) |
| manimpango | [manimpango.md](manimpango.md) |
| audioop / pyaudioop | [audioop.md](audioop.md) |

## See also

- [small-utils.md](small-utils.md) — overlapping coverage of cloup, soupsieve, rpds, srt + a few internal/build-only packages (`_distutils_hack`, `pkg_resources`, `setuptools`, `wheel`, `pylab`, `torchgen`)
- [README.md](README.md) — top-level guide to the docs/ directory
