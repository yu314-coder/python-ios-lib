# OpenCV (cv2) — 4.10.0 native iOS build

Real OpenCV 4.10.0 cross-compiled for iOS arm64 (recipe: `opencv_ios/`).
A **curated module set** — the modules that make sense headless on a phone.
`import cv2` reports 4.10.0; pip sees `opencv-python` (dist-info installed).

## What's in

`core`, `imgproc`, `imgcodecs`, `photo`, `features2d`, `calib3d`, `objdetect`,
`video` (tracking/optical flow — not file I/O), `ml`, `flann`. Image read/write,
filtering, geometric transforms, contours, feature detection/matching, camera
calibration, classic cascades, k-means/SVM/KNN.

## Gaps

| Module / feature | Status | Workaround |
|---|---|---|
| `cv2.dnn` | **Not built** — the DNN stack is large and duplicated by better on-device options | Use onnxruntime (CoreML EP) or torch for inference |
| `highgui` (`cv2.imshow`, `waitKey`) | Not built — no desktop windows on iOS | `cv2.imwrite(...)` and open in the preview |
| `videoio` (`VideoCapture`, `VideoWriter`) | Not built — desktop codec/camera stack | Decode/encode via bundled PyAV (`import av`, VideoToolbox H.264) |
| GPU (CUDA / OpenCL / `cv2.cuda`) | No CUDA/OpenCL on iOS; OpenCV has no Metal backend | CPU path uses NEON SIMD + GCD multi-core — fast in practice |
| `cv2.data` haarcascades path | Bundled — but resolve via `cv2.data.haarcascades` rather than hardcoded paths | — |

## Build gotchas (recipe notes)

- Apple `MacTypes.h` collides with OpenCV's `Point` / `Rect` / `Size` / `Ptr` /
  `nil` — fixed via `ocv_ios_mactypes_fix.h` force-include.
- The gen2 Python-binding generator's typing stubs trip on iOS paths — stubs
  generation is disabled (runtime module unaffected).

## See also
- [onnxruntime.md](onnxruntime.md) — DNN inference replacement
- [av-pyav.md](av-pyav.md) — video I/O replacement
