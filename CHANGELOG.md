# Changelog

## Unreleased

- Initial tmux plugin scaffold and TPM/manual entrypoint.
- Toggleable left/right agent sidebar with focus-preserving lifecycle.
- Pane inventory, foreground process inspection, and agent label detection.
- Clean-room capture-based state detection for blocked/working/done/idle/unknown.
- Live sidebar renderer with icons/colors and prefix-key navigation actions.
- Optional report CLI for explicit status/label integration.

## Release checklist

- Run `python3 -m unittest discover tests`.
- Run `./tests/smoke_tmux.sh` on macOS and Linux where possible.
- Run ShellCheck if installed: `shellcheck agent-sidebar.tmux scripts/*.sh tests/*.sh`.
- Verify manual `run-shell` install instructions.
- Verify TPM install instructions after publishing the repository.
- Update screenshots/demo docs if rendering changed.
