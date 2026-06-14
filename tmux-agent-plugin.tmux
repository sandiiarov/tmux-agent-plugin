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
	set_tmux_option_if_unset "$POPUP_PREVIEW_LINES_OPTION" "$DEFAULT_POPUP_PREVIEW_LINES"
	set_tmux_option_if_unset "$POPUP_FZF_OPTS_OPTION" "$DEFAULT_POPUP_FZF_OPTS"
	set_tmux_option_if_unset "$POPUP_SHOW_STATUS_ICON_OPTION" "$DEFAULT_POPUP_SHOW_STATUS_ICON"
	set_tmux_option_if_unset "$POPUP_SHOW_AGENT_ICON_OPTION" "$DEFAULT_POPUP_SHOW_AGENT_ICON"
	set_tmux_option_if_unset "$POPUP_SHOW_AGENT_LABEL_OPTION" "$DEFAULT_POPUP_SHOW_AGENT_LABEL"
	set_agent_icon_defaults
	set_tmux_option_if_unset "$VIEW_KEY_OPTION" "$DEFAULT_VIEW_KEY"
}

set_agent_icon_defaults() {
	set_tmux_option_if_unset "@agent-status-agent-icon-pi" ""
	set_tmux_option_if_unset "@agent-status-agent-icon-claude" ""
	set_tmux_option_if_unset "@agent-status-agent-icon-codex" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-gemini" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-opencode" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-cursor-agent" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-copilot" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-amp" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-droid" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-grok" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-kimi" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-kiro" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-kilo" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-qodercli" "󰚩"
	set_tmux_option_if_unset "@agent-status-agent-icon-hermes" "󰚩"
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

unbind_view_root_key_if_owned() {
	local key="$1" binding
	[ -n "$key" ] && [ "$key" != "off" ] || return 0
	binding="$(tmux list-keys -T root "$key" 2>/dev/null || true)"
	case "$binding" in
		*"$SCRIPTS_DIR/view.sh"*) tmux unbind-key -n "$key" 2>/dev/null || true ;;
	esac
}

cleanup_old_view_root_keys() {
	unbind_view_root_key_if_owned "$(get_tmux_option "$VIEW_UP_KEY_OPTION" "$DEFAULT_VIEW_UP_KEY")"
	unbind_view_root_key_if_owned "$(get_tmux_option "$VIEW_DOWN_KEY_OPTION" "$DEFAULT_VIEW_DOWN_KEY")"
	unbind_view_root_key_if_owned "$(get_tmux_option "$VIEW_ENTER_KEY_OPTION" "$DEFAULT_VIEW_ENTER_KEY")"
	unbind_view_root_key_if_owned "$(get_tmux_option "$VIEW_EXIT_KEY_OPTION" "$DEFAULT_VIEW_EXIT_KEY")"
	unbind_view_root_key_if_owned "C-n"
	unbind_view_root_key_if_owned "C-p"
	unbind_view_root_key_if_owned "C-o"
	unbind_view_root_key_if_owned "C-x"
}

bind_view_key() {
	local key width height style border_style title
	cleanup_old_view_root_keys

	key="$(get_tmux_option "$VIEW_KEY_OPTION" "$DEFAULT_VIEW_KEY")"
	if [ -z "$key" ] || [ "$key" = "off" ]; then
		return 0
	fi

	width="$(get_tmux_option "$POPUP_WIDTH_OPTION" "$DEFAULT_POPUP_WIDTH")"
	height="$(get_tmux_option "$POPUP_HEIGHT_OPTION" "$DEFAULT_POPUP_HEIGHT")"
	style="$(get_tmux_option "$POPUP_STYLE_OPTION" "$DEFAULT_POPUP_STYLE")"
	border_style="$(get_tmux_option "$POPUP_BORDER_STYLE_OPTION" "$DEFAULT_POPUP_BORDER_STYLE")"
	title="$(get_tmux_option "$POPUP_TITLE_OPTION" "$DEFAULT_POPUP_TITLE")"

	# Compatibility: older configs may use @agent-status-view-key. It now opens
	# the same fzf popup navigator as @agent-status-popup-key instead of creating
	# panes or running the slower shell-rendered preview.
	tmux bind-key "$key" display-popup -E -w "$width" -h "$height" -s "$style" -S "$border_style" -T "$title" "$SCRIPTS_DIR/popup.sh"
}

main() {
	ensure_agent_status_dirs
	set_default_options
	set_format_helpers
	bind_popup_key
	bind_view_key
}

main
