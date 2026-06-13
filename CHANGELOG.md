# Changelog

## Unreleased

- Rewrote the provider as a Rust CLI (`src/main.rs`).
- Pivoted to a values-only tmux provider: no sidebar or popup renderer.
- Added `scripts/bin.sh` to resolve/build the Rust binary on first use.
- Added `scripts/agents.sh` for JSON, TSV, counts, compact summaries, and spinner output.
- Added tmux format helper options such as `@agent-status-compact` and `@agent-status-json`.
- Added `scripts/notify.sh` for transition events as JSON, tmux messages, or system notifications.
- Added optional `scripts/popup.sh` fzf popup navigator with tmux options for key/size/style.
- Kept `scripts/report.sh` for explicit status integrations, now backed by Rust.
- Replaced the historical `agent-sidebar.tmux` entrypoint with `tmux-agent-plugin.tmux`.
- Removed sidebar/action/render Python scripts and Python unit tests.

## Release checklist

- Run `cargo fmt --check`.
- Run `cargo test`.
- Run `cargo build --release`.
- Run `bash -n tmux-agent-plugin.tmux scripts/*.sh tests/*.sh`.
- Run `./tests/smoke_tmux_values.sh`.
- Verify manual `run-shell` install instructions.
- Verify TPM install instructions after publishing.
