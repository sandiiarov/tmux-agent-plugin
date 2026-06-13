#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# shellcheck source=scripts/variables.sh
source "$SCRIPTS_DIR/variables.sh"
# shellcheck source=scripts/helpers.sh
source "$SCRIPTS_DIR/helpers.sh"

set_default_options() {
	set_tmux_option_if_unset "$SCOPE_OPTION" "$DEFAULT_SCOPE"
	set_tmux_option_if_unset "$INCLUDE_NON_AGENTS_OPTION" "$DEFAULT_INCLUDE_NON_AGENTS"
	set_tmux_option_if_unset "$PROCESS_DETECTION_OPTION" "$DEFAULT_PROCESS_DETECTION"
	set_tmux_option_if_unset "$OUTPUT_DETECTION_OPTION" "$DEFAULT_OUTPUT_DETECTION"
	set_tmux_option_if_unset "$CAPTURE_LINES_OPTION" "$DEFAULT_CAPTURE_LINES"
	set_tmux_option_if_unset "$CACHE_TTL_OPTION" "$DEFAULT_CACHE_TTL"
	set_tmux_option_if_unset "$REPORT_TTL_OPTION" "$DEFAULT_REPORT_TTL"
	set_tmux_option_if_unset "$NOTIFY_ACTIVE_OPTION" "$DEFAULT_NOTIFY_ACTIVE"
	set_tmux_option_if_unset "$BINARY_OPTION" "$DEFAULT_BINARY"
	set_tmux_option_if_unset "$NERD_ICONS_OPTION" "$DEFAULT_NERD_ICONS"
	set_tmux_option_if_unset "$POPUP_KEY_OPTION" "$DEFAULT_POPUP_KEY"
	set_tmux_option_if_unset "$POPUP_WIDTH_OPTION" "$DEFAULT_POPUP_WIDTH"
	set_tmux_option_if_unset "$POPUP_HEIGHT_OPTION" "$DEFAULT_POPUP_HEIGHT"
	set_tmux_option_if_unset "$POPUP_STYLE_OPTION" "$DEFAULT_POPUP_STYLE"
	set_tmux_option_if_unset "$POPUP_BORDER_STYLE_OPTION" "$DEFAULT_POPUP_BORDER_STYLE"
	set_tmux_option_if_unset "$POPUP_TITLE_OPTION" "$DEFAULT_POPUP_TITLE"
	set_tmux_option_if_unset "$VIEW_KEY_OPTION" "$DEFAULT_VIEW_KEY"
	set_tmux_option_if_unset "$VIEW_WIDTH_OPTION" "$DEFAULT_VIEW_WIDTH"
	set_tmux_option_if_unset "$VIEW_REFRESH_OPTION" "$DEFAULT_VIEW_REFRESH"
	set_tmux_option_if_unset "$VIEW_UP_KEY_OPTION" "$DEFAULT_VIEW_UP_KEY"
	set_tmux_option_if_unset "$VIEW_DOWN_KEY_OPTION" "$DEFAULT_VIEW_DOWN_KEY"
	set_tmux_option_if_unset "$VIEW_ENTER_KEY_OPTION" "$DEFAULT_VIEW_ENTER_KEY"
	set_tmux_option_if_unset "$VIEW_EXIT_KEY_OPTION" "$DEFAULT_VIEW_EXIT_KEY"
}

set_format_helpers() {
	# Users can embed these with #{E:@agent-status-summary}, etc.
	set_tmux_option "@agent-status-summary" "#($SCRIPTS_DIR/agents.sh summary)"
	set_tmux_option "@agent-status-compact" "#($SCRIPTS_DIR/agents.sh compact)"
	set_tmux_option "@agent-status-spinner" "#($SCRIPTS_DIR/agents.sh spinner)"
	set_tmux_option "@agent-status-count" "#($SCRIPTS_DIR/agents.sh count all)"
	set_tmux_option "@agent-status-working-count" "#($SCRIPTS_DIR/agents.sh count working)"
	set_tmux_option "@agent-status-blocked-count" "#($SCRIPTS_DIR/agents.sh count blocked)"
	set_tmux_option "@agent-status-done-count" "#($SCRIPTS_DIR/agents.sh count done)"
	set_tmux_option "@agent-status-json" "#($SCRIPTS_DIR/agents.sh json)"
}

bind_popup_key() {
	local key width height style border_style title
	key="$(get_tmux_option "$POPUP_KEY_OPTION" "$DEFAULT_POPUP_KEY")"
	if [ -z "$key" ] || [ "$key" = "off" ]; then
		return 0
	fi

	width="$(get_tmux_option "$POPUP_WIDTH_OPTION" "$DEFAULT_POPUP_WIDTH")"
	height="$(get_tmux_option "$POPUP_HEIGHT_OPTION" "$DEFAULT_POPUP_HEIGHT")"
	style="$(get_tmux_option "$POPUP_STYLE_OPTION" "$DEFAULT_POPUP_STYLE")"
	border_style="$(get_tmux_option "$POPUP_BORDER_STYLE_OPTION" "$DEFAULT_POPUP_BORDER_STYLE")"
	title="$(get_tmux_option "$POPUP_TITLE_OPTION" "$DEFAULT_POPUP_TITLE")"

	tmux bind-key "$key" display-popup -E -w "$width" -h "$height" -s "$style" -S "$border_style" -T "$title" "$SCRIPTS_DIR/popup.sh"
}

bind_view_key() {
	local key up_key down_key enter_key exit_key
	key="$(get_tmux_option "$VIEW_KEY_OPTION" "$DEFAULT_VIEW_KEY")"
	if [ -z "$key" ] || [ "$key" = "off" ]; then
		return 0
	fi

	tmux bind-key "$key" run-shell "AGENT_STATUS_TARGET_PANE='#{pane_id}' '$SCRIPTS_DIR/view.sh' toggle"

	up_key="$(get_tmux_option "$VIEW_UP_KEY_OPTION" "$DEFAULT_VIEW_UP_KEY")"
	down_key="$(get_tmux_option "$VIEW_DOWN_KEY_OPTION" "$DEFAULT_VIEW_DOWN_KEY")"
	enter_key="$(get_tmux_option "$VIEW_ENTER_KEY_OPTION" "$DEFAULT_VIEW_ENTER_KEY")"
	exit_key="$(get_tmux_option "$VIEW_EXIT_KEY_OPTION" "$DEFAULT_VIEW_EXIT_KEY")"

	if [ -n "$up_key" ] && [ "$up_key" != "off" ]; then
		tmux bind-key -n "$up_key" run-shell "AGENT_STATUS_TARGET_PANE='#{pane_id}' '$SCRIPTS_DIR/view.sh' up"
	fi
	if [ -n "$down_key" ] && [ "$down_key" != "off" ]; then
		tmux bind-key -n "$down_key" run-shell "AGENT_STATUS_TARGET_PANE='#{pane_id}' '$SCRIPTS_DIR/view.sh' down"
	fi
	if [ -n "$enter_key" ] && [ "$enter_key" != "off" ]; then
		tmux bind-key -n "$enter_key" run-shell "AGENT_STATUS_TARGET_PANE='#{pane_id}' '$SCRIPTS_DIR/view.sh' enter"
	fi
	if [ -n "$exit_key" ] && [ "$exit_key" != "off" ]; then
		tmux bind-key -n "$exit_key" run-shell "AGENT_STATUS_TARGET_PANE='#{pane_id}' '$SCRIPTS_DIR/view.sh' close"
	fi
}

main() {
	ensure_agent_status_dirs
	set_default_options
	set_format_helpers
	bind_popup_key
	bind_view_key
}

main
