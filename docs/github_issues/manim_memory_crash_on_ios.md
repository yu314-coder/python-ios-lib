# Manim scenes crash on iOS when they exceed the ~8 GB jetsam memory limit

**Target repo**: `python-ios-lib` (the one hosting the iOS-specific patches to manim / cairo / pango / sklearn used by OfflinAi)
**Component**: `manim` (bundled at 0.19.x in the iOS app_packages)
**iOS build target**: iPad / iPhone, arm64, sandboxed App Store distribution
**Memory ceiling**: hard jetsam limit of ≈ 50% of device RAM (≈ 8 GB on a 16 GB iPad Pro) for apps **without** the `com.apple.developer.kernel.increased-memory-limit` entitlement — which isn't available to free/personal Apple Developer accounts.

## Summary

Long manim scenes (roughly ≥ 20 `self.play()` calls or heavy MathTex/Text/ImageMobject usage) crash the host app with

```
Thread 2: EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark memory limit exceeded) (limit=8192 MB)
```

around animation 18–23 of a typical mathematical-presentation scene. The root cause is **not** a single leak — it's the sum of several sources of steady memory growth across animations, compounded by iOS's hard jetsam cap. Desktop manim handles the same scene fine because macOS/Linux have swap + a far higher per-process budget.

## Repro

A minimal-ish scene that reliably crashes on a 16 GB iPad Pro around animation 20:

```python
from manim import *

class LongTSNEStyle(ThreeDScene):
    def construct(self):
        for step in range(30):
            title = Text(f"Step {step}: lorem ipsum dolor sit amet",
                         font_size=26, color=ORANGE, weight=BOLD)
            self.add_fixed_in_frame_mobjects(title)
            self.play(FadeIn(title))
            # Synthesize ~3000 small mobjects per step, just like a
            # digit-grid visualization would.
            group = VGroup(*[
                Square(side_length=0.05, fill_opacity=0.6, stroke_width=0.5)
                .shift(np.array([i*0.1, j*0.1, 0]))
                for i in range(-10, 10) for j in range(-10, 10)
            ])
            self.add_fixed_in_frame_mobjects(*group)
            self.play(*[FadeIn(m) for m in group], run_time=0.5)
            self.wait(0.2)
            self.play(*[FadeOut(m) for m in group], FadeOut(title), run_time=0.3)
```

## Root causes identified (in descending order of impact)

### 1. `SVG_HASH_TO_MOB_MAP` never evicts

