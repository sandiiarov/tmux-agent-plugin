#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCKET="tmux-agent-plugin-smoke-$$"
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

shell_join() {
	local out="" item
	for item in "$@"; do
		printf -v item '%q' "$item"
		out+=" ${item}"
	done
	printf '%s' "${out# }"
}

run_shell() {
	local target="$1"
	shift
	run_tmux run-shell -t "$target" "$(shell_join "$@")"
}

wait_for_file() {
	local file="$1"
	local tries=20
	while [ "$tries" -gt 0 ]; do
		[ -s "$file" ] && return 0
		sleep 0.2
		tries=$((tries - 1))
	done
	return 1
}

run_tmux -f /dev/null new-session -d -s tap -x 160 -y 30 "sleep 60"
normal_pane="$(run_tmux list-panes -t tap -F '#{pane_id}')"
run_tmux split-window -t "$normal_pane" -h "bash -lc 'printf \"Claude needs permission to run this command.\\nDo you want to proceed? [y/N]\\n\"; exec -a claude sleep 60'"
blocked_pane="$(run_tmux list-panes -t tap -F '#{pane_id}' | tail -1)"
run_tmux select-pane -t "$normal_pane"

# Lifecycle + renderer smoke test.
run_shell "$normal_pane" "$ROOT_DIR/scripts/toggle.sh" "$normal_pane" toggle
sleep 3
sidebar_pane="$(run_tmux show-options -gqv "@agent-sidebar-registered-pane-${normal_pane}")"
[ -n "$sidebar_pane" ]
[ "$(run_tmux list-panes -t tap -F '#{pane_id}' | wc -l | tr -d ' ')" = "3" ]
sidebar_capture="$(run_tmux capture-pane -t "$sidebar_pane" -p -S -30)"
case "$sidebar_capture" in
	*claude*) ;;
	*) printf 'Sidebar did not render claude pane:\n%s\n' "$sidebar_capture" >&2; exit 1 ;;
esac
run_shell "$normal_pane" "$ROOT_DIR/scripts/toggle.sh" "$normal_pane" toggle
sleep 1
[ "$(run_tmux list-panes -t tap -F '#{pane_id}' | wc -l | tr -d ' ')" = "2" ]

# Navigation to blocked pane.
run_tmux select-pane -t "$normal_pane"
run_shell "$normal_pane" "$ROOT_DIR/scripts/actions.sh" jump-next blocked "$normal_pane"
sleep 2
active_pane="$(run_tmux list-panes -t tap -F '#{pane_active} #{pane_id}' | awk '$1 == 1 { print $2 }')"
[ "$active_pane" = "$blocked_pane" ]

# Explicit done report + acknowledge-on-jump.
run_tmux select-pane -t "$normal_pane"
XDG_CACHE_HOME="$XDG_CACHE_HOME" "$ROOT_DIR/scripts/report.py" --pane "$blocked_pane" --agent claude --state done --label finished --ttl -1 --quiet
run_shell "$normal_pane" "$ROOT_DIR/scripts/actions.sh" jump-next done "$normal_pane"
sleep 2
active_pane="$(run_tmux list-panes -t tap -F '#{pane_active} #{pane_id}' | awk '$1 == 1 { print $2 }')"
[ "$active_pane" = "$blocked_pane" ]
state_file="$XDG_CACHE_HOME/tmux-agent-plugin/pane_state.json"
wait_for_file "$state_file"
cached_state="$(python3 - "$state_file" "$blocked_pane" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as handle:
    data = json.load(handle)
print(data[sys.argv[2]]["state"])
PY
)"
[ "$cached_state" = "idle" ]

printf 'tmux-agent-plugin smoke test passed\n'
printf 'normal=%s blocked=%s cached_state=%s\n' "$normal_pane" "$blocked_pane" "$cached_state"
