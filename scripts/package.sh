#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_ROOT/scripts/build.sh" >&2
python3 "$PROJECT_ROOT/scripts/release.py" package "$@"
