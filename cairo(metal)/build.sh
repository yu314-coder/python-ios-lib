#!/usr/bin/env bash
# ============================================================================
# build.sh -- CairoMetal one-shot build + render
# ----------------------------------------------------------------------------
# Does the three things a fresh checkout needs, in order:
#
#   1. swift build                       -- compiles the library via SwiftPM
#                                           (the canonical build).
#   2. xcrun -sdk macosx metal/metallib  -- compiles shaders/*.metal into a
#                                           default.metallib (SwiftPM cannot
#                                           compile .metal on the command line;
#                                           it only copies the source).
#   3. ./build/demo                      -- builds + runs the smoke-test demo
#                                           (via the Makefile), which renders
#                                           build/demo.png through the public
#                                           C API on a real Metal device.
#
# This mirrors exactly what .github/workflows/build.yml runs in CI.
#
# Usage:
#   ./build.sh                 build everything + render build/demo.png
#   ./build.sh --no-run        build the lib + metallib + demo, do not run it
#   ./build.sh --clean         remove .build/ and build/ first, then do all
#
# Requires: a macOS host with Xcode / the Command Line Tools (clang, swift) and
# the Metal toolchain (`xcrun -sdk macosx -f metal` must resolve). Rendering the
# demo additionally requires a usable Metal device (any Mac from the last decade;
# a headless CI runner with a GPU works, a pure VM without one will fail at the
# *run* step only -- the build steps still pass).
# ============================================================================
set -euo pipefail

# Resolve the package root (this script's directory) so the script works no
# matter what the caller's CWD is -- the folder name has parentheses, which is
# exactly why we never rely on a relative path here.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUN_DEMO=1
DO_CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --no-run) RUN_DEMO=0 ;;
    --clean)  DO_CLEAN=1 ;;
    -h|--help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *)
      echo "build.sh: unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

note() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ----------------------------------------------------------------------------
# 0. Preflight: confirm the toolchain is present before doing any work.
# ----------------------------------------------------------------------------
note "Toolchain"
xcrun --version
swift --version
echo "metal:    $(xcrun -sdk macosx -f metal)"
echo "metallib: $(xcrun -sdk macosx -f metallib)"

if [[ "$DO_CLEAN" == "1" ]]; then
  note "Clean (.build/ and build/)"
  rm -rf .build build
  make clean >/dev/null 2>&1 || true
fi

# ----------------------------------------------------------------------------
# 1. SwiftPM build -- the canonical way the library is consumed.
# ----------------------------------------------------------------------------
note "swift build (SwiftPM -- canonical library build)"
swift build

# ----------------------------------------------------------------------------
# 2. Compile the Metal shaders into build/default.metallib.
#    SwiftPM ships shaders/*.metal as *resources* (it has no command-line rule
#    to compile .metal); the runtime can compile them on demand, but for the
#    CLI/demo path we precompile a real metallib so cm_device.m can load it
#    directly via $CM_METALLIB. We drive this through the Makefile's `metallib`
#    target so there is a single source of truth for the metal invocation.
# ----------------------------------------------------------------------------
note "Compile shaders -> build/default.metallib (xcrun metal + metallib)"
make metallib
ls -la build/default.metallib

# ----------------------------------------------------------------------------
# 3. Build (and optionally run) the demo smoke test.
#    The Makefile links the static lib + frameworks into build/demo. `make run`
#    exports CM_METALLIB=<abs path to build/default.metallib> so the demo finds
#    the shaders outside an app bundle, then renders build/demo.png.
# ----------------------------------------------------------------------------
if [[ "$RUN_DEMO" == "1" ]]; then
  note "Build + run demo (renders build/demo.png)"
  make run
  if [[ -f build/demo.png ]]; then
    note "Done"
    echo "Rendered: $SCRIPT_DIR/build/demo.png"
    # `file` is informative but never fatal.
    file build/demo.png || true
  else
    echo "build.sh: demo ran but build/demo.png was not produced" >&2
    exit 1
  fi
else
  note "Build demo (not running it: --no-run)"
  make demo
  note "Done"
  echo "Built: $SCRIPT_DIR/build/demo (not run)"
fi
