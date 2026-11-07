#!/usr/bin/env bash
# Shared launcher; tomlkit retains comments and unrelated user configuration.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomlkit' >/dev/null 2>&1; then
    exec python3 "$SCRIPT_DIR/configure.py" "$@"
elif command -v uv >/dev/null 2>&1; then
    exec uv run --no-project --with 'tomlkit>=0.13,<1' python "$SCRIPT_DIR/configure.py" "$@"
else
    echo "Python 3.9+와 tomlkit 또는 uv가 필요합니다." >&2
    echo "설치 예: python3 -m pip install --user 'tomlkit>=0.13,<1'" >&2
    exit 1
fi
