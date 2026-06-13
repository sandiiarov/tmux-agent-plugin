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

main() {
	ensure_agent_status_dirs
	set_default_options
	set_format_helpers
}

main
