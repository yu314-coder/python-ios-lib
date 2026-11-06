"""
manim_writer_test.py — the writer thread behind each animation's video clip,
in the same style as manim_encoder_test.py.

Run from the in-app shell:

    python manim_writer_test.py            # about a minute
    python manim_writer_test.py --long     # adds a backlog past 60 s, ~3 min

On a Mac, `--as-ios` runs the iOS code paths too (the VideoToolbox probe, the
frame-queue settings, the memory release at each clip's close).

Why this exists. Each animation is encoded by a writer thread fed through a
bounded queue. At the end of the animation, close_partial_movie_stream used to
give that thread 60 s to finish, then close the clip's container and — on iOS
— drop the stream, container and queue to free memory. At 8K and 120 fps with
32 frames queued, an iPad's encoder is still working normally after 60 s; it
then muxed into None (AttributeError: 'NoneType' object has no attribute
'mux'), and could read the *next* clip's queue, since it looked the queue up
through the writer. Four things have to hold:

  1. A slow encoder is waited for, for as long as it keeps encoding.
  2. A stuck one fails the render with a clear error, without closing the
     container under it.
  3. Each thread reads its own clip's queue; the next clip opens only after
     the previous one's thread has exited.
  4. Every frame lands in its own clip, and the final video has them all
     (counted by time: a wait() may be written as its first and last frame).
"""
from __future__ import annotations

import os
import sys
import tempfile
import threading
import time

PASSED = 0
FAILED = 0
LONG = "--long" in sys.argv
AS_IOS = "--as-ios" in sys.argv


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}  {detail}")


try:
    import av
    from manim import BLUE, PI, RIGHT, Create, Scene, Square, tempconfig
    from manim.scene import scene_file_writer as sfw
    from manim.scene.scene_file_writer import SceneFileWriter
    from manim.utils.ios_encoder import RenderSettings, settings
except Exception as exc:                                   # pragma: no cover
    print(f"  FAIL  import manim  {type(exc).__name__}: {exc}")
    raise SystemExit(1)


class ThreeClips(Scene):
    """A moving clip, a hold (one batch of many frames), another moving clip."""

    def construct(self):
        sq = Square(color=BLUE)
        self.play(Create(sq), run_time=1.0)
        self.wait(1.0)
        self.play(sq.animate.shift(RIGHT * 2).rotate(PI / 3), run_time=1.0)


def frames_in(path, fps=30):
    """The frames a clip shows, by time: a wait() is written as its first and
    last frame, the first lasting until the second (VideoToolbox), so its
    packets are fewer than its frames, but not its length."""
    with av.open(path) as c:
        v = c.streams.video[0]
        if v.duration is not None and v.time_base is not None:
            return int(round(float(v.duration * v.time_base) * fps))
        return sum(1 for p in c.demux(v) if p.size)


def render(per_frame_delay=0.0, block_after=None, stall=None, queue=None):
    """Render ThreeClips and report what the writer did.

    per_frame_delay: each encoded frame takes this much longer.
    block_after: the encoder stops for good after this many frames.
    """
    clips, order, errors = [], [], []
    release = threading.Event()
    encoded = [0]

    real_encode = SceneFileWriter.encode_and_write_frame
    real_open = SceneFileWriter.open_partial_movie_stream
    real_close = SceneFileWriter.close_partial_movie_stream
    real_write = SceneFileWriter.write_frame
    real_hook = threading.excepthook
    saved_stall = settings.encoder_stall_seconds
    saved_explicit = settings._explicit
    saved_env = os.environ.get("OFFLINAI_MANIM_QUEUE_FRAMES")

    def encode(self, frame, num_frames):
        for _ in range(int(num_frames)):
            if block_after is not None and encoded[0] >= block_after:
                release.wait()
            real_encode(self, frame, 1)
            encoded[0] += 1
            if per_frame_delay:
                time.sleep(per_frame_delay)

    def open_(self, *a, **k):
        prev = getattr(self, "writer_thread", None)
        order.append(("open", bool(prev is not None and prev.is_alive())))
        r = real_open(self, *a, **k)
        clips.append({"path": str(self.partial_movie_file_path), "written": 0})
        return r

    def close_(self, *a, **k):
        r = real_close(self, *a, **k)
        t = getattr(self, "writer_thread", None)
        order.append(("closed", bool(t is not None and t.is_alive())))
        return r

    def write(self, frame_or_renderer, num_frames=1):
        r = real_write(self, frame_or_renderer, num_frames)
        if clips:
            clips[-1]["written"] += int(num_frames)
        return r

    SceneFileWriter.encode_and_write_frame = encode
    SceneFileWriter.open_partial_movie_stream = open_
    SceneFileWriter.close_partial_movie_stream = close_
    SceneFileWriter.write_frame = write
    threading.excepthook = lambda a: errors.append(f"{a.exc_type.__name__}: {a.exc_value}")
    if stall is not None:
        settings.encoder_stall_seconds = stall
    if queue is not None:
        os.environ["OFFLINAI_MANIM_QUEUE_FRAMES"] = str(queue)

    out = {"error": None, "clips": clips, "order": order, "thread_errors": errors}
    real_platform = sys.platform
    started = time.monotonic()
    try:
        with tempfile.TemporaryDirectory() as media, tempconfig({
            "pixel_width": 160, "pixel_height": 90, "frame_rate": 30,
            "media_dir": media, "disable_caching": True, "write_to_movie": True,
            "progress_bar": "none", "verbosity": "WARNING", "preview": False,
        }):
            scene = ThreeClips()
            out["writer"] = scene.renderer.file_writer
            if AS_IOS:
                sys.platform = "ios"
            try:
                scene.render()
            except BaseException as e:
                out["error"] = e
            finally:
                sys.platform = real_platform
                release.set()
            for c in clips:
                try:
                    c["in_file"] = frames_in(c["path"])
                except Exception as e:
                    c["in_file"] = f"{type(e).__name__}"
            movie = scene.renderer.file_writer.movie_file_path
            out["movie_frames"] = (frames_in(str(movie))
                                   if out["error"] is None and os.path.exists(movie) else None)
            # A stalled thread is let go above; give it a moment to finish
            # before the files go away.
            t = getattr(out["writer"], "writer_thread", None)
            if t is not None:
                t.join(timeout=10)
    finally:
        SceneFileWriter.encode_and_write_frame = real_encode
        SceneFileWriter.open_partial_movie_stream = real_open
        SceneFileWriter.close_partial_movie_stream = real_close
        SceneFileWriter.write_frame = real_write
        threading.excepthook = real_hook
        object.__setattr__(settings, "encoder_stall_seconds", saved_stall)
        object.__setattr__(settings, "_explicit", saved_explicit)
        if saved_env is None:
            os.environ.pop("OFFLINAI_MANIM_QUEUE_FRAMES", None)
        else:
            os.environ["OFFLINAI_MANIM_QUEUE_FRAMES"] = saved_env
    out["seconds"] = time.monotonic() - started
    return out


