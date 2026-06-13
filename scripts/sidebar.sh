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

LAST_RENDER=""

cleanup() {
	printf '\033[?25h'
}
trap cleanup EXIT HUP INT TERM

render_once() {
	local python output
	python="$(python_bin)"
	if command -v "$python" >/dev/null 2>&1; then
		output="$($python "$CURRENT_DIR/render.py" --owner "$OWNER_PANE_ID" --pane "$SIDEBAR_PANE_ID" 2>&1 || true)"
	else
		output="tmux-agent-plugin

Python not found: $python
Set @agent-sidebar-python to a Python 3 executable."
	fi

	# Render into memory first, then repaint in place. This avoids flashing a
	# blank pane while pane collection/capture is still running. Skip repainting
	# entirely when nothing changed.
	if [ "$output" != "$LAST_RENDER" ]; then
		printf '\033[?25l\033[H%s\033[J' "$output"
		LAST_RENDER="$output"
	fi
}

while :; do
	render_once
	sleep "$(interval)"
done
