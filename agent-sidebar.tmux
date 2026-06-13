#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# shellcheck source=scripts/variables.sh
source "$SCRIPTS_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$SCRIPTS_DIR/helpers.sh"

set_default_options() {
	set_tmux_option_if_unset "$TOGGLE_KEY_OPTION" "$DEFAULT_TOGGLE_KEY"
	set_tmux_option_if_unset "$FOCUS_KEY_OPTION" "$DEFAULT_FOCUS_KEY"
	set_tmux_option_if_unset "$REFRESH_KEY_OPTION" "$DEFAULT_REFRESH_KEY"
	set_tmux_option_if_unset "$JUMP_KEY_OPTION" "$DEFAULT_JUMP_KEY"
	set_tmux_option_if_unset "$NEXT_BLOCKED_KEY_OPTION" "$DEFAULT_NEXT_BLOCKED_KEY"
	set_tmux_option_if_unset "$NEXT_DONE_KEY_OPTION" "$DEFAULT_NEXT_DONE_KEY"
	set_tmux_option_if_unset "$ACK_ALL_KEY_OPTION" "$DEFAULT_ACK_ALL_KEY"

	set_tmux_option_if_unset "$POSITION_OPTION" "$DEFAULT_POSITION"
	set_tmux_option_if_unset "$WIDTH_OPTION" "$DEFAULT_WIDTH"
	set_tmux_option_if_unset "$MINIMUM_WIDTH_OPTION" "$DEFAULT_MINIMUM_WIDTH"
	set_tmux_option_if_unset "$REFRESH_INTERVAL_OPTION" "$DEFAULT_REFRESH_INTERVAL"
	set_tmux_option_if_unset "$CAPTURE_LINES_OPTION" "$DEFAULT_CAPTURE_LINES"
	set_tmux_option_if_unset "$SCOPE_OPTION" "$DEFAULT_SCOPE"
	set_tmux_option_if_unset "$INCLUDE_NON_AGENTS_OPTION" "$DEFAULT_INCLUDE_NON_AGENTS"
	set_tmux_option_if_unset "$PROCESS_DETECTION_OPTION" "$DEFAULT_PROCESS_DETECTION"
	set_tmux_option_if_unset "$OUTPUT_DETECTION_OPTION" "$DEFAULT_OUTPUT_DETECTION"
	set_tmux_option_if_unset "$STYLE_OPTION" "$DEFAULT_STYLE"
	set_tmux_option_if_unset "$NOTIFY_OPTION" "$DEFAULT_NOTIFY"
	set_tmux_option_if_unset "$PYTHON_OPTION" "$DEFAULT_PYTHON"
	set_tmux_option_if_unset "$REPORT_TTL_OPTION" "$DEFAULT_REPORT_TTL"
	set_tmux_option_if_unset "$SHOW_PROJECT_OPTION" "$DEFAULT_SHOW_PROJECT"
}

bind_key_if_set() {
	local option="$1"
	local default_value="$2"
	local command="$3"
	local key
	key="$(get_tmux_option "$option" "$default_value")"
	if [ -n "$key" ] && [ "$key" != "off" ]; then
		tmux bind-key "$key" run-shell "$command"
	fi
}

set_key_bindings() {
	bind_key_if_set "$TOGGLE_KEY_OPTION" "$DEFAULT_TOGGLE_KEY" "\"$SCRIPTS_DIR/toggle.sh\" \"#{pane_id}\" toggle"
	bind_key_if_set "$FOCUS_KEY_OPTION" "$DEFAULT_FOCUS_KEY" "\"$SCRIPTS_DIR/toggle.sh\" \"#{pane_id}\" focus"
	bind_key_if_set "$REFRESH_KEY_OPTION" "$DEFAULT_REFRESH_KEY" "\"$SCRIPTS_DIR/actions.sh\" refresh \"#{pane_id}\""
	bind_key_if_set "$JUMP_KEY_OPTION" "$DEFAULT_JUMP_KEY" "\"$SCRIPTS_DIR/actions.sh\" jump-owner \"#{pane_id}\""
	bind_key_if_set "$NEXT_BLOCKED_KEY_OPTION" "$DEFAULT_NEXT_BLOCKED_KEY" "\"$SCRIPTS_DIR/actions.sh\" jump-next blocked \"#{pane_id}\""
	bind_key_if_set "$NEXT_DONE_KEY_OPTION" "$DEFAULT_NEXT_DONE_KEY" "\"$SCRIPTS_DIR/actions.sh\" jump-next done \"#{pane_id}\""
	bind_key_if_set "$ACK_ALL_KEY_OPTION" "$DEFAULT_ACK_ALL_KEY" "\"$SCRIPTS_DIR/actions.sh\" ack-all \"#{pane_id}\""
}

main() {
	ensure_agent_sidebar_dirs
	set_default_options
	set_key_bindings
}

main
