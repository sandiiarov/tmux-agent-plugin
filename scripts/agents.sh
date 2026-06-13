#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$($CURRENT_DIR/bin.sh)"

exec "$BIN" agents "$@"
