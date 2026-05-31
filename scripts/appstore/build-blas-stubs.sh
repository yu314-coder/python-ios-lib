#!/bin/bash
# build-blas-stubs.sh — fix for python-ios-lib issue #2.
#
# scipy.linalg.cython_blas references the reference-BLAS helper `dcabs1`,
# which Apple's Accelerate framework does NOT export on iOS. On a real
# device dyld aborts importing scipy.signal/scipy.linalg with:
#
#     symbol not found in flat namespace '_dcabs1_'
#
# (`lsame` IS in Accelerate — it's two-level-bound and resolves fine; only
# the flat-namespace `dcabs1` is missing.)
#
# This builds a tiny libscipy_blas_stubs.dylib (dcabs1 / scabs1 / lsame —
# trivial scalar helpers, not real BLAS kernels) and adds an LC_LOAD_DYLIB
# to every cython_blas .so so the flat-namespace `_dcabs1_` resolves against
# it at runtime. Run from anywhere; re-run after rebuilding scipy.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/fortran/blas_compat_stubs.c"
OUT="$ROOT/Frameworks/scipy_aux/libscipy_blas_stubs.dylib"
MINOS="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
SIGN="${EXPANDED_CODE_SIGN_IDENTITY:--}"

mkdir -p "$(dirname "$OUT")"
xcrun -sdk iphoneos clang -target "arm64-apple-ios${MINOS}" -O2 -dynamiclib \
  -install_name @rpath/libscipy_blas_stubs.dylib "$SRC" -o "$OUT"
codesign -f -s "$SIGN" --timestamp=none "$OUT"
echo "built + signed $OUT"

# Add the LC_LOAD_DYLIB to every cython_blas .so (reuses the Mach-O helper
# from patch-cython-lapack.py), then re-sign them.
python3 - "$ROOT" "$SIGN" <<'PY'
import sys, importlib.util, glob, subprocess
from pathlib import Path
root, sign = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location('pcl', f'{root}/scripts/appstore/patch-cython-lapack.py')
pcl = importlib.util.module_from_spec(spec); spec.loader.exec_module(pcl)
name = '@rpath/libscipy_blas_stubs.dylib'
sos = glob.glob(f'{root}/**/scipy/linalg/cython_blas*.so', recursive=True)
for so in sos:
    p = Path(so)
    if pcl.has_load_dylib(p.read_bytes(), name):
        print(f"  {p.name}: LC_LOAD_DYLIB already present")
    elif pcl.add_load_dylib(p, name):
        print(f"  {p.name}: added LC_LOAD_DYLIB -> {name}")
        subprocess.run(['codesign', '-f', '-s', sign, '--timestamp=none', so], check=False)
if not sos:
    print("  (no cython_blas .so found under", root, ")")
PY
echo "done"
