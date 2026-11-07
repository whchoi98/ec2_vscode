#!/usr/bin/env bash
# Compatibility entry point for the shared installer/updater.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/03-update-codex.sh" "$@"
