#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/variables.sh
source "$CURRENT_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

VIEW_PANE_OPTION="@agent-status-view-pane"
VIEW_INDEX_OPTION="@agent-status-view-index"

target_pane() {
	local target="${AGENT_STATUS_TARGET_PANE:-${TMUX_PANE:-}}"
	if [ -n "$target" ] && tmux display-message -p -t "$target" '#{pane_id}' >/dev/null 2>&1; then
		printf '%s\n' "$target"
	else
		tmux display-message -p '#{pane_id}'
	fi
}

window_option_get() {
	local option="$1" target
	target="$(target_pane)"
	tmux show-option -wqv -t "$target" "$option" 2>/dev/null || true
}

window_option_set() {
	local option="$1" value="$2" target
	target="$(target_pane)"
	tmux set-option -wq -t "$target" "$option" "$value"
}

window_option_unset() {
	local option="$1" target
	target="$(target_pane)"
	tmux set-option -wqu -t "$target" "$option" 2>/dev/null || true
}

usage() {
	cat <<'EOF'
usage: view.sh [toggle|pane|render|up|down|enter|close]

Create a tmux split view with agents on the left and the current tmux pane on
the right. The right side is the real tmux pane/layout, so it remains fully
interactive.

Commands:
  toggle  Toggle the split view for the current tmux window. Default.
  pane    Run the left agent-list pane render loop.
  render  Render the agent list once.
  up      Move selection up in the agent list.
  down    Move selection down in the agent list.
  enter   Focus the selected agent pane and close the view.
  close   Close the view.
EOF
}

resolve_width_cells() {
	local value window_width percent digits target
	value="$(get_tmux_option "$VIEW_WIDTH_OPTION" "$DEFAULT_VIEW_WIDTH")"
	target="$(target_pane)"
	window_width="$(tmux display-message -p -t "$target" '#{window_width}')"

	case "$value" in
		*%)
			percent="${value%%%}"
			digits="$(_get_digits_from_string "$percent")"
			if [ -z "$digits" ]; then
				digits=20
			fi
			printf '%s\n' "$((window_width * digits / 100))"
			;;
		*)
			digits="$(_get_digits_from_string "$value")"
			printf '%s\n' "${digits:-32}"
			;;
	esac
}

clamp_width_cells() {
	local cells window_width min_width max_width target
	cells="$1"
	target="$(target_pane)"
	window_width="$(tmux display-message -p -t "$target" '#{window_width}')"
	min_width=18
	max_width=$((window_width - 20))

	if [ "$max_width" -lt "$min_width" ]; then
		max_width="$min_width"
	fi
	if [ "$cells" -lt "$min_width" ]; then
		cells="$min_width"
	fi
	if [ "$cells" -gt "$max_width" ]; then
		cells="$max_width"
	fi
	printf '%s\n' "$cells"
}

view_panes_in_target_window() {
	local target window_id
	target="$(target_pane)"
	window_id="$(tmux display-message -p -t "$target" '#{window_id}')"
	tmux list-panes -t "$window_id" -F '#{pane_id}	#{pane_title}' 2>/dev/null \
		| awk -F '\t' '$2 == "tmux-agent-plugin-view" { print $1 }'
}

current_view_pane() {
	local pane
	pane="$(window_option_get "$VIEW_PANE_OPTION")"
	if view_pane_exists "$pane"; then
		printf '%s\n' "$pane"
		return 0
	fi
	view_panes_in_target_window | head -n 1
}

view_pane_exists() {
	local pane_id="$1"
	[ -n "$pane_id" ] || return 1
	tmux display-message -p -t "$pane_id" '#{pane_id}' >/dev/null 2>&1
}

selected_index() {
	local index
	index="$(window_option_get "$VIEW_INDEX_OPTION")"
	case "$index" in
		''|*[!0-9]*) printf '0\n' ;;
		*) printf '%s\n' "$index" ;;
	esac
}

set_selected_index() {
	window_option_set "$VIEW_INDEX_OPTION" "$1"
}

agent_count() {
	"$CURRENT_DIR/agents.sh" tsv --refresh | awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }'
}

refresh_view_pane() {
	local pane_id pid
	pane_id="${1:-$(current_view_pane)}"
	view_pane_exists "$pane_id" || return 0
	pid="$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null || true)"
	if [ -n "$pid" ]; then
		kill -USR1 "$pid" 2>/dev/null || true
	fi
}

