#!/usr/bin/env python3
"""Collect tmux pane inventory and best-effort agent identity/status."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import detect

REGISTERED_SIDEBAR_PREFIX = "@agent-sidebar-is-sidebar"
REGISTERED_PANE_PREFIX = "@agent-sidebar-registered-pane"

OPTIONS = {
    "scope": ("@agent-sidebar-scope", "current-session"),
    "include_non_agents": ("@agent-sidebar-include-non-agents", "off"),
    "process_detection": ("@agent-sidebar-process-detection", "on"),
    "output_detection": ("@agent-sidebar-output-detection", "on"),
    "capture_lines": ("@agent-sidebar-capture-lines", "80"),
    "notify": ("@agent-sidebar-notify", "off"),
    "report_ttl": ("@agent-sidebar-report-ttl", "30"),
}

TMUX_SEP = "\x1f"
TSV_SEP = "\t"
ON_VALUES = {"1", "on", "true", "yes", "y"}


@dataclass(slots=True)
class ProcessInfo:
    pid: int
    ppid: int
    pgid: int
    stat: str
    args: str
    depth: int = 0

    @property
    def command(self) -> str:
        tokens = detect.command_tokens(self.args)
        return detect.normalize_token(tokens[0]) if tokens else ""


@dataclass(slots=True)
class Pane:
    session_id: str
    session_name: str
    window_id: str
    window_index: str
    window_name: str
    pane_id: str
    pane_index: str
    pane_active: bool
    window_active: bool
    pane_current_command: str
    pane_title: str
    pane_current_path: str
    pane_pid: str
    pane_width: str
    pane_height: str
    foreground_command: str = ""
    foreground_pid: int | None = None
    foreground_pgid: int | None = None
    agent_label: str | None = None
    state: str = "unknown"
    state_reason: str = ""
    raw_state: str = "unknown"
    is_sidebar: bool = False
    explicit_report: dict[str, Any] | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    @property
    def is_active(self) -> bool:
        return self.pane_active and self.window_active

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def run_tmux(args: list[str], *, check: bool = False) -> str:
    try:
        proc = subprocess.run(
            ["tmux", *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )
    except FileNotFoundError:
        return ""
    if proc.returncode != 0 and check:
        raise RuntimeError(proc.stderr.strip())
    return proc.stdout


def tmux_option(option: str, default: str = "") -> str:
    value = run_tmux(["show-option", "-gqv", option]).strip("\n")
    return value if value else default


def option_bool(name: str) -> bool:
    option, default = OPTIONS[name]
    return tmux_option(option, default).strip().lower() in ON_VALUES


def option_int(name: str) -> int:
    option, default = OPTIONS[name]
    value = tmux_option(option, default).strip()
    try:
        return int(value)
    except ValueError:
        return int(default)


def cache_dir() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tmux-agent-plugin"


def state_output_file() -> Path:
    return cache_dir() / "state.json"


def reports_dir() -> Path:
    return cache_dir() / "reports"


def sanitize_pane_id(pane_id: str) -> str:
    return pane_id.replace("%", "pct").replace("/", "_")


def load_report(pane_id: str, ttl: int, now: float) -> dict[str, Any] | None:
    path = reports_dir() / f"{sanitize_pane_id(pane_id)}.json"
    try:
        with path.open("r", encoding="utf-8") as handle:
            report = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    updated_at = float(report.get("updated_at") or 0)
    report_ttl = int(report.get("ttl") or ttl)
    if report_ttl >= 0 and now - updated_at > report_ttl:
        return None
    return report if isinstance(report, dict) else None


def sidebar_pane_ids() -> set[str]:
    ids: set[str] = set()
    output = run_tmux(["show-options", "-gq"])
    prefix = f"{REGISTERED_SIDEBAR_PREFIX}-"
    for line in output.splitlines():
        if not line.startswith(prefix):
            continue
        name = line.split(None, 1)[0]
        pane_id = name[len(prefix) :]
        if pane_id:
            ids.add(pane_id)
    return ids


def owner_scope(owner: str | None) -> tuple[str, str]:
    if owner:
        session_id = run_tmux(["display-message", "-p", "-t", owner, "#{session_id}"]).strip()
        window_id = run_tmux(["display-message", "-p", "-t", owner, "#{window_id}"]).strip()
        if session_id or window_id:
            return session_id, window_id
    session_id = run_tmux(["display-message", "-p", "#{session_id}"]).strip()
    window_id = run_tmux(["display-message", "-p", "#{window_id}"]).strip()
    return session_id, window_id


def parse_bool_flag(value: str) -> bool:
    return str(value).strip() == "1"


def list_panes() -> list[Pane]:
    fields = [
        "#{session_id}",
        "#{session_name}",
        "#{window_id}",
        "#{window_index}",
        "#{window_name}",
        "#{pane_id}",
        "#{pane_index}",
        "#{pane_active}",
        "#{window_active}",
        "#{pane_current_command}",
        "#{pane_title}",
        "#{pane_current_path}",
        "#{pane_pid}",
        "#{pane_width}",
        "#{pane_height}",
    ]
    output = run_tmux(["list-panes", "-a", "-F", TMUX_SEP.join(fields)])
    panes: list[Pane] = []
    for line in output.splitlines():
        parts = line.split(TMUX_SEP)
        if len(parts) != len(fields):
            continue
        panes.append(
            Pane(
                session_id=parts[0],
                session_name=parts[1],
                window_id=parts[2],
                window_index=parts[3],
                window_name=parts[4],
                pane_id=parts[5],
                pane_index=parts[6],
                pane_active=parse_bool_flag(parts[7]),
                window_active=parse_bool_flag(parts[8]),
                pane_current_command=parts[9],
                pane_title=parts[10],
                pane_current_path=parts[11],
                pane_pid=parts[12],
                pane_width=parts[13],
                pane_height=parts[14],
            )
        )
    return panes


def parse_processes() -> dict[int, ProcessInfo]:
    commands = [
        ["ps", "-axo", "pid=,ppid=,pgid=,stat=,args="],
        ["ps", "-eo", "pid=,ppid=,pgid=,stat=,args="],
    ]
    output = ""
    for command in commands:
        proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode == 0 and proc.stdout.strip():
            output = proc.stdout
            break
    processes: dict[int, ProcessInfo] = {}
    for line in output.splitlines():
        parts = line.strip().split(None, 4)
        if len(parts) < 5:
            continue
        try:
            pid, ppid, pgid = int(parts[0]), int(parts[1]), int(parts[2])
        except ValueError:
            continue
        processes[pid] = ProcessInfo(pid=pid, ppid=ppid, pgid=pgid, stat=parts[3], args=parts[4])
    return processes


def descendants(root_pid: int, processes: dict[int, ProcessInfo]) -> list[ProcessInfo]:
    children: dict[int, list[ProcessInfo]] = {}
    for proc in processes.values():
        children.setdefault(proc.ppid, []).append(proc)
    result: list[ProcessInfo] = []
    stack = [(child, 1) for child in children.get(root_pid, [])]
    seen: set[int] = set()
    while stack:
        proc, depth = stack.pop()
        if proc.pid in seen:
            continue
        seen.add(proc.pid)
        proc.depth = depth
        result.append(proc)
        for child in children.get(proc.pid, []):
            stack.append((child, depth + 1))
    return result


def foreground_process(root_pid: str, fallback_command: str, processes: dict[int, ProcessInfo]) -> ProcessInfo | None:
    try:
        root = int(root_pid)
    except (TypeError, ValueError):
        root = -1
    candidates = descendants(root, processes)
    if root in processes:
        root_proc = processes[root]
        root_proc.depth = 0
        candidates.append(root_proc)
    if not candidates:
        return None

    def score(proc: ProcessInfo) -> int:
        value = proc.depth * 10
        command = proc.command
        if "+" in proc.stat:
            value += 100
        if detect.detect_agent(proc.args, fallback_command):
            value += 1000
        if command in detect.SHELL_NAMES:
            value -= 100
        if command in detect.RUNTIME_WRAPPERS:
            value += 5
        return value

    return max(candidates, key=score)


def capture_pane(pane_id: str, lines: int) -> str:
    lines = max(1, lines)
    return run_tmux(["capture-pane", "-t", pane_id, "-p", "-J", "-S", f"-{lines}"])


def filter_by_scope(panes: list[Pane], scope: str, owner: str | None) -> list[Pane]:
    session_id, window_id = owner_scope(owner)
    if scope == "all":
        return panes
    if scope == "current-window":
        return [pane for pane in panes if pane.window_id == window_id]
    # default: current-session
    return [pane for pane in panes if pane.session_id == session_id]


def notify_transition(pane: Pane, previous_state: str) -> None:
    if pane.state not in {"blocked", "done"} or pane.state == previous_state:
        return
    label = pane.agent_label or "pane"
    run_tmux(["display-message", f"tmux-agent-plugin: {label} {pane.state} in {pane.session_name}:{pane.window_index}.{pane.pane_index}"])


def collect(owner: str | None = None, *, write_cache: bool = True) -> dict[str, Any]:
    now = time.time()
    scope = tmux_option(*OPTIONS["scope"]).strip() or "current-session"
    include_non_agents = option_bool("include_non_agents")
    process_detection = option_bool("process_detection")
    output_detection = option_bool("output_detection")
    capture_lines = option_int("capture_lines")
    notify = option_bool("notify")
    report_ttl = option_int("report_ttl")

    panes = filter_by_scope(list_panes(), scope, owner)
    sidebars = sidebar_pane_ids()
    processes = parse_processes() if process_detection else {}
    previous_state = detect.load_pane_state()
    next_state: dict[str, Any] = {}
    output_panes: list[Pane] = []

    for pane in panes:
        pane.is_sidebar = pane.pane_id in sidebars
        if pane.is_sidebar:
            continue

        foreground = foreground_process(pane.pane_pid, pane.pane_current_command, processes) if process_detection else None
        if foreground:
            pane.foreground_command = foreground.args
            pane.foreground_pid = foreground.pid
            pane.foreground_pgid = foreground.pgid
        else:
            pane.foreground_command = pane.pane_current_command

        pane.agent_label = detect.detect_agent(pane.foreground_command, pane.pane_current_command)
        report = load_report(pane.pane_id, report_ttl, now)
        if report:
            pane.explicit_report = report
            pane.agent_label = report.get("agent") or pane.agent_label

        if not pane.agent_label and not include_non_agents and not report:
            continue

        previous = previous_state.get(pane.pane_id, {}) if isinstance(previous_state, dict) else {}
        previous_status = str(previous.get("state") or "unknown")

        if report and report.get("state"):
            pane.state = str(report.get("state"))
            pane.raw_state = pane.state
            pane.state_reason = "explicit-report"
            result_record = {
                "state": pane.state,
                "raw_state": pane.raw_state,
                "reason": pane.state_reason,
                "hash": previous.get("hash", ""),
                "changed": False,
                "updated_at": now,
            }
        elif output_detection:
            captured = capture_pane(pane.pane_id, capture_lines)
            result = detect.classify_screen(
                pane.pane_id,
                captured,
                agent_label=pane.agent_label,
                is_active=pane.is_active,
                previous=previous,
                now=now,
            )
            pane.state = result.state
            pane.raw_state = result.raw_state
            pane.state_reason = result.reason
            result_record = detect.state_record(result, now=now)
        else:
            pane.state = "unknown" if not pane.agent_label else "idle"
            pane.raw_state = pane.state
            pane.state_reason = "output-detection-disabled"
            result_record = {
                "state": pane.state,
                "raw_state": pane.raw_state,
                "reason": pane.state_reason,
                "hash": previous.get("hash", ""),
                "changed": False,
                "updated_at": now,
            }

        next_state[pane.pane_id] = result_record
        if notify:
            notify_transition(pane, previous_status)
        output_panes.append(pane)

    cache_dir().mkdir(parents=True, exist_ok=True)
    detect.save_pane_state(next_state)

    data = {
        "generated_at": now,
        "scope": scope,
        "owner": owner,
        "panes": [pane.to_dict() for pane in output_panes],
    }
    if write_cache:
        tmp = state_output_file().with_suffix(f".json.{os.getpid()}.tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
        tmp.replace(state_output_file())
    return data


def print_tsv(data: dict[str, Any]) -> None:
    columns = [
        "state",
        "agent_label",
        "session_name",
        "window_index",
        "pane_index",
        "pane_id",
        "pane_current_path",
        "pane_title",
        "foreground_command",
        "state_reason",
    ]
    print(TSV_SEP.join(columns))
    for pane in data.get("panes", []):
        print(TSV_SEP.join(str(pane.get(column) or "").replace("\t", " ") for column in columns))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", help="Owner/main pane id for current-session/window scope")
    parser.add_argument("--format", choices=("json", "tsv"), default="json")
    parser.add_argument("--no-cache", action="store_true", help="Do not write state.json")
    args = parser.parse_args(argv)

    data = collect(owner=args.owner, write_cache=not args.no_cache)
    if args.format == "tsv":
        print_tsv(data)
    else:
        json.dump(data, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
