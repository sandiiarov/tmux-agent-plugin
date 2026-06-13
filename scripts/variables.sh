#!/usr/bin/env bash

# Shared constants and tmux option names for tmux-agent-plugin.

AGENT_SIDEBAR_OPTION_PREFIX="@agent-sidebar"

REGISTERED_PANE_PREFIX="@agent-sidebar-registered-pane"
REGISTERED_SIDEBAR_PREFIX="@agent-sidebar-is-sidebar"

SUPPORTED_TMUX_VERSION="2.6"

TOGGLE_KEY_OPTION="@agent-sidebar-toggle-key"
FOCUS_KEY_OPTION="@agent-sidebar-focus-key"
REFRESH_KEY_OPTION="@agent-sidebar-refresh-key"
JUMP_KEY_OPTION="@agent-sidebar-jump-key"
NEXT_BLOCKED_KEY_OPTION="@agent-sidebar-next-blocked-key"
NEXT_DONE_KEY_OPTION="@agent-sidebar-next-done-key"
ACK_ALL_KEY_OPTION="@agent-sidebar-ack-all-key"

POSITION_OPTION="@agent-sidebar-position"
WIDTH_OPTION="@agent-sidebar-width"
MINIMUM_WIDTH_OPTION="@agent-sidebar-minimum-width"
REFRESH_INTERVAL_OPTION="@agent-sidebar-refresh-interval"
CAPTURE_LINES_OPTION="@agent-sidebar-capture-lines"
SCOPE_OPTION="@agent-sidebar-scope"
INCLUDE_NON_AGENTS_OPTION="@agent-sidebar-include-non-agents"
PROCESS_DETECTION_OPTION="@agent-sidebar-process-detection"
OUTPUT_DETECTION_OPTION="@agent-sidebar-output-detection"
STYLE_OPTION="@agent-sidebar-style"
NOTIFY_OPTION="@agent-sidebar-notify"
PYTHON_OPTION="@agent-sidebar-python"
REPORT_TTL_OPTION="@agent-sidebar-report-ttl"
SHOW_PROJECT_OPTION="@agent-sidebar-show-project"

DEFAULT_TOGGLE_KEY="Tab"
DEFAULT_FOCUS_KEY="Bspace"
DEFAULT_REFRESH_KEY="R"
DEFAULT_JUMP_KEY="Enter"
DEFAULT_NEXT_BLOCKED_KEY="B"
DEFAULT_NEXT_DONE_KEY="D"
DEFAULT_ACK_ALL_KEY="A"

DEFAULT_POSITION="left"
DEFAULT_WIDTH="40"
DEFAULT_MINIMUM_WIDTH="71"
DEFAULT_REFRESH_INTERVAL="2"
DEFAULT_CAPTURE_LINES="80"
DEFAULT_SCOPE="current-session"
DEFAULT_INCLUDE_NON_AGENTS="off"
DEFAULT_PROCESS_DETECTION="on"
DEFAULT_OUTPUT_DETECTION="on"
DEFAULT_STYLE="on"
DEFAULT_NOTIFY="off"
DEFAULT_PYTHON="python3"
DEFAULT_REPORT_TTL="30"
DEFAULT_SHOW_PROJECT="on"

agent_sidebar_data_dir() {
	printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/tmux-agent-plugin"
}

agent_sidebar_cache_dir() {
	printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-plugin"
}

agent_sidebar_width_file() {
	printf '%s\n' "$(agent_sidebar_data_dir)/directory_widths.tsv"
}
