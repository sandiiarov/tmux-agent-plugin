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

ensure_agent_status_dirs() {
	mkdir -p "$(agent_status_data_dir)" "$(agent_status_cache_dir)" "$(agent_status_cache_dir)/reports"
}

