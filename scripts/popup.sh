#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	cat <<'EOF'
usage: popup.sh [--list|--select-first]

Open an fzf navigator over tmux-agent-plugin agents.

Options:
  --list          Print formatted fzf rows and exit.
  --select-first  Jump to the first row without opening fzf; useful for tests.
EOF
}

format_rows() {
	"$CURRENT_DIR/agents.sh" tsv --refresh | awk -F '\t' '
		BEGIN {
			esc = sprintf("%c", 27)
			reset = esc "[0m"
			red = esc "[31m"
			yellow = esc "[33m"
			green = esc "[32m"
			blue = esc "[34m"
			dim = esc "[2m"
		}
		NR == 1 { next }
		{
			status = $1
			agent = $2
			target = $3
			name = $4
			session = $5
			window = $6
			pane = $7
			cwd = $8
			pane_id = $9
			window_id = $10
			session_id = $11

			if (status == "blocked") {
				state = red "⚠ blocked" reset
			} else if (status == "working") {
				state = yellow "⠋ working" reset
			} else if (status == "done") {
				state = green "✓ done" reset
			} else if (status == "idle") {
				state = blue "• idle" reset
			} else {
				state = dim "? unknown" reset
			}

			where = session ":" window "." pane
			printf "%s\t%s\t%s\t%-18s\t%-14s\t%-24s\t%-30s\t%s\n", pane_id, window_id, session_id, state, agent, where, name, cwd
		}
	'
}

focus_pane() {
	local pane_id="$1"
	local window_id="${2:-}"
	local session_id="${3:-}"

	if [ -z "$pane_id" ]; then
		return 1
	fi

	if [ -z "$session_id" ]; then
		session_id="$(tmux display-message -p -t "$pane_id" '#{session_id}' 2>/dev/null || true)"
	fi
	if [ -z "$window_id" ]; then
		window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}' 2>/dev/null || true)"
	fi

	if [ -n "$session_id" ]; then
		tmux switch-client -t "$session_id" 2>/dev/null || true
	fi
	if [ -n "$window_id" ]; then
		tmux select-window -t "$window_id" 2>/dev/null || true
	fi
	tmux select-pane -t "$pane_id" 2>/dev/null || true
}

open_popup() {
	local rows selected pane_id window_id session_id
	rows="$(format_rows)"
	if [ -z "$rows" ]; then
		printf 'No agent panes found.\n'
		sleep 1
		return 0
	fi

	if ! command -v fzf >/dev/null 2>&1; then
		printf 'tmux-agent-plugin popup requires fzf.\n\n'
		printf 'Install fzf, or consume values directly with:\n'
		printf '  %s/agents.sh json\n' "$CURRENT_DIR"
		sleep 4
		return 1
	fi

	selected="$(printf '%s\n' "$rows" | fzf \
		--ansi \
		--delimiter='\t' \
		--with-nth=4,5,6,7,8 \
		--nth=4,5,6,7,8 \
		--prompt='agents> ' \
		--header='enter: jump · ctrl-r: refresh · esc: close' \
		--preview='tmux capture-pane -t {1} -p -J -S -30 2>/dev/null' \
		--preview-window='down,45%,border-top' \
		--bind="ctrl-r:reload('$CURRENT_DIR/popup.sh' --list)")" || return 0

	IFS=$'\t' read -r pane_id window_id session_id _ <<< "$selected"
	focus_pane "$pane_id" "$window_id" "$session_id"
}

case "${1:-}" in
	--list)
		format_rows
		;;
	--select-first)
		first="$(format_rows | head -n 1)"
		[ -n "$first" ] || exit 0
		IFS=$'\t' read -r pane_id window_id session_id _ <<< "$first"
		focus_pane "$pane_id" "$window_id" "$session_id"
		;;
	--help|-h)
		usage
		;;
	"")
		open_popup
		;;
	*)
		usage >&2
		exit 2
		;;
esac
