#!/usr/bin/env bash

# Shared constants and tmux option names for tmux-agent-plugin.

AGENT_STATUS_OPTION_PREFIX="@agent-status"
SUPPORTED_TMUX_VERSION="2.6"

SCOPE_OPTION="@agent-status-scope"
INCLUDE_NON_AGENTS_OPTION="@agent-status-include-non-agents"
PROCESS_DETECTION_OPTION="@agent-status-process-detection"
OUTPUT_DETECTION_OPTION="@agent-status-output-detection"
CAPTURE_LINES_OPTION="@agent-status-capture-lines"
CACHE_TTL_OPTION="@agent-status-cache-ttl"
REPORT_TTL_OPTION="@agent-status-report-ttl"
NOTIFY_ACTIVE_OPTION="@agent-status-notify-active"
BINARY_OPTION="@agent-status-binary"
POPUP_KEY_OPTION="@agent-status-popup-key"
POPUP_WIDTH_OPTION="@agent-status-popup-width"
POPUP_HEIGHT_OPTION="@agent-status-popup-height"
POPUP_STYLE_OPTION="@agent-status-popup-style"
POPUP_BORDER_STYLE_OPTION="@agent-status-popup-border-style"
POPUP_TITLE_OPTION="@agent-status-popup-title"

DEFAULT_SCOPE="all"
DEFAULT_INCLUDE_NON_AGENTS="off"
DEFAULT_PROCESS_DETECTION="on"
DEFAULT_OUTPUT_DETECTION="on"
DEFAULT_CAPTURE_LINES="80"
DEFAULT_CACHE_TTL="2"
DEFAULT_REPORT_TTL="30"
DEFAULT_NOTIFY_ACTIVE="off"
DEFAULT_BINARY=""
DEFAULT_POPUP_KEY="off"
DEFAULT_POPUP_WIDTH="94%"
DEFAULT_POPUP_HEIGHT="78%"
DEFAULT_POPUP_STYLE="bg=terminal"
DEFAULT_POPUP_BORDER_STYLE="fg=#45475a,bg=terminal"
DEFAULT_POPUP_TITLE=" agents"

agent_status_data_dir() {
	printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/tmux-agent-plugin"
}

agent_status_cache_dir() {
	printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-plugin"
}
