#!/bin/bash
# Cross-compile aiohttp 3.14.1 + its C/Cython deps (multidict, yarl,
# frozenlist, propcache) for iOS arm64 (cpython-314-iphoneos), adapting the
# psutil_ios recipe: host Python 3.14 + iOS sysconfigdata override + iphoneos
# clang. Cython 3.x comes from ./buildenv (host's system Cython is 0.29, too old).
#
# Usage: build_aiohttp.sh [pkg-dir ...]   (no args = build all)
set -uo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
PY_XCF="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64"
PY_HDRS="$PY_XCF/Python.framework/Headers"
PY_SYSCONFIG="$PY_XCF/platform-config/arm64-iphoneos"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CLANG="$(xcrun --sdk iphoneos --find clang)"
STRIP="$(xcrun --sdk iphoneos --find strip)"
PYBIN="$ROOT/buildenv/bin/python"

export IPHONEOS_DEPLOYMENT_TARGET=13.0
export PKG_CONFIG=/usr/bin/false
export CC="$IOS_CLANG"
# Bake the iOS SDK + arch + Python headers into CXX: distutils injects env
# CFLAGS only into the C compile path, not the C++ one, so a C++ extension
# (frozenlist's _frozenlist.cpp) would otherwise miss -isysroot / -I$PY_HDRS
# and fail with "Python.h not found".
export CXX="$(xcrun --sdk iphoneos --find clang++) -arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -I$PY_HDRS"
export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata__ios_arm64-iphoneos"
export _PYTHON_HOST_PLATFORM="ios-13.0-arm64"
export PYTHONDONTWRITEBYTECODE=1

PKGS=("$@")
if [ ${#PKGS[@]} -eq 0 ]; then
  PKGS=(multidict-6.7.1 propcache-0.5.2 frozenlist-1.8.0 yarl-1.24.2 aiohttp-3.14.1)
fi

build_one() {
  local SRC="$ROOT/src/$1"
  [ -d "$SRC" ] || { echo "  !! missing $SRC"; return 1; }
  echo "=================  $1  ================="
  rm -f "$SRC/Python.framework"; ln -sf "$PY_XCF/Python.framework" "$SRC/Python.framework"
  export CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -I$PY_HDRS -Wno-error=implicit-function-declaration"
  export LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=13.0 -F$SRC"
  export PYTHONPATH="$PY_SYSCONFIG"
  local rc
  if [ -f "$SRC/setup.py" ]; then
    # Legacy setup.py packages (multidict, aiohttp).
    ( cd "$SRC" && rm -rf build && "$PYBIN" setup.py build_ext --inplace ) \
        > "/tmp/aiohttp_build_$1.log" 2>&1
    rc=$?
  else
    # PEP 517 / pyproject-only packages with a custom cythonize backend
    # (propcache, frozenlist, yarl) — no setup.py. Build a wheel without
    # isolation (uses buildenv's Cython 3.x + our cross env) and unpack the
    # compiled .so back into the source tree so the collection step is uniform.
    rm -rf "$SRC/_wheel"
    ( cd "$SRC" && "$ROOT/buildenv/bin/pip" wheel --no-build-isolation --no-deps -w _wheel . ) \
        > "/tmp/aiohttp_build_$1.log" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
      local whl; whl="$(ls "$SRC"/_wheel/*.whl 2>/dev/null | head -1)"
      if [ -n "$whl" ]; then ( cd "$SRC" && unzip -o "$whl" '*.so' -d . >/dev/null 2>&1 ); else rc=1; fi
    fi
  fi
  if [ $rc -ne 0 ]; then
    echo "  BUILD FAILED (rc=$rc) — tail of log:"; tail -18 "/tmp/aiohttp_build_$1.log"; return 1
  fi
  # strip + report
  local n=0
  while IFS= read -r so; do
    "$STRIP" -S -x "$so" 2>/dev/null
    echo "  built: ${so#$SRC/}  [$(file -b "$so" | cut -d, -f1-2)]"
    n=$((n+1))
  done < <(find "$SRC" -name "*.cpython-314-iphoneos.so")
  [ $n -gt 0 ] && echo "  OK ($n .so)" || { echo "  !! no iphoneos .so produced"; return 1; }
}

fail=0
for p in "${PKGS[@]}"; do build_one "$p" || fail=1; done
echo ""; echo "=== DONE (fail=$fail) ==="
exit $fail
