# tmux-agent-plugin options

Set options before loading `agent-sidebar.tmux`.

## Key bindings

Set a key option to a tmux key name or `off`.

| Option | Default | Description |
| --- | --- | --- |
| `@agent-sidebar-toggle-key` | `Tab` | Toggle sidebar and preserve focus. |
| `@agent-sidebar-focus-key` | `Bspace` | Toggle sidebar and focus it when opening. |
| `@agent-sidebar-refresh-key` | `R` | Refresh cached state. |
| `@agent-sidebar-jump-key` | `Enter` | From sidebar, jump to owner pane. |
| `@agent-sidebar-next-blocked-key` | `B` | Jump to next blocked pane. |
| `@agent-sidebar-next-done-key` | `D` | Jump to next done pane and acknowledge it. |
| `@agent-sidebar-ack-all-key` | `A` | Acknowledge all done panes in scope. |

## Layout

| Option | Default | Description |
| --- | --- | --- |
| `@agent-sidebar-position` | `left` | Sidebar placement: `left` or `right`. |
| `@agent-sidebar-width` | `40` | Preferred sidebar width in columns. |
| `@agent-sidebar-minimum-width` | `71` | Minimum owner pane width needed to open. |

Widths are remembered per cwd in
`${XDG_DATA_HOME:-$HOME/.local/share}/tmux-agent-plugin/directory_widths.tsv`.

## Detection and rendering

| Option | Default | Description |
| --- | --- | --- |
| `@agent-sidebar-refresh-interval` | `2` | Sidebar refresh interval in seconds. |
| `@agent-sidebar-capture-lines` | `80` | Lines captured from each candidate pane. |
| `@agent-sidebar-scope` | `current-session` | One of `current-session`, `current-window`, or `all`. |
| `@agent-sidebar-include-non-agents` | `off` | Include panes without detected/report agent identity. |
| `@agent-sidebar-process-detection` | `on` | Enable best-effort process/argv inspection. |
| `@agent-sidebar-output-detection` | `on` | Enable `capture-pane` screen-state detection. |
| `@agent-sidebar-style` | `on` | Enable ANSI color/style in the sidebar. |
| `@agent-sidebar-show-project` | `on` | Show cwd basename instead of title when possible. |
| `@agent-sidebar-notify` | `off` | Show `tmux display-message` notifications for blocked/done transitions. |
| `@agent-sidebar-python` | `python3` | Python 3 executable used by collector/renderer/action scripts. |
| `@agent-sidebar-report-ttl` | `30` | Default explicit report TTL in seconds. |

## Report CLI

```sh
scripts/report.sh --pane %1 --agent pi --state working --label "running tests" --ttl 30
scripts/report.sh --pane %1 --clear
```

Valid states are `blocked`, `working`, `done`, `idle`, and `unknown`.
Use `--ttl -1` for reports that do not expire.
