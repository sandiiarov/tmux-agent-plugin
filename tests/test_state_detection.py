#!/usr/bin/env python3

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import detect  # noqa: E402


def fixture(name: str) -> str:
    return (ROOT / "fixtures" / "detect" / name).read_text(encoding="utf-8")


class StateDetectionTests(unittest.TestCase):
    def test_strips_ansi_sequences(self):
        self.assertEqual(detect.normalize_screen("\x1b[31mReady\x1b[0m\r\n"), "Ready")

    def test_blocked_prompt_fixture(self):
        state, reason = detect.raw_state_from_text(fixture("blocked.txt"), changed=False, agent_label="claude")
        self.assertEqual(state, "blocked")
        self.assertIn("blocked", reason)

    def test_working_spinner_fixture(self):
        state, _ = detect.raw_state_from_text(fixture("working.txt"), changed=False, agent_label="pi")
        self.assertEqual(state, "working")

    def test_idle_fixture(self):
        state, _ = detect.raw_state_from_text(fixture("idle.txt"), changed=False, agent_label="gemini")
        self.assertEqual(state, "idle")

    def test_output_change_marks_known_agent_working(self):
        result = detect.classify_screen(
            "%1",
            "no obvious prompt yet",
            agent_label="codex",
            is_active=True,
            previous={"state": "idle", "hash": "different"},
        )
        self.assertEqual(result.state, "working")
        self.assertEqual(result.reason, "output-changed")

    def test_done_transition_when_unfocused(self):
        previous_hash = detect.screen_hash("running command")
        result = detect.classify_screen(
            "%1",
            "Ready for your message",
            agent_label="gemini",
            is_active=False,
            previous={"state": "working", "hash": previous_hash},
        )
        self.assertEqual(result.state, "done")

    def test_focus_clears_previous_done(self):
        result = detect.classify_screen(
            "%1",
            "Ready for your message",
            agent_label="opencode",
            is_active=True,
            previous={"state": "done", "hash": detect.screen_hash("Ready for your message")},
        )
        self.assertEqual(result.state, "idle")


if __name__ == "__main__":
    unittest.main()
