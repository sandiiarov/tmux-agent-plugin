#!/usr/bin/env python3
"""Report/override pane status for tmux-agent-plugin."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import collect

VALID_STATES = {"blocked", "working", "done", "idle", "unknown"}


def current_pane() -> str:
    pane = os.environ.get("TMUX_PANE") or collect.run_tmux(["display-message", "-p", "#{pane_id}"]).strip()
    return pane


def report_path(pane_id: str) -> Path:
    return collect.reports_dir() / f"{collect.sanitize_pane_id(pane_id)}.json"


def write_report(pane_id: str, report: dict[str, Any]) -> None:
    path = report_path(pane_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".json.{os.getpid()}.tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
    tmp.replace(path)


def clear_report(pane_id: str) -> bool:
    try:
        report_path(pane_id).unlink()
        return True
    except FileNotFoundError:
        return False


def display(message: str) -> None:
    collect.run_tmux(["display-message", message])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pane", help="tmux pane id, default: current pane")
    parser.add_argument("--agent", help="agent label/name override")
    parser.add_argument("--state", choices=sorted(VALID_STATES), help="reported state")
    parser.add_argument("--label", help="short status text shown in the sidebar")
    parser.add_argument("--ttl", type=int, default=None, help="seconds before report expires; -1 disables expiry")
    parser.add_argument("--clear", action="store_true", help="clear the explicit report for the pane")
    parser.add_argument("--quiet", action="store_true", help="do not display a tmux message")
    args = parser.parse_args(argv)

    pane_id = args.pane or current_pane()
    if not pane_id:
        print("tmux-agent-plugin: unable to determine pane id", file=sys.stderr)
        return 2

    if args.clear:
        removed = clear_report(pane_id)
        if not args.quiet:
            display(f"tmux-agent-plugin: {'cleared' if removed else 'no'} report for {pane_id}")
        return 0

    if not (args.agent or args.state or args.label):
        parser.error("at least one of --agent, --state, --label, or --clear is required")

    report: dict[str, Any] = {
        "pane": pane_id,
        "updated_at": time.time(),
    }
    if args.agent:
        report["agent"] = args.agent
    if args.state:
        report["state"] = args.state
    if args.label:
        report["label"] = args.label
    if args.ttl is not None:
        report["ttl"] = args.ttl

    write_report(pane_id, report)
    if not args.quiet:
        pieces = [pane_id]
        if args.agent:
            pieces.append(args.agent)
        if args.state:
            pieces.append(args.state)
        if args.label:
            pieces.append(args.label)
        display("tmux-agent-plugin: reported " + " · ".join(pieces))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
