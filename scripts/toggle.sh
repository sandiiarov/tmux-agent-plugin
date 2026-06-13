#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/variables.sh
source "$CURRENT_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

PANE_ID="${1:-}"
MODE="${2:-toggle}" # toggle or focus

if [ -z "$PANE_ID" ]; then
	PANE_ID="$(current_client_pane)"
fi

sidebar_registration() {
	get_tmux_option "${REGISTERED_PANE_PREFIX}-${PANE_ID}" ""
}

sidebar_pane_id() {
	sidebar_registration
}

sidebar_owner_for_current_pane() {
	get_tmux_option "${REGISTERED_SIDEBAR_PREFIX}-${PANE_ID}" ""
}

clear_sidebar_registration() {
	local main_id="$1"
	local sidebar_id="$2"
	[ -n "$main_id" ] && unset_tmux_option "${REGISTERED_PANE_PREFIX}-${main_id}"
	[ -n "$sidebar_id" ] && unset_tmux_option "${REGISTERED_SIDEBAR_PREFIX}-${sidebar_id}"
}

register_sidebar() {
	local main_id="$1"
	local sidebar_id="$2"
	set_tmux_option "${REGISTERED_PANE_PREFIX}-${main_id}" "$sidebar_id"
	set_tmux_option "${REGISTERED_SIDEBAR_PREFIX}-${sidebar_id}" "$main_id"
	tmux select-pane -t "$sidebar_id" -T "agent-sidebar" 2>/dev/null || true
}

has_sidebar() {
	local sidebar_id
	sidebar_id="$(sidebar_pane_id)"
	if [ -n "$sidebar_id" ] && pane_exists "$sidebar_id"; then
		return 0
	fi
	if [ -n "$sidebar_id" ]; then
		clear_sidebar_registration "$PANE_ID" "$sidebar_id"
	fi
	return 1
}

position_is_left() {
	local position="$1"
	[ "$position" = "left" ]
}

normalize_position() {
	case "$1" in
		left|right) printf '%s\n' "$1" ;;
		*) printf '%s\n' "$DEFAULT_POSITION" ;;
	esac
}

integer_or_default() {
	local value="$1"
	local default_value="$2"
	case "$value" in
		''|*[!0-9]*) printf '%s\n' "$default_value" ;;
		*) printf '%s\n' "$value" ;;
	esac
}

desired_sidebar_size() {
	local pane_width="$1"
	local pane_path="$2"
	local configured remembered half max_size desired
	configured="$(integer_or_default "$(get_tmux_option "$WIDTH_OPTION" "$DEFAULT_WIDTH")" "$DEFAULT_WIDTH")"
	remembered="$(remembered_width_for_path "$pane_path" 2>/dev/null || true)"
	half=$((pane_width / 2))
	max_size=$((pane_width - 20))
	[ "$max_size" -lt 10 ] && max_size="$half"

	if [ -n "$remembered" ] && [ "$remembered" -gt 0 ] 2>/dev/null; then
		desired="$remembered"
	else
		desired="$configured"
	fi

	[ "$desired" -gt "$max_size" ] 2>/dev/null && desired="$half"
	[ "$desired" -lt 10 ] 2>/dev/null && desired="10"
	printf '%s\n' "$desired"
}

sidebar_command() {
	printf '%s %s\n' "$(shell_quote "$CURRENT_DIR/sidebar.sh")" "$(shell_quote "$PANE_ID")"
}

kill_sidebar() {
	local sidebar_id sidebar_width pane_path old_width new_width position direction_flag
	sidebar_id="$(sidebar_pane_id)"
	[ -n "$sidebar_id" ] || return 0

	pane_path="$(get_pane_info "$PANE_ID" '#{pane_current_path}')"
	old_width="$(get_pane_info "$PANE_ID" '#{pane_width}')"
	sidebar_width="$(get_pane_info "$sidebar_id" '#{pane_width}')"
	position="$(normalize_position "$(get_tmux_option "$POSITION_OPTION" "$DEFAULT_POSITION")")"

	if [ -n "$pane_path" ] && [ -n "$sidebar_width" ]; then
		save_width_for_path "$pane_path" "$sidebar_width"
	fi

	if pane_exists "$sidebar_id"; then
		tmux kill-pane -t "$sidebar_id" 2>/dev/null || true
	fi
	clear_sidebar_registration "$PANE_ID" "$sidebar_id"

	new_width="$(get_pane_info "$PANE_ID" '#{pane_width}')"
	if [ -n "$old_width" ] && [ -n "$new_width" ] && [ -n "$sidebar_width" ] && [ "$old_width" = "$new_width" ]; then
		if position_is_left "$position"; then
			direction_flag="-L"
		else
			direction_flag="-R"
		fi
		tmux resize-pane -t "$PANE_ID" "$direction_flag" "$((sidebar_width + 1))" 2>/dev/null || true
	fi
}

create_sidebar_left() {
	local size="$1"
	local pane_path="$2"
	local command sidebar_id
	command="$(sidebar_command)"
	sidebar_id="$(tmux new-window -d -c "$pane_path" -P -F '#{pane_id}' "$command")"
	tmux join-pane -hb -l "$size" -t "$PANE_ID" -s "$sidebar_id"
	printf '%s\n' "$sidebar_id"
}

create_sidebar_right() {
	local size="$1"
	local pane_path="$2"
	local command
	command="$(sidebar_command)"
	tmux split-window -h -l "$size" -c "$pane_path" -P -F '#{pane_id}' "$command"
}

create_sidebar() {
	local pane_width pane_path min_width position size sidebar_id
	pane_width="$(get_pane_info "$PANE_ID" '#{pane_width}')"
	pane_path="$(get_pane_info "$PANE_ID" '#{pane_current_path}')"
	min_width="$(integer_or_default "$(get_tmux_option "$MINIMUM_WIDTH_OPTION" "$DEFAULT_MINIMUM_WIDTH")" "$DEFAULT_MINIMUM_WIDTH")"
	position="$(normalize_position "$(get_tmux_option "$POSITION_OPTION" "$DEFAULT_POSITION")")"

	if [ -z "$pane_width" ] || [ "$pane_width" -lt "$min_width" ]; then
		display_message "Pane too narrow for tmux-agent-plugin sidebar"
		exit 1
	fi

	[ -n "$pane_path" ] || pane_path="$HOME"
	size="$(desired_sidebar_size "$pane_width" "$pane_path")"

	if position_is_left "$position"; then
		sidebar_id="$(create_sidebar_left "$size" "$pane_path")"
	else
		sidebar_id="$(create_sidebar_right "$size" "$pane_path")"
	fi

	register_sidebar "$PANE_ID" "$sidebar_id"
	if [ "$MODE" = "focus" ]; then
		tmux select-pane -t "$sidebar_id"
	else
		tmux select-pane -t "$PANE_ID"
	fi
}

execute_from_owner_if_sidebar() {
	local owner_id
	owner_id="$(sidebar_owner_for_current_pane)"
	if [ -n "$owner_id" ]; then
		if pane_exists "$owner_id"; then
			exec "$CURRENT_DIR/toggle.sh" "$owner_id" "$MODE"
		else
			clear_sidebar_registration "$owner_id" "$PANE_ID"
			tmux kill-pane -t "$PANE_ID" 2>/dev/null || true
			exit 0
		fi
	fi
}

main() {
	ensure_agent_sidebar_dirs
	ensure_supported_tmux_version "$SUPPORTED_TMUX_VERSION" || exit 1
	execute_from_owner_if_sidebar
	if has_sidebar; then
		kill_sidebar
	else
		create_sidebar
	fi
}

main
