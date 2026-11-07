#!/usr/bin/env bash
# Compatibility entry point. Use --provider openai for OpenAI authentication.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/01-setup-env.sh" "$@"
