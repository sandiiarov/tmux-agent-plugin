#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.tmux/plugins/tmux-agent-plugin}"
SOCKET="${SOCKET:-tmux-agent-plugin-docker-$$}"
TMP_DIR="$(mktemp -d)"

cleanup() {
	tmux -L "$SOCKET" kill-server 2>/dev/null || true
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export XDG_CACHE_HOME="$TMP_DIR/cache"
export XDG_DATA_HOME="$TMP_DIR/data"
export PATH="/usr/local/bin:$PATH"

run_tmux() {
	tmux -L "$SOCKET" "$@"
}

wait_for_file() {
	local file="$1" tries=50
	while [ "$tries" -gt 0 ]; do
		[ -s "$file" ] && return 0
		sleep 0.1
		tries=$((tries - 1))
	done
	printf 'timed out waiting for %s\n' "$file" >&2
	return 1
}

run_shell_wait() {
	local target="$1" command="$2" done_file
	done_file="$TMP_DIR/run-shell-$RANDOM.done"
	run_tmux run-shell -t "$target" "($command) && printf done > '$done_file'"
	wait_for_file "$done_file"
}

assert_contains() {
	local needle="$1" file="$2"
	if ! grep -F "$needle" "$file" >/dev/null; then
		printf 'expected %q in %s\n' "$needle" "$file" >&2
		printf '%s\n' '--- file ---' >&2
		cat "$file" >&2
		printf '%s\n' '------------' >&2
		return 1
	fi
}

printf '[1/8] verifying tooling\n'
tmux -V
cargo --version
git --version
[ -x "$HOME/.tmux/plugins/tpm/tpm" ]
[ -x "$PLUGIN_DIR/tmux-agent-plugin.tmux" ]

printf '[2/8] loading plugin through TPM config\n'
cat > "$TMP_DIR/tmux.conf" <<EOF
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'sandiiarov/tmux-agent-plugin'
set -g @agent-status-popup-key 'off'
set -g @agent-status-view-key 'a'
set -g @agent-status-view-width '20%'
set -g @agent-status-view-refresh '1'
set -g @agent-status-nerd-icons 'on'
set -g @agent-status-notify-active 'off'
run '$HOME/.tmux/plugins/tpm/tpm'
EOF

run_tmux -f "$TMP_DIR/tmux.conf" new-session -d -s agents -n work 'bash --noprofile --norc'
shell_pane="$(run_tmux display-message -p -t agents:work '#{pane_id}')"
# Detached TPM startup can race with assertions; source the plugin explicitly so
# option defaults and bindings are deterministic in this harness.
run_shell_wait "$shell_pane" "'$PLUGIN_DIR/tmux-agent-plugin.tmux'"

printf '[3/8] starting fake pi/claude/codex/gemini agent panes\n'
pi_pane="$(run_tmux split-window -d -t "$shell_pane" -h -P -F '#{pane_id}' "FAKE_AGENT_STATE=idle FAKE_AGENT_LABEL=pi pi")"
claude_pane="$(run_tmux split-window -d -t "$shell_pane" -v -P -F '#{pane_id}' "FAKE_AGENT_STATE=working FAKE_AGENT_LABEL=claude claude")"
codex_pane="$(run_tmux new-window -d -t agents -n other -P -F '#{pane_id}' "FAKE_AGENT_STATE=blocked FAKE_AGENT_LABEL=codex codex")"
gemini_pane="$(run_tmux split-window -d -t "$codex_pane" -h -P -F '#{pane_id}' "FAKE_AGENT_STATE=done FAKE_AGENT_LABEL=gemini gemini")"
run_tmux select-window -t agents:work
run_tmux select-pane -t "$shell_pane"
sleep 0.5

printf '[4/8] collecting JSON values\n'
json_file="$TMP_DIR/agents.json"
run_shell_wait "$shell_pane" "'$PLUGIN_DIR/scripts/agents.sh' json --refresh > '$json_file'"
python3 - "$json_file" "$pi_pane" "$claude_pane" "$codex_pane" "$gemini_pane" <<'PY'
import json
import sys
path, pi_pane, claude_pane, codex_pane, gemini_pane = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
by_pane = {item["pane"]["id"]: item for item in data["agents"]}
for pane in [pi_pane, claude_pane, codex_pane, gemini_pane]:
    assert pane in by_pane, (pane, data)
assert by_pane[pi_pane]["agent"] == "pi", by_pane[pi_pane]
assert by_pane[claude_pane]["agent"] == "claude", by_pane[claude_pane]
assert by_pane[codex_pane]["agent"] == "codex", by_pane[codex_pane]
assert by_pane[gemini_pane]["agent"] == "gemini", by_pane[gemini_pane]
assert by_pane[claude_pane]["status"] == "working", by_pane[claude_pane]
assert by_pane[codex_pane]["status"] == "blocked", by_pane[codex_pane]
assert data["counts"]["all"] >= 4, data["counts"]
assert data["counts"]["working"] >= 1, data["counts"]
assert data["counts"]["blocked"] >= 1, data["counts"]
PY

printf '[5/8] checking popup/list formatting\n'
popup_file="$TMP_DIR/popup.txt"
run_shell_wait "$shell_pane" "'$PLUGIN_DIR/scripts/popup.sh' --list > '$popup_file'"
assert_contains ' pi' "$popup_file"
assert_contains ' claude' "$popup_file"

printf '[6/8] checking popup-view render format\n'
view_file="$TMP_DIR/view.txt"
run_shell_wait "$shell_pane" "AGENT_STATUS_TARGET_PANE='$shell_pane' '$PLUGIN_DIR/scripts/view.sh' render > '$view_file'"
assert_contains '' "$view_file"
assert_contains 'agents' "$view_file"
assert_contains ' pi' "$view_file"
assert_contains ' claude' "$view_file"
assert_contains 'codex' "$view_file"
assert_contains 'gemini' "$view_file"
assert_contains '│' "$view_file"

printf '[7/8] checking popup-view binding and controls\n'
run_tmux list-keys | grep -F 'display-popup' | grep -F 'view.sh' >/dev/null
for key in C-n C-p C-o C-x; do
	if run_tmux list-keys -T root "$key" 2>/dev/null | grep -F 'view.sh' >/dev/null; then
		printf 'view should not bind root %s outside the popup\n' "$key" >&2
		exit 1
	fi
done

selected_tsv="$TMP_DIR/selected.tsv"
run_shell_wait "$shell_pane" "'$PLUGIN_DIR/scripts/agents.sh' tsv --refresh > '$selected_tsv'"
expected_first_pane="$(awk -F '\t' 'NR == 2 { print $9 }' "$selected_tsv")"
expected_second_pane="$(awk -F '\t' 'NR == 3 { print $9 }' "$selected_tsv")"
[ -n "$expected_first_pane" ]
[ -n "$expected_second_pane" ]

# C-x exits the popup without jumping.
run_tmux select-pane -t "$shell_pane"
run_shell_wait "$shell_pane" "printf '\\030' | '$PLUGIN_DIR/scripts/view.sh' popup"
active_after_close="$(run_tmux display-message -p '#{pane_id}')"
[ "$active_after_close" = "$shell_pane" ]

# C-n moves down inside the popup, then C-o jumps to that selected pane.
run_shell_wait "$shell_pane" "printf '\\016\\017' | '$PLUGIN_DIR/scripts/view.sh' popup"
active_after_jump="$(run_tmux display-message -p '#{pane_id}')"
[ "$active_after_jump" = "$expected_second_pane" ]

# Explicit jump helper is useful for non-interactive tests and should not create panes.
run_shell_wait "$active_after_jump" "'$PLUGIN_DIR/scripts/view.sh' jump-index 0"
active_after_helper="$(run_tmux display-message -p '#{pane_id}')"
[ "$active_after_helper" = "$expected_first_pane" ]
if run_tmux list-panes -F '#{pane_title}' | grep -Fx 'tmux-agent-plugin-view' >/dev/null; then
	printf 'popup view should not create tmux panes\n' >&2
	run_tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_title}' >&2
	exit 1
fi

printf '[8/8] checking notification command\n'
notify_file="$TMP_DIR/notify.json"
run_shell_wait "$shell_pane" "'$PLUGIN_DIR/scripts/notify.sh' json > '$notify_file'"
python3 - "$notify_file" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert "events" in payload, payload
PY

printf 'docker integration smoke test passed\n'
