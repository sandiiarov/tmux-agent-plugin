# Changelog

## Unreleased

- Rewrote the provider as a Rust CLI (`src/main.rs`).
- Pivoted to a values-first tmux provider with opt-in navigators.
- Added `scripts/bin.sh` to resolve/build the Rust binary on first use.
- Added `scripts/agents.sh` for JSON, TSV, counts, compact summaries, and spinner output.
- Added tmux format helper options such as `@agent-status-compact` and `@agent-status-json`.
- Added `scripts/notify.sh` for transition events as JSON, tmux messages, or system notifications.
- Added optional `scripts/popup.sh` fzf popup navigator with tmux options for key/size/style.
- Improved the fzf popup preview to preserve ANSI colors, join tmux physical wraps into logical lines, avoid fzf wrap markers, follow the bottom/latest output, support `C-n`/`C-p`, `C-o` jump, escape close, extra fzf theme options, and refresh on demand.
- Added a clean Docker integration harness with tmux, TPM, fzf, Rust tooling, and fake agent CLIs.
- Added `@agent-status-nerd-icons` to show Nerd Font agent labels in navigator rows.
- Kept `scripts/report.sh` for explicit status integrations, now backed by Rust.
- Replaced the historical `agent-sidebar.tmux` entrypoint with `tmux-agent-plugin.tmux`.
- Removed sidebar/action/render Python scripts and Python unit tests.

## Release checklist

- Run `cargo fmt --check`.
- Run `cargo test`.
- Run `cargo build --release`.
- Run `bash -n tmux-agent-plugin.tmux scripts/*.sh tests/*.sh`.
- Run `./tests/smoke_tmux_values.sh`.
- Run `./tests/docker_smoke.sh` when Docker is available.
- Verify manual `run-shell` install instructions.
- Verify TPM install instructions after publishing.
