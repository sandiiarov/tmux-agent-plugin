#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/variables.sh
source "$CURRENT_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

exec "$(python_bin)" "$CURRENT_DIR/action.py" "$@"
