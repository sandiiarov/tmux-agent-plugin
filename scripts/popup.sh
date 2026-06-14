#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_on() {
	case "${1:-}" in
		1|on|ON|true|TRUE|yes|YES|y|Y) return 0 ;;
		*) return 1 ;;
	esac
}

nerd_icons_enabled() {
	local value
	value="$(tmux show-option -gqv @agent-status-nerd-icons 2>/dev/null || true)"
	is_on "$value"
}

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
	local nerd_icons="off"
	local refresh_arg=""
	if nerd_icons_enabled; then
		nerd_icons="on"
	fi
	if is_on "${AGENT_STATUS_REFRESH:-off}"; then
		refresh_arg="--refresh"
	fi
	export AGENT_STATUS_NERD_ICONS="$nerd_icons"

	# ANSI colors and UTF-8 glyphs confuse byte-based printf padding, so compute display cells.
	if [ -n "$refresh_arg" ]; then
		"$CURRENT_DIR/agents.sh" tsv "$refresh_arg"
	else
		"$CURRENT_DIR/agents.sh" tsv
	fi | perl -CSDA -Mutf8 -F'\t' -lane '
		BEGIN {
			$esc = "\e";
			$reset = "$esc\[0m";
			$red = "$esc\[31m";
			$yellow = "$esc\[33m";
			$green = "$esc\[32m";
			$blue = "$esc\[34m";
			$dim = "$esc\[2m";
		}

		sub agent_label {
			my ($agent) = @_;
			return $agent unless ($ENV{"AGENT_STATUS_NERD_ICONS"} // "") =~ /^(1|on|true|yes|y)$/i;
			return "" if $agent eq "claude";
			return "" if $agent eq "pi";
			return $agent;
		}

		sub status_icon {
			my ($status) = @_;
			return "$red⚠$reset" if $status eq "blocked";
			return "$yellow●$reset" if $status eq "working";
			return "$green✓$reset" if $status eq "done";
			return "$blue•$reset" if $status eq "idle";
			return "$dim?$reset";
		}

		next if $. == 1;
		my ($status, $agent, $target, $name, $session, $window, $pane, $cwd, $pane_id, $window_id, $session_id) = @F;
		my $display = status_icon($status) . " " . agent_label($agent) . " " . ($name // "");
		print join "\t", $pane_id, $window_id, $session_id, $display;
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

preview_lines() {
	local value
	value="$(tmux show-option -gqv @agent-status-popup-preview-lines 2>/dev/null || true)"
	case "$value" in
		''|*[!0-9]*) printf '200\n' ;;
		*) printf '%s\n' "$value" ;;
	esac
}

popup_fzf_opts() {
	# Use display-message so tmux format references in the option are expanded
	# at popup time, e.g. Catppuccin's #{@thm_bg} / #{@thm_fg} variables.
	tmux display-message -p '#{E:@agent-status-popup-fzf-opts}' 2>/dev/null || true
}

open_popup() {
	local rows selected pane_id window_id session_id lines extra_opts
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

	lines="$(preview_lines)"
	extra_opts="$(popup_fzf_opts)"
	set --
	if [ -n "$extra_opts" ]; then
		# User-controlled tmux option. Word-split intentionally so users can pass
		# normal fzf flags such as: --color=fg:-1,bg:-1,border:8
		eval "set -- $extra_opts"
	fi

	selected="$(printf '%s\n' "$rows" | fzf \
		--ansi \
		--delimiter='\t' \
		--with-nth=4 \
		--nth=4 \
		--prompt='agents> ' \
		--header='C-n/C-p: move · enter: jump · esc: close · C-r: refresh' \
		--preview="tmux capture-pane -t {1} -e -p -J -S -$lines 2>/dev/null" \
		--preview-window='right,70%,border-left,nowrap,follow,noinfo' \
		--bind='ctrl-n:down,ctrl-p:up' \
		--bind="ctrl-r:reload(AGENT_STATUS_REFRESH=on '$CURRENT_DIR/popup.sh' --list)" \
		"$@")" || return 0

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
