"""Self-tests for check_descriptions (L11–L14): DS-1..DS-4.

Synthetic plugin trees are built in a tempdir per test; no committed
fixtures. Every P case must produce no finding for its rule, every N case
must produce the expected rule, and edges are classified per the documented
policy in docs/test-cases.md.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_descriptions  # noqa: E402


def _fm(**pairs) -> str:
    """Render a YAML frontmatter block from scalar string pairs."""
    lines = ["---"]
    for key, value in pairs.items():
        # JSON-ish quoting keeps colons/brackets inside the scalar safe.
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'{key}: "{escaped}"')
    lines.append("---")
    return "\n".join(lines) + "\n"


class DescriptionsTest(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())
        # plugins/<name> layout so Artifact.rel resolves cleanly.
        self.plugin = self.root / "plugins" / "demo"
        (self.plugin / "commands").mkdir(parents=True)
        (self.plugin / "agents").mkdir(parents=True)
        (self.plugin / "skills").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    # ---- artifact writers ------------------------------------------------

    def _skill(self, name, **fm):
        d = self.plugin / "skills" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text(
            _fm(name=name, **fm) + f"\n# {name}\n", encoding="utf-8"
        )

    def _agent(self, name, **fm):
        body = _fm(name=name, tools="Read", model="sonnet", **fm) + f"\n# {name}\n"
        (self.plugin / "agents" / f"{name}.md").write_text(body, encoding="utf-8")

    def _command(self, name, **fm):
        body = _fm(**fm) + f"\n# {name}\n"
        (self.plugin / "commands" / f"{name}.md").write_text(body, encoding="utf-8")

    # ---- helpers ---------------------------------------------------------

    def _run(self):
        return check_descriptions.check(self.plugin)

    def _rules_for(self, name):
        return {f.rule for f in self._run() if name in f.path}

    # ---- DS-1 (L11) length cap ------------------------------------------

    def test_ds1_p_short_description_passes(self):
        self._skill("alpha", description="Use when X. " + "y" * 288)
        self.assertNotIn("descriptions.cap-1536", self._rules_for("alpha"))

    def test_ds1_n_oversized_description_fails(self):
        self._skill("alpha", description="Use when X. " + "y" * 1600)
        self.assertIn("descriptions.cap-1536", self._rules_for("alpha"))

    def test_ds1_e_exactly_1536_passes(self):
        # "Use when " (9) keeps the trigger clause; pad to exactly 1536.
        desc = "Use when " + "y" * (1536 - len("Use when "))
        self.assertEqual(len(desc), 1536)
        self._skill("alpha", description=desc)
        self.assertNotIn("descriptions.cap-1536", self._rules_for("alpha"))

    def test_ds1_e_desc_plus_when_to_use_crosses_cap_fails(self):
        # Each under the cap alone, but summed they cross it.
        self._skill(
            "alpha",
            description="Use when " + "y" * 1000,
            when_to_use="z" * 1000,
        )
        self.assertIn("descriptions.cap-1536", self._rules_for("alpha"))

    def test_ds1_agent_description_alone_over_cap_fails(self):
        self._agent("rev", description="Delegate to this agent. " + "y" * 1600)
        self.assertIn("descriptions.cap-1536", self._rules_for("rev.md"))

    # ---- DS-2 (L12) skill trigger clause --------------------------------

    def test_ds2_p_use_when_passes(self):
        self._skill(
            "alpha",
            description="Builds the CRUD endpoints. Use when adding API resources.",
        )
        self.assertNotIn("descriptions.skill.no-trigger", self._rules_for("alpha"))

    def test_ds2_n_no_trigger_fails(self):
        self._skill("alpha", description="Implements CRUD endpoints for the service.")
        self.assertIn("descriptions.skill.no-trigger", self._rules_for("alpha"))

    def test_ds2_e_when_to_use_phrase_passes(self):
        self._skill(
            "alpha",
            description="When to use this skill: adding API resources to the project.",
        )
        self.assertNotIn("descriptions.skill.no-trigger", self._rules_for("alpha"))

    # ---- DS-3 (L13) agent delegation trigger ----------------------------

    def test_ds3_p_delegate_passes(self):
        self._agent(
            "rev",
            description="Delegate to this agent when reviewing changes for quality.",
        )
        self.assertNotIn("descriptions.agent.no-trigger", self._rules_for("rev.md"))

    def test_ds3_n_no_trigger_fails(self):
        self._agent("rev", description="Code reviewer for the backend service tier.")
        self.assertIn("descriptions.agent.no-trigger", self._rules_for("rev.md"))

    def test_ds3_e_proactively_passes(self):
        self._agent(
            "rev",
            description="Proactively reviews diffs for silent failures "
            "and bad error handling.",
        )
        self.assertNotIn("descriptions.agent.no-trigger", self._rules_for("rev.md"))

    # ---- DS-4 (L14) non-empty / >= 20 chars -----------------------------

    def test_ds4_p_normal_passes(self):
        self._command(
            "run",
            description="Run the suite over a pull request branch.",
            **{"argument-hint": "[pr]"},
        )
        self.assertNotIn("descriptions.too-short", self._rules_for("run.md"))

    def test_ds4_n_single_char_fails(self):
        self._command("run", description="x", **{"argument-hint": "[pr]"})
        self.assertIn("descriptions.too-short", self._rules_for("run.md"))

    def test_ds4_e_exactly_20_chars_passes(self):
        desc = "x" * 20
        self.assertEqual(len(desc), 20)
        self._command("run", description=desc, **{"argument-hint": "[pr]"})
        self.assertNotIn("descriptions.too-short", self._rules_for("run.md"))

    def test_ds4_too_short_applies_to_agent_and_skill(self):
        self._agent("rev", description="short")
        self._skill("alpha", description="short")
        agent_rules = self._rules_for("rev.md")
        skill_rules = self._rules_for("alpha")
        self.assertIn("descriptions.too-short", agent_rules)
        self.assertIn("descriptions.too-short", skill_rules)

    # ---- cross-cutting: clean tree yields nothing -----------------------

    def test_clean_tree_has_no_findings(self):
        self._skill(
            "alpha", description="Builds CRUD endpoints. Use when adding API resources."
        )
        self._agent(
            "rev",
            description="Delegate to this agent when reviewing diffs for quality.",
        )
        self._command(
            "run",
            description="Run the quality suite over a PR branch.",
            **{"argument-hint": "[pr]"},
        )
        self.assertEqual(self._run(), [])


if __name__ == "__main__":
    unittest.main()
