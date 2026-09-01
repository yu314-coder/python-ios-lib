"""
manim_encoder_test.py — the VideoToolbox encoder choice behind high-resolution
manim renders, in the same style as manim_test.py.

Run from the in-app shell:

    python manim_encoder_test.py

Why this exists. ffmpeg's `h264_videotoolbox` binds Apple's *hardware* H.264
encoder and nothing else, so above the size that encoder supports
`avcodec_open2` fails and the render falls back to software mpeg4 — slow, and
a visibly worse file. Where that ceiling sits is a property of the media
engine, not the OS: an M3/M4 stops at 4096x2304 while the newest iPhones go
higher. So the encoder is chosen by asking VideoToolbox at run time.

Three things have to hold, and each was wrong at some point:
  1. Above the H.264 hardware ceiling, HEVC is chosen instead.
  2. The partial files are tagged `hvc1`; ffmpeg's default `hev1` is legal and
     AVFoundation refuses to play it.
  3. The tag survives the concatenation that joins the partials, which copies
     streams from a template and does *not* carry the tag across by itself.
"""
from __future__ import annotations

import os
import sys
import tempfile

PASSED = 0
FAILED = 0


def check(label, ok, detail=""):
    global PASSED, FAILED
    if ok:
        PASSED += 1
        print(f"  PASS  {label}")
    else:
        FAILED += 1
        print(f"  FAIL  {label}  {detail}")


print("== the encoder is chosen by asking, not by assuming ==")
try:
    from manim.utils.ios_encoder import videotoolbox_codec, hardware_h264_available
except Exception as exc:                                   # pragma: no cover
    print(f"  FAIL  import manim.utils.ios_encoder  {type(exc).__name__}: {exc}")
    raise SystemExit(1)

# 1080p is inside every Apple media engine's H.264 range.
codec, tag = videotoolbox_codec(1920, 1080)
check("1080p uses H.264", codec == "h264_videotoolbox", codec)
check("and needs no tag", tag is None, str(tag))

# Whatever this device's ceiling is, the choice has to agree with the probe.
for w, h in [(3840, 2160), (5120, 2880), (7680, 4320)]:
    codec, tag = videotoolbox_codec(w, h)
    hw = hardware_h264_available(w, h)
    expected = "h264_videotoolbox" if hw else "hevc_videotoolbox"
    check(f"{w}x{h}: {'H.264 hardware' if hw else 'no H.264 hardware'} -> {expected}",
          codec == expected, f"chose {codec}")
    check(f"{w}x{h}: HEVC is tagged, H.264 is not",
          (tag == "hvc1") if codec.startswith("hevc") else (tag is None), str(tag))

print("\n== a file written that way is playable ==")
try:
    import av
    import numpy as np
except Exception as exc:
    print(f"  SKIP  PyAV/numpy unavailable ({type(exc).__name__}: {exc})")
else:
    # Small, so this runs in seconds; the codec choice is what is under test,
    # not the throughput.
    W, H = 7680, 4320
    codec, tag = videotoolbox_codec(W, H)
    tmp = tempfile.mkdtemp(prefix="manim-enc-")
    parts = []
    ok_write = True
    try:
        for k in range(2):
            path = os.path.join(tmp, f"part_{k}.mp4")
            container = av.open(path, mode="w")
            stream = container.add_stream(codec, rate=30,
                                          options={"realtime": "1", "g": "30"})
            stream.pix_fmt = "yuv420p"
            stream.width, stream.height = W, H
            if tag:
                stream.codec_tag = tag
            frame = np.zeros((H, W, 3), dtype=np.uint8)
            for i in range(2):
                frame[:, :, k] = (i * 40) % 255
                for packet in stream.encode(av.VideoFrame.from_ndarray(frame, format="rgb24")):
                    container.mux(packet)
            for packet in stream.encode():
                container.mux(packet)
            container.close()
            parts.append(path)
    except Exception as exc:
        ok_write = False
        check(f"{W}x{H} encodes with {codec}", False, f"{type(exc).__name__}: {exc}")

    if ok_write:
        check(f"{W}x{H} encodes with {codec}", True)

        listing = os.path.join(tmp, "parts.txt")
        with open(listing, "w") as fh:
            fh.write("".join(f"file '{p}'\n" for p in parts))

        # Exactly what SceneFileWriter.combine_files does for the mp4 path.
        combined = os.path.join(tmp, "combined.mp4")
        source = av.open(listing, options={"safe": "0"}, format="concat")
        in_stream = source.streams.video[0]
        out = av.open(combined, mode="w")
        out_stream = out.add_stream_from_template(template=in_stream)
        name = (getattr(out_stream.codec_context, "name", "") or "").lower()
        if "hevc" in name or "265" in name:
            out_stream.codec_tag = "hvc1"
        for packet in source.demux(in_stream):
            if packet.dts is None:
                continue
            packet.dts = None
            packet.stream = out_stream
            out.mux(packet)
        out.close()
        source.close()

        played = av.open(combined)
        vstream = played.streams.video[0]
        frames = sum(1 for _ in played.decode(video=0))
        final_tag = getattr(vstream, "codec_tag", None)
        played.close()

        check("the combined file keeps its size",
              (vstream.codec_context.width, vstream.codec_context.height) == (W, H),
              f"{vstream.codec_context.width}x{vstream.codec_context.height}")
        check("the combined file decodes", frames > 0, f"{frames} frames")
        if codec.startswith("hevc"):
            # `hev1` here is the failure that produced a finished render the
            # device could not open.
            check("the combined file is tagged hvc1, not hev1",
                  final_tag == "hvc1", repr(final_tag))

    for path in parts:
        try:
            os.remove(path)
        except OSError:
            pass

print(f"\n{PASSED} passed, {FAILED} failed")
raise SystemExit(1 if FAILED else 0)
