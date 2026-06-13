#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$CURRENT_DIR/.." && pwd)"
BINARY_NAME="tmux-agent-plugin"
RELEASE_BIN="$ROOT_DIR/target/release/$BINARY_NAME"
DEBUG_BIN="$ROOT_DIR/target/debug/$BINARY_NAME"

configured_bin=""
if command -v tmux >/dev/null 2>&1; then
	configured_bin="$(tmux show-option -gqv @agent-status-binary 2>/dev/null || true)"
fi

if [ -n "$configured_bin" ]; then
	if [ -x "$configured_bin" ]; then
		printf '%s\n' "$configured_bin"
		exit 0
	fi
	printf 'tmux-agent-plugin: @agent-status-binary is not executable: %s\n' "$configured_bin" >&2
	exit 1
fi

if [ -x "$RELEASE_BIN" ]; then
	printf '%s\n' "$RELEASE_BIN"
	exit 0
fi

if [ -x "$DEBUG_BIN" ]; then
	printf '%s\n' "$DEBUG_BIN"
	exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
	printf 'tmux-agent-plugin: Rust binary missing and cargo was not found. Run: cargo build --release\n' >&2
	exit 1
fi

lock_dir="${TMPDIR:-/tmp}/tmux-agent-plugin-build.lock"
while ! mkdir "$lock_dir" 2>/dev/null; do
	if [ -x "$RELEASE_BIN" ]; then
		printf '%s\n' "$RELEASE_BIN"
		exit 0
	fi
	sleep 0.1
done
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

if [ ! -x "$RELEASE_BIN" ]; then
	(cd "$ROOT_DIR" && cargo build --release --quiet >&2)
fi

printf '%s\n' "$RELEASE_BIN"
