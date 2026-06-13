# Demo / screenshots

Run the smoke test to create a disposable tmux server, fake an agent pane, open
the sidebar, and print a captured sidebar frame:

```sh
./tests/smoke_tmux.sh
```

For a manual demo in your own tmux session:

1. Install/load the plugin.
2. Open a pane running an agent CLI such as `pi`, `claude`, `codex`, `gemini`, or
   `opencode`.
3. Press `prefix + Tab` to open the sidebar.
4. Press `prefix + B` to jump to blocked panes or `prefix + D` for done panes.

Screenshot checklist for releases:

- Sidebar open on the left and right.
- At least one blocked pane and one done pane.
- Narrow terminal truncation.
- `@agent-sidebar-style off` colorless rendering.
