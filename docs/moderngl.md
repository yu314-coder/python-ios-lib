# moderngl + moderngl_window + screeninfo

**Versions:** moderngl 5.12.0 (+`torch_ios_stub`) + moderngl_window 2.4.6 + screeninfo 0.8.1
**Type:** All three are **pure-Python iOS stubs** (no GPU context outside the host app)
**SPM target:** Bundled as part of `Manim` (transitive dep)
**Total modules:** moderngl 1, moderngl_window 4, screeninfo 9

OpenGL bindings (`moderngl`), a windowing/event helper
(`moderngl_window`), and a display detection library (`screeninfo`).
Bundled because manim's experimental OpenGL renderer asks for them at
import time. iOS doesn't expose OpenGL or windowing to embedded Python,
so all three are stubs — they import cleanly so manim's fallback
paths work, but you won't get real GPU rendering through them.

---

## moderngl

### Modules

| Module | What it does |
|---|---|
| `moderngl.__init__` | The entire stub — class names, draw-mode constants, `create_context` raising-stub, `__getattr__` permissive fallback |

That's it — one file. The bundled `moderngl` is fully self-contained
in `moderngl/__init__.py` (~80 LOC).

### What's stubbed

```python
import moderngl
print(moderngl.__version__)             # '5.12.0+torch_ios_stub'

# Class names that import cleanly:
moderngl.Context, moderngl.Program, moderngl.Framebuffer, moderngl.Texture,
moderngl.Buffer, moderngl.VertexArray, moderngl.Renderbuffer, moderngl.Uniform,
moderngl.Attribute, moderngl.Scope, moderngl.Query, moderngl.Sampler,
moderngl.ComputeShader, moderngl.TextureArray, moderngl.Texture3D,
moderngl.TextureCube, moderngl.Error

# GL constants present:
moderngl.POINTS, LINES, LINE_LOOP, LINE_STRIP, TRIANGLES, TRIANGLE_STRIP,
TRIANGLE_FAN, LINES_ADJACENCY, …
moderngl.BLEND, DEPTH_TEST, CULL_FACE, NEAREST, LINEAR, CLAMP_TO_EDGE, REPEAT
```

Any unknown attribute (`moderngl.SomethingNew`) routes through
`__getattr__` to return the same `_NotImplementedStub` class — so
code that does `class MyShader(moderngl.SomethingNew): ...` at module
load doesn't crash. Instantiation raises:

```python
ctx = moderngl.create_context()
# → NotImplementedError: moderngl.create_context: iOS has no OpenGL
```

### Why stubbed (not implemented)

iOS supports OpenGL ES via `EAGLContext`, but:
1. The embedded Python interpreter doesn't have its own thread/runloop
   binding for EAGLContext setup.
2. The host app's UIKit owns the GL context; sharing it across the
   Python-Swift bridge is non-trivial.
3. moderngl's preferred backend is desktop OpenGL 4.1+, not GLES.
4. Apple deprecated OpenGL on iOS in iOS 12 — the right answer is
   Metal, which moderngl doesn't speak.

### Code example (the only thing that works)

```python
import moderngl
print(moderngl.__version__)
# '5.12.0+torch_ios_stub'

# Type access works (for code that just uses moderngl as type annotations)
def render_pass(ctx: moderngl.Context, prog: moderngl.Program) -> None:
    ...
```

### iOS GPU alternatives

- **Metal** (Swift) — the right answer for native iOS GPU work
- **CoreGraphics** — for 2D vector work, use Apple's CG (or pycairo, bundled)
- **manim's Cairo renderer** — works without moderngl; `manim.config.renderer = "cairo"` (default)

---

## moderngl_window

### Modules

| Module | What it does |
|---|---|
| `moderngl_window.__init__` | Stub — `__getattr__` returns `_Stub` for any attribute; instantiation raises |
| `moderngl_window.context.__init__` | Submodule stub |
| `moderngl_window.context.pyglet` | Empty subpackage |
| `moderngl_window.timers.clock` | The one real module — pure-Python `Timer` (no GL dep) |

### Status

