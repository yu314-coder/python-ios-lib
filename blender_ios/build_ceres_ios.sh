#!/bin/bash
# Cross-compile ceres-solver 2.2.0 for iOS arm64 (static) so Blender's libmv can
# link it -> WITH_LIBMV -> motion tracking / camera solver.
#
# Notes:
#  - Builds against the SAME Eigen Blender uses (deps-install/include/eigen3 +
#    share/eigen3/cmake/Eigen3Config.cmake) so there is no Eigen ABI clash with
#    libmv. ceres 2.2 needs Eigen >= 3.3.
#  - ceres auto-forces MINIGLOG for iOS (no external glog/gflags needed).
#  - SuiteSparse/CXSparse/LAPACK/CUDA all OFF: libmv only needs the dense +
#    EIGENSPARSE solvers, and those extra deps aren't built for iOS.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"

IOS=(
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX"
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF
)

# Blender ships Eigen reporting version 5.0.1; ceres 2.2's `find_package(Eigen3 3.3
# REQUIRED)` SameMajor-rejects a major-5 Eigen. Drop the version constraint so ceres
# builds against the SAME Eigen libmv uses (no ABI clash). Idempotent.
CERES_CML=src/ceres-solver-2.2.0/CMakeLists.txt
if grep -q 'find_package(Eigen3 3.3 REQUIRED)' "$CERES_CML"; then
  sed -i '' 's/find_package(Eigen3 3.3 REQUIRED)/find_package(Eigen3 REQUIRED)  # iOS: accept Eigen 5.0.1/' "$CERES_CML"
  echo "  patched ceres Eigen version constraint"
fi

rm -rf build/ceres-ios
cmake -S src/ceres-solver-2.2.0 -B build/ceres-ios -G Ninja "${IOS[@]}" \
  -DIOS_DEPLOYMENT_TARGET=16.4 -DIOS_PLATFORM=OS \
  -DBUILD_TESTING=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_EXAMPLES=OFF \
  -DPROVIDE_UNINSTALL_TARGET=OFF \
  -DUSE_CUDA=OFF -DGFLAGS=OFF -DMINIGLOG=ON \
  -DSUITESPARSE=OFF -DCXSPARSE=OFF -DACCELERATESPARSE=OFF -DLAPACK=OFF \
  -DEIGENSPARSE=ON -DSCHUR_SPECIALIZATIONS=OFF

cmake --build build/ceres-ios -j8
cmake --install build/ceres-ios

echo "=== ceres installed ==="
ls -la "$PREFIX"/lib/libceres*.a 2>/dev/null
echo "  platform: $(otool -l "$PREFIX"/lib/libceres.a 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}') (2=iOS)"
