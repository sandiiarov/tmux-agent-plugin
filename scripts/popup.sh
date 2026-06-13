#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
	# ANSI colors and UTF-8 glyphs confuse byte-based printf padding, so compute display cells.
	"$CURRENT_DIR/agents.sh" tsv --refresh | perl -CSDA -Mutf8 -F'\t' -lane '
		BEGIN {
			$esc = "\e";
			$reset = "$esc\[0m";
			$red = "$esc\[31m";
			$yellow = "$esc\[33m";
			$green = "$esc\[32m";
			$blue = "$esc\[34m";
			$dim = "$esc\[2m";
		}

		sub is_combining {
			my ($codepoint) = @_;
			return ($codepoint >= 0x0300 && $codepoint <= 0x036f)
				|| ($codepoint >= 0x1ab0 && $codepoint <= 0x1aff)
				|| ($codepoint >= 0x1dc0 && $codepoint <= 0x1dff)
				|| ($codepoint >= 0x20d0 && $codepoint <= 0x20ff)
				|| ($codepoint >= 0xfe20 && $codepoint <= 0xfe2f);
		}

		sub is_wide {
			my ($codepoint) = @_;
			return ($codepoint >= 0x1100 && $codepoint <= 0x115f)
				|| ($codepoint >= 0x2e80 && $codepoint <= 0xa4cf)
				|| ($codepoint >= 0xac00 && $codepoint <= 0xd7a3)
				|| ($codepoint >= 0xf900 && $codepoint <= 0xfaff)
				|| ($codepoint >= 0xfe10 && $codepoint <= 0xfe19)
				|| ($codepoint >= 0xfe30 && $codepoint <= 0xfe6f)
				|| ($codepoint >= 0xff00 && $codepoint <= 0xff60)
				|| ($codepoint >= 0xffe0 && $codepoint <= 0xffe6);
		}

		sub display_width {
			my ($value) = @_;
			$value //= "";
			$value =~ s/\e\[[0-?]*[ -\/]*[@-~]//g;

			my $width = 0;
			for my $char (split //, $value) {
				my $codepoint = ord($char);
				next if $codepoint < 32 || ($codepoint >= 0x7f && $codepoint < 0xa0);
				next if is_combining($codepoint);
				$width += is_wide($codepoint) ? 2 : 1;
			}
			return $width;
		}

		sub pad_right {
			my ($value, $width) = @_;
			$value //= "";
			my $padding = $width - display_width($value);
			return $value . ($padding > 0 ? " " x $padding : "");
		}

		sub color_pad {
			my ($label, $color, $width) = @_;
			my $padding = $width - display_width($label);
			return $color . $label . $reset . ($padding > 0 ? " " x $padding : "");
		}

		next if $. == 1;
		my ($status, $agent, $target, $name, $session, $window, $pane, $cwd, $pane_id, $window_id, $session_id) = @F;
		my ($state_label, $state_color) = ("? unknown", $dim);
		if ($status eq "blocked") {
			($state_label, $state_color) = ("⚠ blocked", $red);
		} elsif ($status eq "working") {
			($state_label, $state_color) = ("⠋ working", $yellow);
		} elsif ($status eq "done") {
			($state_label, $state_color) = ("✓ done", $green);
		} elsif ($status eq "idle") {
			($state_label, $state_color) = ("• idle", $blue);
		}

		my $where = "$session:$window.$pane";
		my $display = color_pad($state_label, $state_color, 10)
			. " " . pad_right($agent, 8)
			. " " . pad_right($where, 22)
			. " " . pad_right($name, 20)
			. " " . ($cwd // "");
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

open_popup() {
	local rows selected pane_id window_id session_id
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

	selected="$(printf '%s\n' "$rows" | fzf \
		--ansi \
		--delimiter='\t' \
		--with-nth=4 \
		--nth=4 \
		--prompt='agents> ' \
		--header='enter: jump · ctrl-r: refresh · esc: close' \
		--preview='tmux capture-pane -t {1} -p -J -S -30 2>/dev/null' \
		--preview-window='down,45%,border-top' \
		--bind="ctrl-r:reload('$CURRENT_DIR/popup.sh' --list)")" || return 0

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
