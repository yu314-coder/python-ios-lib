# PyArrow on iOS — what's bundled here, and how it was built

**Status: BUILT and SHIPPING** (as of 2026-05-23). The `pyarrow/`
sibling directory is a working iOS arm64 cross-compiled
`pyarrow 15.0.2`. The `.so` files use the `cpython-314-iphoneos`
SOABI suffix that BeeWare's iOS `Python.framework` expects.

If you want to extend the build (add Parquet, Dataset, etc.) the
recipe below is what produced what's here. Staging tree at
`<repo>/pyarrow_ios/` is preserved for re-runs.

## What works at runtime

```python
import pyarrow as pa
t = pa.table({"x": [1, 2, 3], "y": ["a", "b", "c"]})
print(t)
# pyarrow.Table
# x: int64
# y: string

import pyarrow.csv as csv
csv.read_csv("file.csv")          # works
pa.compute.sum(t["x"])             # works (basic compute kernels)
pa.ipc.new_stream(buf, schema)     # works (Arrow IPC streaming)
```

## What is intentionally NOT built (and why)

| Component         | Why disabled |
|-------------------|--------------|
| Parquet           | Needs Thrift C++ + Snappy/ZLIB cross-compile |
| Dataset           | Pulls Parquet as transitive dep |
| Acero (query eng) | Hardcoded `arrow_acero_shared` link in pyarrow CMake, won't accept static |
| Flight            | gRPC dep — large, networking, low value on iPad |
| Gandiva           | LLVM JIT — Apple disallows runtime codegen on iOS |
| CUDA              | iOS doesn't expose CUDA |
| ORC               | Needs Protobuf cross-compile |
| S3 / GCS / HDFS   | Cloud filesystems — depend on AWS SDK / curl + dependencies |
| RE2 / UTF8PROC    | Bundled-source build paths use POSIX features iOS restricts |
| Snappy / LZ4 / ZSTD / BZip2 / Brotli | Compression libs — disabled to shrink first build |
| OpenSSL           | TLS / hashing — needs its own iOS cross-compile |
| jemalloc / mimalloc | Custom allocators using madvise flags iOS rejects |

To add any of these, build the corresponding upstream C library
for iOS arm64 first (separate cross-compile each), then re-run the
Arrow C++ configure with the matching `ARROW_*=ON` flag, then
rebuild pyarrow.

## How this build was produced

### 0. Prerequisites

- macOS host (Apple Silicon recommended for fastest build)
- Xcode 16+ with iOS SDK installed
- Homebrew CMake 4.x, Ninja, git
- BeeWare's `Python.xcframework` at the path shown below

### 1. Source

```sh
git clone --depth 1 --branch apache-arrow-15.0.2 \
  https://github.com/apache/arrow.git arrow
```

### 2. Patches applied (3 of them)

These are baked into the staging tree at
`pyarrow_ios/arrow/`. If you re-clone Arrow you must re-apply.

1. **`cpp/cmake_modules/BuildUtils.cmake`** — accept Apple's newer
   `cctools_ld-X.Y` libtool version string. Upstream is fixed in
   Arrow main; v15.0.2 needs the backport:
   ```cmake
   if(NOT "${LIBTOOL_V_OUTPUT}" MATCHES ".*(cctools|cctools_ld)-([0-9.]+).*")
   ```

2. **`cpp/cmake_modules/ThirdpartyToolchain.cmake`** — propagate
   iOS toolchain flags into the bundled-dep CMake sub-builds.
   Add these to `EP_COMMON_CMAKE_ARGS`:
   ```cmake
   -DCMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
   -DCMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}
   -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
   -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
   -DCMAKE_POLICY_VERSION_MINIMUM=3.5
   ```
   Without this, xsimd / zlib_ep / rapidjson_ep configure with
   host detection.

3. **pyarrow C++ NumPy-2 compat patches** in
   `python/pyarrow/src/arrow/python/`:
   ```
   numpy_convert.cc, numpy_to_arrow.cc, arrow_to_pandas.cc:
       descr->elsize       →  PyDataType_ELSIZE(descr)
       descr->c_metadata   →  PyDataType_C_METADATA(descr)
       descr->fields       →  PyDataType_FIELDS(descr)
   udf.cc:
       _Py_IsFinalizing()  →  Py_IsFinalizing()      (Python 3.14)
   ```

### 3. Build Arrow C++

