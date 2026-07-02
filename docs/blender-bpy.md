# Blender `bpy` — on-device 3D (iOS / iPadOS, native arm64)

`import bpy` — the **full Blender Python module**, cross-compiled for iOS arm64
(CPython 3.14). Build scenes, run modifiers and physics, simulate smoke, track
footage, exchange USD, and **render with Cycles on the Apple GPU (Metal) with
OpenImageDenoise** — entirely on-device, no network, no JIT. First public build
of Blender's `bpy` on iOS — and at **feature parity with the PyPI `bpy` wheel**
for everything that doesn't need a GPU windowing backend (see
[Gaps vs PyPI](#gaps-vs-the-pypi-bpy-wheel)).

- **Blender:** 5.3.0 (alpha branch)
- **Module:** `bpy/__init__.so` (~231 MB) + `bpy/5.3/scripts` + datafiles
  (+ `bpy/lib/libusd_ms` + `bpy/usd_resources` for USD)
- **Render:** Cycles SVM on CPU **and** Apple Metal GPU; OpenImageDenoise
- **SwiftPM product:** `Blender` (see [Packaging](#packaging--why-the-binary-is-compressed))

---

## What's compiled in

| Area | Status | Notes |
|------|--------|-------|
| **Cycles** | ✅ | Path tracer — SVM shaders (no-JIT), CPU + **Metal GPU**, path guiding (OpenPGL) |
| **OpenImageDenoise** | ✅ | Intel OIDN AI denoiser (CPU); check via `_cycles.with_openimagedenoise` |
| **Embree** | ✅ | CPU BVH acceleration |
| **OpenSubdiv** | ✅ | Subdivision surfaces / multires |
| **OpenVDB / NanoVDB** | ✅ | Volumes + voxel remesh + fluid caches |
| **Alembic** | ✅ | `.abc` import/export |
| **USD + MaterialX** | ✅ | `.usd/.usda/.usdc` import/export (OpenUSD 26.03 monolithic + usdImaging); MaterialX export path. Script-registered `USDHook`s no-op (USD built without its Python bindings) |
| **Bullet** | ✅ | Rigid-body / physics |
| **Mantaflow** | ✅ | Fluid / smoke — **simulation verified on device** (bake → OpenVDB cache, nonzero density) |
| **Motion tracking (libmv)** | ✅ | ceres-solver camera/object solve — `bpy.ops.clip.solve_camera`, full `MovieTracking` RNA |
| **Audio (audaspace)** | ✅ | The `aud` module — generate/filter/sequence sounds; loads WAV/AIFF/AU/CAF via libsndfile. No playback device (same as PyPI — see gaps) |
| **Ocean (FFTW)** | ✅ | Ocean modifier |
| **Manifold + GMP** | ✅ | Exact-solver boolean |
| **Freestyle** | ✅ | NPR line render |
| **OpenColorIO** | ✅ | Color management |
| **Image I/O** | ✅ | **10/10 on-device:** PNG · JPEG · OpenEXR · TIFF · WebP · JPEG2000 · Cineon · DPX · Targa · BMP (+ DDS/HDR read) |
| **Potrace / Haru** | ✅ | Trace-to-curve / grease-pencil PDF export |
| **HarfBuzz / FreeType / fribidi** | ✅ | Text objects + full i18n (`bpy.app.translations`, 49 locales — *more than the PyPI wheel, which disables i18n*) |
| **OBJ / PLY / STL / FBX / glTF** | ✅ | Mesh I/O — FBX via the new C++ `bpy.ops.wm.fbx_*`; glTF **with Draco** (statically linked, round-trip verified) |
| **Geometry nodes** | ✅ | Full node graph |
| **FFmpeg video** | ✅ | H.264/H.265 (Apple VideoToolbox) · MPEG-4 · FFV1 · QTRLE · … — see [Video output](#video-output-ffmpeg) |
| **Cycles OSL** | ❌ | Needs LLVM — not bundled (PyPI has it; script nodes only) |
| **Eevee / `gpu` module** | ❌ | Needs a GPU windowing backend (Metal GHOST) — headless build; **do not call `gpu.init()` — it deadlocks** |

The definitive runtime check for a compiled-in feature is
`bpy.app.build_options.<name>` (e.g. `.cycles`, `.openvdb`, `.libmv`, `.fluid`,
`.usd`, `.international`). **OIDN is the exception** — Blender never exposed it
there; use `import _cycles; _cycles.with_openimagedenoise`.

---

## Gaps vs the PyPI `bpy` wheel

Audited against Blender's own wheel build config
(`build_files/cmake/config/blender_release.cmake` + `bpy_module.cmake`) and
probed at runtime on device. Things people *assume* are gaps but aren't: the
**PyPI wheel itself** ships with CoreAudio/OpenAL/JACK playback **off**, NDOF
off, IME off — and **i18n off** (this build has i18n **on**).

| | PyPI wheel (macOS arm64) | this iOS build |
|---|---|---|
| Cycles CPU + Metal GPU, Embree, OIDN, guiding | ✅ | ✅ (Metal renders verified on device) |
| USD + MaterialX, Alembic, all mesh I/O, Draco | ✅ | ✅ |
| Fluid, ocean, bullet, tracking (libmv) | ✅ | ✅ |
| Image formats / video (ffmpeg) | ✅ | ✅ (H.264/265 via VideoToolbox) |
| `aud` present, **no playback device** | ✅ | ✅ (identical: null device) |
| i18n (`bpy.app.translations`) | ❌ off | ✅ **on** (49 locales) |
| **Eevee render + working `gpu` module** | ✅ (Metal) | ❌ headless — the *one big gap* |
| Hydra render-delegate framework | ✅ flag on | ❌ off (pointless without GPU delegates) |
| Cycles **OSL** script nodes | ✅ | ❌ (needs LLVM cross-build) |
| **OpenMP** (mantaflow/oceansim threading) | ✅ | ❌ (perf only; Cycles uses TBB regardless) |
| **Rubberband** (VSE audio time-stretch quality) | ✅ | ❌ (falls back to plain resampling) |
| `bpy.app.build_hash` | real hash | `Unknown` (cosmetic; `WITH_BUILDINFO=OFF`) |
| OpenXR / NDOF / IME / audio playback | ❌ off | ❌ off (parity) |

**Runtime notes from the device probes:**

- **Cycles Metal really renders** (kernels compile on first render, cache after).
  On *small* scenes the CPU is often faster (GPU dispatch overhead dominates);
  the GPU pays off at higher resolutions/sample counts — benchmark your workload.
- **Never call `gpu.init()`.** Blender 5.x exposes it for headless-GPU wheels,
  but this build has no GPU backend: it blocks forever inside
  `WM_system_gpu_context` (worker thread, `semaphore_wait_trap`) and the Python
  interpreter never returns. The `BLENDER_EEVEE` enum entry fails the same way
  at render time.
- **Add-ons:** the 13 bundled add-ons match PyPI 5.x `addons_core` exactly
  (`io_scene_gltf2`, `io_scene_fbx`, `rigify`, `pose_library`, `node_wrangler`, …).

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
in the module). Cycles compiles its Metal kernels on the **first render of a
session** (up to ~3 min on older iPads, seconds on M-class; no progress callback
during the compile); kernels then cache and later renders run in seconds. Keep
`prefs.metalrt = "OFF"` and `prefs.kernel_optimization_level = "OFF"` (above) to
keep that first compile manageable. **CPU** (`scene.cycles.device = "CPU"`) has
no compile wait and is often *faster for small stills* — the GPU wins as
resolution/samples grow.

In CodeBench you usually don't write any of the render/preview plumbing: the
bundled startup handler shows a **tqdm progress bar** during every render and
opens the **interactive viewer** (orbit + a "Rendered" toggle) automatically —
see [Interactive preview](#interactive-blend-preview-codebench).

---

## Fluid simulation (mantaflow)

Full smoke/liquid simulation works on device — domain + flow objects, bake to
an OpenVDB cache, and render the volume:

```python
import bpy, os
sc = bpy.data.scenes[0]

bpy.ops.mesh.primitive_cube_add(size=4)
dom = bpy.context.active_object
m = dom.modifiers.new("Fluid", "FLUID"); m.fluid_type = "DOMAIN"
m.domain_settings.domain_type = "GAS"
m.domain_settings.resolution_max = 48
m.domain_settings.cache_directory = os.path.expanduser("~/Documents/fluid_cache")

bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(0, 0, -1.2))
f = bpy.context.active_object.modifiers.new("Flow", "FLUID"); f.fluid_type = "FLOW"
f.flow_settings.flow_type = "SMOKE"; f.flow_settings.flow_behavior = "INFLOW"

sc.frame_start, sc.frame_end = 1, 24
with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom]):
    bpy.ops.fluid.bake_data()            # → .vdb frames in the cache dir
```

Two iOS-specific fixes are baked into the module (upstream-clean, in
`bpy_ios_source.patch`): fluid **teardown** no longer aborts the process, and
the manta Python bindings are finalized even when something imports `manta`
before the first solve (CodeBench's completion indexer does) — without that fix
every *inherited* grid method (`LevelsetGrid.setConst`, …) was missing and the
solver script failed.

---

## Motion tracking (libmv)

`bpy.app.build_options.libmv == True`. Load footage as a **MovieClip**, add
markers, and run the camera solver — the full desktop pipeline:

```python
clip = bpy.data.movieclips.load("~/Documents/shot.mp4")
# ... add/track markers via bpy.ops.clip.* ...
bpy.ops.clip.solve_camera()              # ceres-based reconstruction
print(clip.tracking.reconstruction.average_error)
```

(ceres-solver is cross-built against Blender's own Eigen, so solver results
match desktop.)

---

## Audio (`aud` / audaspace)

The `aud` module is bundled: generate, filter, mix, and sequence audio, and
**load files** (WAV/AIFF/AU/CAF via libsndfile; compressed formats via ffmpeg).

```python
import aud
s = aud.Sound.file("~/Documents/beep.wav").volume(0.5).fadein(0, 0.1)
buf = aud.Sound.buffer(s)                # process fully in memory
```

`aud.Device()` returns a **null device** (no playback) — identical to the PyPI
wheel, which also ships without an audio backend. Route rendered audio to a
file, or play files with the app's own player. **Do not call
`aud.Sound.buffer()` / `.cache()`**: with the null device's 0 Hz rate the full
decode never terminates (spins forever). Filter graphs, file loading, and
explicit-rate APIs are fine.

---

## USD / MaterialX

```python
bpy.ops.wm.usd_export(filepath="scene.usdc")   # + usd_import
```

Round-trip verified on device. The runtime pieces live inside the module
directory (`bpy/lib/libusd_ms` + `bpy/usd_resources/{lib_usd,plugin_usd}`); the
host app sets `PXR_PLUGINPATH_NAME` so the plugin registry resolves (CodeBench
does this automatically). MaterialX shader export is compiled in. Two
limitations: OpenUSD is built **without its Python bindings**, so a `USDHook`
subclass registered from a script never fires (basic import/export unaffected);
and **exporting a scene that contains a baked fluid DOMAIN livelocks** (the
export spins forever at low CPU) — delete/exclude the domain object or export
selected meshes only.

---

## Video output (FFmpeg)

Render an animation straight to a video file. **Blender 5.x gotcha:** set
`image_settings.media_type = 'VIDEO'` *before* `file_format = 'FFMPEG'` — the
file-format enum only exposes the movie formats once the media type is video.

```python
scene = bpy.data.scenes[0]
scene.render.image_settings.media_type = "VIDEO"   # ← must come first
scene.render.image_settings.file_format = "FFMPEG"
scene.render.ffmpeg.format = "MPEG4"                # container (.mp4)
scene.render.ffmpeg.codec  = "H264"                 # see table below
scene.render.filepath = "anim"                      # ~/Documents, NOT /tmp
scene.frame_start, scene.frame_end = 1, 48
bpy.ops.render.render(animation=True)               # → anim0001-0048.mp4
```

**Codecs verified on-device (iPad):**

| Codec | Encoder | Notes |
|-------|---------|-------|
| `H264` / `H265` | Apple **VideoToolbox** (hardware) | standard compact `.mp4`; 4:2:0, lossy |
| `MPEG4` | native libavcodec | widely playable `.mp4` |
| `FFV1` | native libavcodec | lossless (use the `MKV` container) |
| `QTRLE` / `PNG` / `HUFFYUV` | native | lossless / intra-only |

iOS specifics, handled for you in the module:

- **Encoding is single-threaded** on iOS — ffmpeg's encoder worker threads abort
  on teardown on-device, so the movie codecs run on one thread (slower, stable).
- **H.264/H.265 use the hardware VideoToolbox encoder** (no `libx264` is bundled);
  the module feeds it a software 4:2:0 frame, so the *default lossless* setting is
  high-quality lossy for those two — pick `FFV1` for true lossless.
- **Audio muxing:** audaspace is now bundled, so scene-strip audio *can* mix into
  the render — not yet exercised on device; treat as experimental.
- Confirm with `bpy.app.build_options.codec_ffmpeg` (`True`).

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
- **Never call `gpu.init()`** — it deadlocks the interpreter (no GPU backend in
  this headless build). Cycles GPU rendering does *not* need it.
- **glTF + Draco works** (statically linked): export with
  `export_draco_mesh_compression_enable=True` round-trips on device.
- **No `_multiprocessing`** on iOS — a stub ships so `bpy` imports cleanly.

---

## Packaging — why the binary is compressed

`bpy/__init__.so` is ~231 MB, far over GitHub's 100 MB per-blob limit. Git LFS is
incompatible with SwiftPM's checkout
([swift-package-manager#5351](https://github.com/swiftlang/swift-package-manager/issues/5351)),
so — exactly like `libtorch_python.dylib` — the binary ships **LZMA-compressed**:

```
Sources/Blender/
├── Blender.swift                    # BlenderLib.bootstrap()
├── bpy            -> ../../app_packages/site-packages/bpy   (scripts, tracked)
└── bpy_dylib/
    └── __init__.so.applzma          # Apple COMPRESSION_LZMA
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
`IMPORTED` targets. All ~30 dependencies (Embree, OIDN, OpenVDB, Alembic,
Bullet, Mantaflow, FFTW, GMP/manifold, OpenUSD, MaterialX, ceres, libsndfile,
fribidi, …) were rebuilt for iOS arm64 — recipes in the project's
`blender_ios/` tree (`build_*_ios.sh` + the 12-file `bpy_ios_source.patch`,
round-trip verified against upstream `c9dd766c`).

**Remaining gaps vs the PyPI wheel:** Eevee + the `gpu` module (needs a Metal
GHOST backend — the one structural gap), Cycles OSL (LLVM), OpenMP (perf),
Rubberband (VSE audio stretch quality), `build_hash` (cosmetic).
