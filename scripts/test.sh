#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/swift-cache"
"$PROJECT_ROOT/scripts/prepare-jpeg.sh"
swift run --package-path "$PROJECT_ROOT/renderer" --scratch-path "$PROJECT_ROOT/.build/tests" \
    --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config" \
    --security-path "$PROJECT_ROOT/.build/security" --disable-sandbox exifmark-validate
LUA_BIN="${EXIFMARK_LUA:-lua}"
if command -v "$LUA_BIN" >/dev/null 2>&1; then
    "$LUA_BIN" "$PROJECT_ROOT/tests/plugin-tests.lua" "$PROJECT_ROOT"
else
    printf '%s\n' 'Lua测试需要Lua5.1。通过EXIFMARK_LUA指定解释器路径。' >&2
    exit 1
fi
python3 "$PROJECT_ROOT/tests/cli-tests.py"
if [ -f "$PROJECT_ROOT/dist/exifmark-0.1.0-macos.zip" ]; then
    python3 "$PROJECT_ROOT/tests/package-tests.py"
fi