def frames_check(label, r):
    clips = r["clips"]
    check(f"{label}: every frame is in its own clip",
          clips and all(c.get("in_file") == c["written"] for c in clips),
          str([(c["written"], c.get("in_file")) for c in clips]))
    check(f"{label}: the final video has every frame",
          r["movie_frames"] == sum(c["written"] for c in clips),
          f'{r["movie_frames"]} vs {sum(c["written"] for c in clips)}')
    check(f"{label}: each clip opened only after the last one's thread exited",
          not any(alive for kind, alive in r["order"] if kind == "open"), str(r["order"]))
    check(f"{label}: no thread was left running at a clip's close",
          not any(alive for kind, alive in r["order"] if kind == "closed"), str(r["order"]))
    check(f"{label}: no writer thread raised", not r["thread_errors"], str(r["thread_errors"]))


print("== the stall window ==")
s = RenderSettings()
object.__setattr__(s, "encoder_stall_seconds", None)
check("1080p gets the base window", s.encoder_stall_window(1920, 1080)[0] == RenderSettings.STALL_SECONDS)
check("8K gets a longer one", s.encoder_stall_window(7680, 4320)[0] > s.encoder_stall_window(3840, 2160)[0])
check("but never past the ceiling",
      s.encoder_stall_window(15360, 8640)[0] == RenderSettings.STALL_SECONDS_MAX)
s.encoder_stall_seconds = 42
check("an explicit window wins", s.encoder_stall_window(7680, 4320) == (42, "set explicitly"))
s.encoder_stall_seconds = 0
check("zero means no limit", s.encoder_stall_window(7680, 4320)[0] == 0)
check("it survives a refresh", s.refresh().encoder_stall_seconds == 0)

print("\n== a normal render is unchanged ==")
r = render()
check("renders", r["error"] is None, repr(r["error"]))
frames_check("normal", r)

print("\n== a slow encoder is waited for while it keeps encoding ==")
# 0.3 s a frame, a 2 s stall window: each clip's close waits several seconds,
# longer than the window, and must not give up because frames keep coming.
r = render(per_frame_delay=0.3, stall=2, queue=32)
check("renders", r["error"] is None, repr(r["error"]))
frames_check("slow", r)
check("the wait outlasted the stall window", r["seconds"] > 10, f'{r["seconds"]:.1f} s')

if LONG:
    print("\n== a backlog past the old 60 s limit ==")
    r = render(per_frame_delay=2.2, stall=30, queue=32)
    check("renders", r["error"] is None, repr(r["error"]))
    frames_check("long", r)

print("\n== a stuck encoder fails the render cleanly ==")
r = render(block_after=10, stall=3, queue=32)
err = r["error"]
check("the render raises RuntimeError", isinstance(err, RuntimeError), repr(err))
check("saying the encoder made no progress", "made no progress" in str(err), str(err))
check("with the size", "160x90" in str(err), str(err))
check("and nothing touched a None", "NoneType" not in str(err) + str(r["thread_errors"]),
      str(r["thread_errors"]))
w = r["writer"]
check("the clip's container is left alone, not dropped",
      getattr(w, "video_container", None) is not None and getattr(w, "queue", None) is not None)

print("\n== a clip's thread can't outlive it ==")
w = SceneFileWriter.__new__(SceneFileWriter)
busy = threading.Event()
w.writer_thread = threading.Thread(target=busy.wait, daemon=True)
w.writer_thread.start()
try:
    SceneFileWriter.open_partial_movie_stream(w, file_path="unused.mp4")
    check("the next clip refuses to open while it runs", False, "it opened")
except RuntimeError as e:
    check("the next clip refuses to open while it runs", "still running" in str(e), str(e))
finally:
    busy.set()

# A host's Stop button may drain the queue, sentinel and all (ManimStudio's
# does). The thread must still finish once the clip is closing.
from queue import Queue
clip = sfw._ClipEncoding(Queue())
w = SceneFileWriter.__new__(SceneFileWriter)
t = threading.Thread(target=w.listen_and_write, args=(clip,), daemon=True)
t.start()
clip.closing.set()
t.join(timeout=5)
check("a drained queue still lets the thread exit at close", not t.is_alive())

print()
print(f"{PASSED} passed, {FAILED} failed")
if FAILED:
    raise SystemExit(1)
