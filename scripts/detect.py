#!/usr/bin/env python3
"""Clean-room agent identity and screen-state detection helpers.

The process-name detection here intentionally uses broad public CLI names and
package names, not Herdr manifests.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

ANSI_RE = re.compile(
    r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))"
)
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
WHITESPACE_RE = re.compile(r"[ \t\r\f\v]+")

AGENT_ALIASES: dict[str, set[str]] = {
    "pi": {"pi", "pi-coding-agent"},
    "claude": {"claude", "claude-code", "claude_code", "@anthropic-ai/claude-code"},
    "codex": {"codex", "openai-codex", "@openai/codex"},
    "gemini": {"gemini", "gemini-cli", "@google/gemini-cli"},
    "opencode": {"opencode", "opencode-ai"},
    "cursor-agent": {"cursor-agent", "cursoragent"},
    "copilot": {"copilot", "ghcs", "github-copilot"},
    "amp": {"amp"},
    "droid": {"droid"},
    "grok": {"grok"},
    "kimi": {"kimi"},
    "kiro": {"kiro"},
    "kilo": {"kilo"},
    "qodercli": {"qodercli", "qoder"},
    "hermes": {"hermes"},
}

ALIAS_TO_AGENT = {alias: label for label, aliases in AGENT_ALIASES.items() for alias in aliases}

RUNTIME_WRAPPERS = {
    "node",
    "nodejs",
    "npx",
    "npm",
    "pnpm",
    "pnpx",
    "yarn",
    "bun",
    "bunx",
    "deno",
    "python",
    "python3",
    "pipx",
    "uv",
    "uvx",
    "bash",
    "sh",
    "zsh",
    "fish",
    "env",
}

SHELL_NAMES = {"bash", "sh", "zsh", "fish", "ksh", "dash", "tcsh", "csh", "login"}

BLOCKED_PATTERNS = [
    re.compile(pattern, re.I | re.M)
    for pattern in [
        r"\b(do you want to|would you like to)\b[^\n]{0,120}\b(continue|proceed|run|apply|approve|allow)\b",
        r"\b(approve|approval|permission|authorize|confirm|confirmation|required)\b[^\n]{0,120}\b(yes/no|y/n|enter|return|proceed|continue|allow)\b",
        r"\b(yes/no|y/n|\[y/N\]|\[Y/n\])\b",
        r"\bpress\s+(enter|return)\s+to\s+(continue|confirm|proceed|send)",
        r"\bwaiting\s+for\s+(approval|confirmation|input|permission)",
        r"\baction\s+required\b",
        r"\brequires?\s+your\s+(approval|confirmation|permission)",
        r"\benter\s+to\s+confirm\b",
    ]
]

WORKING_PATTERNS = [
    re.compile(pattern, re.I | re.M)
    for pattern in [
        r"(^|\n)\s*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒⣾⣽⣻⢿⡿⣟⣯⣷|/\\-]\s+\w+",
        r"\b(thinking|working|running|analyzing|analysing|generating|searching|planning|editing|writing|reading|executing|compiling)\b",
        r"\b(calling|using|running)\s+(tool|command)",
        r"\b(tool use|tool call|in progress|processing|streaming)\b",
    ]
]

IDLE_PATTERNS = [
    re.compile(pattern, re.I | re.M)
    for pattern in [
        r"\b(ready|idle|waiting for your message|what would you like|ask me anything)\b",
        r"\b(enter|type|send)\s+(your\s+)?(prompt|message|request)\b",
        r"(^|\n)\s*[╰└].*[>$] ?$",
        r"(^|\n).*\b(prompt|message|input)\b.*[>$❯]\s*$",
    ]
]


def _agent_patterns() -> dict[str, dict[str, list[re.Pattern[str]]]]:
    patterns: dict[str, dict[str, list[re.Pattern[str]]]] = {}
    for label in AGENT_ALIASES:
        name = re.escape(label).replace("\\-", "[-_ ]?")
        patterns[label] = {
            "blocked": [
                re.compile(rf"\b{name}\b[^\n]{{0,120}}\b(needs?|waiting for|requires?)\b[^\n]{{0,80}}\b(approval|permission|confirmation|input)\b", re.I | re.M),
            ],
            "working": [
                re.compile(rf"\b{name}\b[^\n]{{0,120}}\b(thinking|working|running|analyzing|analysing|generating)\b", re.I | re.M),
            ],
            "idle": [
                re.compile(rf"\b{name}\b[^\n]{{0,120}}\b(ready|idle|waiting for (your )?(prompt|message|input))\b", re.I | re.M),
            ],
        }
    return patterns


AGENT_SPECIFIC_PATTERNS = _agent_patterns()


@dataclass(slots=True)
class DetectionResult:
    state: str
    reason: str = ""
    raw_state: str = ""
    changed: bool = False
    content_hash: str = ""


def split_command(command: str | None) -> list[str]:
    if not command:
        return []
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def normalize_token(token: str) -> str:
    token = token.strip().strip("'\"")
    if not token:
        return ""
    # Keep scoped package names intact while still normalizing path-like tokens.
    lowered = token.lower()
    if lowered.startswith("@") and "/" in lowered:
        return lowered
    base = os.path.basename(lowered)
    for suffix in (".exe", ".cmd", ".bat", ".js", ".mjs", ".cjs", ".py"):
        if base.endswith(suffix):
            base = base[: -len(suffix)]
    return base


def command_tokens(argv: str | Iterable[str] | None, fallback_command: str | None = None) -> list[str]:
    tokens: list[str] = []
    if isinstance(argv, str):
        tokens.extend(split_command(argv))
    elif argv:
        tokens.extend(str(item) for item in argv)
    if fallback_command:
        tokens.extend(split_command(fallback_command))
    return tokens


def detect_agent(argv: str | Iterable[str] | None, fallback_command: str | None = None) -> str | None:
    """Return a supported agent label from process argv/current-command evidence."""

    tokens = command_tokens(argv, fallback_command)
    normalized = [normalize_token(token) for token in tokens if normalize_token(token)]
    if not normalized:
        return None

    # Special case GitHub Copilot CLI: `gh copilot ...`.
    for index, token in enumerate(normalized[:-1]):
        if token == "gh" and normalized[index + 1] == "copilot":
            return "copilot"

    # Prefer exact CLI/package names.
    for token in normalized:
        if token in ALIAS_TO_AGENT:
            return ALIAS_TO_AGENT[token]

    # Then inspect path/package substrings for runtime wrappers such as node/npx.
    lowered_command = " ".join(tokens).lower()
    substring_markers = [
        ("pi", "pi-coding-agent"),
        ("claude", "claude-code"),
        ("claude", "@anthropic-ai/claude-code"),
        ("codex", "@openai/codex"),
        ("gemini", "@google/gemini-cli"),
        ("opencode", "opencode"),
        ("cursor-agent", "cursor-agent"),
    ]
    for label, marker in substring_markers:
        if marker in lowered_command:
            return label

    return None


def is_shell_command(argv: str | Iterable[str] | None) -> bool:
    tokens = command_tokens(argv)
    if not tokens:
        return False
    return normalize_token(tokens[0]) in SHELL_NAMES


def strip_ansi(text: str) -> str:
    text = ANSI_RE.sub("", text)
    text = CONTROL_RE.sub("", text)
    return text


def normalize_screen(text: str) -> str:
    text = strip_ansi(text).replace("\r", "\n")
    lines = [WHITESPACE_RE.sub(" ", line).rstrip() for line in text.splitlines()]
    return "\n".join(lines).strip()


def screen_hash(text: str) -> str:
    return hashlib.sha256(normalize_screen(text).encode("utf-8", "replace")).hexdigest()


def raw_state_from_text(text: str, changed: bool, agent_label: str | None = None) -> tuple[str, str]:
    normalized = normalize_screen(text)
    if not normalized:
        return "unknown", "empty-capture"
    for pattern in BLOCKED_PATTERNS:
        if pattern.search(normalized):
            return "blocked", f"blocked-pattern:{pattern.pattern}"
    if agent_label in AGENT_SPECIFIC_PATTERNS:
        for pattern in AGENT_SPECIFIC_PATTERNS[agent_label]["blocked"]:
            if pattern.search(normalized):
                return "blocked", f"agent-blocked-pattern:{agent_label}:{pattern.pattern}"
    for pattern in WORKING_PATTERNS:
        if pattern.search(normalized):
            return "working", f"working-pattern:{pattern.pattern}"
    if agent_label in AGENT_SPECIFIC_PATTERNS:
        for pattern in AGENT_SPECIFIC_PATTERNS[agent_label]["working"]:
            if pattern.search(normalized):
                return "working", f"agent-working-pattern:{agent_label}:{pattern.pattern}"
    tail = "\n".join(normalized.splitlines()[-6:])
    for pattern in IDLE_PATTERNS:
        if pattern.search(tail):
            return "idle", f"idle-pattern:{pattern.pattern}"
    if agent_label in AGENT_SPECIFIC_PATTERNS:
        for pattern in AGENT_SPECIFIC_PATTERNS[agent_label]["idle"]:
            if pattern.search(tail):
                return "idle", f"agent-idle-pattern:{agent_label}:{pattern.pattern}"
    if changed and agent_label:
        return "working", "output-changed"
    if agent_label:
        return "idle", "known-agent-no-active-evidence"
    return "unknown", "no-agent-or-pattern"


def cache_dir() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tmux-agent-plugin"


def pane_state_file() -> Path:
    return cache_dir() / "pane_state.json"


def load_pane_state(path: Path | None = None) -> dict[str, Any]:
    path = path or pane_state_file()
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        if isinstance(data, dict):
            return data
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, OSError):
        return {}
    return {}


def save_pane_state(state: dict[str, Any], path: Path | None = None) -> None:
    path = path or pane_state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
    tmp.replace(path)


def classify_screen(
    pane_id: str,
    text: str,
    *,
    agent_label: str | None,
    is_active: bool,
    previous: dict[str, Any] | None = None,
    now: float | None = None,
) -> DetectionResult:
    """Classify pane output and derive done/idle transitions from previous state."""

    now = now or time.time()
    previous = previous or {}
    digest = screen_hash(text)
    changed = bool(previous.get("hash") and previous.get("hash") != digest)
    raw_state, reason = raw_state_from_text(text, changed=changed, agent_label=agent_label)
    prev_state = str(previous.get("state") or "unknown")
    state = raw_state

    if raw_state == "idle" and prev_state in {"working", "blocked"} and not is_active:
        state = "done"
        reason = f"transition:{prev_state}->idle-unfocused"
    elif raw_state == "idle" and is_active:
        state = "idle"
    elif prev_state == "done" and not is_active and raw_state == "idle":
        state = "done"
        reason = "previous-done-unacknowledged"

    return DetectionResult(
        state=state,
        raw_state=raw_state,
        reason=reason,
        changed=changed,
        content_hash=digest,
    )


def state_record(result: DetectionResult, now: float | None = None) -> dict[str, Any]:
    return {
        "state": result.state,
        "raw_state": result.raw_state,
        "reason": result.reason,
        "hash": result.content_hash,
        "changed": result.changed,
        "updated_at": now or time.time(),
    }
