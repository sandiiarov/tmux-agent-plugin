#!/usr/bin/env python3
"""Render the tmux-agent-plugin sidebar."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

import collect

ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ON_VALUES = {"1", "on", "true", "yes", "y"}

STATE_STYLE = {
    "blocked": ("⚠", "31;1"),
    "working": ("●", "34;1"),
    "done": ("✓", "32;1"),
    "idle": ("○", "37"),
    "unknown": ("?", "90"),
}

STATE_TEXT = {
    "blocked": "needs input",
    "working": "working",
    "done": "done",
    "idle": "idle",
    "unknown": "unknown",
}


def tmux_option(option: str, default: str = "") -> str:
    return collect.tmux_option(option, default)


def option_bool(option: str, default: str = "off") -> bool:
    return tmux_option(option, default).strip().lower() in ON_VALUES


def pane_size(sidebar_pane: str | None) -> tuple[int, int]:
    target = sidebar_pane or os.environ.get("TMUX_PANE") or ""
    args = ["display-message", "-p"]
    if target:
        args.extend(["-t", target])
    args.append("#{pane_width} #{pane_height}")
    output = collect.run_tmux(args).strip().split()
    try:
        return max(20, int(output[0])), max(5, int(output[1]))
    except (IndexError, ValueError):
        return 40, 24


def visible_len(text: str) -> int:
    return len(ANSI_RE.sub("", text))


def truncate(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if visible_len(text) <= width:
        return text
    plain = ANSI_RE.sub("", text)
    if width == 1:
        return "…"
    return plain[: max(0, width - 1)] + "…"


def color(text: str, code: str, enabled: bool) -> str:
    if not enabled:
        return text
    return f"\033[{code}m{text}\033[0m"


def project_label(pane: dict[str, Any], show_project: bool) -> str:
    title = str(pane.get("pane_title") or "").strip()
    path = str(pane.get("pane_current_path") or "").strip()
    if show_project and path:
        home = str(Path.home())
        if path == home:
            return "~"
        return Path(path).name or path
    return title or (Path(path).name if path else "-")


def target_label(pane: dict[str, Any], scope: str) -> str:
    window_index = pane.get("window_index") or "?"
    pane_index = pane.get("pane_index") or "?"
    if scope == "all":
        session = pane.get("session_name") or "?"
        return f"{session}:{window_index}.{pane_index}"
    return f"{window_index}.{pane_index}"


def reason_label(pane: dict[str, Any]) -> str:
    report = pane.get("explicit_report") or {}
    if isinstance(report, dict) and report.get("label"):
        return str(report["label"])
    state = str(pane.get("state") or "unknown")
    return STATE_TEXT.get(state, state)


def sort_key(pane: dict[str, Any]) -> tuple[str, int, int]:
    try:
        window_index = int(pane.get("window_index") or 0)
    except ValueError:
        window_index = 0
    try:
        pane_index = int(pane.get("pane_index") or 0)
    except ValueError:
        pane_index = 0
    return (str(pane.get("session_name") or ""), window_index, pane_index)


def header_line(data: dict[str, Any], width: int, styled: bool) -> str:
    scope = data.get("scope") or "current-session"
    title = f" agents · {scope} "
    if len(title) < width:
        pad = "─" * max(0, width - len(title))
        title = title + pad
    return color(truncate(title, width), "1;36", styled)


def render_pane_line(pane: dict[str, Any], width: int, scope: str, styled: bool) -> str:
    state = str(pane.get("state") or "unknown")
    icon, code = STATE_STYLE.get(state, STATE_STYLE["unknown"])
    agent = str(pane.get("agent_label") or "pane")
    target = target_label(pane, scope)
    project = project_label(pane, option_bool("@agent-sidebar-show-project", "on"))
    status = reason_label(pane)

    # Narrow-friendly layout. Keep state/agent/target first; truncate tail.
    plain = f"{icon} {agent:<12.12} {target:<7.7} {project} · {status}"
    return color(truncate(plain, width), code, styled)


def group_header(pane: dict[str, Any], width: int, styled: bool) -> str:
    text = f" {pane.get('session_name')}:{pane.get('window_index')} {pane.get('window_name')} "
    if len(text) < width:
        text = text + "─" * (width - len(text))
    return color(truncate(text, width), "36", styled)


def footer(width: int, styled: bool) -> list[str]:
    lines = [
        "",
        "Tab close · B blocked · D done",
        "R refresh · A ack · Enter owner",
    ]
    return [color(truncate(line, width), "2", styled) for line in lines]


def render(owner: str | None, sidebar_pane: str | None) -> str:
    width, height = pane_size(sidebar_pane)
    styled = option_bool("@agent-sidebar-style", "on")
    data = collect.collect(owner=owner, write_cache=True)
    scope = str(data.get("scope") or "current-session")
    panes = sorted(data.get("panes", []), key=sort_key)

    lines: list[str] = [header_line(data, width, styled)]
    if not panes:
        lines.extend(
            [
                color(truncate("No agent panes detected", width), "33", styled),
                truncate("Start pi/claude/codex/gemini/opencode in a pane.", width),
            ]
        )
    else:
        last_group: tuple[str, str] | None = None
        for pane in panes:
            group = (str(pane.get("session_name") or ""), str(pane.get("window_index") or ""))
            if group != last_group:
                lines.append(group_header(pane, width, styled))
                last_group = group
            lines.append(render_pane_line(pane, width, scope, styled))

    footer_lines = footer(width, styled)
    max_body = max(1, height - len(footer_lines))
    if len(lines) > max_body:
        lines = lines[: max(1, max_body - 1)] + [color(truncate("… more panes", width), "2", styled)]
    lines.extend(footer_lines)
    return "\n".join(truncate(line, width + 20) for line in lines[:height])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", help="Owner/main pane id")
    parser.add_argument("--pane", help="Sidebar pane id for size detection")
    args = parser.parse_args(argv)
    try:
        sys.stdout.write(render(args.owner, args.pane))
        sys.stdout.write("\n")
        return 0
    except Exception as exc:  # Keep the sidebar pane alive and useful on errors.
        width, _ = pane_size(args.pane)
        sys.stdout.write(truncate(f"tmux-agent-plugin render error: {exc}", width) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
