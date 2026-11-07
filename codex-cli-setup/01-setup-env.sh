#!/usr/bin/env bash
# Configure Codex in $CODEX_HOME/config.toml.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run-config.sh" setup "$@"
