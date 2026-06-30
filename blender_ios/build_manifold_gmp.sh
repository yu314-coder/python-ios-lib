#!/bin/bash
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Volumes/D/Xcode.app/Contents/Developer TMPDIR=/Volumes/D/tmp
PREFIX="$PWD/deps-install"; SDK=$(xcrun --sdk iphoneos --show-sdk-path)
plat() { otool -l "$1" 2>/dev/null | grep -A3 LC_BUILD_VERSION | grep platform | head -1 | awk '{print $2}'; }

echo "== manifold =="
rm -rf build/m4-manifold
cmake -S src/manifold-3.4.1 -B build/m4-manifold -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=OFF \
  -DMANIFOLD_TEST=OFF -DMANIFOLD_CBIND=OFF -DMANIFOLD_PYBIND=OFF -DMANIFOLD_CROSS_SECTION=OFF \
  -DMANIFOLD_PAR=NONE -DMANIFOLD_DOWNLOADS=OFF -DMANIFOLD_EXPORT=OFF > build/m4-manifold-cfg.log 2>&1 \
  && cmake --build build/m4-manifold -j4 > build/m4-manifold-b.log 2>&1 \
  && cmake --install build/m4-manifold > build/m4-manifold-i.log 2>&1 \
  && { f=$(find build/m4-manifold "$PREFIX" -name "libmanifold.a"|head -1); cp "$f" "$PREFIX/lib/" 2>/dev/null; echo "  libmanifold plat=$(plat "$PREFIX/lib/libmanifold.a")"; } \
  || { echo "  manifold FAIL"; grep -iE "error|could not find" build/m4-manifold-cfg.log build/m4-manifold-b.log | head -6; }

echo "== gmp (autotools) =="
cd src/gmp-6.3.0
make distclean >/dev/null 2>&1 || true
./configure --host=aarch64-apple-darwin --disable-shared --enable-static --prefix="$PREFIX" \
  CC="$(xcrun --find clang)" CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.4" \
  > "$PREFIX/../build/gmp-cfg.log" 2>&1 && make -j8 > "$PREFIX/../build/gmp-b.log" 2>&1 && make install > "$PREFIX/../build/gmp-i.log" 2>&1 \
  && echo "  libgmp plat=$(plat "$PREFIX/lib/libgmp.a")" || { echo "  gmp FAIL (will try --disable-assembly)"; \
     ./configure --host=aarch64-apple-darwin --disable-shared --enable-static --disable-assembly --prefix="$PREFIX" \
       CC="$(xcrun --find clang)" CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=16.4" > "$PREFIX/../build/gmp-cfg2.log" 2>&1 \
       && make -j8 > "$PREFIX/../build/gmp-b2.log" 2>&1 && make install > "$PREFIX/../build/gmp-i2.log" 2>&1 \
       && echo "  libgmp (no-asm) plat=$(plat "$PREFIX/lib/libgmp.a")" || { echo "  gmp FAIL2"; tail -5 "$PREFIX/../build/gmp-cfg2.log" "$PREFIX/../build/gmp-b2.log"; }; }