```sh
cd arrow/cpp && mkdir build-ios && cd build-ios
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

cmake .. \
  -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
  -DCMAKE_INSTALL_PREFIX="$PWD/install" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DARROW_BUILD_SHARED=OFF -DARROW_BUILD_STATIC=ON \
  -DARROW_BUILD_TESTS=OFF -DARROW_BUILD_BENCHMARKS=OFF \
  -DARROW_BUILD_EXAMPLES=OFF -DARROW_BUILD_UTILITIES=OFF \
  -DARROW_DEPENDENCY_SOURCE=BUNDLED \
  -DARROW_PYTHON=ON -DARROW_COMPUTE=ON -DARROW_CSV=ON -DARROW_IPC=ON \
  -DARROW_JSON=OFF -DARROW_PARQUET=OFF -DARROW_DATASET=OFF \
  -DARROW_FLIGHT=OFF -DARROW_S3=OFF -DARROW_GANDIVA=OFF \
  -DARROW_HDFS=OFF -DARROW_ORC=OFF \
  -DARROW_WITH_RE2=OFF -DARROW_WITH_UTF8PROC=OFF \
  -DARROW_WITH_SNAPPY=OFF -DARROW_WITH_ZLIB=OFF \
  -DARROW_WITH_LZ4=OFF -DARROW_WITH_ZSTD=OFF \
  -DARROW_WITH_BZ2=OFF -DARROW_WITH_BROTLI=OFF \
  -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
  -DARROW_USE_OPENSSL=OFF \
  -DCMAKE_BUILD_TYPE=Release

ninja -j 10 && ninja install
```

Outputs `libarrow.a`, `libarrow_acero.a`, `libarrow_dataset.a`,
`libarrow_bundled_dependencies.a` plus headers under `install/`.
~20 min on M-series Mac.

### 4. Patch Arrow's installed Acero config

`ArrowAceroConfig.cmake` has a stale `find_dependency(Parquet)`
line that fires even when Parquet is off. Comment out:

```cmake
# find_dependency(Parquet)
```

### 5. Build pyarrow's Cython extensions

```sh
cd ../../python && mkdir build-ios && cd build-ios
ARROW_HOME=../../cpp/build-ios/install
PY_XCF=/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64
VPY=/Volumes/D/python-ios-lib/pyarrow_ios/.venv/bin/python
NP_INC=$($VPY -c 'import numpy; print(numpy.get_include())')

cmake .. \
  -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_FIND_ROOT_PATH="$ARROW_HOME;$IOS_SDK" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -DPYARROW_CPP_HOME="$ARROW_HOME" \
  -DArrow_DIR="$ARROW_HOME/lib/cmake/Arrow" \
  -DPYARROW_BUILD_ACERO=OFF -DPYARROW_BUILD_DATASET=OFF \
  -DPYARROW_BUILD_PARQUET=OFF -DPYARROW_BUILD_FLIGHT=OFF \
  -DPYARROW_BUILD_GANDIVA=OFF -DPYARROW_BUILD_CUDA=OFF \
  -DPYARROW_BUILD_ORC=OFF \
  -DPython3_EXECUTABLE="$VPY" \
  -DPython3_INCLUDE_DIR="$PY_XCF/Python.framework/Headers" \
  -DPython3_LIBRARY="$PY_XCF/Python.framework/Python" \
  -DPython3_NumPy_INCLUDE_DIR="$NP_INC" \
  -DCMAKE_SHARED_LINKER_FLAGS="-undefined dynamic_lookup" \
  -DCMAKE_MODULE_LINKER_FLAGS="-undefined dynamic_lookup" \
  -DCMAKE_BUILD_TYPE=Release

ninja -j 10
```

Outputs in `release/`:
* 8 Cython extension modules: `_compute`, `_csv`, `_feather`,
  `_fs`, `_hdfsio`, `_json`, `_pyarrow_cpp_tests`, `lib`
* 1 helper dylib: `libarrow_python.dylib`

### 6. Suffix rename + bundle assembly

The .so files come out as `*.cpython-314-darwin.so` because
the host venv Python set EXT_SUFFIX. Rename to the iOS
suffix that BeeWare's `_sysconfigdata__ios_arm64-iphoneos.py`
declares:

```sh
for f in *.cpython-314-darwin.so; do
  mv "$f" "${f%.cpython-314-darwin.so}.cpython-314-iphoneos.so"
done
```

Final bundle layout dropped into `Sources/PyArrow/pyarrow/`:

```
pyarrow/
├── __init__.py / __init__.pxd
├── *.py             (~80 pure-Python modules)
├── *.pxd / *.pxi    (Cython declarations)
├── *.cpython-314-iphoneos.so   (8 modules)
├── libarrow_python.dylib       (the iOS arm64 dylib, ~23 MB)
└── (no static/, no LICENSE — those live in the sdist tarball)
```

The `.so` files link `@rpath/libarrow_python.dylib` with rpath
`@loader_path`, which means as long as the dylib sits in the same
directory as the .so files (it does here), iOS dyld resolves it
at import time without any further wiring.

## Runtime caveats on iPad

- Apple's restriction on `dlopen` of arbitrary dylibs is
  satisfied because `libarrow_python.dylib` ships embedded in
  the app bundle and is found via rpath, not by absolute path.
- No fork(), no JIT, no exec() — pyarrow's core path doesn't
  hit any of these. Compute kernels are AOT-compiled into the
  static Arrow library.
- `pyarrow.parquet` will fail at `import pyarrow.parquet`
  (module doesn't exist). Same for `pyarrow.dataset`,
  `pyarrow.flight`, etc. Users get a clear ImportError, not a
  crash.
