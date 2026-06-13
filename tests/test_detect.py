#!/usr/bin/env python3

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import detect  # noqa: E402


class AgentDetectionTests(unittest.TestCase):
    def test_exact_agent_commands(self):
        cases = {
            "pi": "pi",
            "claude": "claude",
            "claude-code": "claude",
            "codex": "codex",
            "gemini": "gemini",
            "opencode": "opencode",
            "cursor-agent": "cursor-agent",
            "ghcs": "copilot",
            "amp": "amp",
            "droid": "droid",
            "grok": "grok",
            "kimi": "kimi",
            "kiro": "kiro",
            "kilo": "kilo",
            "qodercli": "qodercli",
            "hermes": "hermes",
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(detect.detect_agent(command), expected)

    def test_runtime_wrapped_agents(self):
        cases = {
            "node /usr/local/bin/pi-coding-agent": "pi",
            "npx @anthropic-ai/claude-code": "claude",
            "npm exec @openai/codex": "codex",
            "bunx @google/gemini-cli": "gemini",
            "python -m opencode": "opencode",
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(detect.detect_agent(command), expected)

    def test_github_copilot_extension(self):
        self.assertEqual(detect.detect_agent("gh copilot suggest 'git status'"), "copilot")

    def test_fallback_current_command(self):
        self.assertEqual(detect.detect_agent("/bin/zsh", "codex"), "codex")

    def test_unknown_command(self):
        self.assertIsNone(detect.detect_agent("vim README.md"))


if __name__ == "__main__":
    unittest.main()
