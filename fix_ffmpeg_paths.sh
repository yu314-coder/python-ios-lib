#!/bin/bash
# Fix PyAV .so files to find ffmpeg dylibs in the app bundle
# This creates symlinks and framework bundles for ffmpeg libs
set -e

FFMPEG_DIR="$PROJECT_DIR/Frameworks/ffmpeg"
AV_DIR="$PROJECT_DIR/app_packages/site-packages/av"

if [ ! -d "$FFMPEG_DIR" ]; then
    echo "No ffmpeg dir found, skipping"
    exit 0
fi

echo "Fixing ffmpeg paths for PyAV..."

# Create symlinks with short names
cd "$FFMPEG_DIR"
for lib in libav*.dylib libsw*.dylib; do
    # Extract short name: libavcodec.62.29.101.dylib -> libavcodec.62.dylib
    short=$(echo "$lib" | sed 's/\([0-9]*\)\.[0-9]*\.[0-9]*\.dylib/\1.dylib/')
    if [ "$lib" != "$short" ] && [ ! -e "$short" ]; then
        ln -sf "$lib" "$short"
        echo "  Symlink: $short -> $lib"
    fi
done

# Rewrite install names in all PyAV .so files
if [ -d "$AV_DIR" ]; then
    find "$AV_DIR" -name "*.so" | while read so; do
        for oldpath in $(otool -L "$so" 2>/dev/null | grep '/tmp/ffmpeg-ios' | awk '{print $1}'); do
            libname=$(basename "$oldpath")
            newpath="@rpath/$libname"
            install_name_tool -change "$oldpath" "$newpath" "$so" 2>/dev/null || true
            echo "  Fixed: $(basename $so): $libname"
        done
    done
fi

echo "ffmpeg paths fixed"
