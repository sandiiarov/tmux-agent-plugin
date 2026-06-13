# tmux-agent-plugin

A tmux plugin that adds a Herdr-like agent sidebar for agent-heavy tmux sessions.
It opens a persistent/toggleable sidebar pane that lists detected agent panes,
their likely status, cwd/title, and quick navigation actions.

## Install

### TPM

```tmux
set -g @plugin 'sandiiarov/tmux-agent-plugin'
run '~/.tmux/plugins/tpm/tpm'
```

### Manual

```tmux
run-shell '/path/to/tmux-agent-plugin/agent-sidebar.tmux'
```

Reload tmux config after installing.

## Quick start

Default prefix bindings:

| Binding | Action |
| --- | --- |
| `prefix + Tab` | Toggle the sidebar, preserving focus by default |
| `prefix + Bspace` | Toggle the sidebar and focus it |
| `prefix + R` | Refresh cached sidebar state |
| `prefix + Enter` | If focused pane is the sidebar, jump back to its owner pane |
| `prefix + B` | Jump to the next blocked pane |
| `prefix + D` | Jump to the next done pane and acknowledge it |
| `prefix + A` | Acknowledge all done panes |

The sidebar currently recognizes common agent CLIs by process name/argv and tmux
fallback command, including `pi`, `claude`, `codex`, `gemini`, `opencode`,
`cursor-agent`, `copilot`/`ghcs`, `amp`, `droid`, `grok`, `kimi`, `kiro`,
`kilo`, `qodercli`, and `hermes`.

## Options

Set options before loading the plugin.

```tmux
set -g @agent-sidebar-position 'left'       # left or right
set -g @agent-sidebar-width '40'            # preferred width in columns
set -g @agent-sidebar-refresh-interval '2'  # seconds
set -g @agent-sidebar-capture-lines '80'    # lines captured from each pane
```

Key options can be set to a tmux key name or `off`:

```tmux
set -g @agent-sidebar-toggle-key 'Tab'
set -g @agent-sidebar-focus-key 'Bspace'
set -g @agent-sidebar-refresh-key 'R'
set -g @agent-sidebar-jump-key 'Enter'
set -g @agent-sidebar-next-blocked-key 'B'
set -g @agent-sidebar-next-done-key 'D'
set -g @agent-sidebar-ack-all-key 'A'
```

Detection/rendering options:

```tmux
set -g @agent-sidebar-scope 'current-session'      # current-session, current-window, all
set -g @agent-sidebar-include-non-agents 'off'     # on/off
set -g @agent-sidebar-process-detection 'on'       # on/off
set -g @agent-sidebar-output-detection 'on'        # on/off
set -g @agent-sidebar-style 'on'                   # ANSI color on/off
set -g @agent-sidebar-notify 'off'                 # tmux display-message transitions
set -g @agent-sidebar-python 'python3'
set -g @agent-sidebar-report-ttl '30'              # seconds for explicit reports
```

See [`docs/options.md`](docs/options.md) for the full option reference.

## Status meanings

- `blocked`: the pane appears to be waiting for approval, confirmation, or input.
- `working`: the pane appears to be generating/running/thinking, or output changed recently.
- `done`: a previously working/blocked agent became idle while not active.
- `idle`: an agent prompt/input area appears ready.
- `unknown`: no supported agent/status evidence was found.

## Manual status override / integration

Agents or wrapper scripts can report a semantic state directly:

```sh
/path/to/tmux-agent-plugin/scripts/report.sh \
  --pane "$TMUX_PANE" \
  --agent pi \
  --state working \
  --label "running tests" \
  --ttl 30
```

Use `--ttl -1` for no expiry, or `--clear` to remove a report. Explicit reports
currently take precedence over screen/process detection.

Example wrapper:

```sh
agent_report=/path/to/tmux-agent-plugin/scripts/report.sh
$agent_report --agent pi --state working --label "starting" --ttl 30
pi "$@"
status=$?
$agent_report --agent pi --state done --label "finished" --ttl 300
exit "$status"
```

## Platform notes and limitations

- Tested locally on macOS with isolated tmux smoke tests.
- Linux is expected to work through portable `ps -eo/-axo` process inspection;
  reliability may vary by distro, shell, and procps implementation.
- tmux exposes the pane shell PID; reliable foreground process detection is OS-
  and shell-dependent. The plugin uses best-effort process-tree inspection plus
  `#{pane_current_command}` fallback.
- Screen-state detection uses `tmux capture-pane` text snapshots, so accuracy is
  lower than tools that inspect terminal internals directly.
- The sidebar is mostly read-only; navigation is tmux keybinding based.

## License and attribution

MIT. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
