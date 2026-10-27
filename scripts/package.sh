#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_ROOT/scripts/build.sh"
mkdir -p "$PROJECT_ROOT/dist"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
    "$PROJECT_ROOT/exifmark.lrplugin" "$PROJECT_ROOT/dist/exifmark-0.1.0-macos.zip"
printf '%s\n' "$PROJECT_ROOT/dist/exifmark-0.1.0-macos.zip"
