#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCKET="tmux-agent-values-smoke-$$"
TMP_DIR="$(mktemp -d)"

cleanup() {
	tmux -L "$SOCKET" kill-server 2>/dev/null || true
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export XDG_CACHE_HOME="$TMP_DIR/cache"
export XDG_DATA_HOME="$TMP_DIR/data"

run_tmux() {
	tmux -L "$SOCKET" "$@"
}

run_shell_wait() {
	local target="$1"
	local command="$2"
	local done_file
	done_file="$TMP_DIR/run-shell-$RANDOM.done"
	run_tmux run-shell -t "$target" "($command) && printf done > '$done_file'"
	wait_for_file "$done_file"
}

wait_for_file() {
	local file="$1"
	local tries=30
	while [ "$tries" -gt 0 ]; do
		[ -s "$file" ] && return 0
		sleep 0.2
		tries=$((tries - 1))
	done
	return 1
}

run_tmux -f /dev/null new-session -d -s tap -x 120 -y 30 "sleep 60"
normal_pane="$(run_tmux list-panes -t tap -F '#{pane_id}')"
run_tmux split-window -t "$normal_pane" -h "bash -lc 'printf \"Claude needs permission to run this command.\\nDo you want to proceed? [y/N]\\n\"; exec -a claude sleep 60'"
agent_pane="$(run_tmux list-panes -t tap -F '#{pane_id}' | tail -1)"

run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/tmux-agent-plugin.tmux'"
summary_option="$(run_tmux show-option -gqv @agent-status-summary)"
[ -n "$summary_option" ]

json_file="$TMP_DIR/agents.json"
run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/agents.sh' json --refresh > '$json_file'"
wait_for_file "$json_file"
python3 - "$json_file" "$agent_pane" <<'PY'
import json
import sys
path, pane_id = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
agents = data["agents"]
assert data["counts"]["all"] >= 1, data
match = [item for item in agents if item["pane"]["id"] == pane_id]
assert match, data
item = match[0]
assert item["agent"] == "claude", item
assert item["status"] == "blocked", item
assert item["target"] == "tap:0.1", item
PY

popup_file="$TMP_DIR/popup.txt"
run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/popup.sh' --list > '$popup_file'"
wait_for_file "$popup_file"
grep -F 'claude' "$popup_file" >/dev/null
grep -F "$agent_pane" "$popup_file" >/dev/null

icon_popup_file="$TMP_DIR/popup-icons.txt"
run_tmux set-option -g @agent-status-nerd-icons on
run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/popup.sh' --list > '$icon_popup_file'"
wait_for_file "$icon_popup_file"
grep -F ' claude' "$icon_popup_file" >/dev/null

view_file="$TMP_DIR/view.txt"
run_shell_wait "$normal_pane" "AGENT_STATUS_TARGET_PANE='$normal_pane' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/view.sh' render > '$view_file'"
wait_for_file "$view_file"
grep -F 'tap' "$view_file" >/dev/null
grep -F ' claude' "$view_file" >/dev/null

run_tmux set-option -g @agent-status-view-key a
run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/tmux-agent-plugin.tmux'"
run_shell_wait "$normal_pane" "AGENT_STATUS_TARGET_PANE='$normal_pane' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/view.sh' toggle"
sleep 0.5
view_pane="$(run_tmux show-option -wqv -t "$normal_pane" @agent-status-view-pane)"
[ -n "$view_pane" ]
run_tmux display-message -p -t "$view_pane" '#{pane_id}' >/dev/null
run_shell_wait "$normal_pane" "AGENT_STATUS_TARGET_PANE='$normal_pane' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/view.sh' down"
run_shell_wait "$normal_pane" "AGENT_STATUS_TARGET_PANE='$normal_pane' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/view.sh' up"
run_shell_wait "$normal_pane" "AGENT_STATUS_TARGET_PANE='$normal_pane' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/view.sh' toggle"
view_closed=0
for _ in $(seq 1 30); do
	if ! run_tmux list-panes -F '#{pane_title}' | grep -Fx 'tmux-agent-plugin-view' >/dev/null; then
		view_closed=1
		break
	fi
	sleep 0.2
done
[ "$view_closed" -eq 1 ]

run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/popup.sh' --select-first"
sleep 0.2
active_pane="$(run_tmux display-message -p '#{pane_id}')"
[ "$active_pane" = "$agent_pane" ]

count_file="$TMP_DIR/count.txt"
run_shell_wait "$normal_pane" "XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_DATA_HOME='$XDG_DATA_HOME' '$ROOT_DIR/scripts/agents.sh' count blocked > '$count_file'"
wait_for_file "$count_file"
blocked_count="$(tr -d '[:space:]' < "$count_file")"
[ "$blocked_count" -ge 1 ]

printf 'tmux-agent-plugin values smoke test passed\n'
printf 'agent_pane=%s blocked_count=%s\n' "$agent_pane" "$blocked_count"
