# moderngl + moderngl_window + screeninfo

> **moderngl 5.12.0+torch_ios_stub** + **moderngl_window 2.4.6** + **screeninfo 0.8.1**  | **Type:** Stubbed on iOS (no GPU context available outside the host app)  | **Status:** Importable; runtime usage limited

OpenGL bindings (`moderngl`), a windowing/event helper
(`moderngl_window`), and a display detection library (`screeninfo`).
Bundled because manim's experimental OpenGL renderer asks for them at
import time. iOS doesn't expose OpenGL or windowing to embedded Python,
so all three are essentially stubs — they import cleanly so manim's
fallback paths work, but you won't get real GPU rendering through them.

---

## moderngl

### Status

The bundled moderngl is the **`_Stub`** version — its `create_context`
function raises a clear "no OpenGL context on iOS" error if called.
The package imports successfully, exposes the correct top-level
attributes (`moderngl.create_context`, `moderngl.Context`,
`moderngl.Buffer`, …), and lets type-annotated code that imports
moderngl symbols without calling them work.

### Why it's stubbed

iOS apps can run OpenGL ES via EAGLContext, but:
1. The embedded Python interpreter doesn't have its own thread/runloop
   binding for EAGLContext setup.
2. The host app's UIKit owns the GL context; sharing it across the
   Python-Swift bridge is non-trivial.
3. moderngl's preferred backend is desktop OpenGL (4.1+), not GLES.

So the iOS shim accepts imports, refuses runtime context creation,
and points users at Metal-based alternatives.

### What works

```python
import moderngl
print(moderngl.__version__)             # '5.12.0+torch_ios_stub'

# Type access (for code that just uses moderngl as type annotations)
ctx_type = moderngl.Context
buf_type = moderngl.Buffer
```

### What fails

```python
ctx = moderngl.create_context()
# → NotImplementedError: moderngl: no OpenGL context available on iOS.
#   Use Metal directly via Swift, or render via a CALayer-backed view.
```

### iOS GPU alternatives

- **Metal** — the right answer for native iOS GPU work. Call from
  Swift; bridge to Python via file IPC or CallableC if you need
  it.
- **CoreGraphics** — for 2D vector work, use Apple's CG instead of
  trying to set up OpenGL. Pair with `cairo` (bundled) for Python-side
  vector rendering, then composite via UIImageView.
- **manim's Cairo renderer** — works fine on iOS without moderngl
  (the OpenGL renderer is opt-in via `manim.config.renderer = "opengl"`,
  default is "cairo").

---

## moderngl_window

### Status

Same story — pure-Python wrapper over multiple windowing back-ends
(GLFW, SDL2, PyQt5, PySide2, Pygame, Tkinter). None of those work
on iOS (no native windowing for embedded Python). The package imports
but `moderngl_window.run_window_config(...)` raises.

### What you'd use it for normally

- Cross-platform "open a window, get an OpenGL context, run an event
  loop" — i.e., desktop OpenGL apps.
- Educational graphics demos that work on Linux/Windows/macOS without
  per-platform setup.

### What to use instead on iOS

- For the host app's UI: UIKit / SwiftUI directly in Swift.
- For an embedded view: SCNView (SceneKit) or MTKView (Metal).
- For headless rendering of a single frame: just use Cairo (`pycairo`)
  to write a PNG and display it via UIImageView.

---

## screeninfo

### Status

Cross-platform display detection — "what monitors does this machine
have, where are they, what's their resolution?" iOS has exactly one
display (the device screen) plus optional external displays via
AirPlay / cable; the OS exposes that via UIScreen, not via
screeninfo's X11/Win32/Quartz back-ends.

The bundled screeninfo imports cleanly and `screeninfo.get_monitors()`
returns a list with one synthetic entry derived from `UIScreen.main`
— width/height in points (NOT pixels), x=0, y=0:

```python
import screeninfo

mons = screeninfo.get_monitors()
for m in mons:
    print(f"{m.width}×{m.height} @ ({m.x},{m.y})  primary={m.is_primary}")
# 393×852 @ (0,0)  primary=True   (e.g. iPhone 14 Pro)
```

### Limitations

- **Points, not pixels.** UIKit reports `bounds` in points; multiply
  by `UIScreen.main.scale` (usually 2.0 or 3.0 on iOS) for pixel
  dimensions.
- **No multi-display detection** — even with AirPlay external
  displays attached, iOS only reports the main one through this
  shim. (External displays exist but go through `UIScreen.screens`
  in Swift; the Python shim doesn't bridge that.)
- **No DPI / refresh-rate / color-profile** — screeninfo's `Monitor`
  shape doesn't carry those fields anyway, so even on Linux/macOS
  it's just position + size.

### When to use

- Code that asks "where's the screen, how big is it?" for layout
  purposes works.
- Anything more sophisticated (multiple monitors, HDR, refresh rate)
  needs to drop down to UIKit / Swift.

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

## Future: Real GPU bridge

A proper implementation would:
1. Create a Metal (or GLES) context in Swift.
2. Wrap it in a Python C extension that exposes the moderngl API
   surface backed by Metal.
3. Provide a Buffer / Texture / Program shape compatible enough
   for manim's OpenGL renderer to work.

That's a non-trivial port (~weeks of work) and arguably the wrong
abstraction layer — manim's OpenGL renderer would still be doing
software-style GPU calls one-at-a-time, which is the opposite of
how Metal performs well. Better to use manim's Cairo renderer on
iOS and accept the per-frame CPU cost.
