# tmux-agent-plugin

A Rust, values-only tmux provider for AI/agent panes.

It does **not** render a sidebar. It returns structured values for status bars
and includes an optional `fzf` popup navigator:

- full list of detected/open agent panes
- agent status: `blocked`, `working`, `done`, `idle`, `unknown`
- session/window/pane metadata
- counts for status bars
- spinner indicator when agents are working
- notification transition events

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

## Status bar examples

The plugin exposes helper tmux options when loaded. Use `#{E:...}` to evaluate
the `#(...)` command stored in the option.

### Compact status

```tmux
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

The plugin includes an optional `fzf` popup helper. It is not bound by default.
Enable it with:

```tmux
set -g @agent-status-popup-key 'a'
```

Then press `prefix + a` to open a searchable popup. The popup shows agent
status, agent name, tmux target, display name, cwd, and a live pane preview.
Press enter to jump to the selected pane. Press `ctrl-r` inside fzf to refresh.

Popup options:

```tmux
set -g @agent-status-popup-key 'a'       # off by default
set -g @agent-status-popup-width '94%'
set -g @agent-status-popup-height '78%'
set -g @agent-status-popup-title ' agents'
set -g @agent-status-popup-style 'bg=terminal'
set -g @agent-status-popup-border-style 'fg=#45475a,bg=terminal'
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
