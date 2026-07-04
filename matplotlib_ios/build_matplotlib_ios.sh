#!/bin/zsh
# build_matplotlib_ios.sh — cross-compile REAL matplotlib (+ kiwisolver,
# contourpy) for iOS arm64 against the BeeWare CPython 3.14 xcframework.
#
# Proven fixes baked in (each cost a failed build to find):
#   * ARCHFLAGS=-arch arm64      — host python is universal2; without this
#     setuptools adds -arch x86_64 and the arm64-only pyconfig.h explodes.
#   * cross-file [binaries] pkg-config + python — meson cross builds can't
#     find header-only pybind11 (pkgconfig) or a python with meson-python
#     installed for the target machine otherwise.
#   * -Dmacosx=false             — mpl otherwise wants an ObjC compiler to
#     build the AppKit GUI backend, which iOS must not link.
#   * vendored FreeType + qhull  — mpl's default meson subprojects; keeps the
#     build self-contained (no system deps).
#
# Output wheels land in src/wheels/. Install step: unzip into
# app_packages/site-packages and rename *.cpython-314-darwin.so →
# *.cpython-314-iphoneos.so (device EXT_SUFFIX; matches sklearn convention).
# The plotly shim lives on at site-packages/_mpl_plotly_shim/ — select it per
# run with CODEBENCH_MPL_BACKEND=plotly. Interactive figures: sitecustomize
# switches real mpl to the WebAgg backend (tornado is bundled) and serves
# figures at 127.0.0.1:<port> into the CodeBench preview;
# CODEBENCH_MPL_INTERACTIVE=0 restores plain PNG output.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"; VENV="$HERE/buildenv"; CF="$HERE/ios-cross.ini"
BIN=/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/bin
PYHDR=/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/Python.framework/Headers

[ -d "$VENV" ] || {
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q meson-python meson ninja pybind11 cppy \
      setuptools_scm 'setuptools>=64' wheel 'numpy==2.3.5'   # match device numpy minor
}
PCDIR=$("$VENV/bin/python" -m pybind11 --pkgconfigdir)
mkdir -p "$SRC" && cd "$SRC"
[ -f matplotlib-3.11.0.tar.gz ] || "$VENV/bin/pip" download --no-deps --no-binary :all: \
    matplotlib==3.11.0 contourpy kiwisolver
for t in *.tar.gz; do tar xzf "$t"; done

echo "→ kiwisolver (setuptools C++)"
( cd kiwisolver-*/ && ARCHFLAGS="-arch arm64" \
  CC="$BIN/arm64-apple-ios-clang" CXX="$BIN/arm64-apple-ios-clang++" \
  LDSHARED="$BIN/arm64-apple-ios-clang++ -bundle -undefined dynamic_lookup" \
  CFLAGS="-I$PYHDR -mios-version-min=13.0" CPPFLAGS="-I$PYHDR -mios-version-min=13.0" \
  LDFLAGS="-mios-version-min=13.0" \
  "$VENV/bin/pip" wheel . --no-build-isolation --no-deps -w ../wheels )

echo "→ contourpy (meson cross)"
PKG_CONFIG_PATH="$PCDIR" "$VENV/bin/pip" wheel ./contourpy-*/ \
  --no-build-isolation --no-deps -w wheels \
  --config-settings=setup-args=--cross-file="$CF"

echo "→ matplotlib (meson cross, vendored freetype+qhull, no AppKit backend)"
PKG_CONFIG_PATH="$PCDIR" "$VENV/bin/pip" wheel ./matplotlib-*/ \
  --no-build-isolation --no-deps -w wheels \
  --config-settings=setup-args=--cross-file="$CF" \
  --config-settings=setup-args=-Dmacosx=false

echo "done:"; ls -la wheels/
