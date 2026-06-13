# tmux-agent-plugin options

This Rust plugin does not render a sidebar or own a popup. It provides values
for tmux formats, status bars, and your own popup scripts.

Set options before loading `tmux-agent-plugin.tmux` / the TPM plugin.

## Collection

| Option | Default | Description |
| --- | --- | --- |
| `@agent-status-scope` | `all` | One of `all`, `current-session`, or `current-window`. |
| `@agent-status-include-non-agents` | `off` | Include panes without detected/reported agent identity. |
| `@agent-status-process-detection` | `on` | Enable best-effort process/argv inspection with `ps`. |
| `@agent-status-output-detection` | `on` | Enable `tmux capture-pane` screen-state detection. |
| `@agent-status-capture-lines` | `80` | Lines captured from each candidate pane. |
| `@agent-status-cache-ttl` | `2` | Seconds a status command may reuse cached JSON before recollecting. |
| `@agent-status-report-ttl` | `30` | Default explicit report TTL in seconds. |
| `@agent-status-notify-active` | `off` | If `on`, notification events can include the active pane. |
| `@agent-status-binary` | empty | Optional path to a prebuilt `tmux-agent-plugin` Rust binary. |

## Format helper options

When loaded, the plugin sets these tmux options for convenience:

| Option | Expands to |
| --- | --- |
| `@agent-status-summary` | `#(.../scripts/agents.sh summary)` |
| `@agent-status-compact` | `#(.../scripts/agents.sh compact)` |
| `@agent-status-spinner` | `#(.../scripts/agents.sh spinner)` |
| `@agent-status-count` | `#(.../scripts/agents.sh count all)` |
| `@agent-status-working-count` | `#(.../scripts/agents.sh count working)` |
| `@agent-status-blocked-count` | `#(.../scripts/agents.sh count blocked)` |
| `@agent-status-done-count` | `#(.../scripts/agents.sh count done)` |
| `@agent-status-json` | `#(.../scripts/agents.sh json)` |

Use them with `#{E:...}`:

```tmux
set -ag status-right ' #{E:@agent-status-compact}'
```

## Raw script API

```sh
scripts/agents.sh json              # full payload
scripts/agents.sh tsv               # tab-separated rows
scripts/agents.sh summary           # human-readable status text
scripts/agents.sh compact           # compact status text
scripts/agents.sh spinner           # spinner only when working > 0
scripts/agents.sh count all
scripts/agents.sh count working
scripts/agents.sh count blocked
scripts/agents.sh count done
scripts/agents.sh refresh           # refresh cache, print nothing
```

The wrappers call the Rust binary. If `target/release/tmux-agent-plugin` is
missing and `cargo` exists, `scripts/bin.sh` builds it once. To avoid first-use
latency, run:

```sh
cargo build --release
```

## Notification events

```sh
scripts/notify.sh json              # return transition events as JSON
scripts/notify.sh tmux              # show tmux display-message events
scripts/notify.sh system            # macOS/Linux desktop notification if available
scripts/notify.sh both              # tmux + system
```

Event rules:

- new `blocked` status => `needs_attention`
- `working`/`blocked` transitioning to `done`/`idle` => `finished`

## Explicit reports

```sh
scripts/report.sh --pane "$TMUX_PANE" --agent pi --state working --label "running tests" --ttl 30
scripts/report.sh --pane "$TMUX_PANE" --clear
```

Valid states are `blocked`, `working`, `done`, `idle`, and `unknown`.
Use `--ttl -1` for reports that do not expire.