Tracked upstream in [ManimCommunity/manim#4327](https://github.com/ManimCommunity/manim/issues/4327).
`manim/mobject/svg/svg_mobject.py:29` declares a module-level `SVG_HASH_TO_MOB_MAP: dict[int, SVGMobject]` that stores a **deep copy** of every parsed SVGMobject / MathTex / Text forever. Each cached MathTex holds every glyph's full bezier point array. On iOS, 20 unique equations = hundreds of MB permanently locked into this dict.

**Fix applied in OfflinAi's bundled manim**:
- Force `use_svg_cache=False` on iOS in `SVGMobject.init_svg_mobject`
- Clear `SVG_HASH_TO_MOB_MAP` between animations in `SceneFileWriter.close_partial_movie_stream`

### 2. `ThreeDCamera.fixed_in_frame_mobjects` set leaks

Users commonly call `scene.add_fixed_in_frame_mobjects(title)` then `FadeOut(title)`. `FadeOut` removes from `scene.mobjects` but **never** prunes the camera's `fixed_in_frame_mobjects: set[Mobject]`. In TSNE-style scenes this set accumulates thousands of entries (every submobject is added via `extract_mobject_family_members`).

**Fix applied**: Override `ThreeDScene.remove()` to also call `cam.fixed_in_frame_mobjects.difference_update(mob.get_family())` recursively.

### 3. `Animation` holds deep-copies of `mobject`, `starting_mobject`, `target_mobject`

After `clean_up_from_scene`, the Animation instance still references full-point-array copies of its mobject. On desktop these die quickly when `scene.animations = new_list` on the next `play()`; on iOS's tight budget they overlap with the next animation's peak allocation.

**Fix applied**: On iOS, after `animation.clean_up_from_scene(scene)` in `Scene.play_internal`, null out `starting_mobject` / `target_mobject` / `target_copy` / `original_mobject`, then set `scene.animations = None` at the end of play_internal.

### 4. Frame queue unbounded in `SceneFileWriter`

`self.queue: Queue[tuple[int, PixelArray | None]] = Queue()` is unbounded. At 1920×1080 RGBA each frame is 8 MB; when PyAV encoding falls behind, frames accumulate. 1920 queued frames = 16 GB. This alone explains many "died around frame ~1800" reports.

**Fix applied**: Cap the queue at 32 frames on iOS.

### 5. User-code: local variables in long scene methods

The scene method itself is often a 300–500 line function that binds `all_images`, `all_matrices`, `all_vectors`, `data_matrix_full`, `clustered_images`, ... to locals. Python can't reclaim any of them until the method returns. `FadeOut` only removes from the *scene's draw list*, not from the Python reference.

**Fix applied**: In all remover animations (`FadeOut`, `Uncreate`, etc.), strip the bulk numpy arrays (`points`, `rgbas`, `stroke_rgbas`, `fill_rgbas`, `triangulation`) from the whole mobject family. The Python shell stays alive (so the user's local reference doesn't crash), but the memory-dominant data is reclaimed.

### 6. VideoToolbox encoder lookahead

`h264_videotoolbox` with `realtime=0` asks VideoToolbox to buffer multiple frames for quality optimization. On iOS this leaks hundreds of MB per long animation.

**Fix applied**: Force `realtime=1` + small GOP (`g=frame_rate`) on iOS.

### 7. Curve subdivision doubles point counts on MathTex

`SingleStringMathTex.__init__` passes `should_subdivide_sharp_curves=True` to add samples at sharp corners for smoother triangulation — ~40% more points per glyph.

**Fix applied**: On iOS, disable subdivision for MathTex.

### 8. `text2svg` shape mismatch (pango stub)

OfflinAi's pango stub (for the iOS pycairo fallback path) originally emitted a single giant `<path>` containing all glyphs as bezier data. manim's `VMobjectFromSVGPath` then created one enormous VMobject per `Text(...)`. Desktop Pango produces `<defs>` + `<use>` (each glyph defined once, referenced N times → N small VMobjects), which is much friendlier to both parse-time memory and per-frame interpolation cost.

**Fix applied**: Rewrote the stub `text2svg` to emit `<defs>` + `<use>` matching real Pango's structure.

## Net effect of the fixes

A TSNE-style scene with 100+ animations now runs to completion on a 16 GB iPad in ~95 s instead of dying at animation 20. A Fermat's-Little-Theorem-style scene (≈ 15 animations, 5 MathTex equations, no large VGroups) runs comfortably and never approaches the jetsam ceiling.

## Still broken — what we can't fix from the library side

Scenes that genuinely create > ~5000 simultaneous VMobjects (e.g., pixel-accurate MNIST digit grids, full chessboards, cellular-automaton frames) still approach the 8 GB ceiling even after all of the above. This is **structural** — there's no way to fit the working set of that many VMobjects + their interpolation intermediates into the 50%-of-RAM per-process limit that iOS imposes on apps without the `increased-memory-limit` entitlement.

**Workarounds for end users**:
1. Split large scene methods into smaller helper methods so Python can reclaim locals between them.
2. Avoid `add_fixed_in_frame_mobjects(*big_vgroup)` — it adds every submobject to the camera's set recursively.
3. Call `self.clear()` between logical scene sections.
4. Render at 720p instead of 1080p (the iOS defaults in OfflinAi's bundled manim are already `pixel_width=1280, pixel_height=720, frame_rate=30`).
5. For distribution: join the paid Apple Developer Program and enable `com.apple.developer.kernel.increased-memory-limit` + `com.apple.developer.kernel.extended-virtual-addressing` in the app's `.entitlements` — this roughly doubles the jetsam ceiling.

## References

- ManimCommunity/manim#4327 — SVGMobject/MathTex caching issues
- ManimCommunity/manim#3743 — unbounded memory allocation in scene.play
- Apple docs: [Increased Memory Limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- OfflinAi's iOS patch stack: `app_packages/site-packages/manim/{_config,scene,mobject,animation,camera}/…`
