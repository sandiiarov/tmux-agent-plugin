#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/variables.sh
source "$CURRENT_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

ESC=$'\033'

usage() {
	cat <<'EOF'
usage: view.sh [popup|render|jump-index INDEX]

Open or render the tmux-agent-plugin popup view.

The popup shows agents grouped by tmux session on the left and a captured preview
of the selected real tmux pane on the right.

Controls inside the popup:
  C-n  Move selection down and update the pane preview.
  C-p  Move selection up and update the pane preview.
  C-o  Jump to the selected real tmux pane and close the popup.
  C-x  Close the popup.
  q    Close the popup.
EOF
}

# Row arrays populated by load_agents.
declare -a STATUSES=()
declare -a AGENTS=()
declare -a TARGETS=()
declare -a NAMES=()
declare -a SESSIONS=()
declare -a PANE_IDS=()
declare -a WINDOW_IDS=()
declare -a SESSION_IDS=()
declare -a LEFT_LINES=()
declare -a RIGHT_LINES=()
AGENT_COUNT=0
SELECTED_INDEX=0
LAST_RENDER=""

nerd_icons_enabled() {
	is_on "$(get_tmux_option "$NERD_ICONS_OPTION" "$DEFAULT_NERD_ICONS")"
}

agent_icon() {
	local agent="$1"
	if nerd_icons_enabled; then
		case "$agent" in
			claude) printf ' ' ;;
			pi) printf ' ' ;;
			*) printf '' ;;
		esac
	fi
}

status_icon() {
	case "$1" in
		blocked) printf '%s[31m⚠%s[0m' "$ESC" "$ESC" ;;
		working) printf '%s[33m⠋%s[0m' "$ESC" "$ESC" ;;
		done) printf '%s[32m✓%s[0m' "$ESC" "$ESC" ;;
		idle) printf '%s[34m•%s[0m' "$ESC" "$ESC" ;;
		*) printf '%s[2m?%s[0m' "$ESC" "$ESC" ;;
	esac
}

visible_len() {
	perl -CSDA -Mutf8 -e '
		my $s = join("", <>);
		$s =~ s/\e\[[0-?]*[ -\/]*[@-~]//g;
		chomp $s;
		print length($s);
	' <<< "$1"
}

pad_right() {
	local value="$1" width="$2" len padding
	len="$(visible_len "$value")"
	if [ "$len" -ge "$width" ]; then
		printf '%s' "$value"
		return 0
	fi
	padding=$((width - len))
	printf '%s%*s' "$value" "$padding" ''
}

truncate_plain() {
	local width="$1" value="$2"
	perl -CSDA -Mutf8 -e '
		my ($width, $value) = @ARGV;
		$value =~ s/\e\[[0-?]*[ -\/]*[@-~]//g;
		$value =~ s/\t/    /g;
		$value =~ s/[\r\n]+$//g;
		my @chars = split //, $value;
		if (@chars > $width) {
			print join("", @chars[0 .. $width - 2]) . "…";
		} else {
			print $value;
		}
	' "$width" "$value"
}

load_agents() {
	STATUSES=()
	AGENTS=()
	TARGETS=()
	NAMES=()
	SESSIONS=()
	PANE_IDS=()
	WINDOW_IDS=()
	SESSION_IDS=()

	local status agent target name session window pane cwd pane_id window_id session_id
	while IFS=$'\t' read -r status agent target name session window pane cwd pane_id window_id session_id; do
		[ "$status" != "status" ] || continue
		STATUSES+=("$status")
		AGENTS+=("$agent")
		TARGETS+=("$target")
		NAMES+=("$name")
		SESSIONS+=("$session")
		PANE_IDS+=("$pane_id")
		WINDOW_IDS+=("$window_id")
		SESSION_IDS+=("$session_id")
	done < <("$CURRENT_DIR/agents.sh" tsv --refresh)

	AGENT_COUNT="${#AGENTS[@]}"
	if [ "$AGENT_COUNT" -le 0 ]; then
		SELECTED_INDEX=0
	elif [ "$SELECTED_INDEX" -ge "$AGENT_COUNT" ]; then
		SELECTED_INDEX=$((AGENT_COUNT - 1))
	elif [ "$SELECTED_INDEX" -lt 0 ]; then
		SELECTED_INDEX=0
	fi
}

resolve_left_width() {
	local cols="$1" value percent digits width max_width
	value="$(get_tmux_option "$VIEW_WIDTH_OPTION" "$DEFAULT_VIEW_WIDTH")"
	case "$value" in
		*%)
			percent="${value%%%}"
			digits="$(_get_digits_from_string "$percent")"
			[ -n "$digits" ] || digits=20
			width=$((cols * digits / 100))
			;;
		*)
			digits="$(_get_digits_from_string "$value")"
			width="${digits:-24}"
			;;
	esac
	[ "$width" -ge 18 ] || width=18
	max_width=$((cols - 24))
	[ "$max_width" -ge 18 ] || max_width=18
	[ "$width" -le "$max_width" ] || width="$max_width"
	printf '%s\n' "$width"
}

