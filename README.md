# tmux-agent-plugin

A Rust, values-only tmux provider for AI/agent panes.

It primarily returns structured values for status bars and custom renderers,
and includes optional tmux helpers for navigation:

- full list of detected/open agent panes
- agent status: `blocked`, `working`, `done`, `idle`, `unknown`
- session/window/pane metadata
- counts for status bars
- spinner indicator when agents are working
- notification transition events
- optional `fzf` popup with search, jump, and ANSI-preserving pane preview

## Install

### TPM

```tmux
set -g @plugin 'sandiiarov/tmux-agent-plugin'
```

The wrapper auto-builds the Rust binary on first use if `cargo` is available.
For faster first status-line render, prebuild it:

```sh
cd ~/.tmux/plugins/tmux-agent-plugin
cargo build --release
```

### Manual

```tmux
run-shell '/path/to/tmux-agent-plugin/tmux-agent-plugin.tmux'
```

## Clean Docker integration test

The repository includes a clean Docker smoke test that installs tmux, TPM, fzf,
Rust tooling, and fake `pi`, `claude`, `codex`, `gemini`, and `opencode` agent
commands. The fake agents exercise process/status detection without requiring
authenticated real agent accounts.

```sh
./tests/docker_smoke.sh
```

The test verifies TPM loading, JSON values, popup formatting, popup-view
rendering, popup controls, and pane jumping.

## Status bar examples

The plugin exposes helper tmux options when loaded. Use `#{E:...}` to evaluate
the `#(...)` command stored in the option.

### Compact status

Set a 1-second status refresh if you want the working spinner to animate:

```tmux
set -g status-interval 1
set -ag status-right ' #{E:@agent-status-compact}'
```

Example:

```text
󰚩4 ⠋2 ⚠1 ✓1
```

### Human-readable status

```tmux
set -ag status-right ' #{E:@agent-status-summary}'
```

Example:

```text
agents 4 · ⠋ 2 working · ⚠ 1 blocked · ✓ 1 done
```

### Style it yourself

```tmux
set -ag status-right ' #[fg=#89b4fa]󰚩#{E:@agent-status-count}'
set -ag status-right ' #[fg=#f9e2af]#{E:@agent-status-spinner}#{E:@agent-status-working-count}'
set -ag status-right ' #[fg=#f38ba8]⚠#{E:@agent-status-blocked-count}'
set -ag status-right ' #[fg=#a6e3a1]✓#{E:@agent-status-done-count}'
```

## Command API

```sh
scripts/agents.sh json              # full payload
scripts/agents.sh tsv               # tab-separated rows
scripts/agents.sh count all
scripts/agents.sh count working
scripts/agents.sh count blocked
scripts/agents.sh count done
scripts/agents.sh spinner
scripts/agents.sh summary
scripts/agents.sh compact
scripts/agents.sh refresh           # refresh cache, print nothing
```

`json`, `tsv`, and `refresh` accept `--refresh` to bypass the status cache.

## JSON shape

```sh
scripts/agents.sh json | jq .
```

Returns:

```json
{
  "generated_at": 1781320000.0,
  "scope": "all",
  "counts": {
    "all": 3,
    "opened": 3,
    "active": 1,
    "attention": 1,
    "blocked": 1,
    "working": 0,
    "done": 0,
    "idle": 2,
    "unknown": 0
  },
  "agents": [
    {
      "agent": "pi",
      "status": "blocked",
      "state": "blocked",
      "target": "project:2.1",
      "name": "project",
      "state_reason": "blocked-pattern:...",
      "session": { "id": "$1", "name": "project" },
      "window": { "id": "@3", "index": "2", "name": "shell", "active": true },
      "pane": {
        "id": "%7",
        "index": "1",
        "active": false,
        "title": "π - project",
        "current_command": "pi",
        "current_path": "/path/to/project",
        "pid": "12345",
        "width": 120,
        "height": 40
      },
      "process": {
        "foreground_command": "pi",
        "foreground_pid": 12345,
        "foreground_pgid": 12345
      }
    }
  ]
}
```

## Popup navigator

The plugin includes an optional `fzf` tmux popup. It is not bound by default.
Enable it with:

```tmux
set -g @agent-status-popup-key 'a'
```

Then press `prefix + a` to open a searchable popup. The popup shows agent
status icon, agent icon/label, pane title, and a right-side pane preview. The
left list is 20% of the popup and the preview is 80%. The preview uses `tmux
capture-pane -e -J`, so existing ANSI colors from the pane are preserved and
tmux's physical wrap points are joined back into logical lines. fzf preview
wrapping is disabled to avoid wrap/return markers, and the preview follows the
bottom/latest output.

