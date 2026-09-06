"""Detect shared safety-contract drift without removing standalone prompt context."""

from __future__ import annotations

import json
import pathlib
import re
import unittest

PLUGIN = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = {
    "command": {
        "profile validation": "validate-profile --repo .",
        "attempt limit": "MAX_ITERATIONS=5",
        "preflight-only fallback": (
            "No fallback or replay is allowed after the invocation starts, "
            "times out or has uncertain effects."
        ),
        "terminal breaker": (
            "Never automatically reset counters or a tripped Ralph circuit breaker."
        ),
        "required gate": "Only PASSED satisfies a required gate.",
    },
    "skill": {
        "profile validation": "validate-profile --repo .",
        "status vocabulary": "Return PASSED, FAILED, SKIPPED or BLOCKED",
        "attempt limit": "persisted count is already 5, stop with FAILED",
        "terminal breaker": "never reset or clear it to retry.",
        "authorization scope": (
            "Reuse authorization only for its exact action, target, "
            "environment and resource scope;"
        ),
    },
    "agent": {
        "attempt limit": "MAX_ITERATIONS=5",
        "missing resume counter": (
            "resuming without its prior count, report BLOCKED instead of assuming zero."
        ),
        "terminal breaker": "Re-entry preserves both count and breaker state.",
        "required gate": "Neither BLOCKED nor SKIPPED satisfies a required check.",
        "quality floor": (
            "Never suppress findings, add baseline exclusions, lower thresholds,"
        ),
    },
}


def contract_violations(text: str, kind: str) -> list[str]:
    normalized = " ".join(text.split())
    return [
        name for name, required in CONTRACTS[kind].items() if required not in normalized
    ]


class PromptContractTests(unittest.TestCase):
    def test_each_standalone_prompt_retains_shared_safety_contract(self):
        groups = {
            "command": (list((PLUGIN / "commands").glob("*.md")), 8),
            "agent": (list((PLUGIN / "agents").glob("*.md")), 7),
            "skill": (list((PLUGIN / "skills").glob("*/SKILL.md")), 14),
        }
        for kind, (paths, expected) in groups.items():
            self.assertEqual(len(paths), expected)
            for path in paths:
                with self.subTest(kind=kind, path=path.relative_to(PLUGIN)):
                    self.assertEqual(contract_violations(path.read_text(), kind), [])

    def test_both_routing_inventories_match_every_skill_description(self):
        descriptions = {}
        for path in (PLUGIN / "skills").glob("*/SKILL.md"):
            line = next(
                line
                for line in path.read_text().splitlines()
                if line.startswith("description:")
            )
            descriptions[path.parent.name] = json.loads(line.split(":", 1)[1].strip())
        for name in ("AI-AGENT-GUIDE.md", "SKILL-DECISION-GUIDE.md"):
            text = (PLUGIN / "skills" / name).read_text()
            entries = re.findall(
                r"^- \[([^]]+)\]\([^)]*/SKILL\.md\) — (.+)$", text, re.M
            )
            with self.subTest(guide=name):
                self.assertEqual(len(entries), len(descriptions))
                self.assertEqual(dict(entries), descriptions)

    def test_counter_and_status_drift_is_detected(self):
        command = (PLUGIN / "commands/do-sdlc.md").read_text()
        self.assertIn(
            "attempt limit",
            contract_violations(
                command.replace("MAX_ITERATIONS=5", "MAX_ITERATIONS=6"), "command"
            ),
        )
        skill = (PLUGIN / "skills/terraform-terraspace/SKILL.md").read_text()
        self.assertIn(
            "status vocabulary",
            contract_violations(
                skill.replace(
                    "Return PASSED, FAILED, SKIPPED or BLOCKED", "Return PASS or FAIL"
                ),
                "skill",
            ),
        )


if __name__ == "__main__":
    unittest.main()
