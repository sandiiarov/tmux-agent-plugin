#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_on() {
	case "${1:-}" in
		1|on|ON|true|TRUE|yes|YES|y|Y) return 0 ;;
		*) return 1 ;;
	esac
}

tmux_option() {
	local option="$1" default="${2:-}"
	local value
	value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
	printf '%s\n' "${value:-$default}"
}

nerd_icons_enabled() {
	is_on "$(tmux_option @agent-status-nerd-icons off)"
}

show_status_icon() {
	is_on "$(tmux_option @agent-status-popup-show-status-icon on)"
}

show_agent_icon() {
	local value
	value="$(tmux_option @agent-status-popup-show-agent-icon auto)"
	case "$value" in
		auto|AUTO|'') nerd_icons_enabled ;;
		*) is_on "$value" ;;
	esac
}

show_agent_label() {
	is_on "$(tmux_option @agent-status-popup-show-agent-label off)"
}

supported_agents() {
	printf '%s\n' \
		pi claude codex gemini opencode cursor-agent copilot amp droid grok kimi kiro kilo qodercli hermes
}

default_agent_icon() {
	case "$1" in
		pi) printf '\n' ;;
		claude) printf '\n' ;;
		*) printf '󰚩\n' ;;
	esac
}

agent_icon_env_name() {
	local agent="$1"
	agent="${agent//-/_}"
	printf 'AGENT_STATUS_ICON_%s\n' "$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')"
}

export_agent_icon_options() {
	local agent option value env_name
	while IFS= read -r agent; do
		[ -n "$agent" ] || continue
		option="@agent-status-agent-icon-$agent"
		value="$(tmux_option "$option" "$(default_agent_icon "$agent")")"
		env_name="$(agent_icon_env_name "$agent")"
		export "$env_name=$value"
	done < <(supported_agents)
}

usage() {
	cat <<'EOF'
usage: popup.sh [--list|--select-first]

Open an fzf navigator over tmux-agent-plugin agents.

Options:
  --list          Print formatted fzf rows and exit.
  --select-first  Jump to the first row without opening fzf; useful for tests.
EOF
}

format_rows() {
	local nerd_icons="off"
	local show_status="off"
	local show_icon="off"
	local show_label="off"
	local refresh_arg=""
	if nerd_icons_enabled; then
		nerd_icons="on"
	fi
	if show_status_icon; then
		show_status="on"
	fi
	if show_agent_icon; then
		show_icon="on"
	fi
	if show_agent_label; then
		show_label="on"
	fi
	if is_on "${AGENT_STATUS_REFRESH:-off}"; then
		refresh_arg="--refresh"
	fi
	export AGENT_STATUS_NERD_ICONS="$nerd_icons"
	export AGENT_STATUS_SHOW_STATUS_ICON="$show_status"
	export AGENT_STATUS_SHOW_AGENT_ICON="$show_icon"
	export AGENT_STATUS_SHOW_AGENT_LABEL="$show_label"
	export_agent_icon_options

	# ANSI colors and UTF-8 glyphs confuse byte-based printf padding, so compute display cells.
	if [ -n "$refresh_arg" ]; then
		"$CURRENT_DIR/agents.sh" tsv "$refresh_arg"
	else
		"$CURRENT_DIR/agents.sh" tsv
	fi | perl -CSDA -Mutf8 -MEncode=decode -F'\t' -lane '
		BEGIN {
			$esc = "\e";
			$reset = "$esc\[0m";
			$red = "$esc\[31m";
			$yellow = "$esc\[33m";
			$green = "$esc\[32m";
			$blue = "$esc\[34m";
			$dim = "$esc\[2m";
		}

		sub enabled {
			my ($name) = @_;
			return ($ENV{$name} // "") =~ /^(1|on|true|yes|y)$/i;
		}

		sub agent_icon_env_name {
			my ($agent) = @_;
			$agent =~ s/[^A-Za-z0-9]/_/g;
			return "AGENT_STATUS_ICON_" . uc($agent);
		}

		sub agent_icon {
			my ($agent) = @_;
			return "" unless enabled("AGENT_STATUS_SHOW_AGENT_ICON");
			my $icon = $ENV{agent_icon_env_name($agent)} // "";
			return decode("UTF-8", $icon);
		}

		sub agent_label {
			my ($agent) = @_;
			return "" unless enabled("AGENT_STATUS_SHOW_AGENT_LABEL");
			return $agent;
		}

		sub status_icon {
			my ($status) = @_;
			return "$red⚠$reset" if $status eq "blocked";
			return "$yellow●$reset" if $status eq "working";
			return "$green✓$reset" if $status eq "done";
			return "$blue•$reset" if $status eq "idle";
			return "$dim?$reset";
		}

		next if $. == 1;
		my ($status, $agent, $target, $name, $session, $window, $pane, $cwd, $pane_id, $window_id, $session_id) = @F;
		my @parts;
		push @parts, status_icon($status) if enabled("AGENT_STATUS_SHOW_STATUS_ICON");
		my $agent_display = join " ", grep { $_ ne "" } (agent_icon($agent), agent_label($agent));
		push @parts, $agent_display if $agent_display ne "";
		my $display = join(" ", @parts);
		$display .= "   " if $display ne "";
		$display .= ($name // "");
		print join "\t", $pane_id, $window_id, $session_id, $display;
	'
}

focus_pane() {
	local pane_id="$1"
	local window_id="${2:-}"
	local session_id="${3:-}"

	if [ -z "$pane_id" ]; then
		return 1
	fi

	if [ -z "$session_id" ]; then
		session_id="$(tmux display-message -p -t "$pane_id" '#{session_id}' 2>/dev/null || true)"
	fi
	if [ -z "$window_id" ]; then
		window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}' 2>/dev/null || true)"
	fi

	if [ -n "$session_id" ]; then
		tmux switch-client -t "$session_id" 2>/dev/null || true
	fi
	if [ -n "$window_id" ]; then
		tmux select-window -t "$window_id" 2>/dev/null || true
	fi
	tmux select-pane -t "$pane_id" 2>/dev/null || true
}

preview_lines() {
	local value
	value="$(tmux show-option -gqv @agent-status-popup-preview-lines 2>/dev/null || true)"
	case "$value" in
		''|*[!0-9]*) printf '200\n' ;;
		*) printf '%s\n' "$value" ;;
	esac
}