Controls inside the popup:

- `C-n` / `C-p`: move selection down/up
- enter: jump to the selected real tmux pane and close the popup
- escape: close the popup
- `C-r`: refresh the agent list

The control keys are read by `fzf` inside the popup only; they are not bound
globally in tmux.

Popup options:

```tmux
set -g @agent-status-popup-key 'a'       # off by default
set -g @agent-status-nerd-icons 'on'     # legacy/auto icon toggle
set -g @agent-status-popup-show-status-icon 'on'
set -g @agent-status-popup-show-agent-icon 'auto'  # auto follows @agent-status-nerd-icons
set -g @agent-status-popup-show-agent-label 'off'
set -g @agent-status-agent-icon-pi ''
set -g @agent-status-agent-icon-claude ''
# Also supported: codex, gemini, opencode, cursor-agent, copilot, amp, droid,
# grok, kimi, kiro, kilo, qodercli, hermes.
set -g @agent-status-popup-width '94%'
set -g @agent-status-popup-height '78%'
set -g @agent-status-popup-preview-lines '200'
set -g @agent-status-popup-title ' agents'
set -g @agent-status-popup-style 'bg=terminal'
set -g @agent-status-popup-border-style 'fg=#45475a,bg=terminal'
# Optional fzf colors/options. This example uses your terminal palette/default bg.
set -g @agent-status-popup-fzf-opts '--color=fg:-1,bg:-1,fg+:15,bg+:8,gutter:-1,hl:5,hl+:13,info:6,prompt:5,pointer:13,marker:10,spinner:13,header:8,border:8'
```

If you use Catppuccin tmux variables, you can theme the popup with tmux formats:

```tmux
set -g @agent-status-popup-style 'fg=#{@thm_fg},bg=#{@thm_bg}'
set -g @agent-status-popup-border-style 'fg=#{@thm_surface1},bg=#{@thm_bg}'
set -g @agent-status-popup-fzf-opts '--color=fg:#{@thm_fg},bg:#{@thm_bg},fg+:#{@thm_fg},bg+:#{@thm_surface0},hl:#{@thm_mauve},hl+:#{@thm_mauve},info:#{@thm_sky},prompt:#{@thm_mauve},pointer:#{@thm_rosewater},marker:#{@thm_green},spinner:#{@thm_rosewater},header:#{@thm_overlay1},border:#{@thm_surface1},gutter:#{@thm_bg}'
```

You can also call the navigator directly:

```sh
scripts/popup.sh
scripts/popup.sh --list          # print formatted rows
scripts/popup.sh --select-first  # jump to first row, useful for tests
```

## Notification events

The notification provider returns transition events or can deliver them:

```sh
scripts/notify.sh json
scripts/notify.sh tmux
scripts/notify.sh system
scripts/notify.sh both
```

Rules:

- a pane becoming `blocked` emits `needs_attention`
- `working`/`blocked` becoming `done`/`idle` emits `finished`
- active pane notifications are suppressed unless `@agent-status-notify-active` is `on`

Example polling hook:

```tmux
set-hook -g client-session-changed 'run-shell -b "~/.tmux/plugins/tmux-agent-plugin/scripts/notify.sh tmux"'
```

Or call `notify.sh json` from your own watcher.

## Explicit reports / integrations

Agents or wrapper scripts can report semantic status directly:

```sh
scripts/report.sh \
  --pane "$TMUX_PANE" \
  --agent pi \
  --state working \
  --label "running tests" \
  --ttl 30
```

Use `--ttl -1` for no expiry, or `--clear` to remove a report. Explicit reports
take precedence over process/screen detection.

## Options

See [`docs/options.md`](docs/options.md).

Common options:

```tmux
set -g @agent-status-scope 'all'          # all, current-session, current-window
set -g @agent-status-cache-ttl '2'
set -g @agent-status-capture-lines '80'
# Optional: point wrappers at a prebuilt binary
set -g @agent-status-binary '/path/to/tmux-agent-plugin'
```

## How detection works

The Rust provider uses:

1. `tmux list-panes -a` for session/window/pane metadata.
2. `ps` child-process inspection from `#{pane_pid}` to identify agent CLIs.
3. `tmux capture-pane -p -J` recent screen text for state heuristics.
4. Optional explicit reports from `scripts/report.sh`.
5. State/cache files under `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-plugin`.

This repo does not copy Herdr source or manifests. Herdr is AGPL/commercial;
this project stays MIT and reimplements behavior-level ideas cleanly in Rust.

## License and attribution

MIT. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
