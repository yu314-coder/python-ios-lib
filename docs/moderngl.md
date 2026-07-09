# moderngl + moderngl_window + screeninfo

**Versions:** moderngl 5.12.0 (+`metal_ios`) + moderngl_window 2.4.6 + screeninfo 0.8.1
**Type:** moderngl core is a **Metal-backed implementation** (via Blender's gpu
module); moderngl_window + screeninfo remain stubs (no windowing on iOS)
**SPM target:** Bundled as part of `Manim` (transitive dep)

**2026-07 upgrade:** moderngl used to be a pure raising-stub ("iOS has no
OpenGL"). The core API now *works on the Apple GPU*: the bundled Blender ships
an offscreen **Metal** backend with a runtime **GLSL→MSL cross-compiler**
(`gpu.init()` / `GPUShader` / `GPUOffScreen` — device-verified), and
`moderngl/_mgl_metal.py` adapts moderngl's object model onto it. Standalone
contexts, buffers, vertex+fragment programs (real GLSL 330 in — Metal out),
uniforms, VAOs with index buffers, framebuffer clear/render/read, and
RGBA8/RGBA32F textures all execute on-device.

```python
import moderngl, struct
ctx  = moderngl.create_standalone_context()      # offscreen Metal context
prog = ctx.program(
    vertex_shader="""#version 330
        in vec2 in_vert;
        void main() { gl_Position = vec4(in_vert, 0.0, 1.0); }""",
    fragment_shader="""#version 330
        out vec4 fragColor; uniform vec3 u_color;
        void main() { fragColor = vec4(u_color, 1.0); }""")
prog["u_color"].value = (0.0, 1.0, 0.0)
vbo = ctx.buffer(struct.pack("<6f", -1,-1, 3,-1, -1,3))
vao = ctx.vertex_array(prog, [(vbo, "2f", "in_vert")])
fbo = ctx.simple_framebuffer((256, 256)); fbo.use(); fbo.clear(0,0,0,1)
vao.render(moderngl.TRIANGLES)                   # runs on the Apple GPU
pixels = fbo.read(components=4)                  # bytes, GL bottom-up rows
```

### Still not supported (clear errors, not crashes)

| Feature | Why |
|---|---|
| Geometry / tessellation / compute shaders | Blender's raw-shader path is vertex+fragment |
| Transform feedback, `Query` / `Scope` | No GL equivalents exposed |
| `TextureArray` / `Texture3D` / `TextureCube` | Not wired (2-D RGBA8/RGBA32F only) |
| `moderngl_window` windowing / event loop | No windows on iOS — offscreen only |
| manim's OpenGL renderer | Needs far more of the API + a window; manim stays on the Cairo renderer (which is also the faster path on iOS — see manim.md) |

First use note: `import bpy` initialises Blender (~seconds, big import) —
the context is created lazily on `create_standalone_context()`.

---

## moderngl

### Modules

| Module | What it does |
|---|---|
| `moderngl.__init__` | Public surface — re-exports the working classes/constants from `_mgl_metal`, keeps raising-stubs + `__getattr__` fallback for the uncovered API |
| `moderngl._mgl_metal` | The Metal backend — adapts Context / Buffer / Program / VertexArray / Framebuffer / Texture onto Blender's `gpu` module (GLSL→MSL, `GPUOffScreen`) |

### How the GLSL gets to the GPU

`ctx.program(vertex_shader=…, fragment_shader=…)` strips the `#version` /
`layout(…)` lines and hands the source to `gpu.types.GPUShader`, whose
runtime cross-compiler emits **MSL** (the same machinery Eevee uses on this
build). Uniforms are deferred and applied at draw; `sampler2D` uniforms bind
`Texture.use(unit)` bindings by name. Framebuffer reads come back as bytes
in OpenGL bottom-up row order, matching real moderngl.

Any unknown attribute (`moderngl.SomethingNew`) still routes through
`__getattr__` to a raising class — import-time compatibility for code
that references the uncovered API is preserved.

### iOS GPU alternatives

- **This module** for offscreen shader rendering from Python
- **bpy's `gpu` module** directly (the machinery underneath)
- **manim's Cairo renderer** — manim stays on Cairo; the GL renderer needs
  far more of the API + a window, and Cairo is the faster path on iOS anyway

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
