#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JPEG_VERSION=3.1.4.1
JPEG_SHA256=ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022
JPEG_ROOT="$PROJECT_ROOT/.build/jpeg"
if [ -f "$JPEG_ROOT/lib/libjpeg.a" ] && [ -f "$JPEG_ROOT/include/jpeglib.h" ] \
    && [ "$(cat "$JPEG_ROOT/version" 2>/dev/null)" = "$JPEG_VERSION" ]; then
    exit 0
fi
CMAKE_BIN="${EXIFMARK_CMAKE:-cmake}"
if ! command -v "$CMAKE_BIN" >/dev/null 2>&1; then
    printf '%s\n' '构建JPEG系数拼接库需要CMake；可用EXIFMARK_CMAKE指定路径。' >&2
    exit 1
fi
mkdir -p "$JPEG_ROOT"
JPEG_ARCHIVE="$JPEG_ROOT/libjpeg-turbo-$JPEG_VERSION.tar.gz"
if [ ! -f "$JPEG_ARCHIVE" ]; then
    curl --fail --location --retry 2 \
        "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VERSION/libjpeg-turbo-$JPEG_VERSION.tar.gz" \
        -o "$JPEG_ARCHIVE.download"
    mv "$JPEG_ARCHIVE.download" "$JPEG_ARCHIVE"
fi
printf '%s  %s\n' "$JPEG_SHA256" "$JPEG_ARCHIVE" | shasum -a 256 -c -
tar -xzf "$JPEG_ARCHIVE" -C "$JPEG_ROOT"
JPEG_SOURCE="$JPEG_ROOT/libjpeg-turbo-$JPEG_VERSION"
for architecture in arm64 x86_64; do
    "$CMAKE_BIN" -S "$JPEG_SOURCE" -B "$JPEG_ROOT/$architecture" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$architecture" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
        -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF
    "$CMAKE_BIN" --build "$JPEG_ROOT/$architecture" --target jpeg-static --parallel
done
mkdir -p "$JPEG_ROOT/include" "$JPEG_ROOT/lib"
cp "$JPEG_SOURCE/src/jpeglib.h" "$JPEG_SOURCE/src/jmorecfg.h" "$JPEG_SOURCE/src/jerror.h" \
    "$JPEG_ROOT/arm64/jconfig.h" "$JPEG_ROOT/include/"
lipo -create "$JPEG_ROOT/arm64/libjpeg.a" "$JPEG_ROOT/x86_64/libjpeg.a" \
    -output "$JPEG_ROOT/lib/libjpeg.a"
printf '%s\n' "$JPEG_VERSION" > "$JPEG_ROOT/version"
