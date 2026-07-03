#!/bin/zsh
# build_gltf_bridges.sh — cross-compile Blender's glTF Draco + MeshOptimizer
# bridge dylibs for iOS arm64, so io_scene_gltf2 can do compressed glTF on device.
#
# Prereqs (already produced by the main blender_ios dep build):
#   deps-install/lib/libdraco.a            (arm64 iphoneos static)
#   deps-install/lib/libmeshoptimizer.a    (arm64 iphoneos static)
#   deps-install/include/{draco,meshoptimizer.h}
# Bridge sources live in blender/intern/{draco_bridge,meshoptimizer_bridge}.
#
# Output → ../Frameworks/gltf_bridges/*.dylib (Xcode's Install-Python phase
# copies them into the app Frameworks/, wrap-loose-dylibs.sh wraps them
# App-Store-safe, and io_scene_gltf2/io/com/library.py resolves them on iOS).
set -e
B="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="$B/../Frameworks/gltf_bridges"; mkdir -p "$OUT"
CC=(xcrun --sdk iphoneos clang++ -target arm64-apple-ios16.4 -isysroot "$SDK" -std=c++17 -O2 -w)

echo "→ draco bridge"
"${CC[@]}" \
  -I "$B/blender/intern/draco_bridge" -I "$B/deps-install/include" \
  "$B/blender/intern/draco_bridge/intern/"{common,decoder,encoder}.cpp \
  "$B/deps-install/lib/libdraco.a" \
  -dynamiclib -install_name @rpath/libbf_intern_draco_bridge.framework/libbf_intern_draco_bridge \
  -o "$OUT/libbf_intern_draco_bridge.dylib"

echo "→ meshoptimizer bridge"
"${CC[@]}" \
  -I "$B/blender/intern/meshoptimizer_bridge" -I "$B/deps-install/include" \
  "$B/blender/intern/meshoptimizer_bridge/intern/"{common,decoder,encoder}.cpp \
  "$B/deps-install/lib/libmeshoptimizer.a" \
  -dynamiclib -install_name @rpath/libbf_intern_meshopt_bridge.framework/libbf_intern_meshopt_bridge \
  -o "$OUT/libbf_intern_meshopt_bridge.dylib"

echo "done:"; ls -la "$OUT"/*.dylib
