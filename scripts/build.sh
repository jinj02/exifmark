#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/swift-cache"
mkdir -p "$PROJECT_ROOT/exifmark.lrplugin/bin" "$PROJECT_ROOT/.build"

for architecture in arm64 x86_64; do
    swift build --package-path "$PROJECT_ROOT/renderer" \
        --scratch-path "$PROJECT_ROOT/.build/$architecture" \
        --cache-path "$PROJECT_ROOT/.build/cache" \
        --config-path "$PROJECT_ROOT/.build/config" \
        --security-path "$PROJECT_ROOT/.build/security" \
        --triple "$architecture-apple-macosx13.0" \
        --disable-sandbox --configuration release --product exifmark-render
done

lipo -create \
    "$PROJECT_ROOT/.build/arm64/arm64-apple-macosx/release/exifmark-render" \
    "$PROJECT_ROOT/.build/x86_64/x86_64-apple-macosx/release/exifmark-render" \
    -output "$PROJECT_ROOT/exifmark.lrplugin/bin/exifmark-render"
cp -R "$PROJECT_ROOT/.build/arm64/arm64-apple-macosx/release/ExifmarkRenderer_ExifmarkCore.bundle" \
    "$PROJECT_ROOT/exifmark.lrplugin/bin/"
codesign --force --sign - --timestamp=none "$PROJECT_ROOT/exifmark.lrplugin/bin/exifmark-render"
"$PROJECT_ROOT/exifmark.lrplugin/bin/exifmark-render" --version
lipo -info "$PROJECT_ROOT/exifmark.lrplugin/bin/exifmark-render"
