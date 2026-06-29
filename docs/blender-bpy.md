# Blender `bpy` — on-device 3D (iOS / iPadOS, native arm64)

`import bpy` — the **full Blender Python module**, cross-compiled for iOS arm64
(CPython 3.14). Build scenes, run modifiers and physics, and **render with
Cycles on the Apple GPU (Metal) with OpenImageDenoise** — entirely on-device, no
network, no JIT. First public build of Blender's `bpy` on iOS.

- **Blender:** 5.3.0 (alpha branch)
- **Module:** `bpy/__init__.so` (~161 MB) + `bpy/5.3/scripts` + datafiles
- **Render:** Cycles SVM on CPU **and** Apple Metal GPU; OpenImageDenoise
- **SwiftPM product:** `Blender` (see [Packaging](#packaging--why-the-binary-is-compressed))

---

## What's compiled in

| Area | Status | Notes |
|------|--------|-------|
| **Cycles** | ✅ | Path tracer — SVM shaders (no-JIT), CPU + **Metal GPU** |
| **OpenImageDenoise** | ✅ | Intel OIDN AI denoiser (CPU); check via `_cycles.with_openimagedenoise` |
| **Embree** | ✅ | CPU BVH acceleration |
| **OpenSubdiv** | ✅ | Subdivision surfaces / multires |
| **OpenVDB** | ✅ | Volumes + voxel remesh |
| **Alembic** | ✅ | `.abc` import/export |
| **Bullet** | ✅ | Rigid-body / physics |
| **Mantaflow** | ✅ | Fluid / smoke |
| **Ocean (FFTW)** | ✅ | Ocean modifier |
| **Manifold + GMP** | ✅ | Exact-solver boolean |
| **Freestyle** | ✅ | NPR line render |
| **OpenColorIO** | ✅ | Color management |
| **OpenEXR / JPEG2000 / WebP / Cineon / TIFF / HDR** | ✅ | Image I/O |
| **Potrace / Haru** | ✅ | Trace-to-curve / PDF |
| **HarfBuzz / FreeType** | ✅ | Text objects |
| **OBJ / PLY / STL / glTF** | ✅ | Mesh I/O (glTF without draco — see below) |
| **Geometry nodes** | ✅ | Full node graph |
| **Cycles OSL** | ❌ | Needs LLVM JIT — forbidden on iOS |
| **USD** | ❌ | Deferred (very large) |
| **FFmpeg video** | ❌ | Deferred (`bpy.app.build_options.codec_ffmpeg == False`) |

The definitive runtime check for a compiled-in feature is
`bpy.app.build_options.<name>` (e.g. `.cycles`, `.openvdb`, `.bullet`). **OIDN is
the exception** — Blender never exposed it there; use
`import _cycles; _cycles.with_openimagedenoise`.

---

## Quick start

```python
import bpy, math

# clean slate (headless: use bpy.data, NOT bpy.context.scene which can be None)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
scene = bpy.data.scenes[0]

# a subdivided monkey
bpy.ops.mesh.primitive_monkey_add()
mon = bpy.context.active_object          # NOT bpy.data.objects[-1] — see gotchas
mon.modifiers.new("s", "SUBSURF").levels = 2

# camera + sun
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.location = (0, -4.5, 1.2); cam.rotation_euler = (math.radians(75), 0, 0)
scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0; sun.rotation_euler = (math.radians(45), 0, math.radians(30))
scene.collection.objects.link(sun)

# render on the Apple GPU with OpenImageDenoise
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
(prefs.refresh_devices if hasattr(prefs, "refresh_devices") else prefs.get_devices)()
for d in prefs.devices: d.use = True
prefs.metalrt = "OFF"                     # iOS: skip the hardware-RT path
prefs.kernel_optimization_level = "OFF"   # iOS: skip the slow specialized kernel compile
scene.cycles.device = "GPU"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.cycles.denoiser = "OPENIMAGEDENOISE"
scene.render.resolution_x, scene.render.resolution_y = 480, 360
scene.render.filepath = "render.png"      # NB: /tmp is read-only on iOS — use a relative path or ~/Documents
bpy.ops.render.render(write_still=True)
```

**GPU on a real device:** the Metal path works (the iOS-only
`setShouldMaximizeConcurrentCompilation:` unrecognized-selector crash is patched
in the module). But Cycles compiles its Metal kernels on the **first render of a
session (~3 min, serial)** — there is no progress callback during that compile;
kernels then cache and later renders run in ~2–3 s. Set `prefs.metalrt = "OFF"`
and `prefs.kernel_optimization_level = "OFF"` (above) to keep that first compile
manageable. **CPU** (`scene.cycles.device = "CPU"`) has no compile wait and is a
good default for quick stills — the full 16-module gallery + a CPU render
finishes in ~16 s on an M3.

In CodeBench you usually don't write any of the render/preview plumbing: the
bundled startup handler shows a **tqdm progress bar** during every render and
opens the **interactive viewer** (orbit + a "Rendered" toggle) automatically —
see the next section.

---

## Interactive `.blend` preview (CodeBench)

In the CodeBench app, **saving a `.blend` auto-generates an interactive WebGL 3D
viewer** in the preview pane — orbit / pinch-zoom / pan, plus a tap-toggle to the
photoreal Cycles render. You write no preview code:

```python
bpy.ops.wm.save_as_mainfile(filepath="/path/scene.blend")   # → live 3D preview
```

This is driven by two bundled modules:

- `codebench_blend_view.py` — extracts evaluated geometry (modifiers applied),
  bakes it to a self-contained WebGL viewer (`build_view(scene, …) → html`).
- `bpy/5.3/scripts/startup/codebench_blend_preview.py` — a `@persistent`
  `save_post` handler that renders a Cycles still, builds the viewer, and ships
  it through CodeBench's preview channel.

Set `CB_BLEND_NO_RENDER=1` to skip the still render for faster saves.

---

## Headless gotchas

- **`bpy.context.scene` / `.active_object` can be `None`** in this headless
  build (and always inside handlers). Use `bpy.data.scenes[0]` /
  `bpy.data.objects`, and read modifier results via the evaluated depsgraph.
- **`bpy.data.objects[-1]` is ordered by *name*, not creation.** After a
  primitive-add op, grab the new object with **`bpy.context.active_object`** (or a
  before/after `set(bpy.data.objects.keys())` diff) — `[-1]` returns the
  alphabetically-last object once the scene fills up.
- **glTF + draco:** draco is statically linked (not a separate dylib), so export
  with `export_draco_mesh_compression_enable=False`. (The addon's draco probe is
  patched not to crash on `sys.platform == 'ios'`.)
- **No `_multiprocessing`** on iOS — a stub ships so `bpy` imports cleanly.

---

## Packaging — why the binary is compressed

`bpy/__init__.so` is ~161 MB, over GitHub's 100 MB per-blob limit. Git LFS is
incompatible with SwiftPM's checkout
([swift-package-manager#5351](https://github.com/swiftlang/swift-package-manager/issues/5351)),
so — exactly like `libtorch_python.dylib` — the binary ships **LZMA-compressed**:

```
Sources/Blender/
├── Blender.swift                    # BlenderLib.bootstrap()
├── bpy            -> ../../app_packages/site-packages/bpy   (scripts, tracked)
└── bpy_dylib/
    └── __init__.so.applzma          # 69 MB, Apple COMPRESSION_LZMA
```

The raw `.so` is git-ignored; rebuild the blob with
`swift scripts/repack-bpy-so.swift` after rebuilding bpy. Consumers decompress
once at launch:

```swift
import Blender
try BlenderLib.bootstrap()    // materializes bpy/__init__.so into Caches/
```

`bootstrap()` is idempotent (a `stat()` after the first run). See `Blender.swift`
for how the host app points Python's loader at `BlenderLib.modulePath`.

---

## Build provenance

Cross-compiled with CMake's built-in iOS support (`-DCMAKE_SYSTEM_NAME=iOS`,
find-root mode, `iphoneos` SDK, deployment 16.4). Blender ships no cross-compile
support, so the host code generators (`makesdna`/`makesrna`/`datatoc`) are
harvested from the build, recompiled host-native, and re-imported as
`IMPORTED` targets. All ~20 M4 dependencies (Embree, OIDN, OpenVDB, Alembic,
Bullet, Mantaflow, FFTW, GMP/manifold, …) were rebuilt for iOS arm64. Full
build notes live in the project's `blender_ios/` tree.

**Deferred:** OSL (LLVM JIT, banned on iOS), USD (size), FFmpeg video
(headers-only link), libmv (Eigen version clash).
