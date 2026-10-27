#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUA_ROOT="$PROJECT_ROOT/.build/lua-5.1.5"
LUA_ARCHIVE="$PROJECT_ROOT/.build/lua-5.1.5.tar.gz"
if [ ! -x "$LUA_ROOT/src/lua" ]; then
    mkdir -p "$PROJECT_ROOT/.build"
    if [ ! -f "$LUA_ARCHIVE" ]; then
        curl --fail --location --retry 2 https://www.lua.org/ftp/lua-5.1.5.tar.gz -o "$LUA_ARCHIVE.download"
        mv "$LUA_ARCHIVE.download" "$LUA_ARCHIVE"
    fi
    printf '%s  %s\n' 2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333 "$LUA_ARCHIVE" | shasum -a 256 -c - >&2
    tar -xzf "$LUA_ARCHIVE" -C "$PROJECT_ROOT/.build"
    make -C "$LUA_ROOT" macosx >&2
fi
"$LUA_ROOT/src/lua" -e 'assert(_VERSION == "Lua 5.1")'
printf '%s\n' "$LUA_ROOT/src/lua"