preview_pane() {
	local pane_id="$1" lines
	lines="$(preview_lines)"
	if [ -n "$pane_id" ]; then
		tmux capture-pane -t "$pane_id" -e -p -J -S "-$lines" 2>/dev/null || true
	fi
	printf '\n\033[2menter: jump · esc: close · C-r: refresh\033[0m\n'
}

popup_fzf_opts() {
	# Use display-message so tmux format references in the option are expanded
	# at popup time, e.g. Catppuccin's #{@thm_bg} / #{@thm_fg} variables.
	tmux display-message -p '#{E:@agent-status-popup-fzf-opts}' 2>/dev/null || true
}

open_popup() {
	local rows selected pane_id window_id session_id extra_opts
	rows="$(format_rows)"
	if [ -z "$rows" ]; then
		printf 'No agent panes found.\n'
		sleep 1
		return 0
	fi

	if ! command -v fzf >/dev/null 2>&1; then
		printf 'tmux-agent-plugin popup requires fzf.\n\n'
		printf 'Install fzf, or consume values directly with:\n'
		printf '  %s/agents.sh json\n' "$CURRENT_DIR"
		sleep 4
		return 1
	fi

	extra_opts="$(popup_fzf_opts)"
	set --
	if [ -n "$extra_opts" ]; then
		# User-controlled tmux option. Word-split intentionally so users can pass
		# normal fzf flags such as: --color=fg:-1,bg:-1,border:8
		eval "set -- $extra_opts"
	fi

	selected="$(printf '%s\n' "$rows" | fzf \
		--ansi \
		--delimiter='\t' \
		--with-nth=4 \
		--nth=4 \
		--prompt='agents> ' \
		--preview="'$CURRENT_DIR/popup.sh' --preview {1}" \
		--preview-window='right,80%,border-left,nowrap,follow,noinfo' \
		--bind='ctrl-n:down,ctrl-p:up' \
		--bind="ctrl-r:reload(AGENT_STATUS_REFRESH=on '$CURRENT_DIR/popup.sh' --list)" \
		"$@")" || return 0

	IFS=$'\t' read -r pane_id window_id session_id _ <<< "$selected"
	focus_pane "$pane_id" "$window_id" "$session_id"
}

case "${1:-}" in
	--list)
		format_rows
		;;
	--select-first)
		first="$(format_rows | head -n 1)"
		[ -n "$first" ] || exit 0
		IFS=$'\t' read -r pane_id window_id session_id _ <<< "$first"
		focus_pane "$pane_id" "$window_id" "$session_id"
		;;
	--preview)
		preview_pane "${2:-}"
		;;
	--help|-h)
		usage
		;;
	"")
		open_popup
		;;
	*)
		usage >&2
		exit 2
		;;
esac
