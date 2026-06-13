#!/usr/bin/env bash

# Shared shell helpers for tmux-agent-plugin.

get_tmux_option() {
	local option="$1"
	local default_value="${2:-}"
	local option_value
	option_value="$(tmux show-option -gqv "$option")"
	if [ -z "$option_value" ]; then
		printf '%s\n' "$default_value"
	else
		printf '%s\n' "$option_value"
	fi
}

set_tmux_option() {
	local option="$1"
	local value="$2"
	tmux set-option -gq "$option" "$value"
}

unset_tmux_option() {
	local option="$1"
	tmux set-option -guq "$option" 2>/dev/null || tmux set-option -gq "$option" ""
}

set_tmux_option_if_unset() {
	local option="$1"
	local value="$2"
	local existing
	existing="$(tmux show-option -gqv "$option")"
	if [ -z "$existing" ]; then
		set_tmux_option "$option" "$value"
	fi
}

is_on() {
	case "${1:-}" in
		1|on|ON|true|TRUE|yes|YES|y|Y) return 0 ;;
		*) return 1 ;;
	esac
}

# Displays a message without permanently overriding tmux's display-time option.
display_message() {
	local message="$1"
	local display_duration="${2:-5000}"
	local saved_display_time
	saved_display_time="$(get_tmux_option "display-time" "750")"
	tmux set-option -gq display-time "$display_duration"
	tmux display-message "$message"
	tmux set-option -gq display-time "$saved_display_time"
}

get_pane_info() {
	local pane_id="$1"
	local format_string="$2"
	tmux display-message -p -t "$pane_id" "$format_string" 2>/dev/null
}

pane_exists() {
	local pane_id="$1"
	tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$pane_id"
}

current_client_pane() {
	tmux display-message -p '#{pane_id}' 2>/dev/null
}

_get_digits_from_string() {
	printf '%s\n' "$1" | tr -dC '[:digit:]'
}

tmux_version_int() {
	_get_digits_from_string "$(tmux -V 2>/dev/null)"
}

version_at_least() {
	local wanted current
	wanted="$(_get_digits_from_string "$1")"
	current="$(tmux_version_int)"
	[ -n "$current" ] && [ "$current" -ge "$wanted" ]
}

ensure_supported_tmux_version() {
	local version="$1"
	if ! version_at_least "$version"; then
		display_message "tmux-agent-plugin requires tmux ${version}+"
		return 1
	fi
}

ensure_agent_sidebar_dirs() {
	mkdir -p "$(agent_sidebar_data_dir)" "$(agent_sidebar_cache_dir)" "$(agent_sidebar_cache_dir)/reports"
}

sanitize_width_path() {
	# Keep the width file line-oriented and tab-separated.
	printf '%s' "$1" | tr '\t\n\r' '   '
}

remembered_width_for_path() {
	local pane_path="$1"
	local width_file
	width_file="$(agent_sidebar_width_file)"
	[ -f "$width_file" ] || return 1
	awk -F '\t' -v p="$(sanitize_width_path "$pane_path")" '$1 == p { value = $2 } END { if (value != "") print value }' "$width_file"
}

save_width_for_path() {
	local pane_path="$1"
	local width="$2"
	local width_file tmp_file clean_path
	ensure_agent_sidebar_dirs
	width_file="$(agent_sidebar_width_file)"
	tmp_file="${width_file}.$$"
	clean_path="$(sanitize_width_path "$pane_path")"
	awk -F '\t' -v p="$clean_path" '$1 != p { print }' "$width_file" 2>/dev/null > "$tmp_file" || true
	printf '%s\t%s\n' "$clean_path" "$width" >> "$tmp_file"
	mv "$tmp_file" "$width_file"
}

python_bin() {
	get_tmux_option "$PYTHON_OPTION" "$DEFAULT_PYTHON"
}

shell_quote() {
	# Bash-only helper used by Bash entrypoints when constructing tmux commands.
	printf '%q' "$1"
}
