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

DEFAULT_SCOPE="all"
DEFAULT_INCLUDE_NON_AGENTS="off"
DEFAULT_PROCESS_DETECTION="on"
DEFAULT_OUTPUT_DETECTION="on"
DEFAULT_CAPTURE_LINES="80"
DEFAULT_CACHE_TTL="2"
DEFAULT_REPORT_TTL="30"
DEFAULT_NOTIFY_ACTIVE="off"
DEFAULT_BINARY=""

agent_status_data_dir() {
	printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/tmux-agent-plugin"
}

agent_status_cache_dir() {
	printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-plugin"
}