build_left_lines() {
	local previous_session="" i line label
	LEFT_LINES=()
	if [ "$AGENT_COUNT" -le 0 ]; then
		LEFT_LINES+=("${ESC}[2mno agents${ESC}[0m")
		return 0
	fi

	for ((i = 0; i < AGENT_COUNT; i++)); do
		if [ "${SESSIONS[$i]}" != "$previous_session" ]; then
			[ -z "$previous_session" ] || LEFT_LINES+=("")
			LEFT_LINES+=("${ESC}[34m${ESC}[0m ${ESC}[1m${SESSIONS[$i]}${ESC}[0m")
			previous_session="${SESSIONS[$i]}"
		fi
		label="$(agent_icon "${AGENTS[$i]}")${AGENTS[$i]}"
		if [ "$i" -eq "$SELECTED_INDEX" ]; then
			label="${ESC}[36m${ESC}[1m${label}${ESC}[0m"
		fi
		line="$(status_icon "${STATUSES[$i]}") ${label}"
		LEFT_LINES+=("$line")
	done
}

build_preview_lines() {
	local max_lines="$1" pane_id title meta capture_start line
	RIGHT_LINES=()
	if [ "$AGENT_COUNT" -le 0 ]; then
		RIGHT_LINES+=("${ESC}[2mNo agent panes found.${ESC}[0m")
		return 0
	fi

	pane_id="${PANE_IDS[$SELECTED_INDEX]}"
	title="$(tmux display-message -p -t "$pane_id" '#{session_name}:#{window_index}.#{pane_index}  #{pane_current_command}' 2>/dev/null || true)"
	meta="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null || true)"
	RIGHT_LINES+=("${ESC}[1m${title}${ESC}[0m")
	[ -z "$meta" ] || RIGHT_LINES+=("${ESC}[2m${meta}${ESC}[0m")
	RIGHT_LINES+=("")

	capture_start=$((0 - max_lines))
	while IFS= read -r line; do
		RIGHT_LINES+=("$line")
	done < <(tmux capture-pane -t "$pane_id" -p -J -S "$capture_start" 2>/dev/null || true)
}

render_screen() {
	load_agents

	local cols rows left_width right_width max_lines i left right left_text right_text
	cols="$(tput cols 2>/dev/null || printf '100')"
	rows="$(tput lines 2>/dev/null || printf '30')"
	[ "$cols" -gt 0 ] || cols=100
	[ "$rows" -gt 0 ] || rows=30
	left_width="$(resolve_left_width "$cols")"
	right_width=$((cols - left_width - 3))
	[ "$right_width" -gt 10 ] || right_width=10
	max_lines=$((rows - 1))
	[ "$max_lines" -gt 1 ] || max_lines=1

	build_left_lines
	build_preview_lines "$max_lines"

	for ((i = 0; i < max_lines; i++)); do
		left="${LEFT_LINES[$i]:-}"
		right="${RIGHT_LINES[$i]:-}"
		left_text="$(truncate_plain "$left_width" "$left")"
		if [ "$(visible_len "$left")" -le "$left_width" ]; then
			left_text="$left"
		fi
		right_text="$(truncate_plain "$right_width" "$right")"
		if [ "$(visible_len "$right")" -le "$right_width" ]; then
			right_text="$right"
		fi
		printf '%s %s[2m│%s[0m %s\n' "$(pad_right "$left_text" "$left_width")" "$ESC" "$ESC" "$right_text"
	done
}