open_view() {
	local existing current_pane width new_pane command selected
	existing="$(current_view_pane)"
	if view_pane_exists "$existing"; then
		return 0
	fi
	window_option_unset "$VIEW_PANE_OPTION"

	current_pane="$(target_pane)"
	width="$(clamp_width_cells "$(resolve_width_cells)")"
	command="$CURRENT_DIR/view.sh pane"
	selected="$(selected_index)"

	# -f makes the agent pane full height when supported. Older tmux versions do
	# not have -f, so fall back to splitting only the current pane.
	new_pane="$(tmux split-window -t "$current_pane" -d -h -b -f -l "$width" -P -F '#{pane_id}' "$command" 2>/dev/null \
		|| tmux split-window -t "$current_pane" -d -h -b -l "$width" -P -F '#{pane_id}' "$command")"

	window_option_set "$VIEW_PANE_OPTION" "$new_pane"
	set_selected_index "$selected"
	tmux select-pane -t "$current_pane"
	refresh_view_pane "$new_pane"
}

close_view() {
	local existing pane seen
	existing="$(current_view_pane)"
	seen=""
	if view_pane_exists "$existing"; then
		tmux kill-pane -t "$existing" 2>/dev/null || true
		seen=" $existing "
	fi
	while IFS= read -r pane; do
		[ -n "$pane" ] || continue
		case "$seen" in
			*" $pane "*) continue ;;
		esac
		tmux kill-pane -t "$pane" 2>/dev/null || true
	done < <(view_panes_in_target_window)
	window_option_unset "$VIEW_PANE_OPTION"
}

toggle_view() {
	local existing
	existing="$(current_view_pane)"
	if view_pane_exists "$existing"; then
		close_view
	else
		open_view
	fi
}

passthrough_key() {
	local key="$1" target
	[ -n "$key" ] || return 0
	target="$(target_pane)"
	tmux send-keys -t "$target" "$key"
}

move_selection() {
	local delta passthrough existing count index
	delta="$1"
	passthrough="$2"
	existing="$(current_view_pane)"
	if ! view_pane_exists "$existing"; then
		passthrough_key "$passthrough"
		return 0
	fi

	count="$(agent_count)"
	if [ "$count" -le 0 ]; then
		set_selected_index 0
		refresh_view_pane "$existing"
		return 0
	fi

	index="$(selected_index)"
	index=$(( (index + delta + count) % count ))
	set_selected_index "$index"
	focus_selected_pane keep-view
}

selected_agent_target() {
	local index
	index="$(selected_index)"
	"$CURRENT_DIR/agents.sh" tsv --refresh | awk -F '\t' -v selected="$index" '
		NR > 1 {
			row = NR - 2
			if (row == selected) {
				print $9 "\t" $10 "\t" $11
				exit
			}
		}
	'
}

focus_selected_pane() {
	local mode existing selected pane_id window_id session_id current_window current_session index current_target
	mode="${1:-keep-view}"
	existing="$(current_view_pane)"
	view_pane_exists "$existing" || return 0

	selected="$(selected_agent_target)"
	[ -n "$selected" ] || return 0
	IFS=$'\t' read -r pane_id window_id session_id <<< "$selected"
	[ -n "$pane_id" ] || return 0

	current_target="$(target_pane)"
	current_window="$(tmux display-message -p -t "$current_target" '#{window_id}')"
	current_session="$(tmux display-message -p -t "$current_target" '#{session_id}')"
	index="$(selected_index)"

	if [ "$window_id" = "$current_window" ] && [ "$session_id" = "$current_session" ]; then
		tmux select-pane -t "$pane_id" 2>/dev/null || true
		if [ "$mode" = "close-view" ]; then
			close_view
		else
			refresh_view_pane "$existing"
		fi
		return 0
	fi

	close_view
	if [ -n "$session_id" ]; then
		tmux switch-client -t "$session_id" 2>/dev/null || true
	fi
	if [ -n "$window_id" ]; then
		tmux select-window -t "$window_id" 2>/dev/null || true
	fi
	tmux select-pane -t "$pane_id" 2>/dev/null || true
	AGENT_STATUS_TARGET_PANE="$pane_id"
	set_selected_index "$index"
	if [ "$mode" != "close-view" ]; then
		open_view
	fi
}

