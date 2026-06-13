"""Self-tests for check_metaguides (L30, MG-1).

Builds synthetic meta-guides (loose ``skills/*.md``) under a tempdir — no
committed fixtures — and verifies the real shipped plugin is clean for L30.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lint"))

import check_metaguides  # noqa: E402

REPO_ROOT = HERE.parent.parent.parent
REAL_PLUGIN = REPO_ROOT / "plugins" / "php-backend-sdlc"

# The verbatim BMAD triage clause as shipped in SKILL-DECISION-GUIDE.md.
TRIAGE_CLAUSE = (
    "The gate contract is: **every skill verdict recorded, no silent skips**."
)


class MetaguideCase(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.root = self.tmp / "plugins" / "p"
        (self.root / "skills").mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_metaguide(self, name, text):
        (self.root / "skills" / f"{name}.md").write_text(text, encoding="utf-8")

    def _write_skill(self, name, text):
        d = self.root / "skills" / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "SKILL.md").write_text(text, encoding="utf-8")

    def _findings(self, check_id=None):
        fs = check_metaguides.check(self.root)
        if check_id is not None:
            fs = [f for f in fs if f.check == check_id]
        return fs

    # --- MG-1 (L30) decision-guide triage clause --------------------------

    def test_mg1_decision_guide_without_clause_fails(self):
        # A DECISION meta-guide lacking the triage contract -> L30 fires.
        self._write_metaguide(
            "MY-DECISION-GUIDE",
            "# My Decision Guide\n\nPick the skill that fits your task.\n",
        )
        fs = self._findings("L30")
        self.assertEqual(len(fs), 1)
        self.assertEqual(fs[0].rule, "metaguide.decision-guide.triage")
        self.assertEqual(fs[0].severity, "S3")

    def test_mg1_decision_guide_with_clause_passes(self):
        # The verbatim shipped clause satisfies the contract -> no finding.
        self._write_metaguide(
            "MY-DECISION-GUIDE",
            f"# My Decision Guide\n\n{TRIAGE_CLAUSE}\n",
        )
        self.assertEqual(self._findings("L30"), [])

    def test_mg1_decision_guide_no_silent_skip_phrasing_passes(self):
        # A reworded "no silent skip" phrasing still satisfies the tolerant rule.
        self._write_metaguide(
            "X-DECISION.md".replace(".md", ""),
            "# X\n\nRecord a verdict per skill with no silent skip.\n",
        )
        self.assertEqual(self._findings("L30"), [])

    def test_mg1_non_decision_metaguide_not_checked(self):
        # A meta-guide whose filename has no DECISION token is exempt.
        self._write_metaguide(
            "AI-AGENT-GUIDE",
            "# AI Agent Guide\n\nNo triage clause here at all.\n",
        )
        self.assertEqual(self._findings("L30"), [])

    def test_mg1_decision_in_subdir_skill_not_checked(self):
        # A SKILL.md inside skills/<name>/ is a skill (kind 'skill'), not a
        # meta-guide — even if the dir name contains DECISION it is not checked.
        self._write_skill(
            "decision-helper",
            "---\nname: decision-helper\ndescription: d\n---\n\nbody\n",
        )
        self.assertEqual(self._findings("L30"), [])

    def test_mg1_case_insensitive_filename_match(self):
        # Lowercase "decision" in the filename is matched too.
        self._write_metaguide(
            "team-decision-notes",
            "# Notes\n\nNo triage clause.\n",
        )
        fs = self._findings("L30")
        self.assertEqual(len(fs), 1)

    # --- real shipped plugin is clean for L30 -----------------------------

    def test_real_plugin_clean_for_metaguides(self):
        self.assertTrue(REAL_PLUGIN.is_dir(), f"missing real plugin at {REAL_PLUGIN}")
        fs = check_metaguides.check(REAL_PLUGIN)
        l30 = [f for f in fs if f.check == "L30"]
        self.assertEqual(
            l30,
            [],
            "shipped plugin must be clean for L30; got: "
            + "; ".join(f.render() for f in l30),
        )


if __name__ == "__main__":
    unittest.main()
