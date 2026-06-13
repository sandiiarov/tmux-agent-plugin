#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/variables.sh
source "$CURRENT_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

OWNER_PANE_ID="${1:-}"
SIDEBAR_PANE_ID="${TMUX_PANE:-}"

interval() {
	local value
	value="$(get_tmux_option "$REFRESH_INTERVAL_OPTION" "$DEFAULT_REFRESH_INTERVAL")"
	case "$value" in
		''|*[!0-9.]*) printf '%s\n' "$DEFAULT_REFRESH_INTERVAL" ;;
		*) printf '%s\n' "$value" ;;
	esac
}

render_once() {
	local python
	python="$(python_bin)"
	printf '\033[H\033[2J'
	if command -v "$python" >/dev/null 2>&1; then
		"$python" "$CURRENT_DIR/render.py" --owner "$OWNER_PANE_ID" --pane "$SIDEBAR_PANE_ID" || true
	else
		printf 'tmux-agent-plugin\n\n'
		printf 'Python not found: %s\n' "$python"
		printf 'Set @agent-sidebar-python to a Python 3 executable.\n'
	fi
}

while :; do
	render_once
	sleep "$(interval)"
done