redraw() {
	local output
	if ! output="$(render_screen 2>&1)"; then
		output="failed to render agents"
	fi
	if [ "$output" != "$LAST_RENDER" ]; then
		printf '%s[H%s%s[J' "$ESC" "$output" "$ESC"
		LAST_RENDER="$output"
	fi
}

jump_to_selection() {
	load_agents
	[ "$AGENT_COUNT" -gt 0 ] || return 0
	local pane_id window_id session_id
	pane_id="${PANE_IDS[$SELECTED_INDEX]}"
	window_id="${WINDOW_IDS[$SELECTED_INDEX]}"
	session_id="${SESSION_IDS[$SELECTED_INDEX]}"
	if [ -n "$session_id" ]; then
		tmux switch-client -t "$session_id" 2>/dev/null || true
	fi
	if [ -n "$window_id" ]; then
		tmux select-window -t "$window_id" 2>/dev/null || true
	fi
	tmux select-pane -t "$pane_id" 2>/dev/null || true
}

handle_key() {
	local key="$1" should_redraw="${2:-yes}"
	case "$key" in
		$'\016') # C-n: down
			load_agents
			if [ "$AGENT_COUNT" -gt 0 ]; then
				SELECTED_INDEX=$(( (SELECTED_INDEX + 1) % AGENT_COUNT ))
			fi
			[ "$should_redraw" = "yes" ] && redraw
			;;
		$'\020') # C-p: up
			load_agents
			if [ "$AGENT_COUNT" -gt 0 ]; then
				SELECTED_INDEX=$(( (SELECTED_INDEX - 1 + AGENT_COUNT) % AGENT_COUNT ))
			fi
			[ "$should_redraw" = "yes" ] && redraw
			;;
		$'\017') # C-o: enter selected pane and close popup
			jump_to_selection
			return 1
			;;
		$'\030'|q|Q|$'\033') # C-x / q / escape: close popup
			return 1
			;;
		*)
			[ "$should_redraw" = "yes" ] && redraw
			;;
	esac
	return 0
}

headless_popup_loop() {
	local key
	while IFS= read -rsn1 key; do
		handle_key "$key" no || return 0
	done
}

popup_loop() {
	local interval old_stty key
	if [ ! -t 1 ]; then
		headless_popup_loop
		return 0
	fi

	interval="$(get_tmux_option "$VIEW_REFRESH_OPTION" "$DEFAULT_VIEW_REFRESH")"
	printf '%s[?1049h%s[?25l' "$ESC" "$ESC"
	old_stty="$(stty -g 2>/dev/null || true)"
	stty -echo -icanon time 0 min 0 2>/dev/null || true
	cleanup() {
		[ -z "${old_stty:-}" ] || stty "$old_stty" 2>/dev/null || true
		printf '%s[?25h%s[?1049l' "$ESC" "$ESC"
	}
	trap cleanup EXIT INT TERM

	redraw
	while :; do
		key=""
		IFS= read -rsn1 -t "$interval" key || true
		handle_key "$key" yes || return 0
	done
}

case "${1:-popup}" in
	popup|toggle|"")
		popup_loop
		;;
	render)
		render_screen
		;;
	jump-index)
		SELECTED_INDEX="${2:-0}"
		jump_to_selection
		;;
	--help|-h|help)
		usage
		;;
	*)
		usage >&2
		exit 2
		;;
esac
