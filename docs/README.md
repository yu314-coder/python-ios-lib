# OfflinAi — Offline Libraries Reference

Everything runs locally on iPad. No internet required.

---

## Languages

| Language | Runtime | Notes |
|----------|---------|-------|
| **Python 3.14** | BeeWare embedded | Full CPython with native extensions |
| **C** | Tree-walking interpreter | 48 operators, structs, pointers, preprocessor |
| **C++** | Tree-walking interpreter | Classes, STL, templates, inheritance |
| **Fortran** | Tree-walking interpreter | Modules, allocatable arrays, intrinsics |

## Python Libraries

### Scientific Computing

| Library | Type | Description |
|---------|------|-------------|
| **NumPy** 2.3 | Native iOS | N-dimensional arrays, linear algebra, FFT, random |
| **SciPy** 1.15 | Pure Python shim | Optimization, interpolation, integration, signal, stats |
| **SymPy** 1.14 | Pure Python | Symbolic math: algebra, calculus, equation solving |
| **mpmath** | Pure Python | Arbitrary-precision arithmetic |

### Machine Learning

| Library | Type | Description |
|---------|------|-------------|
| **scikit-learn** | Pure NumPy (12K lines) | 40 modules: classification, regression, clustering, preprocessing, model selection, metrics |

### Visualization

| Library | Type | Description |
|---------|------|-------------|
| **matplotlib** | Plotly shim (64 modules) | Drop-in pyplot replacement rendering interactive HTML charts |
| **Plotly** 6.6 | Pure Python | Interactive charts: scatter, bar, 3D, maps, animations |
| **manim** 0.20 | Modified for iOS | Math animations: shapes, transforms, graphs, 3D, LaTeX |

### Media & Rendering

| Library | Type | Description |
|---------|------|-------------|
| **PyAV** (FFmpeg) | Native iOS (7 dylibs) | Video encoding/decoding, H.264 hardware via VideoToolbox |
| **Cairo** (pycairo) | Native iOS | 2D vector graphics: SVG, PNG, paths, text |
| **Pillow** 12.2 | Native iOS | Image processing: resize, crop, filter, draw |
| **offlinai_latex** | pdftex C library | Local LaTeX rendering for math typesetting |

### Data & Web

| Library | Type | Description |
|---------|------|-------------|
| **requests** | Pure Python | HTTP client: GET, POST, sessions, JSON |
| **BeautifulSoup4** | Pure Python | HTML/XML parsing and web scraping |
| **NetworkX** 3.6 | Pure Python | Graph theory: algorithms, generators, analysis |
| **jsonschema** | Pure Python | JSON Schema validation (Draft 7) |
| **PyYAML** | Native | YAML parsing and serialization |

### Utilities

| Library | Type | Description |
|---------|------|-------------|
| **rich** | Pure Python | Rich text, tables, progress bars |
| **tqdm** | Pure Python | Progress bars for loops |
| **click** | Pure Python | CLI framework with decorators |
| **Pygments** | Pure Python | Syntax highlighting |
| **pydub** | Pure Python | Audio manipulation |
| **packaging** | Pure Python | Version parsing (PEP 440) |
| **srt** | Pure Python | Subtitle file parsing |
| **watchdog** | Pure Python | File system events |

---

## Detailed Docs

- [NumPy](libs/numpy.md)
- [SciPy](libs/scipy.md)
- [scikit-learn](libs/sklearn.md)
- [matplotlib](libs/matplotlib.md)
- [SymPy](libs/sympy.md)
- [manim](libs/manim.md)
- [Media & Rendering](libs/media.md)
- [C/C++/Fortran Interpreters](libs/interpreters.md)
