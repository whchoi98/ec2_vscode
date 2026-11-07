#!/usr/bin/env bash
# Merge optional AWS MCP servers and legacy mcp.json into config.toml.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run-config.sh" mcp "$@"
