#!/usr/bin/env bash
# ============================================================================
# build_core_ios.sh — cross-build faiss CPU core (libfaiss.a) for iOS arm64.
# ----------------------------------------------------------------------------
# Full module, CPU-only, lean. iOS has no libomp, so OpenMP is replaced by a
# serial omp.h shim (pthread-backed locks → thread-safe; #pragma omp compiles
# serial). BLAS/LAPACK = Apple Accelerate (same as scipy). Generic opt level
# (no x86 avx2/avx512, no SVE). Bindings are a separate step.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
SRC="$ROOT/faiss-1.9.0"
MINVER="13.0"

# ---- omp.h shim: serial OpenMP, real (pthread) locks ----------------------
SHIM="$ROOT/omp_shim"
mkdir -p "$SHIM"
cat > "$SHIM/omp.h" <<'OMP'
#ifndef FAISS_IOS_OMP_SHIM_H
#define FAISS_IOS_OMP_SHIM_H
/* Serial OpenMP shim for iOS (no libomp). #pragma omp lines compile serial;
   the few omp_* API calls faiss uses are provided here. Locks are real
   (pthread) so faiss stays thread-safe if called from multiple threads. */
#include <pthread.h>
typedef pthread_mutex_t omp_lock_t;
#ifdef __cplusplus
extern "C" {
#endif
static inline int  omp_get_max_threads(void) { return 1; }
static inline int  omp_get_num_threads(void) { return 1; }
static inline int  omp_get_thread_num(void)  { return 0; }
static inline int  omp_in_parallel(void)     { return 0; }
static inline void omp_set_num_threads(int n){ (void)n; }
static inline int  omp_get_nested(void)      { return 0; }
static inline void omp_set_nested(int n)     { (void)n; }
static inline double omp_get_wtime(void)     { return 0.0; }
static inline void omp_init_lock(omp_lock_t* l)    { pthread_mutex_init(l, 0); }
static inline void omp_destroy_lock(omp_lock_t* l) { pthread_mutex_destroy(l); }
static inline void omp_set_lock(omp_lock_t* l)     { pthread_mutex_lock(l); }
static inline void omp_unset_lock(omp_lock_t* l)   { pthread_mutex_unlock(l); }
#ifdef __cplusplus
}
#endif
#endif
OMP

# ---- patch out the hard OpenMP requirement (idempotent) -------------------
CM="$SRC/faiss/CMakeLists.txt"
if grep -q "find_package(OpenMP REQUIRED)" "$CM"; then
  sed -i '' \
    -e 's/find_package(OpenMP REQUIRED)/# OpenMP disabled for iOS (serial omp.h shim)/' \
    -e '/OpenMP::OpenMP_CXX/d' "$CM"
  echo "[faiss] patched OpenMP requirement out of faiss/CMakeLists.txt"
fi

# ---- configure for iphoneos arm64 -----------------------------------------
BUILD="$ROOT/build-ios"
rm -rf "$BUILD"; mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINVER" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF \
  -DFAISS_ENABLE_GPU=OFF \
  -DFAISS_ENABLE_PYTHON=OFF \
  -DFAISS_ENABLE_C_API=OFF \
  -DFAISS_OPT_LEVEL=generic \
  -DBUILD_TESTING=OFF \
  -DBLA_VENDOR=Apple \
  -DCMAKE_CXX_FLAGS="-I$SHIM -Wno-unknown-pragmas -Wno-unused-command-line-argument" \
  >/tmp/faiss_cmake.log 2>&1 || { echo "CONFIGURE FAILED:"; tail -25 /tmp/faiss_cmake.log; exit 1; }
echo "[faiss] configured. BLAS found:"; grep -iE "Found BLAS|Accelerate|BLAS_LIB" /tmp/faiss_cmake.log | head

# ---- build just the generic core target -----------------------------------
ninja -C "$BUILD" faiss

LIB="$(find "$BUILD" -name 'libfaiss.a' | head -1)"
echo "========================================================"
echo "[faiss] core lib: $LIB"
[ -n "$LIB" ] || { echo "FATAL: libfaiss.a not built"; exit 1; }
echo "--- size ---"; du -h "$LIB" | cut -f1
echo "--- arch/platform of a member object ---"
file "$LIB" | head -1
echo "[faiss] CORE DONE"