Same story — pure-Python wrapper over multiple windowing back-ends
(GLFW, SDL2, PyQt5, PySide2, Pygame, Tkinter). None work on iOS
(no native windowing for embedded Python). Package imports but
`moderngl_window.run_window_config(...)` raises.

### Code example

```python
import moderngl_window

# Importable:
print(moderngl_window.__name__)

# But:
moderngl_window.run_window_config({})
# → NotImplementedError: moderngl_window: iOS uses cairo renderer
```

### iOS alternatives

- Host app UI: UIKit / SwiftUI directly in Swift
- Embedded view: `SCNView` (SceneKit) or `MTKView` (Metal)
- Headless single-frame: pycairo → PNG → `UIImageView`

---

## screeninfo

### Modules

| Module | What it does |
|---|---|
| `screeninfo.__init__` | Public API: `Enumerator`, `Monitor`, `ScreenInfoError`, `get_monitors` |
| `screeninfo.__main__` | `python -m screeninfo` CLI |
| `screeninfo.common` | `Monitor` dataclass, base `Enumerator` enum |
| `screeninfo.screeninfo` | Dispatch logic — picks an enumerator based on platform |
| `screeninfo.util` | Platform detection |
| `screeninfo.enumerators.cygwin` | Cygwin platform |
| `screeninfo.enumerators.drm` | Linux DRM (kernel display) |
| `screeninfo.enumerators.osx` | macOS Quartz Display Services |
| `screeninfo.enumerators.windows` | Win32 |
| `screeninfo.enumerators.xinerama` | X11 Xinerama |
| `screeninfo.enumerators.xrandr` | X11 RandR |

### Status on iOS

iOS has exactly one display (the device screen) plus optional external
displays via AirPlay / cable; the OS exposes that via `UIScreen`, not
via any of screeninfo's X11/Win32/Quartz back-ends.

The bundled screeninfo imports cleanly and `screeninfo.get_monitors()`
returns a list with one synthetic entry derived from `UIScreen.main`
— width/height in points (NOT pixels), `x=0`, `y=0`:

```python
import screeninfo

mons = screeninfo.get_monitors()
for m in mons:
    print(f"{m.width}×{m.height} @ ({m.x},{m.y})  primary={m.is_primary}")
# 393×852 @ (0,0)  primary=True   (e.g. iPhone 14 Pro)
```

### Limitations

- **Points, not pixels.** UIKit reports `bounds` in points; multiply
  by `UIScreen.main.scale` (usually 2.0 or 3.0) for pixel dimensions.
- **No multi-display detection** — even with AirPlay external displays
  attached, iOS only reports the main one through this shim.
- **No DPI / refresh-rate / color-profile** — `Monitor` shape doesn't
  carry those fields anyway.

---

## Why all three are bundled

manim's import chain on the experimental OpenGL renderer:
```
manim
  └─ moderngl_window         (handles window setup if you opted into OpenGL)
       └─ moderngl           (the GL bindings)
            └─ screeninfo    (figure out where to put the window)
```

Even with the default Cairo renderer, manim's `__init__.py`
conditionally imports these for code paths it might exercise later.
Bundling stubs prevents `ImportError` at `import manim` time.

If your app doesn't use the OpenGL renderer at all, you can remove
all three packages from the bundle to save ~6 MB. They're not pulled
into any other dep chain.

---

## iOS notes

All three are **pure-Python stubs written by the OfflinAi team** —
not vendored copies of the upstream packages. Sources live in
`app_packages/site-packages/moderngl/__init__.py`,
`moderngl_window/__init__.py`, and `screeninfo/`. The dist-info
declares the canonical PyPI versions so `pip` reports them
already-satisfied.

### Future: Real GPU bridge

A proper implementation would:
1. Create a Metal (or GLES) context in Swift.
2. Wrap it in a Python C extension that exposes the moderngl API
   surface backed by Metal.
3. Provide Buffer / Texture / Program shapes compatible enough for
   manim's OpenGL renderer to work.

Non-trivial port (~weeks of work) and arguably the wrong abstraction
— manim's OpenGL renderer makes software-style GPU calls one-at-a-time,
which Metal isn't optimized for. Better to use Cairo on iOS.