enter_selection() {
	local existing
	existing="$(current_view_pane)"
	if ! view_pane_exists "$existing"; then
		passthrough_key C-o
		return 0
	fi

	focus_selected_pane close-view
}

close_or_passthrough() {
	local existing
	existing="$(current_view_pane)"
	if ! view_pane_exists "$existing"; then
		passthrough_key C-x
		return 0
	fi

	close_view
}

render_once() {
	local nerd_icons selected
	nerd_icons="off"
	if is_on "$(get_tmux_option "$NERD_ICONS_OPTION" "$DEFAULT_NERD_ICONS")"; then
		nerd_icons="on"
	fi
	selected="$(selected_index)"
	export AGENT_STATUS_NERD_ICONS="$nerd_icons"
	export AGENT_STATUS_VIEW_INDEX="$selected"

	"$CURRENT_DIR/agents.sh" tsv --refresh | perl -CSDA -Mutf8 -F'\t' -lane '
		BEGIN {
			$esc = "\e";
			$reset = "$esc\[0m";
			$red = "$esc\[31m";
			$yellow = "$esc\[33m";
			$green = "$esc\[32m";
			$blue = "$esc\[34m";
			$cyan = "$esc\[36m";
			$dim = "$esc\[2m";
			$bold = "$esc\[1m";
			$selected = int($ENV{"AGENT_STATUS_VIEW_INDEX"} // 0);
			$row_index = 0;
		}

		sub nerd_icons_enabled {
			return ($ENV{"AGENT_STATUS_NERD_ICONS"} // "") =~ /^(1|on|true|yes|y)$/i;
		}

		sub agent_icon {
			my ($agent) = @_;
			return "" unless nerd_icons_enabled();
			return "" if $agent eq "claude";
			return "" if $agent eq "pi";
			return "";
		}

		sub status_icon {
			my ($status) = @_;
			return "$red⚠$reset" if $status eq "blocked";
			return "$yellow⠋$reset" if $status eq "working";
			return "$green✓$reset" if $status eq "done";
			return "$blue•$reset" if $status eq "idle";
			return "$dim?$reset";
		}

		sub agent_line {
			my ($status, $agent, $index) = @_;
			my $icon = agent_icon($agent);
			my $label = ($icon ne "" ? "$icon " : "") . $agent;
			$label = "$cyan$bold$label$reset" if $index == $selected;
			return status_icon($status) . " " . $label;
		}

		next if $. == 1;
		my ($status, $agent, $target, $name, $session, $window, $pane, $cwd, $pane_id, $window_id, $session_id) = @F;
		push @order, $session unless $seen{$session}++;
		push @{$items{$session}}, [ $status, $agent, $row_index++ ];

		END {
			if (!@order) {
				print "${dim}no agents$reset";
				exit 0;
			}
			my $printed_session = 0;
			for my $session (@order) {
				print "" if $printed_session++;
				print "$blue$reset $bold$session$reset";
				for my $item (@{$items{$session}}) {
					my ($status, $agent, $index) = @$item;
					print agent_line($status, $agent, $index);
				}
			}
		}
	'
}

LAST_RENDER=""

redraw() {
	local output
	if ! output="$(render_once 2>&1)"; then
		output="failed to render agents"
	fi

	# Avoid flicker: collect/render off-screen first, repaint only when content
	# changed, and never clear the pane before the next frame is ready.
	if [ "$output" != "$LAST_RENDER" ]; then
		printf '\033[H%s\033[J' "$output"
		LAST_RENDER="$output"
	fi
}

pane_loop() {
	local interval sleep_pid
	interval="$(get_tmux_option "$VIEW_REFRESH_OPTION" "$DEFAULT_VIEW_REFRESH")"
	printf '\033]2;tmux-agent-plugin-view\033\\'
	printf '\033[?25l'
	trap 'printf "\033[?25h"' EXIT INT TERM
	trap 'redraw' USR1

	redraw
	while :; do
		sleep "$interval" &
		sleep_pid="$!"
		wait "$sleep_pid" || true
		redraw
	done
}

case "${1:-toggle}" in
	toggle)
		toggle_view
		;;
	pane)
		pane_loop
		;;
	render)
		render_once
		;;
	up)
		move_selection -1 C-p
		;;
	down)
		move_selection 1 C-n
		;;
	enter)
		enter_selection
		;;
	close)
		close_or_passthrough
		;;
	--help|-h|help)
		usage
		;;
	*)
		usage >&2
		exit 2
		;;
esac
