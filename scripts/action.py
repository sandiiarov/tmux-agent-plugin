#!/usr/bin/env python3
"""Navigation and acknowledgement actions for tmux-agent-plugin."""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Any

import collect
import detect

REGISTERED_SIDEBAR_PREFIX = "@agent-sidebar-is-sidebar"


def display(message: str) -> None:
    collect.run_tmux(["display-message", message])


def tmux_option(option: str, default: str = "") -> str:
    return collect.tmux_option(option, default)


def pane_exists(pane_id: str) -> bool:
    panes = collect.run_tmux(["list-panes", "-a", "-F", "#{pane_id}"])
    return pane_id in panes.splitlines()


def select_pane(pane: dict[str, Any]) -> None:
    session_name = pane.get("session_name")
    window_index = pane.get("window_index")
    pane_id = pane.get("pane_id")
    if session_name and window_index:
        collect.run_tmux(["switch-client", "-t", f"{session_name}:{window_index}"])
    if pane_id:
        collect.run_tmux(["select-pane", "-t", str(pane_id)])


def report_path(pane_id: str) -> Path:
    return collect.reports_dir() / f"{collect.sanitize_pane_id(pane_id)}.json"


def acknowledge_pane(pane_id: str) -> None:
    state = detect.load_pane_state()
    record = state.get(pane_id, {}) if isinstance(state, dict) else {}
    if not isinstance(record, dict):
        record = {}
    record.update(
        {
            "state": "idle",
            "raw_state": "idle",
            "reason": "acknowledged",
            "acknowledged_at": time.time(),
            "updated_at": time.time(),
        }
    )
    state[pane_id] = record
    detect.save_pane_state(state)
    try:
        report_path(pane_id).unlink()
    except FileNotFoundError:
        pass
    except OSError:
        pass


def current_or_owner(pane_id: str | None) -> str | None:
    if not pane_id:
        pane_id = collect.run_tmux(["display-message", "-p", "#{pane_id}"]).strip()
    if not pane_id:
        return None
    owner = tmux_option(f"{REGISTERED_SIDEBAR_PREFIX}-{pane_id}", "")
    return owner or pane_id


def sorted_panes(data: dict[str, Any]) -> list[dict[str, Any]]:
    def pane_key(pane: dict[str, Any]) -> tuple[str, int, int]:
        try:
            window_index = int(pane.get("window_index") or 0)
        except ValueError:
            window_index = 0
        try:
            pane_index = int(pane.get("pane_index") or 0)
        except ValueError:
            pane_index = 0
        return (str(pane.get("session_name") or ""), window_index, pane_index)

    return sorted(data.get("panes", []), key=pane_key)


def choose_next(panes: list[dict[str, Any]], current_pane_id: str | None) -> dict[str, Any] | None:
    if not panes:
        return None
    if not current_pane_id:
        return panes[0]
    for index, pane in enumerate(panes):
        if pane.get("pane_id") == current_pane_id:
            return panes[(index + 1) % len(panes)]
    return panes[0]


def action_refresh(owner: str | None) -> int:
    data = collect.collect(owner=owner, write_cache=True)
    count = len(data.get("panes", []))
    display(f"tmux-agent-plugin: refreshed {count} pane(s)")
    return 0


def action_jump_owner(pane_id: str | None) -> int:
    if not pane_id:
        pane_id = collect.run_tmux(["display-message", "-p", "#{pane_id}"]).strip()
    owner = tmux_option(f"{REGISTERED_SIDEBAR_PREFIX}-{pane_id}", "") if pane_id else ""
    if owner and pane_exists(owner):
        collect.run_tmux(["select-pane", "-t", owner])
        return 0
    display("tmux-agent-plugin: current pane is not a registered sidebar")
    return 1


def action_jump_next(state: str, pane_id: str | None) -> int:
    owner = current_or_owner(pane_id)
    data = collect.collect(owner=owner, write_cache=True)
    candidates = [pane for pane in sorted_panes(data) if pane.get("state") == state]
    target = choose_next(candidates, owner)
    if not target:
        display(f"tmux-agent-plugin: no {state} panes")
        return 1
    select_pane(target)
    if state == "done" and target.get("pane_id"):
        acknowledge_pane(str(target["pane_id"]))
    label = target.get("agent_label") or "pane"
    display(f"tmux-agent-plugin: jumped to {state} {label} {target.get('pane_id')}")
    return 0


def action_ack_all(owner: str | None) -> int:
    data = collect.collect(owner=owner, write_cache=True)
    done = [pane for pane in data.get("panes", []) if pane.get("state") == "done"]
    for pane in done:
        pane_id = pane.get("pane_id")
        if pane_id:
            acknowledge_pane(str(pane_id))
    display(f"tmux-agent-plugin: acknowledged {len(done)} done pane(s)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    refresh = subparsers.add_parser("refresh")
    refresh.add_argument("pane_id", nargs="?")

    jump_owner = subparsers.add_parser("jump-owner")
    jump_owner.add_argument("pane_id", nargs="?")

    jump_next = subparsers.add_parser("jump-next")
    jump_next.add_argument("state", choices=("blocked", "done", "idle", "working", "unknown"))
    jump_next.add_argument("pane_id", nargs="?")

    ack_all = subparsers.add_parser("ack-all")
    ack_all.add_argument("pane_id", nargs="?")

    ack = subparsers.add_parser("ack")
    ack.add_argument("pane_id")

    args = parser.parse_args(argv)
    if args.action == "refresh":
        return action_refresh(current_or_owner(args.pane_id))
    if args.action == "jump-owner":
        return action_jump_owner(args.pane_id)
    if args.action == "jump-next":
        return action_jump_next(args.state, args.pane_id)
    if args.action == "ack-all":
        return action_ack_all(current_or_owner(args.pane_id))
    if args.action == "ack":
        acknowledge_pane(args.pane_id)
        display(f"tmux-agent-plugin: acknowledged {args.pane_id}")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
